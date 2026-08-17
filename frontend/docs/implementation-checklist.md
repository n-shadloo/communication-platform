# Backend and Flutter implementation checklist

This is the live delivery checklist. Backend checkmarks mean an API/capability exists and
is documented, not that the Flutter integration exists. Flutter documentation is now
specified; pieces 01–06 provide the Android foundation and a preserved post-v1 Web
scaffold, architecture skeleton, app-owned design system, responsive routed shell,
guarded bootstrap, secure local storage, and typed REST/authentication/WebSocket
transport foundation. Later capabilities remain pending. Piece 07 now provides the
shared Rust primitive foundation and Android FFI/isolate adapter; Web/Wasm crypto is
post-v1, explicitly deferred, and remains fail-closed. Piece 12 provides the crash-safe
opaque inbox/outbox synchronization engine and lifecycle foundation, piece 13 provides
the pairwise transport, and piece 14 now provides the application-message protocol,
conversation domain, and local projections. Completion and test evidence are recorded
below only after verification.

Legend: **Ready** = implemented backend contract; **Client protocol** = intentionally
opaque/client-owned; **Pending** = Flutter implementation not started.

## Foundation

| Capability | Backend | Flutter |
|---|---|---|
| Health/reachability | Ready: `/api/v1/health` | Pieces 04/06 typed single-origin state machine and bounded Dio health adapter complete; provisioned staging trust integration remains a release gate |
| Private CA/TLS deployment | Ready | Piece 04 Android network-security template, CA/primary+backup-pin interfaces, and blocking failures complete; the preserved Web external-trust model is post-v1; provisioned-device staging integration remains pending |
| Android project | Not applicable | Piece 01 scaffold complete; development/production Android flavors compile; the preserved Web entry point is post-v1 |
| Architecture and protocol docs | Backend docs ready | Piece 02 feature-first Clean Architecture skeleton compiled with sealed typed failures, scoped Riverpod composition, and source-layout/inward-dependency tests; normative fixtures/security gates pending |
| CI/reproducible offline builds | Backend ready | Local CI commands, SDK pin, and lockfile ready; isolated offline-cache rehearsal pending |
| Redacted diagnostics | Backend ready | Piece 06 typed payload-free network diagnostic events and redaction tests complete; user-initiated local export remains piece 21 |
| Shared Rust crypto core | Client protocol | Piece 07 Android foundation complete: pinned primitive providers, zeroizing secret types, bounded deterministic CBOR, stable ABI/status codes, panic containment, dedicated isolate, three-ABI packaging, and packaged Android smoke pass; Web/Wasm and later protocols remain pending |

## Accounts and devices

| Capability | Backend | Flutter |
|---|---|---|
| Register/manual activation | Ready | Piece 09 account registration, pending-activation state, localized validation/errors, and responsive screens complete; activation remains owner-driven with no polling |
| Login/refresh/logout | Ready | Piece 09 authentication plus piece 10 full-scope enrollment handoff, incomplete-secure-setup restoration/guards, and final messaging release complete |
| User directory | Ready | Piece 11 activated-user fetch, atomic Drift cache, offline presentation, bounded local paging/search, and Contacts/New UI complete |
| Encrypted profile blob | Ready opaque storage | Piece 11 authenticated fetch/publish, version retry, cached fallback gating, and profile-key distribution ports complete; development fake transport is explicitly non-production and production remains fail-closed pending pairwise transport |
| Cross-signing identity publish/fetch | Ready opaque transport | Pieces 10/11 complete local identity lifecycle plus exact peer `master_sig` verification, persisted user-signing attestation, key-change blocking, and profile/Safety Number UI |
| Register/list/label/revoke devices | Ready; two-phase enrollment contract | Pieces 10/17 complete enrollment plus authenticated own-device ETag listing, account-private encrypted labels, relabel, explicit remote/self revocation, crash-resumable log-first removal, secure self cleanup, and Linked Devices UI |
| Peer device lists, ETags, signed device log | Ready opaque transport | Pieces 10/11/17 complete authenticated own/peer device sets, canonical signed-log verification and extension, exact predicted-sequence confirmation, concurrent append recovery, encrypted pairwise head gossip, and persistent global fork/equivocation blocking |
| Hybrid X25519 + ML-KEM prekeys | Ready public distribution | Pending reviewed PQXDH core; no classical fallback |
| PQ MLS key packages | 4096/16384 buckets + last-resort ready | Candidate selected; blocked on the unassigned MLS suite identifier, the hybrid KEM's expiring draft reference, maintained OpenMLS/provider support, vectors, and review |
| SAS/QR master-key verification | Client protocol | Piece 11 exact-two-master-key SAS/QR, explicit out-of-band confirmation, user-signing attestation, and persistent verified/change states complete; messaging remains withheld on every non-verified state |
| Recovery onboarding | Identity backup API ready | Piece 10 one-time checksummed secret, Rust Argon2id/XChaCha backup, first upload, later restore, wrong-secret handling, and honest no-history notice complete |

