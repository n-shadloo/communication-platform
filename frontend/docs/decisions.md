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
| ADR-029 | Accepted | Android background messaging uses best-effort polling, not a persistent service | Matches the client contract and avoids false delivery guarantees; active voice remains foreground. |
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

- Product name, logo, and final Android application ID remain placeholders.
- Direct signed APK distribution is the initial release channel. Self-hosted Web
  distribution is post-v1 and requires a later approved release decision.
- Django Admin remains the administration surface; a client admin feature is out of
  scope.
