//! Construction-level coverage for the beta hybrid KEM and its HPKE integration.
//!
//! **These are project vectors, not external conformance evidence.** Every
//! expected byte in `vectors/beta-hybrid-kem-project-kats.json` was produced by
//! this repository. No standards body, working group, or upstream project
//! publishes known answers for the construction `mls_beta.rs` assembles, because
//! that construction is not any published one: rows D1-D10 of
//! `docs/mls-profile.md` record ten verified differences from HPKE KEM `0x647a`
//! (X-Wing), the KEM `draft-ietf-mls-pq-ciphersuites-06` names for `TBD2`, and
//! its HPKE `kem_id` `0x000F` is unassigned at IANA. ADR-040 resolves that the
//! divergence stays. Nothing here may be cited as `TBD2`, `0x647a`, X-Wing, or
//! RFC 9180 conformance or interoperability evidence.
//!
//! What the vectors are for is regression: they detect change. The construction
//! reaches every beta Welcome, update-path node key, `KeyPackage` init key, and
//! HPKE export, and it is silent on the wire — `Npk`, `Nenc`, and `Nsecret` are
//! byte-identical to X-Wing's, so a change fails at decryption rather than at
//! parsing. Pinned bytes are what turns such a change into a test failure.
//!
//! Two seams are used:
//!
//! - The built beta suite's [`CipherSuiteProvider`] surface — `kem_derive`,
//!   `hpke_open`, `hpke_setup_r`, `hpke_seal` — which is what the beta actually
//!   calls.
//! - A reference recomputation of the same construction, assembled here from
//!   primitives that are *not* AWS-LC: `mlkem-native` for ML-KEM-768,
//!   `x25519-dalek` for X25519, and the `RustCrypto` `hkdf`/`sha2` crates for
//!   HKDF-SHA-256 and HKDF-SHA-384. SHA3-256 and AES-256-GCM have no second
//!   implementation in this crate, so they come from the same AWS-LC entry
//!   points, each already anchored to official vectors in `beta_suite_vectors`.
//!
//! The reference is what makes these more than a self-consistency check: it
//! seals the ciphertext the implementation then opens, and it reproduces the
//! combiner and RFC 9180 key schedule from documented inputs. What it cannot
//! reach is the `SHAKE-128` seed expansion (D6) — no dependency exposes it — so
//! the derived key bytes are pinned rather than reproduced. See
//! `vectors/README.md` for the full statement of what each test does and does
//! not establish.

use hkdf::Hkdf;
use mls_rs::{CipherSuiteProvider, CryptoProvider};
use mls_rs_core::crypto::{HpkeCiphertext, HpkeContextR, HpkePublicKey, HpkeSecretKey};
use mls_rs_crypto_awslc::{AwsLcCipherSuite, AwsLcHash, Sha3};
use mls_rs_crypto_traits::Hash;
use serde_json::Value;
use sha2::{Sha256, Sha384};

use crate::{
    mls_beta::{BETA_CIPHERSUITE, BetaMlsCryptoProvider},
    provider::{
        CryptoProvider as FoundationCryptoProvider, MLKEM_SHARED_BYTES, MLKEM768_CIPHERTEXT_BYTES,
        MLKEM768_PUBLIC_BYTES, MLKEM768_SECRET_BYTES, RustCryptoProvider, X25519_PUBLIC_BYTES,
        X25519_SECRET_BYTES,
    },
    random::FixedRandomProvider,
    secret::SecretBytes,
};

const VECTORS: &str = include_str!("../vectors/beta-hybrid-kem-project-kats.json");

/// The combiner label the vendored `mls-rs` `XWingSharedSecretHashInput` uses:
/// seven bytes with an embedded `0x0a`, placed *first* in the hash input.
const COMBINER_LABEL: [u8; 7] = [0x5c, 0x2e, 0x2f, 0x0a, 0x2f, 0x5e, 0x5c];
/// `XWingLabel` as the X-Wing draft defines it: six bytes, placed *last*.
/// Present only so the divergence can be demonstrated, never as conformance.
const XWING_LABEL: [u8; 6] = [0x5c, 0x2e, 0x2f, 0x2f, 0x5e, 0x5c];

/// The combined KEM's HPKE identifier. Unassigned at IANA; carried into the
/// HPKE `suite_id` and the KEM `dkp_prk` suite ID, which is what makes D4 reach
/// every beta key schedule.
const BETA_HPKE_KEM_ID: u16 = 15;
/// `TBD2`'s KEM. Used only to show that substituting it changes every derived
/// key, never to claim the beta implements it.
const XWING_HPKE_KEM_ID: u16 = 0x647a;
/// The inner `DHKEM(X25519, HKDF-SHA256)` keeps its own correct suite ID.
const DHKEM_X25519_KEM_ID: u16 = 0x0020;
const HKDF_SHA384_KDF_ID: u16 = 0x0002;
const AES256_GCM_AEAD_ID: u16 = 0x0002;

const HYBRID_PUBLIC_BYTES: usize = MLKEM768_PUBLIC_BYTES + X25519_PUBLIC_BYTES;
const HYBRID_SECRET_BYTES: usize = MLKEM768_SECRET_BYTES + X25519_SECRET_BYTES;
const HYBRID_ENC_BYTES: usize = MLKEM768_CIPHERTEXT_BYTES + X25519_PUBLIC_BYTES;
/// FIPS 203 lays out `dk` as `dk_PKE || ek || H(ek) || z`; for ML-KEM-768
/// `dk_PKE` is `384 * k = 1152` bytes.
const MLKEM768_DK_PKE_BYTES: usize = 1152;
const AES256_KEY_BYTES: usize = 32;
const GCM_NONCE_BYTES: usize = 12;
const GCM_TAG_BYTES: usize = 16;
const SHA384_BYTES: usize = 48;
const SHA3_256_BYTES: usize = 32;
const EXPORT_BYTES: usize = 32;

