"""The pure-ASGI limits, driven directly.

One process on 1 GB of RAM has no headroom for an unbounded body or a request
that never ends, and no second host to fail over to. Each middleware is driven
here over `scope`, `receive` and `send`, because that is the layer it works at:
an oversized body has to be caught as the server delivers it, and a deadline has
to be able to answer before the response starts.
"""

import json
from unittest import mock

import anyio
import pytest
from django.conf import settings
from django.db import OperationalError
from fastapi.routing import iter_route_contexts
from psycopg_pool import PoolTimeout

from api.app import route_limits
from api.middleware import (
    SECURITY_HEADERS,
    BodyCap,
    Limits,
    RequestDeadline,
    SecurityHeaders,
    ThreadSensitive,
    TrustedHost,
)
from config.asgi import api_application
from core.buckets import ATTACHMENT_BUCKETS
from core.tests.test_route_table import DOCUMENTATION
from devices.models import Device

CAP = Limits(body_bytes=16, deadline_seconds=0.05)


def limits_for(_path):
    return CAP


def http_scope(host=b"testserver", path="/api/v1/health"):
    return {
        "type": "http",
        "method": "POST",
        "path": path,
        "headers": [(b"host", host)],
        "client": ("127.0.0.1", 4242),
    }


def reader(status=200, headers=(), delay=0):
    """An application that drains the body, then answers."""

    async def app(scope, receive, send):
        while True:
            message = await receive()
            if message["type"] != "http.request" or not message.get("more_body"):
                break
        if delay:
            await anyio.sleep(delay)
        await send(
            {"type": "http.response.start", "status": status, "headers": list(headers)}
        )
        await send({"type": "http.response.body", "body": b"{}"})

    return app


async def drive(app, scope, chunks):
    sent = []
    pending = list(chunks)

    async def receive():
        return pending.pop(0) if pending else {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    await app(scope, receive, send)
    start = next(m for m in sent if m["type"] == "http.response.start")
    body = b"".join(m.get("body", b"") for m in sent if m["type"] == "http.response.body")
    return start["status"], dict(start["headers"]), body


def one_body(payload):
    return [{"type": "http.request", "body": payload, "more_body": False}]


class TestTrustedHost:
    async def test_a_listed_host_passes(self):
        app = TrustedHost(reader(), ["testserver"])

        status, _headers, _body = await drive(app, http_scope(), one_body(b""))

        assert status == 200

    async def test_the_port_is_not_part_of_the_match(self):
        app = TrustedHost(reader(), ["testserver"])

        status, _headers, _body = await drive(
            app, http_scope(host=b"testserver:8000"), one_body(b"")
        )

        assert status == 200

    async def test_an_unlisted_host_is_refused_with_the_envelope(self):
        app = TrustedHost(reader(), ["testserver"])

        status, _headers, body = await drive(
            app, http_scope(host=b"evil.example"), one_body(b"")
        )

        assert status == 400
        assert json.loads(body)["code"] == "invalid_request"

    async def test_a_wildcard_allows_anything(self):
        app = TrustedHost(reader(), ["*"])

        status, _headers, _body = await drive(
            app, http_scope(host=b"anything"), one_body(b"")
        )

        assert status == 200


class TestRequestDeadline:
    async def test_a_request_inside_the_deadline_is_untouched(self):
        app = RequestDeadline(reader(), limits_for)

        status, _headers, _body = await drive(app, http_scope(), one_body(b""))

        assert status == 200

    async def test_a_request_past_the_deadline_is_refused(self):
        app = RequestDeadline(reader(delay=CAP.deadline_seconds * 10), limits_for)

        status, _headers, body = await drive(app, http_scope(), one_body(b""))

        assert status == 503
        assert json.loads(body)["code"] == "unavailable"

    async def test_a_scope_that_is_not_http_carries_no_deadline(self):
        """A WebSocket is a long-lived connection by design, and the lifespan has
        no request to bound."""
        seen = []

        async def app(scope, receive, send):
            seen.append(scope["type"])

        wrapped = RequestDeadline(app, limits_for)
        await wrapped({"type": "lifespan"}, None, None)

        assert seen == ["lifespan"]


class TestBodyCap:
    async def test_a_body_at_the_cap_passes(self):
        app = BodyCap(reader(), limits_for)

        status, _headers, _body = await drive(
            app, http_scope(), one_body(b"x" * CAP.body_bytes)
        )

        assert status == 200

    async def test_a_body_above_the_cap_is_refused(self):
        app = BodyCap(reader(), limits_for)

        status, _headers, body = await drive(
            app, http_scope(), one_body(b"x" * (CAP.body_bytes + 1))
        )

        assert status == 413
        assert json.loads(body)["code"] == "payload_too_large"

    async def test_the_bytes_are_counted_across_chunks(self):
        """The `Content-Length` header is not the measurement: a client that
        understates or omits it defeats every check that reads the header. Each
        chunk here is under the cap and the total is over it."""
        chunks = [
            {"type": "http.request", "body": b"x" * 10, "more_body": True},
            {"type": "http.request", "body": b"x" * 10, "more_body": False},
        ]
        app = BodyCap(reader(), limits_for)

        status, _headers, body = await drive(app, http_scope(), chunks)

        assert status == 413
        assert json.loads(body)["code"] == "payload_too_large"


class TestSecurityHeaders:
    async def test_every_header_is_added(self):
        app = SecurityHeaders(reader())

        _status, headers, _body = await drive(app, http_scope(), one_body(b""))

        for name, value in SECURITY_HEADERS:
            assert headers[name] == value

    async def test_a_header_the_response_already_carries_is_left_alone(self):
        """One owner per header: the Django application behind the catch-all sets
        some of these itself, and a browser reads a duplicated header as two
        policies."""
        app = SecurityHeaders(reader(headers=[(b"cache-control", b"max-age=60")]))

        _status, headers, _body = await drive(app, http_scope(), one_body(b""))

        assert headers[b"cache-control"] == b"max-age=60"
        assert headers[b"x-content-type-options"] == b"nosniff"


class TestThreadSensitiveContext:
    async def test_each_request_runs_in_a_context_of_its_own(self):
        """Two requests must not serialize behind one shared ORM thread."""
        from asgiref.sync import SyncToAsync

        seen = []

        async def app(scope, receive, send):
            seen.append(SyncToAsync.thread_sensitive_context.get(None))
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b""})

        wrapped = ThreadSensitive(app)
        await drive(wrapped, http_scope(), one_body(b""))
        await drive(wrapped, http_scope(), one_body(b""))

        assert all(context is not None for context in seen)
        assert seen[0] is not seen[1]


