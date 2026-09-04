# 0014. Process hardening at the edge

- Status: Accepted
- Phase: 2
- Date: 2026-09-03
- Landing: 2026-09-04, in the first run of phase 2. The trusted-host check, the
  request deadline, the per-route body cap and the security headers are in place as
  pure-ASGI middleware. The uvicorn flags arrive with uvicorn.

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

No CORS policy exists; the web client is served from the API origin.

## Position fields

- **Forcing function.** One process on 1 GB of RAM has no headroom for an
  unbounded body or a request that never ends, and no second host to fail over
  to.
- **Scale band.** Band 0, holding through band 2.
- **Flip trigger.** A browser client is served from an origin other than the API
  origin. A CORS policy then becomes necessary, and its absence stops being a
  simplification.
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
- The middleware is pure ASGI rather than a framework middleware so that the
  deadline covers the WebSocket handshake and the admin mount as well, not only
  FastAPI routes.
- The body cap is per route, not global. nginx's `client_max_body_size 70m`
  covers the largest attachment bucket; a route that accepts a 1 KB JSON body
  must not inherit that ceiling.