fn vectors() -> Value {
    serde_json::from_str(VECTORS).expect("vendored beta hybrid KEM vectors are valid JSON")
}

fn group<'a>(vectors: &'a Value, name: &str) -> &'a Vec<Value> {
    vectors[name]["cases"]
        .as_array()
        .unwrap_or_else(|| panic!("vector group {name} carries a case array"))
}

fn bytes(case: &Value, field: &str) -> Vec<u8> {
    let text = case[field]
        .as_str()
        .unwrap_or_else(|| panic!("{field} is a hex string"));
    assert!(text.len().is_multiple_of(2), "{field} hex has even length");
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            u8::from_str_radix(std::str::from_utf8(pair).expect("vector hex is ASCII"), 16)
                .expect("vector hex is valid")
        })
        .collect()
}

fn name(case: &Value) -> &str {
    case["name"].as_str().unwrap_or("unlabelled")
}

fn beta_suite() -> AwsLcCipherSuite {
    BetaMlsCryptoProvider
        .cipher_suite_provider(BETA_CIPHERSUITE)
        .expect("beta suite is configured")
}

fn foundation() -> RustCryptoProvider {
    RustCryptoProvider::default()
}

fn fixed_array<const N: usize>(bytes: &[u8], what: &str) -> [u8; N] {
    bytes
        .try_into()
        .unwrap_or_else(|_| panic!("{what} has {} bytes, expected {N}", bytes.len()))
}

// ---------------------------------------------------------------------------
// Reference construction, recomputed from primitives that are not AWS-LC.
// ---------------------------------------------------------------------------

/// RFC 9180's HPKE `suite_id`, `"HPKE" || kem_id || kdf_id || aead_id`.
fn hpke_suite_id(kem_id: u16) -> Vec<u8> {
    let mut suite_id = b"HPKE".to_vec();
    suite_id.extend_from_slice(&kem_id.to_be_bytes());
    suite_id.extend_from_slice(&HKDF_SHA384_KDF_ID.to_be_bytes());
    suite_id.extend_from_slice(&AES256_GCM_AEAD_ID.to_be_bytes());
    suite_id
}

/// RFC 9180's KEM suite ID, `"KEM" || kem_id`.
fn kem_suite_id(kem_id: u16) -> Vec<u8> {
    let mut suite_id = b"KEM".to_vec();
    suite_id.extend_from_slice(&kem_id.to_be_bytes());
    suite_id
}

fn labeled_ikm(suite_id: &[u8], label: &[u8], ikm: &[u8]) -> Vec<u8> {
    let mut labeled = b"HPKE-v1".to_vec();
    labeled.extend_from_slice(suite_id);
    labeled.extend_from_slice(label);
    labeled.extend_from_slice(ikm);
    labeled
}

fn labeled_info(suite_id: &[u8], label: &[u8], info: &[u8], length: usize) -> Vec<u8> {
    let mut labeled = u16::try_from(length)
        .expect("HPKE output length fits in u16")
        .to_be_bytes()
        .to_vec();
    labeled.extend_from_slice(b"HPKE-v1");
    labeled.extend_from_slice(suite_id);
    labeled.extend_from_slice(label);
    labeled.extend_from_slice(info);
    labeled
}

fn labeled_extract_sha384(suite_id: &[u8], salt: &[u8], label: &[u8], ikm: &[u8]) -> Vec<u8> {
    let (prk, _) = Hkdf::<Sha384>::extract(Some(salt), &labeled_ikm(suite_id, label, ikm));
    prk.to_vec()
}

fn labeled_expand_sha384(
    suite_id: &[u8],
    prk: &[u8],
    label: &[u8],
    info: &[u8],
    length: usize,
) -> Vec<u8> {
    let mut okm = vec![0u8; length];
    Hkdf::<Sha384>::from_prk(prk)
        .expect("HKDF-SHA-384 PRK is at least 48 bytes")
        .expand(&labeled_info(suite_id, label, info, length), &mut okm)
        .expect("HKDF-SHA-384 expand succeeds");
    okm
}

fn labeled_extract_sha256(suite_id: &[u8], salt: &[u8], label: &[u8], ikm: &[u8]) -> Vec<u8> {
    let (prk, _) = Hkdf::<Sha256>::extract(Some(salt), &labeled_ikm(suite_id, label, ikm));
    prk.to_vec()
}

fn labeled_expand_sha256(
    suite_id: &[u8],
    prk: &[u8],
    label: &[u8],
    info: &[u8],
    length: usize,
) -> Vec<u8> {
    let mut okm = vec![0u8; length];
    Hkdf::<Sha256>::from_prk(prk)
        .expect("HKDF-SHA-256 PRK is at least 32 bytes")
        .expand(&labeled_info(suite_id, label, info, length), &mut okm)
        .expect("HKDF-SHA-256 expand succeeds");
    okm
}

/// SHA3-256, from the same constructor `mls_beta.rs` hands the combiner.
/// `beta_suite_vectors` anchors this entry point in the NIST FIPS 202 examples.
fn sha3_256(data: &[u8]) -> Vec<u8> {
    AwsLcHash::new_sha3(Sha3::SHA3_256)
        .expect("SHA3-256 is available")
        .hash(data)
        .expect("SHA3-256 succeeds")
}

