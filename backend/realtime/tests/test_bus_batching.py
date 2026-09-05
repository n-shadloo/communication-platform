"""What a fan-out of many payloads costs in round trips.

One path publishes to more than one topic at a time: a batch send, which is one
envelope per recipient copy and capped at 256. Awaited one at a time those are
that many sequential round trips on the event loop, and the loop is the whole
process on one vCPU. Measured on loopback: 256 sequential publishes cost 37.1 ms
against 1.5 ms for one pipeline.
"""

import asyncio
import json

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
        (bus.device_topic(f"{prefix}-{index}"), {"type": "probe", "n": index})
        for index in range(count)
    ]


async def test_a_fan_out_of_many_payloads_costs_one_round_trip(round_trips):
    await bus.publish_many(frames(TOPICS))

    assert round_trips == {"publishes": 0, "executes": 1}


async def test_a_fan_out_of_nothing_touches_redis_at_all(round_trips):
    """A send that reached only stale devices arrives here with an empty list."""
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
    source of truth. It still costs the one attempted round trip, and nothing
    falls back to publishing one at a time."""
    monkeypatch.setattr(bus, "get_client", lambda: Redis.from_url(DEAD_REDIS_URL))

    await bus.publish_many(frames(TOPICS))

    assert round_trips == {"publishes": 0, "executes": 1}


async def test_a_fan_out_larger_than_the_pipeline_budget_is_split(
    round_trips, monkeypatch
):
    """A pipeline packs every command into memory before it writes any of them, so
    one that carries the whole fan-out holds it twice — the serialized payloads and
    the packed bytes.

    Measured on the largest batch the body cap admits, 200 envelopes at the
    262 144 bucket and 70 MB of base64: one pipeline peaked at 178.3 MB of resident
    set, against 37.8 MB for the same publishes issued one at a time. That is 140 MB
    of a 1 GB host bought with 35 ms of event loop, which is the wrong trade. The
    budget bounds what is held; the round trips stay far below one for each frame.
    """
    monkeypatch.setattr(bus, "PIPELINE_BYTES", 1000)
    frames = [
        (bus.device_topic(f"large-{index}"), {"blob": "x" * 400}) for index in range(10)
    ]
    each = len(json.dumps(frames[0][1]))
    per_batch = -(-bus.PIPELINE_BYTES // each)  # frames before the budget is passed

    await bus.publish_many(frames)

    assert round_trips == {
        "publishes": 0,
        "executes": -(-len(frames) // per_batch),
    }


async def test_a_payload_the_encoder_refuses_drops_the_whole_batch(round_trips):
    """The encoding is inside the same best-effort bracket as the round trip, so a
    payload no caller should have built cannot take down the send that built it.
    Nothing is written either, which is what makes the batch all-or-nothing here
    rather than half-published."""
    frames = [(bus.device_topic("encoder-refusal"), {"blob": object()})]

    assert await bus.publish_many(frames) is None

    assert round_trips == {"publishes": 0, "executes": 0}


async def test_a_batch_that_lands_exactly_on_the_budget_costs_one_round_trip(
    round_trips, monkeypatch
):
    """The budget is a threshold the loop crosses, and the flush that follows the
    loop must cost nothing when the loop already emptied the buffer. Otherwise
    every fan-out that divides evenly into the budget pays a round trip for a
    pipeline with no commands in it."""
    payload = {"blob": "x" * 100}
    each = len(json.dumps(payload))
    frames = [(bus.device_topic(f"exact-{index}"), payload) for index in range(4)]
    monkeypatch.setattr(bus, "PIPELINE_BYTES", each * len(frames))

    await bus.publish_many(frames)

    assert round_trips == {"publishes": 0, "executes": 1}


async def test_a_push_gives_each_recipient_its_own_envelope_frame():
    """One accepted send fans out to one copy per recipient device, and each copy
    carries that device's own row id and sequence. A frame that carried the
    sender's, or one recipient's id on another's topic, would be a message the
    client cannot ack."""
    subscriber = bus.get_subscriber()
    first, second = [], []
    await subscriber.subscribe(bus.device_topic("push-first"), first.append)
    await subscriber.subscribe(bus.device_topic("push-second"), second.append)

    await bus.push_envelopes(
        [
            ("push-first", "id-one", 1, "blob-one"),
            ("push-second", "id-two", 7, "blob-two"),
        ]
    )

    async with asyncio.timeout(5):
        while not (first and second):
            await asyncio.sleep(0.01)
    assert first == [{"type": "envelope", "id": "id-one", "seq": 1, "blob": "blob-one"}]
    assert second == [{"type": "envelope", "id": "id-two", "seq": 7, "blob": "blob-two"}]
