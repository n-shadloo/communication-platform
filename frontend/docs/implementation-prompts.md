# Ordered Codex implementation prompts

Use these prompts sequentially. Start a fresh Codex task for one prompt, review its diff
and verification results, then commit/merge that piece before sending the next prompt.
Do not send the whole file as one implementation request.

Each prompt assumes Codex is opened at the repository root and automatically reads
`frontend/AGENTS.md`. A piece is complete only when its acceptance criteria pass; an
interface or placeholder alone is not completion. If earlier work changed an assumption,
Codex must reconcile the frontend documentation before proceeding.

## Prompt 01 — Flutter project foundation

~~~text
Implement frontend piece 01: Flutter project foundation.

Read and obey frontend/AGENTS.md. Read frontend/docs/README.md,
product-requirements.md, architecture.md, decisions.md, platform-android.md,
platform-web.md, testing-strategy.md, deployment-and-release.md, and
implementation-checklist.md. Inspect the repository and current working tree first.
Treat backend/ as read-only.

Create the production Flutter project under frontend/ for Android and Web. Establish
the package/application identifiers through explicit development and production
configuration without inventing final branding. Add the accepted foundational
dependencies with compatible pinned constraints, strict analysis/lint configuration,
deterministic code generation commands, test directories, asset declarations, and
development/production entry points. Include English and Persian localization plumbing
but do not build product screens yet. Set up CI commands or workflow configuration for
format checking, flutter analyze, unit/widget tests, and Android/Web builds without
requiring foreign runtime services.

Keep the generated project minimal and remove sample counter behavior. Add a small
bootstrap application that visibly distinguishes non-production configuration and can
render on Android and Web. Do not implement networking, persistence, authentication,
crypto, or later features in this piece.

Acceptance criteria: dependencies resolve; generated files are reproducible; no sample
app remains; Android and Web compile; one smoke widget test passes; flutter analyze is
clean; no backend file changes. Update only the checklist entries actually completed.
Report commands and results, and stop after piece 01. Do not commit unless asked.
~~~

## Prompt 02 — Architecture skeleton

~~~text
Implement frontend piece 02: application architecture skeleton.

Read and obey frontend/AGENTS.md. Read architecture.md, decisions.md,
local-data-model.md, testing-strategy.md, and the current implementation. Confirm piece
01 is complete before editing. Treat backend/ as read-only.

Create the feature-first Clean Architecture skeleton described by the docs. Establish
app, core, shared, and feature boundaries; domain entities/value objects; application
use-case conventions; repository/port interfaces; infrastructure adapter locations;
presentation view-state conventions; and Riverpod dependency composition. Add a typed
Result/failure model that can distinguish transport, authentication, validation,
security, storage, unsupported-protocol, and cancellation failures without leaking raw
backend messages into UI.

Add dependency-boundary tests or static checks that prevent domain/protocol code from
importing Flutter, Dio, Drift, Forui, Flyer Chat, or platform plugins. Include a small
example use case wired through an in-memory fake and Riverpod test—not a fake product
feature—to prove the dependency direction. Remove the example if it would become
production surface.

Do not implement database schemas, API calls, screens, or cryptography yet. Acceptance
criteria: architecture boundaries compile and are tested; dependency injection has no
global mutable singleton; error types are exhaustive and testable; flutter analyze and
tests pass; no backend changes. Update the implementation checklist accurately and stop
after piece 02.
~~~

## Prompt 03 — Design system and responsive shell

~~~text
Implement frontend piece 03: design system and responsive application shell.

Read and obey frontend/AGENTS.md. Read ui-specification.md, responsive-ui.md,
visual-design-system.md, decisions.md, and testing-strategy.md. Inspect the accepted
piece-01/02 code before choosing APIs. Treat backend/ as read-only.

Implement app-owned design tokens and Forui wrapper components for color, typography,
spacing, radii, elevation, focus, motion, semantic status, dialogs, sheets, buttons,
fields, and loading/error/empty states. Implement light, dark, high-contrast-aware,
English LTR, and Persian RTL foundations using only bundled assets/fonts. Build the
adaptive go_router shell for narrow, medium, and wide layouts with stable route identity,
deep-linkable placeholder destinations, guarded-route hooks, keyboard navigation, focus
restoration, reduced motion, and accessible semantics.