/// `DHKEM(X25519, HKDF-SHA256)`, RFC 9180 section 4.1, over the raw X25519
/// output. This is the classical contribution the vendored combiner consumes,
/// and D3 is that X-Wing consumes the raw output instead.
fn dhkem_shared_secret(raw_dh: &[u8], ephemeral_public: &[u8], recipient_public: &[u8]) -> Vec<u8> {
    let suite_id = kem_suite_id(DHKEM_X25519_KEM_ID);
    let eae_prk = labeled_extract_sha256(&suite_id, &[], b"eae_prk", raw_dh);
    let mut kem_context = ephemeral_public.to_vec();
    kem_context.extend_from_slice(recipient_public);
    labeled_expand_sha256(
        &suite_id,
        &eae_prk,
        b"shared_secret",
        &kem_context,
        MLKEM_SHARED_BYTES,
    )
}

/// The vendored combiner: label first, then `ss_mlkem`, the `DHKEM` secret, the
/// ephemeral X25519 public key, and the recipient X25519 public key.
fn beta_combiner(
    mlkem_shared: &[u8],
    dhkem_shared: &[u8],
    ephemeral_public: &[u8],
    recipient_public: &[u8],
) -> Vec<u8> {
    let mut input = COMBINER_LABEL.to_vec();
    input.extend_from_slice(mlkem_shared);
    input.extend_from_slice(dhkem_shared);
    input.extend_from_slice(ephemeral_public);
    input.extend_from_slice(recipient_public);
    sha3_256(&input)
}

/// The X-Wing combiner, for contrast only: the raw X25519 output, and the
/// six-byte label placed last.
fn xwing_combiner(
    mlkem_shared: &[u8],
    raw_dh: &[u8],
    ephemeral_public: &[u8],
    recipient_public: &[u8],
) -> Vec<u8> {
    let mut input = mlkem_shared.to_vec();
    input.extend_from_slice(raw_dh);
    input.extend_from_slice(ephemeral_public);
    input.extend_from_slice(recipient_public);
    input.extend_from_slice(&XWING_LABEL);
    sha3_256(&input)
}

/// RFC 9180 section 5.1 `KeySchedule` in `mode_base`, at HKDF-SHA-384.
struct KeySchedule {
    key: Vec<u8>,
    base_nonce: Vec<u8>,
    exporter_secret: Vec<u8>,
}

fn key_schedule(kem_id: u16, shared_secret: &[u8], info: &[u8]) -> KeySchedule {
    let suite_id = hpke_suite_id(kem_id);
    let psk_id_hash = labeled_extract_sha384(&suite_id, &[], b"psk_id_hash", b"");
    let info_hash = labeled_extract_sha384(&suite_id, &[], b"info_hash", info);
    let mut context = vec![0u8]; // mode_base
    context.extend_from_slice(&psk_id_hash);
    context.extend_from_slice(&info_hash);
    let secret = labeled_extract_sha384(&suite_id, shared_secret, b"secret", b"");
    KeySchedule {
        key: labeled_expand_sha384(&suite_id, &secret, b"key", &context, AES256_KEY_BYTES),
        base_nonce: labeled_expand_sha384(
            &suite_id,
            &secret,
            b"base_nonce",
            &context,
            GCM_NONCE_BYTES,
        ),
        exporter_secret: labeled_expand_sha384(&suite_id, &secret, b"exp", &context, SHA384_BYTES),
    }
}

/// The decapsulation half of the reference: the shared secret a recipient
/// holding `secret_key`/`public_key` derives from `enc`.
fn reference_decapsulate(enc: &[u8], secret_key: &[u8], public_key: &[u8]) -> Vec<u8> {
    let (mlkem_ciphertext, ephemeral_public) = enc.split_at(MLKEM768_CIPHERTEXT_BYTES);
    let (mlkem_secret, classical_secret) = secret_key.split_at(MLKEM768_SECRET_BYTES);
    let classical_public = &public_key[MLKEM768_PUBLIC_BYTES..];

    let mlkem_shared = foundation()
        .mlkem768_decapsulate(
            &SecretBytes::new(fixed_array(mlkem_secret, "ML-KEM-768 decapsulation key")),
            &fixed_array(mlkem_ciphertext, "ML-KEM-768 ciphertext"),
        )
        .expect("ML-KEM-768 decapsulation succeeds");

    let raw_dh = foundation()
        .x25519_shared(
            &SecretBytes::new(fixed_array(classical_secret, "X25519 secret")),
            &fixed_array(ephemeral_public, "X25519 ephemeral public key"),
        )
        .expect("X25519 succeeds");

    let dhkem = dhkem_shared_secret(raw_dh.expose(), ephemeral_public, classical_public);
    beta_combiner(
        mlkem_shared.expose(),
        &dhkem,
        ephemeral_public,
        classical_public,
    )
}

// ---------------------------------------------------------------------------
// Key derivation.
// ---------------------------------------------------------------------------

/// Pins the exact bytes `kem_derive` returns.
///
/// **Proves:** the whole derivation chain is byte-stable — the `dkp_prk`
/// extraction under `"KEM" || 0x000F` (D5), the SHAKE-128 expansion to 96 bytes
/// and its 64/32 split (D6), ML-KEM-768 deterministic keygen over the first 64,
/// the RFC 9180 labeled expansion of the X25519 scalar (D7), and the 2,432-byte
/// serialized private key (D9). Any change to any of them fails here.
///
/// **Does not prove:** that any of that is correct, standard, or interoperable.
/// The expected bytes came from this implementation.
#[test]
fn beta_hybrid_kem_derive_pins_project_vector_bytes() {
    let suite = beta_suite();
    let vectors = vectors();
    let cases = group(&vectors, "kemDerive");
    assert!(!cases.is_empty(), "key derivation vectors are present");
    for case in cases {
        let ikm = bytes(case, "ikm");
        let (secret, public) = suite
            .kem_derive(&ikm)
            .unwrap_or_else(|error| panic!("{}: kem_derive failed: {error:?}", name(case)));
        assert_eq!(
            secret.as_ref(),
            bytes(case, "secretKey"),
            "{}: secret key",
            name(case)
        );
        assert_eq!(
            public.as_ref(),
            bytes(case, "publicKey"),
            "{}: public key",
            name(case)
        );
        assert_eq!(secret.as_ref().len(), HYBRID_SECRET_BYTES);
        assert_eq!(public.as_ref().len(), HYBRID_PUBLIC_BYTES);

        // Deriving twice from the same ikm must agree; nothing in the chain may
        // consume fresh randomness.
        let (again, _) = suite.kem_derive(&ikm).expect("kem_derive repeats");
        assert_eq!(again.as_ref(), secret.as_ref(), "{}: repeat", name(case));
    }
}

