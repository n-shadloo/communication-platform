#![forbid(unsafe_op_in_unsafe_fn)]

mod bounds;
mod cbor;
pub mod device_signatures;
mod error;
mod provider;
mod random;
mod secret;

use std::{
    mem,
    panic::{AssertUnwindSafe, catch_unwind},
    ptr,
};

use cbor::{decode_foundation_record, encode_foundation_record};
use error::{CryptoError, CryptoResult};
use provider::{
    CryptoProvider, RustCryptoProvider, secretstream_pull, secretstream_pull_init,
    secretstream_push, secretstream_push_init,
};
use secret::{SecretBytes, SecretVec};

pub const ABI_VERSION: u32 = 1;
pub const CAPABILITIES_SIZE: usize = std::mem::size_of::<CpCryptoCapabilitiesV1>();
#[allow(clippy::cast_possible_truncation)] // The protocol bound is fixed below u32::MAX.
pub const MAX_INPUT_BYTES: u32 = bounds::MAX_INPUT_BYTES as u32;

pub const CAP_DETERMINISTIC_CBOR: u64 = 1 << 0;
pub const CAP_ED25519: u64 = 1 << 1;
pub const CAP_X25519: u64 = 1 << 2;
pub const CAP_MLKEM768: u64 = 1 << 3;
pub const CAP_ARGON2ID: u64 = 1 << 4;
pub const CAP_XCHACHA20POLY1305: u64 = 1 << 5;
pub const CAP_SHA2: u64 = 1 << 6;
pub const CAP_HKDF: u64 = 1 << 7;
pub const CAP_SECRETSTREAM: u64 = 1 << 8;
pub const CAP_SECURE_RANDOM: u64 = 1 << 9;
pub const CAP_ZEROIZING_SECRETS: u64 = 1 << 10;
pub const CAP_PANIC_CONTAINMENT: u64 = 1 << 11;

#[repr(C)]
pub struct CpCryptoCapabilitiesV1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub feature_bits: u64,
    pub max_input_bytes: u32,
    pub max_cbor_depth: u32,
    pub max_cbor_items: u32,
    pub reserved: u32,
}

const CAPABILITIES: CpCryptoCapabilitiesV1 = CpCryptoCapabilitiesV1 {
        #[allow(clippy::cast_possible_truncation)] // The repr(C) ABI is intentionally 32-bit sized.
        struct_size: CAPABILITIES_SIZE as u32,
    abi_version: ABI_VERSION,
    feature_bits: CAP_DETERMINISTIC_CBOR
        | CAP_ED25519
        | CAP_X25519
        | CAP_MLKEM768
        | CAP_ARGON2ID
        | CAP_XCHACHA20POLY1305
        | CAP_SHA2
        | CAP_HKDF
        | CAP_SECRETSTREAM
        | CAP_SECURE_RANDOM
        | CAP_ZEROIZING_SECRETS
        | CAP_PANIC_CONTAINMENT,
    max_input_bytes: MAX_INPUT_BYTES,
    max_cbor_depth: bounds::MAX_CBOR_DEPTH,
    max_cbor_items: bounds::MAX_CBOR_ITEMS,
    reserved: 0,
};

