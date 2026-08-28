# Post-quantum MLS profile

## Status

This document owns the Flutter client's group-ciphersuite decision. The algorithm
profile is selected, but it is not yet a production wire contract. ADR-036 permits a
real isolated closed-beta implementation with disposable state and a Private Use suite
identifier. That closed beta implements the selected profile's symmetric and signature
choices but not its hybrid KEM. ADR-040 resolves that the beta KEM is not changed;
"Closed-beta KEM divergence from TBD2" is the complete, binding record of the difference
and "Why the beta KEM is not being corrected in place" is the summary of that decision.
Production still resolves the unsupported adapter, keeps the source-only production gate
closed, and cannot create a group or upload a KeyPackage.

Status last verified on 2026-08-17 against IETF draft revision 06, the IANA MLS
ciphersuite registry, the IANA HPKE KEM, KDF, and AEAD registries, the IANA TLS
SignatureScheme registry, NIST FIPS 180-4, `draft-ietf-hpke-pq`,
`draft-irtf-cfrg-concrete-hybrid-kems`, `draft-connolly-cfrg-xwing-kem`, the pinned
vendored `mls-rs` crate sources, the crates.io version index for `mls-rs`, `openmls`, and
the `mls-rs` crypto crates, the OpenMLS supported-ciphersuite list, and the MLS Working
Group interoperability-vector repository. Every Phase-A prerequisite result below is
unchanged from the 2026-08-16 audit; the 2026-08-17 pass re-verified the KEM divergence
against the draft text and the pinned sources line by line and extended it (rows D5, D7,
D8, and the no-upstream-fix finding are new).

A 2026-08-18 pass attempted cross-implementation interoperability against a second,
independent MLS implementation and determined it externally blocked; see "Cross-implementation
interoperability determination" below. That pass re-verified the IANA HPKE KEM registry
(`0x0001`-`0x000F` still Unassigned, `0x647A` still X-Wing at
`draft-connolly-cfrg-xwing-kem-06`, registry still dated 2026-04-16), the crates.io version
indexes for the pinned `mls-rs` crypto crates and for `openmls`, `draft-connolly-cfrg-xwing-kem-10`,
and the MLS working group's `implementation_list.md`. **It corrects Phase-A row 3**: OpenMLS's
unreleased `main` branch now implements `TBD2`'s exact five-primitive mapping at a provisional
code point. No prerequisite result and no gate changed.

### Phase-A external preflight (2026-08-16; re-verified unchanged 2026-08-17)

These prerequisites exist outside this implementation and cannot be made true by adding
more project code. All five remain blocked. The single row that previously combined "final
stable specification and IANA-assigned suite identifier" is now two rows, because the
primitive mapping and the MLS suite value are held in different registries with different
owners, different registration policies, and independent completion paths; that split
changes evidence granularity only. No prerequisite result has changed since 2026-08-09; the
2026-08-17 recheck of the IANA MLS and HPKE registries, `draft-ietf-mls-pq-ciphersuites`,
`draft-ietf-hpke-pq`, `draft-irtf-cfrg-concrete-hybrid-kems`,
`draft-connolly-cfrg-xwing-kem`, and the crates.io indexes for `openmls` and the `mls-rs`
crates found all five still blocked, with the same evidence.

