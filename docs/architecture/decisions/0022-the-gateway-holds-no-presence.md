# 0022. The gateway holds no presence

- Status: Accepted
- Phase: 7
- Date: 2026-09-05
- Landed: 2026-09-05, in phase 7. `subscribe_presence`, the `presence` server
  frame, `PRESENCE_TARGETS_MAX`, the announcement on the subscription and on
  disconnect, and `bus.announce_presence` are gone, and a `signal` blob is now
  base64 of exactly one `SIGNAL_BUCKETS` length.

## Context

The gateway carried presence. A client sent a `subscribe_presence` frame naming up
to `PRESENCE_TARGETS_MAX` device ids — 500 of them; the connection held that set
for its life; and the gateway published a `presence` frame to every device in it
the moment the subscription arrived, and again in the cleanup that runs on every
exit path of the socket. `bus.announce_presence` was the fan-out.

That set is a contact list the client declares to the server. It is exactly "the
devices this device watches", named on the wire and held in the process, which is
the class of thing [0001](0001-pairwise-double-ratchet-group-fan-out.md) removed
from group messaging and [0021](0021-relayed-webrtc-mesh-and-no-server-room.md)
removed from voice: state on the server that describes who talks to whom. It was
also the only frame the gateway composed out of its own knowledge. Everything else
it sends it relays: an envelope from a mailbox, a signal from another device.

The server needs none of it. Who is in a conversation is the client's knowledge —
the client already holds the member devices, because it encrypts to each of them
one at a time — and presence between those devices is one more thing they can tell
each other over the channel they already use for join, leave and query
announcements.

The `signal` blob had a ceiling rather than a bucket. `SIGNAL_MAX` admitted any
string up to its value, 16 384 characters by default, and never asked whether that
string was base64 of anything. So on the one path where the server handles a
ciphertext it does not store, the length of that ciphertext was the client's to
choose, and nothing held a client to the padding rule that governs every ciphertext
at rest.

## Decision

The gateway relays acknowledgements and bucketed signals, and holds no presence.

1. It handles `ack` and `signal` from the client and emits `envelope` and
   `signal`. There is no other frame in either direction.
2. `subscribe_presence`, the `presence` server frame, `PRESENCE_TARGETS_MAX`, the
   announcement on the subscription and on disconnect, and `bus.announce_presence`
   leave. The cleanup on every exit path is the unsubscription of the socket's own
   topic and nothing else.
3. Presence between the members of a conversation is client protocol, carried over
   `signal` frames exactly as the join, the leave and the query announcements of
   [0021](0021-relayed-webrtc-mesh-and-no-server-room.md) are.
   `backend/CLIENT_CONTRACT.md` §N is the binding statement of it.
4. A `signal` blob is standard base64 that decodes to exactly one of
   `SIGNAL_BUCKETS` in `core/buckets.py` — 1024, 4096 or 16384 bytes. A blob
   outside that rule drops the frame in silence, exactly like every other
   malformed but well-typed frame: no close code and no error frame.
5. The bucket rule is a malformed-input guard and never a security control. A
   modified server relays anything, and no client may rely on it. What it buys is
   length uniformity on the one ciphertext this server relays without storing —
   the property the buckets of `core/fields.py` buy at rest, applied to the one
   place that lacked it.
6. `SIGNAL_MAX` leaves, as a setting and as an environment variable. The bound on
   a blob is derived rather than configured: `gateway.SIGNAL_BLOB_MAX` is the
   base64 length of the largest bucket, 21 848 characters, and a longer blob is
   refused on its length alone rather than decoded first. `WS_MAX_FRAME`, the
   hundred frames of a rolling second, the 256-frame send queue and the close
   codes `4003`, `4008` and `1012` are unchanged.

## Position fields

- **Forcing function.** A presence subscription is a contact list the client
  declares to the server, and the server needs none of it. The gateway derived
  nothing from that set except which sockets to tell about its own socket, which
  is a fact the two clients can exchange themselves over a frame the server
  already relays and cannot read.
- **Scale band.** Band 0, holding through band 2. Nothing here scales with
  traffic. What it removes for each connection is a set of up to 500 device ids,
  and what it removes on each subscription and each disconnect is one frame for
  every one of them.
- **Flip trigger.** A client surface that needs server-derived presence for a set
  of devices it cannot enumerate itself. A client that can name the devices can
  ask them.
- **Cost.** A client that wants presence implements it itself: an announcement to
  each member device over `signal`, so it pays a fan-out for each conversation
  member where it used to pay one subscribe frame, and it pays that again whenever
  the set changes. The server can no longer tell a client that a peer went
  offline, so a client learns it from its own timeout — later than the socket knew
  it, and not at all for a peer it never addressed. The bucket rule costs the
  client padding: an announcement of a few dozen bytes travels as 1024, and an
  offer that will not pad down to 16384 has no frame to travel in.
- **Evidence.** Verified on 2026-09-05: the one client sends no
  `subscribe_presence` frame today.
  `frontend/lib/features/networking/infrastructure/realtime/dio_websocket_gateway.dart`
  parses the inbound `presence` frame and validates the outbound subscription, and
  no code under `frontend/lib` constructs one. The client's own notes say the
  same and say why it matters:
  `frontend/lib/app/dependencies/messaging_providers.dart` keeps the presence
  projection with no consumer on purpose, because the subscription is never sent,
  and `frontend/lib/features/messaging/presentation/chat_conversation_view.dart`
  records that the chat header's presence claim was structurally false for that
  reason — every peer read as offline forever, including one holding a live socket.
  So the removal costs the one client that exists nothing today. The fan-out it
  removes was measured before it left: 500 frames in one pipelined round trip,
  2.7 ms and 0.2 MB of peak resident set
  ([`../GROUND-TRUTH.md`](../GROUND-TRUTH.md) §4). **Currency:** current.

## Consequences

- Supersedes in part [0004](0004-websocket-gateway-on-redis-pubsub.md). Its
  decision froze the frame protocol as `backend/realtime/API.md` then stated it,
  and `subscribe_presence` and `presence` were two of those frames; its context
  named presence as one of the two things Redis was already a hard dependency for.
  The rest of it stands unchanged: the Starlette route, the per-topic subscription,
  the Redis fan-out and the close codes `4003`, `4008` and `1012`.
- `bus.publish_many` has one caller with more than one topic left, the batch send.
  Its 1 MiB pipeline budget is unchanged, because the send was always the larger of
  the two fan-outs it was sized against.
- The per-connection state of a socket is now the outbox of 256 frames and the
  rate window. `presence_targets` at 500 was the third of the three the phase-6
  security review recorded, and it is gone.
- `backend/realtime/API.md` loses the `subscribe_presence` client frame, the
  `presence` server frame and the 500-target row of the frame-limits table, and
  states the bucket rule in their place. `API_CHANGES.md` carries all three as
  observable changes: the two removals, and the bucket rule as a breaking change
  for any client that sent an arbitrary string.
- What the gateway sees of a call is now which device signals which device, at one
  of three lengths. That is the visibility
  [0021](0021-relayed-webrtc-mesh-and-no-server-room.md) already records, with the
  length made uniform. It stays below the live-root bar, and `backend/SECURITY.md`
  states it there.