Use Forui's bundled Lucide set through `FLucideIcons`, with no separate general-purpose
icon dependency. Expose it only through a typed app-owned semantic `AppIcons` mapping;
feature screens must not reference package icons directly. Cover icon-only semantic
labels/tooltips, focus and disabled states, target sizes, color-independent meaning, and
intentional RTL mirroring in widget/golden tests.

Create only structural placeholder pages needed to exercise the shell; do not implement
feature screens or package-default visual design. Forui must remain behind app-owned
widgets. Add golden/widget tests for breakpoints, LTR/RTL, large text, keyboard focus,
dark mode, and route preservation during resize.

Acceptance criteria: shell behaves correctly on Android-sized and common browser
viewports; no overflow at supported text scale; no remote assets; tests and analyze pass;
the visual placeholder is explicitly non-shipping. Update the checklist and stop after
piece 03.
~~~

## Prompt 04 — Secure configuration and bootstrap

~~~text
Implement frontend piece 04: secure configuration and platform bootstrap.

Read and obey frontend/AGENTS.md. Read authentication-and-devices.md,
platform-android.md, platform-web.md, threat-model.md, deployment-and-release.md,
ui-specification.md sections 1–3, and backend/core/API.md. Treat all backend files as
read-only.

Implement typed development/production configuration with one provisioned server
origin. Production must not allow arbitrary server entry, certificate bypass, public
connectivity probes, remote configuration, telemetry, or third-party runtime resources.
Implement the bootstrap state machine for configuration loading, protected-storage
availability, local identity/session discovery, backend `/api/v1/health` reachability,
offline eligibility, and routing to connection, login, or the application shell.

Add Android network-security configuration and interfaces for private-CA trust plus
primary/backup SPKI pins. For Web, model the documented prerequisite that the OS/browser
already trusts the private CA; show a blocking provisioning/trust state with no bypass.
Keep concrete secret/provisioning values out of source control. Implement Splash and
Connection UI states with accessible retry behavior and no fake progress.

Use fake trust/reachability/storage ports for deterministic tests. Acceptance criteria:
every bootstrap transition and trust failure is tested; production cannot select another
origin or continue after trust failure; offline routing follows platform rules; analyze
and tests pass; no backend changes. Stop after piece 04.
~~~

## Prompt 05 — Local storage foundation

~~~text
Implement frontend piece 05: secure local storage foundation.

Read and obey frontend/AGENTS.md. Read local-data-model.md, platform-android.md,
platform-web.md, threat-model.md, architecture.md, and testing-strategy.md. Treat backend/
as read-only.

Implement Drift as the sole durable source of truth with the initial versioned schema,
migration framework, transaction helpers, repository base patterns, and reactive
Riverpod projections. Cover the tables and constraints already specified in
local-data-model.md, but do not invent encrypted message schemas beyond the documented
fields. Store sensitive records only as authenticated ciphertext or opaque crypto-core
state handles.

Implement platform adapters for Android Keystore-wrapped database/storage keys and Web
IndexedDB/WebCrypto non-extractable wrapping-key behavior. Web must never persist
decrypted messages, search indexes, filenames, profiles, or room metadata. Add explicit
logout/revocation/wrapping-key-loss wipe flows, bounded cleanup hooks, and migration
failure recovery. Platform APIs must remain behind ports.

Add database tests for constraints, transactions, migrations, wipe behavior, tamper/key
loss, and reactive streams. Acceptance criteria: process restart preserves only allowed
encrypted state; failed transactions do not expose partial projections; Web persistent
records contain no plaintext fixtures; analyze and relevant target tests pass; no backend
changes. Update the checklist and stop after piece 05.
~~~

## Prompt 06 — Networking foundation

~~~text
Implement frontend piece 06: networking and backend-contract foundation.

Read and obey frontend/AGENTS.md. Read backend-api.md and every backend API.md it links,
plus backend/CLIENT_CONTRACT.md and backend/SECURITY.md. Read architecture.md,
authentication-and-devices.md, sync-engine.md, and testing-strategy.md. Backend is
strictly read-only.

Implement one typed Dio REST client, DTO/domain mapping boundaries, request limits,
timeouts, cancellation, safe retries, redacted diagnostics, and the documented error-code
mapping. Implement the access/refresh token coordinator with proactive refresh,
single-flight concurrent refresh, one authenticated retry, logout/revocation handling,
and no token logging. Add the dedicated WebSocket gateway abstraction with authenticated
connect, close-code mapping, reconnect hooks, origin-safe Web behavior, and no business
state stored inside the socket layer.

