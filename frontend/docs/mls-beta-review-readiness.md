# Closed-beta PQ MLS independent-review packet

## Review status

This packet prepares the closed-beta PQ MLS track of implementation piece 19 for
independent cryptographic and application-security review. **It is not a review report,
it records no assessment, and it claims no approval.** No reviewer is retained, named, or
implied anywhere in this document, and none of the seven production gates in
[the MLS profile](mls-profile.md) is satisfied or partially satisfied by anything here.

Nothing in this packet may be cited as evidence that a gate is closed. Assembling review
material is not review, and passing every check listed below would still leave all seven
gates open. Gates 1, 2, and 3 cannot be moved by any work in this repository at all, and
gate 7 additionally needs a party outside it. The MLS profile's Phase-A preflight tracks
five external prerequisites; all five are blocked.

The normative construction is [the post-quantum MLS profile](mls-profile.md), together
with ADR-036, ADR-037, ADR-039, ADR-040, and ADR-041 in
[the decision register](decisions.md). Reviewers should treat code, vectors, and this
packet as subordinate to those documents and report any divergence as a blocking
interoperability/security defect.

### The one thing to read first

**The closed beta does not implement `TBD2` and no beta artifact ever has.** Its
signature, AEAD, KDF, and hash choices match `draft-ietf-mls-pq-ciphersuites-06`'s `TBD2`
exactly; its hybrid KEM does not, in ten recorded ways, the widest of which is an HPKE
`kem_id` of `0x000F` — unassigned at IANA — reaching every key schedule. The complete
binding record is "Closed-beta KEM divergence from TBD2" in
[the MLS profile](mls-profile.md), rows D1-D10. ADR-040 resolves that the KEM is not
changed.

A reviewer who reads this packet as `TBD2` conformance material will reach wrong
conclusions. Beta groups are a hybrid ML-KEM-768 + X25519 MLS deployment on Private Use
identifier `0xFE4C`, and are not `TBD2` interoperability evidence.

## Source baseline

### Repository revision

| | |
|---|---|
| Revision under review | `4e65eaf4f0e4a017a42b48b49a444570f47cbffb` |
| Branch | `frontend` |
| Committed | 2026-08-18T09:13:59-04:00 |
| Working tree at verification | clean; `git diff --check` clean; `git diff --name-only -- ../backend` empty |
| Packet verified against that revision on | 2026-08-18 |

The beta track is the following commits, oldest first. A reviewer auditing incrementally
should read them in this order, because the last five are defect fixes whose commit
messages carry reasoning that is not repeated in the code.

| Commit | Date | Subject |
|---|---|---|
| `c016bd2` | 2026-08-02 | `feat(groups)`: gated group domain and UI (piece 18, crypto-independent) |
| `91ba0f8` | 2026-08-17 | `feat(groups)`: closed-beta PQ MLS implementation |
| `57e13bc` | 2026-08-17 | `test(mlkem)`: anchor ML-KEM-768 in NIST ACVP vectors |
| `9294080` | 2026-08-17 | `test(mls-beta)`: anchor suite primitives in official vectors |
| `2f53170` | 2026-08-17 | `docs(mls-beta)`: record ADR-040 and the full KEM divergence |
| `ff67529` | 2026-08-17 | `docs(upstream)`: `mls-rs` hybrid KEM defect report |
| `dfde3ee` | 2026-08-17 | `test(mls-beta)`: pin the hybrid KEM in project vectors |
| `b41ad48` | 2026-08-17 | `fix(groups)`: remove the grindable fork tie-break (ADR-041) |
| `fe346c3` | 2026-08-18 | `fix(groups)`: recover a queue gap through re-admission |
| `d40e720` | 2026-08-18 | `fix(mls-beta)`: reject disposable pre-v3 group state |
| `2233c44` | 2026-08-18 | `fix(mls-beta)`: reject non-canonical MLS objects |
| `4e65eaf` | 2026-08-18 | `fix(groups)`: route a beta group object to every recipient |

### Toolchain

| | Pinned value | Where |
|---|---|---|
| Rust | `1.97.1` stable, profile `minimal`, components `clippy`/`rustfmt` | `rust-toolchain.toml` |
| Rust edition | 2024, `rust-version = "1.97.1"` | `native/crypto_core/Cargo.toml` |
| Android targets | `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android` | `rust-toolchain.toml` |
| Flutter | 3.44.7 stable | `pubspec.yaml`, verified with `flutter --version` |
| Dart | 3.12.2 (`>=3.12.2 <3.13.0`) | `pubspec.yaml`, verified with `flutter --version` |

The stable pin is itself a review-relevant constraint: `cargo-fuzz`, libFuzzer, AFL++,
ASan, and Miri all need nightly, so no sanitizer or coverage-guided instrumentation backs
any claim in this packet. See "Explicitly out of scope" and "The vectors that do not and
cannot exist".

### Locked cryptographic dependencies

Read from `native/crypto_core/Cargo.toml` (exact `=` pins) and confirmed in
`native/crypto_core/Cargo.lock` on 2026-08-18. Every row whose "Reached by" is
`beta-pq-mls` sits behind that non-default Cargo feature and is absent from the production
build; `mls-rs-crypto-hpke` and `mls-rs-identity-x509` are transitive under it and are
likewise absent.

| Crate | Locked version | Reached by | Role |
|---|---|---|---|
| `mls-rs` | 0.55.2 | `beta-pq-mls` | MLS protocol engine |
| `mls-rs-core` | 0.27.0 | `beta-pq-mls` | credential, identity, storage traits |
| `mls-rs-codec` | 0.7.0 | `beta-pq-mls` | MLS presentation encoding |
| `mls-rs-crypto-awslc` | 0.25.0 | `beta-pq-mls` | cipher suite provider |
| `mls-rs-crypto-traits` | 0.22.0 | `beta-pq-mls` | KEM/DH/hash trait surface |
| `mls-rs-crypto-hpke` | 0.21.0 | transitive | HPKE and the divergent hybrid KEM combiner |
| `mls-rs-identity-x509` | 0.21.0 | transitive | unused by this profile; present in the lock |
| `aws-lc-sys` | 0.40.0 | `beta-pq-mls` | AWS-LC primitives, `bindgen` feature |
| `ed25519-dalek` | 3.0.0 | always | control-event signatures, foundation vectors |
| `x25519-dalek` | 3.0.0 | always | pairwise transport; KEM vector reproduction |
| `chacha20poly1305` | 0.11.0 | always | XChaCha20-Poly1305 state sealing |
| `sha2` | 0.11.0 | always | SHA-256/384; KEM vector reproduction |
| `hkdf` | 0.13.0 | always | HKDF; KEM vector reproduction |
| `hmac` | 0.13.0 | always | direct pin so zeroization unifies into `hkdf` |
| `minicbor` | 2.3.0 | always | canonical CBOR credential/control encoding |
| `libsodium-sys-stable` | 1.24.0 | always | secretstream |
| `argon2` | 0.5.3 | always | recovery KDF |
| `zeroize` | 1.9.0 | always | secret lifetime |
| `subtle` | 2.6.1 | always | constant-time comparison |
| `getrandom` | 0.4.3 | always | CSPRNG |
| `serde_json` | 1.0.149 | always | checked-in vector fixtures only |
| `hex-literal` | 1.1.0 | dev only | vector transcription |

`mls-rs-crypto-hpke 0.21.0`, `mls-rs-crypto-awslc 0.25.0`, and `mls-rs-crypto-traits
0.22.0` were each the newest published version of their crate when checked on crates.io on
2026-08-17. `mls-rs 0.55.3` (2026-08-07) supersedes the locked `0.55.2` but ships the same
crypto crates; moving that lock is a separate reviewed dependency decision and no gate
requires it.

Two vendored C sources are compiled by `build.rs` rather than resolved by cargo:
`native/crypto_core/vendor/mlkem-native` and `native/crypto_core/vendor/libsodium`. The
ML-KEM-768 lineage matters for the differential test — see "Differential coverage and its
limits" in `native/crypto_core/vectors/README.md`, which records that `aws-lc-sys 0.40.0`
also vendors mlkem-native, so the two builds are *not* independent implementations.

### External primary sources and verification dates

These are the dates recorded by the work that produced them, restated here so a reviewer
can see the age of each claim at a glance. This packet re-read the recorded evidence; it
did not re-query the external registries.

