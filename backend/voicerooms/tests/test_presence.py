"""Live room membership: a Redis set and nothing else, atomic under concurrency,
self-cleaning when the room empties, never a database row."""

import asyncio
import types
import uuid

import pytest
from redis.exceptions import ConnectionError as RedisConnectionError

from api.redis import close_client, get_client
from voicerooms import presence
from voicerooms.presence import (
    ROOMLIVE_TTL_SECONDS,
    _key,
    live_counts,
    room_join,
    room_leave,
    room_live_count,
)

from .conftest import DEAD_REDIS_URL


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


class Stub:
    """A stand-in for the `redis` module `live_counts` builds its client from.

    `live_counts` is the one presence call that owns its connection, so what a
    stub can observe here is exactly what the production code decides: whether a
    connection was opened at all, and what happens when closing one fails.
    """

    def __init__(self, counts=(), close_error=None):
        self.counts = list(counts)
        self.close_error = close_error
        self.urls = []
        self.commands = []
        self.closed = 0

    def from_url(self, url, **kwargs):
        self.urls.append(url)
        return self

    def pipeline(self):
        return self

    def scard(self, key):
        self.commands.append(key)

    def execute(self):
        return self.counts

    def close(self):
        self.closed += 1
        if self.close_error is not None:
            raise self.close_error


def module_client(monkeypatch, stub):
    monkeypatch.setattr(
        presence,
        "redis",
        types.SimpleNamespace(Redis=types.SimpleNamespace(from_url=stub.from_url)),
    )
    return stub


async def test_live_counts_of_many_rooms_reads_each_ones_cardinality(room_id):
    """The normal path of the admin's column: one call, one answer for each room
    on the page, keyed by the string form of the id the caller passed."""
    quiet = uuid.uuid4()
    await room_join(room_id, "device-a")
    await room_join(room_id, "device-b")

    counts = live_counts([room_id, quiet])

    assert counts == {str(room_id): 2, str(quiet): 0}


async def test_live_counts_of_no_rooms_answers_empty_without_opening_a_connection(
    monkeypatch,
):
    """An empty changelist page must cost no socket at all: building a client to
    ask about nothing is a round trip and a file descriptor for no answer."""
    stub = module_client(monkeypatch, Stub())

    assert live_counts([]) == {}
    assert stub.urls == []


async def test_an_unreachable_store_reports_zero_rather_than_breaking_the_page(
    settings,
):
    """Best-effort by design: the admin changelist still renders when Redis is
    gone, and the exception it would otherwise raise would name a room id."""
    settings.REDIS_URL = DEAD_REDIS_URL
    rooms = [uuid.uuid4(), uuid.uuid4()]

    assert live_counts(rooms) == dict.fromkeys((str(room) for room in rooms), 0)


async def test_a_client_whose_close_fails_still_answers_the_counts_it_read(
    monkeypatch, room_id
):
    """The rare case: the read succeeded and only the teardown failed, so the
    counts are real and the failure has nowhere useful to go."""
    stub = module_client(monkeypatch, Stub(counts=[3], close_error=OSError("gone")))

    assert live_counts([room_id]) == {str(room_id): 3}
    assert stub.closed == 1


async def test_the_async_count_raises_rather_than_reporting_a_wrong_number(
    monkeypatch, room_id
):
    """The opposite policy to `live_counts`, and deliberately so: the route's
    answer carries `live_count` to a client, so an unreachable store must not be
    rendered as an empty room. The route never reaches here anyway — the rate
    limiter shares the client and fails closed first."""

    class Unreachable:
        async def scard(self, key):
            raise RedisConnectionError("refused")

    monkeypatch.setattr(presence, "get_client", lambda: Unreachable())

    with pytest.raises(RedisConnectionError):
        await room_live_count(room_id)
