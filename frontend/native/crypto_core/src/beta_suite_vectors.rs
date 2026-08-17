//! Official known-answer coverage for the beta MLS ciphersuite composition.
//!
//! `mls_beta::BetaMlsCryptoProvider` assembles the closed-beta suite out of
//! AWS-LC primitives. ML-KEM-768 is anchored separately in `mlkem_vectors`;
//! every other primitive in that composition is anchored here, at the exact
//! parameterization the composition selects.
//!
//! Two seams are used, and the distinction matters:
//!
//! - Primitives the [`CipherSuiteProvider`] surface exposes directly — SHA-384,
//!   HMAC-SHA-384, HKDF-SHA-384, AES-256-GCM, Ed25519 — are driven through the
//!   built beta suite itself, so the vectors also pin the mapping.
//! - Primitives that live *inside* the hybrid KEM — SHA3-256, X25519, and the
//!   HKDF-SHA-256 of `DHKEM(X25519, HKDF-SHA256)` — have no individual entry
//!   point on that surface. They are driven through the same public
//!   constructors, called with the same arguments `mls_beta.rs` passes, and
//!   `beta_suite_parameterization_matches_the_vectored_primitives` guards the
//!   correspondence.
//!
//! The fixture is checked in. Nothing here reaches the network at build or test
//! time. See `vectors/README.md` for each source, its revision, why the subset
//! was chosen, and the one coverage gap that remains.

use mls_rs::{CipherSuite, CipherSuiteProvider, CryptoProvider};
use mls_rs_core::crypto::{HpkePublicKey, HpkeSecretKey, SignaturePublicKey, SignatureSecretKey};
use mls_rs_crypto_awslc::{AwsLcCipherSuite, AwsLcHash, AwsLcHkdf, Ecdh, Sha3};
use mls_rs_crypto_traits::{DhType, Hash, KdfId, KdfType};
use serde_json::Value;

use crate::mls_beta::{BETA_CIPHERSUITE, BetaMlsCryptoProvider};

const VECTORS: &str = include_str!("../vectors/beta-suite-kats.json");

/// The classical half of the beta hybrid KEM, as named in `mls_beta.rs`'s
/// `combined_hpke` call. It selects both X25519 and the `DHKEM` HKDF-SHA-256.
const BETA_KEM_CLASSICAL_SUITE: CipherSuite = CipherSuite::CURVE25519_AES128;

const AES256_KEY_BYTES: usize = 32;
const GCM_NONCE_BYTES: usize = 12;
const GCM_TAG_BYTES: usize = 16;
const SHA384_BYTES: usize = 48;
const SHA3_256_BYTES: usize = 32;
const ED25519_SEED_BYTES: usize = 32;
const ED25519_PUBLIC_BYTES: usize = 32;
const ED25519_SIGNATURE_BYTES: usize = 64;
const X25519_KEY_BYTES: usize = 32;
const MLKEM768_PUBLIC_BYTES: usize = 1184;

fn vectors() -> Value {
    serde_json::from_str(VECTORS).expect("vendored beta suite vectors are valid JSON")
}

fn group<'a>(vectors: &'a Value, name: &str) -> &'a Vec<Value> {
    vectors[name]["cases"]
        .as_array()
        .unwrap_or_else(|| panic!("vector group {name} carries a case array"))
}

fn decode_hex(text: &str) -> Vec<u8> {
    assert!(text.len().is_multiple_of(2), "hex has an even length");
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            u8::from_str_radix(std::str::from_utf8(pair).expect("vector hex is ASCII"), 16)
                .expect("vector hex is valid")
        })
        .collect()
}

/// Reads one fixture byte string.
///
/// `<field>` holds lower-case hex; `<field>Ascii` holds the literal string a
/// source prints as text, which avoids hand-transcribing long ASCII inputs into
/// hex; an optional `<field>Repeat` repeats the decoded block, which is how the
/// sources themselves write their long repeated inputs.
fn bytes(case: &Value, field: &str) -> Vec<u8> {
    let block = match case[format!("{field}Ascii").as_str()].as_str() {
        Some(text) => text.as_bytes().to_vec(),
        None => decode_hex(
            case[field]
                .as_str()
                .unwrap_or_else(|| panic!("{field} is a hex string")),
        ),
    };
    let repeat = case[format!("{field}Repeat").as_str()]
        .as_u64()
        .unwrap_or(1);
    block.repeat(usize::try_from(repeat).expect("repeat count fits in usize"))
}

