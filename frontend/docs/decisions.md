# Architecture decisions

This file is the initial ADR register. A changed accepted decision gets a dated ADR; it
is not silently edited out of history.

| ID | Status | Decision | Reason |
|---|---|---|---|
| ADR-001 | Accepted | Feature-first Clean Architecture | Keeps security, sync, UI, and platform concerns independently testable. |
| ADR-002 | Accepted | Drift is the local source of truth | Prevents REST, socket, and optimistic state from diverging in widgets. |
| ADR-003 | Accepted | Riverpod for DI and reactive application state | Supports testable scopes and database-stream projections without global singletons. |
| ADR-004 | Accepted | Dio for REST and a dedicated WebSocket gateway | Centralizes authentication, redaction, refresh, retries, and protocol limits. |
| ADR-005 | Accepted | `go_router` with route guards | Supports deep links and adaptive navigation without navigation in domain code. |
| ADR-006 | Accepted | Forui behind app-owned components | Gains consistent primitives without coupling product design directly to a package. |
| ADR-007 | Accepted | Flyer Chat behind a timeline adapter | Reuses virtualization while allowing exclusive builders or full replacement. |
| ADR-008 | Accepted | Canonical CBOR for encrypted application payloads | Compact, deterministic, binary-safe, and versionable. |
| ADR-009 | Superseded by ADR-025 | X3DH + Double Ratchet for device-pair channels | The binding backend client contract now requires hybrid PQXDH session establishment. |
| ADR-010 | Accepted | RFC 9420 MLS for group membership/key state | Provides standardized asynchronous group FS/PCS and matches backend key packages. |
| ADR-011 | Accepted | Per-recipient pairwise transport wrapping | Prevents identical MLS ciphertext from linking a sender's recipient set at rest. |
| ADR-012 | Accepted | Local-only search | The server never receives content or search terms. |
| ADR-013 | Accepted | No foreign push or telemetry | Required for operation during international disconnection and privacy. |
| ADR-014 | Superseded by ADR-029 | Explicit Android foreground connection mode | The binding backend client contract now requires background polling for messaging. |
| ADR-015 | Accepted | Web is online-session-first | Browser background execution cannot provide native-style delivery guarantees. |
| ADR-016 | Accepted | English and Persian at first release | RTL and mixed-direction behavior must be structural, not retrofitted. |
| ADR-017 | Release gate | Shared reviewed crypto core and independent assessment | A custom, unaudited cryptographic implementation is not production-ready. |
| ADR-018 | Accepted | Padding is authenticated inside each pairwise transport envelope | Prevents ambiguous/unprotected trailing bytes while preserving backend size buckets. |
| ADR-019 | Accepted | Logical fan-out uses durable per-device targets and deterministic batches of at most 256 | Supports the backend limit, partial progress, and crash-safe retries for large multi-device groups. |
| ADR-020 | Accepted | Event IDs and ratchet state reject replay; sender counters do not reject delayed messages | Preserves legitimate out-of-order delivery without losing rollback detection. |
| ADR-021 | Accepted | Missing profile keys render username plus a deterministic local avatar | Avoids presenting unauthenticated profile identity during contact bootstrap. |
| ADR-022 | Superseded by ADR-028 and ADR-030 | Recovery restores history separately from current secure membership | The server no longer stores history; history transfer and identity recovery are separate. |
| ADR-023 | Accepted | Voice-room leave is client membership/key removal, not backend room deletion | Matches the capability-only backend and gives users an honest consequence statement. |
| ADR-024 | Accepted | A restrained neutral/indigo app-owned visual system is the production baseline | Gives Forui and Flyer builders one reproducible identity while allowing later brand assets to replace only brand tokens. |
| ADR-025 | Accepted | Hybrid X25519 + ML-KEM-768 PQXDH establishes every DM session | Protects recorded sessions against harvest-now-decrypt-later and forbids silent downgrade. |
| ADR-026 | Release gate | Use the IETF `MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519` candidate; do not assign a production ID locally | It aligns hybrid ML-KEM-768/X25519 and Ed25519 with the existing protocol. For the Android-only version-1 release, a stable published specification and registry assignment for every primitive in the mapping, an IANA-assigned MLS ciphersuite value, maintained OpenMLS/provider support, Android interoperability, and review remain mandatory; Web interoperability is a post-v1 Web release gate under ADR-033. Presentation clarified 2026-08-16, decision unchanged: the primitive mapping and the MLS suite value are tracked as two separate gates because different registries own them under different policies and on independent schedules, and the primitive identifiers are already assigned outside the MLS registry while `TBD2` is not assigned at all. This project still assigns no production identifier locally. |
| ADR-027 | Accepted | Account cross-signing and a client-signed device log authenticate devices | A hostile server cannot make an unsigned device or identity substitution trusted by clients. |
| ADR-028 | Accepted | History exists only on clients and transfers device-to-device | Matches the backend's removal of server history and states the online existing-device dependency honestly. |
| ADR-029 | Superseded by ADR-046 (2026-08-21) | Android background messaging uses best-effort polling, not a persistent service | Deferrable polling alone can only ever be eventual: Doze defers it to thinning maintenance windows and the *rare* and *restricted* standby buckets disable background network entirely. ADR-046 keeps it as the mandatory floor and adds an opt-in `specialUse` foreground service above it; active voice remains foreground. |
| ADR-030 | Accepted | Recovery backup contains cross-signing identity material, not history keys | Recovery preserves verifiable account identity but cannot recreate local message history. |
| ADR-031 | Accepted | Forui-bundled Lucide icons are exposed through app-owned semantic icon tokens | Provides one coherent, locally bundled icon language without an extra icon dependency, while isolating feature code from package APIs and centralizing accessibility and RTL choices. |
| ADR-032 | Accepted | Stage piece 07 as a shared Rust core with an Android FFI adapter and defer its Web/Wasm adapter (2026-07-28) | This narrows the current implementation milestone without moving primitives into Dart or JavaScript. The future Web adapter must use the same locked core source, provider choices, serialization, and fixtures; Web crypto remains fail-closed and ADR-017, ADR-026, Android/Web parity, browser vectors, and independent-review gates remain unsatisfied until evidenced. |
| ADR-033 | Accepted | Version 1 ships Android only; Web is post-v1 (2026-07-28) | Keeps the first release on the verified Android trust and delivery boundary. Pieces 08 onward may implement Android protocol behavior without waiting for Wasm, browser workers, or Android/Web parity. The preserved Web foundation remains fail-closed and any future Web release must use the same reviewed Rust core, providers, encodings, vectors, and an independently verified worker boundary. |
| ADR-034 | Accepted | Pairwise transport v1 always mixes the signed ML-KEM-768 prekey and treats an unsigned PQ one-time prekey as additive only (2026-07-29) | The backend does not carry a signature for `pq_otpk`; allowing it to replace `pq_spk` would remove the authenticated PQ contribution. The frozen profile preserves the mandatory signed-PQ layer and gains one-time PQ forward secrecy when the optional key is present. |
| ADR-035 | Accepted | A verified monotonic prekey rotation under an unchanged device identity does not reset master-key verification (2026-07-29) | Routine seven-day rotation necessarily changes `cross_sig`. Requiring user SAS/QR every week would make safe rotation unusable. Only exact `bundle_version + 1` rotations with valid prekey/device signatures and an extending device log are routine; every other signature change remains blocking. |
| ADR-036 | Accepted | Build draft PQ MLS as a real, isolated closed-beta track while keeping the production gate closed (2026-08-02) | Phase A found that the selected suite is still an Internet-Draft with no IANA ciphersuite value, no exact maintained OpenMLS provider, no upstream MLS vectors, and no retained independent reviewer. Closed beta may nevertheless integrate the draft-06 mapping as closely as a maintained provider offers it, behind a source-only beta permit, using only maintained external cryptographic implementations and the real backend/pairwise transport. Correction of fact recorded 2026-08-16, decision unchanged: verification against the pinned vendored sources established that this yields draft-06 `TBD2`'s signature, AEAD, KDF, and hash choices but **not** its KEM `0x647a`, because `mls-rs-crypto-hpke 0.21.0` ships a pre-standard X-Wing variant that reports an unassigned HPKE `kem_id`. Beta groups are hybrid ML-KEM-768/X25519 but are not `TBD2`-conformant and are not `TBD2` interoperability evidence; `docs/mls-profile.md` holds the evidence table. Beta uses an MLS Private Use identifier, a distinct Android application ID and provisioning namespace, and disposable state that must be reinitialized rather than silently migrated when the draft or identifier changes. This decision does not satisfy or weaken ADR-017/ADR-026, does not authorize a classical fallback or production KeyPackage path, and production continues to resolve the unsupported adapter until all seven production gates are evidenced (six until 2026-08-16, when the combined specification/identifier gate was split into separately evidenced primitive-mapping and MLS-suite-identifier gates; nothing was merged away or marked satisfied). |
| ADR-037 | Accepted | Closed-beta MLS transport v3 carries the complete authenticated control transcript needed for later Welcome and re-add; v2 beta groups are recreated, never silently upgraded (2026-08-09) | A later member cannot authenticate the product roster from only the current Invite. V3 therefore binds every prior deterministic control projection to its exact signed payload and signer Authentication Service proof, replays the bounded transcript from the initial state, joins the Welcome, and compares the Rust-returned BasicCredential roster with the reconstructed product roster before one atomic commit. Existing members verify the same transcript. The transcript is capped at 512 entries and fails closed on absence, disagreement, replay, authorization failure, or malformed credentials. V2 state and queued objects are disposable closed-beta data and must be recreated/rejoined; this is not a production migration or permission to open the production gate. |
| ADR-038 | Superseded by ADR-041 (2026-08-17) | Same-revision control forks converge on the lexicographically smallest control state hash; a superseded branch is recovered by remove/re-add, never by rollback (2026-08-16) | RFC 9420 assumes a delivery service that serializes commits and rejects the losers. This project's backend is an untrusted relay and group objects ride per-recipient pairwise envelopes, so no server order exists. Every branch already carries a control state hash over its full signed descriptor, so ordering by that hash is total, deterministic, and needs no extra round trip or server trust. A sibling is authenticated, replayed against the reconstructed shared parent, and authorized before it may influence the decision, so a hostile relay cannot force a quarantine with an invented low-ordering branch. An applied MLS commit cannot be rewound because the previous epoch secrets are gone by construction; a superseded local branch is therefore fork-quarantined and rejoins through the existing remove/re-add path. This is closed-beta convergence behavior and does not open any production gate. |
| ADR-039 | Accepted | Leave is a two-phase departure: a non-membership announcement by the leaver, then the active owner's Remove commit that evicts the leaf (2026-08-16) | RFC 9420 section 12.4 states "A Commit MUST NOT remove the committer", because the committer must know the new epoch secrets; `remove_members_operation` already enforces this and rejects self-removal. The beta control model nevertheless classified `Leave` as membership-changing in both `group_model.dart` and `mls_beta.rs`, and `read_group_control_descriptor` rejects a membership-changing control without a commit hash, so a leaver was required to produce a Commit it is forbidden to produce. `Leave` is therefore reclassified as non-membership in both places. **Phase 1:** the departing member signs a leave at the current epoch, carrying no Commit; every device projects the member to `left`, which means "departure announced, eviction pending", and the leaver's own projection moves to `GroupLifecycle.left`. Because no Commit is involved the leaver is still cryptographically present at that epoch and processes its own announcement like everyone else, so `removedLocally` covers `Remove` only. **Phase 2:** the active owner commits the `Remove` that actually evicts the leaves and rotates the epoch, moving the member to `removed`. The owner is the deterministic committer because `canLeave` only permits an owner to leave as the last active member, so any group that still has members still has exactly one active owner; restricting eviction to that single committer keeps concurrent eviction commits, and the fork they would cause, off the wire. `GroupAuthorization.isEvictable` keeps `left` a valid Remove target — a departed leaf still holds the epoch secret, so eviction is a security obligation, not bookkeeping — while an already `removed` member is not a target again. `GroupPendingEvictionService` runs as post-inbox work, evicting at most one member per group per pass so a partial sweep is always resumable, and treating a concurrent-control conflict as a retry rather than an error. A sole owner leaving needs no committer: nobody remains to be protected from. |
| ADR-040 | Accepted | The closed-beta hybrid KEM is not changed; the complete divergence from `TBD2`'s KEM `0x647a` is recorded, and supplying a conformant KEM through `mls-rs`'s public extension points would be a project-local cryptographic fork (2026-08-17) | The beta already delivers everything ADR-036 asked of it — hybrid ML-KEM-768/X25519 confidentiality from a maintained implementation, `TBD2`'s exact signature/AEAD/KDF/hash mapping, no classical fallback, disposable state on Private Use `0xFE4C` — and the KEM divergence costs only `TBD2` interoperability, which no gate can consume while `TBD2` has no IANA suite value and no upstream PQ vectors exist. The pinned `mls-rs` crypto crates are already the newest published versions, so no maintained fix exists to adopt, and no maintained provider implements `TBD2` at all. Correcting the KEM in place would mean authoring the combiner, the raw-X25519 KEM, the SHAKE-256 expansion, and the encapsulation-key check in project code, because `AwsLcCipherSuite` cannot be re-parameterized — which is what production gate 3 and ADR-017 exclude, closes no gate, and would be written against a specification still in motion. Full reasoning, the ten-row divergence set, and the rejected alternatives are in "ADR-040 in full" below and in `docs/mls-profile.md`. This decision opens no production gate. |

| ADR-041 | Accepted | Same-revision control forks converge on an ordering key the branch author cannot vary — operation precedence class, then the signer's authority in the shared parent, then the signer's authenticated user and device id, then the control state hash; supersedes ADR-038 (2026-08-17) | ADR-038 ordered siblings by the control state hash alone. That hash is SHA-256 over the signed descriptor, and the descriptor's 16-byte event id is free author-chosen entropy that nothing binds, `created_ms` is an unvalidated `u64`, and Ed25519 is deterministic, so one grinding trial is one signature plus one hash and produces an independent uniform ordering value. Measured on the shipped signing path: about 24,500 candidate branches per second per core, and 9 trials to land below one known rival. A member facing eviction sees the `Remove` first, so it could undercut it for well under a millisecond of work and quarantine the evicting owner instead. Ordering now reads the operation's precedence class first, so an eviction cannot lose to a metadata edit, an invite, or a leave; then the signer's role in the reconstructed shared parent, so an evicted admin's counter-`Remove` loses to the owner's; then the authenticated signer identity. The hash is reached only between two branches from one device, where ordering decides nothing that author could not decide by choosing which branch to send. Every input is either fixed by the shared parent or bound to an authenticated device credential, so no participant can bias the outcome, and the rule stays total, deterministic, server-independent and free of extra round trips. Sibling authentication, replay against the reconstructed parent, and authorization are unchanged, and a superseded branch is still recovered by fork-quarantine plus remove/re-add. This is closed-beta convergence behavior and opens no production gate. |

| ADR-042 | Accepted | The Private Experimental Beta ships under a frozen application ID and one persistent signing key, separate from Production, which stays unsigned (2026-08-19) | Android accepts an update only when both the application ID and the signing certificate match the installed app; otherwise the only path forward is uninstall, and this client cannot survive one. Uninstalling erases all app data, here both the SQLCipher database and the `no_backup` envelope holding its key, the manifest sets `allowBackup="false"` so nothing restores either, and the database key is protected by a non-exportable AndroidKeyStore key so no exportable copy exists; local message history has no server-side copy by design. Identity was therefore frozen before any external install rather than after: `com.example.communication_platform.beta` was a documented placeholder awaiting branding, and shipping it would have guaranteed a later forced reinstall, so the flavors move to `dev.nimashadloo.chat{,.beta,.development}` under a domain the project already operates. Beta and Production take separate keys because their application IDs differ, so they coexist and no upgrade path between them can ever exist; a shared key would buy no continuity while dragging Production's identity into the Beta's warmer custody and widening compromise blast radius. Production release keeps no signing config at all, so it packages unsigned: it still builds and is verified in CI, but the OS cannot install it, which is fail-closed by construction. Beta signs v2+v3 without the legacy v1 scheme, which minSdk 24 makes unnecessary; v3 records the signer so a rotation lineage stays possible on API 28+, though rotation requires the original key, so key loss is not recoverable by rotation. Private material never enters source control: Gradle reads it from the environment or an untracked properties file, absence is a hard build failure, and the public certificate fingerprint is committed so every artifact is verified against the identity it must match. |