Generate or hand-write API DTOs according to the repository convention, but do not
invent endpoints or display raw backend detail. Use a mock HTTP server/adapter to test
all status, malformed-body, timeout, cancellation, token-race, retry-safety, size, and
redaction cases. Do not implement feature repositories yet.

Acceptance criteria: DTOs match authoritative contracts; non-idempotent requests are not
automatically replayed; refresh races issue one refresh; logs contain none of the banned
data classes; tests/analyze pass; no backend changes. Update the checklist and stop after
piece 06.
~~~

## Prompt 07 — Shared cryptographic core foundation

~~~text
Implement frontend piece 07: shared Rust cryptographic core foundation.

Read and obey frontend/AGENTS.md. Read cryptographic-protocol.md, mls-profile.md,
threat-model.md, platform-android.md, platform-web.md, decisions.md, and
backend/CLIENT_CONTRACT.md. Treat backend/ as read-only. This is security-critical: do
not improvise primitives or silently weaken a requirement.

Create the shared Rust core and its narrow, versioned Flutter FFI/Android and Web/Wasm
boundary. Establish secret-owning types, zeroization, secure randomness, bounded input
parsing, stable error codes, panic containment, worker/isolate integration, and a testable
provider abstraction. Integrate reviewed maintained libraries for deterministic CBOR,
Ed25519, X25519, ML-KEM-768, Argon2id, XChaCha20-Poly1305, hashing/HKDF, and
secretstream as specified. Dart may pass opaque bytes/handles and orchestrate calls but
must not implement the primitives.

Do not implement PQXDH, Double Ratchet, MLS group state, application message schemas, or
production KeyPackages yet. Pin the Rust toolchain/dependencies and ensure Android and
Wasm builds derive from the same source. Add positive/negative primitive vectors,
malformed-input tests, boundary-size tests, and a Flutter smoke call on both target
interfaces.

Acceptance criteria: secrets never cross the API as loggable debug objects; errors do
not expose inputs; Rust tests, FFI/Wasm smoke tests, Flutter tests, formatting, and analyze
pass. If a reviewed cross-target dependency cannot satisfy the docs, stop and report the
specific blocker rather than substituting an educational implementation. Stop after
piece 07.
~~~

## Prompt 08 — Backend cryptographic vectors

~~~text
Implement frontend piece 08: backend cryptographic encodings and golden vectors.

Read and obey frontend/AGENTS.md. Read cryptographic-protocol.md,
authentication-and-devices.md, testing-strategy.md, backend/CLIENT_CONTRACT.md,
backend/devices/API.md, backend/devices/vectors/README.md, and
backend/devices/vectors/vectors.json. Backend is read-only.

In the shared Rust core, implement the exact canonical encoders and verifiers for
cross_sig, master_sig, spk_sig, and pq_spk_sig. Implement ik_pub as exactly 64 bytes:
Ed25519 public key followed by X25519 public key. Preserve the exact ASCII domains,
four-byte big-endian length prefixes, raw UUID bytes, field order, unsigned version
behavior, and zero-length representation of absent optional PQ fields. Expose only the
minimal typed operations needed by later enrollment/session code.

Import the backend vectors as read-only test fixtures or maintain an automated equality
check against them; do not duplicate hand-edited expected values. Add negative tests for
wrong domain, order, length, UUID encoding, optional-field omission, swapped ik_pub
halves, modified key bytes, wrong signer, and malformed signature. Run the same fixtures
through Android and Web/Wasm builds and assert byte-identical output.

Acceptance criteria: every backend vector reproduces exactly and verifies; every
mutation fails; no encoder exists in Dart; cross-target output is identical; Rust,
Flutter, Android/Wasm tests and analyze pass; no backend changes. Update the checklist
and stop after piece 08.
~~~

## Prompt 09 — Registration and authentication

~~~text
Implement frontend piece 09: account registration and authentication.

Read and obey frontend/AGENTS.md. Read authentication-and-devices.md,
ui-specification.md sections 1–3, backend/accounts/API.md, backend/core/API.md,
platform-android.md, platform-web.md, and testing-strategy.md. Backend is read-only.

Implement account registration, pending-activation, login, refresh/session restoration,
logout, and revoked/expired-session behavior through domain ports, application use cases,
infrastructure repositories, and Riverpod presentation state. Enforce local username and
password validation only for immediate feedback; the backend remains authoritative.
Never add username-existence probing or activation polling. Keep password and recovery
secret concepts, storage, and wording completely separate.

