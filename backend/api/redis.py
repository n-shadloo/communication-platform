"""The Redis client of the process.

One client, shared by everything that speaks to Redis on the async side: the
rate limiter's counters and the live-room presence sets. Sharing matters because
a client owns a connection pool, and a second client would double the pool
against an instance that also carries the Django cache and the channel layer.

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


def get_client():
    """The client of the running loop, built on first use.

    Not built in a lifespan handler: during the transition daphne serves the
    process, and daphne never sends the ASGI lifespan messages, so a client that
    only startup creates would be absent on every production request. Building it
    here needs no await before the assignment, so two concurrent first callers on
    one loop cannot build two clients.
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
