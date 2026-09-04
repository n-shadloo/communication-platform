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
from cryptography.hazmat.primitives.asymmetric import ed25519, mlkem, x25519

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


REQUIRED_MEMBERS = {
    "name",
    "note",
    "signed_by",
    "verify_with_pub_hex",
    "fields",
    "signed_bytes_hex",
    "signature_hex",
}


def test_the_document_carries_every_member_each_vector_needs():
    """A client generates its test suite from this file, so a vector missing a
    member is a platform that silently skips a case rather than failing one."""
    assert len(VECTORS) == len(DOCUMENT["vectors"]), "two vectors share a name"

    for name, vector in VECTORS.items():
        assert set(vector) == REQUIRED_MEMBERS, name
        assert len(bytes.fromhex(vector["signature_hex"])) == 64, name
        assert len(bytes.fromhex(vector["verify_with_pub_hex"])) == 32, name
        assert bytes.fromhex(vector["signed_bytes_hex"]), name
        assert vector["fields"]["domain"].startswith("chat:v1:"), name


@pytest.mark.parametrize("name", sorted(VECTORS))
def test_each_signed_payload_begins_with_its_declared_domain(name):
    """The domain separator is not length-prefixed, so it is literally the head of
    the signed bytes — which is what a client checks first when its own encoder
    disagrees with the vector."""
    vector = VECTORS[name]
    signed = bytes.fromhex(vector["signed_bytes_hex"])

    assert signed.startswith(vector["fields"]["domain"].encode("ascii"))


def test_no_domain_separator_is_a_prefix_of_another():
    """The property that makes the separators worth having: if one domain were a
    prefix of another, a signature over the longer one could be replayed as a
    signature over the shorter, and the four signature kinds would stop being four
    kinds."""
    domains = {vector["fields"]["domain"] for vector in VECTORS.values()}

    for domain in domains:
        others = domains - {domain}
        assert not any(other.startswith(domain) for other in others), domain


def derive_ed25519(seed_hex):
    return (
        ed25519.Ed25519PrivateKey.from_private_bytes(bytes.fromhex(seed_hex))
        .public_key()
        .public_bytes_raw()
    )


def derive_x25519(seed_hex):
    return (
        x25519.X25519PrivateKey.from_private_bytes(bytes.fromhex(seed_hex))
        .public_key()
        .public_bytes_raw()
    )


def derive_mlkem(seed_hex):
    return (
        mlkem.MLKEM768PrivateKey.from_seed_bytes(bytes.fromhex(seed_hex))
        .public_key()
        .public_bytes_raw()
    )


def test_every_public_key_in_the_document_derives_from_its_published_seed():
    """The document publishes the seeds so the file regenerates byte-identically.
    Re-deriving every public key from them is what makes that claim checkable
    without running the generator — and it catches a vector that was hand-edited to
    carry a key nobody holds the private half of."""
    seeds = DOCUMENT["seeds"]
    bundle = VECTORS["device_bundle_hybrid"]["fields"]

    assert (
        derive_ed25519(seeds["master_ed25519_seed_hex"]).hex()
        == (VECTORS["master_sig"]["verify_with_pub_hex"])
    )
    assert (
        derive_ed25519(seeds["self_signing_ed25519_seed_hex"]).hex()
        == (VECTORS["master_sig"]["fields"]["self_signing_pub_hex"])
    )
    assert (
        derive_ed25519(seeds["user_signing_ed25519_seed_hex"]).hex()
        == (VECTORS["master_sig"]["fields"]["user_signing_pub_hex"])
    )
    assert (
        derive_ed25519(seeds["device_signing_ed25519_seed_hex"]).hex()
        == (bundle["ik_pub_ed25519_half_hex"])
    )
    assert (
        derive_x25519(seeds["identity_x25519_seed_hex"]).hex()
        == (bundle["ik_pub_x25519_half_hex"])
    )
    assert derive_x25519(seeds["spk_x25519_seed_hex"]).hex() == bundle["spk_pub_hex"]
    assert (
        derive_mlkem(seeds["pq_spk_mlkem768_seed_hex"]).hex()
        == (bundle["pq_spk_pub_hex"])
    )


def test_the_signing_key_of_each_vector_is_the_one_the_document_names():
    """`signed_by` is prose for the reader; `verify_with_pub_hex` is what a client
    verifies against. They must agree, or a client that follows the prose builds
    the wrong key from the seeds."""
    seeds = DOCUMENT["seeds"]
    by_name = {
        "master_key": derive_ed25519(seeds["master_ed25519_seed_hex"]),
        "self_signing_key": derive_ed25519(seeds["self_signing_ed25519_seed_hex"]),
        "ik_pub_ed25519_half": derive_ed25519(seeds["device_signing_ed25519_seed_hex"]),
    }

    for name, vector in VECTORS.items():
        expected = by_name[vector["signed_by"]]
        assert vector["verify_with_pub_hex"] == expected.hex(), name


def test_the_committed_document_matches_the_generators_declared_inputs():
    """Drift guard on the pair. `generate.py` is the reference implementation of the
    encoding rule, and an edit to its constants that is not followed by a re-run
    leaves a committed file no client can reproduce from the tool that made it."""
    from devices.vectors import generate

    bundle = VECTORS["device_bundle_hybrid"]["fields"]

    assert bundle["user_id"] == str(generate.USER_ID)
    assert bundle["device_id"] == str(generate.DEVICE_ID)
    assert bundle["spk_id"] == generate.SPK_ID
    assert bundle["pq_spk_id"] == generate.PQ_SPK_ID
    assert bundle["registration_id"] == generate.REGISTRATION_ID
    assert bundle["bundle_version"] == generate.BUNDLE_VERSION
    assert DOCUMENT["seeds"]["master_ed25519_seed_hex"] == generate.MASTER_SEED.hex()
    assert DOCUMENT["seeds"]["pq_spk_mlkem768_seed_hex"] == generate.PQ_SPK_SEED.hex()
    assert {vector["fields"]["domain"] for vector in VECTORS.values()} == {
        generate.BUNDLE_DOMAIN.decode(),
        generate.IDENTITY_DOMAIN.decode(),
        generate.SPK_DOMAIN.decode(),
        generate.PQ_SPK_DOMAIN.decode(),
    }


@pytest.mark.parametrize("name", sorted(VECTORS))
def test_no_vector_signature_verifies_over_another_vectors_payload(name):
    """The cross-check the per-vector test cannot make on its own: a signature that
    verified over a different payload would mean the domains and length prefixes
    are not separating the four signature kinds at all."""
    vector = VECTORS[name]
    pub = ed25519.Ed25519PublicKey.from_public_bytes(
        bytes.fromhex(vector["verify_with_pub_hex"])
    )

    for other, foreign in VECTORS.items():
        if other == name:
            continue
        with pytest.raises(InvalidSignature):
            pub.verify(
                bytes.fromhex(vector["signature_hex"]),
                bytes.fromhex(foreign["signed_bytes_hex"]),
            )