| External prerequisite | Current primary-source evidence | Result | Consequence |
|---|---|---|---|
| Stable published specification and registry assignment for every primitive in the selected mapping | Four of the five primitives already rest on published, non-expiring standards and are assigned in registries this project does not control: KDF `0x0002` (HKDF-SHA384, reference RFC 5869) and AEAD `0x0002` (AES-256-GCM, reference NIST SP 800-38D) in the IANA HPKE registries, last updated 2026-04-16; signature `ed25519` `0x0807` (`Recommended = Y`, reference RFC 9846) in the IANA TLS SignatureScheme registry, last updated 2026-08-10; and hash SHA-384, which carries no code point at all and is named directly from NIST FIPS 180-4. The hybrid KEM is the exception. `0x647A` is assigned in the IANA HPKE KEM Identifiers registry, but the only normative reference recorded there is `draft-connolly-cfrg-xwing-kem-06`, an Independent-submission Internet-Draft; that draft has since advanced to `-10` (2026-03-02, expiring 2026-09-03) without the registry reference following it, and the chain draft-06 uses to reach it — `draft-ietf-hpke-pq-05` and `draft-irtf-cfrg-concrete-hybrid-kems-04`, the latter in datatracker state `I-D Exists::Revised I-D Needed` — is still moving. | **Blocked** (one primitive of five) | The mapping cannot be frozen as a production wire contract while its KEM rests on a superseded, expiring draft revision. This prerequisite blocks and clears independently of any MLS Cipher Suites action, which is why it is evidenced separately from the row below. |
| Final MLS specification and an IANA-assigned MLS ciphersuite value | `draft-ietf-mls-pq-ciphersuites-06`, published 2026-07-21, is still an expiring Standards Track Internet-Draft (expires 2027-01-22). Its datatracker state is "I-D Exists", annotated "Waiting for WG Chair Go-Ahead" and "Revised I-D Needed - Issue raised by WG", so the text is expected to change again. Its IANA Considerations request entries in the "MLS Cipher Suites" registry only and request nothing in the HPKE registries. The selected suite is still `TBD2`; that registry, last updated 2025-11-17, contains only `0x0000` RESERVED, RFC 9420 values `0x0001`-`0x0007`, the GREASE values, and Private Use `0xF000`-`0xFFFF`. No post-quantum suite is registered. | **Blocked** | No production suite value, KeyPackage, or group may be emitted. The registry's Specification Required policy is not a route this project may take: ADR-026 forbids assigning a production identifier locally, so this closes only when the working group's document becomes a stable specification and IANA assigns the value that replaces `TBD2`. No amount of primitive-level progress advances it. |
| Maintained non-project-local OpenMLS/provider support for the exact final Android mapping | OpenMLS 0.8.1 (2026-02-13) remains the newest stable release and 0.9.0-rc.2 (2026-08-06) is still a release candidate; both still document only the three classical RFC 9420 suites. OpenMLS's *released* post-quantum work targets X-Wing (`MLS_256_XWING_CHACHA20POLY1305_SHA256_Ed25519`, experimental `0x004D`, with no IANA code point), whose AEAD, KDF, and hash differ from `TBD2`; its KEM does not differ, because `TBD2`'s own KEM `0x647a` *is* X-Wing. **Corrected 2026-08-18:** that statement no longer describes OpenMLS's `main` branch, which adds `MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519 = 0x004E`, annotated in-source as "[draft-ietf-mls-pq-ciphersuites] TBD2 (provisional code point)", mapping to `HpkeKemType::XWingKemDraft6`, `HpkeKdfType::HkdfSha384`, `HpkeAeadType::AesGcm256`, `HashType::Sha2_384`, and Ed25519 — `TBD2`'s exact five-primitive mapping. It is gated behind the `draft-ietf-mls-pq-ciphersuites` cargo feature and is **unreleased**: the newest published versions on crates.io (checked 2026-08-18) are still 0.8.1 and 0.9.0-rc.2. A provisional code point on an unreleased branch is not the assigned value gate 2 requires and is not a maintained release gate 3 can rest on, so the result is unchanged; but the gap is now a release-and-registry gap rather than a mapping gap, and this row previously misstated that. `mls-rs` exposes `CipherSuite::ML_KEM_768_X25519` at Private Use `0xFE4C`, but the mapping this project assembles through the maintained public `AwsLcCipherSuiteBuilder` API is not `TBD2`: its symmetric half matches and its hybrid KEM does not, as evidenced under "Closed-beta KEM divergence" below. No *released* maintained provider implements `TBD2`: released OpenMLS has the right KEM (X-Wing *is* `0x647a`) on the wrong AEAD/KDF/hash, and `mls-rs` has the right AEAD/KDF/hash on a pre-standard KEM. The pinned `mls-rs` crypto crates are already the newest published versions (re-checked on crates.io 2026-08-18: `mls-rs-crypto-hpke 0.21.0`, `mls-rs-crypto-awslc 0.25.0`, and `mls-rs-crypto-traits 0.22.0` are each still the newest of their crate), so no upstream fix is available to adopt. | **Blocked** | The closed beta may use the locked maintained `mls-rs` provider under ADR-036, but composing the mapping ourselves does not satisfy the production OpenMLS/provider gate. No project-local cryptographic fork is permitted, and ADR-040 records that supplying a conformant KEM through `mls-rs`'s public extension points would be one — the maintained cipher suite cannot be re-parameterized, so the project would have to author the KEM itself. |
| Usable upstream interoperability vectors for the selected suite | The MLS Working Group vector repository still exposes only its classical fixture set (`crypto-basics`, `key-schedule`, `message-protection`, `messages`, `passive-client-*`, `psk_secret`, `secret-tree`, `transcript-hashes`, `tree-*`, `treekem`, `welcome`). No ML-KEM/PQ fixture set exists. | **Blocked** | Project lifecycle fixtures are useful beta evidence but cannot substitute for independent upstream interoperability. The construction-level project vectors added on 2026-08-17 (see "Known-answer coverage of the divergent construction") do not change this: they are project-generated regression pins for a construction no external party publishes vectors for, so they are not upstream vectors and do not advance this prerequisite. Nor can cross-implementation interoperability stand in for them: the 2026-08-18 assessment below found that no independent implementation can be configured to the beta composition at all, because its KEM is unpublished and has exactly one implementation. |
| Qualified independent reviewer available for the final implementation | No named, retained reviewer and no review schedule is recorded for this project, and no candidate has been approached. A qualification bar, a scope of work bounded to this implementation, the deliverables required before the review gate can close, and an evaluation of candidates and funding routes against that bar were recorded on 2026-08-18 in [the engagement document](independent-review-engagement.md); it retains nobody and moves no gate. | **Blocked** | Review-dependent production gates cannot close until a qualified reviewer is engaged and all blocking findings are resolved. |

#### Per-identifier registry evidence (verified 2026-08-16; the HPKE KEM/KDF/AEAD and MLS ciphersuite rows re-verified unchanged 2026-08-17)

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

### Closed-beta KEM divergence from TBD2 (complete set, verified 2026-08-17)

The closed beta does not implement `TBD2`, and no beta artifact ever has. Its signature,
AEAD, KDF, and hash choices match `TBD2` exactly; its hybrid KEM does not. **ADR-040
resolves that the beta KEM is not changed** and makes this section the binding record of
the divergence. Nothing in it opens, weakens, or partially satisfies a production gate.

`TBD2` names HPKE KEM `0x647a`. The normative chain for that code point is
`draft-ietf-mls-pq-ciphersuites-06`, which takes its hybrid KEMs from
`draft-ietf-hpke-pq-05` (2026-07-06); that draft registers `0x647a` as `MLKEM768-X25519`
with `Nsecret` 32, `Nenc` 1120, `Npk` 1216, and defers the algorithms to
`draft-irtf-cfrg-concrete-hybrid-kems` — cited there at `-03`, now at `-04` (2026-07-06,
expires 2027-01-07, datatracker state `I-D Exists::Revised I-D Needed`), which states the
construction "is identical to the X-Wing construction" and references
`draft-connolly-cfrg-xwing-kem-10`. The IANA HPKE KEM Identifiers registry, last updated
2026-04-16, still records `0x647A` as X-Wing with reference
`draft-connolly-cfrg-xwing-kem-06` and leaves `0x0001`-`0x000F` unassigned.

The beta provider is assembled in `native/crypto_core/src/mls_beta.rs` from
`mls-rs-crypto-awslc 0.25.0`, which delegates the combiner to `mls-rs-crypto-hpke 0.21.0`.
Every "vendored" row below was read from the pinned crate sources in the local cargo
registry, not from published documentation; every `TBD2` row was read from the X-Wing draft
text itself. `-06` (the revision IANA records for `0x647a`) and `-10` (current) agree on
every row in this table. In the evidence column an unqualified filename means
`mls-rs-crypto-hpke-0.21.0/src/`; anything in the aws-lc crate is spelled out in full.

