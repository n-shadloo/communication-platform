//! Official FIPS 203 known-answer coverage for ML-KEM-768.
//!
//! The vendored fixture is a verbatim subset of the NIST ACVP-Server vectors
//! (see `vectors/README.md` for source, revision, and the extraction recipe).
//! It is checked in, so nothing here reaches the network at build or test time.
//!
//! Every known-answer test drives the production surface —
//! [`CryptoProvider`]'s ML-KEM entry points backed by the vendored
//! `mlkem-native` build — rather than the C API directly, so the vectors also
//! pin the Rust seam: coin ordering, buffer sizes, and error mapping.
//!
//! Under `beta-pq-mls` the same vectors additionally drive AWS-LC's ML-KEM-768
//! and differential tests assert the two agree. See `vectors/README.md` for why
//! that check is weaker than two independent implementations would be.

use serde_json::Value;

use crate::{
    error::CryptoError,
    provider::{
        CryptoProvider, MLKEM_SHARED_BYTES, MLKEM768_CIPHERTEXT_BYTES, MLKEM768_PUBLIC_BYTES,
        MLKEM768_SECRET_BYTES, RustCryptoProvider,
    },
    random::FixedRandomProvider,
    secret::SecretBytes,
};

const VECTORS: &str = include_str!("../vectors/mlkem768-acvp-fips203.json");

/// FIPS 203 keygen randomness is `d || z`; encapsulation randomness is `m`.
const KEYGEN_SEED_BYTES: usize = 64;
const ENCAPS_SEED_BYTES: usize = 32;

fn vectors() -> Value {
    serde_json::from_str(VECTORS).expect("vendored ML-KEM vectors are valid JSON")
}

fn group<'a>(vectors: &'a Value, name: &str) -> &'a Vec<Value> {
    vectors[name]
        .as_array()
        .unwrap_or_else(|| panic!("vector group {name} is an array"))
}

fn hex(case: &Value, field: &str) -> Vec<u8> {
    case[field]
        .as_str()
        .unwrap_or_else(|| panic!("{field} is a hex string"))
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            u8::from_str_radix(std::str::from_utf8(pair).expect("vector hex is ASCII"), 16)
                .expect("vector hex is valid")
        })
        .collect()
}

fn hex_array<const N: usize>(case: &Value, field: &str) -> [u8; N] {
    hex(case, field)
        .try_into()
        .unwrap_or_else(|bytes: Vec<u8>| panic!("{field} has {} bytes, expected {N}", bytes.len()))
}

fn tc_id(case: &Value) -> u64 {
    case["tcId"].as_u64().expect("tcId is an integer")
}

/// A provider whose randomness is exactly the vector's published seed, so the
/// production entry points run deterministically.
fn seeded(seed: &[u8]) -> RustCryptoProvider<FixedRandomProvider> {
    RustCryptoProvider::new(FixedRandomProvider::new(seed.to_vec()))
}

fn keygen_seed(case: &Value) -> Vec<u8> {
    let mut seed = hex(case, "d");
    seed.extend_from_slice(&hex(case, "z"));
    assert_eq!(seed.len(), KEYGEN_SEED_BYTES, "keygen seed is d || z");
    seed
}

#[test]
fn mlkem768_acvp_key_generation_known_answers() {
    let vectors = vectors();
    let cases = group(&vectors, "keyGen");
    assert!(!cases.is_empty(), "keyGen vectors are present");
    for case in cases {
        let (public_key, secret_key) = seeded(&keygen_seed(case))
            .mlkem768_keypair()
            .unwrap_or_else(|error| panic!("tcId {}: keygen failed: {error:?}", tc_id(case)));
        assert_eq!(
            public_key.as_slice(),
            hex(case, "ek"),
            "tcId {}: encapsulation key",
            tc_id(case)
        );
        assert_eq!(
            secret_key.expose().as_slice(),
            hex(case, "dk"),
            "tcId {}: decapsulation key",
            tc_id(case)
        );
    }
}

