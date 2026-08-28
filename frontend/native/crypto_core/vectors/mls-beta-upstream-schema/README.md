# Project vectors for the beta MLS suite, written in the upstream schema

## These are project vectors. They are not upstream vectors.

Every byte in this directory was produced by this repository, by
`native/crypto_core/src/mls_beta.rs`, for the closed-beta MLS **Private Use**
ciphersuite `0xFE4C`. Nothing here is published by the MLS working group, the
IETF, or any other external party.

**These files are not external interoperability evidence and must never be cited
as such.** They are not upstream vectors, they were not produced by a second
implementation, and no upstream vector exists for this suite to compare them
against: `0xFE4C` is a Private Use identifier, and the beta hybrid KEM diverges
from `draft-ietf-mls-pq-ciphersuites` `TBD2` in the ten ways recorded as rows
D1-D10 of `docs/mls-profile.md`. A passing test here is **schema-conformance and
regression evidence only**.

Nothing in this directory advances Phase-A external prerequisite 4 (upstream
interoperability vectors) or any of the seven production gates in
`docs/mls-profile.md`. Those remain exactly as closed as they were.

The disclaimer is repeated verbatim inside **every emitted object**, under the
`_provenance` key, so that a single vector lifted out of a file still carries it.
`every_emitted_vector_declares_project_provenance` asserts that it is present and
unmodified in all three files.

## Why write them in the upstream schema at all

Because the shape is the useful part. Writing the beta artifacts against a
published contract fixes the encodings this implementation would have to satisfy
at a future interop event, makes the beta `Welcome` and follow-along behaviour
machine-checkable against something other than an ad-hoc format, and surfaces
encoding mismatches now rather than at the event. One such mismatch already
turned up; see *Encoding conventions* below.

## Schema authority and how it was verified

| | |
| --- | --- |
| Document | `test-vectors.md`, MLS working group |
| Repository | <https://github.com/mlswg/mls-implementations> |
| Revision | branch `main`, fetched raw and read in full |
| Verified | 2026-08-18 |
| Cross-check | the serde structures `mls-rs 0.55.2` uses to consume the same files, in `src/group/interop_test_vectors/` and `src/tree_kem/interop_test_vectors.rs` |

The document was read directly rather than through any summarizing tool. That
mattered: a summarized reading of the same page reported the Tree Operations
`proposal` field as a `uint16` proposal *type*, where the document defines it as
a hex-encoded TLS-serialized `Proposal`. Only the two independent readings —
the source text and `mls-rs`'s own deserializer — agreed field for field.

The document defines **14 categories**, of which **11 are ciphersuite-parameterized**
(they carry a `cipher_suite` field of type `uint16`):

| Category | `cipher_suite`? | Category | `cipher_suite`? |
| --- | --- | --- | --- |
| Tree Math | no | Tree Operations | yes |
| Crypto Basics | yes | Tree Validation | yes |
| Secret Tree | yes | TreeKEM | yes |
| Message Protection | yes | Messages | no |
| Key Schedule | yes | Passive Client Scenarios | yes |
| Pre-Shared Keys | yes | Vector Deserialization | no |
| Transcript Hashes | yes | Welcome | yes |

Both parameterized categories emitted here carry `"cipher_suite": 65100`, which
is `0xFE4C`. `welcome_vectors_match_the_upstream_schema` and
`passive_client_vectors_match_the_upstream_schema` assert that value against
`BETA_CIPHERSUITE_ID`, and `emitted_vectors_still_describe_the_built_beta_suite`
asserts it against the suite the provider actually builds, so a mapping change in
`mls_beta.rs` cannot leave the fixtures quietly describing a different suite.
`deserialization.json` deliberately has **no** `cipher_suite` key, and the schema
test asserts its absence.

## Encoding conventions, as the document states them

- Each file is a **JSON array of objects**. Both are arrays here, including the
  single-case files.
- `optional<type>` is the value itself or `null`.
- MLS structs are binary-encoded per the specification and carried as
  **lower-case hex strings**. `decode_hex` rejects upper-case and odd-length hex.
- **HPKE and signature public keys are raw binary, without** the length prefix
  those structs normally carry. `signer_pub` is therefore exactly 32 bytes.
- **HPKE private keys** use the `SerializePrivateKey` function for the
  ciphersuite's HPKE method. For the beta hybrid KEM that is the 2,432-byte
  private key, which is what `init_priv` and `encryption_priv` carry.
- **EdDSA private keys** use "their native byte string representation".

That last rule is the mismatch worth recording. The native RFC 8032
representation of an Ed25519 private key is the **32-byte seed**, but the beta
suite's AWS-LC provider represents it as the **64-byte `seed || public key`**
concatenation — `mls_beta.rs` builds exactly that form when it reuses the
enrolled device key. So:

- emission truncates to the 32-byte seed, and
- consumption rebuilds the provider-native form by re-appending the public key
  recovered from the vector's own `KeyPackage`.