| Source | Verified | Recorded in |
|---|---|---|
| IANA MLS Cipher Suites registry (suite value; still no PQ suite) | 2026-08-17 | [MLS profile](mls-profile.md) |
| IANA HPKE KEM/KDF/AEAD registries (`0x647A`, `0x0002`, `0x0002`) | 2026-08-17 | [MLS profile](mls-profile.md) |
| IANA TLS SignatureScheme registry (`ed25519` `0x0807`) | 2026-08-16 | [MLS profile](mls-profile.md) |
| `draft-ietf-mls-pq-ciphersuites-06`, `draft-ietf-hpke-pq-05`, `draft-irtf-cfrg-concrete-hybrid-kems-04`, `draft-connolly-cfrg-xwing-kem-06`/`-10` | 2026-08-17 | [MLS profile](mls-profile.md) |
| Pinned `mls-rs` crate sources read line by line for rows D1-D10 | 2026-08-17 | [MLS profile](mls-profile.md), `docs/upstream/mls-rs-hybrid-kem-defect-report.md` |
| OpenMLS supported-suite list; crates.io indexes | 2026-08-17 | [MLS profile](mls-profile.md) |
| MLS WG interoperability-vector repository (classical fixtures only) | 2026-08-17 | [MLS profile](mls-profile.md) |
| NIST ACVP ML-KEM-768 fixture, tag `v1.1.0.41` | 2026-08-17 | `native/crypto_core/vectors/README.md` |
| RFC 8032 / FIPS 180-4 / FIPS 202 / RFC 4231 / CAVP AES-GCM / RFC 5869 / RFC 7748 transcriptions | 2026-08-17 | `native/crypto_core/vectors/README.md` |
| Project hybrid-KEM vectors produced | 2026-08-17 | `native/crypto_core/vectors/README.md` |
| Closed-beta input-fuzzing campaign | 2026-08-18 | [MLS profile](mls-profile.md), `native/crypto_core/fuzz/README.md` |
| Crash and transaction-failure injection matrix (device-local half) | 2026-08-18 | [MLS profile](mls-profile.md) |

A reviewer should re-verify the registry and draft rows independently. The HPKE KEM row is
the one with a known short shelf life: `0x647A`'s recorded reference is
`draft-connolly-cfrg-xwing-kem-06`, the document is now at `-10`, and `-10` expires
2026-09-03.

### Beta protocol constants

Every constant a reviewer must hold in mind while reading the code, with its source
location in `native/crypto_core/src/mls_beta.rs` unless stated otherwise.

| Constant | Value | Meaning |
|---|---|---|
| `BETA_CIPHERSUITE` | `mls-rs` `CipherSuite::ML_KEM_768_X25519` | the provider's own hybrid suite |
| `BETA_CIPHERSUITE_ID` | `0xFE4C` | RFC 9420 Private Use; never a production value |
| `BETA_STATE_FORMAT_VERSION` | 1 | beta state format generation |
| `CREDENTIAL_PROTOCOL_VERSION` | 1 | `BasicCredential` identifier version |
| beta group transport | magic `CPGTO001`, version `3`, kinds 1/2/3 | `native_beta_group_mls.dart`; ADR-037's "transport v3" |
| `OPERATION_REQUEST_MAGIC` / `OPERATION_RESPONSE_MAGIC` / `OPERATION_VERSION` | `CPMLR001` / `CPMLO001` / 1 | FFI request and response framing |
| `SEALED_STATE_MAGIC` / `SEALED_STATE_VERSION` | `CPMLSE01` / 2 | XChaCha20-Poly1305 outer seal; version 1 still readable, rewritten as 2 |
| `GROUP_STATE_ENVELOPE_MAGIC` / `_VERSION` | `CPMLSG01` / 1 | group state plus authentication proof set |
| `BETA_STATE_MAGIC` | `CPMLSV01` | pre-v3 bare group state; now rejected on import |
| `KEY_PACKAGE_WRAPPER_MAGIC` / `_VERSION` | `CPMKPV01` / 2 | published KeyPackage wrapper |
| `KEY_PACKAGE_STORE_MAGIC` / `_VERSION` | `CPMLSK01` / 2 | persisted KeyPackage store |
| `STATE_BINDING_MAGIC` | `CPMLSB01` | device-signing-key state binding |
| `GROUP_CONTROL_PAYLOAD_MAGIC` | `CPGCV001` | signed control payload |
| control signature / state domains | `chat:v1:group-control`, `chat:v1:group-control-state` | domain separation |
| state-wrap KDF domain | `chat:v1:beta-pq-mls-state-wrap` | HKDF-SHA-256 info |
| group exporter label | `chat:v1:beta-group-export` | exporter confirmation |
| `MLS_MAX_IO_BYTES` | 1,048,576 | ABI input and output ceiling; mirrored in `beta_mls_ffi.dart` |
| `KEY_PACKAGE_BUCKETS` | `[4096, 16384]` | backend padding buckets |
| `MAX_STORED_KEY_PACKAGES` | 101 | persisted KeyPackage store bound; matches Dart's `maximumConsumablePool` of 100 plus one last-resort |
| `MAX_RETAINED_EPOCHS` | 8 | retained prior epochs |
| `MAX_GROUP_AUTHENTICATION_PROOFS` | 50 | persisted bundle proofs per group |
| control transcript cap | 512 entries | `group_model.dart`, `native_beta_group_mls.dart` |
| local schema version | 11 | `local_database.dart` |

## Security claims in scope

These are the properties the implementation intends to hold. They are claims for the
assessor to attack, not findings.

**Credential and identity**

- Every MLS `BasicCredential` resolves to a device the client Authentication Service
  already verified; an unknown, substituted, or duplicate credential cannot join, commit,
  or be trusted as a roster entry.
- The MLS signing key *is* the enrolled device signing key. No parallel MLS identity is
  generated, and a `SigningIdentity` whose signature key differs from the authenticated
  device's is rejected.
- The credential identifier is canonical CBOR over version, user ID, device ID, and the
  SHA-256 of the exact canonical device bundle, and decoding rejects any trailing byte or
  wrong-length field.

**Group control**

- Every product-visible membership, role, policy, and metadata change is carried by a
  signed control event; the deterministic projection a peer applies is the one the signer
  signed.
- A later member reconstructs the full product roster from the bounded authenticated
  control transcript and compares it against the Rust-returned credential roster before
  any state is committed.
- The transcript fails closed on absence, disagreement, replay, authorization failure,
  malformed credentials, or more than 512 entries.
- Same-revision forks converge identically on every device, from data every branch already
  carries, with no server order and no extra round trip.
- The fork ordering key cannot be varied by the branch author in any position that decides
  a real conflict.
- A departing member cannot evict itself; the eviction that removes its leaf is a separate
  owner-committed `Remove`, and a `left` member remains a valid eviction target because it
  still holds the epoch secret.
- A queue-gapped group accepts no control that claims to extend it; recovery is an
  authenticated re-admission that replaces the projection, roster, and transcript rather
  than continuing them.

**Objects on the wire**

- Every relay-reachable MLS object is refused unless it re-serializes to the exact bytes
  received, so one logical object cannot be presented under multiple encodings or
  identities.
- A published KeyPackage fits the backend's 4,096/16,384-byte buckets exactly, including
  last-resort behaviour, and an off-bucket or miscounted response is rejected.

**Persistence**

- New opaque MLS state, the accepted control or application fact, the membership and
  conversation projections, and the exact prepared outbound object commit atomically under
  a control revision and hash compare-and-swap; the object reaches the network only
  afterwards.
- A crash between commit and fan-out leaves the object pending and the retry reuses the
  exact persisted ciphertext rather than stepping any ratchet a second time.
- Sealed group and KeyPackage state is XChaCha20-Poly1305 sealed under a key derived from
  the device identity secret, bound to the device signing key, and typed by kind; a
  mismatched kind, identifier, suite, version, or any tampered or truncated byte fails
  closed.
- Pre-v3 bare group state is rejected explicitly rather than reinterpreted, because the
  newer layout would otherwise parse it as a proof set that happens to be empty.

**Transport**

- One group object becomes one pairwise operation per recipient user, each independently
  sealed by [pairwise transport v1](pairwise-transport-v1.md), so identical MLS ciphertext
  never appears to the relay across a sender's recipient set. That transport is itself
  awaiting independent review under its own packet; this claim inherits its open findings.
- A fan-out failure for one recipient neither strands nor duplicates another's durable
  ciphertext.

**Boundary**

- Dart orchestrates and never implements a primitive; the entire beta MLS surface is one
  bounded C ABI operation.
- The beta operation exists only in the isolated `beta` native profile, under a separate
  Android application ID, reached only from `lib/main_beta.dart`.
- Production resolves the unsupported adapter through a source-only gate whose constructor
  assertion prevents an accidental true value from compiling, and has no KeyPackage
  maintenance path at all.
- No error value, `Debug` implementation, or log carries plaintext, keys, ciphertext,
  tokens, or stable identifiers.

## Explicitly out of scope

The following are **not** claimed, and a finding that merely restates one of them is
already recorded here rather than new.

- **`TBD2` conformance or interoperability.** See rows D1-D10. The beta is a different
  construction and must never be offered as `TBD2` evidence.
- **Any production gate.** All seven remain open. Gates 1, 2, and 3 cannot be advanced by
  any work in this repository, and gate 7 needs a party outside it.
- **Interoperability with any other MLS implementation.** No independent implementation
  speaks `0xFE4C` with this KEM.
- **Post-quantum authentication.** The signature is Ed25519 throughout; the guarantee is
  post-quantum *confidentiality* only.
- **Memory-safety instrumentation.** No sanitizer, no Miri, no coverage-guided fuzzing.
  The crate is safe Rust outside its FFI shims, but nothing enforces that
  dynamically.
- **The physical-device half of the crash matrix.** `SIGKILL` mid-`fsync`, Android
  low-memory and Doze kills, force-stop, power cut, SQLCipher torn writes, and Keystore
  availability after reboot have not been exercised. No device matrix has been run.
