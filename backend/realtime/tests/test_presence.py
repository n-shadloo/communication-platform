"""Presence: derived purely from socket up/down, disclosed only to the device groups
the client authorized via subscribe_presence, and held in memory only."""

import uuid

import pytest

from realtime import gateway

from .conftest import bearer, connect_ok, mint_access, probe, table_counts

pytestmark = pytest.mark.django_db(transaction=True)


async def test_subscriber_comes_online_then_offline_for_the_watched_peer(
    active_user, device, peer, peer_device
):
    """The presence exit test: B is connected; A connects and subscribes-presence to B;
    B learns A is online, and A's disconnect delivers offline."""
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm_a.send_json_to(
        {"type": "subscribe_presence", "device_ids": [str(peer_device.id)]}
    )
    assert await comm_b.receive_json_from(timeout=2) == {
        "type": "presence",
        "device_id": str(device.id),
        "state": "online",
    }

    await comm_a.disconnect()
    assert await comm_b.receive_json_from(timeout=2) == {
        "type": "presence",
        "device_id": str(device.id),
        "state": "offline",
    }
    await comm_b.disconnect()


async def test_presence_reaches_nobody_who_was_not_authorized(
    active_user, device, peer, peer_device
):
    """An empty subscription list means silence: the server tells only the groups the
    client authorized, never every peer it happens to know a socket for."""
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm_a.send_json_to({"type": "subscribe_presence", "device_ids": []})
    await comm_a.disconnect()

    assert await comm_b.receive_nothing(timeout=0.3)
    await comm_b.disconnect()


async def test_oversized_subscription_lists_are_ignored(
    active_user, device, peer, peer_device
):
    """The 500-target cap bounds the per-disconnect fan-out."""
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))

    ids = [str(peer_device.id)] * 501
    await comm_a.send_json_to({"type": "subscribe_presence", "device_ids": ids})

    assert await comm_b.receive_nothing(timeout=0.3)
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_invalid_ids_are_skipped_but_valid_ones_kept(
    active_user, device, peer, peer_device
):
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm_a.send_json_to(
        {
            "type": "subscribe_presence",
            "device_ids": ["not-a-uuid", {"a": 1}, str(peer_device.id).upper()],
        }
    )

    assert await comm_b.receive_json_from(timeout=2) == {
        "type": "presence",
        "device_id": str(device.id),
        "state": "online",
    }
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_subscriptions_leave_zero_rows(active_user, device, peer, peer_device):
    """The subscription set lives in consumer memory only, never any table."""
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    before = await table_counts()

    await comm_a.send_json_to(
        {"type": "subscribe_presence", "device_ids": [str(peer_device.id)]}
    )
    await comm_b.receive_json_from(timeout=2)
    await probe(comm_a, device.id)

    assert await table_counts() == before
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_a_target_list_of_exactly_the_cap_is_accepted(
    active_user, device, peer, peer_device
):
    """500 is what a client may watch, not what it must stay under. The cap bounds
    the fan-out one disconnect costs; a client whose contact list lands exactly on
    it must still be told about every one of them."""
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))
    ids = [str(uuid.uuid4()) for _ in range(gateway.PRESENCE_TARGETS_MAX - 1)]
    ids.append(str(peer_device.id))

    await comm_a.send_json_to({"type": "subscribe_presence", "device_ids": ids})

    assert await comm_b.receive_json_from(timeout=2) == {
        "type": "presence",
        "device_id": str(device.id),
        "state": "online",
    }
    await comm_a.disconnect()
    await comm_b.disconnect()


async def test_a_second_subscribe_replaces_the_target_set(
    active_user, device, peer, peer_device
):
    """The frame is a replacement, not an addition. A set that only ever grew would
    keep announcing this device to a peer the client stopped watching — and would
    do it again on the disconnect, which is the announcement that matters."""
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm_a.send_json_to(
        {"type": "subscribe_presence", "device_ids": [str(peer_device.id)]}
    )
    assert (await comm_b.receive_json_from(timeout=2))["state"] == "online"
    await comm_a.send_json_to({"type": "subscribe_presence", "device_ids": []})
    await comm_a.disconnect()

    assert await comm_b.receive_nothing(timeout=0.3), "offline reached a dropped target"
    await comm_b.disconnect()


async def test_a_target_list_that_is_not_a_list_is_dropped(
    active_user, device, peer, peer_device
):
    """A JSON string is iterable, so an unguarded loop over it would build one
    presence target per character and announce this device to five hundred topics
    that mean nothing."""
    comm_b = await connect_ok(bearer(await mint_access(peer, peer_device)))
    comm_a = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm_a.send_json_to(
        {"type": "subscribe_presence", "device_ids": str(peer_device.id)}
    )

    await probe(comm_a, device.id)  # dropped quietly, the socket is healthy
    assert await comm_b.receive_nothing(timeout=0.2)
    await comm_a.disconnect()
    await comm_b.disconnect()
