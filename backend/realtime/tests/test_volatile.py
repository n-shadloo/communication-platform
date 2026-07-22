"""The headline volatile exit test (§A6, §A11.5): signals relay between live sockets and
leave **zero** trace — no new row in any table, no signal/presence table to write to."""
import uuid

import pytest

from .conftest import bearer, connect_ok, mint_access, probe, table_counts, ws

pytestmark = pytest.mark.django_db(transaction=True)


async def test_signal_relays_and_writes_zero_rows_anywhere(active_user, device,
                                                           peer, peer_device):
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    before = await table_counts()

    await comm_a.send_json_to({"type": "signal", "to_device": str(peer_device.id),
                               "blob": "ciphertext-opaque-to-the-server"})

    frame = await comm_b.receive_json_from(timeout=2)
    # The relayed frame carries type and blob ONLY: no to_device, and structurally no
    # sender — sealed sender on the wire, not just at rest.
    assert frame == {"type": "signal", "blob": "ciphertext-opaque-to-the-server"}

    after = await table_counts()
    assert after == before, "a volatile signal changed a table's row count"
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_there_is_no_signal_or_presence_table_at_all(db):
    """§A1: the server has no schema for volatile traffic — nothing to persist into."""
    labels = list(await table_counts())
    assert not [l for l in labels
                if "signal" in l.lower() or "presence" in l.lower() or
                "typing" in l.lower() or "receipt" in l.lower()]


async def test_signal_to_an_offline_target_is_dropped_silently(active_user, device):
    """No error frame, nothing stored, and the sender's socket stays healthy."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    before = await table_counts()

    await comm.send_json_to({"type": "signal", "to_device": str(uuid.uuid4()),
                             "blob": "x"})

    await probe(comm, device.id)  # the drop didn't kill the consumer
    assert await comm.receive_nothing(timeout=0.2)
    assert await table_counts() == before
    await comm.disconnect()


async def test_oversized_signal_blob_is_dropped(active_user, device, peer,
                                                peer_device, settings):
    settings.SIGNAL_MAX = 64
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))

    await comm_a.send_json_to({"type": "signal", "to_device": str(peer_device.id),
                               "blob": "b" * 65})

    assert await comm_b.receive_nothing(timeout=0.3)
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_malformed_signal_frames_are_dropped(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_json_to({"type": "signal", "to_device": "not-a-uuid", "blob": "x"})
    await comm.send_json_to({"type": "signal", "to_device": str(uuid.uuid4())})
    await comm.send_json_to({"type": "signal", "blob": "x"})
    await comm.send_json_to({"type": "signal", "to_device": {"a": 1}, "blob": "x"})

    await probe(comm, device.id)
    await comm.disconnect()


async def test_alternate_uuid_spellings_still_reach_a_live_target(active_user, device,
                                                                  peer, peer_device):
    """uuid.UUID accepts braces/urn/uppercase; the group name must use the normalized
    form or a live target silently misses the signal (§A6 'forwards to any live socket')."""
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))

    for spelling in ("{%s}" % peer_device.id, str(peer_device.id).upper(),
                     f"urn:uuid:{peer_device.id}"):
        await comm_a.send_json_to({"type": "signal", "to_device": spelling,
                                   "blob": "s"})
        assert await comm_b.receive_json_from(timeout=2) == {"type": "signal",
                                                             "blob": "s"}
    await comm_a.disconnect()
    await comm_b.disconnect()
