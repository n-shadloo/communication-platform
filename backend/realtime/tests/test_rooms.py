"""Room real-time: live membership and ephemeral room text ride the socket and
non-persistent Redis, never the database and never the logs.

Room traffic crosses a Redis publish and subscribe topic, which stores nothing:
Redis holds a published message only for the instant it takes to hand it to the
subscribers connected right then. The only room key Redis keeps is the live-count
set of `voicerooms/presence.py`, and it is asserted directly below. So anything a
test finds afterwards could only have reached a persistent store, which the
zero-row assertions check.
"""

import logging
import uuid

import pytest

from api.orm import run_unit
from api.redis import get_client
from core.buckets import NAME_BUCKETS
from realtime.bus import get_subscriber, room_topic
from voicerooms.models import Room
from voicerooms.presence import room_live_count

from .conftest import bearer, connect_ok, mint_access, probe, table_counts
from .test_log_silence import raw_root_capture

pytestmark = pytest.mark.django_db(transaction=True)


async def make_room():
    return await run_unit(Room.objects.create, name_blob=b"r" * min(NAME_BUCKETS))


async def probe_past(comm, own_device_id):
    """`conftest.probe`, tolerant of one frame that may or may not arrive.

    A leave announcement is published before the socket gives the topic back, so
    whether the leaving socket sees its own leave is a race with its own
    unsubscribe. The probe still orders everything: it is published after the
    unsubscribe has returned, and one subscriber connection delivers in publish
    order, so a socket that has seen the probe has seen whatever came before it.
    """
    await comm.send_json_to(
        {"type": "signal", "to_device": str(own_device_id), "blob": "probe"}
    )
    while await comm.receive_json_from(timeout=2) != {"type": "signal", "blob": "probe"}:
        continue


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

    assert await room_live_count(room_id) == 0
    await subscribe_ok(comm_a, room_id)
    assert await room_live_count(room_id) == 1
    await subscribe_ok(comm_b, room_id)
    assert (await comm_a.receive_json_from(timeout=2))["state"] == "join"
    assert await room_live_count(room_id) == 2

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
    assert await room_live_count(room_id) == 1

    # Disconnect leaves every room without an explicit room_leave frame.
    await comm_b.disconnect()
    assert await room_live_count(room_id) == 0
    assert await table_counts() == before, "presence traffic changed a table"
    await comm_a.disconnect()


async def test_subscribing_to_a_nonexistent_room_is_ignored(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    ghost = str(uuid.uuid4())

    await comm.send_json_to({"type": "room_subscribe", "room_id": ghost})
    await probe(comm, device.id)  # consumer alive, no join echo came
    assert await room_live_count(ghost) == 0

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
    assert await room_live_count(room_id) == 2
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_room_subscriptions_are_capped_per_connection(
    active_user, device, monkeypatch
):
    """One socket cannot hoard unbounded room-group memberships (mirrors the
    500-target presence cap)."""
    monkeypatch.setattr("realtime.gateway.ROOM_SUBSCRIPTIONS_MAX", 1)
    room_one, room_two = await make_room(), await make_room()
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await subscribe_ok(comm, str(room_one.id))
    await comm.send_json_to({"type": "room_subscribe", "room_id": str(room_two.id)})

    await probe(comm, device.id)  # over-cap subscribe dropped quietly
    assert await room_live_count(str(room_two.id)) == 0

    # Re-subscribing a room already held is not "new" and stays allowed.
    await comm.send_json_to({"type": "room_subscribe", "room_id": str(room_one.id)})
    frame = await comm.receive_json_from(timeout=2)
    assert frame["state"] == "join"
    assert await room_live_count(str(room_one.id)) == 1
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


async def test_a_room_leave_for_a_room_the_socket_never_joined_is_ignored(
    active_user, device, peer, peer_device
):
    """Knowing a room id buys nothing on the way out either. A leave that fired for
    a socket that never joined would announce a departure the room's subscribers
    never saw arrive, and would drop a live count this device is not part of."""
    room = await make_room()
    room_id = str(room.id)
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    await subscribe_ok(comm_a, room_id)

    await comm_b.send_json_to({"type": "room_leave", "room_id": room_id})

    await probe(comm_b, peer_device.id)  # dropped quietly, the socket is healthy
    assert await comm_a.receive_nothing(timeout=0.2)
    assert await room_live_count(room_id) == 1
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_a_room_blob_of_exactly_the_cap_still_relays(
    active_user, device, peer, peer_device, settings
):
    """The bound is what a blob may be. Room text that lands exactly on it is the
    largest message the room can carry, and refusing that one drops the message
    without telling anybody."""
    settings.SIGNAL_MAX = 64
    room = await make_room()
    room_id = str(room.id)
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    await subscribe_ok(comm_a, room_id)
    await subscribe_ok(comm_b, room_id)
    assert (await comm_a.receive_json_from(timeout=2))["state"] == "join"
    blob = "b" * settings.SIGNAL_MAX

    await comm_a.send_json_to({"type": "room_signal", "room_id": room_id, "blob": blob})

    expected = {"type": "room_signal", "room_id": room_id, "blob": blob}
    assert await comm_a.receive_json_from(timeout=2) == expected
    assert await comm_b.receive_json_from(timeout=2) == expected
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_leaving_a_room_gives_its_topic_back_to_the_worker(active_user, device):
    """The subscription is per topic, so a room left but never unsubscribed keeps
    this worker receiving every blob of a session it has no socket in — which is
    the cost the pattern subscription was rejected for in the first place."""
    room = await make_room()
    room_id = str(room.id)
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await subscribe_ok(comm, room_id)
    assert room_topic(room_id) in get_subscriber()._sinks

    await comm.send_json_to({"type": "room_leave", "room_id": room_id})
    await probe_past(comm, device.id)

    assert room_topic(room_id) not in get_subscriber()._sinks
    assert await room_live_count(room_id) == 0
    await comm.disconnect()


async def test_a_disconnect_leaves_every_room_it_held_and_no_key_in_redis(
    active_user, device
):
    """The live-count set is the only room key Redis holds, and Redis drops a set
    the moment its last member goes. A count that stayed at zero rather than
    vanishing would be a room roster at rest — small, but a roster."""
    room_one, room_two = await make_room(), await make_room()
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await subscribe_ok(comm, str(room_one.id))
    await subscribe_ok(comm, str(room_two.id))
    assert await room_live_count(str(room_one.id)) == 1

    await comm.disconnect()

    assert await room_live_count(str(room_two.id)) == 0
    assert get_subscriber()._sinks == {}
    assert await get_client().keys("*") == []