| ADR-043 | Accepted | The client's own transport trusts the provisioned private CA exclusively; Android's network security configuration is retained as defence in depth for non-Dart traffic only (2026-08-20) | Release validation of a real signed Beta APK found the app could not reach a healthy, correctly provisioned server. Every network precondition held - DNS, TCP, TLS from the host, a chain verifying against the provisioned CA, ~1.1s latency - and removing the pin-set from a diagnostic build changed nothing. The cause is that Android's `network_security_config` governs the platform's Java HTTP stacks and WebView, while this app's REST and WebSocket traffic both run on `dart:io`, which does not consult it. The configuration was therefore protecting no traffic at all: the app was simultaneously unable to reach its own server and, had it reached one, unpinned. Trust now comes from a `SecurityContext` built with `withTrustedRoots: false` plus the provisioned authority, so the built-in root store is **replaced** rather than extended and no public authority can issue a certificate this client accepts; chain construction, expiry, and hostname verification are still performed in full by BoringSSL. Both transports share one context, and the authority reaches the app as `<ENV>_PRIVATE_CA_PEM_BASE64` because `dart:io` verifies against a certificate, not the digest the configuration previously carried. Absent or malformed authority material fails configuration closed rather than falling back to public roots. Leaf SPKI pinning is deliberately **not** reimplemented in Dart: `X509Certificate` exposes no SPKI accessor and no SHA-256, so it would require hand-written ASN.1 parsing plus a hashing dependency inside the TLS path, which `AGENTS.md` forbids and which would be unreviewed cryptographic code. Anchoring exclusively to a single offline private root is a stronger constraint than the public-CA-plus-leaf-pin model it replaces, and the residual exposure - a stolen CA key minting a new leaf - is accepted for the closed beta and recorded here. The rendered Android configuration and its two pins are kept and still verified in the artifact, but only as defence in depth for any future WebView or Java-side traffic; no document may claim they protect the app's API traffic. Health checks now distinguish `trustRejected` from ordinary connectivity so a refused certificate is never reported, or retried, as an outage. |

| ADR-044 | Accepted | The initial deployment is one Private Experimental Android artifact carrying declared maturity tiers, distributed privately under the frozen Beta identity, while Production stays uninstallable (2026-08-20) | A 20-30 person private deployment needed one authoritative definition, and the repository did not have one. Inspection found the existing build-time separation correct and worth keeping - three flavors, three application IDs, two Cargo profiles whose native symbol sets are verified in the packaged artifact, a signing identity attached only to Beta, and `signingConfig = null` on the release build type so Production packages unsigned and the OS cannot install it. It also found the separation incomplete in one place: `groupFeatureAvailabilityProvider` derived availability from the development-preview permit alone, which requires `!kReleaseMode`, so every group screen in the shipped Beta artifact rendered the closed gate while that same artifact composed `NativeBetaGroupMls`, ran `GroupKeyPackageMaintenanceService`, and processed inbound group objects - uploading MLS KeyPackages for groups no user of it could create. One source-only `GroupProductionGate.privateExperimentalPermit` now decides both the stack and its screens, and the screens gate on `isAvailable` rather than naming one tier. The deployment is defined as **experimental, not beta**: nothing in it has been independently reviewed, its group suite is MLS Private Use `0xFE4C` and is not `TBD2`-conformant (ADR-040), and it has no background delivery, notifications, voice, or search. The frozen application ID keeps its `.beta` suffix because ADR-042 makes it unchangeable and an identifier is not a claim; every user-facing string says Experimental. One artifact carries three declared tiers - supported (pairwise messaging, identity, devices, attachments, history transfer), experimental (closed-beta PQ MLS groups, whose state is disposable by ADR-036 and is disclosed as such on every group screen), and visibly absent (voice, search, notifications, background delivery). Confidentiality, integrity, client-side verification, hybrid PQXDH with no fallback, provisioned-CA-only transport, encrypted local state, key continuity, and the Beta/Production artifact separation all stay mandatory; independent review, registry assignment, interoperability, upstream vectors, reproducible builds, and background delivery are deferred with their residual risk recorded and disclosed to users in writing at handover. Piece 19's closed-beta half is delivered as the experimental tier and its production half stays blocked on the same five external prerequisites; piece 20 is re-scoped from "after every production gate" - unreachable, and therefore dead rather than blocked - to a decision about which MLS exporter may key real-time media, which this decision does not grant. Opens no production gate and supersedes nothing. |

| ADR-045 | Accepted | One application-level maturity word - Experimental - two feature labels that only ever read *down* from it, and one mandatory first-run disclosure inside the enrollment gate that already exists; amends two rows of ADR-044's tier table (2026-08-20) | ADR-044 defined what the deployment *is* and deferred what the software *says*. Inspection of the running surfaces found four different vocabularies reaching users and two of them false in the artifact that carries them: the task-switcher title called the Private Experimental build "Communication Platform (Development)" while its own launcher label said Experimental; the wide navigation rail carried a permanent "Structural placeholder - not for shipping" footer in **every** build including production; Edit Profile claimed a "development-only fake transport" in a build that composes no profile adapter at all, so Save could only fail; and the composer's paperclip opened three inert options because no build composes an attachment picker or transfer service. Those last two are also a correction to ADR-044, whose supported tier listed encrypted profiles and attachments: both are absent and are now labelled **Not built yet**. Terminology was re-derived rather than inherited and landed in the same place for a better reason - Google's published launch-stage definition of Experimental ("not intended for production use or covered by any SLA, support obligation, or deprecation policy and might be subject to backward-incompatible changes", read at primary source 2026-08-20) describes this artifact exactly, including the backward-incompatible clause that is ADR-036's disposable group state, while Preview promises the previewed thing ships and Beta promises feature completeness. Consent reuses `EnrollmentPhase.securityNotice`, which is already mandatory, already durable in the enrollment journal, and already withholds messaging until accepted, rather than adding a second blocking screen that would split the attention paid to both. Seven disclosure points state only the facts that make an ordinary expectation wrong - no review, foreground-only delivery, device-only history, recovery without history, resettable groups, unbuilt surfaces, intended use - and cryptographic identifiers are excluded by decision because printing them beside those seven would bury them. Periodic re-acknowledgement is rejected on measured evidence that repetition destroys a warning and that the damage generalises to this app's genuinely blocking security states; re-consent is content-triggered through `DeploymentDisclosure.revision`, pinned by a test to the exact disclosure text. There is deliberately no label meaning supported, stable, verified or audited: the absence of a badge must never read as an assurance. Opens no production gate and supersedes nothing. |

| ADR-046 | Accepted | Background message delivery is layered — a composed foreground socket, a best-effort WorkManager floor, and an opt-in `specialUse` foreground service holding the same connection — and a notification is a projection of committed local state, never of the transport; supersedes ADR-029 (2026-08-21) | ADR-029 chose best-effort polling and no persistent service. Inspection of the composed artifact found something else entirely: `SyncLifecycleSupervisor`, `DioWebSocketGateway`, `GatewayRealtimeSyncAdapter` and `NetworkingFoundation` exist, are tested, and are constructed **only in tests**, and `durableSyncEngineProvider` is read by nothing, so the shipped build neither drains its mailbox nor transmits its outbox — `SendConversationEvents` ends at `fanout.prepareAndQueue` and the rows stay there. ADR-045's disclosure "messages arrive only while this app is open" is therefore wrong in the user's favour and is corrected here. On the platform, primary sources read 2026-08-21 leave a narrow design space: a backgrounded process is cached, and "if all processes for a particular app are frozen, the system terminates any active TCP sockets maintained by the app", so an unattended socket is closed rather than slow; `WorkManager`'s floor is 15 minutes, Doze defers `JobScheduler` to maintenance windows that thin out over time, Android 16 enforces job quota even in the active standby bucket, and the *rare* and *restricted* buckets disable background network outright, so deferrable work can only ever be *eventual*; while-idle alarms buy six minutes of best-case cadence for a user-revocable `SCHEDULE_EXACT_ALARM` and still wake an app that has no network. The one documented state with unrestricted background network is "app process is running a foreground service", and Android's own Doze acceptable-use table rates the battery-optimization exemption **Acceptable** for an "instant messaging, chat, or calling app" that "can't use FCM because of technical dependency", which is this application exactly — the exemption granting that an app "can use the network and hold partial wake locks during Doze and App Standby" and being itself an exemption from the Android 12 background FGS-start restriction. The type is `specialUse` with a truthful subtype property, because `dataSync` is capped at 6 h/24 h and barred from `BOOT_COMPLETED` at `targetSdk` 35+, `remoteMessaging` means device-to-device continuity, and `systemExempted` is gated on roles this app lacks; the existing test forbidding `remoteMessaging` and `FOREGROUND_SERVICE_DATA_SYNC` in the manifest stands unchanged. Exactly one delivery owner runs at a time, held as a durable Drift lease rather than an in-memory flag, because concurrent isolates would race a *rotating* refresh token and can invalidate the session. Notifications fire only from the existing `PostInboxCommitWorkPort` after the inbox transaction commits, deduplicated by a durable `notified_at`, recovered by query rather than replay, and bounded by a grouped summary. Reliability is stated in four tiers and never as a guarantee: near-real-time foregrounded; near-real-time best-effort backgrounded when the user has granted the exemption and their vendor cooperates; eventual otherwise, and nothing at all in the *rare* and *restricted* buckets; and nothing whatsoever after force-stop, which no design can change. The costs are accepted and disclosed: a persistent shade entry that makes the app observable on the device, real battery use, two permissions, and per-vendor setup on the 77% of the Iranian fleet that is Samsung or Xiaomi (Statcounter, July 2026). Layer 2 ships off by default and may not be enabled in any distributed artifact before the physical-device matrix runs; UnifiedPush was rejected because the backend has no push endpoint and may not be changed, it needs a second app and a second service per user, and it moves message-timing metadata outside the reviewed boundary without removing the Android constraint; SMS wake was rejected outright for binding accounts to carrier-held phone numbers. No experiment was run: only Play-Store emulator images without root were available and no Samsung or Xiaomi hardware, so a local result would have proved nothing about the fleet that matters. Reaffirms ADR-013, opens no production gate, changes no cryptographic behaviour, and adds no dependency by itself. |

## ADR-046 in full — how a backgrounded Android client learns a message arrived (2026-08-21)

### The question

The deployment is roughly 20–30 private users in Iran. The failure condition this
project is built for is that international connectivity is unavailable while domestic
connectivity keeps working, and the backend is inside Iran and stays reachable through
the domestic network. Backend reachability is therefore **not** the problem this
decision solves and is treated as given.

The problem is the one that remains after the server is reachable: **when the user is
not looking at the application, how does the Android client find out that an envelope is
waiting in its domestic mailbox, and how does it tell the user?**

No technology was assumed. `WebSocket`, polling, WorkManager, foreground services, local
notifications and platform push were all treated as candidates to be argued for or
rejected on evidence, including the ones already named in ADR-029 and in
`platform-android.md`.

### What the repository actually does today

Inspection of the composed application, not of its documentation, found this:

| Component | Exists in `lib/` | Composed into the running app |
|---|---|---|
| `DurableSyncEngine` (drain, inspect, commit, ack, outbox) | yes, 509 lines, tested | **no** |
| `SyncLifecycleSupervisor` (lifecycle, reconnect, backoff, polling triggers) | yes, 299 lines, tested | **no** — constructed only in tests |
| `DioWebSocketGateway` (authenticated socket, close-code mapping) | yes, 381 lines, tested | **no** |
| `GatewayRealtimeSyncAdapter` (socket event → drain hint) | yes | **no** |
| `NetworkingFoundation` (the one client + coordinator + gateway) | yes | **no** — nothing constructs it |
| `AndroidPollingScheduler` | port only | no adapter exists |
| Local notifications | — | no dependency, no port, no adapter |

`durableSyncEngineProvider` is declared in `lib/app/dependencies/sync_providers.dart`
and is read by nothing: a repository-wide search for it, for `syncProjectionProvider`,
for `SyncLifecycleSupervisor` and for `GatewayRealtimeSyncAdapter` returns their
declarations and their unit tests, and no presentation, controller, router or bootstrap
reference at all. `bootstrap.dart` composes `AuthenticationAssembly`, which builds a REST
client and a token coordinator and no socket.

The consequence is larger than a missing notification. `SendConversationEvents` ends at
`fanout.prepareAndQueue`, which writes durable outbox rows; the component that would
transmit them is the engine that never runs. **In the artifact as composed, a sent
message is queued locally and never leaves the device, and an incoming envelope is never
drained.** Sending and receiving are both unwired, not merely un-notified.

### The defect this decision had to resolve first

ADR-044 and ADR-045 tell every recipient, in the mandatory enrollment disclosure, that
"messages arrive only while this app is open". Measured against the composed artifact
that sentence is not conservative, it is **wrong in the user's favour**: messages do not
arrive while the app is open either. The disclosure describes ADR-029's intended
architecture rather than the shipped one.

That correction is recorded here because it changes what this decision is. This is not
"add notifications to a working messenger". It is "decide the delivery and notification
architecture for a messenger whose delivery path exists, is tested, and has never been
plugged in". Any notification mechanism chosen below is worthless until that path is
composed, so composing it is step one of the follow-up work and is not optional.

### Exact network and deployment assumptions

Fixed for this decision:

- International connectivity may be entirely unavailable; domestic Iranian connectivity
  keeps working and reaches the backend.
- The backend is inside Iran, is the authoritative durable mailbox
  (`GET /api/v1/me/envelopes`, seven-day TTL, `pruned_through`), and also offers the
  `wss://<host>/ws` gateway, whose `envelope` frame the client already treats as a
  wake-up hint only.
- Distribution is a directly installed signed APK under the frozen Beta identity
  (ADR-042, ADR-044). **Google Play policy does not bind this artifact**, because it is
  never submitted to Play. Platform behaviour still binds it completely.
- `minSdk` 24, `targetSdk` 36, `compileSdk` 36 (Flutter 3.44.7 defaults, read from the
  pinned SDK on 2026-08-21). The client must therefore behave correctly against Android
  16 restrictions while still running on Android 7.
- Fleet: Statcounter for Iran, July 2026, read 2026-08-21 — Samsung 46.34%, Xiaomi
  30.98% (77% combined); Android 13 20.38%, 14 15.77%, 16 14.09%, 12 13.60%, 11 13.55%,
  15 10.10%. The two most aggressive OEM background-management vendors are the fleet, and
  every supported release from 11 to 16 is materially represented.
- ADR-013 stands: no foreign push, no Firebase, no foreign runtime call. FCM is excluded
  twice over — by decision, and by the premise that Google's servers are unreachable
  exactly when this application is most needed.

### Research findings — what Android actually guarantees

All from primary sources, read 2026-08-21.

