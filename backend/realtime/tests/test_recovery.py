"""What survives a connection that drops, a socket that is cancelled, and a socket
that crashes.

None of the three reports itself. A subscriber whose connection went away and
never re-subscribed leaves every socket of the worker silent but open, and a
socket torn down without its cleanup leaves a device announced online to peers
that will never hear otherwise and a topic subscribed with no reader behind it.
"""

import asyncio
import uuid

import pytest
import redis.asyncio

from realtime import auth, bus, gateway

from .conftest import bearer, connect_ok, mint_access

pytestmark = pytest.mark.django_db(transaction=True)

DELIVERY_TIMEOUT = 10


async def wait_for(predicate, timeout=DELIVERY_TIMEOUT):
    async with asyncio.timeout(timeout):
        while not predicate():
            await asyncio.sleep(0.05)


async def test_the_subscriber_keeps_delivering_after_its_connection_drops(
    monkeypatch, settings
):
    """The bus holds one long-lived subscription for the worker, so a dropped
    connection is every socket of the process going quiet at once. The reader
    waits out the drop and reads again; redis-py re-issues SUBSCRIBE for each held
    topic when it reconnects."""
    monkeypatch.setattr(bus, "RECONNECT_DELAY_SECONDS", 0.05)
    received = []
    topic = bus.device_topic("dropped-connection-probe")
    await bus.get_subscriber().subscribe(topic, received.append)

    killer = redis.asyncio.Redis.from_url(settings.REDIS_URL)
    try:
        await killer.execute_command("CLIENT", "KILL", "TYPE", "pubsub")
    finally:
        await killer.aclose()

    async with asyncio.timeout(DELIVERY_TIMEOUT):
        while not received:
            await bus.publish(topic, {"type": "probe"})
            await asyncio.sleep(0.1)
    assert received[0] == {"type": "probe"}


async def test_a_cancelled_socket_still_announces_itself_offline(
    active_user, device, peer, peer_device
):
    """uvicorn cancels what it cannot drain, and a cleanup that a cancellation cuts
    short leaves this device online for every peer that subscribed to it."""
    watcher = []
    peer_topic = bus.device_topic(str(peer_device.id))
    await bus.get_subscriber().subscribe(peer_topic, watcher.append)

    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await comm.send_json_to(
        {"type": "subscribe_presence", "device_ids": [str(peer_device.id)]}
    )
    await wait_for(lambda: any(f.get("state") == "online" for f in watcher))

    comm.task.cancel()  # what a server does to a handler it cannot drain

    await wait_for(lambda: any(f.get("state") == "offline" for f in watcher))
    assert gateway.LIVE == set()


async def test_a_cancelled_socket_gives_its_topic_back(active_user, device):
    """A sink left registered for a topic nobody reads keeps the worker subscribed
    to a device that is gone."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    topic = bus.device_topic(str(device.id))
    await wait_for(lambda: topic in bus.get_subscriber()._sinks)

    comm.task.cancel()  # what a server does to a handler it cannot drain

    await wait_for(lambda: topic not in bus.get_subscriber()._sinks)


async def test_a_socket_that_crashes_still_announces_itself_offline(
    active_user, device, peer, peer_device, monkeypatch
):
    """A defect inside a frame handler leaves the task group with an exception the
    `except* _Stop` clause does not catch, so it propagates rather than closing
    cleanly. The cleanup is in a `finally` for exactly that case: without it a
    crashed socket leaves its device online for every peer watching it."""
    watcher = []
    await bus.get_subscriber().subscribe(
        bus.device_topic(str(peer_device.id)), watcher.append
    )
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await comm.send_json_to(
        {"type": "subscribe_presence", "device_ids": [str(peer_device.id)]}
    )
    await wait_for(lambda: any(f.get("state") == "online" for f in watcher))

    async def explode(*_args, **_kwargs):
        raise RuntimeError("a defect in a frame handler")

    monkeypatch.setattr(auth, "delete_envelopes", explode)
    await comm.send_json_to({"type": "ack", "ids": [str(uuid.uuid4())]})

    await wait_for(lambda: any(f.get("state") == "offline" for f in watcher))
    assert gateway.LIVE == set()
