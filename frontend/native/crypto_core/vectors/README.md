# Protocol and primitive vectors

Every file here is a checked-in artifact. Nothing in this directory is fetched
or regenerated during a build or a test run, so the crate keeps building and
testing with no network access.

## `pairwise-v1.json` — pairwise protocol vectors

`pairwise-v1.json` freezes the byte-level hybrid composition and Double
Ratchet KDF profile implemented by this crate. The four composition cases
cover every allowed combination of the optional classical and post-quantum
one-time prekeys; the signed ML-KEM-768 contribution is present in all four.

The expected values were independently calculated on 2026-07-29 with a small
Python standard-library implementation of RFC 5869 HKDF-SHA-256 and
HMAC-SHA-256, then copied into this file. The Rust test reads this checked-in
artifact and computes each result through the production framing/KDF helpers.
The reference calculation is deliberately not a build-time generator, so a
production-code regression cannot silently rewrite its own expected values.

## `mlkem768-acvp-fips203.json` — official ML-KEM-768 known-answer vectors

### Source and revision

| | |
| --- | --- |
| Publisher | NIST, Automated Cryptographic Validation Protocol (ACVP) |
| Repository | <https://github.com/usnistgov/ACVP-Server> |
| Release tag | `v1.1.0.41` |
| Files | `gen-val/json-files/ML-KEM-keyGen-FIPS203/` and `gen-val/json-files/ML-KEM-encapDecap-FIPS203/` |
| Algorithm | ML-KEM, revision `FIPS203`, parameter set `ML-KEM-768`, `vsId` 42 |
| Standard | NIST FIPS 203, *Module-Lattice-Based Key-Encapsulation Mechanism Standard* |
| Extracted and verified | 2026-08-17 |

**The tag is load-bearing.** ACVP-Server regenerates its vector data between
releases: the same `tcId` carries different values in `v1.1.0.43` (checked
2026-08-17). Bumping the tag invalidates every expected value in this file, so
re-extract the whole fixture rather than editing it in place.

`v1.1.0.41` is pinned because it is the revision the crate already cited: the
`d`/`z` inputs and the `ek`/`dk` SHA-256 fingerprints hard-coded in
`provider.rs`'s `mlkem768_nist_acvp_keygen_vector` reproduce exactly from this
release's keyGen `tcId` 26.

### Contents and how it was extracted

Each record is a verbatim copy of the official values — no field is derived,
recomputed, or reformatted beyond lower-casing the hex. The fields are exactly
ACVP's implementation-under-test contract: inputs come from `prompt.json`,
expected outputs from `expectedResults.json`, and the `reason` label from
`internalProjection.json`. Those three files were checked to agree on every
shared field before extraction.

| Group | ACVP group | Cases | Selected |
| --- | --- | --- | --- |
| `keyGen` | keyGen `tgId` 2, AFT | 5 of 25 | `tcId` 26–30 |
| `encapsulation` | encapDecap `tgId` 2, AFT, `encapsulation` | 5 of 25 | `tcId` 26–30 |
| `decapsulation` | encapDecap `tgId` 5, VAL, `decapsulation` | 10 of 10 | `tcId` 86–95 |
| `decapsulationKeyCheck` | encapDecap `tgId` 9, VAL, `decapsulationKeyCheck` | 4 of 10 | `tcId` 126, 127, 129, 130 |

### Why this subset

The fixture is ~150 KB, so the selection trades breadth against repository
weight deliberately:

- **The AFT groups are homogeneous.** Every one of the 25 keyGen and 25
  encapsulation cases is an independent random draw exercising the same
  straight-line code path. Additional cases raise only the probability of
  catching an input-dependent arithmetic fault — in rejection sampling
  (FIPS 203 Algorithm 7) or compression rounding (Algorithm 5) — with sharply
  diminishing returns. Five of each keeps ~46 KB instead of ~230 KB. Keeping
  the lowest `tcId`s makes the selection reproducible and keeps `tcId` 26,
  which cross-checks the pre-existing hand-pinned test.
- **The VAL decapsulation group is not homogeneous.** Its ten cases split five
  `valid decapsulation` against five `modified ciphertext`, and the latter are
  the only official coverage of FIPS 203 implicit rejection, where decapsulation
  must return the deterministic `J(z ‖ c)` value instead of failing. That is a
  distinct, security-critical branch, so all ten are kept.
- **`decapsulationKeyCheck` is kept at two cases per outcome.** It pins the
  FIPS 203 §7.3 hash check on `dk` — a production reject path that nothing else
  covers — but only two behaviours exist, so two `modified H` and two
  `valid decapsulation key` cases are enough at ~19 KB rather than ~48 KB.
