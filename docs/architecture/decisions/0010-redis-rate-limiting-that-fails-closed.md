# 0010. Redis rate limiting that fails closed

- Status: Accepted
- Phase: 2
- Date: 2026-09-03

## Context

Rate limiting today is DRF's `ScopedRateThrottle` over the Django cache, which is
Redis. DRF leaves with [0002](0002-fastapi-as-the-only-http-api-surface.md), so
the counters need a new home.

Two properties constrain the replacement. Counters are volatile data, and
invariant 7 keeps volatile data off disk — so a database table is not available.
And the process count is not fixed: `WEB_CONCURRENCY` can rise, so an in-process
counter would silently multiply the effective limit by the worker count.

The remaining question is what happens when Redis is unreachable. Failing open
keeps the service up and removes the limit; failing closed refuses traffic.

## Decision

Redis holds the counters. The scopes and the `THROTTLE_*` environment variables
keep their names, defaults and `N/period` syntax. An authenticated request counts
per user id; an anonymous request counts per client address. `429` answers with
code `throttled` and a `Retry-After` header.

When Redis is unreachable, a throttled route fails closed with `503` and code
`unavailable`.

## Position fields

- **Forcing function.** A counter in process memory is per worker, and a counter
  on disk violates the volatile-data rule.
- **Scale band.** Band 0, holding through band 2.
- **Flip trigger.** A second application host appears, and the client address
  stops identifying a caller because every request arrives from one proxy.
- **Cost.** Redis becomes a hard dependency of every throttled route, so its loss
  is an outage by choice rather than a degradation. Registration and login are
  the routes that carry the most weight in that trade.
- **Evidence.** Failing closed is the standard posture for a control whose whole
  purpose is to refuse traffic; failing open turns a cache outage into an open
  door on exactly the routes an attacker wants. Redis is already a hard
  dependency of the gateway, so this adds no new single point of failure.
  **Currency:** current.

## Consequences

- The environment variables do not change, so no deployment is re-tuned by this
  decision.
- `503 unavailable` is a distinct signal from `429 throttled`. A client must
  treat them differently: one is backoff, the other is an outage.
- Keeping the counters keyed on user id for an authenticated request means the
  limit follows the account across devices, which is the intent at this band.
- `X-Forwarded-For` is trusted only from `127.0.0.1`, per
  [0014](0014-process-hardening-at-the-edge.md). Without that, the anonymous
  counter is trivially evaded by a spoofed header.