Build the documented responsive Login, Register, and Pending Activation screens using
app-owned design-system components. Map backend errors to reviewed localized English and
Persian messages. Persist credentials only through the secure token adapter, keep access
tokens in memory where practical, and wipe locally even when network logout fails.

This piece ends at a register-scope/full-scope session boundary; do not implement device
registration yet. Add use-case, repository, widget, route-guard, refresh-race, offline,
malformed-response, inactive-account, rate-limit, and revocation tests.

Acceptance criteria: auth flows match the API exactly on Android/Web; no raw backend
detail or secret enters logs/UI; route restoration is deterministic; tests/analyze pass;
no backend changes. Update the checklist and stop after piece 09.
~~~

## Prompt 10 — Two-phase secure device enrollment

~~~text
Implement frontend piece 10: two-phase secure device enrollment and identity recovery.

Read and obey frontend/AGENTS.md. Read authentication-and-devices.md,
cryptographic-protocol.md, ui-specification.md section 4 and section 16,
local-data-model.md, testing-strategy.md, backend/CLIENT_CONTRACT.md section M,
backend/devices/API.md, and backend/vault/API.md. Backend is read-only.

Implement the complete first-device and later-device state machines. Generate/persist
the registration intent and required device keys before POST. Register without
cross_sig/bundle_version, transactionally persist the returned device_id and full-scope
tokens, then finish security through the prekey endpoint using the canonical vectors
from piece 08. First device: publish account identity, cross-sign with bundle_version 1,
upload the recovery-protected identity backup, and append the first device-log record.
Later device: fetch/unwrap the backup with the recovery secret, cross-sign, and append the
device-set change. Keep the device unverified and messaging withheld until completion.

Implement Argon2id/backup AEAD through the Rust core, one-time recovery-secret display,
confirmation, wrong-secret behavior, secure cleanup, and the documented resumable UI
states. Handle process death and ambiguous registration outcomes without placeholder
signatures or uncontrolled duplicate registration; reconcile/revoke orphan unsigned
devices and record device-log changes when possible.

Do not implement message history transfer yet. Add exhaustive state-transition,
response-loss, retry, identity_required, cap, stale-version, invalid-vector, backup,
process-death, Android/Web persistence, and UI tests.

Acceptance criteria: both enrollment flows complete against contract fixtures; every
intermediate device remains withheld; secrets are never retained/logged improperly;
tests/analyze pass; no backend changes. Stop after piece 10.
~~~

## Prompt 11 — Directory, profiles, and identity verification

~~~text
Implement frontend piece 11: user directory, encrypted profiles, and identity
verification.

Read and obey frontend/AGENTS.md. Read product-requirements.md,
authentication-and-devices.md, cryptographic-protocol.md, threat-model.md,
ui-specification.md sections 7, 10, and 11, backend/accounts/API.md, and
backend/devices/API.md. Backend is read-only.

Implement activated-user directory paging/search, cached offline presentation, encrypted
profile fetch/publish, deterministic username-based placeholder avatars, and profile-key
distribution hooks. Unauthenticated/unverified profile data must never replace the
backend username fallback. Implement peer identity fetch, master_sig verification,
device-bundle/prekey verification, ETag refresh, and the client Authentication Service
needed by later messaging.

Build Contacts/New, Contact Profile, Edit Profile, and Safety Number screens. Implement
SAS and QR values over both exact master keys, explicit out-of-band confirmation,
user-signing-key attestation, and persistent verified/change states. Master-key change,
invalid/unsigned device, and device-log fork must block sensitive actions; do not use
TOFU to enable messaging.

Use fake encrypted profile/key distribution until pairwise transport exists, clearly
behind a port and not as production acceptance. Add malicious-server substitution,
pagination, cache, profile-authentication, SAS/QR, key-change, accessibility, RTL, and
widget tests.

Acceptance criteria: presentation identity never outruns cryptographic verification;
blocking states cannot be bypassed; tests/analyze pass; no backend changes. Update the
checklist and stop after piece 11.
~~~

## Prompt 12 — Synchronization engine

~~~text
Implement frontend piece 12: crash-safe synchronization engine.

Read and obey frontend/AGENTS.md. Read sync-engine.md, local-data-model.md,
message-protocol.md, architecture.md, testing-strategy.md, backend/messaging/API.md,
backend/realtime/API.md, backend/CLIENT_CONTRACT.md sections H–L, and platform docs.
Backend is read-only.

