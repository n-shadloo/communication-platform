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
| Register/list/label/revoke devices | Ready | Pending |
| Peer device lists and ETags | Ready | Pending |
| X3DH prekeys | Ready public distribution | Pending reviewed crypto core |
| MLS key packages | Ready public distribution | Pending OpenMLS integration |
| Safety verification | Client protocol | Pending |
| Recovery onboarding | Backup API ready | History/session distinction specified; implementation pending |

## Messaging

| Capability | Backend | Flutter |
|---|---|---|
| Per-device durable envelope queue | Ready | Pending inbox/outbox |
| Batched fan-out/stale devices | Ready | <=256 deterministic batching specified; implementation pending |
| Drain/ack | Ready | Pending crash-safe pipeline |
| WebSocket live delivery | Ready | Pending gateway |
| DM identity/session | Client protocol | Pending X3DH/Double Ratchet |
| Text messages | Client protocol | Pending |
| Replies/edits/deletes | Client protocol | Pending |
| Reactions/pins/receipts | Client protocol | Pending |
| Typing/presence meaning | Volatile relay ready | Pending encrypted semantics |
| Private contact blocking | No server ACL by design | Protocol specified; implementation pending |
| Multi-device self-sync | Queue primitives ready | Pending protocol/reconciliation |
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
| Encrypted metadata | Opaque transport/history ready | Pending |
| History for new members | History/envelope primitives ready | Pending client re-share |
| Fork/conflict handling | Client protocol | Safe quarantine/blocking specified; reviewed crypto-core convergence remains a release gate |

## Attachments and recovery

| Capability | Backend | Flutter |
|---|---|---|
| Bucketed encrypted upload/download | Ready | Pending secretstream pipeline |
| Quota and TTL | Ready | Pending UI/error handling |
| Encrypted attachment metadata/key | Client protocol | Pending |
| Bounded secure cache | Not applicable | Pending |
| Key backup blob | Ready | Pending Argon2id/wrapping |
| Append/read/delete history | Ready | Pending archive engine |
| New-device restore | Storage primitives ready | Pending recovery flow |

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
| Android Stay Connected mode | Socket supports it | Pending OS/policy spike |
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
- [ ] X3DH/Double Ratchet implementation selection is license/security reviewed.
- [ ] OpenMLS Android/Wasm persistence and fork behavior pass interoperability tests.
- [ ] LiveKit Flutter E2EE meets the SFrame/media threat-model requirement on both targets.
- [ ] Drift encrypted Android and ciphertext-only web storage/migrations work.
- [ ] Flyer builders pass long-history, scroll, RTL, accessibility, and media tests.
- [ ] Android background mode is valid under target-SDK foreground-service rules.
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
