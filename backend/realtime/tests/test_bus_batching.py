"""What a fan-out of many payloads costs in round trips.

Two paths publish to more than one topic at a time: a batch send, which is one
envelope per recipient copy and capped at 256, and a presence announcement, which
is one frame per subscribed device and capped at 500. Awaited one at a time those
are that many sequential round trips on the event loop, and the loop is the whole
process on one vCPU. Measured on loopback: 256 sequential publishes cost 37.1 ms
against 1.5 ms for one pipeline, and 500 cost 55.9 ms against 2.5 ms.
"""

import asyncio

import pytest
from redis.asyncio import Redis
from redis.asyncio.client import Pipeline

from realtime import bus

pytestmark = pytest.mark.django_db(transaction=True)

TOPICS = 20
DEAD_REDIS_URL = "redis://127.0.0.1:6390"


@pytest.fixture
def round_trips(monkeypatch):
    """The round trips a fan-out costs, split by how it paid for them.

    Counted at the two places a batched command and a lone one part company: a
    `Pipeline` buffers through its own `execute_command` and reaches the wire once
    in `execute`, while a command issued on the client goes out through
    `Redis.execute_command` on its own. `Redis.publish` is no use here — a
    `Pipeline` is a `Redis`, so both paths run the same method.
    """
    counts = {"publishes": 0, "executes": 0}
    real_command, real_execute = Redis.execute_command, Pipeline.execute

    async def counted_command(self, *args, **kwargs):
        if args and args[0] == "PUBLISH":
            counts["publishes"] += 1
        return await real_command(self, *args, **kwargs)

    async def counted_execute(self, *args, **kwargs):
        counts["executes"] += 1
        return await real_execute(self, *args, **kwargs)

    monkeypatch.setattr(Redis, "execute_command", counted_command)
    monkeypatch.setattr(Pipeline, "execute", counted_execute)
    return counts


def frames(count, prefix="device"):
    return [
        (bus.device_topic(f"{prefix}-{index}"), {"type": "presence", "n": index})
        for index in range(count)
    ]


async def test_a_fan_out_of_many_payloads_costs_one_round_trip(round_trips):
    await bus.publish_many(frames(TOPICS))

    assert round_trips == {"publishes": 0, "executes": 1}


async def test_a_fan_out_of_nothing_touches_redis_at_all(round_trips):
    """A send that reached only stale devices, and a socket that authorized no
    presence target, both arrive here with an empty list."""
    await bus.publish_many([])

    assert round_trips == {"publishes": 0, "executes": 0}


async def test_every_payload_of_the_batch_reaches_its_own_topic():
    """One round trip, but still one frame per topic: the batching must not
    collapse, reorder or drop a payload."""
    subscriber = bus.get_subscriber()
    seen = {}
    expected = dict(frames(TOPICS, prefix="batched"))
    for topic in expected:
        await subscriber.subscribe(
            topic, lambda payload, t=topic: seen.setdefault(t, payload)
        )

    await bus.publish_many(list(expected.items()))

    async with asyncio.timeout(5):
        while len(seen) < TOPICS:
            await asyncio.sleep(0.01)
    assert seen == expected


async def test_a_dead_bus_swallows_the_whole_batch(monkeypatch, round_trips):
    """Best-effort, exactly like a single publish: the durable mailbox is the
    source of truth, and presence is volatile by design. It still costs the one
    attempted round trip, and nothing falls back to publishing one at a time."""
    monkeypatch.setattr(bus, "get_client", lambda: Redis.from_url(DEAD_REDIS_URL))

    await bus.publish_many(frames(TOPICS))

    assert round_trips == {"publishes": 0, "executes": 1}
