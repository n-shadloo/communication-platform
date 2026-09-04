"""Live room membership: a Redis set and nothing else, atomic under concurrency,
self-cleaning when the room empties, never a database row."""

import asyncio
import uuid

import pytest

from api.redis import close_client, get_client
from voicerooms.presence import (
    ROOMLIVE_TTL_SECONDS,
    _key,
    room_join,
    room_leave,
    room_live_count,
)


@pytest.fixture
def room_id():
    return uuid.uuid4()


@pytest.fixture(autouse=True)
async def drop_key(room_id):
    """Each test runs on its own event loop, so it builds its own client and must
    release it: a client outliving its loop leaves an open socket behind."""
    yield
    await get_client().delete(_key(room_id))
    await close_client()


async def test_join_count_leave_roundtrip(room_id):
    assert await room_live_count(room_id) == 0
    await room_join(room_id, "device-a")
    await room_join(room_id, "device-b")
    assert await room_live_count(room_id) == 2
    await room_leave(room_id, "device-a")
    assert await room_live_count(room_id) == 1


async def test_rejoining_the_same_device_counts_once(room_id):
    await room_join(room_id, "device-a")
    await room_join(room_id, "device-a")
    assert await room_live_count(room_id) == 1


async def test_leaving_a_room_never_joined_is_a_quiet_noop(room_id):
    await room_leave(room_id, "device-a")
    assert await room_live_count(room_id) == 0


async def test_the_last_leave_deletes_the_redis_key_entirely(room_id):
    """When a room empties, nothing lingers, not even an empty set."""
    await room_join(room_id, "device-a")
    await room_leave(room_id, "device-a")
    assert await get_client().exists(_key(room_id)) == 0


async def test_membership_carries_a_self_healing_ttl(room_id):
    """A worker that dies without disconnect() must not strand members forever:
    join/leave activity keeps refreshing a day-long expiry on the whole set."""
    await room_join(room_id, "device-a")
    assert 0 < await get_client().ttl(_key(room_id)) <= ROOMLIVE_TTL_SECONDS

    await room_join(room_id, "device-b")
    await room_leave(room_id, "device-b")
    assert 0 < await get_client().ttl(_key(room_id)) <= ROOMLIVE_TTL_SECONDS


async def test_concurrent_joins_all_survive(room_id):
    """The reason presence is native SADD, not a cached pickled set: the read-modify-
    write round-trip loses concurrent joins."""
    joiners = 16

    await asyncio.gather(*(room_join(room_id, uuid.uuid4()) for _ in range(joiners)))

    assert await room_live_count(room_id) == joiners


async def test_every_caller_shares_one_client(room_id):
    """One client for the loop, so the limiter and presence draw on one pool
    against an instance that also carries the cache and the channel layer."""
    from api import ratelimit

    assert ratelimit.get_client() is get_client()