fn guard(operation: impl FnOnce() -> CryptoResult<()>) -> i32 {
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(Ok(())) => CryptoError::Ok.code(),
        Ok(Err(error)) => error.code(),
        Err(_) => CryptoError::PanicContained.code(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn cp_crypto_v1_abi_version() -> u32 {
    catch_unwind(|| ABI_VERSION).unwrap_or(0)
}

#[unsafe(no_mangle)]
/// Writes the version-1 public capability record.
///
/// # Safety
///
/// `output` must point to writable memory covering at least `output_len`
/// bytes for the duration of this call.
pub unsafe extern "C" fn cp_crypto_v1_capabilities(
    output: *mut CpCryptoCapabilitiesV1,
    output_len: usize,
) -> i32 {
    guard(|| {
        if output.is_null() {
            return Err(CryptoError::InvalidArgument);
        }
        if output_len < CAPABILITIES_SIZE {
            return Err(CryptoError::OutputTooSmall);
        }
        if !(output as usize).is_multiple_of(mem::align_of::<CpCryptoCapabilitiesV1>()) {
            return Err(CryptoError::InvalidArgument);
        }
        // SAFETY: the caller promises a writable buffer of at least
        // CAPABILITIES_SIZE bytes; null, length, and alignment are checked
        // above.
        unsafe {
            ptr::write(output, CAPABILITIES);
        }
        Ok(())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cp_crypto_v1_self_test() -> i32 {
    guard(run_self_test)
}

fn run_self_test() -> CryptoResult<()> {
    let provider = RustCryptoProvider::default();
    let empty_hash = provider.sha256(b"")?;
    if empty_hash
        != [
            0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14, 0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f,
            0xb9, 0x24, 0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c, 0xa4, 0x95, 0x99, 0x1b,
            0x78, 0x52, 0xb8, 0x55,
        ]
    {
        return Err(CryptoError::InternalFailure);
    }

    let encoded = encode_foundation_record(1, 0, b"self-test")?;
    let decoded = decode_foundation_record(&encoded)?;
    if decoded.version != 1 || decoded.kind != 0 || decoded.payload != b"self-test" {
        return Err(CryptoError::InternalFailure);
    }

    let ed_secret = SecretBytes::new([0x11; 32]);
    let ed_public = ed25519_dalek::SigningKey::from_bytes(ed_secret.expose())
        .verifying_key()
        .to_bytes();
    let signature = provider.ed25519_sign(&ed_secret, b"self-test")?;
    provider.ed25519_verify(&ed_public, b"self-test", &signature)?;

    let x_secret = SecretBytes::new([0x22; 32]);
    let x_public = provider.x25519_public(&x_secret)?;
    provider.x25519_shared(&x_secret, &x_public)?;

    let key = SecretBytes::new([0x33; 32]);
    let nonce = [0x44; 24];
    let plaintext = SecretVec::input(b"self-test")?;
    let ciphertext = provider.xchacha20poly1305_encrypt(&key, &nonce, &plaintext, b"aad")?;
    let plaintext = provider.xchacha20poly1305_decrypt(&key, &nonce, &ciphertext, b"aad")?;
    if plaintext.expose() != b"self-test" {
        return Err(CryptoError::InternalFailure);
    }

    let (kem_public, kem_secret) = provider.mlkem768_keypair()?;
    let (kem_ciphertext, sender_secret) = provider.mlkem768_encapsulate(&kem_public)?;
    let receiver_secret = provider.mlkem768_decapsulate(&kem_secret, &kem_ciphertext)?;
    if sender_secret.expose() != receiver_secret.expose() {
        return Err(CryptoError::InternalFailure);
    }

    let stream_key = SecretBytes::new([0x55; 32]);
    let stream_plaintext = SecretVec::input(b"self-test")?;
    let (mut push, header) = secretstream_push_init(&stream_key)?;
    let stream_ciphertext = secretstream_push(&mut push, &stream_plaintext, b"", true)?;
    let mut pull = secretstream_pull_init(&stream_key, &header)?;
    let (stream_plaintext, final_message) = secretstream_pull(&mut pull, &stream_ciphertext, b"")?;
    if !final_message || stream_plaintext.expose() != b"self-test" {
        return Err(CryptoError::InternalFailure);
    }
    let _ = SecretVec::input(&[0x66; 32])?;
    device_signatures::verify_backend_vectors(&provider)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{mem, ptr};

    use super::{
        ABI_VERSION, CAP_ARGON2ID, CAP_DETERMINISTIC_CBOR, CAP_ED25519, CAP_HKDF, CAP_MLKEM768,
        CAP_PANIC_CONTAINMENT, CAP_SECRETSTREAM, CAP_SECURE_RANDOM, CAP_SHA2, CAP_X25519,
        CAP_XCHACHA20POLY1305, CAP_ZEROIZING_SECRETS, CAPABILITIES_SIZE, CpCryptoCapabilitiesV1,
        cp_crypto_v1_abi_version, cp_crypto_v1_capabilities, cp_crypto_v1_self_test, guard,
    };
    use crate::error::CryptoError;

    #[allow(clippy::cast_ptr_alignment)] // Deliberately constructs a malformed C pointer.
    #[test]
    fn abi_is_versioned_and_size_checked() {
        assert_eq!(cp_crypto_v1_abi_version(), ABI_VERSION);
        let mut capabilities = CpCryptoCapabilitiesV1 {
            struct_size: 0,
            abi_version: 0,
            feature_bits: 0,
            max_input_bytes: 0,
            max_cbor_depth: 0,
            max_cbor_items: 0,
            reserved: 0,
        };
        assert_eq!(
            unsafe {
                cp_crypto_v1_capabilities(
                    &raw mut capabilities,
                    CAPABILITIES_SIZE.saturating_sub(1),
                )
            },
            CryptoError::OutputTooSmall.code()
        );
        assert_eq!(
            unsafe { cp_crypto_v1_capabilities(ptr::null_mut(), CAPABILITIES_SIZE) },
            CryptoError::InvalidArgument.code()
        );
        assert_eq!(
            unsafe { cp_crypto_v1_capabilities(&raw mut capabilities, CAPABILITIES_SIZE) },
            CryptoError::Ok.code()
        );
        assert_eq!(capabilities.abi_version, ABI_VERSION);
        assert_eq!(capabilities.struct_size as usize, CAPABILITIES_SIZE);
        assert_eq!(
            capabilities.feature_bits,
            CAP_DETERMINISTIC_CBOR
                | CAP_ED25519
                | CAP_X25519
                | CAP_MLKEM768
                | CAP_ARGON2ID
                | CAP_XCHACHA20POLY1305
                | CAP_SHA2
                | CAP_HKDF
                | CAP_SECRETSTREAM
                | CAP_SECURE_RANDOM
                | CAP_ZEROIZING_SECRETS
                | CAP_PANIC_CONTAINMENT
        );

        let mut unaligned_storage =
            vec![0u8; CAPABILITIES_SIZE + mem::align_of::<CpCryptoCapabilitiesV1>()];
        let base = unaligned_storage.as_mut_ptr() as usize;
        let offset = (0..mem::align_of::<CpCryptoCapabilitiesV1>())
            .find(|offset| {
                !(base + offset).is_multiple_of(mem::align_of::<CpCryptoCapabilitiesV1>())
            })
            .expect("capability record alignment exceeds one byte");
        let unaligned = unaligned_storage
            .as_mut_ptr()
            .wrapping_add(offset)
            .cast::<CpCryptoCapabilitiesV1>();
        assert_eq!(
            unsafe { cp_crypto_v1_capabilities(unaligned, CAPABILITIES_SIZE) },
            CryptoError::InvalidArgument.code()
        );
    }

    #[test]
    fn self_test_is_panic_contained_and_successful() {
        assert_eq!(cp_crypto_v1_self_test(), CryptoError::Ok.code());
        assert_eq!(
            guard(|| panic!("intentional input-free containment test")),
            CryptoError::PanicContained.code()
        );
    }

    #[test]
    fn stable_error_codes_do_not_drift() {
        let errors = [
            CryptoError::Ok,
            CryptoError::InvalidArgument,
            CryptoError::InputTooLarge,
            CryptoError::OutputTooSmall,
            CryptoError::MalformedInput,
            CryptoError::InvalidHandle,
            CryptoError::WrongHandleType,
            CryptoError::AuthenticationFailed,
            CryptoError::UnsupportedVersion,
            CryptoError::UnsupportedOperation,
            CryptoError::ResourceExhausted,
            CryptoError::EntropyUnavailable,
            CryptoError::StateViolation,
            CryptoError::InternalFailure,
            CryptoError::PanicContained,
        ];
        for (expected, error) in (0_i32..).zip(errors) {
            assert_eq!(error.code(), expected);
        }
    }
}
