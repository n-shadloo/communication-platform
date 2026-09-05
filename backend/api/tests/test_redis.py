"""The Redis client of the process, and the loop it belongs to.

One client per event loop, built on first use and released by the lifespan. The
loop key is not an optimisation: an asyncio Redis client holds the reader and the
writer of the loop that built it, so a call from a second loop raises. The tests
drive the application on a loop of their own, which is the case that makes this
observable at all.
"""

import asyncio
import socket
import threading
import time
import uuid

import pytest
import redis
from django.conf import settings

from api.redis import close_client, get_client, timeouts
from core import lockout
from realtime import bus

KEY = "api-tests:redis-client"

# The headroom a timeout assertion allows above the value it was given. Every
# client below talks to a listener on loopback that answers nothing, so the whole
# wait is the timeout; this covers scheduling on a machine running the rest of the
# suite beside it.
PATIENCE = 1.0


@pytest.fixture
def black_hole():
    """A listener that accepts a connection and then answers nothing.

    Not a closed port: a refused connection is a different failure, and every
    client already learns about that one immediately. This is the store that is
    still there and has stopped speaking.
    """
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(8)
    accepted = []

    def hold_everything():
        while True:
            try:
                accepted.append(listener.accept()[0])
            except OSError:
                return

    threading.Thread(target=hold_everything, daemon=True).start()
    try:
        yield f"redis://127.0.0.1:{listener.getsockname()[1]}/0"
    finally:
        listener.close()
        for connection in accepted:
            connection.close()


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
    also carries the lockout state and the fan-out bus."""
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


class TestCommandTimeouts:
    """A store that never answers, which is the failure a refused connection does
    not cover.

    A stopped Redis refuses the connection and every caller learns immediately. A
    Redis that is still listening — blocked on a long command, or on the far side
    of a network that moved under it — accepts the connection and then says
    nothing, and without a timeout the caller waits for ever. On the HTTP surface
    the request deadline would eventually answer `503`; the gateway has no
    deadline at all, so the wait would end only when the client gave up. Each test
    below asserts the same two things about one of the four clients this process
    builds: it waited at least the configured timeout, and it came back.
    """

    async def test_the_configured_value_is_read_when_a_client_is_built(self, settings):
        """The normal path. Read on each call rather than bound at import, so a
        deployment that tunes the value gets the client it configured."""
        settings.REDIS_COMMAND_TIMEOUT_SECONDS = 7

        assert timeouts() == {"socket_timeout": 7, "socket_connect_timeout": 7}

    @pytest.mark.parametrize("configured", [0.15, 0.4])
    async def test_the_async_client_gives_up_on_a_store_that_never_answers(
        self, settings, black_hole, released_client, configured
    ):
        settings.REDIS_URL = black_hole
        settings.REDIS_COMMAND_TIMEOUT_SECONDS = configured

        started = time.monotonic()
        with pytest.raises(redis.TimeoutError):
            await get_client().incr(KEY)
        waited = time.monotonic() - started

        assert configured <= waited < configured + PATIENCE

    @pytest.mark.parametrize("configured", [0.15, 0.4])
    def test_the_login_lockout_refuses_rather_than_waits(
        self, settings, black_hole, monkeypatch, configured
    ):
        """`locked_for` fails closed, and a control that refuses traffic cannot
        spend a whole request deciding to."""
        settings.REDIS_URL = black_hole
        settings.REDIS_COMMAND_TIMEOUT_SECONDS = configured
        monkeypatch.setattr("core.lockout._store", None)

        started = time.monotonic()
        with pytest.raises(lockout.LockoutUnavailable):
            lockout.locked_for("operator", lockout.API)
        waited = time.monotonic() - started

        assert configured <= waited < configured + PATIENCE

    @pytest.mark.parametrize("configured", [0.15, 0.4])
    def test_dropping_the_sockets_of_a_device_comes_back(
        self, settings, black_hole, configured
    ):
        """Revocation runs on the ORM thread inside the unit of work that revoked
        the device. A publish that never returns would hold that transaction open
        against the device row for as long as the store stays silent."""
        settings.REDIS_URL = black_hole
        settings.REDIS_COMMAND_TIMEOUT_SECONDS = configured

        started = time.monotonic()
        bus.close_device_sockets(uuid.uuid4())
        waited = time.monotonic() - started

        assert configured <= waited < configured + PATIENCE
