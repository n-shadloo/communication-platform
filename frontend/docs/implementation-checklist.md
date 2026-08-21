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
| Encrypted profile blob | Ready opaque storage | Piece 11 authenticated fetch/publish, version retry, cached fallback gating, and profile-key distribution ports complete; development fake transport is explicitly non-production and every other flavor resolves the unsupported adapters, so publishing and peer profile decryption fail closed. `profilePublishingProvider` reads that from the composed adapters and Edit Profile states it and disables Save (ADR-045, correcting ADR-044's supported tier) |
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
| WebSocket live delivery | Ready | Piece 06 authenticated gateway/close-code mapping and piece 12 lifecycle supervisor complete, with socket envelopes treated as wake-up hints that always trigger an authoritative REST drain. **Composed 2026-08-21 (ADR-047)**, closing ADR-046 follow-up step 1: `MessageDeliveryController` starts one session per device-bound full session, the socket is built from the one `NetworkingFoundation` that `AuthenticationAssembly` owns, and a composition test drives the real controller, session, supervisor, engine, store, gateway and coordinator against a fake transport. On-device the provisioned beta build clears the fail-closed gate against the live backend; a signed-in socket has not been observed on a device, because reaching full scope needs an account the server owner activates by hand |
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
| Group ciphertext delivery | Envelope transport ready | Piece 19 routes every closed-beta MLS object through durable recipient-bound Double Ratchet fan-out, including own other devices, with exact ciphertext retry. The commit-to-network leg is covered by crash and transaction-failure injection against the real repository, outbox, and fan-out coordinator (2026-08-18), which found and fixed two defects: one logical send identity per group object collided with the durable outbox's unique event id, so any group with two or more remote members committed its epoch and could never transmit it on any retry, and a single unroutable operation stranded every later group behind it. Execution against the packaged Rust core and physical devices remains pending; production remains disabled |
| Group availability by build | Client protocol | ADR-044: one source-only `GroupProductionGate.privateExperimentalPermit` decides both the closed-beta stack and its screens. Before it, `groupFeatureAvailabilityProvider` read the development-preview permit alone, which requires `!kReleaseMode`, so every group screen in the shipped Beta release rendered the closed gate while that same artifact composed `NativeBetaGroupMls`, ran `GroupKeyPackageMaintenanceService` as post-inbox work, and processed inbound group objects - uploading MLS KeyPackages for groups no user of it could create. Screens now gate on `GroupFeatureAvailability.isAvailable` rather than naming one tier, and the group banner states what the running build's stack actually is: the development preview says it transmits nothing, the Private Experimental build says the encryption is experimental and an update may reset the group and delete its messages. Production is unchanged and still resolves `UnsupportedGroupMlsCrypto`. Covered by three architecture tests and one widget test |
| Group creation/membership | Client protocol | Piece 19 implements real closed-beta create, authenticated later Welcome/re-add, membership controls, opaque state, and piece-18 CAS storage. The device-local crash and transaction-failure matrix over that CAS boundary is implemented and passing on 2026-08-18: 39 tests abort one exact statement inside the real transaction at every write in the unit, outbound and inbound, and assert the whole unit is absent; a simulated process restart reopens the durable file, passes `PRAGMA quick_check`, and finishes or discards the interrupted operation. The physical-device half — process kill, Doze, force-stop, torn writes, Keystore after reboot, packaged Rust core — has not been run. Remaining recovery/concurrency matrices keep production fail-closed |
| Owner/admin/member roles | Client protocol | Piece 19 signs and verifies deterministic controls with device authentication proofs and replays the authenticated transcript; full adversarial/device matrix and independent review remain pending |
| Invite/remove/leave | Client protocol | Closed-beta Invite/re-add, remove, and ADR-039 two-phase leave with automatic owner-side eviction are integrated. The queue-gap remove/re-add matrix is implemented and tested on 2026-08-18: an evicted member is re-admissible by a fresh Add against newly claimed KeyPackages, while a live member and one whose eviction is still uncommitted stay refused; a blocked device admits an authenticated re-admission Welcome and nothing else, requires a consumed KeyPackage and a strictly forward revision, and replaces the retained group, roster, and transcript in the same transaction that retires the group's obligation, advances the acknowledged loss baseline through `pruned_through`, and releases the retained MLS-blocked envelopes. Covered by 45 Dart tests across three files (11 domain re-admission, 31 device-side recovery matrix, 3 admission-service re-invite), including compare-and-swap abort, rollback of the pairwise receive, multi-group blocking, explicit local abandonment, and restart-mid-recovery resumability, against a scripted crypto port. The peer-to-peer signal that asks peers to remove and re-add a gapped device has no defined wire format in either the backend or frontend contract and is not implemented; recovery is driven by the re-admission itself. Execution against the real crypto core, a running backend, and multiple physical devices remains pending, and production MLS commits remain gated |
| Encrypted metadata | Opaque envelope transport ready | Closed beta processes metadata/policy controls inside authenticated MLS transport and the atomic state/projection boundary; production remains gated |
| History for new members | Envelope transport ready; no server history | Policy and authenticated Welcome are integrated; bounded cryptographic history re-share validation remains pending and never implies server history |
| Fork/conflict handling | Client protocol | ADR-041 canonical same-revision convergence is implemented and tested: siblings are authenticated and replayed against the shared parent, and the winner is decided by operation precedence class, then the signer's authority in that parent, then the authenticated signer identity, so no branch author can bias the outcome; a superseded branch fork-quarantines atomically for remove/re-add. ADR-038's hash-only order was superseded on 2026-08-17 after the hash was measured to be author-grindable at about 24,500 candidate branches per second per core. Covered by a Rust grinding measurement and 32 Dart tests, including an adversarial sweep over every role and invitation policy. Multi-device execution against the real crypto core remains pending |
| Leave coordination | Client protocol | ADR-039 two-phase departure is implemented and tested: the leaver signs a non-membership announcement at the current epoch and the active owner automatically commits the `Remove` that evicts the leaves. Covered by a Rust descriptor test and 16 Dart tests; multi-device execution against real devices remains pending |

## Attachments and recovery

| Capability | Backend | Flutter |
|---|---|---|
| Bucketed encrypted upload/download | Ready | Pending secretstream pipeline. `AttachmentTransferService` exists but is composed by no provider, `pubspec.yaml` declares no picker, and the composer's sheet now says attachments are not built rather than offering inert choices (ADR-045, correcting ADR-044's supported tier) |
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
| User-facing maturity and disclosure | Not applicable | **Disclosure revision 2 (2026-08-21, ADR-048)**: shipping alerts made "There are no notifications" false, so `DeploymentDisclosure.revision` moved 1 to 2 and both catalogues now say that messages arrive and the app can alert only while it is running, and that nothing re-arms once Android stops it. Per ADR-045's mechanism every later enrollment re-acknowledges, and re-delivering the written handover disclosure to existing recipients is **release-blocking and has not happened**. ADR-045: one application-level word (Experimental), two feature labels that only read down from it (`SurfaceMaturity.experimental`, `SurfaceMaturity.notBuilt`), and one mandatory first-run disclosure rendered inside the existing `EnrollmentPhase.securityNotice` gate rather than in a second consent screen. `DeploymentDisclosure` in `lib/app/config/deployment_disclosure.dart` owns the seven points and the revision that pins them; `SecurityNoticeSections` renders the one notice for the enrollment gate, the Settings entry, and the pre-login links, and resolves to no build section in development and production. Corrections shipped with it: the task-switcher title no longer calls the Private Experimental build "(Development)"; the permanent "Structural placeholder - not for shipping" footer is gone from the wide navigation rail of every build including production; the voice-room and appearance pages say what they are instead of naming routed regions and no longer offer a demo chain into another placeholder; Edit Profile states that this build composes no profile adapter and disables Save instead of failing into a generic error; the attachment sheet states that attachments are not built instead of offering three inert options; five mojibake Connection-screen strings are repaired; and Settings is localized and finally carries the re-viewable security notice `ui-specification.md` §15 has always required. Covered by 8 architecture assertions, 10 widget tests, and 1 provider test |
| 34-screen inventory | Supporting APIs/primitives ready as above | Pieces 09–11 implement authentication/enrollment plus Contacts/New, Contact Profile, Edit Profile, and Safety Number; piece 15 adds Chats List, DM Chat, Saved Messages, pinned/forward/action sheets, and all chat state surfaces; piece 18 adds Create Group, Group Chat, Group Info, Edit Group, and Add Members behind the production gate; later screens remain pending |
| English/Persian RTL | Not applicable | Piece 03 foundations, piece 11 contact/profile/safety screens, piece 15 Chats/DM/Saved coverage, and piece 18 narrow Persian group creation plus responsive group-chat/info coverage complete; later feature-screen verification remains pending |
| Accessibility/high contrast | Not applicable | Piece 18 extends the piece 15 screen-reader/live-state and 200% text foundation with semantic member actions, honest gated/read-only states, and narrow/wide group verification; later feature-flow audit remains pending |