Implement durable inbox/outbox workers around Drift transactions. Cover deterministic
per-device batching, exact-ciphertext retry, server acceptance recording, drain paging,
deduplication, contiguous acknowledgements, stale devices, retry scheduling/backoff,
network transitions, and foreground WebSocket hints followed by authoritative REST
drain. Persist all state required to survive process death at every boundary.

Implement pruned_through comparison and the blocking queue-gap recovery state before
potentially dependent MLS content is processed. Implement lifecycle-safe reconnect and
Android best-effort polling interfaces without Firebase or a permanent messaging
foreground service. UI receives immutable connectivity/sync projections only; transport
callbacks never mutate widgets directly.

Use opaque fixture envelopes in this piece; do not implement message encryption or
domain event application yet. Add fault-injection tests at each transaction/network
boundary, >256-recipient batching, duplicate/reordered deliveries, response loss,
seven-day gaps, socket close codes, offline restart, bounded queues, and redaction.

Acceptance criteria: no event is lost or applied twice under the modeled failures;
non-idempotent encryption is never repeated for a retry; tests/analyze pass on both
targets; no backend changes. Stop after piece 12.
~~~

## Prompt 13 — Pairwise encrypted sessions

~~~text
Implement frontend piece 13: hybrid pairwise session establishment and Double Ratchet.

Read and obey frontend/AGENTS.md. Read cryptographic-protocol.md,
authentication-and-devices.md, threat-model.md, sync-engine.md, message-protocol.md,
testing-strategy.md, backend/CLIENT_CONTRACT.md sections C–F and I, and
backend/devices/API.md claim/replenishment contracts. Backend is read-only.

In the shared Rust core, implement the reviewed hybrid X25519 + ML-KEM-768 PQXDH
composition and Double Ratchet state required by the docs. Bind protocol version,
recipient device, ratchet header, and pairwise-transport-v1 purpose as authenticated
data. Reject missing/invalid PQ material with no classical fallback. Enforce one-time
private-key deletion, signed-prekey rotation/retention, skipped-key per-session/account
bounds, replay rejection, authenticated repair state, and transactional persistence.

Implement client prekey generation, upload, counts, replenishment, claims, peer bundle
verification, and atomic signed-prekey/cross_sig/bundle_version rotation. Implement
per-device fan-out to every live peer device and the sender's other devices; the current
device applies locally. Wire encrypted envelopes through the sync engine without yet
building message semantics/UI.

Add published/reference vectors where available, project cross-target vectors,
malicious-bundle/downgrade/replay tests, simultaneous initiation, lost-response retry,
skipped-key limits, rotation overlap, device revocation, Android/Wasm byte equality, and
independent-review readiness artifacts.

Acceptance criteria: no classical path exists; exact ciphertext is reused on ambiguous
transport retry; all security failures fail closed; tests/analyze pass; no backend
changes. Stop after piece 13.
~~~

## Prompt 14 — Messaging domain and local projections

~~~text
Implement frontend piece 14: application-message protocol, conversation domain, and
local projections.

Read and obey frontend/AGENTS.md. Read message-protocol.md, local-data-model.md,
sync-engine.md, cryptographic-protocol.md, product-requirements.md, and
testing-strategy.md. Backend is read-only.

Implement the versioned deterministic-CBOR application envelopes/events and typed domain
state for conversations, text messages, replies, edits, reactions, pins, delivery/read
receipts, typing/presence semantics, delete-for-me, best-effort delete-for-everyone,
drafts, unread state, muting, ordering, and Saved Messages. Enforce authorization,
revision, sender-counter, event-ID, timestamp/clock-skew, replay, duplicate, unsupported
version/kind, and tombstone rules exactly as documented.

Apply decrypted authenticated events only through one Drift transaction that stores the
event marker and updates projections. Create application use cases and Riverpod streams;
do not expose transport/crypto DTOs to UI. Wire sends through the pairwise fan-out and
sync outbox. Unknown future events must be retained safely as unsupported records.

Do not build the final chat timeline yet. Add golden byte fixtures, property tests,
authorization/mutation tests, event-order permutations, duplicate/replay tests,
transaction-failure injection, Saved Messages behavior, and cross-target equality.

Acceptance criteria: projections are deterministic under every delivery order; local
optimistic state reconciles without lying about delivery; no plaintext enters logs;
tests/analyze pass; no backend changes. Stop after piece 14.
~~~

## Prompt 15 — Chat interface

~~~text
Implement frontend piece 15: production direct-message and Saved Messages interface.

