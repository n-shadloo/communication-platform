"""The Redis client of the process.

One client, shared by everything that speaks to Redis on the async side: the rate
limiter's counters, the live-room presence sets, and the gateway's fan-out bus,
whose subscription connection is borrowed from this pool. Sharing matters because
a client owns a connection pool, and a second client would double the pool
against an instance that also carries the Django cache.

An asyncio Redis client belongs to the event loop that created it: its
connections hold that loop's reader and writer, and a call from another loop
raises. The map below is therefore keyed by loop. The process runs one loop, so
it holds one entry; a context that runs a second loop gets a second client
rather than a cross-loop failure.
"""

import asyncio

from django.conf import settings
from redis.asyncio import Redis

_clients = {}


def timeouts():
    """The connect and command timeouts every Redis client of this process is built
    with, the synchronous ones included.

    Read on each call rather than bound at import, so the value a client is built
    with is the one the settings hold when it is built.
    `config/settings/base.py` carries why the process has them at all.
    """
    return {
        "socket_timeout": settings.REDIS_COMMAND_TIMEOUT_SECONDS,
        "socket_connect_timeout": settings.REDIS_COMMAND_TIMEOUT_SECONDS,
    }


def get_client():
    """The client of the running loop, built on first use.

    On first use rather than in a lifespan startup, because the map is keyed by
    loop and a startup handler only ever sees one of them: the tests drive the
    application on a loop of their own, and a worker that never opens a socket
    never needs a client at all. Building it here needs no await before the
    assignment, so two concurrent first callers on one loop cannot build two
    clients.
    """
    loop = asyncio.get_running_loop()
    client = _clients.get(loop)
    if client is None:
        client = Redis.from_url(settings.REDIS_URL, **timeouts())
        _clients[loop] = client
    return client


async def close_client():
    """Release the client of the running loop, where the server sends a lifespan
    shutdown."""
    client = _clients.pop(asyncio.get_running_loop(), None)
    if client is not None:
        await client.aclose()
