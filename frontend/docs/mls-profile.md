# Post-quantum MLS profile

## Status

This document owns the Flutter client's group-ciphersuite decision. The algorithm
profile is selected, but it is not yet a production wire contract because its IETF
ciphersuite identifier is still unassigned and the preferred library does not yet
document support for it. Group work may proceed behind an experimental build flag, but
production group creation and release remain blocked by the gates below.

Status last verified on 2026-07-27 against IETF draft revision 06, the IANA MLS
ciphersuite registry, and the OpenMLS supported-ciphersuite list.

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

The shared Rust crypto core owns OpenMLS integration and the cryptographic provider;
Flutter/Dart only calls its narrow Android FFI API in version 1. The same source, locked
dependency versions, serialization, and fixtures must be used by a future Web/Wasm
adapter.

Piece 07 stages only the primitive foundation and Android FFI/isolate adapter. It does
not integrate OpenMLS, create MLS state, or produce KeyPackages. Web crypto remains
fail-closed until the reviewed same-source Wasm adapter and browser fixtures exist in a
post-v1 milestone.

Piece 18 implements the crypto-independent group product model, authorization,
transactional storage boundary, and UI. Its Dart crypto port is a boundary for piece 19,
not an MLS implementation. Tests and development previews may use an explicitly
non-cryptographic in-memory adapter that emits no suite identifier, KeyPackage, Welcome,
or production-compatible ciphertext. Production resolves only to an unsupported port;
the release entry point references a source-constant closed gate whose constructor
assertion prevents an accidental true value from compiling.

OpenMLS is preferred, but its documented supported suites currently do not include the
selected candidate. The Android implementation spike must prove provider support and
lifecycle behavior for version 1; a later Web spike must prove the Wasm/browser path.
If maintained support cannot be produced for the target being released, groups remain
disabled; the team does not replace the suite with classical MLS or ship newly invented
cryptography.

## Production gates

All of these are mandatory:

1. The suite has a stable specification and an IANA-assigned identifier.
2. A maintained OpenMLS/provider combination implements the final KEM, KDF, AEAD, hash,
   and signature mappings without a project-local cryptographic fork.
3. For version 1, KeyPackage, Welcome, Commit, Proposal, epoch, exporter, serialization,
   persistence, malformed-input, and downgrade fixtures pass on Android. A future Web
   release additionally requires byte-identical Android/Web fixtures.
4. The padded KeyPackage representation fits the backend's 4,096/16,384-byte buckets,
   including the last-resort behavior.
5. Crash-safe state persistence, queue-gap removal/re-add, and concurrent-commit/fork
   handling pass the full multi-device matrix.
6. An independent cryptographic review closes all blocking findings.

No production KeyPackage is uploaded until these gates pass. A future change of suite
is an explicit protocol migration and group reinitialization, never silent negotiation.

## Authoritative references

- [IETF MLS cipher suites with ML-KEM draft](https://datatracker.ietf.org/doc/draft-ietf-mls-pq-ciphersuites/)
- [IANA MLS registry](https://www.iana.org/assignments/mls/mls.xhtml)
- [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420)
- [OpenMLS](https://github.com/openmls/openmls)
- [MLS Working Group interoperability vectors](https://github.com/mlswg/mls-implementations/tree/main/test-vectors)
