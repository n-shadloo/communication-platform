# 0004. The WebSocket gateway fans out over Redis publish and subscribe

- Status: Accepted
- Phase: 2
- Date: 2026-09-03

## Context

Real-time delivery today is Channels 4 on Daphne with `channels_redis` as the
channel layer. [0002](0002-fastapi-as-the-only-http-api-surface.md) and
[0003](0003-one-asgi-process.md) remove Daphne and make FastAPI the root
application, so the consumer stack has to move regardless.

Channels brings a routing layer, a consumer class hierarchy and a second Redis
client to do what this system needs in one sentence: deliver a frame to the
sockets of one device, wherever they are connected. Redis is already a hard
dependency for rate counters and presence.

The wire contract is already published in `backend/realtime/API.md` and a client
is being written against it. The contract survives the transport change; the
framework does not.

## Decision

The `/ws` gateway is a Starlette WebSocket route inside the FastAPI application.
Fan-out between processes uses Redis publish and subscribe through
`redis.asyncio`, with one subscription connection for each worker process.
Channels and its Redis layer leave.

The frame protocol, the frame limits and the close codes `4001`, `4003`, `4008`
and `4403` stay exactly as `backend/realtime/API.md` states them. A shutdown
closes every socket with `1012`.

## Position fields

- **Forcing function.** Channels' Redis layer is a second framework and a second
  Redis client for a fan-out the system already needs Redis for, and Channels is
  built around a server this deployment no longer runs.
- **Scale band.** Band 0, holding through band 2. At most 500 concurrent sockets
  at the stated population.
- **Flip trigger.** Fan-out needs a delivery guarantee that publish and subscribe
  does not give — replay after a subscriber restart, or an acknowledgement that
  the frame arrived.
- **Cost.** The gateway owns its own group registry, heartbeats and drain, which
  Channels supplied. Redis publish and subscribe drops a message for a subscriber
  that is not connected at that instant: a device that is mid-reconnect misses
  the frame and must fall back to the REST queue.
- **Evidence.** Redis publish and subscribe is the mechanism `channels_redis`
  itself uses for a group send, so the delivery semantics are unchanged by the
  move. `redis.asyncio` is the maintained async client inside redis-py.
  **Currency:** current.

## Consequences

- `channels`, `channels_redis` and `daphne` leave `requirements/prod.txt`;
  `CHANNEL_LAYERS` leaves the settings.
- The durable path is unaffected. `messaging.QueuedEnvelope` remains the source
  of truth for an envelope, and the socket is an optimisation over it — which is
  what `realtime/tests/test_durable.py` already asserts.
- One subscription connection for each worker means the Redis connection count
  tracks `WEB_CONCURRENCY`.
- `1012` on shutdown gives the client a documented reconnect signal, so a deploy
  does not look like a network failure.
