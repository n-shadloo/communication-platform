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