- **The packaged Rust core under the crash matrix.** Those tests drive the development
  in-memory MLS port, not the native beta core.
- **State-format *migration* fuzzing.** Input-boundary fuzzing is done; driving state
  written by one released format version into a later reader is not.
- **The pairwise transport itself.** It has its own packet:
  [Pairwise v1 independent-review packet](pairwise-review-readiness.md). Its decoders are
  outside the beta operation and are not covered by the beta fuzz harness.
- **Application-message and attachment decoders.** Same reason.
- **Traffic analysis, social-graph hiding, and fan-out metadata.** Live server root sees
  which authenticated connection writes to which device queues. See
  [the threat model](threat-model.md).
- **Device compromise while it can decrypt**, rollback of the entire encrypted database to
  a prior internally consistent snapshot, and availability against a refusing server.
- **Web/Wasm.** Post-v1; crypto-dependent Web behaviour is fail-closed.
- **SHAKE-128 seed expansion.** Pinned but not independently reproduced; no dependency
  exposes SHAKE and ADR-040 declines project-local `unsafe` FFI to reach it.
- **HKDF-SHA-384 expansion known answers.** Recomputed from RFC 5869 §2.3 over an
  RFC 4231-pinned HMAC rather than compared to published output.

## Implementation inventory for review

Line counts are from the revision under review. This is the complete surface; nothing outside
it is beta MLS code.

### Rust core — `native/crypto_core/`

| Path | Lines | What to look for |
|---|---|---|
| `src/mls_beta.rs` | 5,363 | the whole engine: suite assembly, authentication context, 13 operations, control encode/decode, storage traits, sealing, KeyPackage wrapping. **Contains no `unsafe`.** |
| `src/mls_beta/fuzz.rs` | 818 | campaign driver, detectors, negative controls |
| `src/mls_beta/fuzz/targets.rs` | 573 | the 12 fuzz targets |
| `src/mls_beta/fuzz/fixture.rs` | 418 | genuine two-device group built by the engine itself |
| `src/mls_beta/fuzz/corpus.rs` | 279 | structure-aware mutation, reproducible from a seed |
| `src/mls_beta/fuzz/allocation.rs` | 128 | counting allocator behind the allocation ceilings |
| `src/beta_kem_vectors.rs` | 1,080 | project hybrid-KEM vectors and their non-AWS-LC reproduction |
| `src/beta_suite_vectors.rs` | 600 | official vectors for every non-ML-KEM suite primitive |
| `src/mlkem_vectors.rs` | 567 | NIST ACVP fixture; four extra AWS-LC differential tests under the feature |
| `src/lib.rs` | 776 | the C ABI and all 46 of its `unsafe {}` blocks; the beta entry is at `lib.rs:541-566` |
| `include/communication_crypto.h` | — | beta declaration at `:147-154`, marked as beta-profile-only |
| `Cargo.toml` / `Cargo.lock` | — | the `beta-pq-mls` feature gate and every pin above |
| `vectors/` | — | five fixtures plus a 371-line README that states per test what is and is not proven |
| `fuzz/README.md` | 80 | why the harness is in-crate, how to run and reproduce |

`unsafe` inventory for the crate, counted as `unsafe {` blocks at this revision: `lib.rs`
46 (the shared C ABI), `provider.rs` 14 (libsodium and mlkem-native FFI), `mlkem_vectors.rs`
10 and the fuzz modules 7 (both test-only, `#[cfg(test)]`), `mls_beta.rs` **0**. The beta
engine adds no `unsafe` of its own; it inherits `lib.rs`'s. Every block must carry a local
size and lifetime argument.

Error values must remain payload-free. No `Debug` implementation may expose opaque state,
plaintext, keys, ciphertext, tokens, or stable identifiers; the four hand-written ones in
`mls_beta.rs` are at `:266`, `:510`, `:2487`, and `:2628`.

### Dart client — `lib/`

| Path | Lines | What to look for |
|---|---|---|
| `features/groups/domain/group_model.dart` | 1,704 | control operations, precedence classes, authorization, fork ordering (`GroupForkCanonicalOrder`, `:1390-1481`), transcript cap |
| `features/groups/infrastructure/native_beta_group_mls.dart` | 2,017 | transport v3 encode/decode, transcript verification, commit-hash binding, native request framing |
| `features/groups/infrastructure/drift_group_repository.dart` | 980 | the compare-and-swap commit boundary (`:166-313`), re-admission (`:326`), quarantine, pending outbound |
| `features/groups/application/group_mls_admission_service.dart` | 538 | create/join/control preparation and live-member verification |
| `features/groups/application/group_use_cases.dart` | 548 | authorized mutation entry points |
| `features/groups/application/group_mls_inbound_coordinator.dart` | 332 | probe, welcome/control/application dispatch, queue-gap rejoin admission |
| `features/groups/application/group_key_package_maintenance_service.dart` | 246 | bucket and last-resort lifecycle |
| `features/groups/application/group_outbound_dispatcher.dart` | 117 | per-recipient fan-out and the routed marker |
| `features/groups/application/group_pending_eviction_service.dart` | 99 | phase 2 of leave |
| `features/groups/infrastructure/drift_group_key_package_maintenance_store.dart` | 404 | durable KeyPackage bookkeeping |
| `features/groups/domain/group_key_package_model.dart` | 291 | bucket validation (`:276`) |
| `features/groups/presentation/group_pages.dart` | 1,552 | gate page, and every screen that must refuse to render outside beta |
| `features/groups/infrastructure/unsupported_group_mls.dart` | 84 | the production adapter; must fail closed on all nine port methods |
| `features/groups/infrastructure/development_in_memory_group_mls.dart` | 256 | non-production preview; must be unreachable in release |
| `shared/infrastructure/crypto/native/beta_mls_ffi.dart` | 85 | the only `dart:ffi` allocation on this path — 1 MiB buffers, zeroed and freed in `finally` |
| `shared/infrastructure/crypto/native/beta_mls_native_session.dart` | 569 | typed request/response codecs over the ABI |
| `shared/infrastructure/crypto/native/verified_bundle_request.dart` | 86 | the authenticated bundle claims handed to Rust |
| `shared/infrastructure/crypto/native/isolate_crypto_core_worker.dart` | 2,346 | isolate ownership of the native session |
| `shared/infrastructure/crypto/crypto_core_runtime.dart` | 1,654 | capability resolution and lifecycle |
| `core/application/ports/beta_mls_crypto_port.dart` | 53 | the narrow port |
| `app/config/group_production_gate.dart` | 31 | the source-only gate and its constructor assertion |
| `app/dependencies/group_providers.dart` | 208 | which adapter each environment resolves |
| `features/pairwise/application/pairwise_fanout_coordinator.dart` | 424 | where the group object becomes per-recipient pairwise operations |
| `features/pairwise/infrastructure/drift_pairwise_transport_store.dart` | 1,629 | the durable outbox the group leg shares |
| `features/synchronization/infrastructure/pairwise_opaque_envelope_inspector.dart` | 871 | inbound routing into the group coordinator, including the deferred queue-gap path |
| `features/synchronization/infrastructure/drift_sync_store.dart` | 1,386 | the enclosing inbound transaction |
| `features/local_storage/infrastructure/database/local_database.dart` | 1,394 | schema 11; `mls_groups`, `group_control_events`, `group_outbound_objects` at `:335-420` |

The group feature is 22 files and 9,779 lines in total.

### Packaging and isolation

| Path | What to look for |
|---|---|
| `tool/build_rust_android.sh` | the export allowlist (`:170-181`), 16-KiB load alignment check, and the assertion that no dynamic libsodium dependency leaks |
| `tool/build_rust_android.ps1` | the Windows wrapper; `-CryptoProfile foundation\|beta` |
| `tool/build_libsodium_android.sh` | the dual-name archive workaround for the MSVC-host cross-build |
| `android/app/build.gradle.kts` | three flavors; `beta` gets `applicationId` suffix `.beta` and its own `jniLibs` source set (`:98-119`) |
| `lib/main_beta.dart` | the only entry point that selects `AppEnvironment.beta` |

The isolation is enforced at the symbol level: the `foundation` profile (development and
production flavors) allowlists **15** exported symbols and the `beta` profile allowlists
**16**, the difference being exactly `cp_crypto_v1_beta_mls_operation`. Both profiles were
rebuilt at this revision on 2026-08-18 and checked with `llvm-nm -D --defined-only` on all
three ABIs; on `arm64-v8a`, `armeabi-v7a`, and `x86_64` alike the sorted symbol lists
differ by that one line and nothing else.

The artifact-level form of that check is stronger and is the one a reviewer should insist
on, because it inspects what would actually ship rather than an intermediate build output.
The native libraries extracted from the built **production release APK** carry exactly the
15-symbol foundation allowlist on every ABI, contain zero `beta_mls` symbols, and are
byte-identical to the freshly built foundation artifacts. A production build therefore
contains no beta PQ MLS code path at all — not a disabled one, not a dead one.

### Documents the reviewer must read alongside the code

