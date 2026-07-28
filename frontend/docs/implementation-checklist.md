# Backend and Flutter implementation checklist

This is the live delivery checklist. Backend checkmarks mean an API/capability exists and
is documented, not that the Flutter integration exists. Flutter documentation is now
specified; pieces 01–06 provide the Android foundation and a preserved post-v1 Web
scaffold, architecture skeleton, app-owned design system, responsive routed shell,
guarded bootstrap, secure local storage, and typed REST/authentication/WebSocket
transport foundation. Later capabilities remain pending. Piece 07 now provides the
shared Rust primitive foundation and Android FFI/isolate adapter; Web/Wasm crypto is
post-v1, explicitly deferred, and remains fail-closed. Completion and test evidence are
recorded below only after verification.

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
| Register/list/label/revoke devices | Ready; two-phase enrollment contract | Piece 10 first/later two-phase registration, unsigned withholding, prekey cross-sign follow-up, orphan reconciliation/revocation, and resumable UI complete; linked-device management remains later work |
| Peer device lists, ETags, signed device log | Ready opaque transport | Pieces 10/11 complete own-device append plus peer ETag cache, signed extension/live-set verification, prekey-bundle authentication, and persistent global fork blocking; encrypted head gossip remains a later messaging task |
| Hybrid X25519 + ML-KEM prekeys | Ready public distribution | Pending reviewed PQXDH core; no classical fallback |
| PQ MLS key packages | 4096/16384 buckets + last-resort ready | Candidate selected; blocked on IANA ID, maintained OpenMLS/provider support, vectors, and review |
| SAS/QR master-key verification | Client protocol | Piece 11 exact-two-master-key SAS/QR, explicit out-of-band confirmation, user-signing attestation, and persistent verified/change states complete; messaging remains withheld on every non-verified state |
| Recovery onboarding | Identity backup API ready | Piece 10 one-time checksummed secret, Rust Argon2id/XChaCha backup, first upload, later restore, wrong-secret handling, and honest no-history notice complete |

## Messaging

| Capability | Backend | Flutter |
|---|---|---|
| Per-device durable envelope queue | Ready | Pending inbox/outbox |
| Batched fan-out/stale devices | Ready | <=256 deterministic batching specified; implementation pending |
| Drain/ack | Ready | Pending crash-safe pipeline |
| Seven-day TTL / `pruned_through` gaps | Ready signal | Pending blocking detection and fresh-Welcome recovery |
| WebSocket live delivery | Ready | Piece 06 authenticated Android gateway, bounded frame parsing, close-code mapping, and reconnect hooks complete; the preserved Web gateway is post-v1; durable inbox/business-state integration remains pending |
| DM identity/session | Client protocol | Pending hybrid PQXDH/Double Ratchet |
| Text messages | Client protocol | Pending |
| Replies/edits/deletes | Client protocol | Pending |
| Reactions/pins/receipts | Client protocol | Pending |
| Typing/presence meaning | Volatile relay ready | Pending encrypted semantics |
| Private contact blocking | No server ACL by design | Protocol specified; implementation pending |
| Multi-device self-sync/history | Envelope primitives ready; no history API | Pending authorized device-to-device transfer |
| Saved Messages | Client protocol | Pending |
| Local search | No plaintext server search by design | Pending Android encrypted index |

## Groups

| Capability | Backend | Flutter |
|---|---|---|
| Key-package claim | Ready | Pending |
| Group ciphertext delivery | Envelope transport ready | Pending MLS + pairwise wrapping |
| Group creation/membership | Client protocol | Pending |
| Owner/admin/member roles | Client protocol | Pending signed control state |
| Invite/remove/leave | Client protocol | Pending MLS commits/UI |
| Encrypted metadata | Opaque envelope transport ready | Pending |
| History for new members | Envelope transport ready; no server history | Pending client re-share |
| Fork/conflict handling | Client protocol | Safe quarantine/blocking specified; reviewed crypto-core convergence remains a release gate |

## Attachments and recovery

| Capability | Backend | Flutter |
|---|---|---|
| Bucketed encrypted upload/download | Ready | Pending secretstream pipeline |
| Quota and TTL | Ready | Pending UI/error handling |
| Encrypted attachment metadata/key | Client protocol | Pending |
| Bounded secure cache | Not applicable | Pending |
| Key backup blob | Ready for cross-signing identity material | Piece 10 4,096-byte Rust Argon2id/XChaCha20-Poly1305 format, parameter/bucket validation, stale-version reconciliation, and cleanup complete |
| Server history | Deliberately absent | Device-to-device transfer specified; implementation pending |
| New-device restore | Two-phase enrollment and identity backup APIs ready | Piece 10 identity-only restore/cross-sign/log follow-up complete; history remains intentionally deferred to device-to-device transfer |

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
| Flyer Chat builders | Not applicable | Selected; pending technical spike |
| 34-screen inventory | Supporting APIs/primitives ready as above | Pieces 09â€“11 implement authentication/enrollment plus Contacts/New, Contact Profile, Edit Profile, and Safety Number; later screens remain pending |
| English/Persian RTL | Not applicable | Piece 03 foundations plus piece 11 localized contact/profile/safety screens and RTL widget coverage complete; later feature-screen verification remains pending |
| Accessibility/high contrast | Not applicable | Piece 03 shell/component semantics, keyboard focus, 48 px icon targets, 200% text-scale layout, reduced motion, dark mode, and authored high-contrast token mapping verified; full feature-flow audit remains pending |

## Platform delivery

| Capability | Backend | Flutter |
|---|---|---|
| Android encrypted database/Keystore | Not applicable | Piece 05 versioned Drift schema, SQLCipher database, Keystore AES-GCM wrapping with StrongBox/TEE preference, transactional repositories, bounded cleanup, and cryptographic wipe flows complete; physical-device process-death/Keystore matrix remains a release gate |
| Android normal resume/drain | Durable queue supports it | Pending |
| Android background polling | Seven-day durable queue supports it | Pending WorkManager polling/gap handling |
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
- [ ] Deterministic-CBOR CDDL, `EnvelopeV1` encoders, and Android golden byte/error
  fixtures are generated from one versioned protocol package.
- [x] Piece 08 canonical device-signature encoders/verifiers reproduce every
  backend `cross_sig`, `master_sig`, `spk_sig`, and `pq_spk_sig` vector byte-for-byte,
  reject required mutations, and pass through the packaged Android FFI/isolate smoke
  test. No Dart encoder or Web/Wasm implementation was added.
- [ ] Android `mlkem_native` passes identical FIPS/PQXDH vectors; no educational or
  pure-Dart ML-KEM is present.
- [ ] Hybrid PQXDH/Double Ratchet composition is independently reviewed.
- [ ] The selected PQ MLS candidate receives an IANA ID and maintained
  OpenMLS/provider support; 4096/16384 wrappers, last-resort behavior, Android
  persistence, and fork handling then pass interoperability tests. Web persistence is
  post-v1.
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
- [ ] Flyer builders pass long-history, scroll, RTL, accessibility, and media tests.
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