#[test]
fn mlkem768_acvp_encapsulation_known_answers() {
    let vectors = vectors();
    let cases = group(&vectors, "encapsulation");
    assert!(!cases.is_empty(), "encapsulation vectors are present");
    for case in cases {
        let public_key = hex_array::<MLKEM768_PUBLIC_BYTES>(case, "ek");
        let seed = hex(case, "m");
        assert_eq!(seed.len(), ENCAPS_SEED_BYTES, "encapsulation seed is m");
        let (ciphertext, shared) = seeded(&seed)
            .mlkem768_encapsulate(&public_key)
            .unwrap_or_else(|error| {
                panic!("tcId {}: encapsulation failed: {error:?}", tc_id(case))
            });
        assert_eq!(
            ciphertext.as_slice(),
            hex(case, "c"),
            "tcId {}: ciphertext",
            tc_id(case)
        );
        assert_eq!(
            shared.expose().as_slice(),
            hex(case, "k"),
            "tcId {}: shared secret",
            tc_id(case)
        );
    }
}

/// Covers both ACVP decapsulation reasons: `valid decapsulation` and
/// `modified ciphertext`. The latter pins FIPS 203 implicit rejection, which
/// must return the deterministic `J(z || c)` value rather than an error.
#[test]
fn mlkem768_acvp_decapsulation_known_answers() {
    let vectors = vectors();
    let cases = group(&vectors, "decapsulation");
    assert!(!cases.is_empty(), "decapsulation vectors are present");
    let mut rejections = 0;
    for case in cases {
        let secret_key = SecretBytes::new(hex_array::<MLKEM768_SECRET_BYTES>(case, "dk"));
        let ciphertext = hex_array::<MLKEM768_CIPHERTEXT_BYTES>(case, "c");
        let shared = seeded(&[])
            .mlkem768_decapsulate(&secret_key, &ciphertext)
            .unwrap_or_else(|error| {
                panic!("tcId {}: decapsulation failed: {error:?}", tc_id(case))
            });
        assert_eq!(
            shared.expose().as_slice(),
            hex(case, "k"),
            "tcId {}: shared secret ({})",
            tc_id(case),
            case["reason"].as_str().unwrap_or("unlabelled")
        );
        if case["reason"].as_str() == Some("modified ciphertext") {
            rejections += 1;
        }
    }
    assert!(
        rejections > 0,
        "implicit-rejection cases are part of the fixture"
    );
}

/// ACVP's `decapsulationKeyCheck` cases carry a `dk` whose embedded `H(ek)` has
/// been corrupted. FIPS 203 requires the hash check to reject those, which the
/// vendored build surfaces as [`CryptoError::MalformedInput`]. A ciphertext that
/// is merely wrong must still be accepted and implicitly rejected, so this pins
/// the boundary between "bad key" and "bad ciphertext".
///
/// The sibling `encapsulationKeyCheck` group is deliberately absent: every
/// invalid case there is a wrong-length `ek` (1600 bytes rather than 1184),
/// which the typed provider seam cannot represent, so there is no runtime
/// behaviour left to pin.
#[test]
fn mlkem768_rejects_malformed_decapsulation_keys() {
    let vectors = vectors();
    let cases = group(&vectors, "decapsulationKeyCheck");
    assert!(!cases.is_empty(), "decapsulation key-check vectors present");
    for case in cases {
        let secret_key = SecretBytes::new(hex_array::<MLKEM768_SECRET_BYTES>(case, "dk"));
        let accepted = seeded(&[])
            .mlkem768_decapsulate(&secret_key, &[0x5a; MLKEM768_CIPHERTEXT_BYTES])
            .is_ok();
        assert_eq!(
            accepted,
            case["testPassed"].as_bool().expect("testPassed is a bool"),
            "tcId {}: decapsulation key acceptance ({})",
            tc_id(case),
            case["reason"].as_str().unwrap_or("unlabelled")
        );
    }
}

