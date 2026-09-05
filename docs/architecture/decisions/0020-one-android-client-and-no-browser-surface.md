# 0020. One Android client, and no browser surface on the server

- Status: Accepted
- Phase: 6
- Date: 2026-09-05
- Landed: 2026-09-05, in the first run of phase 6. The `/ws` gateway has one
  handshake path, the Origin allowlist and `core.E003` are gone, the two
  browser-only response headers and `Content-Disposition` are gone, and the schema
  and documentation routes are unregistered in every mode.

## Context

The product is one Flutter application for Android. The client at `frontend/`
implements registration, enrollment, cross-signing, direct messaging, history
transfer, background delivery and notifications against this server, and it does
so through `dart:io`: a `SecurityContext` that trusts the provisioned private CA,
and an `Authorization: Bearer` header on the `/ws` upgrade. It sends no `Origin`
header, reads no `X-Content-Type-Options`, honours no `Referrer-Policy`, and never
hands a response to a rendering engine that a `Content-Disposition` could steer.

The server was nevertheless built to serve a browser as well, and carried a second
implementation of its own front door to do it. A socket could connect with no
credential at all, be accepted, and then authenticate in band with an `auth` frame
inside ten seconds — because a browser cannot set a header on a WebSocket
handshake. That path is the whole of the gateway's unauthenticated state: a
deadline task, a rebind branch in the frame handler, an `authed` flag, and a close
code (`4001`) that exists to say "the socket I already accepted may not stay". The
`Origin` allowlist and its deploy check (`core.E003`) exist for the same client:
Origin is a browser cross-site defence, a native attacker forges any value, and the
allowlist therefore had to admit an absent header — so on the one client that
exists it decided nothing.

An accepted-then-unauthenticated socket is not free. It is memory, a task group and
a timer that any unauthenticated caller can hold for ten seconds, on one process
with 1 GB of RAM ([0003](0003-one-asgi-process.md)), and it is the one state in
this system where a connection exists without a principal behind it.

## Decision

The product is one Android application. The server keeps no browser-only surface.

- **One handshake path.** `/ws` authenticates the upgrade request with the
  `Authorization: Bearer` header. A bad header or no header refuses the handshake
  before the accept. The bare-connect path, the `auth` frame, the ten-second
  deadline and close code `4001` leave. Every accepted socket is bound to a device.
- **No Origin policy.** `ALLOWED_WS_ORIGINS`, the deploy check `core.E003` and
  close code `4403` leave.
- **No CORS policy**, as before ([0014](0014-process-hardening-at-the-edge.md)).
  None is added.
- **Two response headers leave the API**: `X-Content-Type-Options` and
  `Referrer-Policy`. `Cache-Control: no-store` stays on every response.
  `Content-Disposition` leaves the attachment download; `Cache-Control: private,
  no-store` and `X-Accel-Redirect` stay.
- **The admin panel keeps every header Django's `SecurityMiddleware` sets**, and
  the nginx `/static/` location keeps `nosniff`. The operator uses a browser.
- **No schema route and no interactive documentation, in any mode**, `DEBUG`
  included: `/openapi.json`, `/docs`, `/docs/oauth2-redirect` and `/redoc` are
  unregistered. `python manage.py openapi` still writes `backend/openapi.json` from
  the same generator, and the committed document is the only reference.
- **nginx serves no client bundle.** `= /` keeps answering 404.

## Position fields

- **Forcing function.** The one client is a Flutter application for Android with a
  Rust core behind FFI. Every removed surface exists for a browser, and each is a
  second code path that no test of the real client exercises. The socket path is
  more than dead weight: it is an accepted connection with no principal, held by an
  unauthenticated caller for ten seconds, on a process with 1 GB of RAM.
- **Scale band.** Band 0, holding through band 2. Nothing here scales with traffic;
  it is one less state to hold per connection.
- **Flip trigger.** A second client that cannot set a header on the connection it
  opens — in practice a browser build of the client, since that is the constraint
  that produced the removed path. It would need the in-band authentication frame
  back, and with it the Origin allowlist that a browser client makes meaningful,
  the two response headers, and a CORS decision. `frontend/`'s preserved post-v1
  web foundation is the thing that would fire this; it is not a plan.
- **Cost.** A browser can no longer open a socket against this server at all, and
  a browser build of the client is now a server change and not only a client one.
  The web foundation the client kept is dead until this decision is reversed. The
  attachment download no longer tells a browser to save rather than render — which
  is correct for the one client and is exactly what a browser would need back.
- **Evidence.** Measured, 2026-09-05: the Flutter client authenticates the `/ws`
  upgrade with an `Authorization: Bearer` header through `dart:io`, and `dart:io`
  attaches no `Origin` header — which is why `_origin_allowed` had to return true
  for an absent header, and therefore why the allowlist decided nothing for the one
  client that exists. `realtime/tests/test_server.py` drives a real uvicorn and
  observes `403 Forbidden` for a refused upgrade, so a client has no close code to
  read on that path either way. **Currency:** current.

## Consequences

- Supersedes in part [0004](0004-websocket-gateway-on-redis-pubsub.md), whose
  decision named close codes `4001` and `4403`. The rest of it — the Starlette
  route, the Redis fan-out, `4003`, `4008`, `1012` — stands unchanged.
- Supersedes in part [0008](0008-fastapi-generates-the-openapi-document.md), whose
  decision closed the documentation routes outside `DEBUG`. They are now closed in
  every mode. Generation, the drift gate and the `API.md` files are unchanged, and
  the committed artefact is now the only published form of the contract.
- [0014](0014-process-hardening-at-the-edge.md) keeps its decision. Its flip
  trigger — a browser client served from an origin other than the API origin — is
  moot while this decision holds, and its note that `ALLOWED_WS_ORIGINS` is the
  socket's only origin control is now that the socket has none.
- The gateway has no unauthenticated state, so `realtime/tests/test_auth.py` proves
  the refusal at the handshake rather than a state machine after it, and the
  `4008`-on-an-unauthenticated-socket case in `realtime/tests/test_limits.py` has no
  subject left.
- `CLIENT_WORK.md` at the repository root carries the client half. The server
  cannot remove a file under `frontend/`, and the web target is not gone from the
  product until the client developer does.
- `backend/CLIENT_CONTRACT.md` §O is the binding client-side statement of the one
  handshake path, and `API_CHANGES.md` carries every observable removal.