## Messaging

| Capability | Backend | Flutter |
|---|---|---|
| Per-device durable envelope queue | Ready | Piece 12 durable Drift inbox/outbox journals, opaque event deduplication, bounded queues, and process-death recovery plus piece 14 atomic application-event markers/projections complete |
| Batched fan-out/stale devices | Ready | Piece 12 UUID-byte-sorted <=256 target batches, exact-ciphertext retry, partial progress, stale terminal state/session invalidation, and durable refresh requests complete |
| Drain/ack | Ready | Piece 12 authoritative REST paging, duplicate/reorder handling, post-commit idempotent ack, and durable contiguous checkpoint complete |
| Seven-day TTL / `pruned_through` gaps | Ready signal | Piece 12 pre-processing comparison, blocking queue-gap/group recovery state, retained MLS-dependent opaque envelopes, and recovered loss-baseline transition complete; fresh Welcome production flow remains gated on MLS pieces |
| WebSocket live delivery | Ready | Piece 06 authenticated gateway/close-code mapping plus piece 12 lifecycle supervisor complete; socket envelopes are wake-up hints only and always trigger authoritative REST drain |
| DM identity/session | Client protocol | Piece 13 hybrid PQXDH/Double Ratchet transport and exact pairwise fan-out/outbox integration complete |
| Text messages | Client protocol | Pieces 14–15 complete deterministic-CBOR events, typed projections, honest optimistic transport state, Riverpod streams, and the production app-owned timeline |
| Replies/edits/deletes | Client protocol | Piece 14 reply references, deterministic revision winner, authorization, local tombstone, best-effort remote-delete, and attachment-cache cleanup complete |
| Reactions/pins/receipts | Client protocol | Piece 14 idempotent set projections, participant/role authorization, per-device receipt provenance, durable delivered work, and privacy-gated read sends complete |
| Typing/presence meaning | Volatile relay ready | Piece 14 bounded volatile typing expiry, conservative socket presence, disconnect clearing, and typed Riverpod streams complete; signals never enter durable projections |
| Private contact blocking | No server ACL by design | Protocol specified; implementation pending |
| Multi-device self-sync/history | Ready device-to-device; no history API | Pieces 14/17 complete ordinary own-device fan-out plus authenticated, bounded, resumable history batches over exact-recipient hybrid pairwise envelopes with transactional deduplication and honest partial/no-source recovery states |
| Saved Messages | Client protocol | Pieces 14–15 complete the domain-separated local conversation, own-account authorization, unread-free/local-only behavior, no peer presence/receipt promise, routing, timeline, composer, and actions |
| Local search | No plaintext server search by design | Pending Android encrypted index |

## Groups