`emitted_vectors_still_describe_the_built_beta_suite` pins both widths against a
freshly generated suite key pair, so the day the provider changes representation,
the test says so. Note that `mls-rs`'s own passive-client generator writes the
provider-native secret straight out (`signature_priv: secret_key.to_vec()`),
which would be non-conformant for this suite; its framing generator does truncate
for Edwards suites. The truncation is correct and the divergence is upstream's.

## The one non-upstream key

Each object carries `_provenance`, holding the disclaimer, in addition to the
upstream field set. This is a deliberate, additive departure from a byte-exact
upstream object:

- it is the only added key, and `assert_field_set` fails the build if any other
  key appears or any upstream key goes missing;
- serde-based upstream consumers — including `mls-rs`'s own structures, none of
  which use `deny_unknown_fields` — ignore unknown members, so the files stay
  consumable as ordinary vectors; and
- per-object placement means an extracted single vector still states what it is,
  which a file-level or sidecar note could not achieve.

If a byte-exact upstream object is ever needed, strip that one key.

## Categories emitted

| File | Category | Objects | Contents |
| --- | --- | --- | --- |
| `welcome.json` | Welcome | 1 | Alice creates a beta group and adds Bob: the `KeyPackage`, the `Welcome`, Bob's `init_priv`, and Alice's `signer_pub` |
| `passive-client.json` | Passive Client Scenarios | 1, over 3 epochs | Bob joins from that same `Welcome`, then follows Alice adding Carol, Carol's by-reference update that Alice commits, and Alice removing Carol |
| `deserialization.json` | Vector Deserialization | 8 | `VarInt` headers for lengths 0, 1, 63, 64, 1 024, 16 383, 16 384, and 1 073 741 823 |

The passive-client scenario sets `"ratchet_tree": null`, which the schema defines
as "the tree is in the welcome message". That is accurate: the beta client runs
`DefaultMlsRules` with `ratchet_tree_extension` at its default `true`, so the
tree travels inside the `Welcome`'s `GroupInfo`. `"external_psks": []` is
likewise accurate rather than a stub — the beta client builds no PSK, and
`mls-rs`'s own generator emits the same empty array when no PSK is in play.

The eight deserialization lengths are not arbitrary: they are 0, 1, both sides of
each boundary between the one-, two-, and four-byte encodings, one interior
two-byte value, and `VarInt::MAX`, which is the widest length MLS encodes.

## Categories skipped, and why

The rule applied was: emit a category only if this implementation can populate
**every** field of it through the code it actually ships. Eleven categories fail
that test, and the reason is nearly always the same — the construction the
category vectors is `pub(crate)` inside `mls-rs`, so producing it would mean
vectoring a re-implementation written for the fixture rather than the code that
runs in the beta client. A vector whose expected values come from a parallel
implementation proves nothing about the shipped one.

| Category | Why not |
| --- | --- |
| Crypto Basics | Needs `RefHash`, `ExpandWithLabel`, `DeriveSecret`, `DeriveTreeSecret`, `SignWithLabel`, and `EncryptWithLabel`. The `CipherSuiteProvider` trait exposes only unlabeled primitives; every labeled construction is `pub(crate)` in `mls-rs` (`kdf_derive_secret`, `hash_reference::RefHashInput`, the `signer` label constants). The unlabeled halves are already anchored to official vectors by `beta-suite-kats.json`. |
| Secret Tree | Needs a secret tree built from a *chosen* `encryption_secret` and `sender_data` key/nonce from a chosen `sender_data_secret`. `group::secret_tree` is `pub(crate)`; the `secret_tree_access` feature only exposes the group's own tree at its own internally derived secret, which is not the vector's input. |
| Message Protection | Needs `encryption_secret`, `sender_data_secret`, and `membership_key` injected into a group at a chosen `GroupContext`. No public API accepts them. |
| Key Schedule | Needs the epoch schedule driven from chosen `commit_secret`, `psk_secret`, and `tree_hash` values. `group::key_schedule` is private. |
| Pre-Shared Keys | `psk_secret` is computed by a private trait method, and the beta client enables no PSK path. |
| Transcript Hashes | Needs an `AuthenticatedContent` and the transcript-hash update. Both are private. |
| Tree Operations | Needs the tree that results from applying a bare proposal. The implementation has no "apply a proposal to a tree" entry point; deriving it from a commit would fold the commit's update-path effects into the answer, and `Remove` and `Update` commits require a path, so the value would not be the proposal's effect. |
| Tree Validation | Needs per-node `resolutions` and per-node `tree_hashes`. Neither is exposed. |
| TreeKEM | Needs per-node `path_secrets` and private TreeKEM state. Not exposed. |
| Messages | Cannot be fully populated. `public_message_application` is unreachable — RFC 9420 requires application data to be a `PrivateMessage`, and the beta client additionally sets `encrypt_control_messages`, so `public_message_proposal` and `public_message_commit` are unreachable too. `GroupSecrets` is not publicly exported, and the `ReInit`, `ExternalInit`, and `GroupContextExtensions` proposals are not part of the beta surface. |
| Tree Math | Ciphersuite-independent, so it says nothing about the beta suite; and `tree_kem::math` is private, so any emission would be a re-implementation. |

