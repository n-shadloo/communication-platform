"""Room real-time: live membership and ephemeral room text ride the socket and
non-persistent Redis, never the database and never the logs.

The suite runs on the in-memory channel layer (conftest), so anything that survived
a test could only have done so through a persistent store, which the zero-row and
Redis-key assertions check directly.
"""

import logging
import uuid

import pytest
from channels.db import database_sync_to_async

from core.buckets import NAME_BUCKETS
from voicerooms.models import Room
from voicerooms.presence import room_live_count

from .conftest import bearer, connect_ok, mint_access, probe, table_counts
from .test_log_silence import raw_root_capture

pytestmark = pytest.mark.django_db(transaction=True)


@database_sync_to_async
def make_room():
    return Room.objects.create(name_blob=b"r" * min(NAME_BUCKETS))


@database_sync_to_async
def live_count(room_id):
    return room_live_count(room_id)


async def subscribe_ok(comm, room_id):
    """Subscribe and consume the socket's own join echo (it is in the group when the
    presence broadcast fires), so later receives are deterministic."""
    await comm.send_json_to({"type": "room_subscribe", "room_id": room_id})
    frame = await comm.receive_json_from(timeout=2)
    assert frame == {
        "type": "room_presence",
        "room_id": room_id,
        "device_id": frame["device_id"],
        "state": "join",
    }
    return frame["device_id"]


async def test_room_signal_relays_to_all_subscribers_and_writes_zero_rows(
    active_user, device, peer, peer_device
):
    """The ephemeral-relay exit test: both devices receive room.relay; no table grows."""
    room = await make_room()
    room_id = str(room.id)
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))

    await subscribe_ok(comm_a, room_id)
    await subscribe_ok(comm_b, room_id)
    # A also sees B's join (already in the group by then).
    assert (await comm_a.receive_json_from(timeout=2))["state"] == "join"

    before = await table_counts()
    await comm_a.send_json_to(
        {
            "type": "room_signal",
            "room_id": room_id,
            "blob": "room-ciphertext-opaque-to-the-server",
        }
    )

    # Both subscribers, sender included, get the relay. The frame carries type, room
    # and blob only: no device id, structurally no sender.
    expected = {
        "type": "room_signal",
        "room_id": room_id,
        "blob": "room-ciphertext-opaque-to-the-server",
    }
    assert await comm_a.receive_json_from(timeout=2) == expected
    assert await comm_b.receive_json_from(timeout=2) == expected

    assert await table_counts() == before, "ephemeral room traffic changed a table"
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_live_count_follows_join_leave_and_disconnect(
    active_user, device, peer, peer_device
):
    room = await make_room()
    room_id = str(room.id)
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))

    assert await live_count(room_id) == 0
    await subscribe_ok(comm_a, room_id)
    assert await live_count(room_id) == 1
    await subscribe_ok(comm_b, room_id)
    assert (await comm_a.receive_json_from(timeout=2))["state"] == "join"
    assert await live_count(room_id) == 2

    # Explicit leave: the peer is told, the count drops, nothing is written.
    before = await table_counts()
    await comm_a.send_json_to({"type": "room_leave", "room_id": room_id})
    frame = await comm_b.receive_json_from(timeout=2)
    assert frame == {
        "type": "room_presence",
        "room_id": room_id,
        "device_id": str(device.id),
        "state": "leave",
    }
    assert await live_count(room_id) == 1

    # Disconnect leaves every room without an explicit room_leave frame.
    await comm_b.disconnect()
    assert await live_count(room_id) == 0
    assert await table_counts() == before, "presence traffic changed a table"
    await comm_a.disconnect()


