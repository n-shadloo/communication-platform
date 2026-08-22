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

| ADR-046 | Accepted, Layers 0 and 1 amended by ADR-047 and ADR-049 | Background message delivery is layered — a composed foreground socket, a best-effort WorkManager floor, and an opt-in `specialUse` foreground service holding the same connection — and a notification is a projection of committed local state, never of the transport; supersedes ADR-029 (2026-08-21) | ADR-029 chose best-effort polling and no persistent service. Inspection of the composed artifact found something else entirely: `SyncLifecycleSupervisor`, `DioWebSocketGateway`, `GatewayRealtimeSyncAdapter` and `NetworkingFoundation` exist, are tested, and are constructed **only in tests**, and `durableSyncEngineProvider` is read by nothing, so the shipped build neither drains its mailbox nor transmits its outbox — `SendConversationEvents` ends at `fanout.prepareAndQueue` and the rows stay there. ADR-045's disclosure "messages arrive only while this app is open" is therefore wrong in the user's favour and is corrected here. On the platform, primary sources read 2026-08-21 leave a narrow design space: a backgrounded process is cached, and "if all processes for a particular app are frozen, the system terminates any active TCP sockets maintained by the app", so an unattended socket is closed rather than slow; `WorkManager`'s floor is 15 minutes, Doze defers `JobScheduler` to maintenance windows that thin out over time, Android 16 enforces job quota even in the active standby bucket, and the *rare* and *restricted* buckets disable background network outright, so deferrable work can only ever be *eventual*; while-idle alarms buy six minutes of best-case cadence for a user-revocable `SCHEDULE_EXACT_ALARM` and still wake an app that has no network. The one documented state with unrestricted background network is "app process is running a foreground service", and Android's own Doze acceptable-use table rates the battery-optimization exemption **Acceptable** for an "instant messaging, chat, or calling app" that "can't use FCM because of technical dependency", which is this application exactly — the exemption granting that an app "can use the network and hold partial wake locks during Doze and App Standby" and being itself an exemption from the Android 12 background FGS-start restriction. The type is `specialUse` with a truthful subtype property, because `dataSync` is capped at 6 h/24 h and barred from `BOOT_COMPLETED` at `targetSdk` 35+, `remoteMessaging` means device-to-device continuity, and `systemExempted` is gated on roles this app lacks; the existing test forbidding `remoteMessaging` and `FOREGROUND_SERVICE_DATA_SYNC` in the manifest stands unchanged. Exactly one delivery owner runs at a time, held as a durable Drift lease rather than an in-memory flag, because concurrent isolates would race a *rotating* refresh token and can invalidate the session. Notifications fire only from the existing `PostInboxCommitWorkPort` after the inbox transaction commits, deduplicated by a durable `notified_at`, recovered by query rather than replay, and bounded by a grouped summary. Reliability is stated in four tiers and never as a guarantee: near-real-time foregrounded; near-real-time best-effort backgrounded when the user has granted the exemption and their vendor cooperates; eventual otherwise, and nothing at all in the *rare* and *restricted* buckets; and nothing whatsoever after force-stop, which no design can change. The costs are accepted and disclosed: a persistent shade entry that makes the app observable on the device, real battery use, two permissions, and per-vendor setup on the 77% of the Iranian fleet that is Samsung or Xiaomi (Statcounter, July 2026). Layer 2 ships off by default and may not be enabled in any distributed artifact before the physical-device matrix runs; UnifiedPush was rejected because the backend has no push endpoint and may not be changed, it needs a second app and a second service per user, and it moves message-timing metadata outside the reviewed boundary without removing the Android constraint; SMS wake was rejected outright for binding accounts to carrier-held phone numbers. No experiment was run: only Play-Store emulator images without root were available and no Samsung or Xiaomi hardware, so a local result would have proved nothing about the fleet that matters. Reaffirms ADR-013, opens no production gate, changes no cryptographic behaviour, and adds no dependency by itself. |
| ADR-047 | Accepted | The delivery path is composed at the application root, on the one networking foundation, and a send is a durable write the supervisor observes rather than a call it receives (2026-08-21) | Implements ADR-046's Layer 0 and closes its follow-up step 1. **The two composition roots are resolved into one**: `AuthenticationAssembly` owns a single `NetworkingFoundation` — one `DioRestClient`, one `TokenCoordinator`, one provisioned `SecurityContext` — and the socket is built from it by `NetworkingFoundation.realtimeGateway`, so close 4001 refreshes and close 4003 revokes through the coordinator the whole application shares. A second coordinator was rejected outright: both would rotate the same refresh token and the loser would present one the server has already retired, ending the session for both. `NetworkingFoundation` was dead code and, contrary to ADR-046's inventory, had no tests at all; it is kept and made live rather than deleted, because the role its name claims is the role the application needs. **Ownership sits at the application root**, as a Riverpod notifier the root holds through `listenManual`: `flutter_riverpod` 3.3.2 pauses subscriptions created in `build` when their widget leaves the view (`ConsumerStatefulElement._applyTickerMode`, verified in the pinned source), so a screen-owned or `ref.watch`-owned controller would silently stop managing sessions when a route covered it, while `listenManual` subscriptions are never ticker-mode managed. Exactly one session runs at a time, serialized on one transition queue with the wanted scope re-checked after every await; the durable cross-isolate lease ADR-046 requires is not built and is not yet needed, because this stage composes exactly one isolate. A session runs only for `fullScope`/`offlineFullScope` and stops when logout *begins*, because `TokenCoordinator.logout` wipes protected storage and closes the database before it emits the termination a completion-triggered stop would wait for. **A send is not a call into the supervisor**: composers write exact per-recipient ciphertext into `outbox_operations` and return, and the supervisor requests a cycle when the durable projection's outbox depth *increases*. Reacting to depth being non-zero was rejected — every engine run rewrites the connection phase and re-emits the projection, so it spins against a row waiting out its backoff (demonstrated: the rule inverted makes the loop-safety test hang) — and an in-memory trigger port was rejected for needing cross-feature wiring that the durable queue already provides, and for not surviving a restart. Two platform edges were corrected because they neutralised the composed path: Flutter leaves `WidgetsBinding.lifecycleState` null until the first `SystemChannels.lifecycle` message and documents the initial value as detached "updated to the current state (usually resumed) as soon as the first lifecycle update is received", so reading "not yet reported" as background made a session started at launch stand itself down and never connect; and connectivity_plus documents that Android 8.0+ does not deliver connectivity changes to a backgrounded app and that status should be re-checked on resume, so a cached *unavailable* could outlive the outage and block foreground reconnect. Connectivity, lifecycle, wall-clock delay and the deferred scheduler are resolved and released together as one `DeliveryPlatformPorts`, which is also what lets a test drive the real supervisor without a device. This build composes `UnscheduledBestEffortPolling`, which schedules nothing and emits nothing: ADR-046's Layers 1 to 3 stay unbuilt, a backgrounded application still performs no catch-up, and ADR-045's `foregroundDeliveryOnly` disclosure — previously wrong in the user's favour — is now true, so its revision does not move. Adds no dependency, changes no cryptographic behaviour, opens no production gate, and leaves the Beta/Production boundary untouched: the engine's group stack still resolves through the compile-time permit, and the production artifact verifies unsigned and free of the beta MLS symbol. |
| ADR-048 | Accepted | The user is told a message arrived by one sender-neutral system notification that is a reconciliation of committed local state, not an event; amends ADR-046's Layer 3 and ADR-045's delivery disclosure (2026-08-21) | ADR-046 sketched Layer 3 in three sentences and ADR-047 built the delivery path under it; inspection of the composed artifact found no notification port, adapter, channel or dependency of any kind, and two things that change what could honestly be built — a message arriving into the conversation on screen is still marked unread, because `ChatConversationView` marks read exactly once from `initState`, so `messages.unread` alone cannot answer "is the user looking at this"; and inbound **group** messages set no unread state at all, because `commitMessageInsideTransaction` writes neither `unread` nor `unread_count`, which is a piece-18 gap left unfixed here because `GroupChatPage` also never marks a group read. Three of ADR-046's Layer 3 details are amended on evidence. **One aggregate notification, not bounded individual ones plus a summary**: with a sender-neutral preview, N notifications are N copies of one sentence, and the only thing they add is a per-message or per-conversation identifier visible to `system_server` and to any app holding notification access — which the threat model's "person with filesystem access to a locked device" adversary and its protection of "notification previews" both weigh against; `MessagingStyle` and conversation shortcuts were rejected outright for publishing a pseudonymous per-contact identifier into the launcher, and an unspecified per-package cap (AOSP near 50, OEM-variable, unqueryable) makes any count-growing design unspecified. **A reconciliation of durable state, not an emission from `PostInboxCommitWorkPort`**: that hook fires only when the engine runs, so it can announce but never *withdraw*, and read-elsewhere, withdrawn-by-sender, conversation-opened and mute are all changes to committed state that no post-drain hook observes; drift dispatches table updates only after `COMMIT` (`Transaction.complete()` precedes `disposeChildStreams()`, verified in pinned 2.34.2 source), so a stream over `messages` and `conversations` is a strictly post-commit trigger and preserves ADR-046's actual principle more directly than the hook did. **A boolean `messages.alerted` (schema 12), not `notified_at`**: nothing reads the time, and it survives projection rebuilds because the projector upserts with a companion that omits the column, the same mechanism that already preserves `starred`. Content is `New message` / `New messages` and nothing else — no sender, conversation, text, count or timestamp — `VISIBILITY_PRIVATE` with a matching `setPublicVersion`, because Android 15 shows that during screen sharing and otherwise redacts "without any further context". Tapping carries the launcher intent alone under `FLAG_IMMUTABLE`: no destination, no extra, no identifier, so there is nothing to forge and no path around the routing guards. Deliberate silence (muted, on screen) still spends the marker so it cannot surface late; a platform refusal spends nothing, so granting later announces the backlog. "On screen" requires a mounted route **and** a foregrounded application, with an unreported lifecycle read as foreground for ADR-047's reason. One automatic `POST_NOTIFICATIONS` prompt at the point of use, guarded by a durable marker and by `shouldShowRequestPermissionRationale` — true in exactly the one state where a second refusal would make the denial permanent — so the app never nags and never spends the user's last prompt. No dependency: `flutter_local_notifications` 22.3.0 would work but every API needed is in `androidx.core:core:1.16.0`, already declared for `FileProvider`, so the platform half is app-owned Kotlin behind a port that carries no identifier and holds no policy. Only `POST_NOTIFICATIONS` and `VIBRATE` are added; a new architecture test forbids every foreground-service, boot, exact-alarm and SMS permission while ADR-046's Layers 1 and 2 stay unbuilt. Reliability is unchanged and stated: an alert reaches the user only while the process is alive, so ADR-045's `foregroundDeliveryOnly` — which said "There are no notifications" — is now false, its revision moves 1 → 2, and re-delivering the written handover becomes release-blocking. The Kotlin half is **unmeasured**: no rooted image and no signed-in session are reachable from this workstation, so what the notification looks like on a device is a release gate, not a claim. Full reasoning in "ADR-048 in full" below. Opens no production gate and changes no cryptographic behaviour. |
| ADR-049 | Accepted, ownership arbitration corrected by ADR-050 | A backgrounded client catches up through one persisted periodic `JobScheduler` job at the platform floor, delivered to the isolate that already exists or to a headless one when none does, and never to both; ADR-046's WorkManager dependency and its durable delivery lease are both replaced (2026-08-21) | ADR-046's Layer 1. Nothing was assumed: every Android mechanism that runs without the user was re-derived from primary sources read 2026-08-21, and the scope excludes anything the user must grant, configure or change, which removes the foreground service, the exact alarm and the battery-optimization exemption by definition and leaves deferrable jobs as the only floor. **The dependency is dropped.** `JobInfo` is in the framework at `minSdk` 24 and `setPersisted(true)` survives a reboot with no receiver of this application's own, so `androidx.work` would have added a Room database, a service and a boot receiver to the merged manifest of a security-reviewed artifact in order to schedule one job; the existing test forbidding the `workmanager` package therefore stands and now records a decision rather than an absence. **The durable Drift lease is dropped too, and replaced by something exact.** Verified in the pinned engine source, `DartVMRef::Create` documents that "there can only be one VM running in the process at any given time", the `IsolateNameServer` belongs to that VM, and the job service is declared with no `android:process` — so every delivery owner this design can produce is in one process, on one main looper, and in-process arbitration is not weaker than a heartbeat lease but strictly more precise: a job whose process holds a live activity engine sends `runCatchUp` into that isolate and waits for the reply, and only a process with no engine starts a headless one. The hazard being removed is concrete and now evidenced twice over: two `TokenCoordinator`s rotate one refresh token, the loser presents a retired one, the backend returns 401 `invalid_token` (accounts `API.md`) and `TokenCoordinator._endsSession` clears the session — and `beginNextEnvelopeInspection` selects rows in `received` *or* `inspecting`, so two engines would hand the same envelope to the ratchet twice. A foreground session therefore asks the platform for exclusive ownership *before* it opens storage or reads a token, and waits for a headless run rather than killing one mid-call into the shared native core. **A tick is acknowledged, not fired and forgotten**, because a job that is finished lets the process be frozen again and an unacknowledged tick is a catch-up the platform stops mid-drain. **Arming moved off the lifecycle**: a periodic job restarts its window every time it is registered, so ADR-046's arm-on-background/cancel-on-foreground would have meant a user who opens the app more often than the interval never receives one wake-up, and a process that died while foregrounded would have left nothing scheduled at all; it is armed once for the life of a signed-in session and disarmed on logout, and a headless run that finds no session disarms it for itself. **Both entry points now compose through one `ApplicationRuntime`**, so the provisioned authority, the single token coordinator and the environment-gated crypto core cannot be silently absent from the background path; `MainActivity`'s protected-storage and message-alert channels were Activity-scoped and unreachable from a headless engine, and are now Context-bound classes with one implementation each. The alert path needs no change and asks for no permission in the background, because `ReconcileMessageAlerts` already gates the single automatic prompt on `visible.isForeground`. Reliability is stated in four tiers and never as a guarantee: near-real-time foregrounded; *eventual* backgrounded, fifteen minutes at best and bound to Doze maintenance windows that thin out; **nothing** in the *rare* and *restricted* buckets, where Android disables background network and which Android 13+ applies after eight days without interaction; and nothing whatsoever after a force-stop. ADR-045's disclosure moves to revision 3 in both catalogues, which makes re-delivering the written handover release-blocking again. Adds no dependency, changes no cryptographic behaviour, opens no production gate, and leaves the Beta/Production boundary untouched — verified after the change against the built artifact, which packages unsigned, carries the production application ID, exports no beta MLS symbol, and declares exactly one service, bound with `BIND_JOB_SERVICE`, unexported, in the default process, with no foreground-service permission of any kind. |
| ADR-050 | Accepted | Exactly one part of the application drives delivery, arbitrated in the process and asked for by the *entry point* rather than by the delivery session; the losing owner is asked to stand down and gives way between units of work; and losing a refresh-token rotation to another owner is repaired instead of read as the server ending the session; corrects ADR-049 (2026-08-22) | The hazard ADR-049 named is real and reachable on an ordinary user action - a headless catch-up posts a notification (ADR-048), the user taps it, and two Dart root isolates in one process both rotate one shared refresh token that the backend blacklists on use (`ROTATE_REFRESH_TOKENS` with `BLACKLIST_AFTER_ROTATION`), signing out a user who did nothing. ADR-049 chose the right mechanism and put it in the wrong place: `awaitExclusiveOwnership` was called by `MessageDeliverySession.compose`, which is reached only after `AuthenticationController.restore()` - and that restore *is* the rotation. A test asserted the opposite and passed, because its harness replaced the real `TokenCoordinator`; `sync-engine.md` simultaneously claimed a durable lease ADR-049 had already removed. The gate moves to `bootstrap()`, before storage is opened or a token is read; `attachForeground` now asks an in-flight catch-up to stand down, which `DurableSyncEngine` reads between envelopes, pages and batches, so the foreground waits for one unit of work rather than a whole drain; and the coordinator tells a lost race apart from a real session ending by re-reading the shared durable row rather than its own per-isolate cache. ADR-046's durable lease was re-derived independently and rejected again: every owner is in one process, so a lease coordinates things that always die together while adding an expiry, a clock and a stale-holder window - and it would be *weaker* where it matters, because a headless engine destroyed while the process survives leaves a lease nobody releases, whereas the Kotlin arbiter is the code that destroys it. Nothing durable records ownership and no wait is unbounded, so the mechanism cannot wedge delivery. Proved with two real isolates over one real shared SQLCipher store, in both orderings, under repeated contention, and with a contender killed mid-rotation. Separately corrects a pre-existing defect the work uncovered: `account_session` and `account_identity` were upserted without `singleton_id`, which SQLite treats as a rowid alias and auto-assigns, so every write after the first threw `SqliteException(275)`. Adds no dependency, changes no cryptographic behaviour, touches no backend, opens no production gate, and changes nothing the application says about itself. |