| Document | Why |
|---|---|
| [Post-quantum MLS profile](mls-profile.md) | normative; owns the suite decision, rows D1-D10, the seven gates, the Phase-A preflight, the fuzz and fault-injection records |
| [Architecture decisions](decisions.md) | ADR-036, ADR-037, ADR-039, ADR-040, ADR-041 in full, plus superseded ADR-038 |
| [Pairwise transport version 1](pairwise-transport-v1.md) | the transport every group object rides |
| [Pairwise independent-review packet](pairwise-review-readiness.md) | the adjacent packet whose open findings this one inherits |
| [Threat model](threat-model.md) | adversaries, trust boundaries, residual metadata |
| [Local data model](local-data-model.md) | the MLS transaction boundary this implementation claims to honour |
| [Message protocol](message-protocol.md) | the group transport framing and the pre-v3 rejection requirement |
| [Testing strategy](testing-strategy.md) | what layer each check belongs to and which are recorded as outstanding |
| `native/crypto_core/vectors/README.md` | per-fixture provenance and the per-test proves/does-not-prove table |
| `native/crypto_core/fuzz/README.md` | harness design, knobs, and reproduction |
| `docs/upstream/mls-rs-hybrid-kem-defect-report.md` | the five upstream defects behind the divergence, prepared but **not filed**; useful as an independent restatement of rows D1-D10 with per-finding `main`-branch evidence |
| `backend/CLIENT_CONTRACT.md`, `backend/SECURITY.md` | binding server-side guarantees; read-only from here |

## The project's own protocol inventions

RFC 9420 leaves several things to the deployment, and this project fills those gaps with
mechanisms of its own design. **These are the highest-value review targets in the packet**,
because no external specification or vector can validate them and no other implementation
has ever exercised them. A reviewer who only checks the project's use of MLS will miss all
ten.

### 1. Credential binding to the client Authentication Service

RFC 9420 does not say what a `BasicCredential` means. Here it means: canonical CBOR over
`[version=1, user_id(16), device_id(16), SHA-256(canonical device bundle)]`, and the only
credentials that resolve are those in an `AuthenticatedDeviceIdentityProvider` built from
device bundles the client already verified through its own enrollment and cross-signing
chain (ADR-027).

What binds:

- `BetaMlsAuthenticationContext::from_verified_bundle_requests` re-derives the expected
  canonical bundle from the opaque device state and refuses if it, the cross-signature, or
  the signing key differs, and refuses an all-zero cross-signature outright.
- The MLS signer is the enrolled Ed25519 device key, reassembled into AWS-LC's 64-byte
  `seed || public` form. No second identity exists.
- `resolve` checks that the `SigningIdentity`'s signature key equals the authenticated
  device's, so a credential identifier alone is not enough.
- Historical bundles reach the provider only through `with_key_package_proofs`,
  `with_local_key_package_proof`, and `with_persisted_group_proofs`, each of which requires
  an *active* device with a matching signature key, refuses a conflicting re-insert, and —
  for the persisted case — requires the local credential to still be present.

Review questions: can a rotated bundle ever admit a signature key the active device does
not hold? Can the 50-proof cap be reached in a way that drops a proof a later verification
needs? Does bundle-hash-in-credential mean a routine seven-day prekey rotation changes
every member's credential identifier, and if so, what reconciles the old and new
identities inside one group?

### 2. The control transcript and later-member admission (ADR-037)

A member added at epoch *n* has no way to authenticate the product roster from the current
`Invite` alone. Transport v3 therefore carries the bounded authenticated transcript of
every prior control event: for each entry, the deterministic projection, the exact signed
payload, and the signer's Authentication Service proof. The joiner replays it from the
initial state, joins the Welcome, and compares the Rust-returned `BasicCredential` roster
against the reconstructed product roster before one atomic commit. Existing members verify
the same transcript.

Bounds and failure modes: cap 512 entries, enforced independently in four places
(`group_model.dart:1062`, `native_beta_group_mls.dart:1075`, `:1106`, `:1518`); fails
closed on absence, disagreement, replay, authorization failure, or malformed credentials;
a transcript count is rejected outright unless the object also carries a Commit
(`native_beta_group_mls.dart:1518`), and a prepared transition that carries a preceding
transcript may not also be outbound (`group_model.dart:1063`).

[The message protocol](message-protocol.md) records the project's own position on the
bound: at 512 entries a long-running group needs "a reviewed checkpoint format before that
bound can be raised". No such format exists, so a group that reaches the cap becomes
unjoinable by design.

Review questions: is the reconstructed roster a *function* of the transcript, or can two
different transcripts project to the same roster with different authority? Is the
unjoinable-at-513 behaviour genuinely closed, and can a hostile member drive an honest
group toward the cap cheaply? Can a relay truncate a transcript to a prefix that is
internally consistent but omits a demotion?

### 3. Fork convergence (ADR-041, superseding ADR-038)

There is no delivery service to serialize commits, so the canonical branch is chosen on
the client. Siblings are authenticated, replayed against the reconstructed shared parent,
and authorized before they can influence the outcome; the superseded branch is
fork-quarantined and rejoins by remove/re-add, because an applied MLS commit cannot be
rewound.

The ordering key is a four-part tuple, smallest first: operation precedence class
(`eviction` < `authority` < `membership` < `descriptive`), then the signer's role **in the
reconstructed shared parent**, then the authenticated signer user and device ID, then the
control state hash. `branchOf` returns null — failing closed — when the signer is not an
active member of the shared parent.

This replaced a hash-only tie-break that the branch author could grind: the descriptor's
16-byte event ID is free entropy, `created_ms` is an unvalidated `u64`, and Ed25519 is
deterministic, so one trial was one signature plus one hash. Measured on the shipped
signing path: about 24,500 candidate branches per second per core, 9 trials to land below
a known rival. A member facing eviction could displace its own `Remove` for well under a
millisecond of work. The standing evidence is the Rust test
`an_author_grinds_the_control_state_hash_below_a_known_rival`, which reproduces the shipped
hash byte for byte, grinds, and re-signs the winner through the real operation entry point.

Review questions: is the precedence class always derivable from a permission the author
must already hold, with no operation that can be authored in a higher class than its
signer's authority? Can an operation that promotes its own signer influence key 2? Is the
four-key order genuinely total over every reachable pair? Does quarantine-plus-re-add
terminate, or can two devices quarantine each other indefinitely?

### 4. Leave and eviction semantics (ADR-039)

RFC 9420 §12.4 forbids a Commit that removes its own committer, so a departing member
cannot evict itself. `Leave` is therefore reclassified as non-membership in both
`group_model.dart` and `mls_beta.rs`, and departure is two-phase:

1. The leaver signs a non-membership announcement at the current epoch, carrying no
   Commit. Every device projects the member to `left` — *departure announced, eviction
   pending*. The leaver processes its own announcement like everyone else, so
   `removedLocally` covers `Remove` only.
2. The active owner commits the `Remove` that evicts the leaves and rotates the epoch to
   `removed`. `GroupPendingEvictionService` runs as post-inbox work, evicting at most one
   member per group per pass so a partial sweep stays resumable, and treats a concurrent-
   control conflict as a retry rather than an error.

The owner is the deterministic committer because `canLeave` only lets an owner leave as
the last active member, so any group that still has members has exactly one active owner.
`isEvictable` keeps `left` a valid target: a departed leaf still holds the epoch secret,
so eviction is a security obligation, not bookkeeping.

Review questions: what is the maximum window during which a `left` member still holds a
live epoch secret, and what bounds it? If the sole owner is offline indefinitely, does any
other member's authority ever open? Can a `Leave` announcement be replayed at a later
epoch? Does the one-per-pass sweep interact safely with fork quarantine of the evicting
branch?

### 5. Queue-gap re-admission

A device whose mailbox was pruned past its position cannot follow the epoch chain. The
group is marked queue-gapped, and from then on `commitTransitionInsideTransaction` refuses
any control that claims to extend it — recovery is `rejoinInsideTransaction`, which is
deliberately *not* a control transition: the stale local revision is not the parent of the
new one, so the re-admission Welcome carries its own complete transcript, is replayed from
no state, and replaces the retained projection, roster, and transcript rather than
continuing them. It commits under a compare-and-swap witness on the superseded local
revision and requires the new revision to be strictly greater.

`inspectQueueGapRejoin` returns null rather than a failure for a non-admissible object, so
hostile or merely early input can neither clear the gap nor turn the blocked queue into a
rejection or retry loop.

Review questions: can a relay induce a queue gap it can then fill with a re-admission of
its choosing? Is "strictly greater revision" enough, given that the intervening commits
were never seen? What happens to ciphertext already queued for the dead epoch?

### 6. The transactional commit boundary

The claim is [the local data model](local-data-model.md)'s MLS transaction boundary: new
opaque MLS state, the accepted control or application fact, the membership and conversation
projections, and the exact prepared outbound object commit atomically under a control
revision/hash compare-and-swap, and the object reaches the network only afterwards.

