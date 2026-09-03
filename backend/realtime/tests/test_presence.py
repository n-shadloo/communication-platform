"""Presence: derived purely from socket up/down, disclosed only to the device groups
the client authorized via subscribe_presence, and held in memory only."""

import pytest

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
