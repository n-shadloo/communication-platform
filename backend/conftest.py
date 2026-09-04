import logging

import httpx
import pytest
import redis
from asgiref.sync import async_to_sync
from django.conf import settings
from httpx import ASGITransport

from accounts.models import User
from api.auth import issue_full, issue_register_scope
from config.asgi import api_application, application
from devices.models import Device

PASSWORD = "correct-horse-battery-staple"
BASE_URL = "http://testserver"

# httpx logs every request it makes, with its URL, at INFO. That client is this
# harness, not the server, and a request path in a log line is exactly what the
# log-silence suites exist to catch — so silence the harness rather than let it
# grade the server. The server imports no HTTP client: httpx is a test-only
# dependency and this logger does not exist in production.
logging.getLogger("httpx").disabled = True


class AsgiClient:
    """A synchronous facade over `httpx.AsyncClient` on the composed application.

    Synchronous on purpose. asgiref runs thread-sensitive work — which is every
    ORM unit of work — in the thread that called `async_to_sync`, so a request
    uses the test's own connection, sees the test's uncommitted rows, and lands
    in the counter `django_assert_num_queries` installed. An async test would
    push the ORM onto a second thread with a second connection and see none of
    that.

    Each call runs with the FastAPI lifespan entered. `ASGITransport` never
    enters it, and `async_to_sync` builds a fresh event loop for each call, so
    nothing the lifespan holds may outlive one call.

    `reraise` is the transport's own default and stays on: an unhandled failure
    reaching the test is what keeps a `500` from being mistaken for a passing
    request. Turn it off only to read the `500` body itself, which is the one
    thing the default hides.
    """

    def __init__(self, transport_app, lifespan_app, reraise=True):
        self._client = httpx.AsyncClient(
            transport=ASGITransport(app=transport_app, raise_app_exceptions=reraise),
            base_url=BASE_URL,
        )
        self._lifespan_app = lifespan_app

    async def _request(self, method, url, **kwargs):
        async with self._lifespan_app.router.lifespan_context(self._lifespan_app):
            return await self._client.request(method, url, **kwargs)

    def request(self, method, url, **kwargs):
        return async_to_sync(self._request)(method, url, **kwargs)

    def get(self, url, **kwargs):
        return self.request("GET", url, **kwargs)

    def post(self, url, **kwargs):
        return self.request("POST", url, **kwargs)

    def put(self, url, **kwargs):
        return self.request("PUT", url, **kwargs)

    def delete(self, url, **kwargs):
        return self.request("DELETE", url, **kwargs)


def flush_redis():
    """Empty the shared Redis database: the rate counters, the lockout state and
    the presence sets. Through the redis client rather than Django's cache
    framework, which this project keeps off Redis (ADR-0018)."""
    store = redis.Redis.from_url(settings.REDIS_URL)
    try:
        store.flushdb()
    finally:
        store.close()


@pytest.fixture(autouse=True)
def flush_redis_state():
    """Rate-limit counters live in the shared Redis instance, so without this they
    leak between tests and across whole runs (the login scope is 20/hour)."""
    flush_redis()
    yield


@pytest.fixture
def http():
    """Drives every route of this API through the whole composed stack: the
    middleware, the FastAPI routes, and the Django admin behind them."""
    return AsgiClient(application, api_application)


@pytest.fixture
def new_http():
    """A client factory, for a race test that drives the surface from threads.

    One `AsgiClient` holds one `httpx.AsyncClient`, and `async_to_sync` builds a
    fresh event loop for each call in the thread that made it, so a client shared
    across threads would carry connections bound to a loop that is already gone.
    Each thread builds its own, and its ORM work then runs on that thread, against
    that thread's own database connection.
    """
    return lambda: AsgiClient(application, api_application)


@pytest.fixture
def active_user(db):
    """An account the owner has already activated."""
    return User.objects.create_user(username="alice", password=PASSWORD, is_active=True)


@pytest.fixture
def device(active_user):
    """A live device for `active_user`, enough to mint full-scope tokens."""
    return Device.objects.create(
        user=active_user,
        ik_pub=b"ik-public",
        spk_id=1,
        spk_pub=b"spk-public",
        spk_sig=b"spk-signature",
        registration_id=1001,
    )


@pytest.fixture
def bearer():
    """`Authorization` for a full-scope token bound to `device`."""

    def build(user, device):
        access, _refresh = issue_full(user, device)
        return {"Authorization": f"Bearer {access}"}

    return build


@pytest.fixture
def register_bearer():
    """`Authorization` for the short-lived token whose only power is adding a
    device."""

    def build(user):
        return {"Authorization": f"Bearer {issue_register_scope(user)}"}

    return build


@pytest.fixture
def bob(db):
    """A second activated account, for the tests that need two."""
    return User.objects.create_user(username="bob", password=PASSWORD, is_active=True)