/// Checks the parts of the derived key pair that can be reproduced or
/// cross-checked without AWS-LC.
///
/// **Proves:** `dkp_prk` is exactly the HPKE labeled extract over `"KEM" ||
/// 0x000F` at HKDF-SHA-384, recomputed with `RustCrypto` rather than AWS-LC; the
/// derived `dk` is a well-formed FIPS 203 decapsulation key whose embedded `ek`
/// is the returned public half and whose `H(ek)` is the real SHA3-256 digest;
/// `mlkem-native` accepts the AWS-LC-derived pair and round-trips against it;
/// and `x25519-dalek` agrees that the classical halves are a matching pair.
///
/// **Does not prove:** the SHAKE-128 expansion (D6). No dependency of this
/// crate exposes SHAKE-128, so `d` — unlike `z`, which FIPS 203 stores in `dk` —
/// cannot be recovered and the expansion cannot be reproduced here. Upstream
/// carries its own FIPS 202 SHAKE-128 test.
#[test]
fn beta_hybrid_kem_derive_structure_is_independently_reproducible() {
    let suite = beta_suite();
    let vectors = vectors();
    for case in group(&vectors, "kemDerive") {
        let ikm = bytes(case, "ikm");
        let (secret, public) = suite.kem_derive(&ikm).expect("kem_derive succeeds");

        let recomputed =
            labeled_extract_sha384(&kem_suite_id(BETA_HPKE_KEM_ID), &[], b"dkp_prk", &ikm);
        assert_eq!(
            recomputed,
            bytes(case, "dkpPrk"),
            "{}: dkp_prk under \"KEM\" || 0x000F",
            name(case)
        );
        assert_eq!(recomputed.len(), SHA384_BYTES);

        let decapsulation_key = &secret.as_ref()[..MLKEM768_SECRET_BYTES];
        let encapsulation_key = &public.as_ref()[..MLKEM768_PUBLIC_BYTES];
        let embedded = &decapsulation_key
            [MLKEM768_DK_PKE_BYTES..MLKEM768_DK_PKE_BYTES + MLKEM768_PUBLIC_BYTES];
        assert_eq!(
            embedded,
            encapsulation_key,
            "{}: dk embeds the returned ek",
            name(case)
        );
        let embedded_digest = &decapsulation_key[MLKEM768_DK_PKE_BYTES + MLKEM768_PUBLIC_BYTES
            ..MLKEM768_DK_PKE_BYTES + MLKEM768_PUBLIC_BYTES + SHA3_256_BYTES];
        assert_eq!(
            embedded_digest,
            sha3_256(encapsulation_key),
            "{}: dk embeds H(ek)",
            name(case)
        );

        // mlkem-native, a different ML-KEM-768 build, accepts the derived pair.
        let (ciphertext, sender_shared) = foundation()
            .mlkem768_encapsulate(&fixed_array(encapsulation_key, "ek"))
            .expect("ML-KEM-768 encapsulation succeeds");
        let receiver_shared = foundation()
            .mlkem768_decapsulate(
                &SecretBytes::new(fixed_array(decapsulation_key, "dk")),
                &ciphertext,
            )
            .expect("ML-KEM-768 decapsulation succeeds");
        assert_eq!(
            sender_shared.expose(),
            receiver_shared.expose(),
            "{}: derived ML-KEM pair round-trips under mlkem-native",
            name(case)
        );

        // x25519-dalek agrees the classical halves belong together.
        let classical_secret = SecretBytes::new(fixed_array(
            &secret.as_ref()[MLKEM768_SECRET_BYTES..],
            "X25519 secret",
        ));
        assert_eq!(
            foundation()
                .x25519_public(&classical_secret)
                .expect("X25519 public key derivation succeeds")
                .as_slice(),
            &public.as_ref()[MLKEM768_PUBLIC_BYTES..],
            "{}: X25519 halves match",
            name(case)
        );
    }
}

// ---------------------------------------------------------------------------
// HPKE integration.
// ---------------------------------------------------------------------------