Mechanically: `commitTransitionInsideTransaction` first checks that the signed control's
group, hash, and revision match the next state; validates the transcript; then either
inserts (refusing an existing row) or updates under `groupId AND controlRevision =
expectedPrevious.controlRevision`, additionally requiring `queueGapRecoveryState == 0` and
a byte-equal previous control state hash, and asserting exactly one row was written.
Outbound objects are inserted in the same transaction with `deliveryState = 1`; the
development preview writes `0` and is never dispatched.

Two defects were found here by fault injection on 2026-08-18 and fixed at `4e65eaf`:

- **Multi-recipient fan-out was impossible.** One group object becomes one pairwise
  operation per recipient user, and `pairwise_local_applications.event_id` is `UNIQUE`, so
  the second recipient collided with the first and rolled the whole transaction back. Any
  group with two or more remote members committed its epoch and object and then could
  never route them, identically on every retry. **Closed-beta group transport worked only
  for two-member groups.** The dispatcher now qualifies the logical send identity per
  recipient exactly as it already qualified the operation ID; identifiers inside the MLS
  object are untouched. It went unnoticed because the dispatcher had only ever been tested
  against a fake envelope port.
- **One unroutable operation stranded every later group.** Pending work is ordered by
  creation and the dispatcher returned on the first failure. The pass now continues past a
  failure and still surfaces the first one.

A third gap was closed in the same pass: the two inbound use cases refused a prepared
transition carrying an outbound object, but the three outbound ones did not refuse one
carrying none, so a crypto port returning an inbound-shaped result would have advanced this
device to an epoch with nothing to send.

Review questions: can any failure after key derivation commit state without its exact
ciphertext, or ciphertext without its state? Is the compare-and-swap witness sufficient
under two concurrent inbound envelopes for the same group? Does `markOutboundRouted`
running outside the fan-out transaction admit a double-send, and if not, what prevents it?

### 7. State sealing and versioning

Sealed state is `XChaCha20-Poly1305(key, nonce, plaintext, header)`. The 45-byte header is
`CPMLSE01 || u16 version (currently 2) || u16 0xFE4C || u8 kind ||
SHA-256(binding identifier)`, and it is used as the associated data. The key is
`HKDF-SHA-256(salt = 0^32, ikm = device identity secret,
info = "chat:v1:beta-pq-mls-state-wrap")`.

The binding identifier is version-dependent, which is the subtle part: version 1 bound
state to the complete `BasicCredential` identifier — which contains the device bundle hash,
so it changed on every prekey rotation — and version 2 binds to `CPMLSB01 || user_id ||
device_id || device signing public key`, which does not. Version 1 remains *readable* and
is rewritten as version 2 on the next write; every other version is rejected.

Inside the seal, a group snapshot is `CPMLSG01 || version || suite || local credential
identifier || proof set || raw mls-rs state`. A bare `CPMLSV01` prefix — the pre-v3 layout
with no authentication transcript — is rejected before parsing, because the newer reader
would otherwise interpret it as a v3 state whose proof set happens to be empty and restore
a client that cannot verify the roster it is about to act on.

Review questions: is a single HKDF output with a zero salt the right key derivation here,
given the identity secret is long-lived? Does the version-1-readable path give an attacker
a downgrade to the rotating binding? Is `kind` enough to prevent a group snapshot being
opened as a KeyPackage store or vice versa? What happens on an interrupted version-1 to
version-2 rewrite?

### 8. Per-recipient envelope re-wrapping (ADR-011)

MLS produces one ciphertext for the group. Handing that ciphertext to the relay would link
a sender's recipient set at rest, so every group object is re-wrapped: one pairwise
transport v1 operation per recipient user, each with its own ratchet state, its own
`operationId` and `eventId` qualified by the target, and `includeOwnDevices` set only for
the first target. The group object itself is the opaque payload; the pairwise layer
authenticates version, suite, purpose `pairwise-transport-v1`, recipient device, and
ratchet header around it.

The MLS object does cross the FFI into Dart and is persisted in
`group_outbound_objects.mlsObject` — it must be, because Dart owns transport. The narrower
claim in [the MLS profile](mls-profile.md) is that no MLS *secret* and no raw MLS
ciphertext reaches a Dart *projection* or backend metadata. A reviewer should confirm the
boundary is exactly that and not wider: `encode_commit_operation_response` returns sealed
state, the Commit bytes, a SHA-256 commit digest, the authentication proof set, the
Welcome set, the `GroupInfo`, the group ID, the epoch, and a SHA-256 *of* an exporter
secret — never the exporter secret itself.

Review questions: does the per-target qualification of `eventId` weaken recipient-side
deduplication, which keys on identifiers inside the MLS object? Can a partially completed
fan-out be distinguished by the relay from a complete one? Is `includeOwnDevices` on the
first target only correct when the first target fails and a later pass reorders?

### 9. The FFI boundary

The entire beta MLS surface is `cp_crypto_v1_beta_mls_operation(operation, input,
input_len, output, output_len, written)`, one function, 13 operations, present only in the
beta native profile. The Rust side bounds input to `MLS_MAX_IO_BYTES` before anything else,
rejects an operation outside `1..=13`, then requires magic `CPMLR001` and version 1 before
authenticating the caller and dispatching; each operation is responsible for consuming its
own tail exactly. The response is magic `CPMLO001`, version 1, and the operation byte.
Panics are contained by `guard` and surface as ABI status 14 (`CryptoError::PanicContained`).

Notably, `mls_beta.rs` contains **no `unsafe` at all**; the 46 `unsafe {}` blocks it relies
on are `lib.rs`'s shared ABI helpers. On the Dart side, `beta_mls_ffi.dart` is
the only `dart:ffi` allocation on this path: it refuses over-sized input, allocates a
1 MiB output buffer, and in `finally` zeroes both buffers before freeing all three
pointers. The 1 MiB Dart ceiling equals `MLS_MAX_IO_BYTES` exactly.

Review questions: is a fixed 1 MiB output allocation per call acceptable on a low-memory
Android device under fan-out? `written.value > _maximumBetaMlsBufferBytes` is checked after
a zero status — can the native side ever report success with a larger `written`? Does the
isolate worker keep native session ownership single-threaded under concurrent group and
pairwise work?

### 10. Redaction and the error surface

`BetaMlsEngineError`, `AuthenticationServiceError`, `BetaKeyPackageError`,
`BetaKeyPackageStateError`, and `BetaMlsStateError` are all payload-free C-like enums;
they are mapped to stable `CryptoError` codes and never carry a message. The four
hand-written `Debug` implementations in `mls_beta.rs` — for the authentication context,
generated KeyPackages, and both opaque storages — all use `finish_non_exhaustive()` with
no fields. Secrets are held in `SecretBytes`/`SecretVec`/`Zeroizing`.

Review questions: does any `mls-rs` error type reach a log or a Dart failure message with
content attached? Is the ABI status alone enough for a reviewer to diagnose a field
failure, and if not, what does the project intend to do instead? Do the group projections
written to Drift contain any stable identifier that the local-diagnostics rules forbid?

## Required vector matrix

The distinction between these two tables is load-bearing and must survive into any review
report. `native/crypto_core/vectors/README.md` states per test what is and is not proven;
it is the authority, and this is its summary.

### Official external vectors — conformance evidence for that primitive

| Fixture | Source and revision | Cases | Driven by |
|---|---|---|---|
| `mlkem768-acvp-fips203.json` | NIST ACVP-Server tag `v1.1.0.41`, ML-KEM-768, FIPS 203, `vsId` 42 | keyGen 5 of 25 (`tcId` 26-30); encapsulation 5 of 25 (`tcId` 26-30); decapsulation **10 of 10** (`tcId` 86-95, including all five implicit-rejection cases); `decapsulationKeyCheck` 4 of 10 | `src/mlkem_vectors.rs` |
| `beta-suite-kats.json` — Ed25519 | RFC 8032 §7.1 | TEST 1, 2, 3, SHA(abc) — 4 of 5 | `src/beta_suite_vectors.rs` |
| — SHA-384 | NIST FIPS 180-4 + CSRC examples | empty, `abc`, 896-bit two-block, one million `a` | " |
| — SHA3-256 | NIST FIPS 202 + CSRC examples | empty, `abc`, 448-bit, 896-bit, 1600-bit `0xa3` | " |
| — HMAC-SHA-384 | RFC 4231 §4 | Test Cases 1, 2, 3, 4, 6, 7 — 6 of 7 | " |
| — HKDF-SHA-384 extract | RFC 4231 via RFC 5869 §2.2's normative identity | the same six tags asserted against `kdf_extract` | " |
| — AES-256-GCM | NIST CAVP `gcmEncryptExtIV256.rsp` + GCM specification appendix B | CAVP Count 0 plus specification cases 13-16 | " |
| — HKDF-SHA-256 | RFC 5869 appendix A.1-A.3 | all three SHA-256 cases | " |
| — X25519 | RFC 7748 §5.2, §6.1 | both scalar-multiplication vectors and the exchange | " |

The `pairwise-v1.json` and `attachment-header-v1.json` fixtures also live in that
directory. They belong to other packets and are project vectors.

### Project-generated vectors — regression pins only

`beta-hybrid-kem-project-kats.json`, driven by `src/beta_kem_vectors.rs`. Produced by this
repository on 2026-08-17 by a one-off generator that was then deleted; no build step and no
test run may rewrite it.

