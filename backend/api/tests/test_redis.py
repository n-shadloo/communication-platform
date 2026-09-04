"""The Redis client of the process, and the loop it belongs to.

One client per event loop, built on first use and released by the lifespan. The
loop key is not an optimisation: an asyncio Redis client holds the reader and the
writer of the loop that built it, so a call from a second loop raises. The tests
drive the application on a loop of their own, which is the case that makes this
observable at all.
"""

import asyncio

import pytest
import redis
from django.conf import settings

from api.redis import close_client, get_client

KEY = "api-tests:redis-client"


@pytest.fixture
async def released_client():
    """Whatever this test built stays with this loop and no longer."""
    yield
    await close_client()


def build_and_release_on_a_loop_of_its_own():
    """A client built, used and released on a second event loop."""

    async def build():
        client = get_client()
        try:
            return client, await client.ping()
        finally:
            await close_client()

    return asyncio.run(build())


async def test_one_loop_holds_one_client(released_client):
    """A second client would double the connection pool against an instance that
    also carries the presence sets and the fan-out bus."""
    assert get_client() is get_client()


async def test_a_second_loop_builds_a_client_of_its_own(released_client):
    """A client shared across loops raises on the second loop's first command, so
    the map is keyed by loop rather than held as one module-level client."""
    ours = get_client()

    theirs, reachable = await asyncio.to_thread(build_and_release_on_a_loop_of_its_own)

    assert theirs is not ours
    assert reachable is True


async def test_the_client_writes_to_the_configured_store(released_client):
    """Read back through a separate client built from `REDIS_URL`, so what this
    asserts is the instance the deployment configured and not just a round trip
    through the same object."""
    await get_client().set(KEY, "written-by-the-async-client")

    reader = redis.Redis.from_url(settings.REDIS_URL)
    try:
        assert reader.get(KEY) == b"written-by-the-async-client"
    finally:
        reader.close()


async def test_shutdown_releases_the_client_and_the_next_use_builds_another(
    released_client,
):
    """The lifespan calls this on shutdown. A pooled connection that outlives its
    loop is a socket nothing will ever read again."""
    first = get_client()

    await close_client()

    assert get_client() is not first


async def test_a_shutdown_with_no_client_to_release_is_not_an_error(released_client):
    """The rare case the lifespan hits every time a worker serves no traffic: it
    runs on shutdown whether or not anything ever opened a socket."""
    await close_client()

    await close_client()

    assert await get_client().ping() is True