| Capability | Backend | Flutter |
|---|---|---|
| Key-package claim | Ready | Piece 19 has real closed-beta generation, replenishment, consumable claim, and separately uploaded last-resort lifecycle wiring; backend bucket/consumption contract execution remains pending and production upload is disabled |
| Group ciphertext delivery | Envelope transport ready | Piece 19 routes every closed-beta MLS object through durable recipient-bound Double Ratchet fan-out, including own other devices, with exact ciphertext retry; production remains disabled |
| Group creation/membership | Client protocol | Piece 19 implements real closed-beta create, authenticated later Welcome/re-add, membership controls, opaque state, and piece-18 CAS storage; remaining recovery/concurrency matrices keep production fail-closed |
| Owner/admin/member roles | Client protocol | Piece 19 signs and verifies deterministic controls with device authentication proofs and replays the authenticated transcript; full adversarial/device matrix and independent review remain pending |
| Invite/remove/leave | Client protocol | Closed-beta Invite/re-add, remove, and ADR-039 two-phase leave with automatic owner-side eviction are integrated; the queue-gap remove/re-add matrix remains Piece 19 work and production MLS commits remain gated |
| Encrypted metadata | Opaque envelope transport ready | Closed beta processes metadata/policy controls inside authenticated MLS transport and the atomic state/projection boundary; production remains gated |
| History for new members | Envelope transport ready; no server history | Policy and authenticated Welcome are integrated; bounded cryptographic history re-share validation remains pending and never implies server history |
| Fork/conflict handling | Client protocol | ADR-038 canonical same-revision convergence is implemented and tested: siblings are authenticated and replayed against the shared parent, the smallest control state hash wins, and a superseded branch fork-quarantines atomically for remove/re-add. Multi-device execution against the real crypto core remains pending |
| Leave coordination | Client protocol | ADR-039 two-phase departure is implemented and tested: the leaver signs a non-membership announcement at the current epoch and the active owner automatically commits the `Remove` that evicts the leaves. Covered by a Rust descriptor test and 16 Dart tests; multi-device execution against real devices remains pending |

## Attachments and recovery

| Capability | Backend | Flutter |
|---|---|---|
| Bucketed encrypted upload/download | Ready | Pending secretstream pipeline |
| Quota and TTL | Ready | Pending UI/error handling |
| Encrypted attachment metadata/key | Client protocol | Pending |
| Bounded secure cache | Not applicable | Pending |
| Key backup blob | Ready for cross-signing identity material | Piece 10 4,096-byte Rust Argon2id/XChaCha20-Poly1305 format, parameter/bucket validation, stale-version reconciliation, and cleanup complete |
| Server history | Deliberately absent | Piece 17 transfers only locally held application-event history between cross-signing-authorized online devices; no history/archive endpoint or server-history dependency exists |
| New-device restore | Two-phase enrollment and identity backup APIs ready | Pieces 10/17 complete identity restore/cross-sign/log follow-up and honest device-to-device full/partial history recovery without transferring ratchets, MLS epochs, archive keys, or server history |

## Voice rooms and realtime

| Capability | Backend | Flutter |
|---|---|---|
| Create/read/rename room | Ready opaque name | Pending |
| Room live count/signals | Ready volatile relay | Pending |
| LiveKit token | Ready | Pending join/reconnect client |
| Self-hosted LiveKit/TURN | Deployment ready | Pending integration tests |
| Room invitations/membership | Client protocol | Leave semantics specified; implementation pending |
| Audio E2EE/key distribution | Server deliberately excluded | Pending MLS exporter/E2EE gate |
| Ephemeral room text | Volatile relay ready | Pending encrypted memory-only UI |
| Android active-call service | Not applicable | Pending |
| Web E2EE worker | Not applicable | Post-v1 backlog; not part of the Android release |

## UI

