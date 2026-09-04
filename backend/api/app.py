"""The composed FastAPI application, with the Django application behind it.

FastAPI serves the routes of `core`, `accounts`, `vault` and `messaging`. Every
other path — the admin, and the REST Framework routes of the apps that have not
moved — falls through to the Django ASGI application. Run 05 empties that
fall-through.
"""

from contextlib import asynccontextmanager

from django.conf import settings
from fastapi import FastAPI

from accounts.routes import anonymous as accounts_anonymous
from accounts.routes import authenticated as accounts_authenticated
from api import errors
from api.middleware import (
    BodyCap,
    Limits,
    RequestDeadline,
    SecurityHeaders,
    ThreadSensitive,
    TrustedHost,
)
from api.ratelimit import close_client
from core.routes import router as core_router
from messaging.routes import router as messaging_router
from vault.routes import router as vault_router

API_PREFIX = "/api/v1"


def build_limits():
    """The body cap and the deadline of each route class.

    The listed routes carry the cap their own contract admits. Everything else
    takes the transition class, whose 70 MiB is what nginx admits today: the
    Django catch-all still serves a 64 MiB attachment, and a `messaging` batch is
    far above the JSON class in its own right — 256 envelopes of 256 KiB. That
    route is bounded by the batch cap and the base64 cap its schema declares, and
    it takes a byte cap of its own in run 05, where changing one is a contract
    change with somewhere to be recorded.
    """
    json_class = Limits(settings.BODY_CAP_JSON_BYTES, settings.REQUEST_DEADLINE_SECONDS)
    backup_class = Limits(
        settings.BODY_CAP_BACKUP_BYTES, settings.REQUEST_DEADLINE_SECONDS
    )
    transition_class = Limits(
        settings.BODY_CAP_UPLOAD_BYTES, settings.UPLOAD_DEADLINE_SECONDS
    )
    per_route = {
        f"{API_PREFIX}/health": json_class,
        f"{API_PREFIX}/auth/register": json_class,
        f"{API_PREFIX}/auth/login": json_class,
        f"{API_PREFIX}/auth/refresh": json_class,
        f"{API_PREFIX}/auth/logout": json_class,
        f"{API_PREFIX}/users": json_class,
        f"{API_PREFIX}/me/profile": json_class,
        f"{API_PREFIX}/me/keybackup": backup_class,
    }

    def limits_for(path):
        return per_route.get(path, transition_class)

    return limits_for


@asynccontextmanager
async def lifespan(app):
    """Release what the process holds when the server sends a shutdown.

    Nothing is built here. During the transition daphne serves the process, and
    daphne never sends the lifespan messages, so anything built at startup would
    be absent on every production request; `api.ratelimit.get_client` builds the
    Redis client on first use instead.
    """
    try:
        yield
    finally:
        await close_client()


def create_app(django_app):
    app = FastAPI(
        title="communication platform",
        version="v1",
        lifespan=lifespan,
        # The schema and the two documentation routes describe every route and
        # every payload of a server whose posture is to reveal nothing. ADR-0008
        # makes `manage.py openapi` the way the document is produced.
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )
    errors.install(app)
    app.include_router(core_router, prefix=API_PREFIX)
    app.include_router(accounts_anonymous, prefix=API_PREFIX)
    app.include_router(accounts_authenticated, prefix=API_PREFIX)
    app.include_router(vault_router, prefix=API_PREFIX)
    app.include_router(messaging_router, prefix=API_PREFIX)
    # The Django application is the router's `default`, not a mount at "/". A
    # mount matches every path, so it would answer before the wrong-method 405 of
    # a route that HAS moved; `default` runs only when no route matched at all.
    app.router.default = django_app
    # A mismatched trailing slash is a 404, never a redirect: the redirect
    # rebuilds an absolute address from the scope path and drops any prefix the
    # proxy stripped.
    app.router.redirect_slashes = False
    return app


def wrap(app):
    """The middleware stack, from the outside in."""
    limits_for = build_limits()
    stack = ThreadSensitive(app)
    stack = SecurityHeaders(stack)
    stack = BodyCap(stack, limits_for)
    stack = RequestDeadline(stack, limits_for)
    return TrustedHost(stack, settings.ALLOWED_HOSTS)
