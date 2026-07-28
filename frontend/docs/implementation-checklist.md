# Backend and Flutter implementation checklist

This is the live delivery checklist. Backend checkmarks mean an API/capability exists and
is documented, not that the Flutter integration exists. Flutter documentation is now
specified; pieces 01–06 now provide the Android/Web foundation, architecture skeleton,
app-owned design system, responsive routed shell, guarded bootstrap, secure local
storage, and the typed REST/authentication/WebSocket transport foundation. Later
capabilities remain pending. Piece 07 now provides the shared Rust primitive foundation
and Android FFI/isolate adapter; Web/Wasm crypto is explicitly deferred and remains
fail-closed. Completion and test evidence are recorded below only after verification.

Legend: **Ready** = implemented backend contract; **Client protocol** = intentionally
opaque/client-owned; **Pending** = Flutter implementation not started.

## Foundation

| Capability | Backend | Flutter |
|---|---|---|
| Health/reachability | Ready: `/api/v1/health` | Pieces 04/06 typed single-origin state machine and bounded Dio health adapter complete; provisioned staging trust integration remains a release gate |
| Private CA/TLS deployment | Ready | Piece 04 Android network-security template, CA/primary+backup-pin interfaces, Web external-trust gate, and blocking failures complete; provisioned-device staging integration remains pending |
| Android/Web project | Not applicable | Piece 01 scaffold complete; development/production Android flavors and Web entry points compile |
| Architecture and protocol docs | Backend docs ready | Piece 02 feature-first Clean Architecture skeleton compiled with sealed typed failures, scoped Riverpod composition, and source-layout/inward-dependency tests; normative fixtures/security gates pending |
| CI/reproducible offline builds | Backend ready | Local CI commands, SDK pin, and lockfile ready; isolated offline-cache rehearsal pending |
| Redacted diagnostics | Backend ready | Piece 06 typed payload-free network diagnostic events and redaction tests complete; user-initiated local export remains piece 21 |
| Shared Rust crypto core | Client protocol | Piece 07 Android foundation complete: pinned primitive providers, zeroizing secret types, bounded deterministic CBOR, stable ABI/status codes, panic containment, dedicated isolate, three-ABI packaging, and packaged Android smoke pass; Web/Wasm and later protocols remain pending |

## Accounts and devices

| Capability | Backend | Flutter |
|---|---|---|
| Register/manual activation | Ready | Pending screens/use cases |
| Login/refresh/logout | Ready | Piece 06 proactive single-flight rotating-token coordinator, one safe authenticated retry, revocation, and local-first logout foundation complete; feature use cases/screens remain piece 09 |
| User directory | Ready | Pending local repository/UI |
| Encrypted profile blob | Ready opaque storage | Bootstrap fallback specified; implementation pending |
| Cross-signing identity publish/fetch | Ready opaque transport | Pending master/self/user-signing implementation |
| Register/list/label/revoke devices | Ready; two-phase enrollment contract | Pending register → full scope → cross-sign follow-up and resumable UI |
| Peer device lists, ETags, signed device log | Ready opaque transport | Pending verification, head gossip, fork alert |
| Hybrid X25519 + ML-KEM prekeys | Ready public distribution | Pending reviewed PQXDH core; no classical fallback |
| PQ MLS key packages | 4096/16384 buckets + last-resort ready | Candidate selected; blocked on IANA ID, maintained OpenMLS/provider support, vectors, and review |
| SAS/QR master-key verification | Client protocol | Pending; messaging withheld until verified |
| Recovery onboarding | Identity backup API ready | Pending identity restore; no server-history restore |

## Messaging

| Capability | Backend | Flutter |
|---|---|---|
| Per-device durable envelope queue | Ready | Pending inbox/outbox |
| Batched fan-out/stale devices | Ready | <=256 deterministic batching specified; implementation pending |
| Drain/ack | Ready | Pending crash-safe pipeline |
| Seven-day TTL / `pruned_through` gaps | Ready signal | Pending blocking detection and fresh-Welcome recovery |
| WebSocket live delivery | Ready | Piece 06 authenticated native/Web gateway, bounded frame parsing, close-code mapping, and reconnect hooks complete; durable inbox/business-state integration remains pending |
| DM identity/session | Client protocol | Pending hybrid PQXDH/Double Ratchet |
| Text messages | Client protocol | Pending |
| Replies/edits/deletes | Client protocol | Pending |
| Reactions/pins/receipts | Client protocol | Pending |
| Typing/presence meaning | Volatile relay ready | Pending encrypted semantics |
| Private contact blocking | No server ACL by design | Protocol specified; implementation pending |
| Multi-device self-sync/history | Envelope primitives ready; no history API | Pending authorized device-to-device transfer |
| Saved Messages | Client protocol | Pending |
| Local search | No plaintext server search by design | Pending Android/web indexes |

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
| Key backup blob | Ready for cross-signing identity material | Pending Argon2id/wrapping |
| Server history | Deliberately absent | Device-to-device transfer specified; implementation pending |
| New-device restore | Two-phase enrollment and identity backup APIs ready | Pending restore/cross-sign follow-up; history remains device-to-device |

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
| Web E2EE worker | Not applicable | Pending build/compatibility spike |

## UI