| Group | Cases | Pins |
|---|---|---|
| `kemDerive` | 3 (32-byte zero ikm, 32-byte counter ikm, 8-byte ikm) | `kem_derive(ikm)` to its exact 2,432-byte secret and 1,216-byte public key, plus the recomputed `dkp_prk` |
| `hpke` | 2 (one with AD, 27-byte `info`, four-block plaintext; one with everything empty) | full deterministic encapsulation, key schedule, ciphertext, exporter output, and the X-Wing contrast value; the two cases derive a fourth and a fifth recipient key pair between them, so five distinct ikms are covered in total |

Ten tests drive it, and several demonstrate a divergence row as a computed fact rather than
a documented claim: D5, D6, D7, and D9 (`..._derive_pins_project_vector_bytes`); D1, D2,
and D3 (`..._is_not_the_xwing_construction`); D4
(`..._suite_id_binds_the_unassigned_kem_id`); D8
(`..._public_key_validation_is_a_no_op`).

**These are not external conformance evidence and must never be cited as `TBD2`, `0x647a`,
X-Wing, or RFC 9180 conformance or interoperability.** What keeps them auditable rather
than circular is that every expected value is re-derivable from the case inputs, and the
tests re-derive it on `mlkem-native`, `x25519-dalek`, and RustCrypto `hkdf`/`sha2` — none
of which is AWS-LC — with the reference sealing the ciphertext the implementation then
opens, and with the implementation's own randomized `hpke_seal` decrypted by the reference
to cover the encapsulation direction a static fixture cannot.

### Project-generated vectors written in the upstream schema — still not upstream vectors

`vectors/mls-beta-upstream-schema/`, driven by `src/beta_mls_vectors.rs` (ten tests, plus
an `#[ignore]`d generator). These carry the MLS working group's published vector schema
(`test-vectors.md`, branch `main`, verified 2026-08-18, cross-checked against the
deserializers in `mls-rs 0.55.2`) filled with values this repository produced for `0xFE4C`.

| File | Category | Objects | Round trip |
|---|---|---|---|
| `welcome.json` | Welcome | 1 | the recorded `Welcome` decrypts under the recorded `init_priv`, its `GroupInfo` signature and confirmation tag verify, and `signer_pub` is a member of the group it admits |
| `passive-client.json` | Passive Client Scenarios | 1, over 3 epochs | a client rebuilt from the vector's own key material joins and reproduces `initial_epoch_authenticator` and every epoch authenticator across an add, a by-reference update, and a remove |
| `deserialization.json` | Vector Deserialization | 8 | each `VarInt` header decodes to the recorded length and re-encodes to the same bytes |

Two negative tests keep the round trips from passing vacuously: corrupting one byte of
`init_priv` must break the join, and a commit that incorporates a proposal by reference
must not apply without that proposal.

**The schema is upstream. The values are not. These are not external interoperability
evidence, they do not satisfy Phase-A external prerequisite 4, and they do not move any of
the seven production gates.** Every emitted object repeats that under its own `_provenance`
key, which is the only non-upstream key in the files and is asserted on every test run.

Eleven of the fourteen categories are deliberately absent. The rule applied was to emit a
category only where this implementation can populate every field through the code it ships;
for Crypto Basics, Secret Tree, Message Protection, Key Schedule, Pre-Shared Keys,
Transcript Hashes, Tree Operations, Tree Validation, TreeKEM, and Tree Math the required
construction is `pub(crate)` inside `mls-rs`, so emitting them would vector a
re-implementation written for the fixture rather than the shipped path. Messages is absent
because it cannot be completed at all: RFC 9420 forbids a `PublicMessage` application
message, and the beta client encrypts control messages, so three of its fields are
unreachable. `vectors/mls-beta-upstream-schema/README.md` carries the per-category reasons.

One finding is worth the reviewer's attention on its own: the schema requires `EdDSA`
private keys in "their native byte string representation" — the 32-byte RFC 8032 seed —
while the beta suite's AWS-LC provider represents them as the 64-byte `seed || public key`
concatenation. Emission truncates and consumption re-appends. `mls-rs`'s own passive-client
generator writes the provider-native secret straight out, which would be non-conformant for
this suite; its framing generator truncates correctly.

### The vectors that do not and cannot exist

- **Upstream MLS interoperability vectors for this suite.** The MLS WG repository publishes
  only its classical fixture set. This is Phase-A external prerequisite 4 — tracked
  separately from the seven gates — and it cannot be unblocked from inside this
  repository. [The testing strategy](testing-strategy.md) states the consequence directly:
  experimental PQ MLS fixtures cannot satisfy a production gate. Writing this project's own
  vectors in the upstream *schema* does not change that by even a little: adopting a
  published format is not the same as being validated against a published answer, and
  `vectors/mls-beta-upstream-schema/` says so in every object it contains.
- **Construction-level vectors for the beta hybrid KEM.** There is no registry entry, RFC,
  or Internet-Draft whose vectors it is supposed to reproduce, because it is not a
  published construction — that is what rows D1-D10 say. RFC 9180's DHKEM vectors do not
  reach it either: the inner `DHKEM(X25519, HKDF-SHA256)` is wrapped by a combiner whose
  `kem_id` is `0x000F`. ADR-040 makes this gap permanent for the closed beta rather than
  pending.
- **SHAKE-128 known answers (D6).** `mls-rs-crypto-awslc 0.25.0` does not export
  `AwsLcShake128` and no other dependency exposes SHAKE. The expansion is pinned, not
  rebuilt; one third of it is cross-checked indirectly because FIPS 203 stores `z` in `dk`.
- **HKDF-SHA-384 expansion known answers.** RFC 5869 publishes outputs only for SHA-256 and
  SHA-1; the NIST ACVP `KDA-HKDF-SP800-56Cr2` files are too large to transcribe by hand and
  cannot be fetched under the offline rule. The expand half is checked against RFC 5869
  §2.3's construction over an RFC 4231-pinned HMAC, which is a construction check, not a
  known-answer test.
- **Independent-implementation ML-KEM assurance.** The AWS-LC differential test is *not*
  one: `aws-lc-sys 0.40.0` vendors mlkem-native too. It catches upstream revision drift,
  Keccak substitution, configuration differences, and Rust-seam integration errors. The
  NIST vectors remain the correctness anchor.

### Negative and adversarial coverage that must be present

Malformed and hostile input coverage is carried by the fuzz harness rather than a static
negative-vector table. Twelve targets cover the C ABI entry with its input and output
bounding, the request envelope, relay-served peer device bundles, published `KeyPackage`
buckets, group creation from those buckets, Welcome processing, incoming-message
processing, bare MLS object hashing, signed control transcripts and their
descriptor/metadata/member/text readers, persisted device state, and the three persisted
state-restoration layers.

The recorded campaign of 2026-08-18 executed 20,700,000 inputs across those 12 targets in
1,859.1 s under seed `0x0badc0ded15ea5e5` with no panic, unbounded allocation, hang, or
contained panic. Two earlier campaigns of 2,540,000 inputs each, under two seeds, over the
first ten targets, were also clean. Each ordinary `cargo test --locked --all-features` runs
a bounded 25-base pass over all twelve.

**One defect was found and fixed** (`2233c44`). `MlsMessage::from_bytes` stops at the end of
the object it decodes and ignores whatever follows, so `object || anything` decoded to the
same message. `hash_mls_object` and the `KeyPackage` wrapper already re-serialized and
compared; Welcome processing and incoming-message processing did not. An untrusted relay
could therefore present one logical Welcome or Commit under unlimited distinct byte
encodings, each accepted and each yielding a different SHA-256 identity — defeating any
deduplication or binding keyed on the exact received bytes, including the digest
`native_beta_group_mls.dart` compares against a signed control event's `mls_commit_hash`,
and applying a tampered Commit to a candidate group state before that comparison rejected
it. All four relay-reachable paths now share `exact_mls_object`.
`every_mls_object_path_refuses_a_non_canonical_encoding` is the regression.

Each detector has a negative control (`every_detector_reports_its_injected_defect`), so a
clean campaign is evidence rather than an absence of instrumentation, and the per-target
outcome spread is printed with every run.

That spread is what a reviewer should read rather than the input count, because it shows
whether mutations reached past the first rejection. Re-running the recorded campaign for
this packet on 2026-08-18 at revision `4e65eaf` (same seed, same budget; 1,803.2 s, clean)
produced, for example, `peer_bundle` 10,309 accepted of 4,000,000, `mls_object_hash` 11,612
of 100,000, `state_restoration` 217,310 of 4,000,000, `welcome_join` 168 of 100,000, and
`process_message` 176 of 100,000 — with the balance distributed across distinct typed
rejections rather than concentrated in one. The two lowest rates are the two deepest
targets, and whether they are deep enough is a fair question for the assessor.

Sealed group and KeyPackage state is deliberately **not** fuzzed at the relay boundary: the
relay cannot reach it at all. Its plaintext layers are fuzzed directly instead, which is
the local storage-tamper boundary.

## Test inventory

Verified by running, on 2026-08-18, at revision `4e65eaf`.

### Rust