| # | Property | `TBD2` KEM `0x647a` (X-Wing) | Vendored `mls-rs` combiner | Evidence |
|---|---|---|---|---|
| D1 | Combiner input order | `SHA3-256(ss_M, ss_X, ct_X, pk_X, XWingLabel)` — label last in both `-06` and `-10` | `SHA3-256(label, ss_mlkem, ss_2, enc_2, pk_2)` — label first, the pre-`-05` layout | `xwing.rs:100-115`; X-Wing `-06`/`-10` Combiner; `-10` changelog G.4 "Move label at the end" |
| D2 | Label bytes | 6 bytes, `5c2e2f2f5e5c` | 7 bytes, `5c2e2f0a2f5e5c` (an embedded `0x0a`) | `xwing.rs:107`; X-Wing `-10` "XWingLabel is given by `5c2e2f2f5e5c`" |
| D3 | Traditional contribution `ss_X` | the raw X25519 output, `X25519(ek_X, pk_X)` | a DHKEM(X25519, HKDF-SHA256) secret: `LabeledExpand(LabeledExtract("", "eae_prk", dh), "shared_secret", enc \|\| pk, 32)` under suite ID `"KEM" \|\| 0x0020` with the `HPKE-v1` prefix | `dhkem.rs:111-130`; `kdf.rs:76-86`; `mls-rs-crypto-awslc-0.25.0/src/lib.rs:377-383`; `mls-rs-crypto-traits-0.22.0/src/kem.rs:86` |
| D4 | HPKE `kem_id` | `25722` (`0x647a`) | `15` (`0x000F`), unassigned at IANA, carrying the upstream comment `// TODO not set by any RFC` | `xwing.rs:149-152`; IANA HPKE KEM registry (2026-04-16); X-Wing `-10` `kem_id` 25722 |
| D5 | `DeriveKeyPair` structure | `GenerateKeyPairDerand(SHAKE256(ikm, 32))` — no HPKE `dkp_prk` step exists | an extra `dkp_prk = LabeledExtract("", "dkp_prk", ikm)` under `"KEM" \|\| 0x000F` with HKDF-SHA384, then the seed expansion below | `hpke.rs:208-213`; `kdf.rs:39-51`; X-Wing `-10` `DeriveKeyPair` |
| D6 | Seed expansion | `SHAKE256(sk, 96)`, split `[0:32]`/`[32:64]`/`[64:96]` | `SHAKE-128(dkp_prk, 96)`, split `64`/`32` | `xwing.rs:300-313`; `mls-rs-crypto-awslc-0.25.0/src/kdf.rs:144-177` (`EVP_shake128`); X-Wing `-10` `expandDecapsulationKey` |
| D7 | X25519 key derivation | `sk_X = expanded[64:96]`, used directly as the scalar | the 32-byte half goes through RFC 9180 `DeriveKeyPair`, `LabeledExpand(·, "sk", "", 32)` under `"KEM" \|\| 0x0020` | `dhkem.rs:208-220`; `dhkem.rs:82-91`; X-Wing `-10` `expandDecapsulationKey` |
| D8 | Encapsulation-key check | "ML-KEM-768.Encaps(pk_M) **MUST** perform the encapsulation key check of [MLKEM] §7.2 and raise an error if it fails" | the combined KEM performs no validation of its own — `public_key_validate` returns `Ok(())` with `// TODO Not clear how to do this for Kyber`; whatever checking occurs is whatever `aws_lc_rs::kem::EncapsulationKey::new` does internally at encap time, and the MLS-visible validation hook is a no-op | `xwing.rs:242-245`; `mls-rs-crypto-awslc-0.25.0/src/kem/ml_kem.rs:79,142-144`; X-Wing `-10` §4 |
| D9 | Serialized private key | `Nsk` 32 (a seed; the decapsulation key is re-expanded or cached) | 2,432 bytes of expanded material: ML-KEM-768 `dk` 2,400 `\|\|` X25519 32. Local state only; never on the wire | `mls-rs-crypto-awslc-0.25.0/src/kem/ml_kem.rs:167-173`; `xwing.rs:271-290` |
| D10 | Revision targeted | `-06` is what IANA records for `0x647a`; `-10` (2026-03-02) is current | `draft-connolly-cfrg-xwing-kem-01`, per the combiner's own doc comment — five revisions behind `-06`, nine behind `-10` | `xwing.rs:97` |

`kem_id` (D4) is the widest-reaching divergence, and it is the reason the others cannot be
treated as cosmetic. `0x000F` is bound into the HPKE `suite_id`
(`"HPKE" || kem_id || kdf_id || aead_id`) that every key-schedule
`LabeledExtract`/`LabeledExpand` consumes, and into the KEM suite ID (`"KEM" || kem_id`)
that derives `dkp_prk` for every HPKE key pair (`hpke.rs:89-103` and `:208-213`). It
therefore reaches every beta Welcome, every update-path node key, every KeyPackage init
key, and every HPKE export — so beta key schedules differ from `TBD2` even where the
ML-KEM-768 and X25519 components agree. The inner DHKEM keeps its own correct
`"KEM" || 0x0020` suite ID (`dhkem.rs:51`), so `0x000F` sits only at the outer layer —
which is the layer MLS actually uses.

What does match `TBD2`, re-verified on 2026-08-17: signature Ed25519, AEAD AES-256-GCM
(`0x0002`), KDF HKDF-SHA384 (`0x0002`), hash SHA-384, ML-KEM-768 as the post-quantum
component seeded from a 64-byte `(d ‖ z)` input through aws-lc's deterministic ML-KEM
keygen, SHA3-256 as the combiner hash, the ML-KEM-then-X25519 concatenation order,
`enc = ct_M ‖ ct_X` with `ct_X` the ephemeral X25519 public key, and the `Npk` 1216 /
`Nenc` 1120 / `Nsecret` 32 sizes. Because those sizes are byte-identical between the two
constructions, the divergence is silent on the wire: a mismatched peer or a stale stored
key fails at decryption, never at parsing, so the beta state-format version — not any
length check — is what must reject incompatible state.