**A process that is merely backgrounded cannot hold a connection.** Android 14 states
that "an app's process is in a cached state when it's moved to the background and no
other app process components are running", and that "shortly after an app process enters
a cached state, background work is disallowed, until a process component re-enters an
active state of the lifecycle"
([behaviour changes, all apps](https://developer.android.com/about/versions/14/behavior-changes-all)).
AOSP is blunter about what happens next: "When an app process is frozen, all of its
threads are suspended and can't perform CPU work until unfrozen", and "if all processes
for a particular app are frozen, the system terminates any active TCP sockets maintained
by the app"
([cached apps freezer](https://source.android.com/docs/core/perf/cached-apps-freezer)).
A background `WebSocket` with no running component is not slow; it is closed by the
platform.

**Deferrable jobs are quota-bound, and in two standby buckets have no network at all.**
Android's power-management table
([power details](https://developer.android.com/topic/performance/power/power-details))
gives, per app standby bucket: *active* — jobs up to 20 min per rolling 60 min, no
network restriction; *working set* — 10 min per 4 h, 10 alarms/h; *frequent* — 10 min per
12 h, 2 alarms/h; *rare* — 10 min per 24 h, 1 alarm/h, **network disabled**;
*restricted* — once per day for up to 10 min, one alarm per day, **network disabled**.
The same page notes "execution quota behavior for jobs changed in Android 16. Prior to
Android 16 there was no execution limit when the app is in the active standby bucket",
which Android 16's own notes confirm applies to "tasks scheduled using WorkManager,
JobScheduler, and DownloadManager"
([Android 16 behaviour changes](https://developer.android.com/about/versions/16/behavior-changes-all)).
`WorkManager`'s floor is fixed: "the minimum repeat interval that can be defined is 15
minutes (same as the JobScheduler API)"
([define work](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work)).

**Doze suspends the very things a poll needs.** In Doze the system "suspends network
access", "ignores wake locks", "defers standard `AlarmManager` alarms", "doesn't let
sync adapters run" and "doesn't let `JobScheduler` run. `WorkManager` uses
`JobScheduler` internally, so `WorkManager` tasks don't run", releasing them only in
maintenance windows that "over time … the system schedules … less frequently"
([Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)).
While-idle alarms are the escape hatch and are themselves throttled: "neither
`setAndAllowWhileIdle()` nor `setExactAndAllowWhileIdle()` can fire alarms more than once
per nine minutes, per app", and the power table caps while-idle alarms at 7 per hour.

**A foreground service is the one documented way to keep both the process and the
network.** The power table's app-state axis gives "app process is running a foreground
service → Network: No restrictions", and by Android 14's own definition a process with a
running service component is not cached, so it is not frozen and its sockets are not
terminated. Foreground services are not equal, though:

- `dataSync` "is not allowed to launch … from a `BOOT_COMPLETED` broadcast receiver" for
  apps targeting Android 15+, and is capped: "the system permits an app's `dataSync`
  services to run for a total of 6 hours in a 24-hour period", after which
  `Service.onTimeout()` fires and a failure to stop produces
  `RemoteServiceException`, while a further start throws
  `ForegroundServiceStartNotAllowedException`
  ([Android 15 behaviour changes](https://developer.android.com/about/versions/15/behavior-changes-15),
  [FGS timeouts](https://developer.android.com/develop/background-work/services/fgs/timeout)).
- `shortService` runs "about 3 minutes" and ANRs if it overruns.
- `remoteMessaging` has no runtime prerequisite, no timeout and no boot restriction, but
  its documented description is narrow: "Transfer text messages from one device to
  another. Assists with continuity of a user's messaging tasks when they switch devices."
- `specialUse` "covers any valid foreground service use cases that aren't covered by the
  other foreground service types", has no runtime prerequisite, no timeout and no boot
  restriction, and asks the developer to declare the use case in a manifest `<property>`
  whose values "are reviewed when you submit your app in the Google Play Console"
  ([FGS types](https://developer.android.com/develop/background-work/services/fgs/service-types)).
- `systemExempted` is gated on being a device owner, VPN, emergency-role or exact-alarm
  app, and otherwise throws `ForegroundServiceTypeNotAllowedException`.

**Starting that service from the background is allowed in exactly the cases we have.**
Apps targeting Android 12+ "can't start foreground services while the app is running in
the background, except for a few special cases", and the enumerated exemptions include
receiving `ACTION_BOOT_COMPLETED`, `ACTION_LOCKED_BOOT_COMPLETED` or
`ACTION_MY_PACKAGE_REPLACED` in a receiver, invoking an exact alarm for a user-requested
action, and — decisively — "the user turns off battery optimizations for your app"
([background-start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)).

**Android's own guidance sanctions the battery-optimization exemption for precisely this
application.** The Doze page's acceptable-use table lists "instant messaging, chat, or
calling app" twice. Where the app *can* use FCM, exemption is "Not Acceptable — use FCM
high priority messages". Where the app answers "no, can't use FCM because of technical
dependency on another messaging service or Doze and App Standby break the core function
of the app", exemption is "**Acceptable**". What the exemption buys is stated exactly:
"an app that is partially exempt can use the network and hold partial wake locks during
Doze and App Standby. However, other restrictions still apply … its regular
`AlarmManager` alarms don't fire." The Play-policy sentence attached to that table does
not reach a directly distributed APK, but the technical grant does.

**Notifications need a permission that can be refused.** `POST_NOTIFICATIONS` arrived in
Android 13; "if a user installs your app on a device that runs Android 13 or higher, your
app's notifications are off by default", and on refusal "your app can't send
notifications unless it qualifies for an exemption. All notification channels are
blocked"
([notification permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)).
An app targeting 33+ chooses when to ask.

**Force-stop is absolute.** An app the user force-stops, or that has never been launched
since install, is in the stopped state and receives no broadcasts and runs no scheduled
work until the user launches it manually. No architecture changes this.

**OEM behaviour is the fleet's dominant variable and is not specified by AOSP.** Android
itself only says "the precise restrictions imposed are determined by the device
manufacturer"
([background-task restrictions](https://developer.android.com/develop/background-work/background-tasks/bg-work-restrictions)).
Community documentation for Samsung ("put apps to sleep", adaptive battery, unused-for-
three-days background start blocking, settings that revert after updates) and Xiaomi
(autostart permission, MIUI/HyperOS battery saver) is not normative evidence and is
recorded here as a *risk to be measured on devices*, not as a fact this decision rests
on. It is the reason the physical-device matrix is a release gate rather than a nicety:
77% of the target fleet is Samsung or Xiaomi.

### Alternatives evaluated

**1 — Foreign push (FCM/APNs).** Rejected on the premise, not on preference. FCM's
transport is Google infrastructure reached over international links; during the exact
outage this deployment exists for, it is unreachable. ADR-013 already forbids it. It is
also the only mechanism whose absence Android's own documentation accepts as grounds for
the Doze exemption, so its rejection is what unlocks alternative 5.

**2 — Foreground-only delivery (the status quo, and ADR-029's practical outcome).**
Works while the app is open, needs no permission, costs no battery, leaks nothing, and
provides *no* notification. It is what the current disclosure promises. Rejected as the
final answer, because the whole question is what happens when the app is not open — but
kept as the innermost layer, since it is strictly the best tier when it applies.

**3 — Deferrable background work only (WorkManager/JobScheduler), i.e. ADR-029 as
written.** Survives reboot through WorkManager's own rescheduling, needs no special
permission, costs little battery, and is the mechanism the backend contract names ("no
foreign push (FCM/APNs) is available. Background polling only", `CLIENT_CONTRACT.md` §L).
Its ceiling is hard: 15-minute floor, Doze deferral to maintenance windows that thin out
over time, Android 16 quota enforcement even in the active bucket, and **no network at
all** in the *rare* and *restricted* buckets — which is where an app the user has not
opened for days will sit. It yields *eventual* notification and cannot honestly be
described as anything better. Rejected as the primary mechanism; **retained as the
guaranteed floor**, because it is the only layer that needs nothing from the user.

**4 — While-idle alarms (`setAndAllowWhileIdle` / `setExactAndAllowWhileIdle`).**
Slightly better best-case cadence than WorkManager (nine minutes rather than fifteen) and
fires inside Doze. Rejected: the exact variant needs `SCHEDULE_EXACT_ALARM`, which the
user grants and can revoke — and on revocation "your app stops, and all future exact
alarms are canceled" — or `USE_EXACT_ALARM`, whose acceptable use is an alarm-clock or
calendar core function this application does not have; alarms are cancelled by reboot and
must be re-armed from a boot receiver; and, fatally, an alarm that fires in the *rare* or
*restricted* bucket wakes an app that still has no network. It buys six minutes of
best-case latency for a revocable permission and a semantic overstatement.

**5 — An opt-in persistent connection held by a foreground service.** The only
mechanism that produces near-real-time delivery without Google. It defeats the freezer by
keeping a service component running, and the power table grants that state unrestricted
network; the battery-optimization exemption, which Android's own table calls acceptable
for a chat app that cannot use FCM, additionally grants network and partial wake locks
during Doze and App Standby, and is itself an exemption from the Android 12 background
FGS-start restriction. Costs: a permanent status-bar entry, real battery use, two user
permissions, per-OEM setup on 77% of the fleet, and nothing at all after force-stop.
**Selected, as an opt-in layer above the floor.**

**6 — Self-hosted push through UnifiedPush (a domestic ntfy/NextPush distributor).**
Genuinely the right pattern in general: one distributor app carries the persistent
connection for many applications, the push server can be self-hosted inside Iran, and no
Google dependency appears. Rejected here for four reasons, any one of which is
sufficient. (a) The backend has no push endpoint of any kind and this work may not modify
backend files, so the server half cannot be built. (b) It requires every user to install
and configure a second application and the project to operate a second self-hosted
service, for a 20–30 person deployment. (c) The distributor learns *when* each user
receives a message; that timing metadata moves outside the reviewed trust boundary to a
component this project does not sign, pin, review or update, which is a worse trade than
the one it replaces. (d) It does not remove the Android constraint — the distributor
needs the same foreground service, the same exemption and the same OEM settings — it
relocates it into software the project cannot fix. Worth revisiting only if the backend
ever grows a push endpoint and the metadata question is answered.

**7 — SMS-triggered wake.** The one mechanism genuinely independent of data
connectivity, and the only one rejected on security grounds alone. It requires an SMS
receive permission, requires the backend to send SMS, binds every account to a phone
number held by a carrier, and hands the carrier a precise log of who is messaged and
when. That is the opposite of this project's threat model. Rejected outright.

**8 — `dataSync` or `remoteMessaging` for the foreground service, or `systemExempted`.**
`dataSync` is disqualified by the platform: 6 hours per 24, and no launch from
`BOOT_COMPLETED` at `targetSdk` 35+. `remoteMessaging` is technically unrestricted but
describes device-to-device message continuity, not "hold a socket to my own server";
`platform-android.md` already forbids reaching for it to dodge lifecycle policy, and that
rule survives this decision. `systemExempted` is gated on roles this app does not have.

### Decision

**Delivery and notification are layered, each layer honest about its tier, and all of
them converge on the one durable engine that already exists.**

**Layer 0 — compose what is already built (mandatory, no user action).**
`SyncLifecycleSupervisor`, `GatewayRealtimeSyncAdapter`, `DioWebSocketGateway` and the
platform adapters are wired into the application, attached to the **single**
`TokenCoordinator` and the **single** provisioned-CA `SecurityContext` that
`AuthenticationAssembly` already owns. No second REST client, no second coordinator, no
second trust context. Socket frames stay what they already are: wake-up hints that
trigger an authoritative REST drain and never carry trusted content.

**Layer 1 — best-effort deferrable catch-up (mandatory, no user action).** An Android
`WorkManager` adapter behind the existing `AndroidPollingScheduler` port: a periodic
request at the platform floor with a connected-network constraint, plus one-shot requests
on connectivity recovery and on `ACTION_BOOT_COMPLETED`. Its headless entry point
reconstructs protected storage, database, transport and engine and runs the same
`DurableSyncEngine.synchronize()`. It promises nothing exact and never starts a service.

**Layer 2 — an opt-in persistent-connection foreground service (off by default).** A
`specialUse` foreground service that keeps the process non-cached so the already-composed
socket survives, declared with a truthful
`android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE`. It hosts the same Dart isolate and the
same supervisor; it adds no second delivery implementation. It is started when the user
enables background delivery, and re-started from an `ACTION_BOOT_COMPLETED` receiver.
Enabling it walks the user through `POST_NOTIFICATIONS`, through
`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, and through the vendor settings the
application cannot check for itself.

**Layer 3 — notification as a projection of durable local state.** A `NotificationPort`
whose only trigger is the existing `PostInboxCommitWorkPort` composite, running after the
inbox transaction commits. It reads rows that are committed, unread, and not yet
notified; it posts; it records a durable `notified_at` in the same transaction. Nothing
about the transport reaches it.

**Exactly one delivery owner at a time.** The foreground isolate, the service isolate and
the headless worker isolate must never run the engine concurrently: they would open
several sockets and, far worse, several `TokenCoordinator` instances racing on a
*rotating* refresh token, which can invalidate the session. Ownership is a durable
leased row in Drift with an owner identity and a heartbeat, not an in-memory flag, so a
crash releases it and a restart reclaims it. Layer 1 stands down while Layer 2 holds the
lease — the supervisor already cancels polling whenever it takes over.

### Why `specialUse`

`specialUse` is the type Android defines for "any valid foreground service use cases that
aren't covered by the other foreground service types", and holding an authenticated
connection to the application's own self-hosted server, in a country where the platform's
push transport is unreachable, is exactly such a case. It carries no timeout, no
`BOOT_COMPLETED` prohibition and no runtime prerequisite, and its mandatory subtype
property is a place to write the truth in the manifest rather than a place to hide.
`remoteMessaging` would be a semantic overstatement of a type that means device
continuity; `dataSync` would be both an overstatement and technically unusable. The
existing architecture test that forbids `remoteMessaging` and
`FOREGROUND_SERVICE_DATA_SYNC` in the manifest therefore remains correct and unchanged,
and this decision does not weaken it.

Play review is not a factor because this artifact is never submitted to Play; if that
ever changes, the subtype property already states the justification, and "the deployment
country cannot reach FCM" is a real one.

### Notification versus synchronization

They are deliberately different mechanisms and this decision keeps them apart.

- **Discovery** has three independent triggers — a socket `envelope` frame, a
  lifecycle/network/lease transition, and a WorkManager tick — and all three do the same
  thing: request one engine cycle.
- **Retrieval** is always the authoritative REST drain with post-commit acknowledgement.
  A socket payload is never the message.
- **Unread state** is already durable and already maintained: `conversations.unread_count`
  and `messages.unread` are written by `DriftApplicationEventProjector` inside the commit
  transaction and cleared by the conversation repository on read.
- **Notification** is generated only from that committed state, only after authenticated
  decryption, and never from an envelope that was quarantined, rejected, or blocked by
  queue-gap recovery.
- **Duplicates** are prevented twice: envelope identity already deduplicates delivery, and
  a durable `notified_at` marker prevents a second notification for a row a re-drain
  re-observes. A durable marker is required precisely because the notifying isolate may
  not be the one that comes back.
- **Missed notifications recover by query, not by replay.** Everything unread and
  un-notified is eligible at the next successful commit pass, with a bounded number of
  individual notifications and one grouped summary beyond that threshold, so returning
  from three days offline produces a summary rather than two hundred alerts.

### Reliability, stated honestly in four tiers

No architecture available on Android delivers a **guaranteed** notification, and none
delivers an **immediate** one; that is true with a platform push service and is more true
without one. What this decision buys is the best available tier under each condition.

| Condition | Tier | What actually happens |
|---|---|---|
| App foreground, domestic network up | **Near-real-time** (seconds) | Socket hint → REST drain → commit → in-app state; a notification only if the conversation is not on screen |
| Backgrounded, Layer 2 enabled, exemption granted, OEM settings correct | **Near-real-time, best-effort** | Socket held by the `specialUse` service; same path; the platform *permits* this indefinitely but guarantees nothing |
| Backgrounded, Layer 2 off or killed | **Eventual** | 15 minutes at best; in practice bound to Doze maintenance windows, which thin out; **nothing at all** in the *rare* or *restricted* standby buckets, where background network is disabled |
| Force-stopped, or "Restricted" battery setting applied, or `POST_NOTIFICATIONS` denied | **None** | No broadcast, no job, no alarm, no notification, until the user opens the app. Unfixable by any design |
| Intermittent domestic connectivity | **Eventual, no loss inside 7 days** | Backoff reconnect, drain on every recovery, seven-day server retention, `pruned_through` turning permanent loss into a visible blocking state rather than silence |
| Process killed by the system (memory pressure) | **Best-effort recovery** | The service is restarted by the platform and Layer 1 re-runs; neither is promised |
| After reboot | **Best-effort** | `ACTION_BOOT_COMPLETED` restarts Layer 2 and rearms Layer 1 — but only if the app has been launched at least once since install and has not been force-stopped. `ACTION_LOCKED_BOOT_COMPLETED` is deliberately **not** used: the database key is credential-encrypted and nothing can be decrypted before first unlock |

### What Android guarantees, and what it merely permits

The distinction is load-bearing and must never be blurred in a user-facing string.

**Guaranteed (these are guaranteed *restrictions*, and testing cannot disprove them):** a
force-stopped app runs nothing; `dataSync` is capped at 6 h/24 h and cannot start from
`BOOT_COMPLETED` at `targetSdk` 35+; *rare* and *restricted* buckets have no background
network; a cached process is frozen and its TCP sockets are terminated; `POST_NOTIFICATIONS`
denial blocks every non-exempt channel; `WorkManager`'s periodic floor is 15 minutes.

**Merely permitted (a green test run is evidence of nothing):** that a foreground service
keeps running — the system may still kill it under memory pressure and OEMs kill more
aggressively; that an exempt app keeps network through Doze on a given vendor's build;
that `WorkManager` runs at any particular moment; that `BOOT_COMPLETED` arrives promptly;
that a vendor's battery UI leaves the user's choice in place after a system update.

Every claim in the second group must be measured on the device matrix and may never be
promoted into a promise by observation alone.

### Failure modes

- **The user never grants the exemption, or a vendor silently re-applies its own.**
  Layer 2 degrades to Layer 1 and delivery becomes eventual. The application must detect
  the lost exemption (`isIgnoringBatteryOptimizations()`) and say so plainly rather than
  keep implying real-time delivery.
- **The service is killed and not restarted.** Same degradation; Layer 1 is the floor
  that makes this survivable.
- **The app is force-stopped.** Total silence until manual launch. This is disclosed, not
  engineered around.
- **A hostile relay floods `envelope` hints.** Hints are only triggers; each causes a
  bounded, backed-off REST drain that finds nothing. The cost is battery, not
  correctness, and the existing backoff and circuit-breaker paths bound it.
- **Two isolates race the rotating refresh token.** Prevented by the durable delivery
  lease. This is the single most dangerous implementation mistake available in this design
  and must be covered by a test that runs two owners against one store.
- **A notification for content that was later quarantined.** Prevented by notifying only
  from committed, non-quarantined rows.
- **Notification storm after a long offline period.** Bounded count plus a grouped
  summary.
- **Direct-boot start before first unlock.** Fails closed: the Keystore-wrapped database
  key is unavailable, the worker must abort rather than degrade.

### Security and privacy

- **Client authentication** is unchanged: one device-bound token coordinator, one
  single-flight refresh, one durable token store. Background components attach to it;
  they never mint a second.
- **Transport trust is unchanged and must be re-asserted in every background entry
  point.** The headless isolate and the service must build the same
  `TransportSecurity.provisioned` context (ADR-043); falling back to
  `TransportSecurity.platformDefault()` in a background path would silently restore the
  public root store. This warrants its own architecture test.
- **Server events are not authenticated and are not trusted.** They are hints. All
  authentication remains in the crypto core, behind the drain.
- **Replay and duplicates** are handled by envelope identity, event identity, ratchet
  state and the new durable `notified_at`, not by in-memory state.
- **Notification content keeps the existing rule**: hidden preview by default — app name,
  sender-neutral text, open action — with decrypted previews only as an explicit opt-in
  carrying a lock-screen warning.
- **New exposure this decision creates, stated plainly:** a persistent foreground-service
  notification is a durable, visible indication on the device that this application is
  running, present on the status bar and potentially the lock screen. In this deployment
  that is not a cosmetic cost; it is an observable that survives the user putting the
  phone down, and it is the principal reason Layer 2 is opt-in rather than default. Its
  channel must be low importance, silent, and neutrally worded, and the trade must be
  described to the user in the same voice as the rest of the disclosure.
- **Timing metadata** is unchanged relative to the backend, which already sees when a
  device drains. Holding a socket makes the device's online periods more legible to the
  server, which is already an untrusted relay in the threat model; it does not create a
  new party.
- **No credential leaves its existing boundary.** The service holds no copy of the
  database key or the tokens; it hosts the same isolate and the same composition.

### User and device requirements

Unavoidable, and acceptable for 20–30 trusted users receiving a written handover:

1. Grant `POST_NOTIFICATIONS` (Android 13+). Without it there are no notifications at
   all, whatever the delivery layer does.
2. For Layer 2 only: grant the battery-optimization exemption. Android's own acceptable-
   use table sanctions asking, because this app cannot use FCM.
3. For Layer 2 on most of this fleet: vendor settings — on Samsung, exclude the app from
   "put apps to sleep" and adaptive battery; on Xiaomi, allow autostart and set battery
   saver to no restrictions. The application **cannot verify these** and must say so
   rather than imply it has checked.
4. Do not force-stop the app and do not set its battery usage to "Restricted".

The application explains this once, in one screen reached from enabling background
delivery, in the same plain register as the deployment disclosure: what it will do, what
it costs, what it cannot promise, and what the user must do on their particular phone. It
must not nag, and it must not present the vendor steps as a guarantee.

### Beta and Production

- Layers 0, 1 and 3 are suitable for both Beta and a future Production, once implemented
  and once the device matrix has been run. They introduce no cryptographic surface and
  cross no production gate.
- Layer 2 is suitable for both **as an opt-in that ships off by default**. It is not
  Beta-only — there is no reason a future production build should be worse at delivery —
  but it may not be enabled in any distributed artifact before the physical-device matrix
  on Samsung, Xiaomi and an AOSP image across Android 11 to 16 has actually been run and
  recorded.
- The Beta/Production artifact separation, the two Cargo profiles, the signing identity
  and `signingConfig = null` on release are untouched. Nothing here weakens the production
  boundary to make the private deployment work, and no production gate is opened.

### Known limitations

- Near-real-time delivery is best-effort and vendor-dependent for 77% of the target
  fleet, and cannot be made otherwise without a push service that does not exist in this
  environment.
- A force-stopped application is silent, permanently, by platform design.
- Layer 1 alone provides nothing in the *rare* and *restricted* standby buckets, which is
  where an unopened app eventually lands.
- Layer 2 makes the application visible in the notification shade whenever it is armed.
- The decision rests on documented platform behaviour; the OEM half rests on community
  reporting and is unmeasured until the device matrix runs.
- No experiment was run for this decision: the available emulator images are Play-Store
  images without root, and no Samsung or Xiaomi hardware was available, so any local
  result would have proved nothing about the fleet that matters.

### Follow-up implementation requirements

In order. Each is a piece of work, not a checkbox.

1. **Compose the delivery path** (Layer 0). Until this lands, nothing else in this ADR
   can be observed to work, and neither sending nor receiving functions at all. Includes
   resolving the two composition roots: `NetworkingFoundation` is currently dead code
   while `AuthenticationAssembly` builds the live client, and the socket must attach to
   the live one.
2. **Notification port, `notified_at` column, post-inbox-commit notifier,
   `POST_NOTIFICATIONS` request at point of use.** Useful on its own, before any
   background layer exists.
3. **WorkManager adapter behind `AndroidPollingScheduler`** (Layer 1), with the headless
   entry point reconstructing its own dependencies and failing closed before first unlock.
4. **Durable delivery lease**, with a test that runs two owners against one store.
5. **`specialUse` foreground service, boot receiver, background-delivery setting, and the
   setup screen** (Layer 2), off by default.
6. **Disclosure revision.** Shipping any of steps 2 to 5 makes ADR-045's
   `DisclosurePoint.foregroundDeliveryOnly` false. `DeploymentDisclosure.revision` must
   move, the text must be rewritten to the tier language above, and the written handover
   must be re-delivered to existing recipients. Correcting the *current* text, which
   overstates today's artifact, may not wait for step 5.
7. **Device matrix**: Doze, standby buckets, reboot, force-stop, permission revocation,
   exemption revocation and vendor battery settings, on Samsung and Xiaomi hardware and
   an AOSP image, across Android 11 to 16. This is a release gate for Layer 2.
8. **Dependency decision, recorded with pinned versions when it is made.** The preference
   is app-owned Kotlin behind ports for the notification poster and the foreground service
   — both are small, security-relevant surfaces and `MainActivity` already owns two method
   channels — and a maintained plugin only where the platform glue is genuinely large,
   which is the headless Dart entry point. `flutter_local_notifications` 22.3.0,
   `workmanager` 0.10.9 and `flutter_foreground_task` 11.0.1 all exist and none requires
   Firebase or Play services (pub.dev, read 2026-08-21); none is adopted by this decision.

### Review and revisit conditions

Reopen this decision when any of the following becomes true:

1. **The backend grows a push endpoint.** UnifiedPush against a domestic distributor
   becomes buildable, and alternative 6's balance changes — though its metadata question
   must be answered before it is chosen.
2. **A domestic push service the project controls end to end becomes available**, making
   a shared connection cheaper than a per-app one.
3. **Android changes the freezer, the standby-bucket network rules, the `specialUse`
   contract, or introduces a timeout for it.** The whole of Layer 2 rests on `specialUse`
   having no timeout and no boot restriction.
4. **The device matrix shows Layer 2 is unreliable on Samsung or Xiaomi even when
   configured.** Then near-real-time background delivery is not achievable for this fleet
   and the honest answer reverts to Layer 1 plus a truthful statement.
5. **The user base stops being 20–30 known people receiving a written handover.** The
   per-device setup burden accepted here does not survive that change.
6. **Voice ships.** A microphone foreground service already exists for active calls; the
   interaction between two foreground services and their notifications must be decided
   rather than discovered.

This decision supersedes ADR-029, reaffirms ADR-013, opens no production gate, changes no
cryptographic behaviour, and adds no dependency by itself.

## ADR-045 in full — what the application tells its users about itself (2026-08-20)

**Status:** Accepted. User-facing communication decision. **Opens no production gate.**
Amends two rows of ADR-044's tier table; supersedes nothing.

### The question

ADR-044 defined what the initial deployment *is*. It did not define what the software
*says*. It listed a persistent banner, per-tier honesty on group screens, visibly absent
features, and a written handover disclosure, and it deferred the in-app first-run
disclosure as follow-up work.

That leaves the question this decision answers: **what must a user understand before
using this application, how should the application say it, and what has to be true for
that statement to stay true?** Concretely — one maturity label or several, which words,
where they appear, whether anything must be acknowledged, and who keeps it accurate.

The answer was derived from the running application, not from ADR-044's list. That
matters, because inspecting the surfaces found that ADR-044's list was itself partly
wrong.

### What the application actually said to users, before this decision

Every row was read out of the working tree on 2026-08-20.

| Surface | What a user saw | Verdict |
|---|---|---|
| Shell and Connection banner | "Private experimental build" | Correct. Kept |
| Android launcher label (beta flavor) | "Communication Platform (Experimental)" | Correct. Kept |
| Window and task-switcher title | "Communication Platform (Development)" | **Wrong.** `app.dart` branched on `isProduction` alone, so the Private Experimental artifact named itself a developer build in the task switcher while its own launcher icon said Experimental |
| Navigation rail footer, wide layouts, **every** flavor | "Structural placeholder — not for shipping" | **Wrong.** Developer wording, shown permanently, and flatly false in production. The golden file `shell_wide_dark.png` is a production shell containing it |
| Voice rooms, appearance | "Structural placeholder — not for shipping" plus "The routed voice-room list and detail regions are ready for later feature pieces" | **Wrong.** Engineering vocabulary a user cannot act on, and self-contradictory in a build that does ship |
| Voice rooms placeholder | A button opening `/voice-rooms/sample-room`, another placeholder | Half-presence, which ADR-044 forbids for absent features |
| Group screens | "Experimental group encryption — not reviewed or standardized. An update may reset these groups and delete their messages." | Correct. Kept |
| Edit profile | "Profile encryption and key delivery are using development-only fake transport until pairwise messaging is available. Production remains blocked." | **Wrong in the artifact that ships it.** See below |
| Attachment sheet, reached by the composer's paperclip | "Choose encrypted media or a file." and three options: Photo, File, Camera | **Wrong.** All three are inert |
| Connection screen, five status lines | "Loading secure configurationâ€¦", and four more | **Wrong.** Double-encoded ellipsis, on the first screen every recipient sees |
| Enrollment security notice | What it does and does not protect, with a mandatory "I understand" | Correct, and the right mechanism. Silent about the deployment |
| Pre-login "Security & how this app protects you" | A *different*, shorter notice titled "Security boundary" | **Wrong.** `ui-specification.md` §5 requires the same notice to be re-viewable, not a weaker one |
| Settings | No security-notice entry at all | Missing. §15 has always required one |
| Settings | Entirely hard-coded English | Missing. The product ships English and Persian |

Four different vocabularies reached users — "private experimental build", "experimental",
"structural placeholder — not for shipping", "development-only fake transport" — and two
of them were false in the artifact that carries them. ADR-044's "declared maturity tiers"
had no single expression anywhere in the code.

### The defects this decision had to resolve first

**D-a. Two of ADR-044's "supported" features do not exist in the artifact.**

`profileProtectionProvider` and `profileKeyDistributionProvider` return
`UnsupportedProfileProtection` and `UnsupportedProfileKeyDistribution` for every
environment except development. In the Private Experimental build, `publishOwn` therefore
fails at `protection.seal` and `refreshPeer` fails at `keyDistribution.receive`. Encrypted
profiles do not work at all: a user could type a display name, press Save, and get
`authGenericErrorMessage` — under a warning claiming a "development-only fake transport"
that build does not contain.

`AttachmentTransferService` exists in `lib/features/attachments/application/` and is
composed by no provider anywhere. `pubspec.yaml` declares no file or image picker. The
composer's paperclip dispatches `OpenAttachmentIntent()` with no attachment, and
`AttachmentSheet` renders three `ListTile`s whose `onTap` is `null` because the chat page
passes no `onCancelled`. `docs/implementation-checklist.md` has said attachments are
pending all along.

ADR-044's supported tier lists "contacts and encrypted profiles" and "attachments". Two
of those are not supported, not experimental, and not present. **This decision amends that
row** rather than editing ADR-044 in place, and relabels both surfaces so the application
agrees with the correction.

**D-b. The notice a user must acknowledge and the notice a user can go back and read were
not the same statement.** The enrollment gate showed the protect/does-not-protect
boundary; the pre-login link showed a two-sentence paragraph about passwords and recovery
secrets under a different title. Whichever one is right, they cannot both be the notice.

**D-c. The build's own name disagreed with itself.** Launcher label "Experimental", task
title "Development".

An ADR about honest communication cannot be written over these, so they are fixed here.

### The word

Evaluated independently of ADR-044, against what the artifact provably is.

| Term | What it conventionally promises | Fits this artifact? |
|---|---|---|
| **Experimental** | Google's published launch-stage definition, read at primary source on 2026-08-20: "Experiments are focused on getting customer feedback about a prototype. They are not intended for production use or covered by any SLA, support obligation, or deprecation policy and might be subject to backward-incompatible changes." | **Yes, precisely** — including the backward-incompatible clause, which is exactly ADR-036's disposable group state |
| **Preview** | Same source: "ready for testing by customers before adopting it for production use at GA … not necessarily feature-complete … no SLAs or technical support commitments" | No. "Preview" promises that the thing previewed is what will ship. The group layer will be *replaced* and its data discarded (ADR-036), so it is not a preview of anything |
| **Beta** | Feature-complete, final testing before release. Mozilla's release channels describe Beta as the version "destined to become the next released Firefox"; Google Cloud retired the stage in favour of Preview and GA | No. No background delivery, no notifications, no voice, no search, no attachments, no profiles, and no review of any layer |
| **Alpha** | Incomplete, expect breakage — arguably accurate | No. It is a release-train word: alpha implies a beta and a release follow on a schedule. There is no schedule, and the group layer is not on a train to production |
| **Development** / **Testing** | Not a shipped artifact / a purpose, not a maturity | No. "Development" already names another flavor and would be false on a signed artifact installed by other people; "Testing" invites "so it's finished, you're just testing it?" |
| **Stable**, **Production**, **1.0** | Production-ready, covered by support | **Provably false.** Forbidden |

**"Private Experimental" is kept.** The two words are orthogonal — *private* describes
distribution, *experimental* describes maturity — so combining them adds information
rather than confusion, and *private* carries a real instruction: do not pass the artifact
on. This lands where ADR-044 landed, by a different route.

### Decision

**D1. One application-level maturity designation: Experimental.** It is carried by the
persistent banner, by the launcher label, and now by the task-switcher title, which must
agree with the launcher label and no longer says "Development". Production carries no
designation at all, because it has none to carry and cannot be installed.

**D2. Feature-level labels exist, there are exactly two of them, and both read *down*
from the application label.**

| Label | Meaning | Where it appears today |
|---|---|---|
| **Experimental** | The surface really transmits and really encrypts, using a maintained implementation, but nothing about it is reviewed or standardised and its state is disposable by decision | Group screens, and the build-disclosure section of the security notice |
| **Not built yet** | The surface is routed and visible and has no implementation behind it. Nothing it appears to offer happens | Voice rooms, appearance, file attachments, profile publishing |

**There is no third label, and no label meaning "supported", "stable", "verified" or
"audited".** An unlabelled surface is governed by the application-level Experimental
designation and by nothing stronger. This is the load-bearing part of the model: the
absence of a badge must never be readable as an assurance, so no badge may ever assert
one. `SurfaceMaturity` in `lib/app/config/deployment_disclosure.dart` holds both values
and an architecture test fails if a third is added or if any screen renders a maturity
word without it.

ADR-044's three *tiers* are unchanged as a description of the deployment. What changes is
that only the two tiers that reduce a user's expectations are expressed on screen. The
supported tier is deliberately silent, because "supported" in ADR-044 means "its local
state is intended to survive updates" — a durability claim that would be read as a safety
claim if it were printed next to an encryption feature.

**D3. Disclosure has four placements, each with one job, and nothing is repeated for
emphasis.**

| Placement | Job | Surface |
|---|---|---|
| Continuous, low salience | Identity: which build this is | The environment banner. It is not a warning and must not be turned into one |
| Once, high salience, blocking | Consequences: what a user must know before trusting the app with a conversation | The deployment disclosure inside the existing mandatory enrollment notice |
| Contextual, persistent, per surface | The specific consequence of *this* feature | The group banner; the not-built pages, the profile notice, the attachment sheet |
| On demand, always | Re-reading what was acknowledged | Settings → "Security & how this app protects you", and the pre-login links, both opening the same notice |

**D4. Consent: one mandatory acknowledgement, at first enrollment on a device, inside the
gate that already exists. Never on a timer.**

The mechanism was already in the repository and was not being used for this:
`EnrollmentPhase.securityNotice` is the last step of device enrollment for both the
first-device and later-device flows, it is durably persisted in the enrollment journal,
messaging is withheld until it is accepted, and it already ends in an explicit "I
understand". The deployment disclosure becomes a section of that screen. No second consent
screen is created.

Re-acknowledgement is **content-triggered, not time-triggered**.
`DeploymentDisclosure.revision` moves when, and only when, the disclosed facts move; a
test pins the revision to the exact English text of every point, so changing a word
without raising the revision fails CI. Raising it makes re-delivering the written handover
disclosure to existing recipients release-blocking, and every later enrollment reads the
new text.

Coverage at launch is complete: no external install exists yet, because
`docs/release-signing.md` makes the off-site key-custody procedure mandatory *before* the
first external install and ADR-044 records those backups as still outstanding. Every
recipient of the first artifact will therefore enrol under revision 1. (That is an
inference from the recorded custody state, not an observation of a device.)

**D5. Disclosure content is exactly the set of facts that make an ordinary expectation of
a chat application wrong.** Seven points, ordered by consequence, in
`DisclosurePoint`. Each was chosen because the system's actual behavior contradicts what a
user would otherwise assume:

| Point | The expectation it corrects | Evidence in this repository |
|---|---|---|
| No independent review | "Someone competent has checked the encryption" | ADR-017 is open for every layer; both review packets are prepared and no reviewer is retained |
| Delivery only while the app is open | "Messages arrive when they are sent" | `AndroidPollingScheduler` is a port with no adapter in `lib/`; `pubspec.yaml` declares no notification dependency |
| History lives only on this phone | "My chats are backed up somewhere" | No server history by design (ADR-028); `allowBackup="false"`; the database key is a non-exportable AndroidKeyStore key |
| Recovery restores identity, not messages | "My recovery secret gets everything back" | ADR-030; the backup carries cross-signing identity material only |
| Groups are experimental and can be reset | "A group chat is a chat" | ADR-036: beta group state is disposable and is reinitialised, never migrated |
| Parts of the interface are not built | "If I can see it, it works" | Voice, search, attachments and profile publishing are absent or fail closed |
| Intended use | "This is a secure messenger" | The threat model's release gates are closed; the deployment is private evaluation among people who already trust each other |

**Cryptographic detail is excluded by decision.** `0xFE4C`, `TBD2`, draft revisions, IANA
registry state, `withTrustedRoots: false` and the Cargo feature split are all true and all
unusable by a reader. Printing them beside the seven consequences would bury the
consequences, which is itself a disclosure failure. They stay in the ADRs, in
`docs/mls-profile.md`, and in the written handover.

**D6. The one notice has one title and one body, rendered from one widget.**
`SecurityNoticeSections` renders the permanent boundary — what the protocol does and does
not protect, which stays true in a production release — followed by the build disclosure,
which exists only in a build that is handed to someone else. Production and development
resolve `deploymentDisclosure` to null, so Private Experimental wording is structurally
incapable of appearing in either.

### Scope

In scope: what the Android Private Experimental artifact says about its own maturity,
where it says it, what a user must acknowledge, and the corrections needed to make those
statements true.

Out of scope and unchanged: the deployment definition (ADR-044), signing and identity
(ADR-042), transport trust (ADR-043), every protocol decision, the backend, and the
production gates.

### Explicit non-goals

- It does not implement attachments, profile publishing, search, voice, notifications or
  background delivery. It labels their absence honestly; that is the opposite of building
  them.
- It does not add a consent screen, a terms-of-service flow, a legal agreement, an
  age gate, or any acceptance the application does not act on.
- It does not add analytics, acknowledgement reporting, or any signal that a disclosure
  was read. There is no telemetry in this product and this decision does not introduce the
  first of it.
- It does not change what the group layer is, only how it is labelled.
- It does not open a production gate or relax the written-handover requirement, which
  ADR-044 makes a condition of distribution.

### Alternatives evaluated

**Consent model.**

**A. No acknowledgement, banner only.** Rejected. Three of the seven facts have durable,
irreversible consequences — missed messages, permanently destroyed history, discarded
group state. A banner communicates identity, not consequence, and a permanent banner is
the single most habituated element on a screen.

**B. A second, dedicated consent screen after enrollment.** Rejected, and this is the
alternative that looks most like the obvious answer. Two blocking screens in a row do not
double the attention paid; they split it, and the second is the one that gets dismissed.
The enrollment gate is already mandatory, already durable, already tested, and already the
last thing before a user's first message.

**C. First-run acknowledgement inside the existing gate.** **Selected.**

**D. Periodic re-acknowledgement — monthly, or on every update.** Rejected on evidence,
and it is worth stating why plainly: re-showing an unchanged warning does not refresh it,
it trains dismissal. Kirwan, Bjornn, Anderson, Vance, Eargle and Jenkins measured "a
continued, linear decrease in activation through all six repetitions" of a security
warning in the brain's visual processing regions, and found "the learned negative valence
of computer security warnings is not enough to overcome habituation" (*Frontiers in
Psychology*, 2020). Worse, the damage generalises: this application depends on genuinely
blocking states — unverified identity, unsigned device, changed master key, queue-gap
rejoin — and training a user to click past a familiar warning degrades those too. A
periodic notice would make the app less safe, not more.

**E. Re-acknowledgement when the disclosed facts change.** **Selected, in the narrow
content-triggered form of D4.** The version that was rejected is the runtime one: storing
an acknowledged revision per install and re-opening the notice when it advances. That
needs a new column on `enrollmentIntents`, a schema migration, and a new transition out of
`EnrollmentPhase.complete` — new states in a security-critical state machine, to buy
enforcement that this deployment's distribution model already provides. There is no
over-the-air update here: when a fact changes, the maintainer builds an artifact and hands
it to named people with a written disclosure, which is already release-blocking. The
revision is enforced in CI and bound to that process instead.

**F. Feature-specific acknowledgement, for example a modal before creating a first
group.** Rejected. The group screens already carry a persistent contextual statement of
the exact consequence, which outperforms a modal in front of the least-used feature, where
click-through is highest. A persistent statement cannot be dismissed; a modal exists to be
dismissed.

**Feature labelling.**

**G. One uniform application-level label, no per-feature labels.** Rejected. It forces a
single claim over components with genuinely different failure modes: either the group
layer is overstated and users lose group history unwarned, or the pairwise layer is
understated and the deployment fails to produce the piece-19 evidence it exists to
produce.

**H. A full maturity taxonomy — stable / supported / beta / experimental / planned — with
a badge on every feature.** Rejected on two grounds. It cannot be kept accurate: a badge
on every surface is a maintenance obligation on every change, and the first stale badge
poisons all of them. And it requires a word meaning "assessed", which no evidence in this
repository supports for any layer.

**I. Two labels, both meaning "less than the application label", applied only to
exceptions.** **Selected.** Only the exceptions carry a badge, there are only two kinds,
and both are honest downgrades. Nothing has to be re-audited when a feature is unchanged.

**Where the disclosure lives.**

**J. Out-of-band written handover only, as ADR-044 left it.** Rejected as *sufficient*,
kept as *required*. A document delivered with an APK is read once, by whoever opens the
message, and is not present at the moment a user decides to trust the app with a
conversation. It also cannot reach a second person who installs from a forwarded file.
ADR-044's requirement stands unchanged; this decision adds the in-app statement it
deferred.

**K. Store-listing style disclosure.** Not applicable. There is no store listing;
distribution is a direct APK over the self-hosted channel.

### External evidence, and what it decided

Three findings changed the decision. Everything else was decided from the repository.

| Question | Source | Finding | Effect |
|---|---|---|---|
| Is a warning worth building at all, or do users click through everything? | Akhawe and Felt, "Alice in Warningland: A Large-Scale Field Study of Browser Security Warning Effectiveness", *USENIX Security* 2013 (read at primary source, 2026-08-20) | Measured clickthrough over ~25 million warning impressions: 7.2% and 23.2% for Firefox and Chrome malware warnings, 9.1% and 18.0% for phishing, 33.0% for Firefox SSL — but 70.2% for Chrome SSL. The authors conclude warnings "can be effective in practice; security experts and system architects should not dismiss the goal of communicating security information to end users", and that the variance shows "the user experience of a warning can have a significant impact on user behavior" | Build the disclosure, and design it. The 70.2% outlier is the warning users met most often and could bypass most easily — which is the argument against repetition, not against warning |
| Does repeating the notice help? | Kirwan, Bjornn, Anderson, Vance, Eargle, Jenkins, "Repetition of Computer Security Warnings Results in Differential Repetition Suppression Effects as Revealed With Functional MRI", *Frontiers in Psychology*, 2020 | Continuous linear decrease in visual-processing activation across all six repetitions; the negative valence of a security warning does not overcome habituation | No periodic re-acknowledgement. Re-consent is content-triggered only |
| What does each maturity word promise, in published industry usage? | Google Maps Platform launch stages, `developers.google.com/maps/launch-stages`, last updated 2026-08-19 (read 2026-08-20) | Experimental: "not intended for production use or covered by any SLA, support obligation, or deprecation policy and might be subject to backward-incompatible changes". Preview: "ready for testing by customers before adopting it for production use at GA … not necessarily feature-complete". GA: "production ready" | "Experimental" is the accurate word, on a published definition, and the backward-incompatible clause matches ADR-036 exactly |

Separately, ADR-044's revisit condition 6 required that Android's developer-verification
documentation "be read and dated" at primary source before any of it becomes binding. It
was, on 2026-08-20:
`developer.android.com/developer-verification` records enforcement from **2026-09-30** for
Brazil, Indonesia, Singapore and Thailand on certified devices running Android 7+, with a
global rollout in 2027;
`developer.android.com/developer-verification/guides/limited-distribution` (page dated
2026-08-20) describes the free account type as requiring no government ID and permitting
developers to "Share apps with up to 20 devices that end-users have explicitly
authorized", registered through a QR-code or link handshake. **This changes no part of the
disclosure model** and is recorded because the condition asked for it: the 20-device cap
is per account and this deployment targets 20–30 *users*, several of whom will enrol more
than one device, so the free tier may not cover it. That is a distribution question for
ADR-044's revisit process, not a communication question.

Nothing else external was consulted, and no secondary source was treated as evidence.

### Threats and failure modes

Each was checked against the model, not asserted.

| Failure | How the model addresses it | Residual |
|---|---|---|
| A user assumes the app is production-ready | Application-level Experimental label, on the banner, the launcher and the task title; the disclosure names the absence of review first | A user who ignores all of them. Accepted; the audience is personally known |
| A user assumes stronger encryption than the evidence supports | "Audited", "reviewed", "verified", "standards-compliant" and "interoperable" are forbidden; the disclosure states plainly that nobody outside the project has reviewed it | The word "encrypted" still appears throughout, and is true |
| A user misses time-critical messages | The single most consequential fact is disclosure point 2, and it is stated in the user's terms — "there are no notifications and nothing runs in the background" — not as "best-effort background polling is not implemented" | Real. It is a usability cost ADR-044 accepted deliberately |
| A user loses history to an uninstall or a group reset | Points 3, 4 and 5, plus the persistent group banner at the point of use | The user must act on it. No backup exists to offer |
| Warnings are vague enough to be ignored | Every point states a consequence and an implied action. None says "may", "could" or "we cannot guarantee" | — |
| Warnings are so heavy that adoption fails | Seven short facts on one screen, once. The banner is identity, not alarm. Nothing repeats | If it is still too heavy, that is information about the artifact, not about the wording |
| A user shares the APK beyond the intended group | "Private" is in the application-level label, and the disclosure says who the build is for. A second-hand installer still meets the mandatory enrollment gate, so the in-app disclosure reaches them even though the written handover does not | Distribution beyond named recipients is ADR-044 revisit condition 1 |
| A user relies on it for something it was never built for | Point 7 states the intended use and the excluded use in one sentence | A user whose safety depends on it should not be a recipient at all |
| A label goes stale as features land | Labels are downgrades only, held in one enum, rendered from one place, asserted by tests. A feature that starts working loses its badge; nothing has to be re-certified | A feature that *stops* working needs a badge added, which no test can detect |

### Relationship with the deployment architecture

Checked against the artifact, not against the documentation.

| Claim the model makes | What enforces it |
|---|---|
| Only a build handed to someone else states what it is | `deploymentDisclosure` is null for development and production; asserted per environment |
| Production shows no maturity wording anywhere | No banner, no disclosure, and the navigation-rail "not for shipping" footer is gone. The `shell_wide_dark.png` golden is regenerated from a production shell |
| The task title, the launcher label and the banner name one build | `userFacingTitle` and `configurationBanner` are one extension over `AppEnvironment`; the launcher label is the beta flavor's `resValue` |
| The group label matches the group stack | Both come from `GroupProductionGate.privateExperimentalPermit` through `groupFeatureAvailabilityProvider` (ADR-044) |
| The profile label matches the composed adapters | `profilePublishingProvider` reads the installed adapters, never the environment, so a screen cannot claim a capability the composition root did not install |
| The disclosure and the shell name the same build | `bootstrap()` sets `appEnvironmentProvider` and the app's `environment` from one argument; asserted |

### What may and may not be claimed

ADR-044's table stands. This decision adds:

| Term | Permitted? |
|---|---|
| **Supported**, **stable**, **verified** as a badge on any feature | **No.** There is no such label and none may be added |
| **Not built yet** | Yes, for a routed surface with no implementation behind it |
| **Experimental** as a feature badge | Yes, only for a surface that really transmits and whose state is disposable |
| A feature name in the interface with no working implementation and no label | **No.** Either it works, or it says it does not |
| "Development" in any Private Experimental surface | **No** |

### Maintenance and ownership

One file owns the vocabulary and the disclosure: `lib/app/config/deployment_disclosure.dart`.
The maintainer who changes what the software does owns changing what it says, in the same
change. Enforced by `test/architecture/deployment_disclosure_test.dart`:

- the disclosure exists for the Private Experimental build and for no other;
- every `DisclosurePoint` is rendered, and the order is the ADR's order;
- the revision is pinned to the exact English text of every point;
- every point and label has an English and a Persian string;
- no user-facing string says "beta", "audited", "production ready" or "stable release";
- `SurfaceMaturity` has exactly two values, both downgrades;
- every screen rendering a maturity label renders it from `SurfaceMaturity`;
- `bootstrap()` keeps the composed environment and the rendered environment identical.

### Consequences

- A recipient cannot reach their first message without reading a screen that states, in
  their own language, that nothing is reviewed, that messages arrive only while the app is
  open, and that history has no second copy.
- The written handover disclosure ADR-044 requires is unchanged and still
  release-blocking. It is now a duplicate of an in-app statement rather than the only copy.
- Two features ADR-044 called supported are labelled as not built, and one of them no
  longer offers a Save button that cannot work.
- The application stopped calling itself a development build in the task switcher, and
  stopped telling production users they are running something not for shipping.
- Five status lines on the first screen a user sees are no longer mojibake.
- Settings is localized and, for the first time, satisfies §15's requirement that the
  security notice be re-openable.
- Adding a maturity word to a screen now fails a test unless it comes from the shared
  vocabulary; editing the disclosure fails a test unless the revision moves with it.
- Nothing here opens a production gate, and no accepted decision is superseded.

### Corrections to ADR-044

Recorded here rather than edited into ADR-044, per this register's rule.

1. **D2's supported tier is amended.** "Attachments" and "encrypted profiles" are removed
   from it. Attachments have no composed transfer service, no picker dependency, and an
   inert sheet; profile publishing and profile decryption fail closed in every flavor but
   development. Both belong to the absent tier and are labelled "Not built yet". The rest
   of the supported tier was checked and stands.
2. **The disclosure-requirements section's item 4 note is discharged.** "An in-app
   first-run disclosure is the correct home for item 4 and is recorded as follow-up work"
   — it is now implemented, in the existing mandatory gate, and the written handover
   remains required alongside it.
3. **Revisit condition 6's primary-source requirement is discharged**, with the dates and
   figures recorded above. The condition itself remains open.

### Review and revisit conditions

ADR-044's eight conditions apply unchanged. This decision adds four:

1. **A feature changes tier** — anything absent starts working, or anything working stops.
   The label and the disclosure both move, and the revision moves with them.
2. **A new user-facing surface makes a security or maturity claim** that is not rendered
   from `SurfaceMaturity` or `DisclosurePoint`.
3. **`DeploymentDisclosure.revision` changes.** Re-delivering the written disclosure to
   every existing recipient becomes release-blocking for that build.
4. **Background delivery or notifications ship.** Disclosure point 2 becomes false, which
   is a revision change and, under ADR-044's own condition 8, a re-open of that decision
   too.

## ADR-044 in full — the initial private deployment (2026-08-20)

**Status:** Accepted. Deployment decision. **Opens no production gate.**

### The question

The project needs an initial deployment usable by roughly 20–30 trusted people. The
repository already contains an Android `beta` flavor, a frozen application ID, a
persistent signing identity, a release pipeline, and a large closed-beta PQ MLS
implementation. What it does not contain is one authoritative answer to: what is that
deployment, what may honestly be said about it, what stays mandatory, what may be
deferred, and how it reaches public production without becoming a dead end.

This decision answers that. It is not a plan for future work; it describes what the
next artifact handed to a user is, and it corrects the places where the code and the
documentation disagreed about it.

### What the repository actually ships today

Verified against the working tree on 2026-08-20, not assumed:

| Area | State |
|---|---|
| Flavors | `development`, `beta`, `production` on one `environment` dimension in `android/app/build.gradle.kts` |
| Application IDs | `dev.nimashadloo.chat.development`, `dev.nimashadloo.chat.beta`, `dev.nimashadloo.chat` |
| Entry points | `lib/main_development.dart`, `lib/main_beta.dart`, `lib/main_production.dart`; `lib/main.dart` delegates to development |
| Provisioning | `String.fromEnvironment` under one `<ENV>_` prefix per flavor; no runtime origin selection anywhere |
| Native core | Two Cargo profiles. `foundation` (development, production) exports 15 symbols; `beta` (`--features beta-pq-mls`) exports those plus `cp_crypto_v1_beta_mls_operation` |
| Signing | Beta signs with a persistent RSA-4096 v2+v3 identity attached at flavor level; `buildTypes.release` sets `signingConfig = null`, so Production packages unsigned |
| Signing identity | **Created**, on 2026-08-19; read back out of the keystore and re-verified on 2026-08-20. Certificate SHA-256 `d8d40c0c…71b5a2ff`, subject `CN=dev.nimashadloo.chat.beta`, valid to 2054-01-04, matching `android/beta-release-identity.properties` exactly. Off-site encrypted backups of it are still required before the first external install |
| Transport trust | `SecurityContext(withTrustedRoots: false)` plus the provisioned authority, on both REST and WebSocket (ADR-043) |
| Local state | SQLCipher database keyed by a non-exportable AndroidKeyStore key; `allowBackup="false"`; isolation between flavors is the Android application sandbox, which follows the application ID |
| Background delivery | **Absent.** `AndroidPollingScheduler` is a port with no adapter in `lib/` |
| Notifications | **Absent.** No notification dependency is declared in `pubspec.yaml` |
| Voice | **Absent.** `/voice-rooms` renders `StructuralPlaceholderPage`, badged as a non-shipping placeholder |
| Search | **Absent** |
| Independent review | **None**, for any layer. ADR-017 is open; both review packets are prepared and no reviewer is retained |

Two documented facts were wrong and are corrected by this decision rather than left
standing: `docs/implementation-checklist.md` said the real signing identity had not been
created, and `README.md` said Android release signing was absent. Both predate ADR-042.
`docs/deployment-and-release.md` also listed a `staging` flavor that has never existed in
`build.gradle.kts`, in `lib/`, or in any provisioning prefix.

### The defect this decision had to resolve first

`groupFeatureAvailabilityProvider` derived availability solely from
`GroupProductionGate.developmentPreviewPermit`, which returns non-null only when
`!kReleaseMode && environment == development`. The beta flavor is a release build, so
**every group screen in the Beta artifact rendered `GroupProductionGatePage`** — while
the same artifact composed `NativeBetaGroupMls`, ran `GroupKeyPackageMaintenanceService`
as post-inbox work, and processed inbound Welcome, control, and application objects
through `GroupMlsInboundCoordinator`.

The shipped Beta artifact therefore generated and uploaded MLS KeyPackages, advertising
to the backend and to peers a capability its own interface would never honour, for
groups no user of it could create. Piece 18 introduced the screen gate before piece 19
wired the beta stack, and piece 19 never revisited it. No test covered the beta case.

An ADR cannot state what Beta can access while that contradiction stands, so it is fixed
here: one source-only permit now decides both the stack and its screens.

### The name

"Beta" is the wrong word and this decision stops using it in front of users.

Beta ordinarily means feature-complete, pre-release, expected to work. This build has no
independent cryptographic review of any layer, a group ciphersuite on MLS Private Use
`0xFE4C` that is not `TBD2`-conformant (ADR-040), no background delivery, no
notifications, no voice, and no search. **Experimental** is the accurate word.

The application ID keeps its `.beta` suffix. ADR-042 froze it, and changing it would
force every install through an uninstall that destroys local state irrecoverably. An
application ID is an opaque identifier, not a claim; a launcher label and a persistent
banner are claims. So the identifier stays `dev.nimashadloo.chat.beta`, the Dart enum
stays `AppEnvironment.beta`, the Gradle flavor stays `beta` — and every string a user
reads says Experimental.

### Decision

**D1. The initial deployment is the Private Experimental build.** One Android artifact,
application ID `dev.nimashadloo.chat.beta`, signed by the frozen Beta identity, compiled
against one private origin, distributed as a direct APK with its SHA-256 and metadata
file to a known, named set of roughly 20–30 trusted recipients over the self-hosted
channel. It is not a beta, a release candidate, or a preview of a shipping product, and
no document, screen, or release note may present it as one.

**D2. One artifact carrying declared maturity tiers, not a uniform product.** The
functionality in it is at genuinely different maturity levels and the deployment says so
rather than averaging them into a single claim:

| Tier | Contents | What is promised |
|---|---|---|
| **Supported** | Registration, login, two-phase device enrollment, cross-signing, SAS/QR verification, the signed device log, recovery secret, contacts and encrypted profiles, hybrid PQXDH + Double Ratchet direct messages, the application-event protocol, Saved Messages, attachments, linked devices, device-to-device history transfer, the durable inbox/outbox | Its failure modes are understood, it is covered by tests and vectors, and its local state is intended to survive every update. **Not** that it is audited |
| **Experimental** | Closed-beta PQ MLS groups | It really transmits and really encrypts, using a maintained implementation. Its state is disposable by decision (ADR-036) and an update may reset it. No standards conformance, no interoperability, no review |
| **Absent** | Voice rooms, local search, notifications, background delivery, appearance settings | Nothing. These are visibly missing and must stay visibly missing rather than half-present |

Neither of the first two tiers is independently reviewed. "Supported" distinguishes
expected state durability, not assessed security.

**D3. The existing build-time separation is confirmed and completed, not replaced.**
Separate flavors, separate application IDs, separate native crypto profiles, separate
provisioning prefixes, and a signing identity attached at flavor level are the correct
architecture and are kept exactly as they are. What changes is that the group boundary,
which was expressed inconsistently in four places, now has one source-only expression:
`GroupProductionGate.privateExperimentalPermit`. `group_providers.dart` and
`sync_providers.dart` reach the beta stack only through it, and the five group screens
gate on `GroupFeatureAvailability.isAvailable` rather than naming one tier, so adding a
tier can never silently close them again.

### Scope

In scope: the Android Private Experimental artifact, its distribution, its disclosure,
its isolation from Production, and the conditions under which it is revisited.

Out of scope, and unchanged by this decision: the backend, which stays read-only; the
production ciphersuite selection (ADR-026); the closed-beta protocol decisions (ADR-036,
ADR-037, ADR-039, ADR-040, ADR-041); the signing and identity decision (ADR-042); the
transport trust decision (ADR-043); and the post-v1 Web backlog (ADR-033).

### Explicit non-goals

- This is not a public release, a soft launch, or a staged rollout of one.
- It does not open any of the seven production gates in `docs/mls-profile.md`, and it
  does not touch `GroupProductionGate.releaseAssertion`, ADR-017, or ADR-026.
- It does not give Production a signing identity, and it does not make Production
  installable.
- It does not authorize a locally assigned production ciphersuite identifier, a
  classical fallback, a production KeyPackage path, or a project-local cryptographic
  fork.
- It does not create a second product, a second repository, or a long-lived branch.
- It does not implement background delivery, notifications, search, or voice, and it
  does not permit shipping a partial version of any of them.

### Alternatives evaluated

**A. One artifact containing everything, gated at runtime.** Rejected. The production
artifact would then package a native core exporting `cp_crypto_v1_beta_mls_operation`,
and the only boundary between an unreviewed draft ciphersuite and a production user
would be a runtime branch — defeated by one bug, one define, or one refactor. Today that
boundary is provable from the artifact itself: `tool/verify_release_apk.sh --production`
extracts the packaged `.so` and fails if the beta symbol is present. That evidence is
worth more than the build simplicity it costs.

**B. Separate Beta and Production build flavors.** Selected, because it is what already
exists and it survives every objection raised against the others. Two application IDs
that can never upgrade into one another, two native profiles proven distinct at the
artifact level, one signing identity that reaches only Beta, and a Production artifact
that the OS refuses to install.

**C. A separate private-experimental application, developed as its own product.**
Rejected. It duplicates the entire pairwise stack, doubles the surface any future review
must cover, and guarantees drift from the line it must eventually graduate into. It buys
isolation the flavor split already provides, at the cost of the shared reviewed core
that ADR-032 and ADR-017 depend on.

**D. A long-lived branch or materially separate product.** Rejected for the same reasons
as C, plus one specific to this project: ADR-042 makes the signing identity and
application ID unchangeable, so any divergence that later needs to merge back cannot be
resolved by shipping a different application. The merge cost is paid in user data.

**E. Ship the private deployment with groups closed, as a direct-message-only client.**
Seriously considered and rejected. It is the smallest attack surface, and if the group
stack were unproven *and* unwired it would be the right answer. But the group stack is
already wired into the beta artifact's sync engine and KeyPackage maintenance, so
closing only the screens produces the current defect rather than safety. Closing it
properly means unwiring the work of ADR-036, ADR-037, ADR-039, ADR-040 and ADR-041 and
leaving them permanently unexercisable, since the only remaining piece-19 evidence —
execution against the packaged Rust core on physical devices against a live backend — can
only be produced by people using it. That is a dead end, and it would need to supersede
five accepted decisions to reach. Rejected in favour of exposing it as a declared
experimental tier with honest disclosure.

### Security invariants that remain mandatory

A small, trusted audience reduces the *adversary population*. It changes nothing about
the server, the network, or a lost phone. These stay mandatory and each one is enforced,
not merely asserted:

| Invariant | Enforcement |
|---|---|
| The server stays an untrusted relay; every signature, identity, device-log, version, replay, and AEAD check happens on the client | Runtime, throughout `lib/features/**` |
| No cryptographic primitive or zeroization is implemented in Dart | The primitives live in the Rust core. `test/architecture/crypto_core_boundary_test.dart` asserts the narrow FFI surface and fails if any Dart file imports a cryptography package |
| Confidentiality and integrity of message content, including against a seized backend | Runtime; `docs/threat-model.md` is unchanged by this decision |
| Hybrid PQXDH with no classical fallback and no silent downgrade | Build-time and runtime (ADR-025, ADR-034) |
| Device authentication by cross-signing and the client-signed device log; unsigned devices are never messaged | Runtime (ADR-027) |
| Transport trusts the provisioned private authority and nothing else; absent or malformed authority material fails configuration closed | Runtime (ADR-043); `test/features/networking/transport_security_test.dart` proves it against a real handshake |
| Local state is encrypted at rest under a non-exportable AndroidKeyStore key, with backup disabled | Runtime and manifest |
| Key continuity: the application ID and signing certificate are frozen, and every artifact is verified against the recorded fingerprint before distribution | Build-time and tooling (ADR-042); `tool/verify_release_apk.sh` fails closed |
| Production cannot execute the beta MLS core | Build-time and artifact-level: the Cargo feature is non-default, the symbol allowlist in `tool/build_rust_android.sh` exits 5 on any mismatch, and `verify_release_apk.sh --production` re-checks the packaged library |
| Production cannot be installed | Build-time: `signingConfig = null`; asserted on every CI run by `tool/ci.sh` |
| No arbitrary server selection, certificate bypass, remote configuration, telemetry, foreign push, or third-party runtime resource | Structural: origins come only from `String.fromEnvironment`, `badCertificateCallback` returns false unconditionally, and `pubspec.yaml` declares no such dependency. `AppRuntimePolicy.lockedDown` records the policy and is asserted in `test/features/bootstrap/application/app_configuration_test.dart` |
| No plaintext, credential, key, or ciphertext in logs | Runtime, with redaction tests |
| Catastrophic local data loss is treated as unrecoverable, never as an acceptable migration | Process: ADR-042 and `docs/release-signing.md` |

The signing key custody procedure in `docs/release-signing.md` is mandatory before the
first external install, not after it, and this decision does not relax it. Its one
unmitigated risk — a single key holder — remains accepted and recorded there.

**On `docs/threat-model.md`'s security release gates.** They include "no shipping an
unreviewed cross-platform protocol implementation" and an independent sign-off. Handing
an artifact to 20–30 people is plainly shipping *something*, so the tension is real and
is resolved explicitly rather than by wordplay: those gates are **release** gates and
they stay closed. This decision does not open them, does not claim they are satisfied,
and does not make this artifact a release. It authorizes one narrower thing — private,
named, disclosed distribution of an artifact that says what it is — and it pays for that
by requiring the written disclosure in the user-disclosure section to reach every
recipient. If the disclosure is not delivered, the distribution is not authorized.

### Requirements deferred, and the risk each deferral keeps

| Deferred | Why it is not a prerequisite here | Residual risk |
|---|---|---|
| Independent cryptographic review (ADR-017, production gate 7) | It is a public-release gate. Retaining a reviewer is an external event with unknown availability and cost, and blocking a 20–30 person private deployment on it would leave the implementation permanently unexercised against real devices | **The largest one.** No layer, pairwise included, has been assessed by anyone outside the project. A design or implementation flaw in PQXDH, the ratchet, the device log, or the storage layer would not be caught. Users must be told this plainly |
| An IANA-assigned MLS ciphersuite value and a non-expiring primitive specification (gates 1, 2) | No amount of work in this repository can advance either. The private deployment does not interoperate with anything | Group state is tied to a Private Use identifier and a moving draft, so it is disposable by construction. Disclosed in tier 2 |
| A maintained provider implementing `TBD2`'s KEM (gate 3) | ADR-040 determined that no such provider exists and that supplying one locally would be a project-local cryptographic fork | The beta KEM is hybrid ML-KEM-768/X25519 from a maintained implementation, but it is not `TBD2` and can never be `TBD2` evidence |
| Cross-implementation interoperability | `docs/mls-profile.md` determined it structurally unobtainable: the beta KEM has one implementation and no specification, so no second implementation can be *configured* to it | No independent implementation can validate the group wire format |
| Upstream MLS interoperability vectors (part of gate 4) | The MLS WG repository publishes only classical fixtures | Project vectors and NIST ACVP anchors are the only fixture evidence |
| Web, Wasm, and browser vectors | Post-v1 under ADR-033; crypto-dependent Web behavior stays fail-closed | None for this deployment |
| Background delivery, notifications, search, voice | None is required for the deployment to be usable, and a partial implementation of any of them would make a delivery promise the system cannot keep | Messages arrive only while the app is running. This is the single most consequential user-visible limitation and must be disclosed |
| Reproducible builds and SBOM | Public-release supply-chain requirements. The artifact is built by one maintainer from a recorded revision, and the metadata file records that revision and warns when the tree is dirty | A recipient cannot independently reproduce the artifact; they can only verify that it carries the expected signer and hash |

### What may and may not be claimed

| Term | Permitted? |
|---|---|
| **Experimental** | Yes, everywhere. It is the accurate description of the artifact as a whole |
| **Beta** | Not in user-facing text. Permitted only where it names the frozen identifier, the Gradle flavor, or the `AppEnvironment` value |
| **End-to-end encrypted** | Yes for direct messages, attachments, and profiles. The pairwise construction is implemented, tested against vectors, and has no fallback path |
| **Post-quantum** | Yes, with precision: hybrid X25519 + ML-KEM-768 for direct-message session establishment, and hybrid ML-KEM-768/X25519 for the experimental group layer. Never as a bare adjective for the product |
| **MLS** | Only as "based on the MLS protocol (RFC 9420) with an experimental non-standard ciphersuite". Never unqualified; the suite is Private Use `0xFE4C` |
| **Standards-compliant**, **interoperable**, **conformant** | **No.** For the group layer these are provably false (ADR-040) |
| **Audited**, **reviewed**, **verified** | **No**, for any layer, until ADR-017 closes |
| **Secure** | Not as a bare claim. Specific, scoped statements only — what is protected, against whom, and what is not |
| **Production**, **release**, **stable**, **1.0** | **No** |

### User disclosure requirements

The goal is that the user's expectations match the system's actual behavior. Every item
below is a requirement of this decision:

1. **A persistent build-identity banner.** Present on the blocking Connection screen and
   inside the application shell, reading "Private experimental build". Production shows
   no banner. *Implemented:* `AppEnvironmentBanner`.
2. **Per-tier honesty on the experimental surfaces.** Group screens state that the
   encryption is experimental, unreviewed, non-standard, and that an update may reset
   those groups and delete their messages. The development preview keeps its own distinct
   wording, because it transmits nothing and the experimental build does. *Implemented:*
   `_GroupMaturityBanner`, covered by a widget test asserting the two builds do not share
   one string.
3. **Absent features stay visibly absent.** Voice rooms and appearance remain badged
   non-shipping placeholders. *Implemented:* `StructuralPlaceholderPage`.
4. **Out-of-band disclosure at handover.** Because there is no store listing and no
   in-app onboarding disclosure yet, the following must be delivered in writing with the
   APK, alongside the SHA-256 and the metadata file, and is a release-blocking checklist
   item:
   - no part of the cryptography has been independently reviewed;
   - messages arrive only while the app is running — there is no background delivery and
     no notifications, so this must not be relied on for anything time-critical;
   - group messaging is experimental and its history can be lost on an update;
   - message history exists only on the device; the server holds none, and uninstalling
     destroys it permanently;
   - a recovery secret plus a second enrolled device is the only way to recover an
     identity, and it does not recover history;
   - this build is for evaluation among people who already trust each other, and is not
     appropriate for anyone whose safety depends on the confidentiality of their
     messages.
5. **What must never be communicated:** any claim from the "No" rows above, any implied
   delivery guarantee, and any statement that the private CA pin-set in the Android
   network security configuration protects the app's API traffic — ADR-043 established
   that it does not.

An in-app first-run disclosure is the correct home for item 4 and is recorded as
follow-up work. It is deliberately not implemented here: this decision does not
introduce product surfaces, and a written handover is sufficient and verifiable for a
named 20–30 person audience.

### The production boundary

Unchanged by this decision except that the group boundary now has one expression instead
of being restated in each composition root and again on every screen. Nothing here
weakens an existing boundary.

| | Production | Private Experimental |
|---|---|---|
| Installable | **No.** Packages unsigned; the OS refuses it | Yes, signed by the frozen Beta identity |
| Native core | `foundation` profile. Does not export `cp_crypto_v1_beta_mls_operation` | `beta` profile. Exports it |
| Group stack | `UnsupportedGroupMlsCrypto`, failing closed on all nine port methods | `NativeBetaGroupMls` |
| Group screens | `GroupProductionGatePage` | Reachable, with the experimental banner |
| KeyPackage upload | Impossible: the maintenance provider throws | Generated and uploaded |
| Origin, CA, pins | `PRODUCTION_*` only | `BETA_*` only. A separate backend deployment and separate accounts |
| Local state | Its own sandbox, its own KeyStore alias | Its own sandbox, its own KeyStore alias |
| Signing identity | None | The frozen persistent identity |

**Nothing crosses.** The two are different applications; neither upgrades into the other,
no data migrates between them, and no MLS state, group, ratchet, or KeyPackage produced
by one is ever readable by the other.

**If someone tries to enable beta functionality in Production**, in order of which fails
first: `GroupProductionGate.privateExperimentalPermit` returns null for production, so
the composition root installs the unsupported adapter; `main_production.dart` references
`GroupProductionGate.releaseAssertion`, whose `assert` and explicit `StateError` fail
release compilation if the constant is edited; the production Cargo build does not enable
`beta-pq-mls`, so the symbol does not exist to call; `tool/build_rust_android.sh` exits 5
if the exported symbol set differs from its allowlist; `tool/verify_release_apk.sh
--production` extracts the packaged library and fails if the symbol is present;
`tool/ci.sh` runs that check on every run; and the artifact is unsigned regardless, so no
device can install it.

Compile-time and build-time: the Cargo feature, the flavor source sets, the symbol
allowlist, the provisioning prefixes, `signingConfig = null`, and the
`GroupProductionGate` constants. Runtime: the permits and the composed adapters.
CI-enforced: the production build, the artifact verification, analysis, and the test
suite.

This was run, not assumed. A production release APK built from this working tree on
2026-08-20 passed `tool/verify_release_apk.sh --production`: application ID
`dev.nimashadloo.chat`, unsigned so the OS cannot install it, and a packaged native core
that does not export `cp_crypto_v1_beta_mls_operation`.

### Piece 19 under this deployment

The deployment objective changes how piece 19's remaining work is classified. It changes
none of its findings.

| Classification | Work |
|---|---|
| **Mandatory for this deployment** | Nothing new to build. What ships is what exists. The one genuinely required outstanding item is execution of the closed-beta group stack against the packaged Rust core, on physical devices, against a live backend — which this deployment is the mechanism for producing |
| **Useful but deferrable** | Broader adversarial and multi-device matrices; the manual product-state upgrade tier in `docs/release-signing.md` before any storage-, schema-, or crypto-state-touching release |
| **Primarily public production** | Gates 1, 2, 3, 5 and 7: registry assignment, suite identifier, maintained provider support, KeyPackage bucket conformance for the production suite, and independent review. Gates 4 and 6 each have an Android device half that this deployment does exercise, but neither can be *evidenced* until the suite those fixtures must be run against exists |
| **Externally blocked** | Gates 1, 2, 3, upstream vectors, and a retained reviewer. Five prerequisites, none movable from inside this repository |
| **Obsolete as previously framed** | Re-running the Phase-A preflight audit as the deliverable of every attempt at piece 19. It is now trigger-driven: re-run it when one of the revisit conditions below fires, not on a schedule. The audit's *content*, its stop-and-decide rule, and the prohibition on locally assigning an identifier are all unchanged |

Piece 19 is therefore not "blocked pending five gates" for the purposes of this
deployment. Its closed-beta half is **delivered**, as the experimental tier. Its
production half stays blocked exactly as `docs/mls-profile.md` records.

### Piece 20

Its prerequisite was written for a public-release objective and no longer says anything
actionable: it requires that piece 19 pass every production gate, and gates 1–3 cannot be
reached from inside this project, so as written piece 20 is permanently dead rather than
merely blocked.

Re-scoped, without touching any implementation, because none exists: **piece 20's real
prerequisite is a decision about which MLS exporter it may derive media keys from.** Two
paths, and this ADR grants neither:

- the production gates close and voice consumes the reviewed production exporter; or
- a separate, later ADR explicitly accepts the private-experimental exporter for
  experimental voice only, under the same disposable-state and disclosure rules.

The second is available but is deliberately not taken here. Real-time audio would rest on
the least mature layer in the system, and it needs its own evidence: a self-hosted
LiveKit and TURN deployment, an Android SFrame wire spike proving the SFU cannot decrypt,
and a truthful foreground-service integration. That is a decision to make with that
evidence in hand, not a corollary of this one.

`docs/implementation-prompts.md` is untracked, so this re-scope is recorded here, and
this ADR is authoritative over the prompt text.

### Evolution toward public production

The private deployment must not become an architectural dead end. It does not, because
almost everything in it graduates unchanged.

**Graduates as-is:** the entire supported tier — the Rust core and its FFI boundary, the
pairwise transport, the application-event protocol, device enrollment and cross-signing,
the device log, recovery, attachments, history transfer, the durable sync engine, the
storage layer, the design system, and the transport trust model.

**Needs replacement, not migration:** the experimental group layer. When production gates
1–3 close, the suite changes, and ADR-036 already fixes the consequence: beta group state
is reinitialized, never silently migrated. Groups are recreated and rejoined. This is
disclosed to users in advance rather than discovered by them.

**Needs building:** background delivery, notifications, search, and voice.

**How users migrate.** They do not upgrade from the experimental application into the
production one — the application IDs differ, so no upgrade path can exist. A user moving
to the public product installs a second application, registers against the production
backend, and starts fresh. Their experimental install keeps working independently until
they remove it. Anyone expecting their experimental history to appear in the production
app will be wrong, and must be told so before they invest in that history.

**Application identity.** Production keeps `dev.nimashadloo.chat`, already reserved and
already the flavor's ID. It gains its own signing identity only through an explicit,
separate release decision, created offline, with its own custody procedure. Nothing in
this decision authorizes creating it.

**Cryptographic state.** Identity material — the account master key, device keys, the
device log — is portable in principle through the existing recovery format, but it is
bound to a backend deployment, and the experimental and production backends are separate.
In practice, production enrollment is a fresh enrollment.

### Irreversible decisions

Recorded plainly, because pretending migration will be easy is how projects lose user
data:

1. **The Beta application ID and signing certificate are permanent.** Losing the key ends
   the deployment's ability to update. Rotation cannot fix key loss, and with `minSdk` 24
   the original key must keep signing the v2 block forever, so a compromised key can
   never be fully retired.
2. **Local history has no second copy.** No server history by design, backup disabled,
   database key non-exportable. Any event that erases app data erases history for a
   single-device user, permanently.
3. **Experimental group state is disposable and will be discarded.** Not a risk — a
   scheduled outcome, whenever the draft, the identifier, or the suite changes.
4. **The private CA is the only trust anchor.** `withTrustedRoots: false` means a lost or
   compromised authority requires a new build, distributed out of band, to restore
   connectivity. This is deliberate and stronger than the public-CA model it replaced,
   and it has no runtime recovery path.
5. **Every user who receives this artifact learns the project exists.** A private
   deployment is not anonymous distribution.

### Consequences

- The Beta artifact's group stack becomes reachable by the people who install it, which
  is the only way the last outstanding piece-19 evidence can be produced.
- The KeyPackages that artifact was already uploading now correspond to groups that can
  actually exist.
- One permit, in one file, decides the experimental boundary. Three architecture tests
  and one widget test fail if either half drifts from the other.
- Users see "Experimental" rather than "Closed beta", which is a weaker and truer claim.
- Production's fail-closed posture is unchanged and now stated in one place: it cannot
  execute the beta core, and it cannot be installed at all.
- The deployment ships without background delivery or notifications. That is a real
  usability cost, accepted deliberately in exchange for not making a delivery promise the
  system cannot keep.
- Nothing here opens a production gate, and no accepted decision is superseded.

### Review and revisit conditions

Deadlines are not triggers. Re-open this decision when one of these occurs:

1. **The audience changes shape** — distribution beyond the known, named recipients, or
   any distribution to someone who is not personally trusted by the maintainer.
2. **Public distribution is proposed**, in any form, including a store listing.
3. **An independent cryptographic review is retained**, or reports findings. This is the
   single largest deferred requirement and its closure changes what may be claimed.
4. **A production gate closes**, particularly gates 1 or 2, which would begin the group
   layer's replacement and its state reinitialization.
5. **A signing or application-identity event** — key loss, suspected key exposure, or a
   second key holder being added.
6. **Android's developer-verification requirement reaches the deployment's users.**
   Google's developer-verification documentation, read on 2026-08-20, records enforcement
   for certified Android devices in Brazil, Indonesia, Singapore and Thailand from
   2026-09-30, a global rollout in 2027, ADB and an advanced install flow remaining
   available for unregistered apps, and a free limited-distribution account capped at
   about 20 devices. This deployment targets 20–30 *users*, several of whom will enrol
   more than one device, so that cap may not cover it. This was established from search
   summaries of official Google domains, not from a page read end to end; the primary
   documentation must be read and dated before any of it becomes binding, and no
   distribution decision may rest on the numbers above until it is.
7. **The threat model changes** — a user whose safety depends on this software, or a
   materially different adversary than `docs/threat-model.md` records.
8. **Background delivery or notifications are implemented**, which changes the delivery
   promise and therefore the disclosure.

## ADR-041 in full — same-revision fork ordering (2026-08-17)

**Status:** Accepted. Closed-beta protocol decision. Supersedes ADR-038. **Opens no
production gate.**

### Question

Can the branch author bias ADR-038's same-revision tie-break, and if so what ordering rule
replaces it?

### Finding: confirmed, and cheap

The ordered value was the control state hash, computed in
`native/crypto_core/src/mls_beta.rs` as
`SHA-256("chat:v1:group-control-state" ‖ frame(canonical) ‖ frame(signature))`. Its inputs
are the CBOR canonical descriptor — event id, group id, revision, previous control state
hash, MLS epoch, commit hash, signer user and device id, `created_ms`, operation — and the
Ed25519 signature over that descriptor.

Of those, the author freely chooses the 16-byte `event_id` (nothing derives, binds, or
range-checks it; honest clients draw it at random), `created_ms` (read as a bare `u64`,
validated against no clock), and the operation payload's own text. `ed25519-dalek 3.0.0`
signs per RFC 8032, deterministically, so one descriptor yields exactly one signature and
one hash — grinding therefore means re-signing under a fresh event id, at a cost of one
Ed25519 signature plus one SHA-256 per candidate, with a fresh uniform 256-bit result each
time.

Measured on 2026-08-17 through the shipped signing path on this workstation (release,
x86-64): **1,000 candidate branches in 40.8 ms — about 24,500 per second per core — and 9
trials to place a branch below one known rival.** Against a *known* rival hash `H` the
expected trial count is `2^256 / H`, whose median over uniform rivals is two. Against an
*unknown* future rival, grinding `N` candidates and keeping the smallest loses only with
probability about `1/N`: one second of one core is `N ≈ 24,500`, or 99.996 %. The standing
evidence is the Rust test
`an_author_grinds_the_control_state_hash_below_a_known_rival`, which reproduces the shipped
hash byte for byte, grinds, and then re-signs the winning event id through the real
operation entry point.

### Finding: who could use it, and against what

A competing branch at the shared parent revision must pass authentication, replay against
the reconstructed parent, and `GroupControlStateMachine` authorization. Enumerating what
each role may author there:

| Role of the member facing eviction | Branches it can author at the parent | Under ADR-038 |
|---|---|---|
| Owner | not evictable at all — `GroupAuthorization.canRemove` refuses an owner target | n/a |
| Admin | `UpdateMetadata` at every revision, `Leave` once, `Invite` where the policy allows, and its own `Remove` of a plain member | defeats the eviction indefinitely |
| Member, `allMembers` invitations | `Invite` at every revision, `Leave` once | defeats the eviction indefinitely |
| Member, `ownerOnly`/`ownerAndAdmins` | `Leave` once | defeats one eviction |

A departing member's own `Leave` is the sharpest case: every active member holds
`GroupPermission.leave`, it carries no Commit, and under ADR-038 a ground `Leave` displaced
the `Remove` that was evicting its author. Because `GroupPendingEvictionService` retries the
eviction on the next drain, any role with a repeatable authorized operation — an admin's
metadata edit, a member's invite under `allMembers` — could repeat the grind at every
revision and never be evicted, while each round either fork-quarantined the evicting owner
or left the attacker in the group holding the current epoch secret. So: **confirmed,
exploitable by the eviction target itself, and repeatable for two of the four cases.**

### The rule

Sibling branches are compared on a tuple, smallest first:

1. `GroupControlPrecedence` of the operation — `eviction`, then `authority`
   (`ChangeRole`, `TransferOwnership`, `UpdatePolicies`, `Create`), then `membership`
   (`Invite`, `Leave`), then `descriptive` (`UpdateMetadata`).
2. The signer's role **in the reconstructed shared parent** — owner, admin, member.
3. The signer's authenticated user id, then device id.
4. The control state hash.

Key 1 removes the class of attack outright: the target of an eviction cannot reach the
eviction class, because reaching it means holding `removeMembers`, which is the same check
the branch already has to pass. Key 2 closes the one remaining case, an admin under
eviction issuing its own `Remove`: `canRemove` only lets an owner evict an admin, so the
competing branch is always the owner's and always outranks it. Neither key is variable by
the author — the class follows from the permission it actually holds, and the role comes
from the parent roster, not from the branch's claims about itself, so an operation that
promotes its own signer cannot promote its own ordering. Key 3 is bound by the device
credential the sibling was authenticated against.

Key 4 survives only as the last resort, and it is reached only when two branches agree on
class, role, user and device — that is, when one device signed two controls at one
revision. Grinding there reorders the equivocating author's own branches, which it could
already do by choosing which one to send, so it wins nothing.

The order stays **total** (four keys over a finite domain, with the hash total on the
remainder), **deterministic** (every input is carried in the authenticated branch or the
replayed parent), and needs **no server order and no extra round trip**. Sibling
authentication, replay against the reconstructed parent, and authorization are unchanged;
`branchOf` additionally refuses to place a signer that is not an active member of the shared
parent, which fails closed rather than ordering a branch on its own claims.

### Options evaluated

**1. Precedence class, then parent authority, then signer identity, then hash — CHOSEN.**
Removes the grindable input from every position that can decide a real conflict, states the
security property directly ("an eviction is not displaced by a convenience operation"), and
keeps convergence total and server-independent.

**2. Keep the hash but bind the event id to something unchosen — REJECTED.** There is
nothing to bind it to that the author does not also control: the parent hash, revision and
epoch are shared constants at a fork, so any derivation still leaves `created_ms` and the
operation payload free. It would also make the wire format's event id derived rather than
opaque, for no gain.

**3. Order by a key derived from the epoch secret — REJECTED.** Every member knows the
epoch secret, so the attacker computes the same PRF and grinds exactly as before. It only
hides the order from non-members, who are already unable to place a branch.

**4. Prefer the branch that carries an MLS Commit — REJECTED.** `Invite` also carries one,
and every member holds `inviteMembers` under `allMembers`, so it would hand the same
displacement back to the same attacker.

**5. Order by signer identity alone — REJECTED.** It is not author-variable per fork, but
it is grindable at account registration and it says nothing about what the branches do: a
low-id member's metadata edit would still beat a high-id owner's eviction.

### Consequences

No state, schema, or wire format changes: the ordering key is derived from data every
branch already carries. `BETA_STATE_FORMAT_VERSION`, transport v3, the control descriptor,
and the control state hash are all unchanged — the hash keeps its jobs as branch identity,
chain link, and audit digest, and only stops being the deciding input. No reinitialization
is triggered.

Honest concurrent branches of the same class and authority now converge on the lower signer
id instead of the lower hash. Both were arbitrary; this one is stable and explains itself in
the quarantine record. A superseded branch is still recovered by fork-quarantine plus
remove/re-add, because an applied MLS commit cannot be rewound.

**This decision does not open any production gate.** All seven gates in
`docs/mls-profile.md` remain closed. It does not touch the production adapter,
`GroupProductionGate`, ADR-017, or ADR-026.

**Reversal trigger.** Re-open if a future control operation cannot be honestly placed in one
of the four precedence classes, or if a delivery service that serializes commits is ever
introduced, which would remove the need for a client-side tie-break entirely.

## ADR-040 in full — closed-beta hybrid KEM (2026-08-17)

**Status:** Accepted. Closed-beta protocol decision. **Opens no production gate.**

### Question

Must the closed-beta hybrid KEM be changed to match the selected candidate suite's KEM,
and what exactly is the divergence?

### Divergence set

Ten divergences, each independently verified on 2026-08-17 against the pinned crate sources
in the local cargo registry and against the X-Wing draft text: combiner input order (label
last in `-06`/`-10`, label first in the vendored combiner), label bytes (6 vs 7, with an
embedded `0x0a`), the traditional contribution (raw X25519 vs a DHKEM(X25519, HKDF-SHA256)
secret), HPKE `kem_id` (`0x647a` vs `15`, unassigned at IANA), `DeriveKeyPair` structure (no
`dkp_prk` step vs an extra HKDF-SHA384 `dkp_prk` extraction), seed expansion (SHAKE-256 vs
SHAKE-128), X25519 key derivation (raw scalar vs RFC 9180 labeled expand), the mandatory
ML-KEM encapsulation-key check (required vs no-op), the serialized private key (`Nsk` 32 vs
2,432 bytes), and the targeted revision (`-06`/`-10` vs `draft-01`). `docs/mls-profile.md`
holds the table with per-row file-and-line evidence as rows D1-D10; that table is the
binding record and this ADR does not restate it.

`kem_id` is the divergence that makes the rest non-cosmetic: `0x000F` is bound into the
HPKE `suite_id` every key-schedule `LabeledExtract`/`LabeledExpand` consumes and into the
`"KEM" || kem_id` suite ID that derives `dkp_prk` for every HPKE key pair, so it reaches
every beta Welcome, update-path node key, KeyPackage init key, and HPKE export. `Npk`,
`Nenc`, and `Nsecret` are byte-identical between the two constructions, so the divergence
is silent on the wire and fails at decryption rather than at parsing.

### Specification stability of the candidate KEM

`TBD2` names HPKE KEM `0x647a`. That code point is assigned in the IANA HPKE KEM registry
(last updated 2026-04-16) with `draft-connolly-cfrg-xwing-kem-06` as its only normative
reference, while the draft itself has advanced to `-10` (2026-03-02, Independent stream,
expires 2026-09-03) and moved the combiner label between those revisions.
`draft-ietf-hpke-pq-05` (2026-07-06) defers the algorithms to
`draft-irtf-cfrg-concrete-hybrid-kems`, cited there at `-03` and now at `-04` in
datatracker state `I-D Exists::Revised I-D Needed`. `draft-ietf-mls-pq-ciphersuites-06`
(2026-07-21, expires 2027-01-22) is annotated "Waiting for WG Chair Go-Ahead" and "Revised
I-D Needed - Issue raised by WG", and `TBD2` still has no value in the IANA MLS Cipher
Suites registry (last updated 2025-11-17). The candidate KEM is therefore defined by a
superseded, expiring Internet-Draft revision whose successor already differs, under a
chain that is still moving.

### Extension points, and why using them is a fork

The extension points are real. `mls_rs::CryptoProvider` and
`mls_rs_core::crypto::CipherSuiteProvider` are public traits; the project already
implements the former. `mls_rs_crypto_traits::{KemType, DhType, Hash, VariableLengthHash}`
are public; `CombinedKem::new_custom` and the `SharedSecretHashInput` trait are public, so
the correct 6-byte label and label-last order are expressible; and aws-lc's ML-KEM,
X25519, and SHA3-256 are reachable through public constructors, including the 64-byte
`(d ‖ z)` deterministic ML-KEM keygen X-Wing needs. None of this requires editing vendored
source.

They are still not usable here. `AwsLcCipherSuite` cannot be re-parameterized: its fields
are private, the `AwsLcHpke` enum is private, and both hybrid builder entry points
hard-code `CombinedKem::new_xwing`. So the project would have to implement the ~25-method
`CipherSuiteProvider` itself; that needs `mls_rs_crypto_hpke::{hpke::Hpke,
context::{ContextS, ContextR}}`, which `mls-rs-crypto-awslc` imports privately and does not
re-export, so it also needs a new direct dependency, and `HpkeKdf` is `pub(crate)` so the
labeled-KDF helpers would be rewritten too. SHAKE-256 is not exposed by any current
dependency's safe API, so it would need project-local `unsafe` FFI against `aws-lc-sys`.

**Explicit reasoning on the fork question.** Read narrowly, "project-local cryptographic
fork" means a patched copy of upstream source, and this route is not one. That reading does
not survive contact with the gate the phrase belongs to. Production gate 3 requires that
*a maintained OpenMLS/provider combination implements* the final KEM, KDF, AEAD, hash, and
signature mappings; the operative question is who implements the KEM, not how the code is
delivered. On this route upstream would ship `new_xwing` unchanged and the project would
author and own the combiner, the raw-X25519 KEM, the SHAKE-256 expansion, the `(d ‖ z)`
split, the encapsulation-key check, and the whole cipher-suite provider — code no upstream
maintainer tests, versions, fuzzes, or patches. That is the condition gate 3 exists to
exclude, is what ADR-017 calls "a custom, unaudited cryptographic implementation", is what
ADR-036 excludes by permitting "only maintained external cryptographic implementations",
and is what prompt 19 names directly. So the answer is yes: it is a project-local
cryptographic fork for the purposes of AGENTS.md and gate 3, even though no vendored file
would change.

Two qualifications, so the finding is not overstated. It would **not** be invented
cryptography — X-Wing is a specified construction with published vectors, and transcribing
a specification is not invention; the prohibition that bites is the maintained-provider and
reviewed-core one. And selecting and composing maintained primitives is **not** a fork:
`combined_hpke(...)` selects among upstream constructions, which is what the beta does
today and is legitimate. The line is crossed when the project authors a KEM's own algorithm
steps.

### Options evaluated

**1. Retain the current combiner and document the divergence — CHOSEN.** The beta's purpose
under ADR-036 is to exercise the real lifecycle — authenticated credentials, KeyPackage
maintenance, Welcome and transcript replay, epoch and exporter state, sealed state,
pairwise fan-out, ADR-038 convergence, ADR-039 leave — on a Private Use identifier with
disposable state. It was never wire-compatible with anything, and nothing in that purpose
depends on the KEM's code point. Every property the beta needs it already has: hybrid
ML-KEM-768 + X25519 confidentiality from a maintained implementation, `TBD2`'s exact
signature, AEAD, KDF, and hash mapping, and no classical fallback. The divergence costs
exactly one thing, `TBD2` interoperability, and no gate can consume it: gate 2 has no suite
value to be interoperable on, and gate 4's upstream vectors do not exist for any
post-quantum suite. Retaining is also the only option that leaves the KEM in maintained
hands, which is the state gate 3 requires.

**2. Implement a conformant KEM through supported extension points — REJECTED.** It is a
project-local cryptographic fork under gate 3, ADR-017, ADR-036, and prompt 19, for the
reasons stated above. It closes no gate: gates 1, 2, 4, and 7 are untouched, and gate 3
moves away from satisfaction, because the implementation becomes project-local rather than
maintained. It enlarges the reviewable surface at the most sensitive layer in the build,
replacing a maintained cipher-suite provider with a project one. It requires a new direct
dependency and project-local `unsafe` FFI, each a reviewed decision in its own right. It
targets a specification still in motion — `-06` and `-10` differ in label position and the
chain beneath is mid-revision — so the code would be written to a revision expected to
change and then discarded. And it would buy nothing even if perfect: the MLS suite
identifier stays Private Use `0xFE4C`, no counterparty implements `TBD2`, and the change
would still cost the full beta reinitialization below.

**3. Migrate to a different maintained MLS provider — REJECTED.** OpenMLS stable is 0.8.1
(2026-02-13) and 0.9.0-rc.2 (2026-08-06) is still a release candidate; both document only
the three classical RFC 9420 suites. Its post-quantum work targets
`MLS_256_XWING_CHACHA20POLY1305_SHA256_Ed25519` at experimental `0x004D` with no IANA code
point. That provider has the right KEM and the wrong AEAD, KDF, and hash; `mls-rs` has the
right AEAD, KDF, and hash and the wrong KEM. Migrating trades one divergence set for
another of the same class while discarding a working, tested beta stack and reinitializing
every beta group. No maintained provider implements `TBD2`. OpenMLS remains the production
preference precisely because its X-Wing path could one day satisfy gate 3 with maintained,
formally verified primitives — but on a different suite, and not today.

**4. Defer entirely — REJECTED.** The divergence is not prospective: it is on disk, in
built beta artifacts, and already governs every beta key schedule. ADR-036's 2026-08-16
correction of fact recorded *that* the KEM diverges but did not resolve *whether it must
change*, and the divergence set it referenced was incomplete — it lacked the
`DeriveKeyPair` structural difference, the missing encapsulation-key check, and the finding
that no newer maintained crate exists. Deferring leaves an unresolved protocol question
attached to live beta state and makes the next auditor re-derive the same evidence.
Deciding "no change, here is the complete set, here is the cost of changing" resolves it
and stays reversible, because the reversal trigger is written down.

### Consequences

No reinitialization is triggered by this decision. `BETA_STATE_FORMAT_VERSION`, transport
v3, schema v11, sealed key-package snapshots, sealed group state, existing beta groups, and
queued beta group objects all remain valid, and the ciphersuite identifier stays Private
Use `0xFE4C`. Whenever the KEM does change, in either direction, the cost is fixed by the
divergence set: no stored beta HPKE key pair or epoch secret survives, because every one is
bound to `kem_id 0x000F` through `dkp_prk` and the HPKE `suite_id`; the serialized
private-key layout changes, so sealed snapshots must be reinitialized rather than migrated;
uploaded consumable and last-resort beta KeyPackages must be replaced; in-flight queued
group objects must be dropped; every beta group must be recreated and re-invited; and the
state-format version must reject old state explicitly, because `Npk` and `Nenc` are
unchanged and nothing fails at parse time. That is the ADR-036 disposability rule already
exercised for v2 to v3 under ADR-037, and it is a closed-beta reinitialization, never a
production migration.

The beta remains a hybrid ML-KEM-768 + X25519 group implementation that is **not** a
`TBD2` implementation and MUST NOT be offered as `TBD2` interoperability evidence.

**This decision does not open any production gate.** All seven gates in
`docs/mls-profile.md` remain closed and none is weakened or partially satisfied. It does
not satisfy or relax ADR-017 or ADR-026, does not authorize a classical fallback, a
production ciphersuite identifier, or a production KeyPackage path. Production continues to
resolve the unsupported adapter, `GroupProductionGate.releaseAssertion` stays closed, and
production KeyPackage generation and group creation remain impossible.

**Reversal trigger.** Re-open this decision when a maintained provider implements `TBD2`'s
KEM `0x647a` against a stable, non-expiring specification — production gates 1 and 3. That
is an upstream event, not a task this project can perform.

## Dependency opinion

The mandated Flutter stack is appropriate. The main qualification is that packages are
replaceable infrastructure/presentation adapters. No package's model is allowed to become
the product protocol. Versions are selected and pinned during scaffolding after platform
spikes, not guessed in this document.

## Decisions that do not block development

- Product name, logo, and app icon remain placeholders. The Android application IDs are
  **not** placeholders: ADR-042 froze them, and ADR-044 makes the Private Experimental
  one the identity the initial deployment ships under.
- Direct signed APK distribution is the initial release channel, defined by ADR-044.
  Self-hosted Web distribution is post-v1 and requires a later approved release decision.
- Django Admin remains the administration surface; a client admin feature is out of
  scope.