| | Count |
|---|---|
| `cargo test --locked --all-features` | **120 declared, 118 run, 2 ignored, 0 failed** |
| `cargo test --locked` (default features, no beta) | **55 declared, 55 passed, 0 failed** |
| Added by the `beta-pq-mls` feature | **65** |

The two ignored tests are the on-demand fuzz entry points
`mls_beta::fuzz::beta_mls_fuzz_campaign` and `mls_beta::fuzz::beta_mls_fuzz_replay`.

| Module | Tests under `--all-features` | Scope |
|---|---|---|
| `mls_beta::tests` | 23 | suite mapping, authentication, key packages, buckets, group lifecycle, control signing, sealing and versioning, tamper and truncation, fork grinding |
| `mls_beta::fuzz` | 17 | 12 targets, detectors and their negative controls, corpus reproducibility, seed round-trip, the non-canonical-encoding regression |
| `beta_suite_vectors` | 11 | official primitive vectors and the parameterization assertion |
| `beta_kem_vectors` | 10 | project KEM vectors and their non-AWS-LC reproduction |
| `mlkem_vectors` | 10 (6 without the feature) | ACVP fixture plus 4 AWS-LC differential tests |
| `provider` | 10 | foundation primitives |
| `enrollment` | 8 | device bundles and recovery |
| `pairwise` | 7 | pairwise transport |
| `application` | 6 | application protocol |
| `prekey_state`, `cbor` | 4 each | prekey lifecycle, canonical CBOR |
| `tests` (crate root), `secret` | 3 each | ABI and error-code stability, secret types |
| `device_signatures`, `attachment` | 2 each | canonical encoders, attachment headers |

### Dart

`flutter test` at this revision: **510 passed, 1 failed** (process exit 1). The single failure
is `test/widget/linked_devices_page_test.dart` — "lists encrypted labels and requires
explicit rename and revoke actions" — which fails on any host west of UTC because the
widget renders `.toLocal()` while the test asserts a UTC date. It is unrelated to group or
MLS code and is the pre-existing baseline on this workstation.

Group and beta-MLS tests, run as a subset: **157 passed across 21 files.**

| File | Tests |
|---|---|
| `test/features/groups/infrastructure/group_commit_boundary_injection_test.dart` | 18 |
| `test/features/groups/domain/group_fork_grinding_test.dart` | 16 |
| `test/features/groups/application/group_fork_convergence_test.dart` | 14 |
| `test/features/synchronization/group_inbox_crash_injection_test.dart` | 12 |
| `test/features/groups/domain/group_readmission_test.dart` | 11 |
| `test/features/groups/application/group_outbound_interruption_test.dart` | 9 |
| `test/features/groups/domain/group_leave_test.dart` | 9 |
| `test/features/groups/infrastructure/native_beta_group_mls_test.dart` | 9 |
| `test/features/groups/application/group_mls_admission_service_test.dart` | 7 |
| `test/features/groups/application/group_pending_eviction_service_test.dart` | 7 |
| `test/features/groups/domain/group_authorization_state_machine_test.dart` | 7 |
| `test/features/groups/infrastructure/drift_group_repository_test.dart` | 6 |
| `test/architecture/group_production_gate_test.dart` | 5 |
| `test/features/groups/application/group_key_package_maintenance_service_test.dart` | 5 |
| `test/widget/group_pages_test.dart` | 5 |
| `test/features/groups/infrastructure/group_key_package_api_test.dart` | 4 |
| `test/features/groups/application/group_outbound_dispatcher_test.dart` | 3 |
| `test/features/groups/application/group_use_cases_test.dart` | 3 |
| `test/features/groups/infrastructure/drift_group_key_package_maintenance_store_test.dart` | 3 |
| `test/features/groups/infrastructure/native_beta_group_mls_fork_test.dart` | 2 |
| `test/features/synchronization/group_inbox_transaction_test.dart` | 2 |

Plus, outside that subset: `test/shared/infrastructure/crypto/beta_mls_native_session_test.dart`
(9 tests, the FFI request/response codecs) and
`test/architecture/crypto_core_boundary_test.dart` (3 tests: port narrowness against the
Android build script's symbol list, Web fail-closed, and that the native boundary never
logs or stringifies a caught exception).

The 39 crash and transaction-failure injection tests the MLS profile records are three
files from that table: `group_commit_boundary_injection_test.dart` (18),
`group_inbox_crash_injection_test.dart` (12), and
`group_outbound_interruption_test.dart` (9). They use a temporary SQLite trigger that
raises `ABORT` on one exact statement inside the real transaction
(`test/support/storage_fault_injection.dart`); nothing under `lib/` is stubbed or given a
test-only seam, and process death is modelled by a file-backed database whose whole Dart
object graph is dropped and reopened through the production `beforeOpen` path, so
`PRAGMA quick_check` fails the test if an aborted write left the file inconsistent.

## Adversarial state-machine questions for the assessor

Grouped by the invention they attack. None of these is a known defect; they are the
questions this packet cannot answer for itself.

**Credential and roster**

- Can a device whose bundle rotated between two group operations be simultaneously present
  under two credential identifiers, and does any authorization decision differ between them?
- Can a hostile relay supply a proof set that authenticates a roster the transcript does not
  project, or vice versa?
- Does the 50-proof cap ever silently drop a proof that a later restore needs, turning a
  live group into an unopenable one?

**Transcript and admission**

- Is there any pair of distinct transcripts that reconstruct the same roster with different
  authority assignments?
- Can a truncated-but-consistent transcript prefix hide a demotion or an eviction from a
  joining member?
- A group that reaches 512 control events becomes unjoinable until a checkpoint format
  exists. Can a member inside the group drive an honest group to that cap cheaply, and is
  reaching it distinguishable from an attack?

**Fork convergence**

- Is the ordering tuple total over every reachable pair of authenticated siblings?
- Can any operation be authored in a precedence class above the authority its signer holds
  in the shared parent?
- Can two devices quarantine each other's branches in a cycle that never converges?
- Is the parent reconstruction that key 2 reads ever itself ambiguous at a fork?

**Leave and eviction**

- What bounds the window in which a `left` member still holds a live epoch secret?
- If the sole active owner never returns, does the group have any safe terminal state?
- Can a `Leave` announcement be replayed at a later epoch, or a `Remove` be replayed after
  re-admission?
- Does the one-eviction-per-pass sweep make progress under a hostile member that forks every
  revision?

**Queue gap and re-admission**

- Can a relay manufacture a queue gap and then choose the re-admission that fills it?
- Is a strictly greater revision sufficient, given the intervening commits were never seen
  and never will be?
- Does un-routed ciphertext from the dead epoch ever escape after re-admission?

**Commit boundary and concurrency**

- Can any failure after key derivation commit state without its exact ciphertext, or the
  reverse?
- Can two concurrent inbound envelopes for one group both pass the compare-and-swap?
- Does the routed marker being outside the fan-out transaction admit a double-send or a
  permanently unroutable object?
- Can a crash between the KeyPackage consumption and the group insert lose a private key
  that is still needed?

**Sealing and versioning**

- Does version 1 remaining readable give an attacker a downgrade to the rotation-sensitive
  binding?
- Is `kind` sufficient to prevent cross-opening a group snapshot as a KeyPackage store?
- What is left behind by an interrupted version-1 to version-2 rewrite?
- Is a zero-salt HKDF over a long-lived identity secret the right derivation for state at
  rest?

**Transport**

- Does per-target qualification of the logical send identity weaken recipient-side
  deduplication?
- Can a partial fan-out be distinguished from a complete one by the relay?
- Is `includeOwnDevices` on the first target only still correct when that target fails and a
  later pass reorders the recipient list?

**Boundary and resource**

- Can the native side report success with `written` beyond the caller's buffer?
- Is a fixed 1 MiB output allocation per call safe under fan-out on a low-memory device?
- Does the isolate keep single-threaded ownership of the native session under concurrent
  group and pairwise work?
- Does any `mls-rs` error reach a log or a user-visible string with content attached?

**The divergence itself**

- The upstream defect report's finding 3.4 states that `ML_KEM_512`, `ML_KEM_768`, and the
  beta's `ML_KEM_768_X25519` all produce the same HPKE `suite_id` and `kem_suite_id`
  because `kem_id` is the same placeholder `15` in each. That reproduction is
  source-derived and was not executed. Does the collision hold when run, and does it have
  any consequence for a deployment that only ever instantiates one of the three?
- Does the encapsulation-key check being a no-op (D8) have an exploitable consequence for
  beta traffic, given whatever `aws_lc_rs::kem::EncapsulationKey::new` does internally?
- Because `Npk`, `Nenc`, and `Nsecret` are byte-identical between the beta construction and
  X-Wing, the divergence is silent on the wire and a mismatched peer fails at decryption
  rather than at parsing. Is the beta state-format version genuinely the only thing that
  rejects incompatible state, and is that sufficient?

## Reproduction commands

Run from `frontend/` with the repository-pinned toolchains and offline cache. Every command
in this section was executed at revision `4e65eaf` on 2026-08-18; "Validation results"
below records what each returned, and lists separately what was *not* run.

### Checks that must pass