## ADR-050 in full — guaranteeing that one part of the application drives delivery (2026-08-22)

**Status:** Accepted. Corrects ADR-049's ownership arbitration, which was placed downstream
of the operation it existed to protect, and adds the repair that makes the shared durable
row safe when the arbitration cannot run at all. Reaffirms ADR-049's *choice* of mechanism
on re-derived evidence. Adds no dependency, changes no cryptographic behaviour, touches no
backend, opens no production gate.

### The question

> More than one part of this application may be capable of driving the same delivery work
> against the same device, at the same time, without sharing memory. Is that true, exactly
> which shared things are unsafe when it is, and what makes it impossible for two of them
> to be doing the unsafe part at once — including when one of them stops existing
> mid-operation and never gets to clean up?

Nothing was assumed: not that the hazard exists, not the mechanism, not where the
coordinating state lives, not the unit of exclusion, not what a loser does, and not that
ADR-049's answer was right.

### Exact environment, fixed

Unchanged from ADR-044 and ADR-049. 20–30 users, all in Iran, private handover, no foreign
runtime dependency at any layer, backend inside Iran and reachable, Android/Flutter client
installed as a signed artifact, server an untrusted relay, devices killed and restarted
without cooperation. `minSdk` 24, `targetSdk` 36, Flutter 3.44.7 / Dart 3.12.2.

### Is the hazard real? Yes, and it is reachable on an ordinary user action

Established from the composed artifact on 2026-08-22, by trace rather than by inference.

**Two drivers can exist.** `DeferredDeliveryJobService` is declared with no
`android:process`, so it runs in the default process; `beginCatchUp` starts a headless
`FlutterEngine` when no activity engine is attached. Two `FlutterEngine`s in one process
share one Dart VM but **not** one heap: two Dart *root isolates*, no shared memory, one
shared SQLCipher file.

**They meet on a user action, not on a rare interleaving.** The job fires while the process
is gone → a headless run starts → the user opens the application. ADR-048 makes that
sequence *more* likely rather than less: a catch-up that finds a message posts a
notification, and tapping it is what starts the activity.

**What they both touch, and how badly.**

| Shared thing | What two drivers do to it | Severity |
|---|---|---|
| `account_session.token_metadata_ciphertext` — the **rotating** refresh token | both read `R0`; both present it; the backend blacklists on rotation, so the loser gets `401 invalid_token`, which `_endsSession` reads as the server ending the session → `store.clear()` deletes the shared row | **destroys session state**: the device is signed out and the user must log in again |
| `inbox_envelopes` rows in `received`/`inspecting` | `beginNextEnvelopeInspection` deliberately re-offers `inspecting` rows so a crashed inspection is retried, so both claim the same lowest-sequence envelope and hand one ciphertext to the ratchet twice | corrupted/duplicated ratchet work |
| outbox target rows | same claim-and-send shape | duplicated sends; recipients deduplicate by event id, so mostly wasted effort |
| alert markers (ADR-048) | two reconciliations of one shade | cosmetic |
| group KeyPackage maintenance, pending eviction, outbound dispatch | concurrency properties never established | unknown, therefore treated as unsafe |

The first row is the sharp one and it is not theoretical. `config/settings/base.py` sets
`ROTATE_REFRESH_TOKENS: True` and `BLACKLIST_AFTER_ROTATION: True`;
`backend/accounts/API.md` states it in the contract — "the presented token is blacklisted
and a new access/refresh pair is issued", "replaying an already-rotated token is a 401",
and that `401 invalid_token` "also covers expired and already-blacklisted tokens". In the
client, `BackendFailureCode.invalidToken` is in `_endsSession`, so the loser terminates.

**And the window is not narrow.** `SecureSessionTokenAdapter` never persists an access
token; a restored process reconstructs one with `expiresAt` at the epoch, precisely so that
"the coordinator rotates the persisted refresh token before any authenticated request can
be sent". So the *first* authenticated act of *every* fresh root isolate is a rotation of
the shared row. Two isolates starting within one network round trip of each other both
present `R0`.

### What the repository actually did before, and where it disagreed with itself

ADR-049 identified this hazard precisely and named the right mechanism. Its arbitration is
sound: `BackgroundDelivery` is a Kotlin object in the one process, mutated only on the main
looper — `JobService` "executes each incoming job on a `Handler` running on your
application's main thread", and `FlutterActivity.configureFlutterEngine` is on the same
looper.

**But the gate was in the wrong place.** ADR-049 states: "`MessageDeliverySession.compose`
calls `awaitExclusiveOwnership()` before it opens storage or reads a token". Traced through
the composed application, that is false:

1. `MessageDeliveryController` starts a session only for `fullScope`/`offlineFullScope`;
2. that access state is produced only by `AuthenticationController.restore()`;
3. `restore()` calls `CoordinatedAuthenticationSession.restore()` → `tokens.read()` (opens
   protected storage) → `coordinator.accessToken()` (**rotates the shared refresh token**);
4. the router sends a dormant launch to `/session-restoring`, whose first post-frame
   callback is that `restore()`.

So the ownership question was asked *strictly after* the operation it existed to protect.
The mechanism prevented two engines; it did not prevent the two token coordinators whose
collision ADR-049 traced to "401 `invalid_token`, `_endsSession`, `store.clear()`, and a
user signed out who did nothing".

**A test asserted the opposite and passed.**
`test/app/dependencies/message_delivery_composition_test.dart` — "a session waits for a
catch-up that already owns delivery" — asserts `harness.http.requests` is empty while
ownership is held, with the comment "before it opens storage or reads a token — not
after". It passes because its harness overrides `restore` with a fake session, so the real
`TokenCoordinator` never runs. It is a true statement about the delivery session and was
read as a true statement about the application.

**Documentation contradicted itself.** `docs/sync-engine.md` said, in *Token lifecycle*,
that "the durable delivery lease of ADR-046 is what actually prevents two coordinators from
racing the rotating refresh token" — while, forty lines later, recording that ADR-049 had
removed that lease. Both halves cannot be true, and the half that was load-bearing for the
sharpest hazard named a mechanism that does not exist in the artifact.

**A separate, pre-existing defect made the whole area unverifiable.**
`SecureSessionTokenAdapter._writeFullSession` built `AccountSessionsCompanion.insert`
without `singletonId`. `singleton_id` is the sole `INTEGER` primary key of a rowid table, so
SQLite treats it as an alias for the rowid: an insert that omits it is assigned
`max(rowid) + 1` and the `DEFAULT 1` is never reached. The first write to a database
succeeds with rowid 1; **every write after it fails** `CHECK("singleton_id" = 1)` with
`SqliteException(275)`, thrown out of `store.replace(...)` inside `_performRefresh`. Every
token rotation after the first, on any given device, would have thrown. Reproduced directly
on 2026-08-22 against a real `LocalDatabase`; no test covered a second write.
`drift_enrollment_journal_store.dart` had the identical omission for `account_identity`.
`DriftSyncStore._ensureCheckpoint` has it too but is harmless by accident, because
`INSERT OR IGNORE` swallows the CHECK violation and the "ensure exists" intent is met
anyway.

### Research findings

Primary sources only; blogs and forums were used for discovery and are cited nowhere.

**One Dart VM per process, and one `IsolateNameServer` owned by it.** Read at the exact
pinned revision — `flutter/flutter@84fc5cbb22` (Flutter 3.44.7), 2026-08-22.
`engine/src/flutter/runtime/dart_vm_lifecycle.h`: "There can only be one VM running in the
process at any given time." `dart_vm_lifecycle.cc`: `DartVMRef::Create` takes `gVMMutex`,
and "If there is already a running VM in the process, grab a strong reference to it" —
returning the existing VM and logging "Ignoring arguments for current VM create call and
reusing the old VM". The name server is created once per VM
(`auto isolate_name_server = std::make_shared<IsolateNameServer>()`), stored as
`gVMIsolateNameServer`, and served to every caller by `DartVMRef::GetIsolateNameServer()`.
`dart:ui`'s own documentation: "All isolates share a global mapping of names to ports."
ADR-049 asserted this; it is now verified at the pinned revision.

**Which settles what the storage layer actually is.** `drift_flutter` 0.3.1
(`lib/src/native.dart`, read 2026-08-22) implements `shareAcrossIsolates: true` by looking
up `drift-db/<name>` in `IsolateNameServer` and, if present,
`DriftIsolate.fromConnectPort(port).connect()`; only when absent does it spawn an isolate
that registers itself. Because the name server is VM-wide, the headless root isolate and
the activity root isolate **connect to the same database server isolate**: one
`NativeDatabase`, one SQLCipher connection, one file. There is no second connection and no
file-level locking question to answer.