The divergence cannot be closed by moving the dependency pin. Checked against crates.io on
2026-08-17, the pinned `mls-rs-crypto-hpke 0.21.0`, `mls-rs-crypto-awslc 0.25.0`, and
`mls-rs-crypto-traits 0.22.0` are each the newest published version of their crate (all
published 2026-04-21), so the newest maintained `mls-rs` provider still ships the
`draft-01` combiner and `kem_id` 15. `mls-rs 0.55.3` (2026-08-07) supersedes the locked
`0.55.2`, but its crypto crates are unchanged; moving that lock is a separate reviewed
dependency decision and is not required by any production gate.

Consequences. The beta is a hybrid ML-KEM-768 + X25519 group implementation on a Private
Use identifier; it is not a `TBD2` implementation and MUST NOT be offered as `TBD2`
interoperability evidence. Nothing here weakens or satisfies a production gate: all seven
below remain closed, and adopting the real `TBD2` later is a full protocol migration with
group reinitialization, not a relabelling. Verified against the primary sources listed at
the end of this document on 2026-08-17.

Because ADR-040 changes nothing, no reinitialization is triggered now: the beta state
format, transport v3, schema v11, sealed key-package snapshots, sealed group state, and
existing beta groups all stay valid. Whenever the KEM does change — by adopting `0x647a`
or by migrating providers — the cost is fixed by D4, D5, and D9 above and is the same in
either direction:

- every stored HPKE key pair is bound to `kem_id 0x000F` through `dkp_prk`, and every
  epoch's key schedule is bound to it through the HPKE `suite_id`, so no stored beta key
  or epoch secret survives;
- the serialized private-key layout changes (2,432 bytes to `Nsk` 32), so sealed
  key-package and group snapshots must be reinitialized, not migrated;
- uploaded beta KeyPackages, consumable and last-resort, must be replaced rather than
  reused, and in-flight queued group objects must be dropped;
- every beta group must be recreated and re-invited; and
- the beta state-format version must reject the old state explicitly, because `Npk` and
  `Nenc` are unchanged and nothing would fail at parse time.

This is the disposability rule ADR-036 established and ADR-037 already exercised for
v2 to v3. It is a closed-beta reinitialization, never a production migration.

#### Known-answer coverage of the divergent construction (2026-08-17)

The divergence above is now pinned by tests rather than only recorded in prose.
`native/crypto_core/vectors/beta-hybrid-kem-project-kats.json` and
`native/crypto_core/src/beta_kem_vectors.rs` add construction-level coverage of the
hybrid KEM and its HPKE integration: `kem_derive` to exact bytes, a full
deterministic encapsulation, key schedule, ciphertext, and exporter output, and
probes that demonstrate D1, D2, D3, D4, and D8 as computed facts.

**Those vectors are project-generated and are not external conformance evidence.**
Official construction-level vectors do not exist for this construction and cannot
be obtained, because the construction is not a published one — that is what rows
D1-D10 say. There is no registry entry, RFC, or Internet-Draft whose vectors it is
supposed to reproduce, and RFC 9180's DHKEM vectors do not reach it either, since
the inner `DHKEM(X25519, HKDF-SHA256)` is wrapped by a combiner whose `kem_id` is
`0x000F`. ADR-040 makes that gap permanent for the closed beta rather than pending,
so the vectors are a regression pin: they detect change in a construction that is
silent on the wire and would otherwise fail only at decryption. They must never be
cited as `TBD2`, `0x647a`, X-Wing, or RFC 9180 conformance or interoperability
evidence, and they close no production gate.

What keeps them auditable rather than circular is that every expected value is
re-derivable from the case inputs, and the tests re-derive it on ML-KEM-768,
X25519, and HKDF implementations that are not AWS-LC — `mlkem-native`,
`x25519-dalek`, and the RustCrypto `hkdf`/`sha2` crates — with the reference
sealing the ciphertext the implementation then opens. The reproduction confirmed
the implementation performs exactly the construction rows D1-D10 describe; no
mismatch was found and no cryptographic code was changed. One step is pinned but
not reproduced: the SHAKE-128 seed expansion of D6, because no dependency exposes
SHAKE and ADR-040 declines project-local `unsafe` FFI to reach it.
`native/crypto_core/vectors/README.md` states per test what is and is not proven.

### Cross-implementation interoperability determination (2026-08-18)

Interoperating the closed-beta suite against a second, independent MLS implementation was
attempted and is **externally blocked**. No harness was built, because the prerequisite
that a harness would exercise cannot be satisfied by any candidate. This is a structural
result, not a scheduling one: it does not clear when a maintainer ships a release, and no
amount of project code changes it.

The exact composition a second implementation would have to be configured to is the one
`BetaMlsCryptoProvider` builds in `native/crypto_core/src/mls_beta.rs`: MLS ciphersuite
identifier `0xFE4C`, KDF HKDF-SHA384, AEAD AES-256-GCM, hash SHA-384, signature Ed25519,
and the hybrid KEM described by rows D1-D10 above — `mls-rs`'s `CombinedKem` at HPKE
`kem_id` `0x000F`, label-first, 7-byte label `5c2e2f0a2f5e5c`, an inner
`DHKEM(X25519, HKDF-SHA256)` shared secret, SHAKE-128 `DeriveKeyPair` expansion, and no
encapsulation-key check.

The eleven implementations on the MLS working group's `implementation_list.md` (fetched
2026-08-18) were assessed against that composition. Every one of them fails on the KEM,
and for the same reason: **the beta KEM is not a published construction.** It has no
specification, no IANA code point, and exactly one implementation in existence — the
`mls-rs-crypto-hpke` crate this project already depends on. A second implementation
cannot be *configured* to a construction that no specification describes; it could only
be made to perform it by someone authoring the algorithm inside it. That is not
configuration, and it would destroy the independence that makes the exercise evidence at
all, because the KEM under test would then be code written by this project from its own
reading of the crate under test.

