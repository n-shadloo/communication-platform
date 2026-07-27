# Product requirements

## Product statement

Communication Platform is the working name for a private, self-hosted chat application
for a small circle of friends. It provides direct messages, invite-only groups, and
standalone voice rooms without a foreign runtime dependency. The final name and logo are
placeholders and do not block engineering.

## Supported platforms

- Android is a first-class native target.
- The web client supports current common versions of Chrome, Firefox, Edge, and other
  standards-compliant browsers.
- iOS, Windows, macOS, and Linux applications are out of scope.
- The interface supports English and Persian from the first release, including RTL,
  mixed-direction message text, and localized dates.

## Release scope

The first production release includes the complete screen inventory in
[ui-specification.md](ui-specification.md): authentication, encryption onboarding, chat
list, search, contacts, DMs, groups, voice rooms, profiles and safety numbers, Saved
Messages, settings, linked devices, recovery, and all referenced dialogs and states.

The implementation may be delivered in vertical milestones, but an incomplete milestone
is not called the production release.

## Privacy invariants

- The server MUST never receive message, profile, group, room, attachment, or media
  plaintext or a content-encryption key.
- The client MUST NOT use FCM, APNs, foreign analytics, CDNs, remote fonts, remote
  scripts, or public connectivity probes.
- Search is local only.
- Login passwords and recovery secrets are distinct in storage, behavior, and wording.
- Cross-signing master keys are verified out of band before messaging; unsigned devices,
  master-key changes, and device-log forks fail closed.
- New direct-message sessions use hybrid X25519 + ML-KEM-768 without silent classical
  downgrade, and groups require the reviewed, production-approved suite defined by the
  [PQ MLS profile](mls-profile.md).
- Delete-for-everyone, ephemeral room text, and recovery limitations are described
  honestly and never as guarantees.
- Logs and diagnostics MUST exclude plaintext, identifiers, tokens, keys, ciphertext
  bodies, URLs carrying capabilities, and attachment metadata.

## Functional behavior

- The local database is the UI source of truth.
- Cached Android conversations remain readable offline; sends enter a durable outbox.
- The web client is primarily an online session. A suspended or closed tab is not
  presented as capable of reliable message delivery.
- A message received from REST and WebSocket is displayed once.
- Multi-device delivery includes every live peer device and the sender's other devices.
- The server stores no history. Message history remains on client devices and a new
  device receives it only through an encrypted transfer from an existing online device.
- The recovery backup restores cross-signing identity material, not message history,
  ratchets, MLS epochs, or authorization.
- A mailbox `pruned_through` gap is a blocking recovery state; potentially affected MLS
  memberships are removed and re-added with a fresh Welcome.
- Revoked devices lose tokens, queued content, local session access, and future group
  access.
- Voice is audio-only and uses the self-hosted LiveKit and TURN deployment.

## Non-functional requirements

- Smooth scrolling and stable anchoring with long histories.
- Responsive phone, tablet, and wide-web layouts.
- Keyboard, pointer, touch, screen-reader, large-text, RTL, dark-mode, and high-contrast
  support.
- Deterministic recovery after process death at every send/receive transaction boundary.
- Reproducible builds with pinned dependencies and an offline-capable build cache.
- No release while a required security, protocol, accessibility, or migration gate is
  failing.

## Known platform limits

- Android background messaging uses best-effort local polling only. There is no
  always-on messaging socket or foreign push; delayed delivery is expected under Doze,
  force-stop, or OEM restrictions. A foreground service is used only while voice audio
  is actively connected.
- A closed browser cannot maintain the application WebSocket. Messages remain in the
  backend's durable device queue until the user returns.
- A server able to replace the web bundle can attack future browser sessions. CSP and
  reproducible artifacts reduce risk but cannot give the web client the same trust
  boundary as a pinned native binary.