**What that server guarantees under concurrent clients.** drift 2.34.2,
`lib/src/remote/server_impl.dart`: "when a transaction is active, all queries that don't
operate on another query executor have to wait", implemented by `_executorBacklog` and
`_waitForTurn`; and `lib/src/runtime/executor/helpers/engines.dart`, where
`_StatementBasedTransactionExecutor.ensureOpen` holds the parent executor's `Lock` until
the transaction completes ("Block the main database or the parent transaction while this
transaction is active"). So **a drift write transaction is already mutually exclusive
across isolates**. `singleClientMode` defaults to `false` on this path, so closing one
client does not shut the server down for the other, and table-update notifications are
forwarded to every *other* connected client (`dispatchTableUpdateNotification`).

This is a precise and load-bearing limit: transactions are atomic and serialized across
owners, so nothing is half-written. What is *not* protected is any logical operation that
spans transactions with I/O in between — read token → rotate over the network → write
token, or claim envelope → decrypt → commit. Those are exactly the unsafe operations above.

**Platform threading and process death.** `JobService`: "This service executes each
incoming job on a `Handler` running on your application's main thread"; "Job services must
be protected with this permission" (`BIND_JOB_SERVICE`), and one that is not "will be
ignored by the system"; `jobFinished` releases the wakelock the system holds for the job
(developer.android.com/reference/android/app/job/JobService, read 2026-08-22). AOSP cached
apps freezer: "If all processes for a particular app are frozen, the system terminates any
active TCP sockets maintained by the app" (source.android.com/docs/core/perf/
cached-apps-freezer, read 2026-08-22).

**Clocks.** Deliberately not researched into a dependency, because the design uses none.
No part of this decision reads wall-clock time, elapsed time, or a timer whose value
affects who owns delivery. That removes the entire class of failures a lease-based design
inherits from a clock a user can set.

**Backend, read-only.** `backend/config/settings/base.py` and `backend/accounts/API.md`, as
quoted above. No backend file was read for anything other than its contract, and none was
changed.

### Alternatives evaluated

**1 — Nothing; the hazard is not real.** Rejected on the trace above and on
`delivery_owner_contention_test.dart`, which reproduces the damage with two real isolates
over one real shared store.

**2 — Keep ADR-049's arbitration exactly as it is.** Rejected: it does not cover
`restore()`, which is where the damage is. This is a placement defect, not a mechanism
defect.

**3 — Reinstate ADR-046's durable Drift delivery lease.** Re-examined independently rather
than inherited from ADR-049's rejection, and rejected again, more firmly. Every owner that
can exist lives in one OS process (no `android:process`; one Dart VM per process; the job
service runs in the default process), so a durable lease coordinates between things that
always die together. What it *adds* is the entire stale-holder problem: an expiry, a clock
to measure it with, a heartbeat writing to an encrypted database forever, and a window
after every crash in which delivery is blocked by a lease nobody holds. That is a permanent
availability failure introduced to fix an intermittent correctness one, which the brief
names as the worse outcome. It is also strictly weaker in the case that matters most: the
headless engine is destroyed by `onStopJob` or by the four-minute deadline **while the
process survives**, and a durable lease would then be stale with nothing to release it,
whereas the Kotlin arbiter is *the same code that destroys the engine* and releases in the
same call.

**4 — A Dart-side lock over `IsolateNameServer`.** Genuinely available — it is VM-wide and
`registerPortWithName` is an atomic test-and-set, which is how `drift_flutter` elects its
database server. Rejected: `FlutterEngine.destroy()` kills the headless root isolate
abruptly and leaves the name registered, wedging the foreground until the process dies.
Recovering from that needs `Isolate.ping` liveness probing with a timeout — more machinery,
a new failure mode, and no advantage over an arbiter that already owns the engine's
lifetime.

**5 — Remove the concurrency instead of coordinating it.** Two shapes. Delete the headless
entry point: rejected, that is ADR-049's whole value and a backgrounded client would
receive nothing. Or never start a headless run when an activity might appear: impossible,
the platform starts the activity, not this application.

**6 — Kill the in-flight headless run when the user opens the application.** Rejected for
ADR-049's reason, re-checked: the run may be inside the shared native cryptographic core
(on a worker isolate spawned from the headless root, so engine teardown takes the whole
group). Abandoning remains what happens when the *platform* takes the decision — `onStopJob`
and the four-minute deadline — and is not made the ordinary path.

**7 — Let the foreground wait for the headless run to finish naturally.** This is what
ADR-049's design does. Rejected as the *whole* answer once the gate moves to launch: the
bound on that wait is a complete drain — up to 100 pages of 100 envelopes — and blocking
application launch on it is a visible failure. Waiting is kept; what changes is that the
thing being waited for is asked to stop.

**8 — Protect only the refresh token and let the rest overlap.** Rejected for ADR-049's
reason, which still holds: `beginNextEnvelopeInspection` re-offers `inspecting` rows by
design, and the post-inbox composite's concurrency properties are not established.
Exclusion covers the whole cycle.

**9 — Make the refresh token safe and *also* exclude.** Selected. The two are not
alternatives: one is the guarantee, the other is what the guarantee's own failure costs.

### Decision

**Three changes. One moves the gate to where the damage is, one makes the losing owner give
way promptly, and one makes the sharpest shared row survive the mechanism failing
altogether.**

**A. The ownership question is asked by the entry point, before anything exists.**
`bootstrap()` awaits `DeliveryOwnershipGate.awaitExclusiveOwnership()` before
`ApplicationRuntime.create` — before protected storage is opened, before a token is read,
before `runApp`. One gate, at the one place every foreground path passes through, covering
session restoration, delivery, alerts, and anything added later. The session-level
`awaitExclusiveOwnership` in `MessageDeliverySession.compose` stays as a second, normally
instant check.

**B. The catch-up gives way; the foreground never yields.** The two owners are not
symmetric. A catch-up runs *because* nobody is looking; the moment somebody is, the
foreground drains the same mailbox within seconds and the run has no reason left to exist.
`BackgroundDelivery.attachForeground` — which runs in `configureFlutterEngine`, before that
engine's Dart entry point does anything — invokes `standDown` on the headless engine's
channel. `DeferredCatchUpHandshake` latches it and *is* the `DeliveryStandDownSignal` the
engine reads, so what the platform says and what the engine sees cannot drift apart through
a mapping layer. `DurableSyncEngine` reads it between units of work: before each envelope
inspection, each drain page, and each outbox batch. A displaced cycle finishes the
transaction it holds, reports `deferred`, and stops; the catch-up returns `displaced`,
skips the alert pass, and reports finished. Nothing is abandoned part-way.

**C. Losing a rotation is repaired, not read as the session ending.** `TokenCoordinator`
now distinguishes the two things a `401 invalid_token` can mean, using the shared durable
row rather than its own per-isolate cache:

- the success path compares against `store.readDurable()`, so a rotation cannot overwrite a
  newer pair another owner persisted while it was in flight;
- the failure path, and only for `invalid_token`/`token_not_valid` (never `token_revoked`,
  which means a revoked device or a dead account and cannot be repaired by presenting a
  different token), waits briefly and finitely for the row to move. If it moves, another
  owner rotated first: adopt what it wrote and rotate that, up to a small budget. If it
  never moves, the session really is over and is ended exactly as before.
- Exhausting the budget while the row keeps moving is reported as a **transient** failure,
  never a termination — a row that keeps moving is positive evidence that the session is
  alive, and ending it there would be the one outcome that cannot be undone.

The wait is bounded by a **count**, not by elapsed time (default 40 × 25 ms), because a
device clock can move backwards and a wait that cannot terminate is the failure this whole
piece exists to avoid. `readDurable()` is a new `SessionTokenStore` method; it reads the row
without disturbing the in-memory access token, which the durable row never holds.

**D (correction, separately reported).** `singletonId: const Value(1)` is now stated
explicitly in the `account_session` and `account_identity` upserts. Without it the second
write to either table on any device throws.

### Correctness questions, answered

- **Can two contexts genuinely run at once in the shipped artifact?** Yes — two Dart root
  isolates in one process, shown above, and reproduced in test.
- **What is the unit of exclusion, and why that unit?** *All of what one delivery owner
  does with the application runtime*, from the entry point until the run ends. Not a job,
  not a resource, not an envelope: the unsafe operations span transactions with network I/O
  in between, and the composite post-inbox work has no established concurrency properties.
  A finer unit would require establishing safety for every one of them.
- **How does a contender acquire, and what does it observe when it cannot?** It asks the
  platform on the main looper. A headless run in flight is recorded; the question is
  answered when that run ends. When the platform cannot answer at all, the foreground
  proceeds after a bounded wait — see *worst case* below.
- **How does a holder release, on the ordinary path and every extraordinary one?** Ordinary:
  the Dart side reports finished, Kotlin destroys the engine, `headless = null`, waiters
  released. Displaced: the same path, reached sooner. `onStopJob`: `abandonCatchUp` →
  `finish()` → same release. Four-minute deadline: same. Engine start failure: `headless`
  cleared and waiters released in the same statement. **Process death: nothing to release,
  because nothing durable was held.**
- **How is a holder that will never release detected, and how long does that take?** It is
  not detected, because it cannot exist. Every holder is inside one process; the release is
  performed by the object that owns the holder's lifetime, on the same thread. The only
  "undetected" case is a Dart side that never reports, and that is bounded by Kotlin's
  four-minute deadline and, behind it, the platform's ten-minute job limit.
- **What stops a displaced holder still running from acting as though it holds?** The
  latched signal it reads between units of work, plus the fact that its engine is destroyed
  when it reports. In the interval between the two, it holds no exclusive resource: its
  transactions are serialized by the one drift server, and its token rotation is repairable.
- **Can the mechanism deadlock, starve, or wedge delivery permanently?** No. The arbiter has
  one waiter list and one release path, all on one thread. Every wait has a bound: 20 s at
  the entry point, 5 min at the session, 4 min for the headless engine, 2 min for a tick.
  Every bound expires into *proceeding*, never into stopping. Nothing durable records
  ownership, so nothing survives a restart to block the next run.
- **What happens on the very first run, before any coordinating state exists?** Nothing to
  wait for: `headless` is null and the question returns immediately. There is no first-run
  case because there is no state to create.
- **What if the coordinating state is corrupt, from an older version, or absent?** It cannot
  be any of those. It is two fields in a process-lifetime Kotlin object; a new process
  starts with them empty, which is the correct state.
- **Does anything the user sees change?** No new screen, no new string, no new permission,
  no new notification. The only visible change is the *absence* of an unexplained sign-out.

### Guarantees, assumptions, observations — three different things

**Guaranteed by construction, with the argument:**

1. *No stale holder can exist.* Every owner lives in the one process (manifest declares no
   `android:process`; the Flutter engine documents one Dart VM per process and reuses it),
   and the only coordinating state is process-lifetime memory. Process death releases
   everything simultaneously with the things it was protecting.
2. *The mechanism cannot block delivery permanently.* Every wait is bounded and every bound
   expires into proceeding. Nothing durable is written by it.
3. *Transactions cannot interleave destructively.* One SQLCipher connection behind one drift
   server, and drift serializes transactions across clients at the pinned version.
4. *An unanswerable ownership question is never read as "somebody else rotated".* The repair
   adopts only a value that is present *and* different; a store that cannot be read answers
   null and the session ends as it would have.

**Guaranteed only under assumptions, and here they are:**

5. *Exactly one owner drives the engine* — assuming `JobService` callbacks and
   `FlutterActivity.configureFlutterEngine` really are delivered on one looper in order
   (documented, not measured here), and assuming no future code path starts a Dart root
   isolate outside `BackgroundDelivery`.
6. *The foreground's wait is short* — assuming the displaced run reaches a unit boundary
   promptly. The bound is one envelope's inspection, one drain page, or one outbox batch,
   not a whole cycle. It is not a bound on wall-clock time.
7. *The repair converges* — assuming the losing owner can read the durable row and that the
   winner persists what it was issued.

**Merely not observed to fail, and proving nothing:**

8. That a job runs at all on a device. No device or emulator run was possible; every
   Android-side statement rests on documentation and on source assertions.
9. That the Kotlin arbiter behaves as argued. No Dart test can drive it, and what is pinned
   is the *shape* of the source, not its behaviour.
10. That a headless engine starts the `backgroundDelivery` entry point in a release AOT
    snapshot. Inherited unchanged from ADR-049.

### Failure modes, including of the mechanism itself

- **The platform never answers the ownership question.** The entry point proceeds after
  20 s. Exclusion is then absent for that launch, and the sharpest damage is bounded by the
  repair in C: a redundant rotation instead of a sign-out.
- **The stand-down request never arrives, or arrives at an engine not yet listening.**
  Kotlin re-sends on a second attach, and `standDownImmediately` covers a run started while
  an activity was already attaching. If it is still missed, the foreground waits for the run
  to end naturally — ADR-049's behaviour, with ADR-049's bounds.
- **The displaced run ignores the request.** It cannot ignore it for longer than one unit of
  work; if it is wedged inside one, the four-minute engine deadline ends it.