fn name(case: &Value) -> &str {
    case["name"].as_str().unwrap_or("unlabelled")
}

fn beta_suite() -> AwsLcCipherSuite {
    BetaMlsCryptoProvider
        .cipher_suite_provider(BETA_CIPHERSUITE)
        .expect("beta suite is configured")
}

/// The beta composition's Ed25519 secret key is AWS-LC's 64-byte
/// `seed || public key`, so RFC 8032's 32-byte seed is joined to its published
/// public key here rather than being expanded by this test.
fn ed25519_secret(case: &Value) -> SignatureSecretKey {
    let mut secret = bytes(case, "secretSeed");
    assert_eq!(
        secret.len(),
        ED25519_SEED_BYTES,
        "RFC 8032 seed is 32 bytes"
    );
    secret.extend_from_slice(&bytes(case, "publicKey"));
    SignatureSecretKey::from(secret)
}

/// Recomputes RFC 5869 section 2.3 `HKDF-Expand` from the suite's own HMAC.
///
/// This is the construction the RFC defines, not an independently published
/// output: `T(0) = ""`, `T(i) = HMAC(PRK, T(i-1) || info || i)`, and
/// `OKM = first L bytes of T(1) || T(2) || ...`.
fn rfc5869_expand(suite: &AwsLcCipherSuite, prk: &[u8], info: &[u8], length: usize) -> Vec<u8> {
    let mut previous = Vec::new();
    let mut okm = Vec::new();
    let mut counter = 1u8;
    while okm.len() < length {
        let mut block = previous.clone();
        block.extend_from_slice(info);
        block.push(counter);
        previous = suite.mac(prk, &block).expect("HMAC-SHA-384 succeeds");
        okm.extend_from_slice(&previous);
        counter += 1;
    }
    okm.truncate(length);
    okm
}

/// RFC 8032 Ed25519, through the beta suite's signature seam.
///
/// The 1023-byte `TEST 1024` case is absent: its message is not reproducible by
/// hand and `vectors/README.md` records that exclusion.
#[test]
fn beta_suite_ed25519_rfc8032_known_answers() {
    let suite = beta_suite();
    let vectors = vectors();
    let cases = group(&vectors, "ed25519");
    assert!(!cases.is_empty(), "Ed25519 vectors are present");
    for case in cases {
        let public = SignaturePublicKey::from(bytes(case, "publicKey"));
        let message = bytes(case, "message");
        let expected = bytes(case, "signature");
        assert_eq!(
            expected.len(),
            ED25519_SIGNATURE_BYTES,
            "{}: signature length",
            name(case)
        );

        let derived = suite
            .signature_key_derive_public(&ed25519_secret(case))
            .expect("public key derivation succeeds");
        assert_eq!(
            derived.as_ref(),
            public.as_ref(),
            "{}: derived public key",
            name(case)
        );

        let signature = suite
            .sign(&ed25519_secret(case), &message)
            .expect("Ed25519 signing succeeds");
        assert_eq!(signature, expected, "{}: signature", name(case));
        suite
            .verify(&public, &signature, &message)
            .unwrap_or_else(|error| panic!("{}: verification failed: {error:?}", name(case)));

        let mut altered = signature;
        altered[0] ^= 1;
        assert!(
            suite.verify(&public, &altered, &message).is_err(),
            "{}: a modified signature was accepted",
            name(case)
        );
    }
}

/// FIPS 180-4 SHA-384, through the beta suite's hash seam.
#[test]
fn beta_suite_sha384_fips180_4_known_answers() {
    let suite = beta_suite();
    let vectors = vectors();
    let cases = group(&vectors, "sha384");
    assert!(!cases.is_empty(), "SHA-384 vectors are present");
    for case in cases {
        let digest = suite
            .hash(&bytes(case, "message"))
            .expect("SHA-384 succeeds");
        assert_eq!(digest.len(), SHA384_BYTES, "{}: digest length", name(case));
        assert_eq!(digest, bytes(case, "digest"), "{}: digest", name(case));
    }
}

