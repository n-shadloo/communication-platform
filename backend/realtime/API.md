# realtime API — the `/ws` gateway

One WebSocket endpoint carries everything live: instant envelope delivery, volatile
device-to-device signals, presence, and ephemeral room traffic. Frames are JSON text
objects in both directions — binary frames are a protocol violation. Nothing relayed
here is persisted or logged; the durable message queue (see `messaging/API.md`) is
the source of truth, and this socket only makes it fast.

Delivery between sockets is Redis publish and subscribe, which holds a message only
for the instant it takes to hand it to whoever is connected. A frame published for a
device that is mid-reconnect is dropped, and the client's next REST drain is what
recovers it — which is why the queue, not this socket, is the contract for delivery.

**URL:** `wss://<host>/ws`

## Connection and authentication

One handshake path. Send `Authorization: Bearer <access token>` on the upgrade
request. A valid full-scope, device-bound token accepts the connection; anything
else — a bad token, or no header at all — **refuses the handshake**: the server
answers the upgrade request with `403 Forbidden` and no WebSocket is ever
established. There is no close code to read, because the refusal is decided before
the accept and there is no socket to send one on. Treat a failed handshake as
"refresh the access token and reconnect".

The token is validated with the same strength as REST: signature and expiry, `full`
scope (a register-scope token opens no socket), a live device whose
`token_generation` matches, and an active account. On success the socket subscribes
to the device's delivery topic and the device's `last_active_date` is touched (day
precision).

Every accepted socket is therefore already bound to a device: there is no
unauthenticated state, no in-band authentication frame and no deadline to meet.
`auth` is not a frame type, and one sent on a live socket is ignored like any other
unknown type.

## Frame limits

| Limit | Value | On violation |
|---|---|---|
| Frame encoding | JSON text object | close 4008 |
| Frame size | `WS_MAX_FRAME` (default 524288 bytes) | close 4008 |
| Message rate | 100 frames per rolling second | close 4008 |
| `signal` / `room_signal` blob | `SIGNAL_MAX` (default 16384 chars) | frame dropped |
| `ack` ids | ≤ 200 | frame dropped |
| `subscribe_presence` targets | ≤ 500 | frame dropped |
| Room subscriptions per socket | 100 | subscribe dropped |
| Undelivered server frames queued for one socket | 256 | close 4008 |

Undecodable JSON, non-object JSON, and binary frames close 4008. Frames with an
unknown `type` are ignored (but still count against the rate limit). Malformed but
well-typed frames — a bad UUID, an oversized blob, a wrong-typed field — are silently
dropped without closing the socket, matching the volatile, fire-and-forget semantics.

The last row is backpressure rather than a frame the client sent. Server frames for a
socket that is not reading them are held in a bounded queue; past the bound the socket
is a slow consumer and is closed 4008. Read continuously, and treat a 4008 with no
preceding protocol error as a signal to reconnect and drain over REST.

## Client → server messages

### `ack`

```json
{ "type": "ack", "ids": ["e4f8a1c2-9b3d-4e5f-8a70-6c1d2e3f4a5b"] }
```

Deletes the named envelopes from this device's durable queue, exactly like
`POST /api/v1/me/envelopes/ack`. 1–200 UUIDs. Ids outside this device's mailbox match
nothing. No reply frame; the deletion is idempotent.

### `signal`

```json
{ "type": "signal", "to_device": "2a77d4b9-e611-4c0f-9f1c-6a2e3b7d4e0f", "blob": "kzXhc…" }
```

Volatile relay of an opaque string to one device. Delivered as a `signal` frame to
every live socket of the target device; dropped silently if the target is offline.
`blob` ≤ `SIGNAL_MAX` characters. The relayed frame does not name the sender — the
sender identifies itself inside the ciphertext if the protocol needs it.

### `subscribe_presence`

```json
{ "type": "subscribe_presence", "device_ids": ["2a77d4b9-e611-4c0f-9f1c-6a2e3b7d4e0f"] }
```