- **The repair adopts a token that is itself immediately retired.** Bounded by the adoption
  budget and then reported as transient. The user stays signed in and the next call retries.
- **The winner dies between being issued a token and persisting it.** The loser waits, sees
  a row that never moves, and ends the session — which is *correct*: the issued pair is lost
  and the presented one is blacklisted, so no working token exists. Covered by test.
- **The durable store is unavailable during the repair.** Fail-closed: no adoption, session
  ends as before.
- **A future second process.** Invalidates the entire argument. An architecture test fails
  if `android:process` appears anywhere in the manifest.

### Worst case if the mechanism itself fails

Both gates absent and both owners running: the loser's rotation is repaired, so the user
stays signed in; the same envelope may be handed to the ratchet twice and the same outbox
batch sent twice. The first is a decryption failure that is retried; the second is
deduplicated by recipients on the logical event id. Nothing is destroyed that a later
session cannot re-derive. That is a strictly better worst case than the one this decision
found in the artifact, where the user was signed out.

### Security and privacy

- **Can failure invalidate a session, lock a user out, or destroy account state?** That was
  the *pre-existing* behaviour and it is what C removes. The remaining path to a
  termination is a durable row that genuinely never moves, which means no working token
  exists.
- **Can anything an attacker controls influence who holds, or displace a holder?** No. The
  arbitration reads no network input and no server-supplied value. A hostile relay can
  answer `token_revoked` to end a session, which it could already do, and which the repair
  deliberately does not soften.
- **Does the coordinating state reveal anything?** It is two in-memory fields holding a
  channel reference and a run object. Nothing is written to disk, no log line, no
  preference. The stand-down call carries no arguments.
- **Can an interrupted operation leave security-relevant state in a middle position?** The
  refresh is the one that can: a rotation may be issued and not persisted. That is the case
  in *Failure modes* above, and its resolution is to end the session, not to guess.
- **Can this be used to suppress delivery or notification silently?** A displaced catch-up
  skips its alert pass — but it skips it *because* the foreground owns the shade from that
  moment and reconciles from the same committed state, and `MessageAlertController` starts
  with `_alertPosted = true` precisely so a new process can withdraw or re-post what a
  previous one left. Nothing an attacker can reach triggers a displacement.
- **No existing invariant was weakened.** Both entry points still compose through one
  `ApplicationRuntime`; the headless container's one extra override is additive and typed
  as `DeliveryStandDownSignal`, so it cannot replace a transport, storage or crypto
  override.

### Beta and production

Suitable for both, now. No dependency added, no cryptographic surface touched, no production
gate crossed, and the Beta/Production separation is exactly where ADR-042 and ADR-044 left
it. It changes nothing the application says about itself: ADR-045's disclosure revision is
unchanged at 3, because the delivery *tiers* are unchanged — this decision makes the
existing claims true rather than making new ones.

### Known limitations

- **The Kotlin arbiter is argued, not tested.** Its correctness rests on the one-looper
  argument and on source assertions.
- **The foreground's wait is bounded by a unit of work, not by a duration.** A single
  pathological envelope inspection bounds it, and nothing here caps that.
- **The repair costs up to a second before a genuinely ended session signs out.** Deliberate:
  a user who is being signed out anyway is not harmed by a second, and a user who is not
  being signed out is spared entirely.
- **`MessageAlertController` has no gate of its own.** It starts after restoration, by which
  time any headless run has been asked to stand down; its worst case is a duplicate
  notification, and it is not made a reason to add a second gate.

### Outstanding validation

1. **Everything Android-side.** No device and no usable emulator (all installed AVDs are
   Play-Store images). The displacement path, the stand-down channel call, the headless
   engine teardown and the one-looper ordering are unexercised on hardware.
2. **The interaction with `onStopJob` under real Doze/quota pressure.**
3. **That the pre-existing singleton-write defect is now genuinely absent end-to-end**, i.e.
   that a real device can rotate twice. Verified against a real `LocalDatabase` on the host;
   not on a device.
4. **The device matrix** from ADR-049 remains open and unchanged.

### Follow-up work

1. Device validation of everything in *Outstanding validation*.
2. `DriftSyncStore._ensureCheckpoint` relies on `INSERT OR IGNORE` swallowing a CHECK
   violation that a stated `singletonId` would turn into an intended primary-key conflict.
   Harmless today, fragile if the insert mode ever changes.
3. ADR-046's Layer 2 (`specialUse` foreground service) remains unbuilt. When it ships it is
   a third owner and this arbitration must be re-derived, not extended by assumption.
4. Re-delivering the ADR-049/ADR-048 handover disclosure at revision 3 remains
   release-blocking and is untouched by this decision.

### Review and revisit conditions

1. **Any second process appears** — the whole argument is that there is one. The
   architecture test fails first.
2. **A third delivery owner appears** (Layer 2, or anything else that starts a root isolate).
3. **The Flutter engine stops guaranteeing one Dart VM per process**, or `drift_flutter`
   stops sharing one database server across isolates. Both are pinned-version facts.
4. **The backend stops blacklisting on rotation, or starts revoking the whole token family
   on reuse.** The second would make the repair in C useless and would demand real exclusion
   over the refresh, not repair.
5. **Any wait here becomes unbounded**, or any coordinating state becomes durable.

## ADR-049 in full — what makes a backgrounded client take delivery (2026-08-21)

**Status:** Accepted. Implements ADR-046's Layer 1 and **replaces two of its
mechanisms** — the `WorkManager` dependency and the durable Drift delivery lease — on
evidence recorded below. Amends ADR-045's delivery disclosure to revision 3. Opens no
production gate.

### The question

The user has closed the application, or has not opened it for some time. Messages are
waiting for this device on a server it can reach. **What causes the application to take
delivery of them, how often can that honestly be expected to happen, and what must be
true for it to be safe every time it does?**

The scope excludes, by definition, anything that requires the user to grant, configure or
change something; anything that requires the application to keep running; and anything
that needs per-manufacturer instructions to work at all. This is the floor beneath every
better mechanism, and the only thing that will be true for a user who never reads the
instructions.

Nothing was assumed. The mechanism, the cadence, the entry point, the process model, the
ownership model, the dependency and the native/Dart split were all re-derived, including
the ones ADR-046 had already named.

### Exact environment, fixed

- 20–30 users, all in Iran, known to the operator, receiving the artifact by private
  handover. Nothing configured, nothing granted, no setting changed.
- International connectivity may be entirely unavailable; domestic connectivity reaches
  the backend, which is inside Iran and is the authoritative durable mailbox
  (`GET /api/v1/me/envelopes`, seven-day TTL).
- Fleet dominated by Samsung and Xiaomi, whose background-management behaviour AOSP does
  not specify. Android 11 through 16 all materially represented.
- `minSdk` 24, `targetSdk` 36, `compileSdk` 36 (read from the pinned Flutter 3.44.7
  Gradle extension, 2026-08-21). Directly installed signed APK; Play policy does not bind
  it, platform behaviour binds it completely.
- ADR-013 stands: no foreign push, no Firebase, no foreign runtime call. FCM is excluded
  twice over — by decision, and because Google's servers are unreachable exactly when
  this application is most needed.

### What the repository actually did before

Verified in the composed application on 2026-08-21, not in its documentation.

| Component | Existed | Reachable at runtime |
|---|---|---|
| Foreground socket, engine, drain, commit (ADR-047) | yes | yes |
| Alert reconciliation from committed state (ADR-048) | yes | yes |
| `AndroidPollingScheduler` port | yes | **no adapter** |
| `UnscheduledBestEffortPolling` composed as the polling port | yes | yes — it schedules nothing and emits nothing |
| Any `<service>`, job, alarm or receiver in the manifest | **no** | no |

So a backgrounded application performed no catch-up whatsoever, exactly as
`sync_platform_adapters.dart` said and exactly as ADR-045's disclosure told recipients.
Three further findings came out of that inspection and changed what could be built:

1. **The protected-storage boundary was unreachable from any second entry point.**
   `loadOrCreateStorageKey` was a method-channel handler registered in
   `MainActivity.configureFlutterEngine`, and a channel handler exists only on the engine
   that registered it. A headless engine calling it would have received
   `MissingPluginException` — which `AndroidKeystoreProtectedStorage` does not catch, so
   it would have propagated out of `SecureLocalStorageRuntime.open()`. The same was true
   of the message-alert channel. Both are now Context-bound classes with exactly one
   implementation each, and `MainActivity` keeps only what genuinely needs a window: the
   permission dialog, the settings screen, `FLAG_SECURE`, and the clipboard.
2. **The supervisor armed and disarmed the scheduler on lifecycle transitions.**
   `_enterBackground` called `polling.schedule`, `_resumeForeground` called
   `polling.cancel`. Against a *periodic* platform job that is a defect rather than a
   detail: registering one restarts its window, so a user who opens the application more
   often than the interval would never receive a single wake-up, and a process that died
   while foregrounded would have left nothing scheduled at all. Arming moved to the
   session.
3. **`SyncLifecycleSupervisor.dispose()` did not cancel polling**, so a job armed for a
   session would have outlived logout.

### Research findings

All from primary sources, read 2026-08-21, plus the pinned Android SDK sources
(`android-35`) and the pinned Flutter engine sources shipped with Flutter 3.44.7.

**Deferrable jobs are the only mechanism inside this scope.** Everything Android offers
for running without the user, and why each does or does not survive the exclusions:

| Mechanism | Needs from the user | Verdict |
|---|---|---|
| `JobScheduler` / `WorkManager` periodic job | nothing | **the only candidate** |
| Foreground service (`specialUse`, ADR-046 Layer 2) | battery-optimization exemption, notification permission, per-vendor setup | out of scope by definition; still unbuilt |
| `setExactAndAllowWhileIdle` | `SCHEDULE_EXACT_ALARM`, which the user can revoke | out of scope, and see below |
| `setAndAllowWhileIdle` | nothing | in scope, and rejected on evidence below |
| `BOOT_COMPLETED` receiver | nothing (normal permission) | not needed: `setPersisted(true)` does it |
| `MY_PACKAGE_REPLACED` receiver | nothing | rejected: deliverability not established, see *outstanding validation* |
| Sync adapter | a visible account | worse than a job in every respect, and Doze stops it too |
| Home-screen widget `updatePeriodMillis` | the user must place a widget | out of scope |
| Platform push (FCM) | nothing | excluded by ADR-013 and unreachable in the outage this deployment exists for |
| UnifiedPush / self-hosted distributor | a second app, a second service | out of scope here; ADR-046 rejected it and nothing has changed |
| SMS wake | a phone number and an SMS permission | rejected outright by ADR-046 on the threat model |

**What the job floor actually is.** `JobInfo.java` in the pinned API 35 SDK:
`MIN_PERIOD_MILLIS = 15 * 60 * 1000L`, and `setPeriodic` logs and silently raises anything
shorter. `MIN_FLEX_MILLIS = 5 * 60 * 1000L`, and flex is clamped to
`max(5% of the period, 5 minutes)`, so a 15-minute job is eligible in the last five
minutes of each period. `setPeriodic`'s own contract is an upper bound on frequency, not
a lower bound on delivery: "You have no control over when within this interval this job
will be executed, only the guarantee that it will be executed **at most** once within
this interval, as long as the constraints are satisfied."

**Doze suspends what a catch-up needs.** In Doze the system "suspends network access",
"ignores wake locks", "defers standard `AlarmManager` alarms" and "doesn't let
`JobScheduler` run. `WorkManager` uses `JobScheduler` internally, so `WorkManager` tasks
don't run", releasing them only in maintenance windows of which "over time … the system
schedules … less frequently"
([Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)).