| Candidate | Language | Identifier `0xFE4C` | KDF/AEAD/hash/signature | Beta KEM | Precise gap |
|---|---|---|---|---|---|
| OpenMLS | Rust | **No** — `Ciphersuite` is a closed `#[repr(u16)]` enum; `TryFrom<u16>` returns `DecodingError` for any unlisted value | Yes, as one suite: `main` defines `MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519 = 0x004E` mapping to `HkdfSha384`, `AesGcm256`, `Sha2_384`, Ed25519 | **No** — that suite's KEM is `HpkeKemType::XWingKemDraft6`, the conformant X-Wing, which is precisely what rows D1-D10 say the beta KEM is not | Identifier unrepresentable and `HpkeKemType` is a closed enum with no `0x000F` variant. Its PQ suites are also unreleased and feature-gated behind `draft-ietf-mls-pq-ciphersuites` |
| MLSpp | C++ | Partially — `CipherSuite` wraps a `uint16_t` `enum struct ID`, so the value can be *held*, but the private `get()` is a fixed lookup and `all_supported_cipher_suites` is a fixed `std::array`, so nothing binds primitives to it | Yes, as one suite: `MLKEM768X25519_AES256GCM_SHA384_Ed25519 = 0x0008` | **No** — same X-Wing/ML-KEM hybrid, not the `0x000F` combiner | No registration API; primitives are bound to IDs in private source. Would require editing MLSpp |
| ts-mls | TypeScript | **Yes** — `CryptoProvider.getCiphersuiteImpl(id: number)` accepts an arbitrary number and `CiphersuiteImpl.id` is `number` | **Yes** — `Kdf`, `Hash`, `Signature`, and AEAD are interfaces; `HKDF-SHA384`, `SHA-384`, `AES256GCM`, and `Ed25519` all ship | **No** — `KemAlgorithm` is a closed union of nine, and no shipped `Hpke` implements the `0x000F` combiner | The one candidate configurable on five of six requirements. Fails only on the KEM, and only because supplying it means authoring it |
| BouncyCastle | Java | Partially — the `MlsCipherSuite` constructor is public and takes a `short` id, but `getSuite(short)` is a fixed switch | Partially — `BcMlsKdf(SHA384Digest)` and `BcMlsAead(aead_AES_GCM256)` exist, but no Ed25519 + SHA-384 suite is assembled | **No** — only the seven classical RFC 9420 suites; `org.bouncycastle.crypto.hpke.HPKE` exposes a fixed `kem_*` set with no combiner | No post-quantum MLS support of any kind |
| mls-kotlin | Kotlin | **No** — closed `enum class CipherSuite`; Kotlin enums cannot be extended at runtime | **No** — no Ed25519 + SHA-384 combination | **No** — no ML-KEM at all | Seven classical suites plus GREASE only |
| mls-go | Go | Not reached | Not reached | **No** — no ML-KEM; documented interop covers suites 1, 2, 3 | No post-quantum support |
| go-mls | Go | Not reached | Not reached | **No** — no ML-KEM | "RFC in progress"; no post-quantum support |
| mls_stuff | Python | Not reached | Not reached | **No** — no ML-KEM | Self-described work in progress; incomplete RFC 9420 support |
| MLS\* | F\* | Not reached | Not reached | **No** | "RFC in progress"; no post-quantum support and no obtainable artifact |
| RingCentral | C++ | Not reached | Not reached | Not reached | Proprietary and unpublished; cannot be obtained or pinned at any revision |
| mls-rs | Rust | Yes | Yes | Yes | **Not independent.** It is this implementation's own provider. Running it against itself is a round trip, which `beta_mls_vectors.rs` already performs |

Two findings came out of the assessment and are recorded as findings rather than acted on:

- **Gate 3's evidence has moved, and this document's Phase-A row 3 is corrected above.**
  OpenMLS `main` now implements `TBD2`'s exact five-primitive mapping — the claim that it
  had "the right KEM on the wrong AEAD/KDF/hash" is true only of its *released* versions.
  It is unreleased, feature-gated, and at a provisional code point, so gate 3 does not
  close; but the direction of travel is real and the row should not misstate it.
- **The ecosystem has not converged on a provisional value.** OpenMLS uses `0x004E` for
  `TBD2` and MLSpp uses `0x0008` for the same composition. Two independent implementations
  picked two mutually incompatible code points for one suite. That is exactly the failure
  mode gate 2 exists to prevent, and it is direct evidence that gate 2 cannot be
  satisfied by adopting anyone's provisional value.

One further observation is recorded but **not traced to the wire**: OpenMLS's
`HpkeKemType::XWingKemDraft6` carries the discriminant `0x004D`, which is not X-Wing's
registered HPKE `kem_id` `0x647A` (25722). Whether that discriminant reaches the HPKE
`suite_id` was not followed into its crypto backends, and nothing in this project depends
on the answer. It is noted only so that a future reader does not assume OpenMLS's `0x004E`
is wire-compatible with a conformant `0x647a` peer without checking.

What remains externally blocked, precisely: **cross-implementation interoperability
evidence for the closed-beta suite is unobtainable for as long as the beta KEM is the
`mls-rs` `0x000F` combiner.** It is not blocked on a missing release, a missing fixture,
or a missing counterparty — it is blocked because the construction has no second
implementation and can have none without someone writing one. ADR-040 makes that
condition permanent for the closed beta rather than pending. The route that would unblock
it is the same upstream event ADR-040 already names as its reversal trigger: a maintained
provider implementing `0x647a` against a stable specification, at which point a second
implementation configured to the same published suite becomes possible for the first time.

Interoperating with a second implementation under a Private Use identifier would in any
case be **cross-implementation evidence, not upstream interoperability.** It would not
satisfy Phase-A prerequisite 4 and would close none of the seven production gates: a
Private Use value is by definition not the assigned value gate 2 requires, and agreement
between two parties on an unregistered construction is not conformance to a published
one. Had a candidate been configurable, the result would have been recorded under that
constraint. None was.

### Why the beta KEM is not being corrected in place (ADR-040, 2026-08-17)