/// Pins one complete HPKE decryption per case.
///
/// **Proves:** the implementation still opens a ciphertext built from the
/// documented construction. Because the AEAD key is derived through the KEM
/// shared secret and a `suite_id` carrying `kem_id 0x000F`, a change anywhere —
/// combiner order, label bytes, the inner `DHKEM`, the `kem_id`, the KDF, the
/// AEAD — makes this fail. It also pins the exporter, and shows the AEAD
/// rejects a modified ciphertext, a modified `enc`, and modified associated
/// data.
///
/// **Does not prove:** conformance. The ciphertext was produced for this
/// construction by this repository.
#[test]
fn beta_hpke_open_matches_project_vector_bytes() {
    let suite = beta_suite();
    let vectors = vectors();
    let cases = group(&vectors, "hpke");
    assert!(!cases.is_empty(), "HPKE vectors are present");
    for case in cases {
        let secret = HpkeSecretKey::from(bytes(case, "recipientSecretKey"));
        let public = HpkePublicKey::from(bytes(case, "recipientPublicKey"));
        let info = bytes(case, "info");
        let aad = bytes(case, "aad");
        let plaintext = bytes(case, "plaintext");
        let enc = bytes(case, "enc");

        // The recipient key pair is the one the pinned ikm derives.
        let (derived_secret, derived_public) = suite
            .kem_derive(&bytes(case, "recipientIkm"))
            .expect("kem_derive succeeds");
        assert_eq!(derived_secret.as_ref(), secret.as_ref(), "{}", name(case));
        assert_eq!(derived_public.as_ref(), public.as_ref(), "{}", name(case));

        let ciphertext = HpkeCiphertext {
            kem_output: enc.clone(),
            ciphertext: bytes(case, "ciphertext"),
        };
        let opened = suite
            .hpke_open(&ciphertext, &secret, &public, &info, Some(&aad))
            .unwrap_or_else(|error| panic!("{}: hpke_open failed: {error:?}", name(case)));
        assert_eq!(opened.as_slice(), plaintext, "{}: plaintext", name(case));

        let context = suite
            .hpke_setup_r(&enc, &secret, &public, &info)
            .expect("HPKE receiver setup succeeds");
        let exported = context
            .export(&bytes(case, "exporterContext"), EXPORT_BYTES)
            .expect("HPKE export succeeds");
        assert_eq!(
            exported.as_slice(),
            bytes(case, "exportedValue"),
            "{}: exported value",
            name(case)
        );

        let mut tampered = ciphertext.clone();
        tampered.ciphertext[0] ^= 1;
        assert!(
            suite
                .hpke_open(&tampered, &secret, &public, &info, Some(&aad))
                .is_err(),
            "{}: a modified ciphertext was accepted",
            name(case)
        );

        let mut rewritten_enc = ciphertext.clone();
        rewritten_enc.kem_output[0] ^= 1;
        assert!(
            suite
                .hpke_open(&rewritten_enc, &secret, &public, &info, Some(&aad))
                .is_err(),
            "{}: a modified enc was accepted",
            name(case)
        );

        let mut other_aad = aad.clone();
        other_aad.push(0);
        assert!(
            suite
                .hpke_open(&ciphertext, &secret, &public, &info, Some(&other_aad))
                .is_err(),
            "{}: modified associated data was accepted",
            name(case)
        );
    }
}

/// Rebuilds every pinned HPKE value from the case inputs alone.
///
/// **Proves:** the fixture is re-derivable rather than opaque, and that the
/// construction this repository documents — the vendored combiner, the inner
/// `DHKEM(X25519, HKDF-SHA256)`, and RFC 9180's `mode_base` key schedule at
/// HKDF-SHA-384 under a `suite_id` carrying `kem_id 0x000F` — is the one the
/// implementation actually performs, since
/// [`beta_hpke_open_matches_project_vector_bytes`] opens exactly this
/// ciphertext. ML-KEM-768, X25519, and both HKDFs are recomputed here on
/// `mlkem-native`, `x25519-dalek`, and `RustCrypto`, so agreement is across
/// implementations rather than within one.
///
/// **Does not prove:** that the construction is a published one. It is not.
#[test]
fn beta_hpke_values_are_reproducible_from_the_documented_construction() {
    let suite = beta_suite();
    let vectors = vectors();
    for case in group(&vectors, "hpke") {
        let (shared, enc) = reproduce_encapsulation(case);
        reproduce_key_schedule(&suite, case, &shared);

        // Decapsulating the pinned enc reaches the same secret from the other side.
        assert_eq!(
            reference_decapsulate(
                &enc,
                &bytes(case, "recipientSecretKey"),
                &bytes(case, "recipientPublicKey")
            ),
            shared,
            "{}: decapsulation agrees with encapsulation",
            name(case)
        );
    }
}

/// The encapsulation half of the reproduction: every value from the ML-KEM
/// ciphertext through the combined shared secret, checked against the fixture.
fn reproduce_encapsulation(case: &Value) -> (Vec<u8>, Vec<u8>) {
    let public = bytes(case, "recipientPublicKey");
    let classical_public = &public[MLKEM768_PUBLIC_BYTES..];

    // ML-KEM-768 encapsulation, replayed deterministically on mlkem-native.
    let seeded = RustCryptoProvider::new(FixedRandomProvider::new(bytes(
        case,
        "mlkemEncapsulationSeed",
    )));
    let (mlkem_ciphertext, mlkem_shared) = seeded
        .mlkem768_encapsulate(&fixed_array(&public[..MLKEM768_PUBLIC_BYTES], "ek"))
        .expect("ML-KEM-768 encapsulation succeeds");
    assert_eq!(
        mlkem_ciphertext.as_slice(),
        bytes(case, "mlkemCiphertext"),
        "{}: ML-KEM ciphertext",
        name(case)
    );
    assert_eq!(
        mlkem_shared.expose().as_slice(),
        bytes(case, "mlkemSharedSecret"),
        "{}: ML-KEM shared secret",
        name(case)
    );

    // The X25519 ephemeral, on x25519-dalek.
    let ephemeral = SecretBytes::new(fixed_array(
        &bytes(case, "ephemeralX25519Secret"),
        "X25519 ephemeral secret",
    ));
    let ephemeral_public = foundation()
        .x25519_public(&ephemeral)
        .expect("X25519 public key derivation succeeds");
    assert_eq!(
        ephemeral_public.as_slice(),
        bytes(case, "x25519Enc"),
        "{}: X25519 enc",
        name(case)
    );
    let raw_dh = foundation()
        .x25519_shared(&ephemeral, &fixed_array(classical_public, "X25519 public"))
        .expect("X25519 succeeds");
    assert_eq!(
        raw_dh.expose().as_slice(),
        bytes(case, "x25519RawSharedSecret"),
        "{}: raw X25519 output",
        name(case)
    );

    // The inner DHKEM secret, then the combiner.
    let dhkem = dhkem_shared_secret(raw_dh.expose(), &ephemeral_public, classical_public);
    assert_eq!(
        dhkem,
        bytes(case, "dhkemSharedSecret"),
        "{}: DHKEM(X25519, HKDF-SHA256) shared secret",
        name(case)
    );
    let shared = beta_combiner(
        mlkem_shared.expose(),
        &dhkem,
        &ephemeral_public,
        classical_public,
    );
    assert_eq!(
        shared,
        bytes(case, "kemSharedSecret"),
        "{}: combined shared secret",
        name(case)
    );

    let mut enc = mlkem_ciphertext.to_vec();
    enc.extend_from_slice(&ephemeral_public);
    assert_eq!(enc, bytes(case, "enc"), "{}: enc", name(case));
    assert_eq!(enc.len(), HYBRID_ENC_BYTES);

    (shared, enc)
}

