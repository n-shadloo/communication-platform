"""The pure-ASGI middleware, from the outside in.

Pure ASGI rather than `BaseHTTPMiddleware`: that class runs the rest of the
application in a task of its own, which breaks the cancellation a deadline
depends on and breaks context propagation for everything below it.

The order is trusted host, request deadline, body cap, response headers, then
the thread-sensitive context that every ORM unit of work runs inside.
"""

import json
from collections import namedtuple

import anyio
from asgiref.sync import ThreadSensitiveContext

# Set on every response this surface produces: every one of them carries either
# ciphertext or a token, and neither may be written to a cache. The headers a
# browser reads and a native client ignores — `X-Content-Type-Options` and
# `Referrer-Policy` — left with the web target (ADR-0020); Django's own
# `SecurityMiddleware` still sets them on the admin path, which an operator does
# open in a browser.
RESPONSE_HEADERS = ((b"cache-control", b"no-store"),)

Limits = namedtuple("Limits", "body_bytes deadline_seconds")


async def _send_envelope(send, status, code, detail):
    body = json.dumps({"code": code, "detail": detail}).encode()
    headers = [
        (b"content-type", b"application/json"),
        (b"content-length", str(len(body)).encode()),
        *RESPONSE_HEADERS,
    ]
    await send({"type": "http.response.start", "status": status, "headers": headers})
    await send({"type": "http.response.body", "body": body})


class TrustedHost:
    """Refuse a `Host` header that `ALLOWED_HOSTS` does not list.

    Without it an unvalidated `Host` reaches every absolute address the process
    builds. The match is exact and case-insensitive with the port removed; `*`
    allows any host, as it does in Django.
    """

    def __init__(self, app, allowed_hosts):
        self.app = app
        self.allow_any = "*" in allowed_hosts
        self.allowed = {host.lower() for host in allowed_hosts}

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or self.allow_any:
            await self.app(scope, receive, send)
            return
        header = dict(scope["headers"]).get(b"host", b"").decode("latin-1")
        if header.rsplit(":", 1)[0].lower() not in self.allowed:
            await _send_envelope(
                send, 400, "invalid_request", {"host": ["Unknown host."]}
            )
            return
        await self.app(scope, receive, send)


class RequestDeadline:
    """Bound every request. No ASGI server sets a handler timeout, so without
    this a stuck query holds its connection and its thread until the client
    gives up, and under load the stuck handlers take the whole process."""

    def __init__(self, app, limits_for):
        self.app = app
        self.limits_for = limits_for

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started = False

        async def watched_send(message):
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            with anyio.fail_after(self.limits_for(scope["path"]).deadline_seconds):
                await self.app(scope, receive, watched_send)
        except TimeoutError:
            # A second response start is a protocol fault, so a deadline that
            # fires after the headers went out can only propagate.
            if started:
                raise
            await _send_envelope(
                send, 503, "unavailable", "The request exceeded its deadline."
            )


class BodyCap:
    """Refuse a body above the cap of its route, counted as the server delivers
    it. The `Content-Length` header is not the measurement: a client that
    understates or omits it defeats every check that reads the header."""

    def __init__(self, app, limits_for):
        self.app = app
        self.limits_for = limits_for

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        cap = self.limits_for(scope["path"]).body_bytes
        received = 0
        over = False
        started = False

        async def counted_receive():
            nonlocal received, over
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > cap:
                    over = True
                    # A disconnect, not an exception: FastAPI wraps anything
                    # raised while it reads a body into a 400 of its own, so an
                    # exception here would be reported as a malformed body
                    # rather than an oversized one.
                    return {"type": "http.disconnect"}
            return message

        async def capped_send(message):
            nonlocal started
            if over:
                return  # the application's answer to a body it never received
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        await self.app(scope, counted_receive, capped_send)
        if over and not started:
            await _send_envelope(
                send, 413, "payload_too_large", "Request body is too large."
            )


class ResponseHeaders:
    """Add each header the response does not already carry. Only-if-absent
    keeps one owner per header while the Django catch-all still answers for
    half the surface and sets some of them itself."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def headed_send(message):
            if message["type"] == "http.response.start":
                headers = message.setdefault("headers", [])
                present = {name.lower() for name, _value in headers}
                headers.extend(
                    (name, value)
                    for name, value in RESPONSE_HEADERS
                    if name not in present
                )
            await send(message)

        await self.app(scope, receive, headed_send)


class ThreadSensitive:
    """Give each request its own thread-sensitive context, so the units of work
    of one request share one thread and one connection, and two requests do not
    serialize behind each other."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        async with ThreadSensitiveContext():
            await self.app(scope, receive, send)