A conformant `0x647a` KEM cannot be reached through the maintained provider. The public
extension points that do exist — `mls_rs::CryptoProvider`,
`mls_rs_core::crypto::CipherSuiteProvider`, `mls_rs_crypto_traits::{KemType, DhType, Hash,
VariableLengthHash}`, `CombinedKem::new_custom` with a project `SharedSecretHashInput`, and
the public aws-lc primitive constructors including the 64-byte `(d ‖ z)` deterministic
ML-KEM keygen — are real and would not require editing one line of vendored source. They
are nevertheless not a route this project may take:

- `AwsLcCipherSuite` cannot be re-parameterized. Its fields are private and the
  `AwsLcHpke` enum is private (`mls-rs-crypto-awslc-0.25.0/src/lib.rs:80`); both hybrid
  builder entry points hard-code `CombinedKem::new_xwing` (`:243-290`). There is no way to
  hand the maintained cipher suite a different KEM, so the project would have to implement
  the ~25-method `CipherSuiteProvider` itself, at the most security-sensitive layer in the
  build.
- That needs `mls_rs_crypto_hpke::{hpke::Hpke, context::{ContextS, ContextR}}`, which
  `mls-rs-crypto-awslc` imports privately and does not re-export (`:38-42`, `:51`), so it
  requires a new direct dependency; and `HpkeKdf` is `pub(crate)`, so the labeled-KDF
  helpers would have to be rewritten too.
- SHAKE-256 (D6) is not reachable from any current dependency's safe API — the awslc crate
  exposes only `AwsLcShake128` — so it would require project-local `unsafe` FFI against
  `aws-lc-sys`.

Under gate 3 that route is a project-local cryptographic fork even though no vendored file
would change, because gate 3 requires that *a maintained provider implements* the mapping,
and here the project would author and own the combiner, the raw-X25519 KEM, the SHAKE-256
expansion, and the encapsulation-key check. It would not be invented cryptography — X-Wing
is specified and has published vectors — but it is exactly the "custom, unaudited
cryptographic implementation" ADR-017 names, and ADR-036 permits only maintained external
implementations. Selecting and composing maintained primitives, which is what
`combined_hpke` already does, stays on the right side of that line; authoring a KEM's own
algorithm steps does not. ADR-040 carries the full reasoning and the rejected alternatives.

The reversal trigger is written down and is an upstream event, not a project task: a
maintained provider implements `TBD2`'s KEM `0x647a` against a stable, non-expiring
specification. That is gates 1 and 3 below.

### Beta convergence and leave semantics (2026-08-16)

Two beta gaps were researched against RFC 9420 and resolved as far as the toolchain
allows.

**Same-revision forks now converge.** RFC 9420 assumes a delivery service that
serializes commits; this project has none, so the canonical branch is chosen on the
client. Siblings are authenticated, replayed against the reconstructed shared parent,
and authorized before they can influence the outcome. A superseded branch is
fork-quarantined and rejoins by remove/re-add, because an applied MLS commit cannot be
rewound. ADR-038 originally ordered siblings by the lexicographically smallest control
state hash; **ADR-041 (2026-08-17) supersedes that**, because the hash is a SHA-256 over
a descriptor whose event id and `created_ms` the author chooses freely, measured at about
24,500 candidate branches per second per core, so a member facing eviction could grind a
branch that displaced its own `Remove`. The order now reads the operation's precedence
class first — an eviction is never displaced by an invite, a leave, or a metadata edit —
then the signer's role in the shared parent, then the authenticated signer identity, and
only then the hash, which is reachable solely between two branches signed by one device.

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
downgrade, concurrent-commit and fork tests; state-format migration fuzzing; and an
independent review of the final implementation. Passing any of these does not override a
failed external prerequisite above.

Input-boundary fuzzing of the closed-beta operation is no longer outstanding and is
evidenced below; state-format *migration* fuzzing, which drives a state written by one
released format version into a later reader, is a different exercise and remains open.
The device-local half of the crash and transaction-failure matrix is also evidenced below.
Its physical-device half — process kill, Doze and force-stop, torn writes, Keystore
availability after reboot, and the packaged Rust core — has not been run and is the larger
part of gate 6. The packaged-core cell of it is also the condition ADR-055 put in front of
the closed-beta group surface reaching a user at all, and ADR-056 satisfied that condition
for `arm64-v8a` on 2026-08-24. **It does not satisfy gate 6**, which additionally needs
process kill, Doze and force-stop, torn writes and Keystore availability after reboot —
none of which has been run.

### Closed-beta MLS input fuzzing (2026-08-18)

Every decoder reachable from `cp_crypto_v1_beta_mls_operation` is fuzzed by an in-crate
harness (`native/crypto_core/src/mls_beta/fuzz.rs`, documented in
`native/crypto_core/fuzz/README.md`). Twelve targets cover the C ABI entry with its input
and output bounding, the request envelope, relay-served peer device bundles, published
`KeyPackage` buckets, group creation from those buckets, Welcome processing,
incoming-message processing, bare MLS object hashing, signed group-control transcripts and
their descriptor/metadata/member/text readers, persisted device state, and the three
persisted state-restoration layers.

The harness is structure-aware and mutational, not coverage-guided: the pinned stable
`1.97.1` toolchain and the offline/pinned-dependency rules exclude `cargo-fuzz`, libFuzzer,
AFL++, ASan, and Miri. It builds one genuine two-device beta group with the engine itself
and mutates only the fields an untrusted relay supplies, with operators aware of the `u32`
frame headers and `u16` counts the format uses. Detectors are a caught panic, a contained
panic (ABI status 14), per-input allocation-growth and single-allocation ceilings measured
by a test-only counting allocator, a slow-input budget, and a watchdog that aborts on a
decoder that never returns. Each detector has a negative control
(`every_detector_reports_its_injected_defect`), so a clean campaign is evidence rather than
an absence of instrumentation. The per-target outcome spread is printed with every run, so
how deep the mutations actually reached is recorded rather than asserted.

