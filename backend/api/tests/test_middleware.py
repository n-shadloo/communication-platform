"""The pure-ASGI stack, at the layer it works at.

`core/tests/test_request_limits.py` holds the table — which cap and which
deadline each route class takes — and the normal path of each middleware. What is
left, and what this file covers, is the rest of the surface each one presents: the
scopes it must not touch, the headers its own refusal carries, and the two states
it can reach after a response has already started, where a wrong answer is a
protocol fault rather than a status code.
"""

import json

import anyio
import pytest

from api.middleware import (
    RESPONSE_HEADERS,
    BodyCap,
    Limits,
    RequestDeadline,
    ResponseHeaders,
    ThreadSensitive,
    TrustedHost,
)

CAP = Limits(body_bytes=16, deadline_seconds=0.05)
REGISTER_URL = "/api/v1/auth/register"
JSON_CAP = 16 * 1024  # BODY_CAP_JSON_BYTES, the class every JSON route takes


def limits_for(_path):
    return CAP


def http_scope(host=b"testserver", headers=None):
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/health",
        "headers": [(b"host", host)] if headers is None else headers,
        "client": ("127.0.0.1", 4242),
    }
    return scope


def one_body(payload):
    return [{"type": "http.request", "body": payload, "more_body": False}]


async def drive(app, scope, chunks):
    """Run one request and return every message the application sent."""
    sent = []
    pending = list(chunks)

    async def receive():
        return pending.pop(0) if pending else {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    await app(scope, receive, send)
    return sent


def answer_of(sent):
    start = next(m for m in sent if m["type"] == "http.response.start")
    body = b"".join(m.get("body", b"") for m in sent if m["type"] == "http.response.body")
    return start["status"], dict(start["headers"]), body


def reader(status=200):
    """An application that drains the body, then answers."""

    async def app(scope, receive, send):
        while True:
            message = await receive()
            if message["type"] != "http.request" or not message.get("more_body"):
                break
        await send({"type": "http.response.start", "status": status, "headers": []})
        await send({"type": "http.response.body", "body": b"{}"})

    return app


class TestTheRefusalsTheStackWritesItself:
    """Two responses never pass through a route, so nothing else can give them
    the headers every other response of this surface carries."""

    @pytest.mark.parametrize(
        "build, scope, chunks, status, code",
        [
            (
                lambda: TrustedHost(reader(), ["testserver"]),
                http_scope(host=b"evil.example"),
                one_body(b""),
                400,
                "invalid_request",
            ),
            (
                lambda: BodyCap(reader(), limits_for),
                http_scope(),
                one_body(b"x" * (CAP.body_bytes + 1)),
                413,
                "payload_too_large",
            ),
        ],
        ids=["unknown host", "oversized body"],
    )
    async def test_the_envelope_is_complete_and_correctly_framed(
        self, build, scope, chunks, status, code
    ):
        sent = await drive(build(), scope, chunks)

        answered, headers, body = answer_of(sent)
        assert answered == status
        assert json.loads(body)["code"] == code
        assert headers[b"content-type"] == b"application/json"
        assert int(headers[b"content-length"]) == len(body)
        for name, value in RESPONSE_HEADERS:
            assert headers[name] == value

    async def test_the_refusal_bodies_never_echo_what_was_refused(self):
        """An unknown `Host` and an oversized body are both client input, and no
        error body of this surface repeats client input back."""
        secret = b"x" * (CAP.body_bytes + 1)

        host_refusal = answer_of(
            await drive(
                TrustedHost(reader(), ["testserver"]),
                http_scope(host=b"leak.example"),
                one_body(b""),
            )
        )
        body_refusal = answer_of(
            await drive(BodyCap(reader(), limits_for), http_scope(), one_body(secret))
        )

        assert b"leak.example" not in host_refusal[2]
        assert secret not in body_refusal[2]


class TestTrustedHost:
    async def test_the_match_ignores_case(self):
        sent = await drive(
            TrustedHost(reader(), ["testserver"]), http_scope(host=b"TESTSERVER"), []
        )

        assert answer_of(sent)[0] == 200

    @pytest.mark.parametrize(
        "host",
        [b"", b"nottestserver", b"testserver.evil.example", b"evil.example:80"],
        ids=["absent", "suffix", "prefix", "with a port"],
    )
    async def test_a_host_that_is_not_the_listed_one_is_refused(self, host):
        """The match is the whole name with the port removed, so neither a
        prefix nor a suffix of an allowed host passes, and a request with no
        `Host` at all is refused rather than defaulted."""
        headers = [] if host == b"" else [(b"host", host)]

        sent = await drive(
            TrustedHost(reader(), ["testserver"]), http_scope(headers=headers), []
        )

        assert answer_of(sent)[0] == 400


class TestRequestDeadline:
    async def test_a_deadline_that_fires_after_the_headers_went_out_propagates(self):
        """The rare case, and the only one with no answer: a second
        `http.response.start` is a protocol fault, so the middleware cannot
        render its envelope and must let the failure reach the server."""

        async def slow_after_the_headers(scope, receive, send):
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await anyio.sleep(CAP.deadline_seconds * 20)
            await send({"type": "http.response.body", "body": b"never sent"})

        with pytest.raises(TimeoutError):
            await drive(
                RequestDeadline(slow_after_the_headers, limits_for), http_scope(), []
            )


class TestBodyCap:
    async def test_a_body_exactly_at_the_cap_is_not_refused(self):
        """The boundary is `>`, so the largest legal body is the cap itself."""
        sent = await drive(
            BodyCap(reader(), limits_for), http_scope(), one_body(b"x" * CAP.body_bytes)
        )

        assert answer_of(sent)[0] == 200

    async def test_an_application_that_already_answered_is_cut_off_not_rewritten(self):
        """The rare case: a route that answers before it reads. The cap still
        stops the body, but the response it interrupts has already started, so
        nothing more may be written to the client — not even the envelope."""

        async def answers_first(scope, receive, send):
            await send({"type": "http.response.start", "status": 200, "headers": []})
            while True:
                message = await receive()
                if message["type"] != "http.request" or not message.get("more_body"):
                    break
            await send({"type": "http.response.body", "body": b"served"})

        chunks = [
            {"type": "http.request", "body": b"x" * CAP.body_bytes, "more_body": True},
            {"type": "http.request", "body": b"x", "more_body": False},
        ]

        sent = await drive(BodyCap(answers_first, limits_for), http_scope(), chunks)

        assert [message["type"] for message in sent] == ["http.response.start"]

    async def test_a_message_that_is_not_a_body_chunk_passes_through_the_counter(self):
        """A client that goes away mid-request sends `http.disconnect`, which
        carries no bytes. Counting it, or swallowing it, would leave the handler
        waiting for a body that is never going to arrive."""
        seen = []

        async def watchful(scope, receive, send):
            seen.append(await receive())
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b""})

        await drive(
            BodyCap(watchful, limits_for), http_scope(), [{"type": "http.disconnect"}]
        )

        assert seen == [{"type": "http.disconnect"}]

    async def test_the_route_sees_a_disconnect_rather_than_an_exception(self):
        """Anything raised while FastAPI reads a body becomes its own `400` about
        a malformed body, which is the wrong answer for a body that was simply
        too large."""
        seen = []

        async def watchful(scope, receive, send):
            seen.append(await receive())
            seen.append(await receive())
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b""})

        chunks = [
            {
                "type": "http.request",
                "body": b"x" * (CAP.body_bytes + 1),
                "more_body": True,
            },
            {"type": "http.request", "body": b"", "more_body": False},
        ]

        await drive(BodyCap(watchful, limits_for), http_scope(), chunks)

        assert seen[0] == {"type": "http.disconnect"}


