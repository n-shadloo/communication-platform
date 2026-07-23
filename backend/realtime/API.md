# realtime API — the `/ws` gateway

One WebSocket endpoint carries everything live: instant envelope delivery, volatile
device-to-device signals, presence, and ephemeral room traffic. Frames are JSON text
objects in both directions — binary frames are a protocol violation. Nothing relayed
here is persisted or logged; the durable message queue (see `messaging/API.md`) is
the source of truth, and this socket only makes it fast.

**URL:** `wss://<host>/ws`

## Connection and authentication

Two handshake paths:

- **Native clients** send `Authorization: Bearer <access token>` on the upgrade
  request. A valid full-scope, device-bound token accepts the connection; anything
  else closes with **4001** immediately after accept.
- **Browsers** cannot set WebSocket headers: connect bare, then send an `auth` frame
  as the first message. The server allows ten seconds; an unauthenticated socket that
  sends any other frame, presents a bad token, or lets the deadline pass closes with
  **4001**.

The token is validated with the same strength as REST: signature and expiry, `full`
scope (a register-scope token opens no socket), a live device whose
`token_generation` matches, and an active account. On success the socket joins the
device's delivery group and the device's `last_active_date` is touched (day
precision).

If the server is configured with an Origin allowlist (`ALLOWED_WS_ORIGINS`, required
in production), a handshake presenting an Origin header not on the list is closed
with **4403**. A handshake with no Origin header at all is allowed — native clients
send none, and the header is only a browser cross-site defense.

### `auth` (client → server)

```json
{ "type": "auth", "access": "eyJhbGciOiJIUzI1NiIs…" }
```

Valid only as the first frame of a bare connection. Success is silent; the next
frames are processed normally. Failure closes 4001.

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

Undecodable JSON, non-object JSON, and binary frames close 4008. Frames with an
unknown `type` are ignored (but still count against the rate limit). Malformed but
well-typed frames — a bad UUID, an oversized blob, a wrong-typed field — are silently
dropped without closing the socket, matching the volatile, fire-and-forget semantics.

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

Joins the live session of an existing room: the socket enters the room's relay
group, every subscriber (including this one) receives a `room_presence` join, and the
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

| Code | Meaning |
|---|---|
| 4001 | Authentication failed: bad/expired/register-scope token, revoked device, inactive account, missed auth deadline, or a frame before authentication |
| 4003 | The device was revoked or its account deactivated while connected |
| 4008 | Protocol violation: binary frame, oversized frame, undecodable or non-object JSON, or rate cap exceeded |
| 4403 | Origin header present but not on the server's allowlist |

After 4003 the token is dead; reconnecting requires a fresh login on another device.
After 4001 the client should refresh its access token and reconnect.