/// The RFC 9180 `mode_base` key schedule, the AEAD, and the exporter, checked
/// against the fixture for one case.
fn reproduce_key_schedule(suite: &AwsLcCipherSuite, case: &Value, shared: &[u8]) {
    let schedule = key_schedule(BETA_HPKE_KEM_ID, shared, &bytes(case, "info"));
    assert_eq!(schedule.key, bytes(case, "aeadKey"), "{}: key", name(case));
    assert_eq!(
        schedule.base_nonce,
        bytes(case, "baseNonce"),
        "{}: base nonce",
        name(case)
    );
    assert_eq!(
        schedule.exporter_secret,
        bytes(case, "exporterSecret"),
        "{}: exporter secret",
        name(case)
    );

    let sealed = suite
        .aead_seal(
            &schedule.key,
            &bytes(case, "plaintext"),
            Some(&bytes(case, "aad")),
            &schedule.base_nonce,
        )
        .expect("AES-256-GCM seal succeeds");
    assert_eq!(
        sealed,
        bytes(case, "ciphertext"),
        "{}: ciphertext",
        name(case)
    );

    assert_eq!(
        labeled_expand_sha384(
            &hpke_suite_id(BETA_HPKE_KEM_ID),
            &schedule.exporter_secret,
            b"sec",
            &bytes(case, "exporterContext"),
            EXPORT_BYTES,
        ),
        bytes(case, "exportedValue"),
        "{}: exported value",
        name(case)
    );
}

/// Covers the direction a static fixture cannot: the implementation's own
/// randomized encapsulation.
///
/// **Proves:** what `hpke_seal` produces is decryptable by the reference
/// construction — so the implementation's encapsulation, not only its
/// decapsulation, follows the documented combiner and key schedule.
///
/// **Does not prove:** anything about specification conformance, and nothing
/// about the ephemeral key generation beyond that it yields a usable pair.
#[test]
fn beta_hpke_seal_is_decryptable_by_the_reference_construction() {
    let suite = beta_suite();
    let vectors = vectors();
    for case in group(&vectors, "hpke") {
        let secret = bytes(case, "recipientSecretKey");
        let public = bytes(case, "recipientPublicKey");
        let info = bytes(case, "info");
        let aad = bytes(case, "aad");
        let plaintext = bytes(case, "plaintext");

        let sealed = suite
            .hpke_seal(
                &HpkePublicKey::from(public.clone()),
                &info,
                Some(&aad),
                &plaintext,
            )
            .expect("HPKE seal succeeds");
        assert_eq!(sealed.kem_output.len(), HYBRID_ENC_BYTES);
        assert_eq!(sealed.ciphertext.len(), plaintext.len() + GCM_TAG_BYTES);

        let shared = reference_decapsulate(&sealed.kem_output, &secret, &public);
        let schedule = key_schedule(BETA_HPKE_KEM_ID, &shared, &info);
        let opened = suite
            .aead_open(
                &schedule.key,
                &sealed.ciphertext,
                Some(&aad),
                &schedule.base_nonce,
            )
            .unwrap_or_else(|error| {
                panic!(
                    "{}: reference could not open hpke_seal: {error:?}",
                    name(case)
                )
            });
        assert_eq!(opened.as_slice(), plaintext, "{}", name(case));
    }
}

// ---------------------------------------------------------------------------
// Divergence probes. These pin the difference, never conformance.
// ---------------------------------------------------------------------------