/// RFC 4231 HMAC-SHA-384, through the beta suite's MAC seam.
///
/// The truncated `Test Case 5` is absent: RFC 4231 publishes only its leading
/// 128 bits, and the suite seam returns the full tag.
#[test]
fn beta_suite_hmac_sha384_rfc4231_known_answers() {
    let suite = beta_suite();
    let vectors = vectors();
    let cases = group(&vectors, "hmacSha384");
    assert!(!cases.is_empty(), "HMAC-SHA-384 vectors are present");
    for case in cases {
        let tag = suite
            .mac(&bytes(case, "key"), &bytes(case, "data"))
            .expect("HMAC-SHA-384 succeeds");
        assert_eq!(tag.len(), SHA384_BYTES, "{}: tag length", name(case));
        assert_eq!(tag, bytes(case, "tag"), "{}: tag", name(case));
    }
}

/// RFC 5869 section 2.2 defines `HKDF-Extract(salt, IKM) = HMAC-Hash(salt, IKM)`.
/// RFC 4231's published HMAC-SHA-384 tags are therefore published
/// HKDF-SHA-384 pseudo-random keys, read through that normative identity, and
/// they anchor the extract half of the suite's KDF against official numbers.
#[test]
fn beta_suite_hkdf_sha384_extract_matches_rfc4231_over_rfc5869_identity() {
    let suite = beta_suite();
    let vectors = vectors();
    assert_eq!(suite.kdf_extract_size(), SHA384_BYTES);
    for case in group(&vectors, "hmacSha384") {
        let prk = suite
            .kdf_extract(&bytes(case, "key"), &bytes(case, "data"))
            .expect("HKDF-SHA-384 extract succeeds");
        assert_eq!(&*prk, &bytes(case, "tag"), "{}: extracted PRK", name(case));
    }
}

/// RFC 5869 section 2.3 defines `HKDF-Expand` entirely in terms of HMAC-Hash.
///
/// No published `HKDF-SHA-384` expansion output could be vendored offline, so
/// this is a construction check rather than a known-answer test: the expected
/// value is recomputed from [`rfc5869_expand`] over the suite's own
/// HMAC-SHA-384, which the test above pins to RFC 4231. The two run through
/// different AWS-LC entry points (`HKDF_expand` against `hmac::sign`), and the
/// lengths cross the 48-byte block boundary so the `T(i)` chaining is
/// exercised. `vectors/README.md` records this as the one remaining gap.
#[test]
fn beta_suite_hkdf_sha384_expand_follows_rfc5869_construction() {
    let suite = beta_suite();
    let vectors = vectors();
    for case in group(&vectors, "hmacSha384") {
        // Each RFC 4231 tag is an official 48-byte PRK, the exact width
        // HKDF-SHA-384 extract produces.
        let prk = bytes(case, "tag");
        for info in [b"".as_slice(), b"mls beta expand context".as_slice()] {
            for length in [1, 47, 48, 49, 96, 144] {
                let expanded = suite
                    .kdf_expand(&prk, info, length)
                    .expect("HKDF-SHA-384 expand succeeds");
                assert_eq!(expanded.len(), length, "{}: expanded length", name(case));
                assert_eq!(
                    &*expanded,
                    &rfc5869_expand(&suite, &prk, info, length),
                    "{}: expansion for L={length}",
                    name(case)
                );
            }
        }
    }
}

