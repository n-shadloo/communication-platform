"""Live room membership: a Redis set and nothing else, atomic under concurrency,
self-cleaning when the room empties, never a database row."""
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest

from voicerooms.presence import _key, _redis, room_join, room_leave, room_live_count


@pytest.fixture
def room_id():
    return uuid.uuid4()


@pytest.fixture(autouse=True)
def drop_key(room_id):
    yield
    _redis().delete(_key(room_id))


def test_join_count_leave_roundtrip(room_id):
    assert room_live_count(room_id) == 0
    room_join(room_id, "device-a")
    room_join(room_id, "device-b")
    assert room_live_count(room_id) == 2
    room_leave(room_id, "device-a")
    assert room_live_count(room_id) == 1


def test_rejoining_the_same_device_counts_once(room_id):
    room_join(room_id, "device-a")
    room_join(room_id, "device-a")
    assert room_live_count(room_id) == 1


def test_leaving_a_room_never_joined_is_a_quiet_noop(room_id):
    room_leave(room_id, "device-a")
    assert room_live_count(room_id) == 0


def test_the_last_leave_deletes_the_redis_key_entirely(room_id):
    """When a room empties, nothing lingers, not even an empty set."""
    room_join(room_id, "device-a")
    room_leave(room_id, "device-a")
    assert _redis().exists(_key(room_id)) == 0


def test_membership_carries_a_self_healing_ttl(room_id):
    """A worker that dies without disconnect() must not strand members forever:
    join/leave activity keeps refreshing a day-long expiry on the whole set."""
    from voicerooms.presence import ROOMLIVE_TTL_SECONDS

    room_join(room_id, "device-a")
    assert 0 < _redis().ttl(_key(room_id)) <= ROOMLIVE_TTL_SECONDS

    room_join(room_id, "device-b")
    room_leave(room_id, "device-b")
    assert 0 < _redis().ttl(_key(room_id)) <= ROOMLIVE_TTL_SECONDS


def test_concurrent_joins_all_survive(room_id):
    """The reason presence is native SADD, not a cached pickled set: the read-modify-
    write round-trip loses concurrent joins."""
    joiners = 16
    barrier = threading.Barrier(joiners)

    def join(_):
        barrier.wait()
        room_join(room_id, uuid.uuid4())

    with ThreadPoolExecutor(max_workers=joiners) as pool:
        list(pool.map(join, range(joiners)))

    assert room_live_count(room_id) == joiners