"Gate" below never means a production gate; these are the repository's ordinary
verification commands.

```powershell
cargo fmt --manifest-path native/crypto_core/Cargo.toml -- --check
cargo test --locked --manifest-path native/crypto_core/Cargo.toml
cargo test --locked --all-features --manifest-path native/crypto_core/Cargo.toml
cargo clippy --locked --all-targets --all-features --manifest-path native/crypto_core/Cargo.toml -- -D warnings
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
flutter test
git diff --check
git diff --name-only -- ../backend
```

The two `cargo test` invocations are both required and are not redundant: the first proves
the production build does not contain the beta engine, the second exercises it.

### The beta subset alone

```powershell
cargo test --locked --all-features --manifest-path native/crypto_core/Cargo.toml mls_beta
cargo test --locked --all-features --manifest-path native/crypto_core/Cargo.toml beta_suite_vectors
cargo test --locked --all-features --manifest-path native/crypto_core/Cargo.toml beta_kem_vectors
cargo test --locked --all-features --manifest-path native/crypto_core/Cargo.toml mlkem_vectors
flutter test test/features/groups test/architecture/group_production_gate_test.dart test/features/synchronization/group_inbox_crash_injection_test.dart test/features/synchronization/group_inbox_transaction_test.dart test/widget/group_pages_test.dart
flutter test test/shared/infrastructure/crypto/beta_mls_native_session_test.dart test/architecture/crypto_core_boundary_test.dart
```

### The fuzz campaign

The bounded 25-base pass runs inside every `cargo test --locked --all-features`. The
recorded campaign is:

```sh
CP_FUZZ_ITERATIONS=100000 cargo test --locked --all-features --profile fuzz \
    mls_beta::fuzz::beta_mls_fuzz_campaign -- --exact --ignored --nocapture
```

Run it from `frontend/native/crypto_core/`. A dispatcher target executes the base budget
and a direct-decoder target executes forty times that, so the twelve targets total
20,700,000 inputs. Every knob — seed, target subset, allocation ceilings, slow-input budget,
watchdog, artifact directory — is documented in `native/crypto_core/fuzz/README.md`. A
finding writes the exact input to `CP_FUZZ_ARTIFACTS` and prints its own replay command;
the artifact, not the seed, is the unit of reproduction, because the fixtures are real
protocol artifacts built with live randomness.

### Packaging and the isolation check

```powershell
powershell -File tool/build_rust_android.ps1 all foundation
powershell -File tool/build_rust_android.ps1 all beta
flutter build apk --debug --flavor beta --target lib/main_beta.dart
flutter build apk --release --flavor production --target lib/main_production.dart
```

The export allowlist inside `build_rust_android.sh` fails the build on any unexpected
symbol, so a successful build *is* the isolation assertion. To see it independently, with
`<ndk>` the pinned NDK's LLVM toolchain:

```sh
"<ndk>/bin/llvm-nm" -D --defined-only build/rust-android/foundation/jniLibs/arm64-v8a/libcommunication_crypto_core.so | awk '{print $NF}' | sort
"<ndk>/bin/llvm-nm" -D --defined-only build/rust-android/beta/jniLibs/arm64-v8a/libcommunication_crypto_core.so | awk '{print $NF}' | sort
```

The lists must differ by exactly one line, `cp_crypto_v1_beta_mls_operation`, present only
in the second. Repeat for `armeabi-v7a` and `x86_64`.

Then repeat it on the shipped artifact, which is the check that actually matters:

```sh
unzip -o -q build/app/outputs/flutter-apk/app-production-release.apk 'lib/*/libcommunication_crypto_core.so' -d /tmp/apk-prod
for abi in arm64-v8a armeabi-v7a x86_64; do
  "<ndk>/bin/llvm-nm" -D --defined-only "/tmp/apk-prod/lib/$abi/libcommunication_crypto_core.so" | awk '{print $NF}' | sort
done
```

Every ABI must list exactly the 15 foundation symbols and no `beta_mls` symbol.

The packaged Android smoke test and the physical-device crash matrix additionally require a
connected supported Android device or emulator, and neither has been run. Web byte equality
is deliberately absent from this packet and remains a post-v1 gate.

## Validation results

What this packet actually ran, at revision `4e65eaf` on 2026-08-18.

| Command | Result |
|---|---|
| `cargo fmt … -- --check` | clean |
| `cargo test --locked` (default features) | **55 passed, 0 failed**; `mls_beta` absent from the enumerated list, as expected |
| `cargo test --locked --all-features` | **118 passed, 0 failed, 2 ignored** in 22.74 s |
| beta cargo subsets (`mls_beta`, `beta_suite_vectors`, `beta_kem_vectors`, `mlkem_vectors`) | 38+2 ignored, 11, 10, 10 — all passed |
| `CP_FUZZ_ITERATIONS=100000 … beta_mls_fuzz_campaign` | **12 targets, 20,700,000 inputs, 1,803.2 s, seed `0x0badc0ded15ea5e5`, clean** — no panic, contained panic, unbounded allocation, or hang. Independently reproduces the 2026-08-18 campaign recorded in [the MLS profile](mls-profile.md), which took 1,859.1 s on the same seed and budget |
| `cargo clippy --locked --all-targets --all-features -- -D warnings` | clean, exit 0 |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | 319 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` | No issues found |
| `flutter test` | **510 passed, 1 failed**, process exit 1 — the pre-existing host-timezone failure in `linked_devices_page_test.dart`, unrelated to this work |
| group subset (21 files) | **157 passed** |
| `flutter test test/shared/…/beta_mls_native_session_test.dart test/architecture/crypto_core_boundary_test.dart` | 12 passed (9 + 3) |
| wider crypto and architecture subset | 53 passed |
| `git diff --check` | clean |
| `git diff --name-only -- ../backend` | empty — no backend file changed |
| `tool/build_rust_android.ps1 all foundation` | all three ABIs built; export allowlist, 16-KiB alignment, and static-libsodium checks passed |
| `tool/build_rust_android.ps1 all beta` | all three ABIs built; same checks passed against the 16-symbol beta allowlist |
| `llvm-nm -D --defined-only` on all six freshly built artifacts | 15 vs 16 symbols on every ABI, differing by exactly `cp_crypto_v1_beta_mls_operation` |
| `flutter build apk --debug --flavor beta --target lib/main_beta.dart` | built `app-beta-debug.apk` |
| `flutter build apk --release --flavor production --target lib/main_production.dart` | built `app-production-release.apk` (80.4 MB) |
| `llvm-nm` on the native libraries **inside the production release APK** | 15 symbols on every ABI, zero `beta_mls` symbols, byte-identical to the freshly built foundation artifacts |

Every command published above was executed for this packet. What was **not** run, and is
therefore not evidence of anything:

- the packaged Android smoke test and any on-device execution — no device or emulator was
  attached;
- the physical-device crash matrix in every one of its cells;
- state-format migration fuzzing;
- any backend contract execution against a running Django stack; and
- any sanitizer, Miri, or coverage-guided fuzzing run, for the toolchain reason above.

## Review disposition template

| Area | Reviewer | Revision/hash | Finding | Severity | Required action | Closed by |
|---|---|---|---|---|---|---|
| Credential binding and Authentication Service integration | | | | | | |
| Control transcript and later-member admission | | | | | | |
| Fork convergence and quarantine | | | | | | |
| Leave, eviction, and re-admission | | | | | | |
| Transactional commit boundary and concurrency | | | | | | |
| State sealing, versioning, and migration | | | | | | |
| Per-recipient envelope re-wrapping | | | | | | |
| KeyPackage lifecycle and backend buckets | | | | | | |
| FFI boundary, isolate ownership, and bounds | | | | | | |
| Redaction and error surface | | | | | | |
| Suite assembly and the recorded KEM divergence | | | | | | |
| Vector coverage and its stated limits | | | | | | |
| Fuzzing, fault injection, and their gaps | | | | | | |
| Android packaging and beta isolation | | | | | | |

**Empty rows never imply approval.** An unfilled row means the area has not been assessed,
not that it passed. A row filled with "no finding" means one reviewer looked and recorded a
result; it still does not close a production gate.

Closing the closed beta's own review would require every blocking and high finding
resolved, the exact reviewed source hashes recorded, vector reproduction on the packaged
Android artifact, the physical-device crash matrix run, and explicit written acceptance of
every residual risk listed under "Explicitly out of scope".

**Even then, no production gate opens.** Gate 1 needs every primitive assigned in its
owning registry against a published, non-expiring reference; gate 2 needs a final stable
MLS specification and an IANA-assigned suite value replacing `TBD2`; gate 3 needs a
maintained provider that implements that final mapping without a project-local
cryptographic fork. None of the three can be supplied by any review of this code, and
ADR-026 forbids substituting a locally assigned identifier for gate 2. The separate
Phase-A prerequisite of usable upstream interoperability vectors is likewise external: the
MLS Working Group publishes none for any post-quantum suite, and the project-generated
vectors in this packet explicitly do not advance it.

This packet exists so that the implementation-dependent work — gates 4, 5, 6, and the
review half of gate 7 — is ready when those external conditions change. It is not evidence
that they have.
