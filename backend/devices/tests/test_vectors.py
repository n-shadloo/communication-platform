"""The committed interop vectors are self-consistent and match the documented rule.

**This is not server-side signature verification.** The server neither computes nor
checks any encoding here, and no view imports this module or `devices/vectors/` (see
SECURITY.md). What these tests do is lock the *specification artifact*: if the vectors
and the documented encoding rule ever disagree, Android and Web would each "follow the
documentation" and produce incompatible signatures — the exact failure the vectors
exist to prevent. Re-deriving the bytes here also means the vectors cannot be edited by
hand into something the rule does not produce.
"""

import json
import pathlib
import uuid

import pytest
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric import ed25519

VECTORS_PATH = pathlib.Path(__file__).resolve().parents[1] / "vectors" / "vectors.json"
DOCUMENT = json.loads(VECTORS_PATH.read_text())
VECTORS = {vector["name"]: vector for vector in DOCUMENT["vectors"]}


def encode(domain, *fields):
    """Independent re-implementation of the documented rule, written from the prose
    in CLIENT_CONTRACT.md §B rather than imported from the generator — a copy of the
    generator would agree with itself no matter what the rule says."""
    out = bytearray(domain.encode("ascii"))
    for field in fields:
        out += len(field).to_bytes(4, "big")
        out += field
    return bytes(out)


def u32(value):
    return value.to_bytes(4, "big")


def hexed(vector, key):
    return bytes.fromhex(vector["fields"][key])


@pytest.mark.parametrize("name", sorted(VECTORS))
def test_every_vector_signature_verifies_against_its_stated_public_key(name):
    """A client that reproduces signed_bytes but fails verification knows its
    Ed25519 is at fault, not the vector."""
    vector = VECTORS[name]
    pub = ed25519.Ed25519PublicKey.from_public_bytes(
        bytes.fromhex(vector["verify_with_pub_hex"])
    )

    pub.verify(
        bytes.fromhex(vector["signature_hex"]), bytes.fromhex(vector["signed_bytes_hex"])
    )


@pytest.mark.parametrize("name", sorted(VECTORS))
def test_a_tampered_signed_payload_fails_verification(name):
    """Guards against a vector whose signature would verify over anything — e.g. an
    all-zero signature or a mismatched public key silently accepted."""
    vector = VECTORS[name]
    pub = ed25519.Ed25519PublicKey.from_public_bytes(
        bytes.fromhex(vector["verify_with_pub_hex"])
    )
    tampered = bytearray(bytes.fromhex(vector["signed_bytes_hex"]))
    tampered[-1] ^= 0x01

    with pytest.raises(InvalidSignature):
        pub.verify(bytes.fromhex(vector["signature_hex"]), bytes(tampered))


def test_the_hybrid_device_bundle_matches_the_documented_field_order():
    vector = VECTORS["device_bundle_hybrid"]
    fields = vector["fields"]

    expected = encode(
        "chat:v1:device-bundle",
        uuid.UUID(fields["user_id"]).bytes,
        uuid.UUID(fields["device_id"]).bytes,
        hexed(vector, "ik_pub_hex"),
        u32(fields["spk_id"]),
        hexed(vector, "spk_pub_hex"),
        u32(fields["pq_spk_id"]),
        hexed(vector, "pq_spk_pub_hex"),
        u32(fields["registration_id"]),
        u32(fields["bundle_version"]),
    )

    assert expected.hex() == vector["signed_bytes_hex"]


def test_absent_pq_fields_are_zero_length_not_skipped():
    """The subtle half of the rule. Skipping an absent field instead of emitting a
    zero length would let a hybrid bundle and a classical-only one collide onto the
    same signed bytes, so one cross_sig would verify for both."""
    vector = VECTORS["device_bundle_classical_only"]
    fields = vector["fields"]
    assert fields["pq_spk_id"] is None and fields["pq_spk_pub_hex"] is None

    expected = encode(
        "chat:v1:device-bundle",
        uuid.UUID(fields["user_id"]).bytes,
        uuid.UUID(fields["device_id"]).bytes,
        hexed(vector, "ik_pub_hex"),
        u32(fields["spk_id"]),
        hexed(vector, "spk_pub_hex"),
        b"",
        b"",
        u32(fields["registration_id"]),
        u32(fields["bundle_version"]),
    )

    assert expected.hex() == vector["signed_bytes_hex"]
    # And the two bundles really are distinguishable, which is the whole point.
    assert (
        vector["signed_bytes_hex"] != VECTORS["device_bundle_hybrid"]["signed_bytes_hex"]
    )


def test_the_master_signature_covers_both_subkeys_and_not_the_version():
    vector = VECTORS["master_sig"]
    fields = vector["fields"]

    expected = encode(
        "chat:v1:cross-signing-keys",
        uuid.UUID(fields["user_id"]).bytes,
        hexed(vector, "self_signing_pub_hex"),
        hexed(vector, "user_signing_pub_hex"),
    )

    assert expected.hex() == vector["signed_bytes_hex"]
    assert "version" not in fields


@pytest.mark.parametrize(
    "name,domain,id_key,pub_key",
    [
        ("spk_sig", "chat:v1:signed-prekey", "spk_id", "spk_pub_hex"),
        ("pq_spk_sig", "chat:v1:pq-signed-prekey", "pq_spk_id", "pq_spk_pub_hex"),
    ],
)
def test_the_prekey_signatures_match_their_documented_encodings(
    name, domain, id_key, pub_key
):
    vector = VECTORS[name]
    fields = vector["fields"]

    expected = encode(
        domain,
        uuid.UUID(fields["user_id"]).bytes,
        u32(fields[id_key]),
        hexed(vector, pub_key),
    )

    assert expected.hex() == vector["signed_bytes_hex"]


def test_the_two_prekey_domains_differ_so_neither_signature_replays_as_the_other():
    assert (
        VECTORS["spk_sig"]["signed_bytes_hex"]
        != VECTORS["pq_spk_sig"]["signed_bytes_hex"]
    )
    assert not VECTORS["spk_sig"]["signed_bytes_hex"].startswith(
        "chat:v1:pq".encode().hex()
    )


def test_ik_pub_is_the_documented_sixty_four_byte_split():
    vector = VECTORS["device_bundle_hybrid"]
    ik_pub = hexed(vector, "ik_pub_hex")

    assert len(ik_pub) == 64
    assert ik_pub[:32] == hexed(vector, "ik_pub_ed25519_half_hex")
    assert ik_pub[32:] == hexed(vector, "ik_pub_x25519_half_hex")
    # The Ed25519 half is what the prekey signatures verify against.
    assert VECTORS["spk_sig"]["verify_with_pub_hex"] == ik_pub[:32].hex()
    assert VECTORS["pq_spk_sig"]["verify_with_pub_hex"] == ik_pub[:32].hex()


def test_the_pq_prekey_is_a_real_ml_kem_768_encapsulation_key_size():
    assert len(hexed(VECTORS["device_bundle_hybrid"], "pq_spk_pub_hex")) == 1184