Read and obey frontend/AGENTS.md. Read ui-specification.md chat/search-related sections,
responsive-ui.md, visual-design-system.md, architecture.md UI boundary,
message-protocol.md, and testing-strategy.md. Treat backend/ as read-only.

Implement Chats List, DM Chat, Saved Messages, message composer, pinned banner, reply/edit
strip, unread divider, pagination/loading/empty/error states, jump-to-message, message
actions, and documented security/offline/queue states. Use Flyer Chat only through the
timeline adapter and custom builders. Builders receive immutable app view models and
dispatch typed intents; they must not decrypt, call APIs, access Drift, or contain sync
logic. Use the app-owned visual system, not package-default screens.

Support incoming/outgoing/group-ready containers, author grouping, dates, text/system/
unsupported messages, reply quotes, reactions, pins, edited/deleted states, and explicit
queued/encrypting/sending/accepted/delivered/read/failed states. Preserve scroll anchors
during upward pagination, image-size changes, edits, reactions, resize, and RTL/LTR
mixing. Enforce withheld composer behavior for unverified identity/device/log-fork/PQ
failures.

Add widget/golden/accessibility tests across narrow/medium/wide, English/Persian,
large text, keyboard, screen reader semantics, dark/high contrast, reduced motion, and
50,000-message performance fixtures. If Flyer cannot pass anchoring or accessibility,
replace only the adapter with a custom sliver timeline as documented.

Acceptance criteria: all documented states are visually distinct and honest; no domain
state lives in Flyer controllers; performance remains bounded; tests/analyze/Web build
pass; no backend changes. Stop after piece 15.
~~~

## Prompt 16 — Attachments and local media

~~~text
Implement frontend piece 16: encrypted attachments and local media handling.

Read and obey frontend/AGENTS.md. Read attachments.md, message-protocol.md,
local-data-model.md, threat-model.md, ui-specification.md attachment/media sections,
backend/attachments/API.md, and testing-strategy.md. Backend is read-only.

Implement streaming attachment encryption/decryption through the Rust core using the
documented secretstream format, authenticated header/metadata, random file key, chunking,
final-tag validation, size/bucket rules, and capability handling. Implement create,
upload, download, resume/retry where contract-safe, cancellation, expiry, corruption,
quota, and safe filename/MIME behavior without buffering large plaintext/ciphertext in
memory. Attachment capabilities and keys travel only inside encrypted message events.

Build the attachment sheet, preview/send progress, image/file messages, safe open/save
behavior, missing/expired/corrupt states, and bounded thumbnail/decrypted-file caches.
Web decrypted files must be ephemeral; Android files must use private storage and safe
content-provider sharing. Do not execute active content or trust MIME/extension alone.

Add golden/header vectors, stream truncation/reorder/corruption/final-tag tests, quota and
expiry contract tests, cancellation/process-death recovery, memory-bound large-file
tests, cache eviction/wipe tests, and UI/accessibility tests.

Acceptance criteria: plaintext never reaches backend or logs; large files stay bounded;
tampering fails before unsafe presentation; tests/analyze and target builds pass; no
backend changes. Stop after piece 16.
~~~

## Prompt 17 — Linked devices and history transfer

~~~text
Implement frontend piece 17: linked-device management, device-log security, and
device-to-device history transfer.

Read and obey frontend/AGENTS.md. Read authentication-and-devices.md,
cryptographic-protocol.md device-log/recovery sections, sync-engine.md history section,
local-data-model.md, ui-specification.md sections 15–16, backend/devices/API.md,
backend/vault/API.md, and backend/CLIENT_CONTRACT.md. Backend is read-only.

Implement own-device listing with ETags, encrypted labels, relabel, explicit revocation,
self-revocation cleanup, and Linked Devices UI. Implement signed device-log record
encoding/verification, head extension, predicted sequence confirmation, encrypted head
gossip, concurrent append handling, and a global fail-closed fork/equivocation state.

Implement authenticated history-transfer control and bounded batch events over ordinary
hybrid pairwise envelopes. Only a cross-signing-authorized existing online device may
send its locally held full or partial history. The receiver authenticates, stores, and
deduplicates transactionally. Transfer no ratchet state, MLS epoch state, archive key, or
server history. Model identity recovered, waiting for source, partial transfer, no source,
group re-invitation, queue-gap recovery, and done states honestly.