/// Demonstrates D1, D2, and D3 as computed facts rather than prose.
///
/// **Proves:** the shared secret the beta derives is not the one X-Wing derives
/// from the same components, and that each of the three combiner differences —
/// label position, label bytes, raw versus `DHKEM` classical contribution —
/// changes the result on its own.
///
/// **Does not prove:** that the X-Wing value computed here is X-Wing's correct
/// answer. It is this repository's reading of the draft text, present only for
/// contrast. Nothing here is X-Wing conformance evidence in either direction.
#[test]
fn beta_hybrid_kem_is_not_the_xwing_construction() {
    let vectors = vectors();
    for case in group(&vectors, "hpke") {
        let mlkem_shared = bytes(case, "mlkemSharedSecret");
        let dhkem_shared = bytes(case, "dhkemSharedSecret");
        let raw_dh = bytes(case, "x25519RawSharedSecret");
        let ephemeral_public = bytes(case, "x25519Enc");
        let recipient_public = bytes(case, "recipientPublicKey")[MLKEM768_PUBLIC_BYTES..].to_vec();
        let shared = bytes(case, "kemSharedSecret");

        let xwing = xwing_combiner(&mlkem_shared, &raw_dh, &ephemeral_public, &recipient_public);
        assert_eq!(
            xwing,
            bytes(case, "xwingCombinerSharedSecret"),
            "{}: contrast value",
            name(case)
        );
        assert_ne!(xwing, shared, "{}: beta secret equals X-Wing's", name(case));

        // D1 alone: same seven-byte label, moved to the end.
        let mut moved = mlkem_shared.clone();
        moved.extend_from_slice(&dhkem_shared);
        moved.extend_from_slice(&ephemeral_public);
        moved.extend_from_slice(&recipient_public);
        moved.extend_from_slice(&COMBINER_LABEL);
        assert_ne!(
            sha3_256(&moved),
            shared,
            "{}: D1 label position",
            name(case)
        );

        // D2 alone: X-Wing's six-byte label in the vendored position.
        let mut relabelled = XWING_LABEL.to_vec();
        relabelled.extend_from_slice(&mlkem_shared);
        relabelled.extend_from_slice(&dhkem_shared);
        relabelled.extend_from_slice(&ephemeral_public);
        relabelled.extend_from_slice(&recipient_public);
        assert_ne!(
            sha3_256(&relabelled),
            shared,
            "{}: D2 label bytes",
            name(case)
        );
        assert_ne!(
            COMBINER_LABEL.as_slice(),
            XWING_LABEL.as_slice(),
            "the two labels differ"
        );

        // D3 alone: the raw X25519 output in place of the DHKEM secret.
        assert_ne!(
            raw_dh,
            dhkem_shared,
            "{}: DHKEM wraps the raw output",
            name(case)
        );
        assert_ne!(
            beta_combiner(&mlkem_shared, &raw_dh, &ephemeral_public, &recipient_public),
            shared,
            "{}: D3 classical contribution",
            name(case)
        );
    }
}

/// Demonstrates D4: the unassigned `kem_id` reaches the key schedule.
///
/// **Proves:** substituting `TBD2`'s `0x647a` for `0x000F` in the HPKE
/// `suite_id`, changing nothing else, yields a different AEAD key, base nonce,
/// and exporter secret, and the pinned ciphertext no longer opens. That is why
/// D4 cannot be treated as a labelling detail: it binds into every beta key
/// schedule.
///
/// **Does not prove:** what a real `0x647a` implementation would produce. Its
/// KEM shared secret would differ too; only the `suite_id` is varied here.
#[test]
fn beta_hpke_suite_id_binds_the_unassigned_kem_id() {
    let suite = beta_suite();
    let vectors = vectors();
    for case in group(&vectors, "hpke") {
        let shared = bytes(case, "kemSharedSecret");
        let info = bytes(case, "info");
        let beta = key_schedule(BETA_HPKE_KEM_ID, &shared, &info);
        let substituted = key_schedule(XWING_HPKE_KEM_ID, &shared, &info);

        assert_eq!(beta.key, bytes(case, "aeadKey"), "{}", name(case));
        assert_ne!(beta.key, substituted.key, "{}: AEAD key", name(case));
        assert_ne!(
            beta.base_nonce,
            substituted.base_nonce,
            "{}: base nonce",
            name(case)
        );
        assert_ne!(
            beta.exporter_secret,
            substituted.exporter_secret,
            "{}: exporter secret",
            name(case)
        );
        assert!(
            suite
                .aead_open(
                    &substituted.key,
                    &bytes(case, "ciphertext"),
                    Some(&bytes(case, "aad")),
                    &substituted.base_nonce,
                )
                .is_err(),
            "{}: the pinned ciphertext opened under kem_id 0x647a",
            name(case)
        );
    }
}

/// Demonstrates D8: the MLS-visible encapsulation-key check is a no-op.
///
/// **Proves:** `kem_public_key_validate` accepts an all-zero key, a truncated
/// key, and an empty key. X-Wing makes the ML-KEM-768 encapsulation-key check
/// of FIPS 203 section 7.2 a MUST; the vendored combiner returns `Ok(())`
/// unconditionally, so whatever checking happens is whatever AWS-LC does
/// internally at encapsulation time.
///
/// **Does not prove:** that beta traffic is exploitable. This pins current
/// behaviour so that an upstream fix, or a regression, is visible. If upstream
/// implements the check this test fails and D8 must be re-recorded.
#[test]
fn beta_hybrid_kem_public_key_validation_is_a_no_op() {
    let suite = beta_suite();
    for (label, key) in [
        ("all-zero hybrid key", vec![0u8; HYBRID_PUBLIC_BYTES]),
        ("truncated key", vec![0u8; 1]),
        ("empty key", Vec::new()),
    ] {
        assert!(
            suite
                .kem_public_key_validate(&HpkePublicKey::from(key))
                .is_ok(),
            "{label}: validation unexpectedly rejected the key — D8 may be stale"
        );
    }
}

// ---------------------------------------------------------------------------
// Guards.
// ---------------------------------------------------------------------------

/// Keeps the composition and the vectors in step.
///
/// If `mls_beta.rs` ever changes the KEM halves, the KDF, or the AEAD, the
/// pinned bytes above would keep passing only by coincidence or would fail
/// without saying why. Every size and identifier the reference construction
/// assumes is asserted here against the built suite.
#[test]
fn beta_hybrid_kem_parameterization_matches_the_project_vectors() {
    let suite = beta_suite();
    assert_eq!(suite.cipher_suite(), BETA_CIPHERSUITE);
    assert_eq!(suite.kdf_extract_size(), SHA384_BYTES);
    assert_eq!(suite.aead_key_size(), AES256_KEY_BYTES);
    assert_eq!(suite.aead_nonce_size(), GCM_NONCE_BYTES);

    let (secret, public) = suite.kem_generate().expect("KEM key generation succeeds");
    assert_eq!(secret.as_ref().len(), HYBRID_SECRET_BYTES);
    assert_eq!(public.as_ref().len(), HYBRID_PUBLIC_BYTES);

    let sealed = suite
        .hpke_seal(&public, b"", None, b"probe")
        .expect("HPKE seal succeeds");
    assert_eq!(sealed.kem_output.len(), HYBRID_ENC_BYTES);
    assert_eq!(
        suite
            .hpke_open(&sealed, &secret, &public, b"", None)
            .expect("HPKE open succeeds")
            .as_slice(),
        b"probe"
    );

    assert_eq!(sha3_256(b"").len(), SHA3_256_BYTES);
    assert_eq!(COMBINER_LABEL.len(), 7);
    assert_eq!(XWING_LABEL.len(), 6);
}

