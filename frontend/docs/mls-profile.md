# Post-quantum MLS profile

## Status

This document owns the Flutter client's group-ciphersuite decision. The algorithm
profile is selected, but it is not yet a production wire contract. ADR-036 permits a
real isolated closed-beta implementation with disposable state and a Private Use suite
identifier. That closed beta implements the selected profile's symmetric and signature
choices but not its hybrid KEM, which "Closed-beta KEM divergence from TBD2" records in
full. Production still resolves the unsupported adapter, keeps the source-only production
gate closed, and cannot create a group or upload a KeyPackage.

Status last verified on 2026-08-16 against IETF draft revision 06, the IANA MLS
ciphersuite registry, the IANA HPKE KEM, KDF, and AEAD registries, the IANA TLS
SignatureScheme registry, NIST FIPS 180-4, `draft-ietf-hpke-pq`,
`draft-irtf-cfrg-concrete-hybrid-kems`, `draft-connolly-cfrg-xwing-kem`, the pinned
vendored `mls-rs` crate sources, the OpenMLS supported-ciphersuite list, the `mls-rs`
release index, and the MLS Working Group interoperability-vector repository.

### Phase-A external preflight (2026-08-16)

These prerequisites exist outside this implementation and cannot be made true by adding
more project code. All five remain blocked. The single row that previously combined "final
stable specification and IANA-assigned suite identifier" is now two rows, because the
primitive mapping and the MLS suite value are held in different registries with different
owners, different registration policies, and independent completion paths; that split
changes evidence granularity only. No prerequisite result has changed since 2026-08-09.

| External prerequisite | Current primary-source evidence | Result | Consequence |
|---|---|---|---|
| Stable published specification and registry assignment for every primitive in the selected mapping | Four of the five primitives already rest on published, non-expiring standards and are assigned in registries this project does not control: KDF `0x0002` (HKDF-SHA384, reference RFC 5869) and AEAD `0x0002` (AES-256-GCM, reference NIST SP 800-38D) in the IANA HPKE registries, last updated 2026-04-16; signature `ed25519` `0x0807` (`Recommended = Y`, reference RFC 9846) in the IANA TLS SignatureScheme registry, last updated 2026-08-10; and hash SHA-384, which carries no code point at all and is named directly from NIST FIPS 180-4. The hybrid KEM is the exception. `0x647A` is assigned in the IANA HPKE KEM Identifiers registry, but the only normative reference recorded there is `draft-connolly-cfrg-xwing-kem-06`, an Independent-submission Internet-Draft; that draft has since advanced to `-10` (2026-03-02, expiring 2026-09-03) without the registry reference following it, and the chain draft-06 uses to reach it — `draft-ietf-hpke-pq-05` and `draft-irtf-cfrg-concrete-hybrid-kems-04`, the latter in datatracker state `I-D Exists::Revised I-D Needed` — is still moving. | **Blocked** (one primitive of five) | The mapping cannot be frozen as a production wire contract while its KEM rests on a superseded, expiring draft revision. This prerequisite blocks and clears independently of any MLS Cipher Suites action, which is why it is evidenced separately from the row below. |
| Final MLS specification and an IANA-assigned MLS ciphersuite value | `draft-ietf-mls-pq-ciphersuites-06`, published 2026-07-21, is still an expiring Standards Track Internet-Draft (expires 2027-01-22). Its datatracker state is "I-D Exists", annotated "Waiting for WG Chair Go-Ahead" and "Revised I-D Needed - Issue raised by WG", so the text is expected to change again. Its IANA Considerations request entries in the "MLS Cipher Suites" registry only and request nothing in the HPKE registries. The selected suite is still `TBD2`; that registry, last updated 2025-11-17, contains only `0x0000` RESERVED, RFC 9420 values `0x0001`-`0x0007`, the GREASE values, and Private Use `0xF000`-`0xFFFF`. No post-quantum suite is registered. | **Blocked** | No production suite value, KeyPackage, or group may be emitted. The registry's Specification Required policy is not a route this project may take: ADR-026 forbids assigning a production identifier locally, so this closes only when the working group's document becomes a stable specification and IANA assigns the value that replaces `TBD2`. No amount of primitive-level progress advances it. |
| Maintained non-project-local OpenMLS/provider support for the exact final Android mapping | OpenMLS 0.8.1 (2026-02-13) remains the newest stable release and 0.9.0-rc.2 (2026-08-06) is still a release candidate; both still document only the three classical RFC 9420 suites. OpenMLS's published post-quantum work targets X-Wing (`MLS_256_XWING_CHACHA20POLY1305_SHA256_Ed25519`, experimental `0x004D`, with no IANA code point), whose AEAD, KDF, and hash differ from `TBD2`; its KEM does not differ, because `TBD2`'s own KEM `0x647a` *is* X-Wing. `mls-rs` exposes `CipherSuite::ML_KEM_768_X25519` at Private Use `0xFE4C`, but the mapping this project assembles through the maintained public `AwsLcCipherSuiteBuilder` API is not `TBD2`: its symmetric half matches and its hybrid KEM does not, as evidenced under "Closed-beta KEM divergence" below. | **Blocked** | The closed beta may use the locked maintained `mls-rs` provider under ADR-036, but composing the mapping ourselves does not satisfy the production OpenMLS/provider gate. No project-local cryptographic fork is permitted. |
| Usable upstream interoperability vectors for the selected suite | The MLS Working Group vector repository still exposes only its classical fixture set (`crypto-basics`, `key-schedule`, `message-protection`, `messages`, `passive-client-*`, `psk_secret`, `secret-tree`, `transcript-hashes`, `tree-*`, `treekem`, `welcome`). No ML-KEM/PQ fixture set exists. | **Blocked** | Project lifecycle fixtures are useful beta evidence but cannot substitute for independent upstream interoperability. |
| Qualified independent reviewer available for the final implementation | No named, retained reviewer, scope of work, or review schedule is recorded for this project. | **Blocked** | Review-dependent production gates cannot close until a qualified reviewer is engaged and all blocking findings are resolved. |