/// AES-256-GCM, through the beta suite's AEAD seam.
///
/// The suite seals with a 12-byte nonce and appends the 16-byte tag, so each
/// case's expected ciphertext is compared as `ciphertext || tag`.
#[test]
fn beta_suite_aes256_gcm_known_answers() {
    let suite = beta_suite();
    let vectors = vectors();
    let cases = group(&vectors, "aes256Gcm");
    assert!(!cases.is_empty(), "AES-256-GCM vectors are present");
    assert_eq!(suite.aead_key_size(), AES256_KEY_BYTES);
    assert_eq!(suite.aead_nonce_size(), GCM_NONCE_BYTES);
    for case in cases {
        let key = bytes(case, "key");
        let nonce = bytes(case, "nonce");
        let aad = bytes(case, "aad");
        let plaintext = bytes(case, "plaintext");
        let mut expected = bytes(case, "ciphertext");
        let tag = bytes(case, "tag");
        assert_eq!(key.len(), AES256_KEY_BYTES, "{}: key length", name(case));
        assert_eq!(nonce.len(), GCM_NONCE_BYTES, "{}: nonce length", name(case));
        assert_eq!(tag.len(), GCM_TAG_BYTES, "{}: tag length", name(case));
        expected.extend_from_slice(&tag);

        let sealed = suite
            .aead_seal(&key, &plaintext, Some(&aad), &nonce)
            .expect("AES-256-GCM seal succeeds");
        assert_eq!(sealed, expected, "{}: ciphertext and tag", name(case));

        let opened = suite
            .aead_open(&key, &sealed, Some(&aad), &nonce)
            .expect("AES-256-GCM open succeeds");
        assert_eq!(&*opened, &plaintext, "{}: recovered plaintext", name(case));

        let mut wrong_aad = aad.clone();
        wrong_aad.push(0xff);
        assert!(
            suite
                .aead_open(&key, &sealed, Some(&wrong_aad), &nonce)
                .is_err(),
            "{}: ciphertext opened under the wrong associated data",
            name(case)
        );

        let mut tampered = sealed;
        let last = tampered.len() - 1;
        tampered[last] ^= 1;
        assert!(
            suite
                .aead_open(&key, &tampered, Some(&aad), &nonce)
                .is_err(),
            "{}: a modified tag was accepted",
            name(case)
        );
    }
}

/// FIPS 202 SHA3-256, through the very expression `mls_beta.rs` hands to
/// `combined_hpke` as the hybrid KEM's combiner hash.
#[test]
fn beta_kem_combiner_sha3_256_fips202_known_answers() {
    let combiner_hash =
        AwsLcHash::new_sha3(Sha3::SHA3_256).expect("SHA3-256 combiner hash is available");
    let vectors = vectors();
    let cases = group(&vectors, "sha3_256");
    assert!(!cases.is_empty(), "SHA3-256 vectors are present");
    for case in cases {
        let digest = combiner_hash
            .hash(&bytes(case, "message"))
            .expect("SHA3-256 succeeds");
        assert_eq!(
            digest.len(),
            SHA3_256_BYTES,
            "{}: digest length",
            name(case)
        );
        assert_eq!(digest, bytes(case, "digest"), "{}: digest", name(case));
    }
}

/// RFC 7748 X25519, through the `Ecdh` the beta hybrid KEM's `DHKEM` half uses.
#[test]
fn beta_kem_x25519_rfc7748_known_answers() {
    let ecdh = Ecdh::new(BETA_KEM_CLASSICAL_SUITE).expect("X25519 is available");
    let vectors = vectors();

    let scalar_cases = vectors["x25519"]["scalarMultiplication"]
        .as_array()
        .expect("X25519 scalar-multiplication vectors are an array");
    assert!(!scalar_cases.is_empty(), "X25519 vectors are present");
    for case in scalar_cases {
        let secret = HpkeSecretKey::from(bytes(case, "scalar"));
        let public = HpkePublicKey::from(bytes(case, "u"));
        let output = ecdh
            .dh(&secret, &public)
            .unwrap_or_else(|error| panic!("{}: X25519 failed: {error:?}", name(case)));
        assert_eq!(output, bytes(case, "output"), "{}: output", name(case));
    }

    let exchange = &vectors["x25519"]["diffieHellman"];
    let alice_secret = HpkeSecretKey::from(bytes(exchange, "alicePrivate"));
    let bob_secret = HpkeSecretKey::from(bytes(exchange, "bobPrivate"));
    let alice_public = HpkePublicKey::from(bytes(exchange, "alicePublic"));
    let bob_public = HpkePublicKey::from(bytes(exchange, "bobPublic"));
    let shared = bytes(exchange, "sharedSecret");

    assert_eq!(
        ecdh.to_public(&alice_secret)
            .expect("public key derivation succeeds")
            .as_ref(),
        alice_public.as_ref(),
        "RFC 7748 6.1: Alice public key"
    );
    assert_eq!(
        ecdh.to_public(&bob_secret)
            .expect("public key derivation succeeds")
            .as_ref(),
        bob_public.as_ref(),
        "RFC 7748 6.1: Bob public key"
    );
    assert_eq!(
        ecdh.dh(&alice_secret, &bob_public)
            .expect("X25519 succeeds"),
        shared,
        "RFC 7748 6.1: shared secret from Alice"
    );
    assert_eq!(
        ecdh.dh(&bob_secret, &alice_public)
            .expect("X25519 succeeds"),
        shared,
        "RFC 7748 6.1: shared secret from Bob"
    );
}

