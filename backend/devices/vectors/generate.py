"""Regenerate `vectors.json`, the cross-platform interop vectors.

Run from the backend root with the dev venv:

    python devices/vectors/generate.py

This is a **development-time tool and a reference implementation of the client
contract's signature encodings**. Nothing in the server imports it, and the server
never computes or verifies any encoding it produces — see ARCHITECTURE.md §A16 and
CLAUDE.md. It lives here so the vectors the Android and Web clients test against are
reproducible and auditable rather than pasted in by hand.

Every key is derived from a fixed seed, so a re-run must produce a byte-identical
file. `cryptography` is already a pinned production dependency (requirements/prod.txt),
so this adds nothing to the dependency set.
"""
import json
import pathlib
import uuid

from cryptography.hazmat.primitives.asymmetric import ed25519, mlkem, x25519

# Fixed inputs. Chosen to be obviously synthetic and easy to eyeball in a hex dump.
USER_ID = uuid.UUID("11111111-2222-3333-4444-555555555555")
DEVICE_ID = uuid.UUID("66666666-7777-8888-9999-aaaaaaaaaaaa")

MASTER_SEED = bytes([0x01]) * 32
SELF_SIGNING_SEED = bytes([0x02]) * 32
USER_SIGNING_SEED = bytes([0x03]) * 32
DEVICE_SIGNING_SEED = bytes([0x04]) * 32
IDENTITY_X25519_SEED = bytes([0x05]) * 32
SPK_X25519_SEED = bytes([0x06]) * 32
PQ_SPK_SEED = bytes([0x07]) * 64  # FIPS 203 keygen seed (d || z)

SPK_ID = 1
PQ_SPK_ID = 2
REGISTRATION_ID = 4242
BUNDLE_VERSION = 1

BUNDLE_DOMAIN = b"chat:v1:device-bundle"
IDENTITY_DOMAIN = b"chat:v1:cross-signing-keys"
SPK_DOMAIN = b"chat:v1:signed-prekey"
PQ_SPK_DOMAIN = b"chat:v1:pq-signed-prekey"


def encode(domain, *fields):
    """The one encoding rule: ASCII domain separator, then each field prefixed with
    its own 4-byte big-endian length. The domain separator itself is not prefixed.

    An absent optional field is still emitted, as a length of 0 with no content —
    never skipped. Skipping it would let a bundle with PQ material and one without
    collide onto the same signed bytes.
    """
    out = bytearray(domain)
    for field in fields:
        out += len(field).to_bytes(4, "big")
        out += field
    return bytes(out)


def u32(value):
    return value.to_bytes(4, "big")


