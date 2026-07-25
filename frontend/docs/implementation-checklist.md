# Backend and Flutter implementation checklist

This is the live delivery checklist. Backend checkmarks mean an API/capability exists and
is documented, not that the Flutter integration exists. Flutter documentation is now
specified; Flutter source implementation has not yet been scaffolded.

Legend: **Ready** = implemented backend contract; **Client protocol** = intentionally
opaque/client-owned; **Pending** = Flutter implementation not started.

## Foundation

| Capability | Backend | Flutter |
|---|---|---|
| Health/reachability | Ready: `/api/v1/health` | Pending |
| Private CA/TLS deployment | Ready | Pending trust/pinning adapters |
| Android/Web project | Not applicable | Pending scaffold |
| Architecture and protocol docs | Backend docs ready | Client behavior specified; normative fixtures/security gates pending |
| CI/reproducible offline builds | Backend ready | Pending |
| Redacted diagnostics | Backend ready | Pending local-only export |

## Accounts and devices

| Capability | Backend | Flutter |
|---|---|---|
| Register/manual activation | Ready | Pending screens/use cases |
| Login/refresh/logout | Ready | Pending token coordinator |
| User directory | Ready | Pending local repository/UI |
| Encrypted profile blob | Ready opaque storage | Bootstrap fallback specified; implementation pending |
| Cross-signing identity publish/fetch | Ready opaque transport | Pending master/self/user-signing implementation |
| Register/list/label/revoke devices | Registration contract circular; backend blocker | Blocked pending signable client-known device ID/bootstrap |
| Peer device lists, ETags, signed device log | Ready opaque transport | Pending verification, head gossip, fork alert |
| Hybrid X25519 + ML-KEM prekeys | Ready public distribution | Pending reviewed PQXDH core; no classical fallback |
| PQ MLS key packages | 4096/16384 buckets + last-resort ready | Pending reviewed PQ suite/OpenMLS integration |
| SAS/QR master-key verification | Client protocol | Pending; messaging withheld until verified |
| Recovery onboarding | Identity backup API ready | Pending identity restore; no server-history restore |

## Messaging

| Capability | Backend | Flutter |
|---|---|---|
| Per-device durable envelope queue | Ready | Pending inbox/outbox |
| Batched fan-out/stale devices | Ready | <=256 deterministic batching specified; implementation pending |
| Drain/ack | Ready | Pending crash-safe pipeline |
| Seven-day TTL / `pruned_through` gaps | Ready signal | Pending blocking detection and fresh-Welcome recovery |
| WebSocket live delivery | Ready | Pending gateway |
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
| New-device restore | Enrollment contract currently circular | Backend-blocked before identity/history flow |

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
| Responsive shell | Not applicable | Specified; pending implementation |
| Forui design system | Not applicable | Visual tokens specified; wrapper components pending |
| Flyer Chat builders | Not applicable | Selected; pending technical spike |
| 34-screen inventory | Supporting APIs/primitives ready as above | Specified; pending implementation |
| English/Persian RTL | Not applicable | Specified; pending localization |
| Accessibility/high contrast | Not applicable | Specified; pending verification |

## Platform delivery

| Capability | Backend | Flutter |
|---|---|---|
| Android encrypted database/Keystore | Not applicable | Pending |
| Android normal resume/drain | Durable queue supports it | Pending |
| Android background polling | Seven-day durable queue supports it | Pending WorkManager polling/gap handling |
| Android local notifications | No foreign push by design | Pending |
| Web persistent encrypted device | Device API supports it | Pending WebCrypto/IndexedDB |
| Web open-tab realtime | WebSocket auth supports it | Pending |
| Closed-browser notification | Not supported without push by design | Explicitly out of scope |
| Direct signed APK distribution | Self-hosted operation supports it | Pending release pipeline |
| Self-hosted hardened web bundle | nginx deployment base exists | Pending build/header config |

## Required spikes before broad implementation

- [ ] Deterministic-CBOR CDDL, `EnvelopeV1` encoders, and Android/Web golden byte/error
  fixtures are generated from one versioned protocol package.
- [ ] Shared crypto core builds and passes identical vectors on Android and browser Wasm.
- [ ] Android `mlkem_native` and reviewed Web Wasm ML-KEM pass identical FIPS/PQXDH
  vectors; no educational/pure-Dart ML-KEM is present.
- [ ] Hybrid PQXDH/Double Ratchet composition is independently reviewed.
- [ ] A PQ MLS ciphersuite, 4096/16384 KeyPackage wrappers, last-resort behavior,
  Android/Wasm persistence, and fork handling pass interoperability tests.
- [ ] Backend enrollment is made non-circular: the client can know the signed device ID
  and obtain/authorize cross-signing material before `cross_sig` is required.
- [ ] The protocol owner defines and vectors the exact `master_sig` canonical input and
  the `ik_pub` representation of separate Ed25519 signing/X25519 identity keys.
- [ ] Device-log chain verification, ETag refresh, encrypted head gossip, and fork alarms
  pass malicious-server tests.
- [ ] LiveKit Flutter E2EE meets the SFrame/media threat-model requirement on both targets.
- [ ] Drift encrypted Android and ciphertext-only web storage/migrations work.
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
