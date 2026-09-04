"""Live room membership: one Redis set for each room, and nothing else.

Redis-backed and non-persistent (redis runs with save "" and appendonly no). Live
room membership is ephemeral state, never written to the database.

Native set ops (SADD/SREM/SCARD) instead of cache round-tripping: pickling a Python
set through cache.get/cache.set is a read-modify-write that loses concurrent joins.
Each command below is a single atomic Redis op, and Redis deletes a set key the
moment its last member is removed, so an empty room leaves nothing behind.

Async, on the client `api.redis` shares with the rate limiter: both callers are
already on the event loop — the room routes and the WebSocket gateway — and a
synchronous client there would block it for the round trip.
"""

from api.redis import get_client

# Self-healing bound: a worker that dies without running disconnect() strands its
# members in the set, so every join/leave refreshes a day-long TTL. A room whose
# membership sees zero churn for 24h self-clears, and ghosts from a crash never
# outlive the day.
ROOMLIVE_TTL_SECONDS = 86400


def _key(room_id):
    return f"roomlive:{room_id}"


async def room_join(room_id, device_id):
    client = get_client()
    await client.sadd(_key(room_id), str(device_id))
    await client.expire(_key(room_id), ROOMLIVE_TTL_SECONDS)


async def room_leave(room_id, device_id):
    client = get_client()
    await client.srem(_key(room_id), str(device_id))
    await client.expire(_key(room_id), ROOMLIVE_TTL_SECONDS)


async def room_live_count(room_id):
    return await get_client().scard(_key(room_id))