## Platform delivery

| Capability | Backend | Flutter |
|---|---|---|
| Android encrypted database/Keystore | Not applicable | Piece 05 versioned Drift schema, SQLCipher database, Keystore AES-GCM wrapping with StrongBox/TEE preference, transactional repositories, bounded cleanup, and cryptographic wipe flows complete; physical-device process-death/Keystore matrix remains a release gate |
| Android normal resume/drain | Durable queue supports it | Piece 12 lifecycle/network resume, durable reconnect, socket-hint, and authoritative drain flow complete and **composed 2026-08-21 (ADR-047)**. Outbound traffic moves: growth of the durable outbox is what asks the supervisor for a cycle, so rows `SendConversationEvents` writes through `fanout.prepareAndQueue` are transmitted without further stimulus, and rows queued before a restart are transmitted when the next session starts. Two edges were corrected in the same work: an unreported platform lifecycle state at launch is no longer read as background, and every foreground transition re-reads connectivity |
| Android background polling | Seven-day durable queue supports it | Piece 12 app-owned best-effort/headless scheduler port complete, with no Firebase; the composed build installs `UnscheduledBestEffortPolling`, which schedules nothing, so a backgrounded application still performs no catch-up. ADR-046 keeps deferrable work as the mandatory *eventual* floor and adds an opt-in `specialUse` foreground service above it for *near-real-time, best-effort* delivery, superseding ADR-029's "no persistent service". `dataSync` and `remoteMessaging` remain forbidden and the architecture test that enforces that is unchanged. Concrete WorkManager registration, the durable single-owner delivery lease, the service, the boot receiver, and the Samsung/Xiaomi/AOSP device matrix are all pending |
| Android local notifications | No foreign push by design | **Implemented 2026-08-21 (ADR-048)**, closing ADR-046 follow-up step 2 and amending three of its details. One aggregate, sender-neutral notification — content is `New message` or `New messages` and nothing else, `VISIBILITY_PRIVATE` with a matching `setPublicVersion`, no timestamp, one frozen channel id, and a launcher-intent tap under `FLAG_IMMUTABLE` carrying no destination and no identifier. It is a *reconciliation* of committed rows rather than an emission from `PostInboxCommitWorkPort`, because that hook can announce but never withdraw; the trigger is a Drift table-update signal, which the pinned 2.34.2 source dispatches only after `COMMIT`. Idempotence is the durable boolean `messages.alerted` (schema 12), preserved across projector rebuilds by the same upsert mechanism that already preserves `starred`, spent after a successful post and never before, spent also for a deliberate suppression (muted, or the conversation on screen) and never for a platform refusal. `POST_NOTIFICATIONS` is requested at point of use, only while foregrounded, and spent at most once automatically under two guards; Settings states the true platform answer and offers one action that asks Android and falls through to its settings screen. No dependency was added: every API comes from `androidx.core:core:1.16.0`, already declared for `FileProvider`. Covered by 29 policy tests, 8 store tests, 6 projector-seam tests, 11 channel tests, 8 composition tests, 10 widget tests and 7 architecture assertions. **Open**: the Kotlin half is unmeasured — no device or emulator run was possible — so lock-screen rendering, the status-bar icon, heads-up behaviour, channel vibration and the permission dialog are a release gate, not a claim; group messages produce no alert because the piece-18 projection sets no unread state; decrypted previews are not built |
| Web persistent encrypted device | Device API supports it | Preserved piece-05 ciphertext-only Drift/WebCrypto foundation; post-v1 only, with supported-browser persistence matrix deferred |
| Web open-tab realtime | WebSocket auth supports it | Preserved piece-06 origin-derived `wss` gateway; post-v1 only, with page lifecycle/drain integration deferred |
| Web shared crypto Wasm/worker | Client protocol | Post-v1 backlog; crypto-dependent Web behavior remains fail-closed with no Dart/JavaScript fallback |
| Closed-browser notification | Not supported without push by design | Explicitly out of scope |
| Direct signed APK distribution | Self-hosted operation supports it | ADR-042 Beta release pipeline complete: the Beta application ID is frozen in `android/beta-release-identity.properties` and read by the build, `betaRelease` signs with a persistent v2+v3 identity supplied only from the environment or an untracked file, a missing identity fails the build closed rather than producing an unsigned or debug-signed artifact, and `tool/build_beta_release.sh` refuses to publish anything `tool/verify_release_apk.sh` has not verified against the recorded certificate. Production release stays unsigned and is verified as such in CI, including that its packaged native core does not export the beta MLS symbol. Upgrade continuity tier 1 passed on an API 35 emulator on 2026-08-19: version code 1 upgraded to 2 in place with no uninstall, `firstInstallTime` unchanged, and the same artifact re-signed with a different key was rejected. The real signing identity was created on 2026-08-19 and its certificate SHA-256 is recorded in `android/beta-release-identity.properties`; re-verified against the keystore on 2026-08-20 (subject `CN=dev.nimashadloo.chat.beta`, valid to 2054-01-04, fingerprint matching the recorded value exactly). The rooted file-survival tier and the manual account/group/history tier against a live backend remain to be run, and the off-site encrypted key backups required by `docs/release-signing.md` must exist before the first external install |
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
  still document only the three classical suites and their *released* post-quantum work
  targets X-Wing rather than the selected mapping — corrected 2026-08-18: OpenMLS's
  unreleased `main` branch does now implement the selected mapping exactly, at provisional
  code point `0x004E` behind a cargo feature, which changes the gap from a mapping gap to a
  release-and-registry gap without changing the result, (4) the MLS Working Group vector repository
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
  ADR-041 canonical fork convergence (superseding ADR-038) and ADR-039
  two-phase leave are both implemented and tested. ADR-040 (2026-08-17) keeps this KEM
  mapping unchanged, so no beta state, sealed snapshot, KeyPackage, or group is
  reinitialized by that decision; it also records what a later KEM change would cost.
  The divergent hybrid KEM and its HPKE integration now carry construction-level
  known-answer coverage (`vectors/beta-hybrid-kem-project-kats.json`,
  `src/beta_kem_vectors.rs`, 10 tests): exact `kem_derive` bytes, a deterministic
  encapsulation, key schedule, ciphertext and exporter output, and probes that
  demonstrate D1-D4 and D8 by computation. **Those vectors are project-generated and are
  not external conformance evidence** — official construction vectors do not exist for
  this construction and cannot, because it is not a published one — so they close no gate
  and do not advance the upstream-vector prerequisite. They found no mismatch: the
  implementation performs exactly the construction D1-D10 describe. The beta group
  operations additionally carry protocol-level vectors written in the MLS working group's
  published vector schema (`vectors/mls-beta-upstream-schema/`, `src/beta_mls_vectors.rs`,
  10 tests plus an `#[ignore]`d generator): Welcome, Passive Client Scenarios, and Vector
  Deserialization, with round trips that rejoin from the recorded `Welcome` and reproduce
  every epoch authenticator, and negative tests that keep those round trips from passing
  vacuously. The other eleven categories are skipped because the constructions they vector
  are `pub(crate)` inside `mls-rs`, or — for Messages — cannot be fully populated at all.
  **The schema is upstream; the values are not.** They are project-generated, are not
  external interoperability evidence, close no gate, and do not advance the upstream-vector
  prerequisite. Cross-implementation interoperability against a second, independent MLS
  implementation was attempted on 2026-08-18 and is **externally blocked**; no harness was
  built. All eleven implementations on the MLS working group's list fail the same
  requirement — the beta hybrid KEM is not a published construction, so it has no
  specification, no IANA code point, and exactly one implementation in existence, which is
  the `mls-rs` crate this project already depends on. ts-mls is configurable on five of the
  six requirements (arbitrary ciphersuite identifier, HKDF-SHA384, AES-256-GCM, SHA-384,
  Ed25519) and fails only on the KEM; every other candidate fails on the identifier or on
  ML-KEM support as well. The blocker is structural rather than scheduling: it clears only
  on the same upstream event ADR-040 names as its reversal trigger. Two findings were
  recorded rather than acted on — OpenMLS's unreleased `main` now implements `TBD2`'s exact
  five-primitive mapping at provisional code point `0x004E`, which **corrects** this
  document's and `docs/mls-profile.md`'s prior statement that OpenMLS had the right KEM on
  the wrong AEAD/KDF/hash; and OpenMLS and MLSpp have chosen two mutually incompatible
  provisional code points (`0x004E` and `0x0008`) for that one suite, which is direct
  evidence that no provisional value may be adopted in place of the IANA assignment. Full
  per-candidate gaps are in `docs/mls-profile.md`, "Cross-implementation interoperability
  determination". Remaining blockers are the full
  queue-gap remove/re-add/history matrix, upstream/project interoperability and
  bucket/backend contract execution against a running backend, multi-device and
  process-death/fault matrices on real hardware, state-format migration fuzzing, and
  independent cryptographic review. Device-local crash and transaction-failure
  injection over the piece-18 CAS boundary and the commit-to-network leg is done as of
  2026-08-18: 39 Dart tests across
  `test/features/groups/infrastructure/group_commit_boundary_injection_test.dart`,
  `test/features/groups/application/group_outbound_interruption_test.dart`, and
  `test/features/synchronization/group_inbox_crash_injection_test.dart`, using a
  temporary SQLite `RAISE(ABORT)` trigger per failure point and a reopened file-backed
  database for process death. It found and fixed a per-recipient logical send identity
  collision that made closed-beta groups of three or more members permanently
  untransmittable, a head-of-line stall in outbound dispatch, and a missing
  outbound-direction check in the three locally originated use cases
  (`docs/mls-profile.md`). This runs on the host VM against SQLite and the development
  MLS port; it does not substitute for the on-hardware matrix above. Input-boundary fuzzing of the beta MLS operation is
  done: twelve targets over every relay-reachable decoder, run on 2026-08-18, which found
  and fixed one non-canonical MLS object acceptance (`docs/mls-profile.md`,
  `native/crypto_core/fuzz/README.md`). The material an independent assessor needs is now
  assembled in `docs/mls-beta-review-readiness.md` (2026-08-18, revision `4e65eaf`): source
  baseline and pinned versions, in-scope claims and an explicit out-of-scope list, the full
  implementation inventory, the ten project-specific protocol inventions no external
  specification or vector can validate, the official-versus-project vector split, the
  adversarial state-machine question set, verified reproduction commands, and a
  finding-disposition template. **That packet is not a review, records no assessment, and
  closes no gate**; no reviewer is retained, and its own disposition table is empty.
  The engagement that would use that packet is prepared in
  `docs/independent-review-engagement.md` (2026-08-18): a qualification bar, a scope of work
  bounded to this implementation, the seven deliverables required before the review gate can
  close, and an evaluation of candidates and funding routes against primary sources.
  **That document retains nobody, names nobody as retained, and moves no gate**; retaining a
  reviewer, funding, the review, and closure of its findings are all external, and its
  engagement record is empty. Production still resolves the unsupported adapter,
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
