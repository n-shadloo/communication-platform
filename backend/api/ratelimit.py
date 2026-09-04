"""The Redis rate limiter.

Counters are volatile data, so they live in Redis and never on disk, and they
live outside the process so that raising `WEB_CONCURRENCY` cannot multiply the
effective limit by the worker count. The window is fixed: one `INCR` under a key
that carries the window index, and one `EXPIRE` on the first hit of that window.
`INCR` is a single atomic round trip, so two concurrent requests can never read
the same count.

When Redis is unreachable a throttled route fails closed with `503`. A control
whose whole purpose is to refuse traffic must not open the door when its store
is down.
"""

import asyncio
import time

from django.conf import settings
from fastapi import Request
from redis.asyncio import Redis
from redis.exceptions import RedisError

from api.errors import ApiError

# The suffix syntax REST Framework used, kept so the THROTTLE_* values and their
# defaults carry over unchanged.
_PERIODS = {"s": 1, "m": 60, "h": 3600, "d": 86400}


def parse_rate(rate):
    """`"120/min"` to `(120, 60)`."""
    count, _, period = rate.partition("/")
    return int(count), _PERIODS[period[0]]


# An asyncio Redis client belongs to the event loop that created it: its
# connections hold that loop's reader and writer, and a call from another loop
# raises. The process runs one loop, so this map holds one entry; a context that
# runs a second loop gets a second client rather than a cross-loop failure.
_clients = {}


def get_client():
    """The Redis client of the running loop, built on first use.

    Not built in the lifespan handler: during the transition daphne serves the
    process, and daphne never sends the ASGI lifespan messages, so a client that
    only startup creates would be absent on every production request. Building it
    here needs no await before the assignment, so two concurrent first requests
    on one loop cannot build two clients.
    """
    loop = asyncio.get_running_loop()
    client = _clients.get(loop)
    if client is None:
        client = Redis.from_url(settings.REDIS_URL)
        _clients[loop] = client
    return client


async def close_client():
    """Release the client of the running loop, where the server sends a lifespan
    shutdown."""
    client = _clients.pop(asyncio.get_running_loop(), None)
    if client is not None:
        await client.aclose()


def _ident(request):
    """An authenticated request counts per account, so the limit follows the
    caller across their devices. Anything else counts per client address, which
    is trustworthy only because the process trusts a forwarded header from the
    proxy's own address alone."""
    principal = getattr(request.state, "principal", None)
    if principal is not None:
        return f"user:{principal.user.id}"
    client = request.client
    return f"addr:{client.host if client else 'unknown'}"


def rate_limit(scope):
    """The dependency that counts one request against `scope`."""

    async def limit(request: Request):
        rate, period = parse_rate(settings.THROTTLE_RATES[scope])
        now = int(time.time())
        key = f"ratelimit:{scope}:{_ident(request)}:{now // period}"
        client = get_client()
        try:
            count = await client.incr(key)
            if count == 1:
                await client.expire(key, period)
        except RedisError:
            raise ApiError(503, "unavailable", "The service is temporarily unavailable.")
        if count > rate:
            raise ApiError(
                429,
                "throttled",
                "Request was throttled.",
                {"Retry-After": str(period - now % period)},
            )

    # The route table test reads the scope of each route off this name.
    limit.__name__ = f"rate_limit_{scope}"
    return limit