| Capability | Backend | Flutter |
|---|---|---|
| Responsive shell | Not applicable | Pieces 03â€“04 adaptive `go_router` shell plus guarded Splash/Connection bootstrap routing complete; stable branch identity, deep-link placeholders, guard hooks, keyboard navigation, focus restoration, reduced motion, resize preservation, accessible Retry, and Android-only offline entry are tested |
| Forui design system and Lucide icons | Not applicable | Piece 03 app-owned semantic tokens and Forui wrappers complete; bundled Lucide is isolated behind typed `AppIcons`, with package-boundary, semantics, target-size, disabled, focus, and RTL-mirroring tests |
| Flyer Chat builders | Not applicable | Selected; pending technical spike |
| 34-screen inventory | Supporting APIs/primitives ready as above | Specified; pending implementation |
| English/Persian RTL | Not applicable | Piece 03 LTR/RTL foundations complete with pinned local Vazirmatn, localized shell chrome, directional-icon policy, and narrow/medium golden coverage; feature-screen verification remains pending |
| Accessibility/high contrast | Not applicable | Piece 03 shell/component semantics, keyboard focus, 48 px icon targets, 200% text-scale layout, reduced motion, dark mode, and authored high-contrast token mapping verified; full feature-flow audit remains pending |

## Platform delivery

| Capability | Backend | Flutter |
|---|---|---|
| Android encrypted database/Keystore | Not applicable | Piece 05 versioned Drift schema, SQLCipher database, Keystore AES-GCM wrapping with StrongBox/TEE preference, transactional repositories, bounded cleanup, and cryptographic wipe flows complete; physical-device process-death/Keystore matrix remains a release gate |
| Android normal resume/drain | Durable queue supports it | Pending |
| Android background polling | Seven-day durable queue supports it | Pending WorkManager polling/gap handling |
| Android local notifications | No foreign push by design | Pending |
| Web persistent encrypted device | Device API supports it | Piece 05 ciphertext-only Drift persistence, non-extractable WebCrypto wrapping key in IndexedDB, authenticated wrapped storage key, unsafe-storage rejection, memory clearing hooks, and key-loss/tamper wipe complete; supported-browser persistence matrix remains a release gate |
| Web open-tab realtime | WebSocket auth supports it | Piece 06 origin-derived `wss` gateway and first-frame browser authentication complete; page lifecycle/drain integration remains pending |
| Web shared crypto Wasm/worker | Client protocol | Deferred after the Android-only piece-07 scope; crypto-dependent Web behavior remains fail-closed with no Dart/JavaScript fallback, and same-source Android/Web vectors remain pending |
| Closed-browser notification | Not supported without push by design | Explicitly out of scope |
| Direct signed APK distribution | Self-hosted operation supports it | Pending release pipeline |
| Self-hosted hardened web bundle | nginx deployment base exists | Pending build/header config |

## Required spikes before broad implementation

- [x] Piece 07 shared Rust primitive core, stable native ABI, Android packaging,
  isolate lifecycle, redaction, malformed-input, boundary, and packaged-device smoke
  checks pass. This Android-only item does not satisfy the cross-target item below.
- [ ] Deterministic-CBOR CDDL, `EnvelopeV1` encoders, and Android/Web golden byte/error
  fixtures are generated from one versioned protocol package.
- [ ] Shared crypto core builds and passes identical vectors on Android and browser Wasm.
- [ ] Android `mlkem_native` and reviewed Web Wasm ML-KEM pass identical FIPS/PQXDH
  vectors; no educational/pure-Dart ML-KEM is present.
- [ ] Hybrid PQXDH/Double Ratchet composition is independently reviewed.
- [ ] The selected PQ MLS candidate receives an IANA ID and maintained
  OpenMLS/provider support; 4096/16384 wrappers, last-resort behavior, Android/Wasm
  persistence, and fork handling then pass interoperability tests.
- [ ] First/later-device two-phase enrollment is crash-safe and resumable; unsigned
  intermediate devices remain withheld until the prekey cross-signature follow-up.
- [ ] Android and Web reproduce the backend `cross_sig`, `master_sig`, `spk_sig`, and
  `pq_spk_sig` golden vectors, including optional fields and the 64-byte `ik_pub` layout.
- [ ] Device-log chain verification, ETag refresh, encrypted head gossip, and fork alarms
  pass malicious-server tests.
- [ ] LiveKit Flutter E2EE meets the SFrame/media threat-model requirement on both targets.
- [x] Piece 05 Drift foundation: SQLCipher Android plus ciphertext-only Web schema,
  transactional migrations/repositories, constraints, reactive Riverpod projections,
  restart/privacy checks, and key-loss/tamper/logout/revocation wipe tests pass. The
  physical-device and supported-browser release matrix remains tracked below.
- [x] Piece 06 networking foundation: one bounded typed Dio client, contract DTO
  boundaries, safe replay/cancellation/timeout policy, payload-free diagnostics,
  proactive single-flight token rotation, and authenticated native/Web WebSocket
  gateway pass mock-adapter, race, size, redaction, and close-code tests.
- [ ] Flyer builders pass long-history, scroll, RTL, accessibility, and media tests.
- [ ] Android WorkManager polling is tested under Doze/standby/force-stop; only active
  voice uses a foreground service.
- [ ] Private CA/SPKI and strict WebSocket origin behavior work in staging.
- [ ] Final product name/logo/app icon replace the neutral placeholder and pass light,
  dark, small-size, contrast, and Android/web asset review before release.

## Production completion gates

- [ ] Every pending row above is implemented or explicitly removed by an approved ADR.
- [ ] Backend contract suite passes against production-equivalent infrastructure.
- [ ] Full multi-device Android/Web E2E matrix passes.
- [ ] Offline/international-disconnection rehearsal passes with zero foreign requests.
- [ ] Accessibility, RTL, performance, migration, battery, and voice gates pass.
- [ ] Independent security review is complete and blocking findings are closed.
- [ ] Reproducible artifacts, SBOM, signatures, hashes, update, and rollback runbooks are
  archived.