def main():
    master = ed25519.Ed25519PrivateKey.from_private_bytes(MASTER_SEED)
    self_signing = ed25519.Ed25519PrivateKey.from_private_bytes(SELF_SIGNING_SEED)
    user_signing = ed25519.Ed25519PrivateKey.from_private_bytes(USER_SIGNING_SEED)
    device_signing = ed25519.Ed25519PrivateKey.from_private_bytes(DEVICE_SIGNING_SEED)
    identity_x = x25519.X25519PrivateKey.from_private_bytes(IDENTITY_X25519_SEED)
    spk_x = x25519.X25519PrivateKey.from_private_bytes(SPK_X25519_SEED)
    pq_spk = mlkem.MLKEM768PrivateKey.from_seed_bytes(PQ_SPK_SEED)

    raw = lambda key: key.public_key().public_bytes_raw()  # noqa: E731

    # ik_pub is the 64-byte concatenation: Ed25519 signing half, then X25519 half.
    ik_pub = raw(device_signing) + raw(identity_x)
    spk_pub = raw(spk_x)
    pq_spk_pub = raw(pq_spk)
    assert len(ik_pub) == 64
    assert len(pq_spk_pub) == 1184

    def vector(name, signer, signer_name, verify_pub, signed_bytes, fields, note):
        return {
            "name": name,
            "note": note,
            "signed_by": signer_name,
            "verify_with_pub_hex": verify_pub.hex(),
            "fields": fields,
            "signed_bytes_hex": signed_bytes.hex(),
            "signature_hex": signer.sign(signed_bytes).hex(),
        }

    bundle_hybrid = encode(
        BUNDLE_DOMAIN, USER_ID.bytes, DEVICE_ID.bytes, ik_pub, u32(SPK_ID), spk_pub,
        u32(PQ_SPK_ID), pq_spk_pub, u32(REGISTRATION_ID), u32(BUNDLE_VERSION))
    bundle_classical = encode(
        BUNDLE_DOMAIN, USER_ID.bytes, DEVICE_ID.bytes, ik_pub, u32(SPK_ID), spk_pub,
        b"", b"", u32(REGISTRATION_ID), u32(BUNDLE_VERSION))
    identity_bytes = encode(
        IDENTITY_DOMAIN, USER_ID.bytes, raw(self_signing), raw(user_signing))
    spk_bytes = encode(SPK_DOMAIN, USER_ID.bytes, u32(SPK_ID), spk_pub)
    pq_spk_bytes = encode(PQ_SPK_DOMAIN, USER_ID.bytes, u32(PQ_SPK_ID), pq_spk_pub)

    common = {
        "user_id": str(USER_ID),
        "device_id": str(DEVICE_ID),
        "ik_pub_hex": ik_pub.hex(),
        "ik_pub_ed25519_half_hex": ik_pub[:32].hex(),
        "ik_pub_x25519_half_hex": ik_pub[32:].hex(),
    }

    document = {
        "description": (
            "Golden interop vectors for the client-side signature encodings of the "
            "E2EE chat client contract. Every platform must reproduce signed_bytes_hex "
            "exactly and verify signature_hex against verify_with_pub_hex. The server "
            "computes and verifies none of this: it stores and relays these bytes "
            "opaquely, so agreement between clients is the only thing that makes the "
            "signatures meaningful."),
        "encoding_rule": (
            "ASCII domain separator, then for each field in order a 4-byte big-endian "
            "length followed by the field bytes. The domain separator is not "
            "length-prefixed. An absent optional field is emitted as a 4-byte zero "
            "length with no content, never omitted."),
        "ik_pub_layout": (
            "Exactly 64 bytes: Ed25519 device signing public key (bytes 0-31) then "
            "X25519 identity public key (bytes 32-63). The Ed25519 half verifies "
            "spk_sig and pq_spk_sig; the X25519 half is the identity key in "
            "X3DH/PQXDH."),
        "seeds": {
            "note": ("Fixed so this file regenerates byte-identically. Private "
                     "material for test use only — never reuse these anywhere."),
            "master_ed25519_seed_hex": MASTER_SEED.hex(),
            "self_signing_ed25519_seed_hex": SELF_SIGNING_SEED.hex(),
            "user_signing_ed25519_seed_hex": USER_SIGNING_SEED.hex(),
            "device_signing_ed25519_seed_hex": DEVICE_SIGNING_SEED.hex(),
            "identity_x25519_seed_hex": IDENTITY_X25519_SEED.hex(),
            "spk_x25519_seed_hex": SPK_X25519_SEED.hex(),
            "pq_spk_mlkem768_seed_hex": PQ_SPK_SEED.hex(),
        },
        "vectors": [
            vector(
                "device_bundle_hybrid", self_signing, "self_signing_key",
                raw(self_signing), bundle_hybrid,
                dict(common, domain=BUNDLE_DOMAIN.decode(), spk_id=SPK_ID,
                     spk_pub_hex=spk_pub.hex(), pq_spk_id=PQ_SPK_ID,
                     pq_spk_pub_hex=pq_spk_pub.hex(),
                     registration_id=REGISTRATION_ID,
                     bundle_version=BUNDLE_VERSION),
                "cross_sig for a device that uploaded ML-KEM-768 material."),
            vector(
                "device_bundle_classical_only", self_signing, "self_signing_key",
                raw(self_signing), bundle_classical,
                dict(common, domain=BUNDLE_DOMAIN.decode(), spk_id=SPK_ID,
                     spk_pub_hex=spk_pub.hex(), pq_spk_id=None, pq_spk_pub_hex=None,
                     registration_id=REGISTRATION_ID,
                     bundle_version=BUNDLE_VERSION),
                ("cross_sig for a device with no PQ material. Pins the zero-length "
                 "rule: both PQ fields contribute 00000000 and are not skipped.")),
            vector(
                "master_sig", master, "master_key", raw(master), identity_bytes,
                {"domain": IDENTITY_DOMAIN.decode(), "user_id": str(USER_ID),
                 "self_signing_pub_hex": raw(self_signing).hex(),
                 "user_signing_pub_hex": raw(user_signing).hex()},
                ("Binds both subkeys to the master key. `version` is deliberately "
                 "not covered — it is an anti-accident check, not a guarantee.")),
            vector(
                "spk_sig", device_signing, "ik_pub_ed25519_half",
                ik_pub[:32], spk_bytes,
                {"domain": SPK_DOMAIN.decode(), "user_id": str(USER_ID),
                 "spk_id": SPK_ID, "spk_pub_hex": spk_pub.hex()},
                ("device_id is deliberately absent: it does not exist until "
                 "registration succeeds, and spk_sig is required at registration. "
                 "cross_sig is what binds this prekey to a device_id.")),
            vector(
                "pq_spk_sig", device_signing, "ik_pub_ed25519_half",
                ik_pub[:32], pq_spk_bytes,
                {"domain": PQ_SPK_DOMAIN.decode(), "user_id": str(USER_ID),
                 "pq_spk_id": PQ_SPK_ID, "pq_spk_pub_hex": pq_spk_pub.hex()},
                ("A separate domain from spk_sig so neither signature can be "
                 "replayed as the other.")),
        ],
    }

    path = pathlib.Path(__file__).with_name("vectors.json")
    path.write_text(json.dumps(document, indent=2) + "\n")
    print(f"wrote {path} ({len(document['vectors'])} vectors)")


if __name__ == "__main__":
    main()