**One defect was found and fixed.** `MlsMessage::from_bytes` stops at the end of the object
it decodes and ignores whatever follows, so `object || anything` decoded to the same
message. `hash_mls_object` and the `KeyPackage` wrapper already re-serialized and compared;
Welcome processing and incoming-message processing did not. An untrusted relay could
therefore present one logical Welcome or Commit under unlimited distinct byte encodings,
each accepted and each yielding a different SHA-256 identity. That defeats any
deduplication or binding keyed on the exact received bytes — including the digest
`native_beta_group_mls.dart` compares against a signed control event's `mls_commit_hash` —
and a tampered Commit was applied to a candidate group state before that comparison
rejected it. All four relay-reachable MLS object paths now share `exact_mls_object`, which
refuses any encoding that does not re-serialize to the exact input bytes.
`every_mls_object_path_refuses_a_non_canonical_encoding` is the regression. This tightens a
bound and does not relax one; RFC 9420 presentation encoding is canonical by construction,
so no conforming peer is excluded.

Recorded campaign, run on the pinned toolchain with no network access:

```sh
CP_FUZZ_ITERATIONS=100000 cargo test --locked --all-features --profile fuzz \
    mls_beta::fuzz::beta_mls_fuzz_campaign -- --exact --ignored --nocapture
```

| | |
|---|---|
| Date | 2026-08-18 |
| Seed | `0x0badc0ded15ea5e5` (default) |
| Targets | 12 |
| Inputs executed | 20,700,000 |
| Duration | 1859.1 s |
| Panics, unbounded allocations, hangs, contained panics | none |

The base budget is per dispatcher target; a direct-decoder target runs forty times that
many, so the twelve targets executed 100,000 inputs each for the seven dispatcher targets
and 4,000,000 each for the five decoder targets. Two earlier campaigns of 2,540,000 inputs
each, under seeds `0x0badc0ded15ea5e5` and `0x51d2a7c3b9e40611`, were run over the first ten
targets and were also clean. Each `cargo test --locked --all-features` additionally runs a
bounded 25-base gate over all twelve targets.

Not fuzzed, and why:

- Sealed group and `KeyPackage` state cannot be reached by the relay at all: it is
  XChaCha20-Poly1305 sealed under a key derived from the device identity secret and bound
  to the device signing key. Its plaintext layers are fuzzed directly instead, which is the
  local storage-tamper boundary rather than the relay boundary.
- Memory-safety instrumentation is absent. The crate is safe Rust apart from the reviewed
  FFI shims, but no sanitizer or Miri run backs that up, because both need a nightly
  toolchain the project does not pin. This is the one gate condition the harness does not
  close.
- Coverage-guided corpus growth is absent for the same reason. Corpus admission uses a
  deterministic outcome-novelty signal, not edge coverage, so reach is evidenced by the
  printed outcome spread rather than by a coverage percentage.
- The pairwise transport, application-message, and attachment decoders are outside this
  operation and are not covered here.

### Closed-beta crash and transaction-failure injection (2026-08-18)

Gate 6 asks for crash-safe state persistence. The persistence claim is
`docs/local-data-model.md`'s MLS transaction boundary: new opaque MLS state, the accepted
control or application fact, the membership and conversation projections, and the exact
prepared outbound object commit atomically under a control revision/hash compare-and-swap,
and the object reaches the network only afterwards. That is a claim about what an
interruption leaves behind, so it is now tested by interrupting it.

The device-local half of the matrix is implemented and passing. The technique is a
temporary SQLite trigger that raises `ABORT` on one exact statement inside the real
transaction (`test/support/storage_fault_injection.dart`), which is the same mechanism
pieces 12 and 13 already use for the inbox and pairwise outbox, generalised so any table
and write kind can be the failure point. Nothing under `lib/` is stubbed or given a
test-only seam, so the rollback under test is the shipped one. Process death is modelled by
a file-backed database whose whole Dart object graph is dropped and reopened; the reopen
runs the production `beforeOpen` path, so `PRAGMA quick_check` fails the test if an aborted
write left the file inconsistent, and the injected fault does not survive the restart.

39 Dart tests across three files cover the four steps and the three gaps between them:

| Step | Failure points covered |
|---|---|
| T1 compare-and-swap commit | abort at the opaque-state write, the accepted control fact, the message projection, the immutable message fact, the conversation projection, the roster projection, and the exact outbound object; a stale compare-and-swap witness; a concurrent revision overtaking a prepared branch; a locally originated transition carrying no outbound object |
| T1 nested in the inbound receive | the same aborts inside the pairwise receive transaction, plus an abort in the pairwise leg *after* the group leg already wrote, an unrecordable fork quarantine, and a re-admission that discards its dead epoch's un-routed work while leaving already-queued ciphertext alone |
| T1 → T2 | death after the commit and before any fan-out; restart resumes from durable state alone |
| T2 | a failed outbox transaction; a fan-out that fails part-way through the recipient list |
| T2 → T3 | death after every recipient is queued and before the routing marker; the retry reuses the exact persisted ciphertext and the ratchet does not step twice |
| T3 → T4 | a re-dispatch after the relay already accepted the batch |
| after T4 | a redelivered envelope after a crash before acknowledgement |

`test/features/groups/application/group_outbound_interruption_test.dart` runs the real
Drift group repository, the real durable pairwise outbox, and the real fan-out coordinator
together; only the device resolver, the prekey claim, and the native ratchet step are
stand-ins, and the ratchet stand-in counts its own invocations, so "the retry did not
re-encrypt" is an assertion rather than a description.

**Two defects were found and fixed.**

The first is not conditional on any interruption. One group object becomes one pairwise
operation per recipient user, and `pairwise_local_applications.event_id` is `UNIQUE`, so the
second recipient's operation collided with the first and its whole transaction rolled back.
Any group with two or more remote members committed its epoch and its outbound object and
then could never route them: the fan-out failed identically on every retry, so the operation
was neither resumable nor abandonable, and the group stalled permanently at the first
Commit. Closed-beta group transport therefore worked only for two-member groups. The
dispatcher now qualifies the logical send identity per recipient exactly as it already
qualified the operation id. The identifiers inside the MLS object, which recipients
deduplicate on, are untouched. It went unnoticed because the dispatcher was only ever tested
against a fake envelope port, so the schema constraint on the far side of that seam was
never exercised.