| Capability | Backend | Flutter |
|---|---|---|
| Responsive shell | Not applicable | Pieces 03â€“04 adaptive `go_router` shell plus guarded Splash/Connection bootstrap routing complete; stable branch identity, deep-link placeholders, guard hooks, keyboard navigation, focus restoration, reduced motion, resize preservation, accessible Retry, and Android-only offline entry are tested |
| Forui design system and Lucide icons | Not applicable | Piece 03 app-owned semantic tokens and Forui wrappers complete; bundled Lucide is isolated behind typed `AppIcons`, with package-boundary, semantics, target-size, disabled, focus, and RTL-mirroring tests |
| Timeline adapter and builders | Not applicable | Piece 15 selected the documented custom reversed-sliver adapter because Flyer 2.11.1 requires mutable controller-owned message state; app-owned immutable builders, anchors, jump, semantics, and bounded virtualization pass |
| 34-screen inventory | Supporting APIs/primitives ready as above | Pieces 09–11 implement authentication/enrollment plus Contacts/New, Contact Profile, Edit Profile, and Safety Number; piece 15 adds Chats List, DM Chat, Saved Messages, pinned/forward/action sheets, and all chat state surfaces; piece 18 adds Create Group, Group Chat, Group Info, Edit Group, and Add Members behind the production gate; later screens remain pending |
| English/Persian RTL | Not applicable | Piece 03 foundations, piece 11 contact/profile/safety screens, piece 15 Chats/DM/Saved coverage, and piece 18 narrow Persian group creation plus responsive group-chat/info coverage complete; later feature-screen verification remains pending |
| Accessibility/high contrast | Not applicable | Piece 18 extends the piece 15 screen-reader/live-state and 200% text foundation with semantic member actions, honest gated/read-only states, and narrow/wide group verification; later feature-flow audit remains pending |

## Platform delivery

| Capability | Backend | Flutter |
|---|---|---|
| Android encrypted database/Keystore | Not applicable | Piece 05 versioned Drift schema, SQLCipher database, Keystore AES-GCM wrapping with StrongBox/TEE preference, transactional repositories, bounded cleanup, and cryptographic wipe flows complete; physical-device process-death/Keystore matrix remains a release gate |
| Android normal resume/drain | Durable queue supports it | Piece 12 lifecycle/network resume, durable reconnect, socket-hint, and authoritative drain flow complete |
| Android background polling | Seven-day durable queue supports it | Piece 12 app-owned best-effort/headless scheduler interface complete with no Firebase or messaging foreground service; concrete WorkManager registration and physical-device matrix remain pending |
| Android local notifications | No foreign push by design | Pending |
| Web persistent encrypted device | Device API supports it | Preserved piece-05 ciphertext-only Drift/WebCrypto foundation; post-v1 only, with supported-browser persistence matrix deferred |
| Web open-tab realtime | WebSocket auth supports it | Preserved piece-06 origin-derived `wss` gateway; post-v1 only, with page lifecycle/drain integration deferred |
| Web shared crypto Wasm/worker | Client protocol | Post-v1 backlog; crypto-dependent Web behavior remains fail-closed with no Dart/JavaScript fallback |
| Closed-browser notification | Not supported without push by design | Explicitly out of scope |
| Direct signed APK distribution | Self-hosted operation supports it | Pending release pipeline |
| Self-hosted hardened web bundle | nginx deployment base exists | Post-v1 backlog; not part of the Android release |

## Required spikes before broad implementation

- [x] Piece 07 shared Rust primitive core, stable native ABI, Android packaging,
  isolate lifecycle, redaction, malformed-input, boundary, and packaged-device smoke
  checks pass for the Android-only version-1 target.
- [x] Deterministic-CBOR application-event CDDL, encoders/decoders, and Android
  golden byte/error fixtures are generated from one versioned protocol package
  (Piece 14: unknown-kind structural validation, future-version opaque retention,
  native property/golden tests, and Android smoke fixture verified on 2026-07-30).
- [x] Piece 08 canonical device-signature encoders/verifiers reproduce every
  backend `cross_sig`, `master_sig`, `spk_sig`, and `pq_spk_sig` vector byte-for-byte,
  reject required mutations, and pass through the packaged Android FFI/isolate smoke
  test. No Dart encoder or Web/Wasm implementation was added.
- [ ] Android `mlkem_native` passes identical FIPS/PQXDH vectors; no educational or
  pure-Dart ML-KEM is present.