Replaces this socket's presence-target set (≤ 500 device UUIDs; invalid entries are
skipped) and immediately announces `online` to every target. The same targets are
told `offline` when this socket disconnects. Presence flows only toward devices the
client explicitly listed; an empty list means nobody is told anything.

### `room_subscribe`

```json
{ "type": "room_subscribe", "room_id": "7c1d2e3f-4a5b-6c7d-8e9f-0a1b2c3d4e5f" }
```

Joins the live session of an existing room: the socket subscribes to the room's
relay topic, every subscriber (including this one) receives a `room_presence` join, and the
device is added to the room's live-count set. Subscribing to a nonexistent room or
past the 100-room cap is silently ignored; re-subscribing to a held room re-announces
join and stays allowed.

### `room_leave`

```json
{ "type": "room_leave", "room_id": "7c1d2e3f-4a5b-6c7d-8e9f-0a1b2c3d4e5f" }
```

Leaves the live session: subscribers receive a `room_presence` leave and the live
count drops. Disconnecting leaves every subscribed room the same way without an
explicit frame.

### `room_signal`

```json
{ "type": "room_signal", "room_id": "7c1d2e3f-4a5b-6c7d-8e9f-0a1b2c3d4e5f", "blob": "cmFuZG9t…" }
```

Relays an opaque blob (ephemeral room text or state, encrypted client-side) to every
subscriber of a room this socket has itself subscribed to — knowing a room id is not
enough. `blob` ≤ `SIGNAL_MAX` characters. Never persisted; a device that was offline
never sees it.

## Server → client messages

### `envelope`

```json
{ "type": "envelope", "id": "e4f8a1c2-9b3d-4e5f-8a70-6c1d2e3f4a5b", "seq": 12, "blob": "kzXhc…" }
```

Live push of a queued envelope the moment it is accepted for this device. The same
envelope remains in the durable queue until acked, so a client may receive it here
and again on its next REST drain; deduplicate by `id`.

### `signal`

```json
{ "type": "signal", "blob": "kzXhc…" }
```

A volatile signal relayed from some device. Carries no sender field.

### `presence`

```json
{ "type": "presence", "device_id": "9f1c6a2e-3b7d-4e0f-8c15-2a77d4b9e611", "state": "online" }
```

A device this socket was named in a `subscribe_presence` list came online
(`"online"`) or its socket closed (`"offline"`).

### `room_signal`

```json
{ "type": "room_signal", "room_id": "7c1d2e3f-4a5b-6c7d-8e9f-0a1b2c3d4e5f", "blob": "cmFuZG9t…" }
```

An ephemeral room blob relayed to every subscriber, the sender included. Carries the
room id and blob only.

### `room_presence`

```json
{
  "type": "room_presence",
  "room_id": "7c1d2e3f-4a5b-6c7d-8e9f-0a1b2c3d4e5f",
  "device_id": "9f1c6a2e-3b7d-4e0f-8c15-2a77d4b9e611",
  "state": "join"
}
```

A device joined (`"join"`) or left (`"leave"`) a room this socket subscribes to.
Leave fires on explicit `room_leave` and on disconnect.

## Close codes

| Code | Meaning | What the client does |
|---|---|---|
| 4003 | The device was revoked or its account deactivated while connected | Stop reconnecting; the token is dead and a fresh login on another device is required |
| 4008 | Protocol violation — binary frame, oversized frame, undecodable or non-object JSON, rate cap exceeded — or a slow consumer whose server-frame queue overflowed | Fix the frame, or read faster; reconnect and drain over REST |
| 1012 | The server is restarting and drained its sockets | Reconnect after a backoff; this is a deploy, not a fault |

**A refused handshake carries no code.** Authentication is decided before the accept,
so a server has no socket to send a close frame on and answers the upgrade request
with `403 Forbidden` instead. A failed handshake therefore means "refused": refresh
the access token and retry. Once a socket has been accepted, every code above arrives
as a close frame.