The second is a liveness defect the first exposed. Pending work is ordered by creation and
the dispatcher returned on the first failure, so one operation nobody can route — an
unreachable recipient, a corrupt persisted row — stranded every later group's durable
ciphertext behind it for as long as its cause lasted. Each operation is independent and
idempotent, so the pass now continues past a failure and still surfaces the first one.

A third, smaller gap was closed in the same pass: the two inbound use cases refuse a
prepared transition that carries an outbound object, but the three outbound ones did not
refuse one that carries none, so a crypto port returning an inbound-shaped result would have
advanced this device to an epoch with nothing to send. The commit boundary cannot detect
this on its own, because an inbound commit legitimately has no outbound object, so the check
lives with the caller that knows the direction.

**What this does not close.** Everything above runs on the host VM against SQLite. It models
a process that dies between transactions. It does not model a `SIGKILL` mid-`fsync`, an
Android low-memory or Doze kill, a force-stop, a power cut, SQLCipher page-level torn
writes, or Keystore unavailability after reboot, and it exercises the development in-memory
MLS port rather than the packaged Rust core. Those cells need the physical-device matrix and
remain outstanding; see gate 6 and
`docs/implementation-checklist.md`. No device matrix has been run.

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
is not draft-06's `0x647a`; see "Closed-beta KEM divergence" above. ADR-040 keeps that
mapping unchanged and records the reinitialization cost of ever changing it. It uses the real beta
backend contracts and durable
recipient-bound pairwise outbox; no MLS secret or shared/raw MLS ciphertext is exposed
to Dart projections or backend metadata.

The beta transport/state format is explicitly disposable and versioned. ADR-044 made
that track user-reachable in the Private Experimental artifact and only there: one
source-only `GroupProductionGate.privateExperimentalPermit` decides both the beta stack
and its screens, and every group screen in that build states that the encryption is
experimental and that an update may reset the group and delete its messages. Until
ADR-044 the screens gated on the development-preview permit alone, so the shipped beta
artifact uploaded KeyPackages for groups its own interface would never show.

**ADR-055 (2026-08-24) held that track closed in the distributed artifact, and ADR-056
reopened it on one measured ABI the same day.** The permit requires the beta environment
*and* an admissible record in `GroupExperimentalGate` for the ABI the running process
loaded. `arm64-v8a` was measured on a Samsung SM-A566B on 2026-08-24 — the crate's own
`--features beta-pq-mls` suite ran on the phone and passed, 128 passed and 0 failed,
matching the host counts exactly — so devices loading that library get the experimental
tier. `armeabi-v7a` and `x86_64` have no record, so devices loading those resolve the
unsupported port exactly as production does: no stack, no screens, and **no KeyPackage
generated or uploaded**. `armeabi-v7a` is unmeasurable on the hardware available, because a
64-bit-only ARM phone cannot execute AArch32 at all; it stays recorded as unmeasured rather
than demoted. The instrument is `tool/measure_beta_mls_core.sh` and the run records live in
`docs/validation/beta-mls-core/`. None of this closes any of the seven gates below. Production
still resolves only to the unsupported port; the release entry point references a
source-constant closed gate whose constructor assertion prevents an accidental true
value from compiling. OpenMLS remains the production preference, but its documented
supported suites do not include the candidate. If maintained exact support cannot be
produced for the target being released, groups remain disabled; the team does not
replace the suite with classical MLS or ship newly invented cryptography.

### The exporter, and what may not be keyed from it (ADR-058, 2026-08-25)

The beta engine derives one exporter, under the label `chat:v1:beta-group-export`, and it
**does not leave the Rust core**. `exporter_confirmation` returns SHA-256 over the 32-byte
`export_secret` output, and Dart uses that digest for exactly one purpose: confirming that
two members agree on an epoch. No exporter secret crosses the FFI boundary, on any profile.

That is the intended posture and this decision does not change it. It is recorded here
because piece 20 was re-scoped onto "which MLS exporter may key real-time media"
(ADR-044) and the answer is currently *none, on either path* — there is no operation that
returns media key material at all. Adding one is a change to the reviewed native surface:
a new domain-separated label distinct from the group's, a new symbol in the export
allowlist `tool/build_rust_android.sh` enforces, and rotation semantics tied to membership
change. [ADR-058](decisions.md) P2 requires it before piece 20 begins, and ADR-058 P3
requires that any such derivation resolve through the same per-ABI permit as the group
stack, so media can never be keyed on a device where `GroupExperimentalGate` withholds the
core that would key it.

None of this opens, weakens, or partially satisfies any of the seven gates below.

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

Sources for the 2026-08-18 cross-implementation assessment, each read as raw source at
branch `main` on that date rather than through documentation or a summarizing tool:

- [MLS Working Group implementation list](https://github.com/mlswg/mls-implementations/blob/main/implementation_list.md), which enumerates the eleven candidates assessed
- [OpenMLS `traits/src/types.rs`](https://raw.githubusercontent.com/openmls/openmls/main/traits/src/types.rs), for the closed `Ciphersuite` and `HpkeKemType` enums and the `0x004E` mapping
- [MLSpp `include/mls/crypto.h`](https://raw.githubusercontent.com/cisco/mlspp/main/include/mls/crypto.h), for `CipherSuite::ID` and the fixed `all_supported_cipher_suites` array
- [ts-mls `src/crypto/`](https://github.com/LukaJCB/ts-mls/tree/main/src/crypto) — `ciphersuite.ts`, `provider.ts`, `hpke.ts`, `kdf.ts`, and `kem.ts`, for the arbitrary-`id` `CryptoProvider` and the closed `KemAlgorithm` union
- [BouncyCastle `MlsCipherSuite.java`](https://raw.githubusercontent.com/bcgit/bc-java/main/mls/src/main/java/org/bouncycastle/mls/crypto/MlsCipherSuite.java), for `ALL_SUPPORTED_SUITES` and the fixed `getSuite` switch
- [mls-kotlin `CipherSuite.kt`](https://raw.githubusercontent.com/Traderjoe95/mls-kotlin/main/protocol/src/main/kotlin/com/github/traderjoe95/mls/protocol/crypto/CipherSuite.kt), for the closed `enum class CipherSuite`