/// Keeps the fixture honest.
///
/// Every case must carry the fields its harness reads at the widths the
/// construction defines, the recorded identifiers must match the constants this
/// module uses, and the provenance block must keep saying what these bytes are
/// not. A future edit cannot quietly reshape a case or soften the warning.
#[test]
fn beta_hybrid_kem_project_vector_fixture_is_well_formed() {
    let vectors = vectors();

    let provenance = &vectors["_provenance"];
    let kind = provenance["kind"].as_str().expect("provenance kind");
    assert!(
        kind.contains("PROJECT-GENERATED") && kind.contains("NOT EXTERNAL CONFORMANCE EVIDENCE"),
        "the provenance block must keep disclaiming external conformance"
    );
    let warning = provenance["warning"].as_str().expect("provenance warning");
    for required in ["TBD2", "0x647a", "X-Wing", "regression"] {
        assert!(
            warning.contains(required),
            "the provenance warning must keep naming {required}"
        );
    }

    let construction = &vectors["construction"];
    assert_eq!(
        construction["hpkeKemId"].as_u64(),
        Some(BETA_HPKE_KEM_ID.into())
    );
    assert_eq!(
        construction["hpkeKdfId"].as_u64(),
        Some(HKDF_SHA384_KDF_ID.into())
    );
    assert_eq!(
        construction["hpkeAeadId"].as_u64(),
        Some(AES256_GCM_AEAD_ID.into())
    );
    assert_eq!(
        construction["innerDhkemKemId"].as_u64(),
        Some(DHKEM_X25519_KEM_ID.into())
    );
    assert_eq!(
        bytes(construction, "combinerLabel"),
        COMBINER_LABEL.to_vec(),
        "recorded combiner label"
    );
    assert_eq!(
        bytes(construction, "xwingLabelForContrast"),
        XWING_LABEL.to_vec(),
        "recorded contrast label"
    );

    for case in group(&vectors, "kemDerive") {
        assert!(case["name"].is_string());
        assert!(!bytes(case, "ikm").is_empty());
        assert_eq!(bytes(case, "dkpPrk").len(), SHA384_BYTES);
        assert_eq!(bytes(case, "secretKey").len(), HYBRID_SECRET_BYTES);
        assert_eq!(bytes(case, "publicKey").len(), HYBRID_PUBLIC_BYTES);
    }

    let hpke = group(&vectors, "hpke");
    for case in hpke {
        assert!(case["name"].is_string());
        assert_eq!(bytes(case, "recipientIkm").len(), MLKEM_SHARED_BYTES);
        assert_eq!(
            bytes(case, "mlkemEncapsulationSeed").len(),
            MLKEM_SHARED_BYTES
        );
        assert_eq!(
            bytes(case, "ephemeralX25519Secret").len(),
            X25519_SECRET_BYTES
        );
        assert_eq!(bytes(case, "recipientSecretKey").len(), HYBRID_SECRET_BYTES);
        assert_eq!(bytes(case, "recipientPublicKey").len(), HYBRID_PUBLIC_BYTES);
        assert_eq!(
            bytes(case, "mlkemCiphertext").len(),
            MLKEM768_CIPHERTEXT_BYTES
        );
        assert_eq!(bytes(case, "enc").len(), HYBRID_ENC_BYTES);
        assert_eq!(bytes(case, "x25519Enc").len(), X25519_PUBLIC_BYTES);
        assert_eq!(bytes(case, "aeadKey").len(), AES256_KEY_BYTES);
        assert_eq!(bytes(case, "baseNonce").len(), GCM_NONCE_BYTES);
        assert_eq!(bytes(case, "exporterSecret").len(), SHA384_BYTES);
        assert_eq!(bytes(case, "exportedValue").len(), EXPORT_BYTES);
        assert_eq!(
            bytes(case, "ciphertext").len(),
            bytes(case, "plaintext").len() + GCM_TAG_BYTES,
            "AES-GCM appends a 16-byte tag"
        );
        for field in [
            "mlkemSharedSecret",
            "dhkemSharedSecret",
            "x25519RawSharedSecret",
            "kemSharedSecret",
            "xwingCombinerSharedSecret",
        ] {
            assert_eq!(bytes(case, field).len(), MLKEM_SHARED_BYTES, "{field}");
        }
        assert_ne!(
            bytes(case, "kemSharedSecret"),
            bytes(case, "xwingCombinerSharedSecret"),
            "the divergence must stay visible in the fixture"
        );
    }

    // The HPKE group must keep one case with associated data and a multi-block
    // plaintext, and one fully empty case; otherwise the GHASH path and the
    // empty-input edge would stop being covered.
    assert!(
        hpke.iter()
            .any(|case| !bytes(case, "aad").is_empty() && bytes(case, "plaintext").len() > 16)
    );
    assert!(hpke.iter().any(|case| bytes(case, "info").is_empty()
        && bytes(case, "aad").is_empty()
        && bytes(case, "plaintext").is_empty()));
}