- [ ] Hybrid PQXDH/Double Ratchet composition is independently reviewed.
- [ ] Piece 19 Phase-A production prerequisites pass. The former combined
  specification/identifier prerequisite is now two separately evidenced rows, because the
  primitive mapping and the MLS suite value sit in different registries with different
  owners, registration policies, and completion paths. As rechecked against primary
  sources on 2026-08-16, all five remain blocked. (1) The primitive mapping is blocked on
  one identifier of five: hybrid KEM `0x647A` is assigned in the IANA HPKE KEM registry
  (last updated 2026-04-16) but its only reference there is
  `draft-connolly-cfrg-xwing-kem-06`, a superseded Independent-stream draft now at `-10`
  and expiring 2026-09-03, while KDF `0x0002`, AEAD `0x0002`, hash SHA-384, and signature
  `ed25519` `0x0807` already rest on published standards. (2) The MLS suite identifier is
  blocked outright: `draft-ietf-mls-pq-ciphersuites-06` is an expiring Internet-Draft that
  the working group has already flagged as needing another revision, its IANA
  Considerations touch only the MLS Cipher Suites registry, and `TBD2` has no assignment
  there (that registry, last updated 2025-11-17, still holds only RFC 9420
  `0x0001`-`0x0007`, GREASE, and Private Use). (3) OpenMLS 0.8.1 stable and 0.9.0-rc.2
  still document only the three classical suites and their post-quantum work targets
  X-Wing rather than the selected mapping, (4) the MLS Working Group vector repository
  still publishes only classical fixtures, and (5) no qualified independent reviewer is
  retained. Draft-06 still defines `TBD2` with the exact recorded primitive mapping, so no
  suite/ADR stop-and-decide is triggered. Separately re-verified on 2026-08-17 against the
  pinned vendored crate sources and the X-Wing draft text: the closed beta implements
  `TBD2`'s signature, AEAD, KDF, and hash choices but not its KEM `0x647a`, so beta groups
  are not `TBD2`-conformant and are not `TBD2` interoperability evidence. The divergence is
  now recorded as a complete ten-row set (D1-D10) with per-row file-and-line evidence, and
  **ADR-040 resolves that the beta KEM is not changed**: the pinned `mls-rs` crypto crates
  are already the newest published versions so no maintained fix exists, no maintained
  provider implements `TBD2` at all, and supplying a conformant KEM through `mls-rs`'s
  public extension points would be a project-local cryptographic fork because
  `AwsLcCipherSuite` cannot be re-parameterized. The per-identifier registry evidence and
  every evidence table are in `docs/mls-profile.md`; production has seven mandatory gates,
  and ADR-040 opens none of them. Web support remains post-v1.
- [x] Piece 10 first/later-device two-phase enrollment is crash-safe and resumable;
  registration response loss never causes a blind duplicate; recoverable unsigned
  orphans are adopted or revoked; every intermediate state remains withheld through the
  signed device-log append and mandatory notice. Rust backup/recovery vectors, Android
  encrypted persistence/process-death tests, contract fixtures, UI tests, Clippy,
  analyze, and the Android build were verified on 2026-07-28.
- [x] Piece 11 activated directory/cache, authenticated-profile presentation gate,
  peer identity/device/prekey/log verification, exact-master SAS/QR, explicit
  user-signing attestation, persistent key-change/fork blocking, and localized
  contact/profile/safety screens pass malicious-server, pagination, cache,
  profile-authentication, accessibility, RTL, locked Rust/Clippy, analyze, widget,
  and three-ABI Android APK build gates. The profile transport fake is
  development-only and encrypted device-log gossip remains a later messaging task.
- [x] Piece 12 deterministic 513-target fan-out, exact-ciphertext ambiguous retry,
  durable REST drain/ack paging, opaque event deduplication, contiguous checkpointing,
  stale-device invalidation/refresh, full-jitter retry state, queue-gap MLS blocking,
  lifecycle/network/socket-close handling, offline restart, bounded queues, transaction
  fault injection, and redaction pass the full Flutter suite, fatal analysis,
  development/production Android APK builds, and preserved fail-closed Web build on
  2026-07-29. Piece 13 pairwise crypto and piece 14 application-domain integration
  now build on this durable foundation; concrete Android WorkManager registration/
  Doze validation remains pending.