async def test_subscribing_to_a_nonexistent_room_is_ignored(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    ghost = str(uuid.uuid4())

    await comm.send_json_to({"type": "room_subscribe", "room_id": ghost})
    await probe(comm, device.id)  # consumer alive, no join echo came
    assert await live_count(ghost) == 0

    # And the socket did not silently join the group: a signal to it goes nowhere.
    await comm.send_json_to({"type": "room_signal", "room_id": ghost, "blob": "x"})
    assert await comm.receive_nothing(timeout=0.2)
    await comm.disconnect()


async def test_malformed_room_subscribe_is_dropped_not_fatal(active_user, device):
    """Raw client input must never reach the UUID pk lookup: unparsed, each of these
    raises ValidationError inside the consumer, killing the socket and embedding the
    value in an error-log traceback."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    for room_id in ("not-a-uuid", {"a": 1}, 7, "", None):
        await comm.send_json_to({"type": "room_subscribe", "room_id": room_id})
    await comm.send_json_to({"type": "room_subscribe"})

    await probe(comm, device.id)
    await comm.disconnect()


async def test_room_signal_from_a_non_subscriber_is_dropped(
    active_user, device, peer, peer_device
):
    """Knowing a room id is not enough to relay into it over this socket; the sender
    must have subscribed (joined the live session) first."""
    room = await make_room()
    room_id = str(room.id)
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    await subscribe_ok(comm_a, room_id)

    await comm_b.send_json_to({"type": "room_signal", "room_id": room_id, "blob": "x"})

    await probe(comm_b, peer_device.id)  # dropped quietly, socket healthy
    assert await comm_a.receive_nothing(timeout=0.2)
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_oversized_room_blob_is_dropped(
    active_user, device, peer, peer_device, settings
):
    settings.SIGNAL_MAX = 64
    room = await make_room()
    room_id = str(room.id)
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    await subscribe_ok(comm_a, room_id)
    await subscribe_ok(comm_b, room_id)
    assert (await comm_a.receive_json_from(timeout=2))["state"] == "join"

    await comm_a.send_json_to(
        {"type": "room_signal", "room_id": room_id, "blob": "b" * 65}
    )

    assert await comm_b.receive_nothing(timeout=0.3)
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_alternate_room_uuid_spellings_land_in_one_group(
    active_user, device, peer, peer_device
):
    """uuid.UUID accepts braces/uppercase/urn spellings; without normalization the two
    sockets would sit in different `room.<spelling>` groups and never meet."""
    room = await make_room()
    room_id = str(room.id)
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))

    echoed = await subscribe_ok(comm_a, room_id)  # canonical
    assert echoed == str(device.id)
    await comm_a.send_json_to({"type": "room_subscribe", "room_id": "{%s}" % room_id})
    # Braced spelling normalizes to the same group: the re-join echo names the
    # canonical room id.
    frame = await comm_a.receive_json_from(timeout=2)
    assert frame["room_id"] == room_id

    await comm_b.send_json_to({"type": "room_subscribe", "room_id": room_id.upper()})
    frame_b = await comm_b.receive_json_from(timeout=2)
    assert frame_b["room_id"] == room_id  # normalized into the same namespace
    assert (await comm_a.receive_json_from(timeout=2))["state"] == "join"

    await comm_b.send_json_to({"type": "room_signal", "room_id": room_id, "blob": "s"})
    assert (await comm_a.receive_json_from(timeout=2))["blob"] == "s"
    assert await live_count(room_id) == 2
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_room_subscriptions_are_capped_per_connection(
    active_user, device, monkeypatch
):
    """One socket cannot hoard unbounded room-group memberships (mirrors the
    500-target presence cap)."""
    monkeypatch.setattr("realtime.consumers.ROOM_SUBSCRIPTIONS_MAX", 1)
    room_one, room_two = await make_room(), await make_room()
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await subscribe_ok(comm, str(room_one.id))
    await comm.send_json_to({"type": "room_subscribe", "room_id": str(room_two.id)})

    await probe(comm, device.id)  # over-cap subscribe dropped quietly
    assert await live_count(str(room_two.id)) == 0

    # Re-subscribing a room already held is not "new" and stays allowed.
    await comm.send_json_to({"type": "room_subscribe", "room_id": str(room_one.id)})
    frame = await comm.receive_json_from(timeout=2)
    assert frame["state"] == "join"
    assert await live_count(str(room_one.id)) == 1
    await comm.disconnect()


async def test_room_traffic_emits_no_identifier_or_payload_into_logs(
    active_user, device, peer, peer_device
):
    """Capture swaps out all root handlers; caplog would grade the scrub filter's
    homework, not the code's."""
    room = await make_room()
    room_id = str(room.id)
    blob = "room-ciphertext-blob"

    with raw_root_capture() as lines:
        logging.getLogger("test.canary").debug("canary")

        comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
        comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
        await subscribe_ok(comm_a, room_id)
        await subscribe_ok(comm_b, room_id)
        await comm_a.receive_json_from(timeout=2)  # B's join, seen by A

        await comm_a.send_json_to(
            {"type": "room_signal", "room_id": room_id, "blob": blob}
        )
        await comm_a.receive_json_from(timeout=2)
        await comm_b.receive_json_from(timeout=2)

        # The malformed/ghost paths must be equally silent.
        await comm_a.send_json_to({"type": "room_subscribe", "room_id": "not-a-uuid"})
        await comm_a.send_json_to(
            {"type": "room_subscribe", "room_id": str(uuid.uuid4())}
        )
        await comm_a.send_json_to({"type": "room_leave", "room_id": room_id})
        await comm_b.receive_json_from(timeout=2)  # A's leave
        await comm_a.disconnect()
        await comm_b.disconnect()

    assert any("canary" in line for line in lines), "log capture was not live"
    forbidden = {
        "room id": room_id,
        "device id A": str(device.id),
        "device id B": str(peer_device.id),
        "room blob": blob,
    }
    for line in lines:
        for label, secret in forbidden.items():
            assert secret not in line, f"{label} leaked into a log line: {line[:80]}"
