import redis
from django.conf import settings

# Redis-backed, non-persistent (redis is configured save "" / appendonly no — §A10). Live
# room membership is ephemeral state, never written to the database.
#
# Native set ops (SADD/SREM/SCARD) instead of cache round-tripping: pickling a Python set
# through cache.get/cache.set is a read-modify-write that loses concurrent joins (measured
# pre-phase: 16 simultaneous joins left as few as 3 members). Each command below is a
# single atomic Redis op, and Redis deletes a set key the moment its last member is
# removed, so an empty room leaves nothing behind.

_client = None

# Self-healing bound: a worker that dies without running disconnect() strands its
# members in the set, so every join/leave refreshes a day-long TTL. A room whose
# membership sees zero churn for 24h self-clears — best-effort ephemerality, worded
# honestly (§A14) — and ghosts from a crash never outlive the day.
ROOMLIVE_TTL_SECONDS = 86400


def _redis():
    global _client
    if _client is None:
        _client = redis.Redis.from_url(settings.REDIS_URL)
    return _client


def _key(room_id):
    return f"roomlive:{room_id}"


def room_join(room_id, device_id):
    client = _redis()
    client.sadd(_key(room_id), str(device_id))
    client.expire(_key(room_id), ROOMLIVE_TTL_SECONDS)


def room_leave(room_id, device_id):
    client = _redis()
    client.srem(_key(room_id), str(device_id))
    client.expire(_key(room_id), ROOMLIVE_TTL_SECONDS)


def room_live_count(room_id):
    return _redis().scard(_key(room_id))