## What these vectors prove, and what they do not

| Test | Proves | Does not prove |
| --- | --- | --- |
| `welcome_vectors_match_the_upstream_schema` | the object carries exactly the upstream Welcome fields, the suite identifier, the documented byte widths, and `MLSMessage`s that re-encode to the fixture bytes | anything about the values themselves |
| `welcome_vectors_round_trip_through_the_beta_implementation` | the recorded `Welcome` decrypts under the recorded `init_priv`, its `GroupInfo` signature and confirmation tag verify, and `signer_pub` is a member of the resulting group | interoperability; the `Welcome` was produced for this suite by this repository |
| `welcome_vectors_need_the_recorded_init_priv` | the round trip is not vacuous — corrupting one byte of `init_priv` breaks the join | — |
| `passive_client_vectors_match_the_upstream_schema` | the full upstream field set including every epoch's field set, widths, the null tree, and the empty PSK array | — |
| `passive_client_vectors_round_trip_through_the_beta_implementation` | a client rebuilt from the vector's own `key_package`, `signature_priv`, `encryption_priv`, and `init_priv` joins from the `Welcome`, reproduces `initial_epoch_authenticator`, and reproduces every epoch authenticator after applying the recorded proposals and commits | that any other implementation would agree; every byte came from this one |
| `passive_client_vectors_need_the_recorded_proposals` | the `proposals` array is load-bearing — a commit that incorporates a proposal by reference does not apply without it | — |
| `deserialization_vectors_match_the_upstream_schema` | exactly `vlbytes_header` and `length`, no `cipher_suite`, and a header of 1, 2, or 4 bytes | — |
| `deserialization_vectors_round_trip_through_the_beta_codec` | each header decodes to the recorded length through `mls_rs_codec::VarInt` and re-encodes to the same bytes, so the recorded encoding is the canonical one | conformance beyond this codec; it is the codec the beta protocol uses, not a second opinion |
| `every_emitted_vector_declares_project_provenance` | every object in every file still carries the exact disclaimer | — |
| `emitted_vectors_still_describe_the_built_beta_suite` | the suite the provider builds still has the identifier, KDF extract size, and Ed25519 key widths the fixtures assume | — |

The correspondence checks the upstream passive-client verification calls for are
performed on load rather than asserted from the fixture: `signature_priv` is
required to re-derive the `KeyPackage`'s `signature_key` through RFC 8032 key
generation, and `init_priv` is required to open a ciphertext sealed to the
`KeyPackage`'s `hpke_init_key`. `encryption_priv` is exercised implicitly — the
update commit in epoch 3 carries a path, so a wrong leaf secret fails to decrypt
it.

## The harness input the schema has no room for

The upstream schema carries no identity or Authentication-Service context,
because upstream harnesses accept any `BasicCredential`. This implementation does
not: `AuthenticatedDeviceIdentityProvider` resolves a credential to an approved
device record and checks its signature key. Replaying these vectors therefore
needs a device directory, which is **harness input, not vector data**.

That roster is three fixed entries in `src/beta_mls_vectors.rs`, each a user id,
a device id, a canonical bundle string, and a 32-byte Ed25519 seed. It is
deterministic, so a replay rebuilds byte-identical credentials from the seeds
alone and no key material has to be smuggled into or alongside the fixtures.
Those seeds are throwaway fixture identities with no relationship to any enrolled
device.

The generator also issues `KeyPackage` lifetimes of 100 years, so a checked-in
vector keeps replaying. Production uses the default lifetime; nothing else about
the harness client differs from
`BetaMlsAuthenticationContext::client` — same identity provider, crypto provider,
encryption options, storage types, and suite.

## Generating and regenerating

`src/beta_mls_vectors.rs` holds both the generator and the tests. The generator
is `emit_project_vectors_in_the_upstream_schema`, and it is `#[ignore]`d:

```text
cargo test --locked --all-features -- --ignored emit_project_vectors
```

`cargo test` does not run ignored tests, so no ordinary test run — including
`cargo test --all-features` — can rewrite an expected value. This is a
deliberately weaker rule than the one governing the official fixtures in
`../README.md`, which nothing in the repository may write at all. It is weaker
because these values are *this implementation's own output*: there is no external
answer for a regeneration to drift away from, so the thing worth preventing is a
silent rewrite, not a rewrite. Keeping the generator checked in and reviewable is
worth more here than deleting it, which is what the hybrid-KEM fixture did.

Regenerating changes every value, because the scenario draws fresh HPKE and
signature randomness. A diff that touches only these files is expected after a
deliberate regeneration and means nothing on its own; a diff that appears
*without* one means a checked-in fixture was rewritten by something that should
not have rewritten it.

The tests read the files through `include_str!`, so they are compile-time inputs
and nothing is fetched at build or test time.
