"""Durable path: a live push mirrors the queue row; an ack deletes it. The row, not
the frame, is the source of truth. The send route enqueues, the socket optimizes."""

import pytest

from api.orm import run_unit
from core.buckets import ENVELOPE_BUCKETS
from messaging.models import QueuedEnvelope

from .conftest import (
    bearer,
    connect_ok,
    envelope_blob,
    http_request,
    mint_access,
    probe,
)

pytestmark = pytest.mark.django_db(transaction=True)

SEND_URL = "/api/v1/envelopes"


async def send(access, device_id, blob):
    return await http_request(
        "POST",
        SEND_URL,
        access,
        json={"messages": [{"device_id": str(device_id), "blob": blob}]},
    )


async def queue_count(device_id):
    return await run_unit(
        QueuedEnvelope.objects.filter(recipient_device_id=device_id).count
    )


async def test_enqueued_envelope_is_pushed_acked_and_deleted(
    active_user, device, peer, peer_device
):
    """The headline durable exit test: enqueue via the messaging service, receive the
    `envelope` frame, ack it, and the queue row is gone."""
    comm = await connect_ok(bearer(await mint_access(peer, peer_device)))
    blob = envelope_blob(b"d")

    resp = await send(await mint_access(active_user, device), peer_device.id, blob)
    assert resp.status_code == 202 and resp.json()["accepted"] == 1

    frame = await comm.receive_json_from(timeout=2)
    row = await run_unit(QueuedEnvelope.objects.get, recipient_device_id=peer_device.id)
    assert frame == {"type": "envelope", "id": str(row.id), "seq": 1, "blob": blob}

    await comm.send_json_to({"type": "ack", "ids": [frame["id"]]})
    await probe(comm, peer_device.id)  # barrier: the ack has been fully processed
    assert await queue_count(peer_device.id) == 0
    await comm.disconnect()


async def test_ack_only_touches_the_calling_devices_rows(
    active_user, device, peer, peer_device
):
    """Device A acking device B's envelope id must delete nothing: the socket's
    device identity scopes the delete exactly like REST's ack."""
    row = await run_unit(
        QueuedEnvelope.objects.create,
        recipient_device_id=peer_device.id,
        seq=1,
        blob=b"e" * min(ENVELOPE_BUCKETS),
    )
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_json_to({"type": "ack", "ids": [str(row.id)]})
    await probe(comm, device.id)

    assert await queue_count(peer_device.id) == 1
    await comm.disconnect()


async def test_malformed_ack_ids_are_dropped_without_killing_the_socket(
    active_user, device
):
    """Non-UUID ids never reach the pk column (the WS twin of the ack route's
    guard); the socket survives and later frames still work."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_json_to({"type": "ack", "ids": ["not-a-uuid", {"nested": 1}]})
    await comm.send_json_to({"type": "ack", "ids": "not-a-list"})
    await comm.send_json_to({"type": "ack", "ids": [str(n) for n in range(201)]})

    await probe(comm, device.id)  # still alive, nothing crashed
    await comm.disconnect()
