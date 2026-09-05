# 0014. Process hardening at the edge

- Status: Accepted
- Phase: 2
- Date: 2026-09-03
- Landed: 2026-09-04, in the fourth run of phase 2. The trusted-host check, the
  request deadline, the per-route body cap and the security headers are in place as
  pure-ASGI middleware, and `ops/systemd/chat.service` carries the uvicorn flags.

## Context

[0003](0003-one-asgi-process.md) puts the whole API, the admin and every
WebSocket connection in one process on a host with 1 vCPU and 1 GB of RAM. One
unbounded request body, or one request that never finishes, is enough to take
that process down. There is no second host to absorb it.

The process sits behind nginx on loopback, which means two things must be
decided explicitly: which forwarded headers to believe, and from whom.

## Decision

uvicorn runs with `--proxy-headers`, `--forwarded-allow-ips 127.0.0.1` and
`--no-access-log`.

A pure-ASGI middleware sets a deadline on every HTTP request. Every route has an
explicit body cap equal to the largest payload its contract admits. The trusted
host list is `ALLOWED_HOSTS`.

No CORS policy exists. There is no browser client to need one.

## Position fields

- **Forcing function.** One process on 1 GB of RAM has no headroom for an
  unbounded body or a request that never ends, and no second host to fail over
  to.
- **Scale band.** Band 0, holding through band 2.
- **Flip trigger.** A browser client is served from an origin other than the API
  origin. A CORS policy then becomes necessary, and its absence stops being a
  simplification. Moot while
  [0020](0020-one-android-client-and-no-browser-surface.md) holds: the product is
  one Android application, so the trigger cannot fire without reversing that
  decision first.
- **Cost.** A deadline can cut a legitimate slow request, and a body cap is one
  more contract detail that must stay true as payload sizes change. Both fail
  closed, which is the intent.
- **Evidence.** Trusting forwarded headers only from the proxy's own address is
  uvicorn's documented posture, and the default of trusting `127.0.0.1` is what
  `--forwarded-allow-ips` exists to pin. The single-origin argument against a
  CORS policy is standard. **Currency:** current.

## Consequences

- `--no-access-log` is not a performance choice. Invariant 6 forbids a request
  path in a log line, and an access log is a request path in a log line.
- The `--forwarded-allow-ips 127.0.0.1` pin is what makes the anonymous rate
  limit of [0010](0010-redis-rate-limiting-that-fails-closed.md) meaningful.
  Without it a client sets its own `X-Forwarded-For` and every anonymous counter
  is per-header rather than per-caller.
- The middleware is pure ASGI rather than a framework middleware so that it covers
  the admin mount as well, not only FastAPI routes. Each of the five passes a
  websocket scope straight through, which is load-bearing rather than incidental: a
  request deadline on a long-lived socket would cancel it, and the body cap's counting
  `receive` would turn a websocket frame into `http.disconnect`. What bounds the
  socket instead lives in `realtime/gateway.py` — the frame cap, the rate cap and
  the send-queue bound. The consequence to hold in mind is that `ALLOWED_HOSTS` is
  not checked on a handshake, and since
  [0020](0020-one-android-client-and-no-browser-surface.md) removed
  `ALLOWED_WS_ORIGINS` the socket has no origin control at all — what refuses a
  handshake is the bearer token and nothing else.
- The body cap is per route, not global. nginx's `client_max_body_size 70m`
  covers the largest attachment bucket; a route that accepts a 1 KB JSON body
  must not inherit that ceiling.