/// RFC 5869 HKDF-SHA-256, through the `AwsLcHkdf` the beta hybrid KEM's
/// `DHKEM(X25519, HKDF-SHA256)` half uses. Unlike the suite's own
/// HKDF-SHA-384, RFC 5869 publishes both the PRK and the OKM at SHA-256, so
/// extract and expand are both known-answer tested here.
#[test]
fn beta_kem_hkdf_sha256_rfc5869_known_answers() {
    let kdf = AwsLcHkdf::new(BETA_KEM_CLASSICAL_SUITE).expect("HKDF-SHA-256 is available");
    let vectors = vectors();
    let cases = group(&vectors, "hkdfSha256");
    assert!(!cases.is_empty(), "HKDF-SHA-256 vectors are present");
    for case in cases {
        let prk = kdf
            .extract(&bytes(case, "salt"), &bytes(case, "ikm"))
            .expect("HKDF-SHA-256 extract succeeds");
        assert_eq!(prk, bytes(case, "prk"), "{}: PRK", name(case));

        let length = usize::try_from(case["length"].as_u64().expect("length is an integer"))
            .expect("length fits in usize");
        let okm = kdf
            .expand(&prk, &bytes(case, "info"), length)
            .expect("HKDF-SHA-256 expand succeeds");
        assert_eq!(okm.len(), length, "{}: OKM length", name(case));
        assert_eq!(okm, bytes(case, "okm"), "{}: OKM", name(case));
    }
}

/// Guards the correspondence between the vectors above and the composition.
///
/// If `mls_beta.rs` ever selects a different hash, MAC, KDF, AEAD, signature,
/// or classical KEM half, the vectors would silently stop covering the shipped
/// mapping. Every parameter they assume is asserted here against the built
/// suite, and the two constructor expressions this module reproduces are
/// checked to yield the primitives they are supposed to.
#[test]
fn beta_suite_parameterization_matches_the_vectored_primitives() {
    let suite = beta_suite();
    assert_eq!(suite.cipher_suite(), BETA_CIPHERSUITE);

    // SHA-384 hash and HMAC-SHA-384 MAC.
    assert_eq!(suite.hash(b"").expect("hash succeeds").len(), SHA384_BYTES);
    assert_eq!(
        suite
            .mac(&[0; SHA384_BYTES], b"")
            .expect("MAC succeeds")
            .len(),
        SHA384_BYTES
    );

    // HKDF-SHA-384.
    assert_eq!(suite.kdf_extract_size(), SHA384_BYTES);
    assert_eq!(
        suite.kdf_extract(b"", b"").expect("extract succeeds").len(),
        SHA384_BYTES
    );

    // AES-256-GCM: 32-byte key, 12-byte nonce, 16-byte appended tag.
    assert_eq!(suite.aead_key_size(), AES256_KEY_BYTES);
    assert_eq!(suite.aead_nonce_size(), GCM_NONCE_BYTES);
    assert_eq!(
        suite
            .aead_seal(&[0; AES256_KEY_BYTES], b"", None, &[0; GCM_NONCE_BYTES])
            .expect("seal succeeds")
            .len(),
        GCM_TAG_BYTES
    );

    // Ed25519 with AWS-LC's 64-byte `seed || public key` secret.
    let (signature_secret, signature_public) = suite
        .signature_key_generate()
        .expect("signature key generation succeeds");
    assert_eq!(
        signature_secret.as_ref().len(),
        ED25519_SEED_BYTES + ED25519_PUBLIC_BYTES
    );
    assert_eq!(signature_public.as_ref().len(), ED25519_PUBLIC_BYTES);
    assert_eq!(
        suite
            .sign(&signature_secret, b"")
            .expect("signing succeeds")
            .len(),
        ED25519_SIGNATURE_BYTES
    );

    // The hybrid KEM public key is the ML-KEM-768 encapsulation key followed by
    // an X25519 public key, which is what makes the classical half X25519.
    let (_, kem_public) = suite.kem_generate().expect("KEM key generation succeeds");
    assert_eq!(
        kem_public.as_ref().len(),
        MLKEM768_PUBLIC_BYTES + X25519_KEY_BYTES
    );

    // The two constructor expressions this module reproduces from `mls_beta.rs`.
    let ecdh = Ecdh::new(BETA_KEM_CLASSICAL_SUITE).expect("X25519 is available");
    assert_eq!(ecdh.public_key_size(), X25519_KEY_BYTES);
    assert_eq!(ecdh.secret_key_size(), X25519_KEY_BYTES);
    let kem_kdf = AwsLcHkdf::new(BETA_KEM_CLASSICAL_SUITE).expect("HKDF-SHA-256 is available");
    assert_eq!(kem_kdf.kdf_id(), KdfId::HkdfSha256 as u16);
    assert_eq!(kem_kdf.extract_size(), 32);
    assert_eq!(
        AwsLcHash::new_sha3(Sha3::SHA3_256)
            .expect("SHA3-256 is available")
            .hash(b"")
            .expect("hash succeeds")
            .len(),
        SHA3_256_BYTES
    );
}