#### Per-identifier registry evidence (verified 2026-08-16)

Every identifier in the selected mapping was checked against the registry that owns it. The
first two Phase-A rows are split along the boundary this table makes visible: five primitive
identifiers are owned by the IANA HPKE registries, the IANA TLS SignatureScheme registry,
and NIST, and not one of them is owned by the MLS registry that still lacks the suite value.

| Identifier | Value | Owning registry or specification | Registration policy | Registry last updated | Reference recorded there | Status |
|---|---|---|---|---|---|---|
| Hybrid KEM | `0x647A` (X-Wing) | [IANA HPKE KEM Identifiers](https://www.iana.org/assignments/hpke/hpke.xhtml) | Specification Required (RFC 9180) | 2026-04-16 | `draft-connolly-cfrg-xwing-kem-06` | Assigned, but the reference is a superseded Independent-stream Internet-Draft; the document is now at `-10` (2026-03-02, expires 2026-09-03) |
| KDF | `0x0002` HKDF-SHA384 | [IANA HPKE KDF Identifiers](https://www.iana.org/assignments/hpke/hpke.xhtml) | Specification Required (RFC 9180) | 2026-04-16 | RFC 5869 | Assigned against a published standard |
| AEAD | `0x0002` AES-256-GCM | [IANA HPKE AEAD Identifiers](https://www.iana.org/assignments/hpke/hpke.xhtml) | Specification Required (RFC 9180) | 2026-04-16 | NIST SP 800-38D | Assigned against a published standard |
| Hash | SHA-384 | No code point; named algorithm from [NIST FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final) | Not registry-assigned; NIST publication process | FIPS 180-4 final 2015-08-04; NIST recorded an intent to revise on 2023-03-07 | FIPS 180-4 | Specified; no registry action is possible or needed |
| Signature | `ed25519` `0x0807` | [IANA TLS SignatureScheme](https://www.iana.org/assignments/tls-parameters/tls-parameters.xhtml) | IANA records "Either Standards Action With Expert Review or IESG Approval" and "Specification Required"; RFC 9847 requires IETF Standards Action with Expert Review or IESG Approval to set the `Recommended` column | 2026-08-10 | RFC 9846 (registry cites RFC 9846, RFC 9851, RFC 9847) | Assigned, `Recommended = Y`, against a published standard |
| MLS ciphersuite | `TBD2` — no value | [IANA MLS Cipher Suites](https://www.iana.org/assignments/mls/mls.xhtml) | Specification Required (RFC 9420 section 17.1); designated experts Sean Turner, Raphael Robert, Richard Barnes | 2025-11-17 | none | **Unassigned**; the registry holds only `0x0000` RESERVED, `0x0001`-`0x0007`, GREASE, and Private Use `0xF000`-`0xFFFF` |

`draft-ietf-mls-pq-ciphersuites-06` Table 2 gives `TBD2` as KEM `0x647a`, KDF `0x0002`,
AEAD `0x0002`, hash `SHA384`, signature `ed25519`, and its IANA Considerations ask IANA to
add entries to the "MLS Cipher Suites" registry only. It requests nothing in the HPKE
registries. The primitive assignments therefore neither wait on nor advance the suite
assignment, and the suite assignment will not change any primitive identifier. That is the
justification for evidencing the two prerequisites separately: different owners, different
policies, independent registry cadences (2026-04-16, 2026-08-10, and 2025-11-17), and
different completion paths. The split removes nothing — the primitive prerequisite is an
additional condition that the previous combined row never stated explicitly.

Draft-06 still defines `TBD2` as `MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519` with
KEM `0x647a`, KDF `0x0002` (HKDF-SHA384), AEAD `0x0002` (AES-256-GCM), hash SHA-384, and
signature Ed25519 — the exact mapping already recorded here. The suite name and primitive
mapping are therefore unchanged from the selected candidate and the stop-and-decide rule
is not triggered by this audit. Any later change to the name, mapping, or assigned
identifier requires an explicit owning-document/ADR decision and group reinitialization;
it is never adapted silently.

That statement is about the recorded *candidate*, not about what the closed beta builds.
The two are not the same, and the next section is the binding record of the difference.

### Closed-beta KEM divergence from TBD2 (verified 2026-08-16)

The closed beta does not implement `TBD2`, and no beta artifact ever has. Its signature,
AEAD, KDF, and hash choices match `TBD2` exactly; its hybrid KEM does not.

`TBD2` names HPKE KEM `0x647a`. The normative chain for that code point is
`draft-ietf-mls-pq-ciphersuites-06`, which takes its hybrid KEMs from
`draft-ietf-hpke-pq-05` (2026-07-06); that draft registers `0x647a` as `MLKEM768-X25519`
with `Nsecret` 32, `Nenc` 1120, `Npk` 1216, and defers the algorithms to
`draft-irtf-cfrg-concrete-hybrid-kems-03`, which states the construction "is identical to
the X-Wing construction". The IANA HPKE KEM Identifiers registry, last updated
2026-04-16, records `0x647A` as X-Wing with reference `draft-connolly-cfrg-xwing-kem-06`
and leaves `0x0001`-`0x000F` unassigned.

The beta provider is assembled in `native/crypto_core/src/mls_beta.rs` from
`mls-rs-crypto-awslc 0.25.0`, which delegates the combiner to `mls-rs-crypto-hpke 0.21.0`.
The rows below were read from the pinned vendored crate sources in the local cargo
registry, not from published documentation.

| Property | `TBD2` KEM `0x647a` (X-Wing) | Vendored `mls-rs` combiner | Evidence |
|---|---|---|---|
| Combiner input order | `SHA3-256(ss_M, ss_X, ct_X, pk_X, XWingLabel)` — label last | `SHA3-256(label, ss_mlkem, ss_2, enc_2, pk_2)` — label first | `mls-rs-crypto-hpke-0.21.0/src/kem_combiner/xwing.rs:100-115` |
| Label bytes | 6 bytes, `5c2e2f2f5e5c` | 7 bytes, `5c2e2f0a2f5e5c` (an embedded `0x0a`) | `mls-rs-crypto-hpke-0.21.0/src/kem_combiner/xwing.rs:107` |
| Traditional contribution | the raw X25519 output | a DHKEM(X25519, HKDF-SHA256) secret: labeled extract-then-expand over the ECDH with `kem_context = enc \|\| pk` under suite ID `"KEM" \|\| 0x0020` | `mls-rs-crypto-hpke-0.21.0/src/dhkem.rs:111-130`; `mls-rs-crypto-awslc-0.25.0/src/lib.rs:377-383` |
| HPKE `kem_id` | `0x647a` | `15` (`0x000F`), carrying the upstream comment `// TODO not set by any RFC` | `mls-rs-crypto-hpke-0.21.0/src/kem_combiner/xwing.rs:149-152` |
| Seed expansion | SHAKE-256 to 96 bytes; the X25519 third is used as the raw scalar | SHAKE-128 to 96 bytes; the X25519 third goes through RFC 9180 `DeriveKeyPair` | `mls-rs-crypto-hpke-0.21.0/src/kem_combiner/xwing.rs:300-313`; `mls-rs-crypto-awslc-0.25.0/src/kdf.rs:144-177`; `mls-rs-crypto-hpke-0.21.0/src/dhkem.rs:208-220` |
| Revision targeted | `-06`, the revision IANA references for `0x647a` | `draft-connolly-cfrg-xwing-kem-01` (2024-01-22), per the combiner's own doc comment | `mls-rs-crypto-hpke-0.21.0/src/kem_combiner/xwing.rs:97` |

The `kem_id` divergence is the widest-reaching one. `0x000F` is bound into the HPKE
`suite_id` (`"HPKE" || kem_id || kdf_id || aead_id`) that every key-schedule
`LabeledExtract`/`LabeledExpand` uses, and into the KEM suite ID (`"KEM" || kem_id`) that
derives `dkp_prk` for every HPKE key pair
(`mls-rs-crypto-hpke-0.21.0/src/hpke.rs:89-103` and `:208-213`). Beta Welcome,
update-path, and application key schedules therefore differ from `TBD2` even where the
ML-KEM-768 and X25519 components agree.

What does match `TBD2`: signature Ed25519, AEAD AES-256-GCM (`0x0002`), KDF HKDF-SHA384
(`0x0002`), hash SHA-384, ML-KEM-768 as the post-quantum component, SHA3-256 as the
combiner hash, the ML-KEM-then-X25519 concatenation order, and the `Npk` 1216 / `Nenc`
1120 / `Nsecret` 32 sizes. The serialized private key differs (2,432 bytes of expanded
key material rather than `Nsk` 32 seed bytes), which is local state only and never
reaches the wire.

Consequences. The beta is a hybrid ML-KEM-768 + X25519 group implementation on a Private
Use identifier; it is not a `TBD2` implementation and cannot be offered as `TBD2`
interoperability evidence. Nothing here weakens or satisfies a production gate: all seven
below remain closed, and adopting the real `TBD2` later is a full protocol migration with
group reinitialization, not a relabelling. Verified against the primary sources listed at
the end of this document on 2026-08-16.

`mls-rs 0.55.3` was published on 2026-08-07. The closed beta deliberately stays on the
locked `0.55.2`/`mls-rs-crypto-awslc 0.25.0` pair; moving the lock is a separate reviewed
dependency decision and is not required by any production gate, all of which remain
blocked above.

### Beta convergence and leave semantics (2026-08-16)

Two beta gaps were researched against RFC 9420 and resolved as far as the toolchain
allows.

**Same-revision forks now converge.** RFC 9420 assumes a delivery service that
serializes commits; this project has none, so ADR-038 makes the canonical branch the
one with the lexicographically smallest control state hash. Siblings are
authenticated, replayed against the reconstructed shared parent, and authorized
before they can influence the outcome. A superseded branch is fork-quarantined and
rejoins by remove/re-add, because an applied MLS commit cannot be rewound.

**Leave is implemented as a two-phase departure.** RFC 9420 section 12.4 forbids a
Commit that removes its own committer, so a departing member cannot evict itself.
Under ADR-039 the leaver signs a non-membership announcement at the current epoch,
which projects it to `left` — departure announced, eviction pending — and the active
owner then commits the `Remove` that evicts the leaves and rotates the epoch to
`removed`. The owner is the deterministic committer because `canLeave` only lets an
owner leave as the last active member. A departed leaf still holds the epoch secret
until that Commit lands, so the eviction is a security obligation and runs
automatically as post-inbox work, one member per group per pass so a partial sweep
stays resumable.

The remaining gates are implementation-dependent and are evidenced only after code
exists: packaged-Android lifecycle and malformed-input fixtures; backend KeyPackage
bucket and last-resort contract tests; crash, transaction-failure, queue-gap, replay,
downgrade, concurrent-commit and fork tests; state-format migration and fuzzing; and an
independent review of the final implementation. Passing any of these does not override a
failed external prerequisite above.

## Selected candidate

The version-1 candidate is the IETF MLS Working Group suite currently named:

`MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519`

This is `TBD2` in `draft-ietf-mls-pq-ciphersuites-06`. It combines X25519 with
ML-KEM-768 for hybrid classical/post-quantum confidentiality, retains Ed25519 to align
with the project's existing device identity, and uses AES-256-GCM with SHA-384.

The full application identity chain is currently Ed25519, so selecting an ML-DSA MLS
signature alone would not make account authentication post-quantum. Version 1 therefore
prioritizes hybrid protection against recorded-ciphertext decryption while keeping one
reviewable identity/signature model. A future post-quantum authentication migration must
cover account master, device, control-event, and MLS signatures together.

No numeric ciphersuite value is assigned by this project. Private-use or historical
experimental values MUST NOT appear in production KeyPackages or groups. When IANA
assigns the suite, that assigned value and the final specification replace `TBD2`
through a reviewed protocol decision before production data exists.

The suite provides post-quantum confidentiality, not post-quantum authentication,
because its signature algorithm remains Ed25519. Product and security wording MUST use
that precise claim.

## Implementation ownership

The shared Rust crypto core owns MLS integration and the cryptographic provider;
Flutter/Dart only calls its narrow Android FFI API in version 1. The same source, locked
dependency versions, serialization, and fixtures must be used by a future Web/Wasm
adapter.

Piece 07 stages only the primitive foundation and Android FFI/isolate adapter. It does
not integrate OpenMLS, create MLS state, or produce KeyPackages. Web crypto remains
fail-closed until the reviewed same-source Wasm adapter and browser fixtures exist in a
post-v1 milestone.

Piece 18 implements the crypto-independent group product model, authorization,
transactional storage boundary, and UI. Piece 19's closed-beta track implements that
existing port and transaction boundary using locked `mls-rs 0.55.2` and
`mls-rs-crypto-awslc 0.25.0` dependencies, draft-06's symmetric and signature mapping over
that provider's own pre-standard hybrid KEM, and Private Use identifier `0xFE4C`. The KEM
is not draft-06's `0x647a`; see "Closed-beta KEM divergence" above. It uses the real beta
backend contracts and durable
recipient-bound pairwise outbox; no MLS secret or shared/raw MLS ciphertext is exposed
to Dart projections or backend metadata.

The beta transport/state format is explicitly disposable and versioned. Production
still resolves only to the unsupported port; the release entry point references a
source-constant closed gate whose constructor assertion prevents an accidental true
value from compiling. OpenMLS remains the production preference, but its documented
supported suites do not include the candidate. If maintained exact support cannot be
produced for the target being released, groups remain disabled; the team does not
replace the suite with classical MLS or ship newly invented cryptography.

## Production gates

All of these are mandatory:

1. **Primitive mapping.** Every primitive in the selected mapping — hybrid KEM, KDF, AEAD,
   hash, and signature — is assigned in the registry that owns it, and each assignment's
   normative reference is a published, non-expiring specification rather than an
   Internet-Draft revision.
2. **MLS suite identifier.** The ciphersuite itself has a final stable specification and an
   IANA-assigned value in the "MLS Cipher Suites" registry, and that assigned value is what
   the client emits. No Private Use, GREASE, or experimental value ever stands in for it,
   and this project never assigns one locally.
3. A maintained OpenMLS/provider combination implements the final KEM, KDF, AEAD, hash,
   and signature mappings without a project-local cryptographic fork.
4. For version 1, KeyPackage, Welcome, Commit, Proposal, epoch, exporter, serialization,
   persistence, malformed-input, and downgrade fixtures pass on Android. A future Web
   release additionally requires byte-identical Android/Web fixtures.
5. The padded KeyPackage representation fits the backend's 4,096/16,384-byte buckets,
   including the last-resort behavior.
6. Crash-safe state persistence, queue-gap removal/re-add, and concurrent-commit/fork
   handling pass the full multi-device matrix.
7. An independent cryptographic review closes all blocking findings.

Gates 1 and 2 are evidenced separately because different registries own them, on
independent schedules: the primitive identifiers live in the IANA HPKE and TLS registries
and in NIST publications, while the suite value lives in the IANA MLS Cipher Suites
registry. Both are currently open. Closing gate 1 does not open gate 2, and gate 2 cannot
be reached by any work inside this project. The per-identifier evidence, with registration
policies and registry dates, is in "Per-identifier registry evidence" above.

No production KeyPackage is uploaded until these gates pass. A future change of suite
is an explicit protocol migration and group reinitialization, never silent negotiation.

## Authoritative references

- [IETF MLS cipher suites with ML-KEM draft](https://datatracker.ietf.org/doc/draft-ietf-mls-pq-ciphersuites/)
- [Post-quantum KEMs for HPKE (`draft-ietf-hpke-pq`), the source of `TBD2`'s KEM `0x647a`](https://datatracker.ietf.org/doc/draft-ietf-hpke-pq/)
- [Concrete hybrid KEMs (`draft-irtf-cfrg-concrete-hybrid-kems`), which defines that construction](https://datatracker.ietf.org/doc/draft-irtf-cfrg-concrete-hybrid-kems/)
- [X-Wing KEM (`draft-connolly-cfrg-xwing-kem`), the IANA reference for `0x647A`](https://datatracker.ietf.org/doc/draft-connolly-cfrg-xwing-kem/)
- [IANA MLS registry, which owns the unassigned suite value](https://www.iana.org/assignments/mls/mls.xhtml)
- [IANA HPKE registry, which owns the KEM, KDF, and AEAD identifiers](https://www.iana.org/assignments/hpke/hpke.xhtml)
- [IANA TLS parameters registry, which owns the `ed25519` SignatureScheme `0x0807`](https://www.iana.org/assignments/tls-parameters/tls-parameters.xhtml)
- [RFC 5869 (HKDF), the reference IANA records for KDF `0x0002`](https://www.rfc-editor.org/rfc/rfc5869)
- [NIST SP 800-38D (GCM), the reference IANA records for AEAD `0x0002`](https://doi.org/10.6028/NIST.SP.800-38D)
- [NIST FIPS 180-4 (Secure Hash Standard), which specifies SHA-384](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
- [RFC 9846 (TLS 1.3), the reference IANA records for `ed25519`](https://www.rfc-editor.org/rfc/rfc9846)
- [RFC 9847 (IANA registry updates for TLS and DTLS), for the `Recommended` column policy](https://www.rfc-editor.org/rfc/rfc9847)
- [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420)
- [RFC 9180 (HPKE), for the `suite_id` and `DeriveKeyPair` behavior cited above](https://www.rfc-editor.org/rfc/rfc9180)
- [OpenMLS](https://github.com/openmls/openmls)
- [MLS Working Group interoperability vectors](https://github.com/mlswg/mls-implementations/tree/main/test-vectors)
