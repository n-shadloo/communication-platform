# Pairwise protocol vectors

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