Add malicious-server log fork/rollback tests, concurrent device changes, ETag refresh,
relabel/revoke, remote/self revocation, partial/resumed/duplicate/corrupt transfer,
source disappearance, no-history endpoint assertions, process death, and UI tests.

Acceptance criteria: no server response alone can authorize a device; forks globally
block sensitive operations; history moves only device-to-device; tests/analyze pass; no
backend changes. Stop after piece 17.
~~~

## Prompt 18 — Group domain and interface

~~~text
Implement frontend piece 18: group domain, authorization, storage, and responsive UI
behind the PQ MLS production gate.

Read and obey frontend/AGENTS.md. Read product-requirements.md, ui-specification.md group
sections, message-protocol.md, cryptographic-protocol.md groups section, mls-profile.md,
local-data-model.md, sync-engine.md, and testing-strategy.md. Backend is read-only.

Implement group domain types, deterministic control events, owner/admin/member role and
permission evaluation, invitation/removal/leave intent, metadata/history-sharing policy,
membership projections, conflict/quarantine states, and repository/use-case boundaries.
Implement Create Group, Group Chat, Group Info, Edit Group, member picker, role-aware
actions, removed/read-only state, and honest history re-share wording using fake/in-memory
MLS ports only in tests and development previews.

Create the real crypto port interfaces and transactional state boundaries required by
piece 19, but do not generate/upload production KeyPackages, assign a private suite ID,
send production group ciphertext, or represent groups as production-enabled while the
mls-profile gates are open. The production feature flag must fail closed and be
impossible to enable accidentally in a release build.

Add authorization/state-machine/property tests, concurrent admin/member changes,
malformed/unauthorized controls, persistence failure, queue-gap quarantine, responsive
RTL/accessibility UI, and a build-time assertion for the production gate.

Acceptance criteria: group product behavior is complete independently of crypto, but
production transport remains disabled and honestly surfaced; tests/analyze pass; no
backend changes. Stop after piece 18.
~~~

## Prompt 19 — PQ MLS integration

~~~text
Implement frontend piece 19: production PQ MLS integration only if every prerequisite
in frontend/docs/mls-profile.md can now be evidenced.

Read and obey frontend/AGENTS.md. Re-read mls-profile.md, cryptographic-protocol.md,
testing-strategy.md, sync-engine.md, local-data-model.md, backend/CLIENT_CONTRACT.md, and
backend/devices/API.md. Verify the current IETF/IANA/OpenMLS/provider status from primary
official sources because it is time-sensitive. Backend is read-only.

Before editing, produce a gate table with evidence for every mls-profile production
condition: final stable specification and IANA ID; maintained non-project-local
OpenMLS/provider support; Android/Web support; upstream/project vectors; backend bucket
fit; crash/fork/migration behavior; and independent review availability. If any gate is
not satisfied, do not implement a private-use production suite or weaken the contract.
Keep production groups disabled, update only stale frontend status/evidence if needed,
and report the blocker.

If and only if all gates pass, integrate the finalized
MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519 suite in the shared Rust core. Implement
authenticated BasicCredential binding, KeyPackage/last-resort lifecycle, Welcome,
GroupInfo, Proposal, Commit, PrivateMessage, application events, member add/remove,
epoch/exporter state, transactional persistence, fork policy, queue-gap remove/re-add,
and explicit protocol migration. Wrap every transported MLS object independently for
each recipient as required; never upload shared/raw group ciphertext.

Run upstream and project vectors byte-identically on Android/Web, multi-version/device
interop, malformed/downgrade/fork/crash tests, bucket-size tests, and independent review
gates. Enable production groups only after all evidence is recorded. Stop after piece 19;
never edit backend.
~~~

## Prompt 20 — Voice rooms and realtime media

~~~text
Implement frontend piece 20: voice rooms, realtime encrypted media, and ephemeral room
text. Start only after production MLS piece 19 is complete.

Read and obey frontend/AGENTS.md. Read voice-and-realtime.md, ui-specification.md voice
sections, cryptographic-protocol.md, mls-profile.md, platform docs,
backend/voicerooms/API.md, backend/realtime/API.md, and testing-strategy.md. Backend is
read-only.

Implement room discovery/create/read/rename, encrypted room metadata, client-owned
invitation/membership controls, join/token/reconnect, participant state, speaking/mute,
audio-device selection, minimize/active-call banner, invite/remove/leave, and ephemeral
memory-only room text. Backend room capability is not membership authorization; verify
all accepted membership/control events through the established account/device/MLS chain.

