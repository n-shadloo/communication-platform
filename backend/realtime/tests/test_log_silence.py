"""Nothing on the realtime path logs an identifier, a target, or a payload.

Like the messaging/devices suites, capture must bypass the configured ScrubFilter to
assert the code never emits an identifier in the first place. caplog is not enough:
the filter mutates records in place, so the console handler launders the message
before caplog's later-attached handler stores it, and a leak would grade its own
homework. So, like assertLogs, all root handlers are swapped out for the capture
window."""
import logging
import uuid
from contextlib import contextmanager

import pytest

from .conftest import bearer, connect_ok, envelope_blob, expect_close, mint_access, ws

pytestmark = pytest.mark.django_db(transaction=True)


class _RawCapture(logging.Handler):
    def __init__(self):
        super().__init__(level=logging.DEBUG)
        self.lines = []

    def emit(self, record):
        self.lines.append(record.getMessage())


@contextmanager
def raw_root_capture():
    root = logging.getLogger()
    handler = _RawCapture()
    old_handlers, old_level = root.handlers[:], root.level
    root.handlers[:] = [handler]
    root.setLevel(logging.DEBUG)
    try:
        yield handler.lines
    finally:
        root.handlers[:] = old_handlers
        root.setLevel(old_level)


async def test_every_socket_scenario_emits_no_identifier_or_payload(
        active_user, device, peer, peer_device):
    access_a = await mint_access(active_user, device)
    access_b = await mint_access(peer, peer_device)
    signal_blob = "volatile-ciphertext-blob"
    push_blob = envelope_blob(b"l")
    offline_target = str(uuid.uuid4())

    with raw_root_capture() as lines:
        logging.getLogger("test.canary").debug("canary")

        # Header-auth connect (A), frame-auth connect (B).
        comm_a = await connect_ok(bearer(access_a))
        comm_b = await connect_ok([])
        await comm_b.send_json_to({"type": "auth", "access": access_b})

        # Durable push and ack, including a malformed ack.
        from channels.layers import get_channel_layer
        await get_channel_layer().group_send(
            f"dev.{device.id}", {"type": "envelope.push", "id": str(uuid.uuid4()),
                                 "seq": 1, "blob": push_blob})
        frame = await comm_a.receive_json_from(timeout=2)
        await comm_a.send_json_to({"type": "ack", "ids": [frame["id"]]})
        await comm_a.send_json_to({"type": "ack", "ids": [str(device.id) + "-corrupt"]})

        # Volatile signals: delivered, braced spelling, offline target, malformed.
        await comm_a.send_json_to({"type": "signal", "to_device": str(peer_device.id),
                                   "blob": signal_blob})
        assert await comm_b.receive_json_from(timeout=2) == {"type": "signal",
                                                             "blob": signal_blob}
        await comm_a.send_json_to({"type": "signal", "to_device": offline_target,
                                   "blob": signal_blob})
        await comm_a.send_json_to({"type": "signal", "to_device": "not-a-uuid",
                                   "blob": signal_blob})

        # Presence subscribe + the offline emit on disconnect.
        await comm_a.send_json_to({"type": "subscribe_presence",
                                   "device_ids": [str(peer_device.id)]})
        await comm_b.receive_json_from(timeout=2)   # A online
        await comm_a.disconnect()
        await comm_b.receive_json_from(timeout=2)   # A offline
        await comm_b.disconnect()

        # Rejected handshakes: bad token, unlisted origin, and a
        # protocol-violation close.
        bad = ws(bearer("garbage-token"))
        assert (await bad.connect(timeout=2))[0] is False
        rejected = ws([(b"origin", b"https://evil.example")])
        assert (await rejected.connect(timeout=2))[1] == 4403
        await rejected.disconnect()
        binary = await connect_ok(bearer(access_a))
        await binary.send_to(bytes_data=b"\x00")
        await expect_close(binary, 4008)
        await binary.disconnect()

    assert any("canary" in line for line in lines), "log capture was not live"
    forbidden = {
        "sender device id": str(device.id),
        "target device id": str(peer_device.id),
        "offline to_device": offline_target,
        "signal blob": signal_blob,
        "envelope blob": push_blob,
        "access token A": access_a,
        "access token B": access_b,
        "user id": str(active_user.id),
        "peer user id": str(peer.id),
    }
    for line in lines:
        for label, secret in forbidden.items():
            assert secret not in line, f"{label} leaked into a log line: {line[:80]}"