**Two standby buckets have no background network at all, and an unopened app lands in
one.** The power table gives, per bucket: *active* — 20 min of jobs per rolling hour, no
network restriction; *working set* — 10 min per 4 h; *frequent* — 10 min per 12 h;
*rare* — 10 min per 24 h, **network disabled**; *restricted* — once per day for 10 min,
**network disabled**
([power details](https://developer.android.com/topic/performance/power/power-details)).
The same page notes that "execution quota behavior for jobs changed in Android 16. Prior
to Android 16 there was no execution limit when the app is in the active standby bucket",
which Android 16's own notes confirm reaches "tasks scheduled using WorkManager,
JobScheduler, and DownloadManager"
([Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-all)).
Decisively for this deployment: "On Android 13 (API level 33) and higher, unless your app
qualifies for an exemption, the system places your app in the restricted bucket … [when]
the user doesn't interact with your app for a specific number of days … Android 13
reduces the number of days to 8", and in that bucket "restricted jobs don't run by
themselves. There must be at least one other job running or pending at the same time"
([app standby buckets](https://developer.android.com/topic/performance/appstandby)).
The same page also records the counter-pressure this design gets for free: the system
does **not** treat an app as idle while "the app generates a notification that users see
on the lock screen or in the notification tray", and an app returns to *active* when
"the user taps on a notification that your app sends". A catch-up that finds a message
and alerts (ADR-048) is therefore self-reinforcing; a catch-up that finds nothing for
eight days is not, and that is the honest limit.

**While-idle alarms buy nothing here, and the two primary sources disagree about how
little.** The Doze page says "neither `setAndAllowWhileIdle()` nor
`setExactAndAllowWhileIdle()` can fire alarms more than once per nine minutes, per app".
The pinned SDK's own `AlarmManager.java` javadoc is less generous: "Under normal system
operation, it will not dispatch these alarms more than about every minute …; **when in
low-power idle modes this duration may be significantly longer, such as 15 minutes**",
and the dispatch grants only that "the app will also be added to the system's temporary
power exemption list for **approximately 10 seconds**". Ten seconds does not cover a
Keystore unwrap, a SQLCipher open, a TLS handshake to a private CA and a drain. Alarms
are also bucket-quota'd (one per hour in *rare*, one per day in *restricted*), do not
survive a reboot, and the javadoc restricts the API to cases "where it is actually
required that the alarm go off while in idle — a reasonable example would be … a calendar
notification". Rejected on all four counts, more firmly than ADR-046 rejected it.

**A job is the one thing that both runs and has a network.** `JobScheduler`'s own
javadoc: "While a job is running, the system holds a wakelock on behalf of your app", and
the network constraint means the job is not started until there is one. Its limits are
recorded honestly: from Android 12 "jobs will still be stopped after 10 minutes if the
system is busy or needs the resources"; from Android 14 the scheduler "may try to optimize
job execution by shifting execution to times with more available system resources", and
`onStartJob` that does not return "within several seconds" is an ANR; `JobService`
"executes each incoming job on a Handler running on your application's main thread".
`setPersisted(true)` carries `@RequiresPermission(RECEIVE_BOOT_COMPLETED)` and is what
loads the job at boot, so no receiver of this application's own is needed.

**A backgrounded process cannot hold anything.** Android 14: "an app's process is in a
cached state when it's moved to the background", and "shortly after an app process enters
a cached state, background work is disallowed". AOSP: "if all processes for a particular
app are frozen, the system terminates any active TCP sockets maintained by the app"
([cached apps freezer](https://source.android.com/docs/core/perf/cached-apps-freezer)).
This is why a catch-up opens no socket, and why an unacknowledged wake-up is not a slow
catch-up but an interrupted one.

**Force-stop is absolute.** An app the user force-stops, or that has never been launched
since install, receives no broadcasts and runs no scheduled work until it is launched
manually. No architecture changes this.

**Data Saver is a user setting this design cannot and will not work around.** With Data
Saver on and the device on a metered network, "the system blocks background data usage";
an app may ask for an allowlist exemption through
`ACTION_IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS`
([Data Saver](https://developer.android.com/training/basics/network-ops/data-saver)).
Asking is out of scope for this piece by definition, so it is disclosed instead.

**One process, one Dart VM — verified in source, not assumed.** The pinned Flutter engine
states in `dart_vm_lifecycle.h` that "there can only be one VM running in the process at
any given time", and `DartVMRef::Create` reuses a running one; `IsolateNameServer` is
owned by that `DartVM` and its Dart-side documentation says "all isolates share a global
mapping of names to ports". Two `FlutterEngine`s in one Android process therefore share
one VM and one name server — which is also why `drift_flutter`'s
`shareAcrossIsolates: true`, already used by this application, connects a headless isolate
to the *same* database server isolate rather than opening a second connection to the same
SQLCipher file.

**The headless entry point is a documented Flutter API.** `new FlutterEngine(context)`
registers generated plugins automatically (verified in `FlutterEngine.java`), and
`DartExecutor.executeDartEntrypoint(DartEntrypoint(bundlePath, functionName))` runs a
named top-level function. Plugins Flutter generates are registered; **channels this
application registers on its activity are not**, which is finding 1 above.

### Alternatives evaluated

**1 — Nothing; keep `UnscheduledBestEffortPolling` (the status quo).** Costs nothing,
leaks nothing, promises nothing, and is exactly what the disclosure said. Rejected as the
answer, because the question is what happens when the application is not open, and for a
private messenger with no push the difference between "never" and "usually within tens of
minutes" is the difference between usable and not.

**2 — Tell the user something arrived without draining it.** There is no such signal
without push, and inventing one would mean announcing something this device has not
authenticated. Rejected: it is the one thing ADR-046's Layer 3 principle forbids.

**3 — Do the catch-up in Kotlin.** Would avoid a second Dart context entirely. Rejected
outright: the drain, the envelope inspection, the ratchet, the group stack and the
projection are Dart over a reviewed Rust core, and a Kotlin reimplementation would be a
second, unreviewed copy of the security-critical path.

**4 — `androidx.work` (ADR-046 as written).** The documented recommendation, and it
handles reboot rescheduling itself. Rejected. At `minSdk` 24 WorkManager delegates to
`JobScheduler` anyway, and `setPersisted(true)` gives the reboot property directly. What
it would add is a Room database, a `SystemJobService`, a `RescheduleReceiver`, an
`androidx.startup` `InitializationProvider` and `RECEIVE_BOOT_COMPLETED` — merged
invisibly into the manifest of an artifact whose manifest is an audited surface — in
order to schedule one job. ADR-048 set the precedent for exactly this trade and the
evidence points the same way. The existing test forbidding the `workmanager` package
therefore stands unchanged and now records a decision rather than an absence.

**5 — The `workmanager` Flutter plugin.** Adds all of the above plus a plugin, a
`SharedPreferences`-held callback handle, and a generic background channel. Rejected for
the same reasons, more so.

**6 — A self-rescheduling one-shot job with `setMinimumLatency` and
`setOverrideDeadline`.** A deadline gets better treatment from the Android 14 shifting
behaviour. Rejected on two counts: `setOverrideDeadline` runs the job when the deadline
expires **even if its constraints are not met**, which means waking with no network; and a
chain that fails to reschedule itself once is a chain that is broken permanently, while a
periodic job is self-healing by construction.

**7 — While-idle alarms.** Rejected on the four grounds recorded under *Research*.

**8 — Keeping ADR-046's durable Drift delivery lease.** ADR-046 required "a durable
leased row in Drift with an owner identity and a heartbeat, not an in-memory flag, so a
crash releases it and a restart reclaims it". Re-examined against evidence and
**rejected**. Its stated advantage does not exist here: a crash of the process releases an
in-memory flag too, because the process is what held it, and there is no second process to
coordinate with — the job service is declared with no `android:process`, and one Dart VM
per process is the engine's own documented invariant. What it would cost is real: a
heartbeat writing to an encrypted database on a timer forever, and a stale lease after a
crash that blocks catch-up until it expires. What replaces it is more precise, not weaker
— see below.

**9 — Letting the two owners overlap and only protecting the token refresh.** Tempting,
because the refresh is the sharpest hazard. Rejected: `beginNextEnvelopeInspection`
deliberately selects rows in `received` *or* `inspecting` so a crashed inspection is
retried, which means two concurrent engines would hand the same envelope to the ratchet
twice; and the post-inbox composite runs group KeyPackage maintenance, pending eviction
and outbound dispatch, whose concurrency properties are not established. Exclusion covers
the whole cycle.

**10 — Killing an in-flight headless run when the user opens the application.** Equivalent
to process death for the durable engine, which it is built to survive. Rejected anyway:
the run may be inside an FFI call into the shared native cryptographic core, and abandoning
one is a worse trade than waiting the seconds a catch-up takes.

### Decision

**One persisted periodic `JobScheduler` job at the platform floor, delivered to whichever
Dart isolate already exists, and to a headless one only when none does.**

**The mechanism.** `JobInfo.Builder(JOB_ID, DeferredDeliveryJobService)` with
`setPeriodic(max(requested, JobInfo.getMinPeriodMillis()))`,
`setRequiredNetworkType(NETWORK_TYPE_ANY)` and `setPersisted(true)`. The floor is read
from the platform rather than repeated as a number. No dependency is added: `JobInfo` is
in the framework at `minSdk` 24. The service is a plain service — `exported="false"`,
`android:permission="android.permission.BIND_JOB_SERVICE"`, no `foregroundServiceType`,
no `android:process` — so the job scheduler is the only thing that can start it and
everything runs in the one process the ownership argument rests on.

**Arming belongs to the session, not to the lifecycle.** A `MessageDeliverySession` arms
the job once when it starts and disarms it when it stops; the supervisor no longer
schedules or cancels anything. This is the correction of finding 2: a periodic job
restarts its window each time it is registered.

**Exactly one delivery owner, arbitrated in the process rather than in the database.**
`onStartJob` runs on the application's main looper, and so does
`FlutterActivity.configureFlutterEngine`. `MainActivity` registers its engine's channel as
the delivery owner and clears it in `cleanUpFlutterEngine`. A tick therefore takes one of
three paths, decided on that one thread:

- a live activity engine exists → `runCatchUp` is invoked into that isolate, the
  supervisor runs one cycle, and the job finishes when the reply arrives. This is the
  common case: a cached process keeps its engine for as long as the system leaves it
  alone, and starting a second engine beside it is precisely the hazard;
- no engine exists → a headless `FlutterEngine` is created, this application's
  protected-storage, message-alert and delivery channels are attached to it, and the
  `backgroundDelivery` entry point runs;
- a headless run is already in flight → the tick is dropped.

For the one remaining race — the user opening the application while a headless run is in
flight — the foreground **waits**. `MessageDeliverySession.compose` calls
`awaitExclusiveOwnership()` before it opens storage or reads a token, and the platform
completes it when the headless run ends.

**A tick is acknowledged.** `BestEffortDeliveryTick.complete()` is what tells the platform
the wake-up may end, and it is called unconditionally — including when the cycle failed or
was refused for want of a network — because the scheduler is asking whether the process
may be let go, not whether delivery succeeded. The adapter applies its own two-minute
deadline so a stalled owner cannot hold the wake-up open until the platform's ten-minute
limit kills it mid-drain.

**The headless run holds nothing.** It opens **no socket**: a cached process is frozen and
its TCP sockets are terminated, so a connection is not a thing a bounded wake-up can own.
It restores the session, runs one `DurableSyncEngine.synchronize()` — the same engine, the
same store, the same inspector, the same group stack — reconciles the alert from committed
state, and stops. It runs the alert pass even when the drain failed, because an alert is a
projection of committed local state and messages committed by an earlier run may still
never have been announced.

**Both entry points compose through one `ApplicationRuntime`.** The provisioned
`SecurityContext`, the single `TokenCoordinator` and the environment-gated crypto core are
built in one constructor that `bootstrap()` and the headless entry point both call. The
dangerous background failure is not a crash; it is a quieter posture — the public root
store instead of the provisioned authority, a second coordinator, a crypto core without
the compiled environment's permit — and this removes the possibility rather than testing
for its absence.

**Which build a background run believes it is, is compiled in.** Each flavor's entry-point
file exports a `@pragma('vm:entry-point')` `backgroundDelivery()` that names its own
`AppEnvironment`. The platform picks a *name*; which environment that name resolves to is
decided by which file was compiled, so nothing about the provisioned server, the trust
anchor or the closed-beta group permit is selectable at runtime. A build asked for an
entry point it does not contain fails to start one, which is the fail-closed direction.

### Correctness questions, answered

- **What causes the work, and what stops it?** A periodic job armed when a device-bound
  full session starts. It stops on logout, when a headless run finds no session (it
  disarms itself), on force-stop, and on uninstall. It does not stop on a locked phone or
  a dropped connection, because neither says anything about the next attempt.
- **What may it assume?** Nothing. It reconstructs storage, configuration, trust, crypto
  and session for itself, in the same order and through the same constructor the activity
  uses.
- **What if protected state cannot be opened?** It concludes `storageUnavailable`: nothing
  read, nothing written, nothing announced, no marker spent, schedule untouched. The
  device being locked after a restart reaches here, and it can never be mistaken for
  "nothing was waiting" because it does not touch the mailbox at all.
- **What if another part of the application is doing the same job?** It cannot be. A live
  engine takes the tick itself; a headless run blocks a foreground session from composing
  until it finishes; a second job tick while one is in flight is dropped.
- **What if it is interrupted mid-way?** Identical to process death, which the durable
  engine is designed for: every write is a transaction, an abandoned drain leaves
  committed state consistent, and an envelope left `inspecting` is picked up again.
- **The very first time?** There is no session, so nothing is armed; enrollment arms it.
- **After force-stop?** Nothing, until the user opens the application. Disclosed, not
  engineered around.
- **How is failure surfaced?** It is not surfaced as an event at all. There is no
  background error state and no notification about failing to check — that would be noise
  the user cannot act on. What the user has is the alert when something *is* delivered,
  and one sentence in the enrollment disclosure telling them what not to rely on.
- **What does the application now claim?** Revision 3, in both catalogues.

### Security and privacy

- **What the new entry point can reach**: exactly what the activity reaches, because it
  composes from the same constructor — and nothing that needs a window. `FLAG_SECURE`,
  the clipboard, the permission dialog and the settings screen stay on `MainActivity` and
  are unreachable from a headless engine.
- **Transport trust cannot be silently absent.** One `ApplicationRuntime` builds the
  provisioned `SecurityContext`; the headless path contains no
  `TransportSecurity.platformDefault`, no second `NetworkingFoundation`, no second
  `TokenCoordinator` and no second `DioRestClient`, and an architecture test asserts each
  of those absences.
- **Credentials**: obtained by restoring the same device-bound session, refreshed through
  the same single-flight coordinator, invalidated the same way. Two coordinators are what
  this design exists to prevent, and the cost of failing was traced to its end: 401
  `invalid_token` from the backend, `_endsSession`, `store.clear()`, and a user signed out
  who did nothing.
- **Protected material** is opened only when the platform can unwrap it, which is after
  first unlock. The application is not direct-boot aware, so the platform itself withholds
  the job until then; the Dart path fails closed on top of that rather than relying on it.
- **What an untrusted server or a network attacker can cause.** Nothing new. The job's
  cadence is set by the platform, not by anything on the wire, so a hostile relay cannot
  increase how often this device wakes; it can only make each drain find nothing. Envelope
  flooding costs battery, not correctness, and the existing backoff and circuit-breaker
  paths bound it. Nothing that fails authentication reaches `messages`, so nothing a
  server sends can produce an alert.
- **What it writes or leaves behind**: one job record in the platform's own scheduler
  store, containing an id, an interval and a component name. Nothing else. No log line,
  no file, no preference. The Kotlin half contains no `Log.` and no `println`, asserted by
  test.
- **New metadata, stated plainly.** A device that catches up in the background makes its
  online periods visible to the server on a roughly-fifteen-minute cadence whether or not
  its owner is present. The server is already an untrusted relay that sees every drain, so
  this creates no new party and no new class of observation — but it does make an idle
  device look like an active one, and that is a real change from an artifact that only
  ever spoke while its owner was looking at it.
- **Truthfulness of what is declared to the platform.** The one service is what it says it
  is: a job service, bound with `BIND_JOB_SERVICE`, showing no notification, holding no
  connection, claiming no foreground-service type. `RECEIVE_BOOT_COMPLETED` is declared
  because `setPersisted(true)` requires it and for no other purpose; no receiver is
  declared. Nothing here describes work as something it is not in order to obtain
  behaviour the platform would otherwise withhold.

### Reliability, stated honestly

**Guaranteed — these are guaranteed *restrictions*, and no test run can disprove them:**
a force-stopped application runs nothing; the periodic floor is fifteen minutes and a
shorter request is silently raised; the *rare* and *restricted* buckets disable background
network; Android 13+ places an app in *restricted* after eight days without interaction
unless exempt; a cached process is frozen and its TCP sockets terminated; a job is stopped
after ten minutes when the system wants the resources; `setPeriodic` promises *at most*
one run per interval, never at least one.

**Merely permitted — a green run proves nothing:** that a job runs at any particular
moment; that a maintenance window arrives promptly; that a vendor's build honours the
schedule at all; that a cached process survives long enough for its engine to take the
tick; that `setPersisted` work is restored across an application upgrade.

**What was observed here:** nothing about timing. No device or emulator run was possible
(see *Outstanding validation*), so every timing statement above is documentation, not
measurement.

| Condition | Tier | What actually happens |
|---|---|---|
| Foreground, network up | **Near-real-time** (seconds) | Socket hint → REST drain → commit → alert if the conversation is not on screen |
| Backgrounded, process alive, *active*/*working set* bucket | **Eventual, minutes** | The job wakes the existing isolate; fifteen minutes at best, and only if Doze is not deferring it |
| Backgrounded, process gone | **Eventual, minutes** | A headless engine is started for one drain; same cadence, higher cost per run |
| Device in Doze | **Eventual, hours** | Jobs run only in maintenance windows, which the system schedules less frequently the longer the device is idle |
| Not opened for eight days (Android 13+) | **None** | *Restricted* bucket: background network disabled, one batched job a day that will not run alone |
| Data Saver on, metered network | **None** | Background data blocked; asking for the exemption is out of scope for this piece |
| Force-stopped, or battery usage set to "Restricted" | **None** | Unfixable by any design |
| After a reboot, before first unlock | **None, safely** | Not direct-boot aware, and the database key is credential-encrypted; the job is restored and waits |
| After a reboot, after first unlock | **Best-effort** | `setPersisted(true)` restored the job with no receiver of this application's own |
| Intermittent connectivity | **Eventual, no loss inside 7 days** | The network constraint holds the job until there is one; seven-day server retention; `pruned_through` turns permanent loss into a visible blocking state rather than silence |

### Failure modes

- **The platform refuses to schedule.** Caught; delivery reverts to foreground-only, which
  is what the artifact already tells its users can happen.
- **No implementation behind the channel** (a host test, a future Web build). The port
  resolves to `UnscheduledBestEffortPolling` and says so; nothing pretends to be armed.
- **The owner never acknowledges a tick.** The adapter answers after two minutes, and the
  platform's own ten-minute limit is behind that.
- **A headless run hangs.** The platform side tears the engine down after four minutes,
  which is equivalent to process death and leaves committed state consistent.
- **The platform stops the job** (`onStopJob`: constraints no longer met, quota, the
  system wanting the resources). Whatever is in flight is released — the headless engine
  is destroyed, or a tick handed to the foreground is settled — and `false` is returned so
  the job is rescheduled by its own periodic policy rather than backed off. Nothing
  inconsistent is left behind, because every durable write is a transaction.
- **The user opens the application mid-run.** The session waits, bounded by that same
  deadline. If the platform stops answering the ownership question altogether, the wait
  fails after five minutes and the session composes nothing rather than proceeding as
  though it had established that it is the only owner.
- **A run finds no session.** It disarms the job, so a signed-out device is not woken
  every interval to rediscover it.
- **A run cannot open storage.** It concludes nothing and leaves the job armed.
- **Logout while a job is armed.** The session disarms it; if that call fails, the next
  headless run disarms it instead.
- **An upgrade cancels the job.** Not established either way (see below); the next launch
  re-arms it.

### User requirements

**None.** No permission the user can refuse, no exemption to grant, no vendor setting to
change, no second application to install. The two permissions in the manifest that this
piece touches are `RECEIVE_BOOT_COMPLETED` (normal, install-time, no prompt) and, from
ADR-048, `POST_NOTIFICATIONS` — which gates being *told*, not being *delivered to*: a
catch-up with notifications refused still drains, commits and marks unread.

What the user can nevertheless do that silently disables it, all disclosed:

1. Force-stop the application, or set its battery usage to "Restricted".
2. Not open it for eight days on Android 13+, which moves it to the *restricted* bucket.
3. Turn on Data Saver and stay on a metered network.
4. A vendor's own battery manager doing any of the above on the user's behalf, which on
   this fleet is the likeliest of the four and the one nothing in this repository can
   detect.

### Beta and production

Suitable for both, now, subject to the device matrix below for any *claim* about timing.
It adds no dependency, introduces no cryptographic surface, crosses no production gate,
and leaves the Beta/Production separation exactly as ADR-042 and ADR-044 left it —
verified after the change against the built artifact: the production release packages
unsigned, carries the production application ID, and exports no beta MLS symbol.

It changes what the artifact says about itself. ADR-045's `DisclosurePoint` is renamed
`bestEffortDelivery`, its text is rewritten in both catalogues, and
`DeploymentDisclosure.revision` moves 2 → 3. Per ADR-045's mechanism that makes every
later enrollment re-acknowledge, and **re-delivering the written handover disclosure to
existing recipients is release-blocking** — a requirement that was already outstanding
from ADR-048 and is now outstanding at a higher revision.

### Known limitations

- **Eventual is the ceiling.** Nothing in this piece can produce near-real-time background
  delivery; that is ADR-046's Layer 2 and it is deliberately out of scope here.
- **An application nobody opens for eight days stops receiving anything in the
  background**, and the user most likely to be caught by that is the one who has not been
  messaged recently — which is exactly the person an urgent message would be for.
- **The OEM half is unmeasured**, and 77% of the target fleet is Samsung or Xiaomi.
- **A live-engine tick depends on the process still being cached.** How long that lasts is
  the system's decision and varies by device and memory pressure.
- **Battery and data cost are real but small**: one wake-up per interval at best, holding
  a wakelock for the seconds a drain takes, over a connection that must already exist for
  the job to start.

### Outstanding validation

None of the following could be established here, and none may be inferred from the passing
checks:

1. **That the job runs at all on a device.** No physical device was available, and the
   installed emulator images are Play-Store images without root; reaching a signed-in
   session on this workstation is additionally blocked by server-side account activation.
   Everything about timing in this record is documentation, not observation.
2. **That a headless `FlutterEngine` starts the `backgroundDelivery` entry point in the
   release AOT snapshot.** What *is* established: the entry-point name, both channel names
   and `runDeferredDeliveryEntryPoint` all survive tree-shaking into the shipped
   `libapp.so`. That the platform can then look the function up and run it needs a device.
3. **Whether a persisted job survives an in-place application upgrade.** Not specified by
   the platform documentation that could be found, and therefore not assumed. Mitigated by
   re-arming on every session start. `ACTION_MY_PACKAGE_REPLACED` was **not** used: the
   background-execution-limits exemption list does not name it, and the page's note about
   package broadcasts not being exempt names `ACTION_PACKAGE_REPLACED` rather than the
   targeted variant, so its deliverability to a manifest receiver on a modern release is
   undocumented either way.
4. **The device matrix**: Doze, standby-bucket transitions, the eight-day restricted-bucket
   move, reboot, force-stop, Data Saver, and vendor battery managers, on Samsung and Xiaomi
   hardware and an AOSP image across Android 11 to 16. Release-blocking for any *claim*
   about timeliness; not release-blocking for shipping the mechanism, which cannot make
   anything worse than the absence it replaces.

### Follow-up work

1. **Re-deliver the written handover disclosure** at revision 3 to existing recipients.
   Release-blocking, and inherited from ADR-048.
2. **The device matrix** above.
3. **ADR-046's Layer 2** (`specialUse` foreground service, opt-in, off by default) remains
   the only route to near-real-time background delivery and remains unbuilt. Nothing here
   forecloses it: it would hold the same connection, drive the same engine, and reuse the
   ownership arbitration this decision introduces.
4. **Group messages still produce no alert**, because the piece-18 group projection sets no
   unread state (ADR-048). A background catch-up that drains a group message therefore
   commits it silently.

### Review and revisit conditions

Reopen when any of the following becomes true:

1. **The platform changes the job floor, the standby-bucket network rules, the eight-day
   restricted-bucket rule, or the freezer.** Every tier above rests on those four.
2. **Layer 2 ships.** The ownership arbitration then has a third owner to consider, and a
   foreground service changes which bucket the application sits in.
3. **The device matrix shows the job does not run on Samsung or Xiaomi even unconfigured.**
   Then this floor is not a floor for this fleet, and the honest answer is to say so rather
   than to keep the mechanism as reassurance.
4. **The application ever needs a second process.** The whole ownership argument is that
   there is one, and an `android:process` attribute anywhere would invalidate it. An
   architecture test fails if one appears.
5. **The backend grows a push endpoint**, which reopens ADR-046 alternative 6 and would
   make this floor much less load-bearing.
6. **The deployment stops being 20–30 known people receiving a written handover.** The
   disclosure this decision rewrote is calibrated to a reader who was handed the artifact
   in person.

This decision implements ADR-046's Layer 1, replaces its `WorkManager` mechanism and its
durable delivery lease for the reasons recorded above, amends ADR-045's delivery
disclosure to revision 3, reaffirms ADR-013 and ADR-043, adds no dependency, changes no
cryptographic behaviour, and opens no production gate.

## ADR-048 in full — how the user finds out a message arrived (2026-08-21)

### The question

A message has been drained, authenticated, decrypted and committed to this device's
database. The user is not looking at that conversation. **How do they find out — once,
correctly, and without being told anything untrue?**

ADR-046 answered the surrounding question, "how does a backgrounded client learn an
envelope is waiting", and sketched an answer to this one in three sentences of its
Layer 3. ADR-047 built its Layer 0. This decision is the piece in between: the one that
turns a committed row into something a person notices. Nothing was assumed — not the
presentation mechanism, not the trigger point, not the marker, not the dependency, and
not ADR-046's own sketch.

### What the repository actually did before

Verified in the composed application on 2026-08-21, not in its documentation:

| Component | Existed | Reachable at runtime |
|---|---|---|
| Delivery path (socket, engine, drain, commit) | yes | **yes**, since ADR-047 |
| `messages.unread` written inside the inbox transaction | yes | yes |
| `conversations.unread_count`, `muted_until` | yes | yes |
| Any notification port, adapter, channel or dependency | **no** | no |
| Any record of which conversation is on screen | **no** | no |

So the delivery half was real and the alert half did not exist in any form. Two further
findings came out of that inspection and are recorded here because they change what could
honestly be built:

1. **A message that arrives while its conversation is on screen is still marked unread.**
   `ChatConversationView` marks a conversation read exactly once, from a post-frame
   callback in `initState`. Nothing re-marks it while the route stays mounted. So
   `messages.unread` alone cannot answer "is the user looking at this", and an alert path
   that assumed it could would announce messages the user was watching arrive.
2. **Inbound group messages set no unread state at all.**
   `DriftGroupRepository.commitMessageInsideTransaction` inserts into `messages` without
   `unread` and updates `conversations` without `unread_count`, so a group message leaves
   no unread trace anywhere. This is a pre-existing gap in the piece-18 group projection,
   not in this one; its consequence for this decision is stated under *Known limitations*
   and it is deliberately **not** fixed here, because `GroupChatPage` also never marks a
   group read, so setting the flag would produce a badge nothing could clear.

### Research findings

All read at primary source on 2026-08-21, against `minSdk` 24 / `targetSdk` 36 /
`compileSdk` 36 as pinned by Flutter 3.44.7.

**Notifications need a runtime permission that can be refused, and refused permanently.**
`POST_NOTIFICATIONS` arrived in Android 13 (API 33); "if a user installs your app on a
device that runs Android 13 or higher, your app's notifications are off by default", and
on refusal "your app can't send notifications unless it qualifies for an exemption. All
notification channels are blocked"
([notification permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)).
An app targeting 33+ "has complete control over when the permission dialog is displayed" —
and that control is finite: "if the user taps Deny for a specific permission more than once
during your app's lifetime of installation on a device, the user will no longer see the
system permissions dialog if your app requests that permission again. The user's action
implies 'don't ask again,' and is considered a permanent denial"
([requesting permissions](https://developer.android.com/training/permissions/requesting)).
`shouldShowRequestPermissionRationale` is false both *before* the first request and *after*
the permanent denial, so the platform cannot distinguish those two states for the
application.

**Every notification needs a channel, and its behaviour is the user's after the first
post.** Channels are mandatory from Android 8.0 (API 26): "if you target Android 8.0 (API
level 26) or higher and post a notification without specifying a notification channel, the
notification doesn't appear and the system logs an error". "After you create a notification
channel, you can't change the notification behaviors. The user has complete control at that
point. However, you can still change a channel's name and description"
([channels](https://developer.android.com/develop/ui/views/notifications/channels)).
The platform source for `NotificationChannel` in the API 35 SDK confirms the constructor
defaults this decision relies on: `mSound = Settings.System.DEFAULT_NOTIFICATION_URI`,
`mVibrationEnabled = false`, `mLights = false`, `mShowBadge = true`, and
`mLockscreenVisibility = VISIBILITY_NO_OVERRIDE` — so a per-notification visibility is what
actually applies. `enableVibration(boolean)` carries no `@RequiresPermission` annotation.

**What a lock screen shows is the application's choice.** `setVisibility()` takes
`VISIBILITY_PUBLIC` ("the notification's full content shows on the lock screen"),
`VISIBILITY_PRIVATE` ("only basic information, such as the notification's icon and the
content title") or `VISIBILITY_SECRET` ("no part of the notification shows on the lock
screen")
([create a notification](https://developer.android.com/develop/ui/views/notifications/build-notification)).
Android 15 adds a second consumer of the same mechanism: "notification content is hidden
during screen sharing sessions to preserve the user's privacy. If the app implements
`setPublicVersion()`, Android shows the public version of the notification which serves as
a replacement notification in insecure contexts. Otherwise, the notification content is
redacted without any further context"
([Android 15 behavior changes](https://developer.android.com/about/versions/15/behavior-changes-all)).

**Tapping must go through a `PendingIntent`, and it must be immutable.** "Apps that target
Android 12 or higher can't start activities from services or broadcast receivers that are
used as notification trampolines", and "if your app targets Android 12, you must specify the
mutability of each `PendingIntent` object that your app creates"
([Android 12 behavior changes](https://developer.android.com/about/versions/12/behavior-changes-12)).

**More than one notification is a shade full of them.** "If your app sends four or more
notifications and doesn't specify a group, the system automatically groups them on Android
7.0 and higher", and grouping requires the app to build and maintain a summary
notification; "you always need to manually set a summary to enable grouped notifications"
([grouped notifications](https://developer.android.com/develop/ui/views/notifications/group)).
Conversation notifications go further still: "**MessagingStyle**: … Your notifications must
be created with this style to use Android's conversation features", together with long-lived
share shortcuts
([conversations](https://developer.android.com/social-and-messaging/guides/communication/notifications-conversations)).
The per-package notification cap is not a documented API — `NotificationManagerService`
carries a constant near 50, OEMs vary it, and there is no way to query it — so a design
whose count grows with traffic is a design whose behaviour is unspecified. Android also
rate-limits: updates posted many times in less than a second may be dropped, and from
Android 8.1 an app "cannot make a notification sound more than once per second".

**Android 16 introduces nothing here.** Its all-apps behaviour changes cover JobScheduler
quota, broadcasts, ART, 16 KB pages, accessibility announcements, navigation, themed icons,
intent redirection and Bluetooth; none of them touches posting, channels, ranking or the
permission
([Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-all)).

**The dependency question answers itself.** `flutter_local_notifications` 22.3.0 (pub.dev,
read 2026-08-21) is current, requires Flutter 3.38.1 or newer, needs no Firebase and no
Play services — it would work. But `NotificationCompat`, `NotificationManagerCompat`,
`NotificationChannelCompat` and `ActivityCompat` all live in `androidx.core:core`, which
this build **already declares at 1.16.0** for `FileProvider`, and `MainActivity` already
owns two method channels. Every API this decision needs is therefore already on the
classpath.

### Alternatives evaluated

**Presentation.**

**1 — Nothing; rely on the unread badge (the status quo).** Costs no permission, leaks
nothing, needs no platform code. Rejected: it answers "how does a user who opens the app
find out" and the question is about a user who does not.

**2 — An in-app banner only.** Correct and free while the app is foregrounded, and worth
having later. Rejected as the answer, because it says nothing to a user who has switched to
another app, which is most of the window in which delivery still works.

**3 — One notification per message, bounded, plus a group summary.** This is the shape
ADR-046 sketched. Rejected on the evidence above. With a sender-neutral preview, N
notifications are N copies of one sentence, so the only thing they add over one
notification is a per-message identifier visible to the system notification service and to
any application the user has granted notification access. They also drag in summary
management, automatic-grouping differences across OEMs, and an unspecified per-package cap.

**4 — One notification per conversation, with `MessagingStyle` and conversation
shortcuts.** The mainstream messenger design, and the one Android optimises for. Rejected
squarely on the threat model. It requires a stable per-conversation notification id and a
long-lived share shortcut, which publish a pseudonymous per-contact identifier into
`system_server` and the launcher, where they persist and can be correlated over time by
anything holding notification access. `MessagingStyle` exists to show senders and message
text. The threat model names "a person with filesystem access to a locked but otherwise
uncompromised Android device" as an adversary and lists "notification previews" among
protected assets; this option trades directly against both, and buys a per-conversation tap
target that a sender-neutral alert cannot use anyway.

**5 — One aggregate notification, sender-neutral, tapping to the launcher. Selected.**
One id, one tag, one channel, one sentence. See below.

**6 — Full previews (sender and message text) by default.** Rejected. It is the single
change that would most improve the experience and it is the wrong default for a deployment
of 20–30 people in Iran, where a name on a lock screen implicates two people rather than
one. Not shipped even as an opt-in in this piece: the switch is small, but the reviewed
bilingual warning around it is not, and adding a way for a user to make themselves less
safe is not a good use of the first notification release. Recorded as follow-up.

**Trigger.**

**7 — Emit from `PostInboxCommitWorkPort`, as ADR-046 specified.** It is a real
post-commit hook and it would work for the announce case. Rejected as the whole answer:
it fires only when the sync engine runs, so it cannot *withdraw*. A user who opens the app
and reads a conversation, or who reads it on another device, leaves the alert standing in
the shade until the next drain. Every question this piece has to answer that is not
"announce" — read elsewhere, withdrawn by its sender, conversation opened, mute applied —
is a change to committed state that no post-drain hook observes.

**8 — Reconcile from a durable-state signal. Selected.** Drift buffers table updates
inside a transaction and dispatches them to the parent stream store only after `COMMIT`
(`Transaction.complete()` runs before `disposeChildStreams()`, verified in the pinned
drift 2.34.2 source), so a stream over `messages` and `conversations` is a strictly
post-commit trigger. This preserves ADR-046's actual principle — an alert is a projection
of committed local state and never of a transport event — more directly than the hook did,
and it makes withdrawal fall out of the same rule as announcement.

**Marker.**

**9 — `notified_at` timestamp, per ADR-046.** Rejected in favour of a boolean
`messages.alerted`. Nothing in the design reads the time, a timestamp would be one more
wall-clock value to reason about under skew, and a column nothing reads is a column that
will eventually be read for the wrong reason.

**Dependency.**

**10 — `flutter_local_notifications` 22.3.0.** Rejected: it would add a maintained
dependency, a plugin registration, and a second scheduling/timezone surface, to reach APIs
already on the classpath through `androidx.core:core:1.16.0`. ADR-046 step 8 stated the
preference for app-owned Kotlin behind a port for exactly this surface, and the evidence
supports it. No dependency is added by this decision.

### Decision

**The user is told by one system notification that says only that something arrived, and
that notification is a reconciliation of committed local state rather than an event.**

**One alert.** A single notification, fixed id and tag, in one channel whose id
(`"messages"`) is frozen for the life of the installation because it keys the user's own
sound and importance settings. Its entire content is `New message` or `New messages` —
grammatical number and nothing else. No sender, no conversation, no text, no count, no
timestamp (`setShowWhen(false)`). It is `VISIBILITY_PRIVATE` and supplies a
`setPublicVersion` carrying the same sentence, so a lock screen and a screen-sharing
session show exactly what the application chose rather than whatever the system's own
redaction produces.

**Tapping carries nothing.** The content intent is the launcher intent obtained from
`getLaunchIntentForPackage`, wrapped `FLAG_IMMUTABLE`, with `setAutoCancel(true)`. There is
no destination, no extra, and no identifier — so there is nothing to validate, nothing to
forge, and no path that could bypass the routing guards that already stand between an entry
point and content. Tapping opens the application exactly as its icon does, and the guards
decide what may be shown.

**A reconciliation, not an emission.** Each pass reads the committed rows that are unread,
not deleted for this device, not withdrawn by their sender, and not in Saved Messages;
subtracts the muted conversations and the conversation currently on screen; and brings the
shade into agreement with what is left. Announce when something un-alerted survives that
subtraction, withdraw when nothing survives it at all. Every hard case falls out of that
one rule instead of needing its own.

**Idempotence is durable.** `messages.alerted` (schema 12) is spent in the same pass that
posts. It survives a projection rebuild because the projector writes messages through
`insertOnConflictUpdate` with a companion that omits the column — drift documents that
"columns from the old row that are not present on [entity] are unchanged" — the same
mechanism that already preserves `starred`. It is written *after* a successful post, never
before: a crash in between costs one repeated alert on the same notification id, while the
opposite order costs a message the user is never told about.

**Deliberate silence still spends the marker.** A message suppressed because its
conversation is muted or on screen is marked alerted without being announced. Without that,
leaving the conversation or outliving the mute would produce a late alert for something the
user has already seen or has asked not to hear about.

**What could not be delivered is not spent.** When the platform refuses — no permission, no
implementation, a failed post — no marker is spent, so granting permission later announces
the backlog instead of losing it.

**"On screen" is a conjunction.** `VisibleConversationRegistry` reports a conversation only
when its route is mounted *and* the application is in the foreground. A chat route left
mounted behind a backgrounded application is not something anyone is looking at. An
unreported lifecycle state at launch is read as foreground, for the same reason ADR-047
gave: Flutter leaves `lifecycleState` null until the first platform message, and the
opposite reading would silence every alert until one arrives.

**One automatic prompt, at the point of use, guarded twice.** The permission is requested
the first time a message is waiting that cannot be announced, and only while the
application is foregrounded, because the prompt belongs to an activity the user is looking
at. It is guarded by a durable marker in `local_preferences` — which stops it repeating on
every launch — and by Android's own `shouldShowRequestPermissionRationale`, which is true
in exactly one situation, the user has refused once and not yet twice. Honouring the second
guard means an automatic prompt can never be the refusal that makes the denial permanent,
and it means a refusal the user made from Settings is respected even though Settings writes
no marker of its own.

**Settings states the truth and offers one action.** The row reads the operating system,
not the application's beliefs, and shows three states: on, off, or not available in this
build. When off, one button asks Android, and falls through to this application's own
notification settings screen when asking changed nothing — so one tap always ends somewhere
the user can act, and never on a button that silently does nothing.

**The platform side holds no policy.** `MainActivity` gains one method channel that reports
what Android says, posts the sentence Dart hands it, withdraws it, and opens the settings
screen. Nothing identifying a conversation, a sender or a message crosses it. Every
decision is Dart, so every decision is covered by host tests.

### What is guaranteed and what is merely permitted

**Guaranteed, and testing cannot disprove it:** a refused `POST_NOTIFICATIONS` blocks every
non-exempt channel; a second refusal is permanent and the application can no longer prompt;
a channel's importance cannot be changed after creation; a notification posted without a
channel on API 26+ does not appear; sound is capped at once per second from Android 8.1.

**Merely permitted, and a green test run is evidence of nothing:** that a heads-up appears
on a given vendor's build; that vibration occurs; that the notification survives however
long the user leaves it; that a vector drawable renders identically as a status-bar icon
across the fleet; that the per-package cap is where AOSP puts it.

**And the tier this piece actually delivers:** an alert reaches the user only while the
application's process is alive. ADR-046's Layers 1 and 2 remain unbuilt, this build still
composes `UnscheduledBestEffortPolling`, and nothing re-arms after Android stops the app.
That is a real limit and it is now what the enrollment disclosure says.

### Failure modes

- **Permission refused, or revoked after being granted.** Nothing is announced, no marker
  is spent, and Settings says so plainly. Granting later announces the backlog.
- **A crash between posting and marking.** The same notification id is re-posted on the
  next pass, so the user sees one notification and may hear one extra sound. Chosen over
  the alternative, which loses the message silently.
- **A burst of arrivals.** Passes are serialized behind a dirty flag and a pass spends every
  marker it read, so a wave of commits collapses into one alert. Verified at 25 messages in
  one transaction.
- **A backlog larger than one read page.** The read is ordered so unspent markers come
  first, so consecutive passes drain it rather than returning the same page. Because there
  is only ever one notification, those extra passes update it rather than adding to a pile.
- **Storage unavailable.** The pass concludes nothing: nothing posted, nothing withdrawn,
  no marker spent, so the next pass reaches the same conclusion.
- **No platform implementation.** Resolves to *unavailable*; nothing is posted and the
  Settings row says so, rather than a screen failing.
- **A hostile relay floods envelopes.** Nothing that fails authentication reaches
  `messages`, so nothing it sends can produce an alert. What it can do is cause repeated
  bounded drains, which is the cost ADR-046 already accepted.
- **A stale alert from a previous process.** The first pass of a session assumes one may be
  posted and withdraws it when nothing is outstanding, which is what covers a message read
  on another device while this one was not running.

### Security and privacy

- **On an unlocked device, a bystander sees** the application name and `New messages`.
  **On a locked one, the same**, by declaration rather than by the system's redaction.
  **During screen sharing on Android 15+, the same again**, through `setPublicVersion`.
- **To an application holding notification access**: the package name, that same sentence,
  one constant id and one constant tag. No conversation, no sender, no count, no timing
  beyond the moment of posting, and nothing that can be correlated per contact.
- **New metadata created on the device**: one boolean per message row inside the existing
  SQLCipher database, and one preference key recording that the permission prompt was
  shown. Both are erased with the database by the existing wipe paths. Nothing is written
  outside it, and `allowBackup="false"` is unchanged.
- **Logs**: nothing is logged. The channel carries a localized sentence and nothing derived
  from content, identifiers or keys.
- **Forgery and suppression by a server or a network attacker**: an alert can only be
  produced by a row that survived authenticated decryption and a durable commit, so a relay
  cannot cause one. It can suppress by withholding envelopes, which it could already do.
- **Credentials and keys**: no component gains access to anything it did not hold. The
  platform side receives strings.
- **The safe posture is the only posture.** There is no preview setting to get wrong, and
  the one user action available — turning notifications on — increases what the device
  shows only by the sentence above.
- **Permissions added**: `POST_NOTIFICATIONS` (dangerous, runtime, requested at point of
  use) and `VIBRATE` (normal, granted at install, no prompt). No foreground service, no
  boot receiver, no exact alarm, no SMS. The architecture test that forbids
  `remoteMessaging` and `FOREGROUND_SERVICE_DATA_SYNC` is untouched and a new one forbids
  every foreground-service and boot permission outright while ADR-046's layers stay
  unbuilt.

### User requirements

One, and it is unavoidable: on Android 13 and above the user must allow notifications.
They are asked once, automatically, at the moment a message is waiting that cannot be
announced, and never again automatically. Everything after that is theirs: Settings offers
the action whenever they want it, and the channel's sound, vibration and importance are
theirs to change from the moment it first appears. There is no vendor setup to explain,
because this piece starts no service and schedules no work.

### Beta and production

Suitable for both, now. It introduces no cryptographic surface, crosses no production gate,
adds no dependency, and leaves the Beta/Production separation exactly as ADR-042 and
ADR-044 left it — verified after the change: the production release still packages
unsigned, still carries the production application ID, and still contains no beta MLS
symbol.

It does change what the artifact says about itself. ADR-045's
`DisclosurePoint.foregroundDeliveryOnly` read "Messages arrive only while this app is open.
There are no notifications and nothing runs in the background", and the second clause is now
false. `DeploymentDisclosure.revision` moves 1 → 2, the text is rewritten to say that
messages arrive and the application can alert only while it is running and that nothing
re-arms once Android stops it, and both language catalogues move with it. Per ADR-045's
mechanism, that makes every later enrollment re-acknowledge, and **re-delivering the
written handover disclosure to existing recipients is release-blocking**.

### Known limitations

- **Nothing reaches a user whose application Android has stopped.** This is ADR-046's
  Layers 1 and 2, and they are still unbuilt.
- **Group messages produce no alert**, because the piece-18 group projection sets no unread
  state (see *What the repository actually did before*). The alert path needs no change when
  that is fixed; the group projection and `GroupChatPage` do.
- **A message that arrives while its conversation is on screen stays unread** after the user
  leaves it. That is the pre-existing mark-read behaviour, unchanged here; this decision only
  makes sure it is never announced.
- **No preview option**, so a user cannot tell which conversation an alert is about without
  opening the application.
- **The Kotlin half is unmeasured.** No device or emulator run was possible: the available
  images are Play-Store images without root, and reaching a signed-in session on this
  workstation is blocked by server-side account activation. What the notification looks like,
  whether the vector icon renders correctly in the status bar, whether the channel vibrates,
  and how the permission dialog behaves are all **unverified on a device**.
- **A refusal made from Settings is not recorded durably**, so in one sequence — turn on
  from Settings, refuse — the automatic prompt may still be spent later. Android's rationale
  flag prevents that in the common case; the residue is at most one extra dialog, ever.

### Follow-up work

1. **Device matrix for this piece**: Android 13 first-install prompt, refusal, second
   refusal, revocation after grant, lock-screen rendering, heads-up, status-bar icon,
   channel settings, and the Persian rendering of both strings — on Samsung, Xiaomi and an
   AOSP image across Android 11 to 16. Release-blocking for any claim about what the user
   sees.
2. **Re-deliver the written handover disclosure** to existing recipients — still not done,
   and now outstanding at revision 3, which ADR-049 moved it to.
3. **Group unread state** in the piece-18 projection, plus mark-read in `GroupChatPage`;
   the alert path then covers groups with no change.
4. **Mark-read while a conversation is on screen**, which also makes read receipts correct.
5. **An in-app presentation** for the foregrounded case, so an alert does not appear over
   the application that produced it.
6. **A preview setting**, if and only if the reviewed bilingual lock-screen warning is
   written first.

### Review and revisit conditions

Reopen when any of the following becomes true:

1. ~~**ADR-046's Layer 1 or Layer 2 ships.**~~ **Layer 1 shipped 2026-08-21 — ADR-049**,
   and this prediction held exactly: the alert path needed no change, because a headless
   run supplies a `VisibleConversationPort` reporting the truth — nothing on screen, not
   in the foreground — and the existing `visible.isForeground` guard is therefore what
   keeps the single automatic prompt from being spent into a context with no activity.
   What did *not* hold is the prerequisite: ADR-049 replaced the durable delivery lease
   with in-process arbitration on evidence. Layer 2 shipping still reopens this.
2. **The deployment stops being 20–30 known people receiving a written handover.** The
   sender-neutral default is calibrated to a threat model where a name on a lock screen
   implicates two people; a different population may weigh that differently.
3. **Voice ships.** A microphone foreground service posts its own notification, and the
   interaction between the two must be decided rather than discovered.
4. **Android changes the permission model, the channel contract, or lock-screen
   redaction.** Every claim above about what a bystander sees rests on `setVisibility`,
   `setPublicVersion` and channel-level user control.
5. **The device matrix contradicts anything in "merely permitted".**

This decision implements ADR-046's step 2 and amends its Layer 3 sketch — one aggregate
alert instead of bounded individual notifications plus a summary, a durable-state
reconciliation instead of a post-inbox-commit emission, and a boolean marker instead of a
timestamp — for the reasons recorded above. It amends ADR-045's
`DisclosurePoint.foregroundDeliveryOnly` and moves the disclosure to revision 2. It adds no
dependency, changes no cryptographic behaviour, opens no production gate, and leaves the
Beta/Production boundary untouched.

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

1. **Compose the delivery path** (Layer 0). ~~Until this lands, nothing else in this ADR
   can be observed to work, and neither sending nor receiving functions at all. Includes
   resolving the two composition roots: `NetworkingFoundation` is currently dead code
   while `AuthenticationAssembly` builds the live client, and the socket must attach to
   the live one.~~ **Done 2026-08-21 — ADR-047.** The two roots are resolved into one
   and the socket attaches to the live coordinator. One correction to the inventory
   above: `NetworkingFoundation` was not "tested and constructed only in tests" — it had
   no tests and no callers at all.
2. ~~**Notification port, `notified_at` column, post-inbox-commit notifier,
   `POST_NOTIFICATIONS` request at point of use.** Useful on its own, before any
   background layer exists.~~ **Done 2026-08-21 — ADR-048**, with three of this
   line amended on evidence: one aggregate alert rather than bounded individual
   notifications plus a grouped summary; a reconciliation driven by committed
   durable state rather than an emission from `PostInboxCommitWorkPort`, which
   can announce but never withdraw; and a boolean `messages.alerted` rather than
   a `notified_at` timestamp nothing reads. The `POST_NOTIFICATIONS` request is
   at point of use and spent at most once automatically.
3. ~~**WorkManager adapter behind `AndroidPollingScheduler`** (Layer 1), with the headless
   entry point reconstructing its own dependencies and failing closed before first unlock.~~
   **Done 2026-08-21 — ADR-049**, with the mechanism amended on evidence: a persisted
   periodic `JobScheduler` job rather than `WorkManager`, because `JobInfo` is in the
   framework at `minSdk` 24 and `setPersisted(true)` survives a reboot, so the dependency
   would only have added a Room database, a service and a boot receiver to an audited
   manifest. Arming also moved off the lifecycle and onto the session, because registering
   a periodic job restarts its window. The headless entry point does reconstruct its own
   dependencies and does fail closed before first unlock, as required here.
4. ~~**Durable delivery lease**, with a test that runs two owners against one store.~~
   **Replaced 2026-08-21 — ADR-049.** The lease was specified for a hazard that is real
   and a topology that is not: the job service is declared with no `android:process`, and
   the Flutter engine documents one Dart VM per process, so every owner this design can
   produce is on one main looper. Ownership is arbitrated there instead — a tick goes to
   the isolate that already exists, a headless engine starts only when none does, and a
   foreground session waits for a headless run rather than racing it. The two-owner test
   this line asked for exists as a composition test that holds ownership and asserts that
   nothing authenticated happens until it is released. **Corrected 2026-08-22 — ADR-050.**
   That test proves less than this sentence claims: its harness replaces the real
   `TokenCoordinator` with a fake session, so "nothing authenticated happens" was true of
   the delivery session and untrue of the application, which rotates the shared refresh
   token during session restoration well before a session composes. The two-owner test
   this line originally asked for now exists as
   `test/features/networking/delivery_owner_contention_test.dart`: two real isolates, one
   real shared SQLCipher store, both orderings, repeated contention, and a contender
   killed mid-rotation. The conclusion that a lease was specified for a topology that does
   not exist is unchanged and was re-derived independently.
5. **`specialUse` foreground service, boot receiver, background-delivery setting, and the
   setup screen** (Layer 2), off by default.
6. **Disclosure revision.** Shipping any of steps 2 to 5 makes ADR-045's original
   `DisclosurePoint.foregroundDeliveryOnly` false. `DeploymentDisclosure.revision` must
   move, the text must be rewritten to the tier language above, and the written handover
   must be re-delivered to existing recipients. **Moved twice: 2026-08-21 — ADR-048**
   took it to revision 2 when alerts shipped, and **ADR-049** took it to revision 3 when
   background catch-up did, renaming the point `bestEffortDelivery`. Re-delivering the
   written handover to existing recipients has **not** happened and is release-blocking
   at revision 3.
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