Integrate self-hosted LiveKit/TURN only. Derive/distribute media keys through the reviewed
MLS exporter flow and validate RFC 9605 SFrame or the selected LiveKit E2EE wire behavior.
Implement Web E2EE worker packaging/hashing and Android microphone/foreground-call
service only while a call is active. No foreign push, telemetry, STUN/TURN, or media
service is permitted. Leaving must update client membership/keys rather than pretend to
delete the backend room.

Add token expiry, reconnect, participant churn, key rotation, removed-member exclusion,
malicious capability holder, E2EE worker failure, background/lifecycle, audio route,
ephemeral-text cleanup, RTL/accessibility, and sustained-call tests.

Acceptance criteria: the media server cannot decrypt; unauthorized peers receive no
room/media keys; all runtime dependencies are self-hosted; tests/analyze/target builds
pass; no backend changes. Stop after piece 20.
~~~

## Prompt 21 — Search, settings, notifications, and finishing features

~~~text
Implement frontend piece 21: local search, settings, notifications, and remaining
product surfaces.

Read and obey frontend/AGENTS.md. Read the complete ui-specification.md plus
product-requirements.md, responsive-ui.md, visual-design-system.md, local-data-model.md,
platform docs, threat-model.md, and testing-strategy.md. Backend is read-only.

Implement local-only conversation/message/contact search with Android encrypted indexes
and Web memory-only active-session indexes. Implement Settings, Edit Profile completion,
Security Settings, recovery rotation, appearance/language, privacy and notification
controls, Saved Messages entry points, About, Security Notice, local clear-history,
logout confirmation, and all shared dialogs/sheets/menus from the UI inventory.

Implement Android local notifications generated only after authenticated decryption,
with hidden previews by default and best-effort polling expectations. Web must not claim
closed-browser notifications. Implement a user-initiated redacted diagnostics export
that contains none of the prohibited values. Finish deep links, keyboard shortcuts,
focus behavior, safe clipboard handling/expiry where supported, screenshot protection on
Android secret screens, and consistent destructive-action consequence wording.

Audit the complete screen inventory and add missing loading/empty/offline/error/security
states. Add search lifecycle/privacy tests, notification content tests, recovery rotation,
wipe/clear semantics, diagnostics redaction, deep links, RTL, accessibility, and
responsive goldens.

Acceptance criteria: every documented screen/state is implemented or explicitly gated;
search and diagnostics leak no plaintext/stable secrets; tests/analyze pass; no backend
changes. Stop after piece 21.
~~~

## Prompt 22 — Production hardening and release

~~~text
Implement frontend piece 22: production hardening, verification, and release readiness.

Read and obey frontend/AGENTS.md. Read every frontend document, every backend API.md,
backend/CLIENT_CONTRACT.md, backend/SECURITY.md, and the current implementation/checklist.
Backend is read-only. Do not mark a gate complete without evidence.

Run and close the complete production matrix: Flutter/Rust formatting and static
analysis; unit/widget/golden/property/fuzz/contract/E2E tests; Android and Chrome,
Firefox, and other supported-browser builds; multi-account/multi-device messaging;
process death and migration; seven-day queue gaps; accessibility; Persian RTL; large
text; keyboard; high contrast; performance/memory; battery/polling; attachment limits;
voice quality; malicious-server behavior; TLS/private-CA/SPKI failure; and local wipe.

Rehearse a fully isolated environment with Iran's international internet unavailable.
Prove that app assets, fonts, Web/Wasm workers, APIs, PostgreSQL/Redis/nginx,
LiveKit/TURN, APK installation/update, and Web loading require no foreign request.
Remove debug endpoints, unsafe logs, development trust, placeholders, remote resources,
and accidental feature-gate bypasses. Produce reproducible Android/Web artifacts, SBOM,
licenses, hashes/signatures, security headers, CSP/integrity manifests, deployment,
backup, update, rollback, and incident runbooks.

Require the independent security review and close all blocking findings, including
PQXDH, MLS, storage, Web threat boundary, media E2EE, and protocol parsing. If PQ MLS
gates remain open, the full production product is not complete; keep affected group and
voice features disabled and report this explicitly.

Update implementation-checklist.md with evidence links/results, not optimistic checks.
Acceptance criteria: every production gate is evidenced or clearly open; no known
critical/high issue remains; no backend file changed. Provide the final readiness report
and stop. Do not deploy, commit, push, or create a PR unless separately authorized.
~~~