#[test]
fn mlkem768_vector_fixture_shapes_are_well_formed() {
    let vectors = vectors();
    for case in group(&vectors, "keyGen") {
        assert_eq!(hex(case, "d").len(), 32);
        assert_eq!(hex(case, "z").len(), 32);
        assert_eq!(hex(case, "ek").len(), MLKEM768_PUBLIC_BYTES);
        assert_eq!(hex(case, "dk").len(), MLKEM768_SECRET_BYTES);
    }
    for case in group(&vectors, "encapsulation") {
        assert_eq!(hex(case, "ek").len(), MLKEM768_PUBLIC_BYTES);
        assert_eq!(hex(case, "m").len(), ENCAPS_SEED_BYTES);
        assert_eq!(hex(case, "c").len(), MLKEM768_CIPHERTEXT_BYTES);
        assert_eq!(hex(case, "k").len(), MLKEM_SHARED_BYTES);
    }
    for case in group(&vectors, "decapsulation") {
        assert_eq!(hex(case, "dk").len(), MLKEM768_SECRET_BYTES);
        assert_eq!(hex(case, "c").len(), MLKEM768_CIPHERTEXT_BYTES);
        assert_eq!(hex(case, "k").len(), MLKEM_SHARED_BYTES);
    }
    for case in group(&vectors, "decapsulationKeyCheck") {
        assert_eq!(hex(case, "dk").len(), MLKEM768_SECRET_BYTES);
        assert!(case["testPassed"].is_boolean());
    }

    // Both ACVP decapsulation reasons must be represented, otherwise a future
    // re-extraction could silently drop the implicit-rejection coverage.
    let reasons: std::collections::BTreeSet<&str> = group(&vectors, "decapsulation")
        .iter()
        .filter_map(|case| case["reason"].as_str())
        .collect();
    assert_eq!(
        reasons,
        ["modified ciphertext", "valid decapsulation"]
            .into_iter()
            .collect()
    );
}

/// The vendored build must not accept a truncated or oversized secret key
/// through the typed seam; sizes are compile-time checked, so this pins the
/// error mapping for a structurally valid but wrong-content key instead.
#[test]
fn mlkem768_decapsulation_maps_failures_to_malformed_input() {
    let secret_key = SecretBytes::new([0u8; MLKEM768_SECRET_BYTES]);
    assert_eq!(
        match seeded(&[]).mlkem768_decapsulate(&secret_key, &[0u8; MLKEM768_CIPHERTEXT_BYTES]) {
            Err(error) => error,
            Ok(_) => panic!("an all-zero decapsulation key was accepted"),
        },
        CryptoError::MalformedInput
    );
}

#[cfg(feature = "beta-pq-mls")]
mod aws_lc {
    //! Thin deterministic driver over AWS-LC's ML-KEM-768, used only by the
    //! differential test. AWS-LC exposes the FIPS 203 seeds through its
    //! experimental deterministic KEM API, which is what makes a byte-exact
    //! comparison against the vendored build possible.

    use aws_lc_sys::{
        EVP_PKEY, EVP_PKEY_CTX, EVP_PKEY_CTX_free, EVP_PKEY_CTX_kem_set_params, EVP_PKEY_CTX_new,
        EVP_PKEY_CTX_new_id, EVP_PKEY_KEM, EVP_PKEY_decapsulate,
        EVP_PKEY_encapsulate_deterministic, EVP_PKEY_free, EVP_PKEY_get_raw_private_key,
        EVP_PKEY_get_raw_public_key, EVP_PKEY_kem_new_raw_public_key,
        EVP_PKEY_kem_new_raw_secret_key, EVP_PKEY_keygen_deterministic, EVP_PKEY_keygen_init,
        NID_MLKEM768,
    };

    use crate::provider::{
        MLKEM_SHARED_BYTES, MLKEM768_CIPHERTEXT_BYTES, MLKEM768_PUBLIC_BYTES, MLKEM768_SECRET_BYTES,
    };

    struct Key(*mut EVP_PKEY);

    impl Drop for Key {
        fn drop(&mut self) {
            // SAFETY: `self.0` is a non-null EVP_PKEY owned by this guard.
            unsafe { EVP_PKEY_free(self.0) }
        }
    }

    struct Ctx(*mut EVP_PKEY_CTX);

    impl Drop for Ctx {
        fn drop(&mut self) {
            // SAFETY: `self.0` is a non-null EVP_PKEY_CTX owned by this guard.
            unsafe { EVP_PKEY_CTX_free(self.0) }
        }
    }