/// Keeps the fixture honest: every case must carry the fields its group's
/// harness reads, at the widths its primitive defines, so a future re-extraction
/// cannot quietly drop or reshape a case.
#[test]
fn beta_suite_vector_fixture_shapes_are_well_formed() {
    let vectors = vectors();
    for group_name in [
        "ed25519",
        "sha384",
        "sha3_256",
        "hmacSha384",
        "aes256Gcm",
        "hkdfSha256",
    ] {
        assert!(
            vectors[group_name]["source"]
                .as_str()
                .is_some_and(|source| { !source.is_empty() }),
            "{group_name} records its source"
        );
        for case in group(&vectors, group_name) {
            assert!(case["name"].is_string(), "{group_name}: case is named");
        }
    }

    for case in group(&vectors, "ed25519") {
        assert_eq!(bytes(case, "secretSeed").len(), ED25519_SEED_BYTES);
        assert_eq!(bytes(case, "publicKey").len(), ED25519_PUBLIC_BYTES);
        assert_eq!(bytes(case, "signature").len(), ED25519_SIGNATURE_BYTES);
    }
    for case in group(&vectors, "sha384") {
        assert_eq!(bytes(case, "digest").len(), SHA384_BYTES);
    }
    for case in group(&vectors, "sha3_256") {
        assert_eq!(bytes(case, "digest").len(), SHA3_256_BYTES);
    }
    for case in group(&vectors, "hmacSha384") {
        assert_eq!(bytes(case, "tag").len(), SHA384_BYTES);
    }
    for case in group(&vectors, "aes256Gcm") {
        assert_eq!(bytes(case, "key").len(), AES256_KEY_BYTES);
        assert_eq!(bytes(case, "nonce").len(), GCM_NONCE_BYTES);
        assert_eq!(bytes(case, "tag").len(), GCM_TAG_BYTES);
        assert_eq!(
            bytes(case, "ciphertext").len(),
            bytes(case, "plaintext").len(),
            "GCM is length preserving before the tag"
        );
    }
    for case in group(&vectors, "hkdfSha256") {
        assert_eq!(bytes(case, "prk").len(), 32);
        assert_eq!(
            bytes(case, "okm").len(),
            usize::try_from(case["length"].as_u64().expect("length is an integer"))
                .expect("length fits in usize")
        );
    }

    let vectors_x25519 = &vectors["x25519"];
    assert!(vectors_x25519["source"].is_string());
    for case in vectors_x25519["scalarMultiplication"]
        .as_array()
        .expect("scalar-multiplication vectors are an array")
    {
        for field in ["scalar", "u", "output"] {
            assert_eq!(bytes(case, field).len(), X25519_KEY_BYTES);
        }
    }
    for field in [
        "alicePrivate",
        "alicePublic",
        "bobPrivate",
        "bobPublic",
        "sharedSecret",
    ] {
        assert_eq!(
            bytes(&vectors_x25519["diffieHellman"], field).len(),
            X25519_KEY_BYTES
        );
    }

    // The AES-256-GCM group must keep at least one case with associated data
    // and one with a multi-block plaintext; otherwise the vectors would stop
    // covering the GHASH path that MLS ciphertexts actually exercise.
    let gcm = group(&vectors, "aes256Gcm");
    assert!(gcm.iter().any(|case| !bytes(case, "aad").is_empty()));
    assert!(gcm.iter().any(|case| bytes(case, "plaintext").len() > 16));
}