class TestResponseHeaders:
    async def test_a_response_that_carries_no_headers_at_all_still_gets_them(self):
        """`headers` is optional in the ASGI response message, and a `204` is the
        response most likely to omit it."""

        async def no_headers(scope, receive, send):
            await send({"type": "http.response.start", "status": 204})
            await send({"type": "http.response.body", "body": b""})

        sent = await drive(ResponseHeaders(no_headers), http_scope(), [])

        _status, headers, _body = answer_of(sent)
        for name, value in RESPONSE_HEADERS:
            assert headers[name] == value


@pytest.mark.parametrize(
    "build",
    [
        lambda app: TrustedHost(app, ["testserver"]),
        lambda app: RequestDeadline(app, limits_for),
        lambda app: BodyCap(app, limits_for),
        lambda app: ResponseHeaders(app),
        lambda app: ThreadSensitive(app),
    ],
    ids=["trusted host", "deadline", "body cap", "response headers", "thread sensitive"],
)
async def test_a_websocket_scope_reaches_the_gateway_untouched(build):
    """Every one of these bounds a request, and a socket is not one: a cap
    counts a request body, a deadline ends a request, and the headers belong to a
    response the handshake never sends. A middleware that touched the scope would
    break the gateway rather than protect it."""
    sent = []

    async def gateway(scope, receive, send):
        await send({"type": "websocket.accept"})

    async def send(message):
        sent.append(message)

    await build(gateway)({"type": "websocket", "path": "/ws"}, None, send)

    assert sent == [{"type": "websocket.accept"}]


@pytest.mark.django_db(transaction=True)
class TestThroughTheWholeStack:
    def json_of(self, size):
        """A valid registration body padded to exactly `size` bytes.

        Padded with the whitespace JSON allows between tokens rather than with a
        longer password, because the schema bounds every field: a body that is
        over the cap must be refused by the cap, not by a validator.
        """
        head = b'{"username":"bob","password":"a-sufficiently-long-passphrase"'
        tail = b"}"
        return head + b" " * (size - len(head) - len(tail)) + tail

    def test_a_body_at_the_json_cap_reaches_the_route(self, http):
        """The boundary from the outside: at the cap the route answers, so the
        `413` below is the cap and not something else refusing the request."""
        response = http.post(
            REGISTER_URL,
            content=self.json_of(JSON_CAP),
            headers={"content-type": "application/json"},
        )

        assert response.status_code == 201

    def test_one_byte_past_the_cap_is_refused_with_the_envelope(self, http):
        response = http.post(
            REGISTER_URL,
            content=self.json_of(JSON_CAP + 1),
            headers={"content-type": "application/json"},
        )

        assert response.status_code == 413
        assert response.json() == {
            "code": "payload_too_large",
            "detail": "Request body is too large.",
        }
        for name, value in RESPONSE_HEADERS:
            assert response.headers[name.decode()] == value.decode()

    def test_an_oversized_body_never_reaches_the_route(self, http):
        """The point of counting bytes as they arrive: the account is not created
        and the password is never hashed."""
        from accounts.models import User

        http.post(
            REGISTER_URL,
            content=self.json_of(JSON_CAP + 1),
            headers={"content-type": "application/json"},
        )

        assert not User.objects.filter(username="bob").exists()

    def test_an_understated_content_length_does_not_buy_a_larger_body(self, http):
        """The header is not the measurement. httpx sends the real length, so
        this states one that is a lie."""
        response = http.post(
            REGISTER_URL,
            content=self.json_of(JSON_CAP + 1),
            headers={"content-type": "application/json", "content-length": "30"},
        )

        assert response.status_code == 413