- [x] Piece 14 deterministic-CBOR application events, typed conversation/message
  projections, authorization and tombstone rules, duplicate/replay/counter conflict
  handling, unsupported-event retention, receipt/typing/presence semantics, drafts,
  unread/mute/Saved Messages behavior, event-order permutations, transaction-failure
  injection, redaction, strict Rust/Clippy, full Flutter tests/analyze, three-ABI
  native packaging, and development Android APK/integration fixture builds verified
  on 2026-07-30. Piece 15 now supplies the final direct-message and Saved Messages
  interface.
- [x] Piece 15 production Chats List, DM Chat, Saved Messages, composer,
  reply/edit/pin/forward/delete/reaction/star/retry actions, explicit
  local-only/queued/encrypting/sending/accepted/delivered/read/failed states,
  fail-closed identity/device/log-fork/PQ composer gates, local conversation pin/unread
  projections and migration, and the app-owned timeline adapter pass full Flutter
  tests/analyze, responsive English/Persian goldens, keyboard/screen-reader semantics,
  dynamic-size/upward-pagination anchors, and the 50,000-message bounded-widget fixture
  plus development and production Android APK builds on 2026-07-30.
- [x] Piece 18 group domain, deterministic control projection, role authorization,
  invite/remove/leave and metadata/history policies, membership/conflict/quarantine
  projections, atomic Drift state/outbound boundaries, and responsive localized group
  screens pass authorization/state-machine/property/concurrency/fault tests, the full
  Flutter suite, fatal analysis, and development/production Android APK builds on
  2026-08-02. Development uses an explicitly non-cryptographic in-memory preview;
  production is compile-time fail-closed with no KeyPackage, suite ID, or group
  ciphertext path. All cryptographic production enablement remains piece 19.
- [ ] Piece 19 real closed-beta PQ MLS implementation is complete and production-ready.
  The dark implementation currently uses locked maintained `mls-rs 0.55.2` and
  `mls-rs-crypto-awslc 0.25.0` with the draft-06 candidate's symmetric and signature
  mapping over that provider's own pre-standard hybrid KEM — not draft-06's KEM `0x647a`,
  as recorded in `docs/mls-profile.md` — and Private Use identifier `0xFE4C`; implements
  authenticated BasicCredential/device proof binding,
  KeyPackage maintenance and last-resort separation, create/Welcome/Proposal/Commit/
  PrivateMessage processing, signed deterministic controls, later-member authenticated
  transcript replay, member add/remove, epoch/exporter state, opaque state-format
  versioning, and durable per-recipient pairwise fan-out through the piece-18 atomic CAS
  boundary. Transport v3 and schema v11 reject insufficient v2 transcript state rather
  than silently migrating it. The production fail-closed audit is covered by
  five `test/architecture/group_production_gate_test.dart` assertions, including the
  fully composed port that the use cases and sync engine actually consume, the closed
  KeyPackage-maintenance path, and every `GroupMlsCryptoPort` method on the unsupported
  adapter. The Windows host toolchain carries the MSVC C++ build tools, LLVM, NASM, and
  Ninja that the pinned `x86_64-pc-windows-msvc` host requires, so the **entire** Rust
  validation stack executes. Verified on 2026-08-16: `cargo fmt --all -- --check`,
  `cargo test --locked` (49), `cargo test --locked --all-features` (60, including the
  `mls_beta` suite), `cargo clippy --locked --all-targets --all-features -- -D warnings`,
  `dart format --set-exit-if-changed lib test` (310 files, 0 changed),
  `flutter analyze --fatal-infos` (no issues), the full Flutter suite (403 tests), and
  `flutter build apk --release --flavor production`. Packaged Android builds of **both**
  the foundation and beta profiles cover all three ABIs (arm64-v8a, armeabi-v7a, x86_64)
  with the export allowlist, 16 KiB alignment, and static-libsodium checks. Artifact-level
  fail-closed evidence: `llvm-nm -D --defined-only` on the native libraries extracted from
  the built **production release APK** reports exactly the 15-symbol foundation allowlist
  on every ABI and zero `cp_crypto_v1_beta_mls_operation` symbols, which exist only in the
  separate `beta` artifact, so a production build contains no PQ MLS code path at all.
  ADR-038 canonical fork convergence and ADR-039
  two-phase leave are both implemented and tested. ADR-040 (2026-08-17) keeps this KEM
  mapping unchanged, so no beta state, sealed snapshot, KeyPackage, or group is
  reinitialized by that decision; it also records what a later KEM change would cost.
  Remaining blockers are the full
  queue-gap remove/re-add/history matrix, upstream/project interoperability and
  bucket/backend contract execution against a running backend, multi-device and
  process-death/fault matrices on real hardware, migration fuzzing, and independent
  cryptographic review. Production still resolves the unsupported adapter,
  `GroupProductionGate` remains false, and production KeyPackage/group creation remains
  impossible.
