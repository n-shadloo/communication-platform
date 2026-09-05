# 0004. The WebSocket gateway fans out over Redis publish and subscribe

- Status: Accepted
- Phase: 2
- Date: 2026-09-03
- Landed: 2026-09-04, in the fourth run of phase 2. `/ws` is a Starlette WebSocket
  route of the FastAPI application, `realtime/bus.py` is the fan-out, and Channels,
  its Redis layer and `CHANNEL_LAYERS` are gone.

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

The frame protocol, the frame limits and the close codes stay exactly as
`backend/realtime/API.md` states them. A shutdown closes every socket with `1012`.

**Superseded in part by [0020](0020-one-android-client-and-no-browser-surface.md).**
This decision named `4001` and `4403` among those codes. Both left with the browser
surface: the gateway authenticates the upgrade request and has no unauthenticated
state to close, and there is no Origin policy to refuse against. `4003`, `4008` and
`1012` are unchanged.

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

## The subscription strategy, and its cost

Each worker subscribes and unsubscribes per topic — on a bind, a room join and a room
leave — rather than holding one pattern subscription and filtering locally.

The pattern costs one command for the life of the process and none afterwards, which
is the cheaper side of the trade at the control plane. It loses on the data plane, and
the common case is what decides it: a live push to a device with no socket is a whole
envelope blob, up to a base64 bucket, and under a pattern subscription Redis carries
that blob to every worker so each can discard it. Under a per-topic subscription Redis
drops it server-side, because `PUBLISH` to a channel with no subscribers reaches
nobody.

What per-topic costs instead: a registry of topic to sockets in each worker, and one
Redis round trip on each bind, room join and room leave. That is connection-lifecycle
rate, not frame rate — at band 0, a handful of commands per socket for its whole life.
A bind also waits for the `SUBSCRIBE` confirmation before it returns, because redis-py
sends the command without reading its reply and a publish that lands in that window is
dropped by a server that does not yet hold the subscription; on the revocation path
that window is a socket outliving its own token.

The flip: if the topic count per worker ever grows past what one subscription
connection handles comfortably, or churn becomes frame-rate rather than
connection-rate, the pattern subscription is the fallback and the local registry is
already the thing that would filter it.

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