- **`encapsulationKeyCheck` is excluded entirely.** Every invalid case in that
  group is a wrong-length `ek` (1600 bytes rather than ML-KEM-768's 1184). The
  provider takes `&[u8; 1184]`, so those inputs cannot be constructed at all and
  there is no runtime behaviour to pin; the valid cases duplicate what the
  encapsulation group already covers.

### Regenerating

The fixture was produced by selecting the rows above out of the three official
JSON files at tag `v1.1.0.41` and copying the listed fields verbatim. To audit
it, fetch those files and compare field by field against this artifact. Do not
wire any such step into `build.rs` or a test: the extraction is a one-off,
performed by hand and reviewed, precisely so that offline builds keep working
and so that a production-code regression can never rewrite its own expected
values.

## `beta-suite-kats.json` — official vectors for the rest of the beta MLS suite

`mls_beta::BetaMlsCryptoProvider` assembles the closed-beta ciphersuite out of
AWS-LC primitives. ML-KEM-768 is anchored by the ACVP fixture above. This file
anchors every *other* primitive in that composition, at the parameterization the
composition actually selects, and `src/beta_suite_vectors.rs` drives it.

### What the composition uses, and where each primitive is covered

| Primitive | Parameterization in the beta suite | Anchored by |
| --- | --- | --- |
| Signature | Ed25519, AWS-LC's 64-byte `seed \|\| public key` secret | RFC 8032 §7.1 |
| Hash | SHA-384 | NIST FIPS 180-4 / CSRC examples |
| MAC | HMAC-SHA-384 | RFC 4231 §4 |
| KDF | HKDF-SHA-384 | RFC 4231 §4 via RFC 5869 §2.2 (extract only — see the gap below) |
| AEAD | AES-256-GCM, 12-byte nonce, appended 16-byte tag | NIST CAVP AES-GCM and the GCM specification appendix B |
| KEM, post-quantum half | ML-KEM-768 | `mlkem768-acvp-fips203.json` (above) |
| KEM, classical half | X25519 | RFC 7748 §5.2, §6.1 |
| KEM, `DHKEM` KDF | HKDF-SHA-256 | RFC 5869 appendix A.1–A.3 |
| KEM, combiner hash | SHA3-256 | NIST FIPS 202 / CSRC examples |
| KEM, seed expansion | SHAKE-128 | **not covered here** — see the gap below |

The suite-level primitives are driven through the built beta suite's
[`CipherSuiteProvider`] surface, so the vectors pin the mapping as well as the
arithmetic. The three KEM-internal primitives have no individual entry point on
that surface; they are driven through the same public constructors called with
the same arguments `mls_beta.rs` passes, and
`beta_suite_parameterization_matches_the_vectored_primitives` asserts every
parameter the vectors assume against the built suite so a mapping change cannot
silently leave them covering nothing.

Note that the foundation `provider.rs` vectors do **not** cover any of these.
That module's Ed25519, X25519, SHA-2, and HKDF run on `ed25519-dalek`,
`x25519-dalek`, `sha2`, and `hkdf`; the beta suite runs on AWS-LC. Same
algorithms, different implementations, so the coverage is not redundant.

### Sources and revisions

Every value is a verbatim published constant. None was produced by this crate,
by AWS-LC, or by any other implementation.

| Group | Source | Revision | Cases kept |
| --- | --- | --- | --- |
| `ed25519` | RFC 8032, *Edwards-Curve Digital Signature Algorithm (EdDSA)*, §7.1 | RFC 8032 (2017-01) | `TEST 1`, `TEST 2`, `TEST 3`, `TEST SHA(abc)` — 4 of 5 |
| `sha384` | NIST FIPS 180-4, *Secure Hash Standard*, with the NIST CSRC SHA-384 example values | FIPS 180-4 (2015-08) | empty, `abc`, the 896-bit two-block message, one million `a` |
| `sha3_256` | NIST FIPS 202, *SHA-3 Standard*, with the NIST CSRC SHA-3 example values | FIPS 202 (2015-08) | empty, `abc`, the 448-bit and 896-bit messages, the 1600-bit `0xa3` message |
| `hmacSha384` | RFC 4231, *Identifiers and Test Vectors for HMAC-SHA-224/256/384/512*, §4 | RFC 4231 (2005-12) | Test Cases 1, 2, 3, 4, 6, 7 — 6 of 7 |
| `aes256Gcm` | NIST CAVP AES-GCM validation vectors (`gcmtestvectors`, `gcmEncryptExtIV256.rsp`) for NIST SP 800-38D, plus the NIST-hosted GCM specification appendix B | CAVP AES-GCM; GCM specification appendix B | CAVP `Keylen=256 IVlen=96 PTlen=0 AADlen=0 Taglen=128` Count 0, plus GCM specification test cases 13–16 |
| `hkdfSha256` | RFC 5869, *HKDF*, appendix A.1–A.3 | RFC 5869 (2010-05) | all three SHA-256 cases |
| `x25519` | RFC 7748, *Elliptic Curves for Security*, §5.2 and §6.1 | RFC 7748 (2016-01) | both §5.2 scalar-multiplication vectors and the §6.1 exchange |

Extracted and verified 2026-08-17.

`hmacSha384` does double duty. RFC 5869 §2.2 defines
`HKDF-Extract(salt, IKM) = HMAC-Hash(salt, IKM)`, so RFC 4231's published
HMAC-SHA-384 tags *are* published HKDF-SHA-384 pseudo-random keys read through
that normative identity. They are asserted against `kdf_extract` as well as
against `mac`.

Byte strings a source prints as text are stored in `<field>Ascii` rather than
hand-converted to hex, and the long repeated inputs the sources describe as a
repeated block are stored as `<field>` plus `<field>Repeat`. Both keep the
fixture faithful to how the source writes the value.

### Why this subset

- **Ed25519 excludes `TEST 1024`.** Its 1023-byte message cannot be transcribed
  by hand with any confidence, and its code path is identical to the other four.
  The four kept cases already cover an empty message, a 1-byte message, a
  2-byte message, and a 64-byte message.
- **HMAC-SHA-384 excludes Test Case 5.** RFC 4231 publishes only that case's
  leading 128 bits, and the suite seam returns the whole 48-byte tag, so there
  is no full published answer to compare against. Test Cases 6 and 7 already
  cover the longer-than-block-size key path that Test Case 5 does not.
- **AES-256-GCM excludes GCM specification test cases 17 and 18.** They use
  8-byte and 60-byte IVs. The beta suite reports `aead_nonce_size() == 12` and
  AWS-LC rejects any other length, so those inputs are unreachable through the
  composition. What remains covers empty plaintext, a single block, a
  four-block plaintext, and a case with associated data; the fixture shape test
  asserts the last two keep existing.
- **HKDF excludes RFC 5869's SHA-1 cases (4–7).** The composition contains no
  SHA-1.
- **RFC 7748 keeps only the single-iteration vectors.** The §5.2 iterated
  vectors (1 000 and 1 000 000 rounds) test nothing the composition performs;
  every X25519 call in the beta KEM is a single scalar multiplication.

### The remaining gap

**HKDF-SHA-384 expansion has no vendored known answer.** RFC 5869 publishes
outputs only for SHA-256 and SHA-1; NIST's HKDF-at-SHA-384 answers live in the
ACVP `KDA-HKDF-SP800-56Cr2` files, which are far too large to transcribe by hand
and cannot be fetched under the offline rule. Rather than leave the expand half
untested, `beta_suite_hkdf_sha384_expand_follows_rfc5869_construction` recomputes
the expected output from RFC 5869 §2.3's normative definition over the suite's
own HMAC-SHA-384, which the test above pins to RFC 4231. The two run through
different AWS-LC entry points (`HKDF_expand` against `hmac::sign`), and the
lengths cross the 48-byte block boundary so the `T(i)` chaining is exercised.
That is a construction check anchored at one end by official numbers, not an
independent known-answer test, and it must not be described as one. Closing it
properly needs the ACVP KDA files vendored the way the ML-KEM fixture was.

**SHAKE-128 is not covered.** The beta hybrid KEM expands its `kem_derive` seed
with `AwsLcShake128`, but `mls-rs-crypto-awslc 0.25.0` does not export that type
(`mod kdf` is private and only `pub use`s `AwsLcHash`, `AwsLcHkdf`, and `Sha3`),
so no test in this crate can address it without a project-local fork. It is
exercised only indirectly, through `kem_derive`. Upstream carries its own FIPS
202 SHAKE-128 test at `mls-rs-crypto-awslc-0.25.0/src/kdf.rs`.

Neither gap is on a production path: the whole beta suite is behind the
non-default `beta-pq-mls` feature and `docs/mls-profile.md`'s production gates
remain closed.

### Regenerating

Do not. As with the ML-KEM fixture, these values are transcribed by hand from
the published sources and reviewed; nothing writes them from an implementation's
output, precisely so a regression cannot rewrite its own expected values, and
nothing fetches them, so offline builds keep working. To audit the file, open
each source above and compare field by field.

## Differential coverage and its limits

`src/mlkem_vectors.rs` also runs these vectors through AWS-LC's ML-KEM-768
under the non-default `beta-pq-mls` feature and asserts byte-for-byte agreement
with the vendored `mlkem-native` build, in both directions.

That check is **not** an independent-implementation cross-check, and must not be
described as one. AWS-LC does not have its own ML-KEM: `aws-lc-sys` 0.40.0
vendors mlkem-native too, at
`crypto/fipsmodule/ml_kem/mlkem/`. The two builds share upstream lineage for the
core lattice arithmetic. They do differ in ways worth testing:

- **Different upstream revisions.** Comparing the two vendored trees,
  `kem.c` and `verify.c` are byte-identical while `indcpa.c`, `compress.c`,
  `poly.c`, and `sampling.c` differ.
- **Different FIPS 202 backend.** Our build uses mlkem-native's bundled Keccak;
  AWS-LC substitutes its own SHA3/SHAKE through
  `MLK_CONFIG_FIPS202_CUSTOM_HEADER`.
- **Different configuration and build.** AWS-LC supplies custom zeroize,
  `randombytes`, and `memcpy` hooks, enables a keygen pairwise-consistency test
  under FIPS, and may select native arithmetic backends; our build compiles the
  portable C monolith with no assembly.

So the differential test catches upstream revision drift, Keccak-substitution
faults, configuration-dependent behaviour, and integration errors at the Rust
seam. It does not provide the independent-implementation assurance that a
genuinely separate ML-KEM would. The NIST vectors above remain the primary
correctness anchor.