- [x] Android reproduces the backend `cross_sig`, `master_sig`, `spk_sig`, and
  `pq_spk_sig` golden vectors, including optional fields and the 64-byte `ik_pub` layout
  (Piece 08: Rust vectors, strict Clippy, Flutter tests, three-ABI native package build,
  and Android FFI/isolate smoke test verified on 2026-07-28).
- [ ] Device-log chain verification, ETag refresh, encrypted head gossip, and fork alarms
  pass malicious-server tests.
- [ ] Android LiveKit Flutter E2EE meets the SFrame/media threat-model requirement.
- [x] Piece 05 Drift foundation: SQLCipher Android plus a preserved ciphertext-only Web
  schema,
  transactional migrations/repositories, constraints, reactive Riverpod projections,
  restart/privacy checks, and key-loss/tamper/logout/revocation wipe tests pass for the
  Android foundation. The Web persistence matrix is post-v1.
- [x] Piece 06 networking foundation: one bounded typed Dio client, contract DTO
  boundaries, safe replay/cancellation/timeout policy, payload-free diagnostics,
  proactive single-flight token rotation, and authenticated native Android WebSocket
  gateway pass mock-adapter, race, size, redaction, and close-code tests.
- [x] Piece 15 timeline builders pass long-history, upward pagination, dynamic row/media
  sizing, jump, mixed RTL/LTR, accessibility, keyboard, high-contrast, large-text, and
  reduced-motion tests. The Flyer 2.11.1 controller path did not meet the no-duplicate-
  state boundary, so only the adapter was replaced by the documented custom sliver.
- [ ] Android WorkManager polling is tested under Doze/standby/force-stop; only active
  voice uses a foreground service.
- [ ] Private CA/SPKI behavior works in Android staging. Strict WebSocket origin behavior
  is post-v1 Web work.
- [ ] Final product name/logo/app icon replace the neutral placeholder and pass light,
  dark, small-size, contrast, and Android asset review before release.

## Production completion gates

- [ ] Every pending row above is implemented or explicitly removed by an approved ADR.
- [ ] Backend contract suite passes against production-equivalent infrastructure.
- [ ] Full multi-device Android E2E matrix passes.
- [ ] Offline/international-disconnection rehearsal passes with zero foreign requests.
- [ ] Accessibility, RTL, performance, migration, battery, and voice gates pass.
- [ ] Independent security review is complete and blocking findings are closed.
- [ ] Reproducible artifacts, SBOM, signatures, hashes, update, and rollback runbooks are
  archived.

## Post-v1 Web backlog

The following remain intentionally outside the version-1 release: browser encrypted
storage compatibility, WebSocket lifecycle, shared Rust Wasm/worker packaging, browser
crypto vectors, Web E2EE media, browser E2E, CSP/SRI/headers, and self-hosted Web
distribution. They remain fail-closed and must be reopened by an explicit ADR before
being treated as release work.
