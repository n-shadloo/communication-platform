# Voice and realtime

## Realtime gateway

One application-owned gateway wraps `/ws`. It validates frame type and bounds before
routing typed events. Widgets never send raw JSON. Android authenticates the upgrade
with its bearer header. A future Web client sends the required auth frame first and sends
nothing else until authentication succeeds.

Durable `envelope` frames enter the inbox pipeline and are deduplicated against REST.
`signal`, presence, room signal, and room presence are volatile and expire locally.

The client obeys backend limits: JSON text objects only, maximum frame size, 100 frames
per rolling second, bounded ack/presence lists, signal size, and room subscriptions.
Batching and backpressure prevent locally generated bursts from causing close 4008.

## Voice-room model

A backend room is a capability ID plus an encrypted name and live count. Membership,
invites, and media-key state are authenticated client protocol state. All invited peers
are equal in the product UI; there is no server owner/member table.

Create flow:

1. Generate room metadata key and encrypted name bucket.
2. POST `/api/v1/rooms`.
3. Establish the room's client-side MLS membership state.
4. Send encrypted `room.invite` events containing the capability and Welcome/material.
5. Persist room capability only in protected storage.

Rename and invite actions require valid current room membership even though the backend
capability endpoint cannot enforce it. A malicious capability holder can still call the
backend rename API; clients authenticate accepted metadata updates and surface conflicts
rather than trusting server ciphertext alone.

Room MLS credentials obey the same verified account-master/device-cross-signature and
[PQ MLS production gates](mls-profile.md#production-gates) as group chat. An unsigned,
unverified, forked, or classical-only peer cannot receive room membership/media keys.

Leaving is a client-protocol action, not a backend deletion. The client sends an
authenticated `room.control` leave/removal event, commits the MLS membership change,
disconnects from LiveKit/realtime presence, and deletes its local capability, room keys,
and ephemeral text after the durable transition succeeds. The backend room row persists
and the capability itself cannot be revoked by the current API. Peers ignore future
metadata from a removed credential, and a returning user requires a fresh authenticated
invite. The confirmation dialog states these limits; it never claims that leaving deletes
the server room or erases copies held by others.

## Joining voice

1. Fetch/decrypt room state and subscribe to room realtime presence.
2. POST `/api/v1/rooms/{room_id}/token` with a device-bound full token.
3. Derive the current media-key context from authenticated room MLS state using a
   domain-separated exporter label containing room ID and media epoch.
4. Connect to the returned self-hosted LiveKit URL before token expiry.
5. Enable E2EE before publishing the microphone.
6. Publish audio only; do not enable video or unencrypted data channels.
7. Re-mint a token on reconnect and rotate media keys on membership change.

LiveKit is responsible for WebRTC/SRTP transport and SFU forwarding, not key
distribution. Media keys are never placed in the LiveKit token or sent to the backend,
SFU, or TURN server.

## Media encryption gate

RFC 9605 SFrame is the target framing contract. LiveKit documents E2EE support in its
Flutter SDK on native and web, with additional worker build steps for web. Before the
Android version-1 release, a wire-level spike MUST prove the selected SDK version and
cipher/key-provider behavior meets the project's SFrame/E2EE requirements on Android.
Before a future Web release, the corresponding browser worker behavior must also pass.
If not,
an audited compatible integration is required; ordinary SRTP to the SFU is not accepted
as end-to-end encryption.

## Media-key lifecycle

- Each media epoch has fresh exporter context.
- A participant removal causes an MLS commit and media-key rotation before further audio.
- Per-sender key IDs/counters are unique and replay-checked.
- Old media keys are retained only for a short jitter/reordering window then erased.
- Reconnect never silently falls back to unencrypted media.
- Key failure mutes publishing and shows a blocking encryption error.

## Ephemeral room text

Room text uses authenticated `room_signal` ciphertext and is held in memory only. It is
never appended to history or the durable message queue. Clients drop it when they leave,
when room membership becomes invalid, and when the observed room empties. Wording remains
best-effort because another participant can retain decrypted content.

## Presence and participant state

Room subscription produces device join/leave hints. The LiveKit participant connection
is authoritative for current media tiles; backend `live_count` is a coarse hint and may
lag. Display name/avatar comes from locally authenticated profile state. Speaking and mic
indicators come from local/LiveKit media state and reveal no readable audio to the server.

## Platform lifecycle

- Android uses microphone permission only on explicit join and a microphone/connected
  foreground-service notification while active.
- A future Web client requires secure context and a user gesture for microphone
  permission/audio start.
- Network change enters reconnecting state, stops misleading speaking indicators, and
  never connects to a foreign fallback.
- Minimizing the room keeps audio only when the platform can truthfully maintain it and
  shows the persistent in-app banner.

## Primary references

- [Realtime API](../../backend/realtime/API.md)
- [Voice rooms API](../../backend/voicerooms/API.md)
- [RFC 9605: SFrame](https://www.rfc-editor.org/info/rfc9605)
- [LiveKit encryption overview](https://docs.livekit.io/transport/encryption/)
- [LiveKit Flutter SDK E2EE reference](https://docs.livekit.io/reference/client-sdk-flutter/)