@pytest.mark.django_db(transaction=True)
class TestThroughTheWholeStack:
    def test_every_response_carries_the_security_headers(self, http):
        response = http.get("/api/v1/health")

        assert response.headers["x-content-type-options"] == "nosniff"
        assert response.headers["cache-control"] == "no-store"
        assert response.headers["referrer-policy"] == "no-referrer"

    def test_an_unlisted_host_never_reaches_a_route(self, http):
        response = http.get("/api/v1/health", headers={"Host": "evil.example"})

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"


class TestTheRouteLimitTable:
    """Which cap and which deadline each route takes. Both are contract: a body
    between two caps is a `413` that used to reach the route, and a deadline is the
    point a slow request becomes a `503`."""

    def test_every_route_the_api_serves_names_a_class(self):
        """A route missing from the table takes the fallback in silence, and the
        fallback is 16 KiB — small enough to refuse a legal prekey batch.

        The documentation routes are the exception the table records rather than
        carries: they read no body, they exist only under `DEBUG`, and the
        fallback is the right class for a GET that takes none.
        """
        per_route, _fallback = route_limits()
        served = {
            context.path
            for context in iter_route_contexts(api_application.routes)
            if context.methods is not None and context.path not in DOCUMENTATION
        }

        assert served == set(per_route)

    def test_no_documentation_route_names_a_class_of_its_own(self):
        per_route, _fallback = route_limits()

        assert DOCUMENTATION & set(per_route) == set()

    def test_the_gateway_is_the_one_route_outside_the_table(self):
        """A body cap counts a request body and a deadline bounds a request; a
        socket has neither, and both middlewares pass a websocket scope through
        untouched. What bounds the socket instead is the gateway's own frame cap,
        rate cap, send-queue bound and authentication deadline."""
        per_route, _fallback = route_limits()
        outside = {
            context.path
            for context in iter_route_contexts(api_application.routes)
            if context.methods is None
        }

        assert outside == {"/ws"}
        assert "/ws" not in per_route

    def test_the_upload_route_takes_the_largest_bucket_plus_the_wrapper(self):
        per_route, _fallback = route_limits()
        limits = per_route["/api/v1/attachments"]

        assert limits.body_bytes == (
            max(ATTACHMENT_BUCKETS) + settings.MULTIPART_OVERHEAD_BYTES
        )
        assert limits.deadline_seconds == settings.UPLOAD_DEADLINE_SECONDS

    def test_a_path_no_route_claims_takes_the_smallest_class(self):
        """Only the admin, and the static files in development, reach it."""
        _per_route, fallback = route_limits()

        assert fallback.body_bytes == settings.BODY_CAP_JSON_BYTES
        assert fallback.deadline_seconds == settings.REQUEST_DEADLINE_SECONDS


def test_an_exhausted_connection_pool_is_reported_as_unavailable(
    http, active_user, device, bearer, monkeypatch
):
    """A pool with no free connection is saturation, not a defect. Reported as a
    `500` the client stops; reported as a `503` it retries, which is the same
    answer the rate limiter gives when Redis is gone.

    The pool is not the binding constraint at the measured service times — sixty
    concurrent drains through a pool of one all returned `200` — but a burst of
    maximum-size sends holds sixteen connections for as long as their inserts take,
    and the pool's ten-second timeout fires inside the fifteen-second deadline.
    """
    exhausted = OperationalError("connection pool exhausted")
    exhausted.__cause__ = PoolTimeout("couldn't get a connection after 10.00 sec")

    with mock.patch.object(Device.objects, "select_related", side_effect=exhausted):
        response = http.get("/api/v1/me/envelopes", headers=bearer(active_user, device))

    assert response.status_code == 503
    assert response.json()["code"] == "unavailable"


def test_any_other_operational_failure_stays_a_server_error(
    http, active_user, device, bearer
):
    """Django wraps every psycopg `OperationalError` in one class. A dropped
    connection or a deadlock is not saturation, and telling a client to retry
    would be telling it the wrong thing."""
    with mock.patch.object(
        Device.objects,
        "select_related",
        side_effect=OperationalError("server closed the connection unexpectedly"),
    ):
        response = http.get("/api/v1/me/envelopes", headers=bearer(active_user, device))

    assert response.status_code == 500
    assert response.json()["code"] == "server_error"
