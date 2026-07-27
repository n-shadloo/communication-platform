# Interop vectors for the client signature encodings

`vectors.json` pins the exact bytes every client must sign and verify. Android, Web and
any future client must reproduce each `signed_bytes_hex` **byte for byte** and verify
each `signature_hex` against the stated public key. Two clients that each "follow the
documentation" but disagree here cannot talk to each other, and the disagreement shows
up as unverifiable devices rather than as an error anyone can debug — which is why these
vectors exist rather than prose alone.

**The server verifies none of this.** It stores and relays these signatures as opaque
bytes and has no opinion on whether they are valid (ARCHITECTURE.md §A16, CLAUDE.md).
Agreement between clients is the only thing that gives them meaning. Nothing in the
server imports this directory; `generate.py` is a development-time tool.

## The rule

ASCII domain separator, then for each field in order a **4-byte big-endian length**
followed by the field bytes. The domain separator itself is not length-prefixed.

An absent optional field is emitted as a **4-byte zero length with no content** — never
skipped. Skipping it would let a bundle with PQ material and one without collide onto
the same signed bytes, so a single `cross_sig` would verify for both. The
`device_bundle_classical_only` vector exists specifically to pin this.

## `ik_pub`

Exactly **64 bytes**, one field carrying two keys:

| Bytes | Key | Used for |
|---|---|---|
| 0–31 | Ed25519 device signing public key | verifying `spk_sig`, `pq_spk_sig`, and the device's own signatures |
| 32–63 | X25519 identity public key | the identity key in X3DH / PQXDH |

## The vectors

| Name | Signature | Signed by |
|---|---|---|
| `device_bundle_hybrid` | `cross_sig`, device with ML-KEM-768 material | self-signing key |
| `device_bundle_classical_only` | `cross_sig`, no PQ material | self-signing key |
| `master_sig` | master over both subkeys | master key |
| `spk_sig` | signed prekey | Ed25519 half of `ik_pub` |
| `pq_spk_sig` | ML-KEM-768 signed prekey | Ed25519 half of `ik_pub` |

## Regenerating

```bash
python devices/vectors/generate.py
```

Every key derives from a fixed seed, so a re-run must produce a byte-identical file. If
it does not, the encoding changed and every client is now incompatible with the last
release — treat that as a breaking change, not a refresh. `devices/tests/test_vectors.py`
re-derives each encoding from the documented rule and verifies each signature, so a
hand-edited vector or a drifted rule fails the suite.

The seeds and private keys in this directory are test material. Never reuse them.