    fn ctx_for(key: &Key) -> Ctx {
        // SAFETY: `key.0` is a live EVP_PKEY; a null engine selects the default.
        let ctx = unsafe { EVP_PKEY_CTX_new(key.0, std::ptr::null_mut()) };
        assert!(!ctx.is_null(), "AWS-LC EVP_PKEY_CTX_new failed");
        Ctx(ctx)
    }

    /// FIPS 203 `ML-KEM.KeyGen_internal(d, z)` with `seed = d || z`.
    pub fn keypair(seed: &[u8; 64]) -> ([u8; MLKEM768_PUBLIC_BYTES], [u8; MLKEM768_SECRET_BYTES]) {
        // SAFETY: a null engine selects the default provider.
        let ctx = unsafe { EVP_PKEY_CTX_new_id(EVP_PKEY_KEM, std::ptr::null_mut()) };
        assert!(!ctx.is_null(), "AWS-LC EVP_PKEY_CTX_new_id failed");
        let ctx = Ctx(ctx);
        let mut raw: *mut EVP_PKEY = std::ptr::null_mut();
        let mut seed_len = seed.len();
        // SAFETY: `ctx.0` is live, `raw` is a valid out-pointer, and `seed` is a
        // 64-byte buffer matching MLKEM768_KEYGEN_SEED_LEN.
        let ok = unsafe {
            EVP_PKEY_CTX_kem_set_params(ctx.0, NID_MLKEM768) == 1
                && EVP_PKEY_keygen_init(ctx.0) == 1
                && EVP_PKEY_keygen_deterministic(
                    ctx.0,
                    &raw mut raw,
                    seed.as_ptr(),
                    &raw mut seed_len,
                ) == 1
        };
        assert!(ok, "AWS-LC deterministic ML-KEM-768 keygen failed");
        let key = Key(raw);

        let mut public_key = [0u8; MLKEM768_PUBLIC_BYTES];
        let mut public_len = public_key.len();
        let mut secret_key = [0u8; MLKEM768_SECRET_BYTES];
        let mut secret_len = secret_key.len();
        // SAFETY: both buffers are exactly the ML-KEM-768 raw key sizes AWS-LC
        // reports for NID_MLKEM768.
        let ok = unsafe {
            EVP_PKEY_get_raw_public_key(key.0, public_key.as_mut_ptr(), &raw mut public_len) == 1
                && EVP_PKEY_get_raw_private_key(key.0, secret_key.as_mut_ptr(), &raw mut secret_len)
                    == 1
        };
        assert!(ok, "AWS-LC raw ML-KEM-768 key export failed");
        assert_eq!(public_len, MLKEM768_PUBLIC_BYTES);
        assert_eq!(secret_len, MLKEM768_SECRET_BYTES);
        (public_key, secret_key)
    }

    /// FIPS 203 `ML-KEM.Encaps_internal(ek, m)` with `seed = m`.
    pub fn encapsulate(
        public_key: &[u8; MLKEM768_PUBLIC_BYTES],
        seed: &[u8; 32],
    ) -> Option<([u8; MLKEM768_CIPHERTEXT_BYTES], [u8; MLKEM_SHARED_BYTES])> {
        // SAFETY: `public_key` is a 1184-byte buffer, the raw ek length AWS-LC
        // expects for NID_MLKEM768.
        let raw = unsafe {
            EVP_PKEY_kem_new_raw_public_key(
                NID_MLKEM768,
                public_key.as_ptr(),
                MLKEM768_PUBLIC_BYTES,
            )
        };
        if raw.is_null() {
            return None;
        }
        let key = Key(raw);
        let ctx = ctx_for(&key);
        let mut ciphertext = [0u8; MLKEM768_CIPHERTEXT_BYTES];
        let mut ciphertext_len = ciphertext.len();
        let mut shared = [0u8; MLKEM_SHARED_BYTES];
        let mut shared_len = shared.len();
        let mut seed_len = seed.len();
        // SAFETY: every buffer is exactly the length AWS-LC reports for
        // NID_MLKEM768, and the lengths are passed as in/out parameters.
        let ok = unsafe {
            EVP_PKEY_encapsulate_deterministic(
                ctx.0,
                ciphertext.as_mut_ptr(),
                &raw mut ciphertext_len,
                shared.as_mut_ptr(),
                &raw mut shared_len,
                seed.as_ptr(),
                &raw mut seed_len,
            ) == 1
        };
        if !ok {
            return None;
        }
        assert_eq!(ciphertext_len, MLKEM768_CIPHERTEXT_BYTES);
        assert_eq!(shared_len, MLKEM_SHARED_BYTES);
        Some((ciphertext, shared))
    }

