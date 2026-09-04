"""The composed FastAPI application, with the Django admin behind it.

FastAPI serves every HTTP route of this API. The Django ASGI application answers
`ADMIN_PATH` and, in development, the static files the admin renders with; a path
that is neither reaches FastAPI's own `not_found`, never a Django 404 page.
"""

from contextlib import asynccontextmanager

from django.conf import settings
from fastapi import FastAPI
from starlette.exceptions import HTTPException

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
from api.redis import close_client
from attachments.routes import router as attachments_router
from config.urls import ADMIN_PATH
from core.buckets import ATTACHMENT_BUCKETS
from core.routes import router as core_router
from devices.routes import authenticated as devices_authenticated
from devices.routes import registration as devices_registration
from messaging.routes import router as messaging_router
from vault.routes import router as vault_router
from voicerooms.routes import router as voicerooms_router

API_PREFIX = "/api/v1"


def build_limits():
    """The body cap and the deadline of each route class.

    Four classes, and every route names one. The JSON class covers a body of a
    few fields; the backup class the one blob an account keeps whole; the batch
    class the `devices` and `messaging` bodies, whose length is a list cap times a
    base64 cap — 200 ML-KEM prekeys at 1184 bytes each, or a 256-item batch of
    256 KiB envelopes — and whose 70 MiB is what nginx admits rather than what
    those schemas could produce, so the largest batch a schema allows is already
    refused. The attachment class is the largest bucket plus the multipart
    wrapper, which is the only body of this API that is bytes rather than JSON.

    A path no route claims takes the JSON class. Only the admin, and the static
    files in development, ever reach it, and Django bounds its own forms below
    that anyway.
    """
    json_class = Limits(settings.BODY_CAP_JSON_BYTES, settings.REQUEST_DEADLINE_SECONDS)
    backup_class = Limits(
        settings.BODY_CAP_BACKUP_BYTES, settings.REQUEST_DEADLINE_SECONDS
    )
    batch_class = Limits(settings.BODY_CAP_BATCH_BYTES, settings.UPLOAD_DEADLINE_SECONDS)
    attachment_class = Limits(
        max(ATTACHMENT_BUCKETS) + settings.MULTIPART_OVERHEAD_BYTES,
        settings.UPLOAD_DEADLINE_SECONDS,
    )
    per_route = {
        f"{API_PREFIX}/health": json_class,
        f"{API_PREFIX}/auth/register": json_class,
        f"{API_PREFIX}/auth/login": json_class,
        f"{API_PREFIX}/auth/refresh": json_class,
        f"{API_PREFIX}/auth/logout": json_class,
        f"{API_PREFIX}/users": json_class,
        f"{API_PREFIX}/users/{{user_id}}/profile": json_class,
        f"{API_PREFIX}/me/profile": json_class,
        f"{API_PREFIX}/me/keybackup": backup_class,
        f"{API_PREFIX}/me/identity": json_class,
        f"{API_PREFIX}/users/{{user_id}}/identity": json_class,
        f"{API_PREFIX}/me/devices": batch_class,
        f"{API_PREFIX}/me/devices/{{device_id}}": json_class,
        f"{API_PREFIX}/me/devices/{{device_id}}/prekeys": batch_class,
        f"{API_PREFIX}/me/devices/{{device_id}}/prekeys/count": json_class,
        f"{API_PREFIX}/me/devicelog": batch_class,
        f"{API_PREFIX}/users/{{user_id}}/devicelog": json_class,
        f"{API_PREFIX}/users/{{user_id}}/devices": json_class,
        f"{API_PREFIX}/users/{{user_id}}/keys/claim": batch_class,
        f"{API_PREFIX}/envelopes": batch_class,
        f"{API_PREFIX}/me/envelopes": batch_class,
        f"{API_PREFIX}/me/envelopes/ack": batch_class,
        f"{API_PREFIX}/attachments": attachment_class,
        f"{API_PREFIX}/attachments/{{attachment_id}}": json_class,
        f"{API_PREFIX}/rooms": json_class,
        f"{API_PREFIX}/rooms/{{room_id}}": json_class,
        f"{API_PREFIX}/rooms/{{room_id}}/token": json_class,
    }

    def limits_for(path):
        return per_route.get(path, json_class)

    return limits_for


def django_paths(django_app):
    """The dispatcher that stands where Starlette's own `not_found` would.

    Django answers `ADMIN_PATH` and, in development, `STATIC_URL`. Every other
    unmatched path raises the same `HTTPException` the router raises for a miss,
    so it renders as this API's `not_found` envelope rather than as Django's HTML
    404 page.
    """
    prefixes = ["/" + ADMIN_PATH.strip("/")]
    if settings.DEBUG:
        prefixes.append("/" + settings.STATIC_URL.strip("/"))

    async def dispatch(scope, receive, send):
        path = scope.get("path", "")
        if scope["type"] == "http" and any(
            path == prefix or path.startswith(prefix + "/") for prefix in prefixes
        ):
            await django_app(scope, receive, send)
            return
        raise HTTPException(status_code=404)

    return dispatch


@asynccontextmanager
async def lifespan(app):
    """Release what the process holds when the server sends a shutdown.

    Nothing is built here. During the transition daphne serves the process, and
    daphne never sends the lifespan messages, so anything built at startup would
    be absent on every production request; `api.redis.get_client` builds the
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
    app.include_router(devices_registration, prefix=API_PREFIX)
    app.include_router(devices_authenticated, prefix=API_PREFIX)
    app.include_router(messaging_router, prefix=API_PREFIX)
    app.include_router(attachments_router, prefix=API_PREFIX)
    app.include_router(voicerooms_router, prefix=API_PREFIX)
    # The Django application is reached through the router's `default`, not a
    # mount at "/". A mount matches every path, so it would answer before the
    # wrong-method 405 of a route this API serves; `default` runs only when no
    # route matched at all.
    app.router.default = django_paths(django_app)
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