    /// FIPS 203 `ML-KEM.Decaps(dk, c)`, including implicit rejection.
    pub fn decapsulate(
        secret_key: &[u8; MLKEM768_SECRET_BYTES],
        ciphertext: &[u8; MLKEM768_CIPHERTEXT_BYTES],
    ) -> Option<[u8; MLKEM_SHARED_BYTES]> {
        // SAFETY: `secret_key` is a 2400-byte buffer, the raw dk length AWS-LC
        // expects for NID_MLKEM768.
        let raw = unsafe {
            EVP_PKEY_kem_new_raw_secret_key(
                NID_MLKEM768,
                secret_key.as_ptr(),
                MLKEM768_SECRET_BYTES,
            )
        };
        if raw.is_null() {
            return None;
        }
        let key = Key(raw);
        let ctx = ctx_for(&key);
        let mut shared = [0u8; MLKEM_SHARED_BYTES];
        let mut shared_len = shared.len();
        // SAFETY: `shared` is 32 bytes and `ciphertext` is 1088, both matching
        // the lengths AWS-LC reports for NID_MLKEM768.
        let ok = unsafe {
            EVP_PKEY_decapsulate(
                ctx.0,
                shared.as_mut_ptr(),
                &raw mut shared_len,
                ciphertext.as_ptr(),
                MLKEM768_CIPHERTEXT_BYTES,
            ) == 1
        };
        if !ok {
            return None;
        }
        assert_eq!(shared_len, MLKEM_SHARED_BYTES);
        Some(shared)
    }
}

// The differential tests below compare the vendored `mlkem-native` build
// against AWS-LC's ML-KEM-768 on identical input. Both builds descend from the
// same upstream project at different revisions and with different FIPS 202
// backends, so these are cross-build agreement checks, not
// independent-implementation checks. `vectors/README.md` records that limit.

/// Key generation must agree byte-for-byte on `ek` and `dk`.
#[cfg(feature = "beta-pq-mls")]
#[test]
fn mlkem768_key_generation_agrees_with_aws_lc() {
    let vectors = vectors();
    for case in group(&vectors, "keyGen") {
        let seed: [u8; KEYGEN_SEED_BYTES] = keygen_seed(case)
            .try_into()
            .expect("keygen seed is 64 bytes");
        let (ours_public, ours_secret) = seeded(&seed).mlkem768_keypair().unwrap();
        let (theirs_public, theirs_secret) = aws_lc::keypair(&seed);
        assert_eq!(
            ours_public,
            theirs_public,
            "tcId {}: encapsulation keys diverge",
            tc_id(case)
        );
        assert_eq!(
            ours_secret.expose(),
            &theirs_secret,
            "tcId {}: decapsulation keys diverge",
            tc_id(case)
        );
    }
}

/// Encapsulation must agree byte-for-byte on the ciphertext and shared secret.
#[cfg(feature = "beta-pq-mls")]
#[test]
fn mlkem768_encapsulation_agrees_with_aws_lc() {
    let vectors = vectors();
    for case in group(&vectors, "encapsulation") {
        let public_key = hex_array::<MLKEM768_PUBLIC_BYTES>(case, "ek");
        let seed = hex_array::<ENCAPS_SEED_BYTES>(case, "m");
        let (ours_ciphertext, ours_shared) =
            seeded(&seed).mlkem768_encapsulate(&public_key).unwrap();
        let (theirs_ciphertext, theirs_shared) =
            aws_lc::encapsulate(&public_key, &seed).expect("AWS-LC encapsulation failed");
        assert_eq!(
            ours_ciphertext,
            theirs_ciphertext,
            "tcId {}: ciphertexts diverge",
            tc_id(case)
        );
        assert_eq!(
            ours_shared.expose(),
            &theirs_shared,
            "tcId {}: shared secrets diverge",
            tc_id(case)
        );
    }
}

/// Decapsulation must agree on both the valid and the implicitly rejected
/// cases, and both builds must accept or reject a malformed `dk` alike.
#[cfg(feature = "beta-pq-mls")]
#[test]
fn mlkem768_decapsulation_agrees_with_aws_lc() {
    let vectors = vectors();
    for case in group(&vectors, "decapsulation") {
        let secret_bytes = hex_array::<MLKEM768_SECRET_BYTES>(case, "dk");
        let ciphertext = hex_array::<MLKEM768_CIPHERTEXT_BYTES>(case, "c");
        let ours = seeded(&[])
            .mlkem768_decapsulate(&SecretBytes::new(secret_bytes), &ciphertext)
            .unwrap();
        let theirs =
            aws_lc::decapsulate(&secret_bytes, &ciphertext).expect("AWS-LC decapsulation failed");
        assert_eq!(
            ours.expose(),
            &theirs,
            "tcId {}: decapsulated secrets diverge ({})",
            tc_id(case),
            case["reason"].as_str().unwrap_or("unlabelled")
        );
    }

    for case in group(&vectors, "decapsulationKeyCheck") {
        let secret_bytes = hex_array::<MLKEM768_SECRET_BYTES>(case, "dk");
        let ciphertext = [0x5a; MLKEM768_CIPHERTEXT_BYTES];
        let ours = seeded(&[])
            .mlkem768_decapsulate(&SecretBytes::new(secret_bytes), &ciphertext)
            .ok();
        let theirs = aws_lc::decapsulate(&secret_bytes, &ciphertext);
        assert_eq!(
            ours.is_some(),
            theirs.is_some(),
            "tcId {}: key-check acceptance diverges ({})",
            tc_id(case),
            case["reason"].as_str().unwrap_or("unlabelled")
        );
        if let (Some(ours), Some(theirs)) = (ours, theirs) {
            assert_eq!(
                ours.expose(),
                &theirs,
                "tcId {}: implicitly rejected secrets diverge",
                tc_id(case)
            );
        }
    }
}

/// Cross-direction interoperability: a ciphertext produced by either build must
/// decapsulate to the same secret under the other. This depends on no published
/// output value, so it stays meaningful even if the vectors are re-extracted.
#[cfg(feature = "beta-pq-mls")]
#[test]
fn mlkem768_interoperates_with_aws_lc_in_both_directions() {
    let vectors = vectors();
    let encaps_seed = [0xa5u8; ENCAPS_SEED_BYTES];
    for case in group(&vectors, "keyGen") {
        let seed: [u8; KEYGEN_SEED_BYTES] = keygen_seed(case)
            .try_into()
            .expect("keygen seed is 64 bytes");
        let (public_key, secret_key) = seeded(&seed).mlkem768_keypair().unwrap();
        let secret_bytes = *secret_key.expose();

        let (ours_ciphertext, ours_shared) = seeded(&encaps_seed)
            .mlkem768_encapsulate(&public_key)
            .unwrap();
        let theirs_from_ours = aws_lc::decapsulate(&secret_bytes, &ours_ciphertext)
            .expect("AWS-LC decapsulation failed");
        assert_eq!(
            ours_shared.expose(),
            &theirs_from_ours,
            "tcId {}: AWS-LC could not decapsulate the vendored ciphertext",
            tc_id(case)
        );

        let (theirs_ciphertext, theirs_shared) =
            aws_lc::encapsulate(&public_key, &encaps_seed).expect("AWS-LC encapsulation failed");
        let ours_from_theirs = seeded(&[])
            .mlkem768_decapsulate(&SecretBytes::new(secret_bytes), &theirs_ciphertext)
            .unwrap();
        assert_eq!(
            ours_from_theirs.expose(),
            &theirs_shared,
            "tcId {}: vendored build could not decapsulate the AWS-LC ciphertext",
            tc_id(case)
        );
    }
}
