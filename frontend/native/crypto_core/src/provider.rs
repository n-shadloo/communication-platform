use std::{
    mem::{self, MaybeUninit},
    ptr,
    sync::OnceLock,
};

use argon2::{Algorithm, Argon2, Block, Params, Version};
use chacha20poly1305::{
    Key, XChaCha20Poly1305, XNonce,
    aead::{AeadInOut, KeyInit},
};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hkdf::Hkdf;
use sha2::{Digest, Sha256, Sha384};
use subtle::ConstantTimeEq;
use x25519_dalek::{PublicKey as X25519PublicKey, StaticSecret};
use zeroize::{Zeroize, Zeroizing};

use crate::{
    bounds::{BoundedBytes, MAX_INPUT_BYTES, MAX_PASSWORD_BYTES},
    error::{CryptoError, CryptoResult},
    random::{OsRandomProvider, RandomProvider},
    secret::{SecretBytes, SecretVec},
};

pub const ED25519_SECRET_BYTES: usize = 32;
pub const ED25519_PUBLIC_BYTES: usize = 32;
pub const ED25519_SIGNATURE_BYTES: usize = 64;
pub const X25519_SECRET_BYTES: usize = 32;
pub const X25519_PUBLIC_BYTES: usize = 32;
pub const X25519_SHARED_BYTES: usize = 32;
pub const MLKEM768_PUBLIC_BYTES: usize = 1184;
pub const MLKEM768_SECRET_BYTES: usize = 2400;
pub const MLKEM768_CIPHERTEXT_BYTES: usize = 1088;
pub const MLKEM_SHARED_BYTES: usize = 32;
#[allow(dead_code)] // Exercised by unit vectors; exported through future typed handles.
pub const ARGON2_SALT_BYTES: usize = 16;
#[allow(dead_code)] // Exercised by unit vectors; exported through future typed handles.
pub const ARGON2_OUTPUT_BYTES: usize = 32;
pub const XCHACHA_KEY_BYTES: usize = 32;
pub const XCHACHA_NONCE_BYTES: usize = 24;
pub const XCHACHA_ABYTES: usize = 16;
pub const SECRETSTREAM_KEY_BYTES: usize = 32;
pub const SECRETSTREAM_HEADER_BYTES: usize = 24;
pub const SECRETSTREAM_ABYTES: usize = 17;

unsafe extern "C" {
    fn CP_CRYPTO_MLKEM_keypair_derand(
        public_key: *mut u8,
        secret_key: *mut u8,
        coins: *const u8,
    ) -> i32;
    fn CP_CRYPTO_MLKEM_enc_derand(
        ciphertext: *mut u8,
        shared_secret: *mut u8,
        public_key: *const u8,
        coins: *const u8,
    ) -> i32;
    fn CP_CRYPTO_MLKEM_dec(
        shared_secret: *mut u8,
        ciphertext: *const u8,
        secret_key: *const u8,
    ) -> i32;
}

static SODIUM_INIT: OnceLock<CryptoResult<()>> = OnceLock::new();

struct ZeroizingBuffer<T: AsMut<[u8]>>(T);

impl<T: AsMut<[u8]>> Drop for ZeroizingBuffer<T> {
    fn drop(&mut self) {
        self.0.as_mut().zeroize();
    }
}

fn ensure_sodium() -> CryptoResult<()> {
    *SODIUM_INIT.get_or_init(|| {
        // SAFETY: libsodium's initialization function has no pointer arguments
        // and is explicitly safe to call more than once.
        let result = unsafe { libsodium_sys::sodium_init() };
        if result < 0 {
            Err(CryptoError::InternalFailure)
        } else {
            Ok(())
        }
    })
}

#[allow(dead_code)] // The narrow v1 ABI exposes only capability/self-test calls.
pub trait CryptoProvider: Send + Sync {
    fn random_bytes(&self, output: &mut [u8]) -> CryptoResult<()>;
    fn ed25519_sign(
        &self,
        secret: &SecretBytes<ED25519_SECRET_BYTES>,
        message: &[u8],
    ) -> CryptoResult<[u8; ED25519_SIGNATURE_BYTES]>;
    fn ed25519_verify(
        &self,
        public_key: &[u8; ED25519_PUBLIC_BYTES],
        message: &[u8],
        signature: &[u8; ED25519_SIGNATURE_BYTES],
    ) -> CryptoResult<()>;
    fn x25519_public(
        &self,
        secret: &SecretBytes<X25519_SECRET_BYTES>,
    ) -> CryptoResult<[u8; X25519_PUBLIC_BYTES]>;
    fn x25519_shared(
        &self,
        secret: &SecretBytes<X25519_SECRET_BYTES>,
        peer_public: &[u8; X25519_PUBLIC_BYTES],
    ) -> CryptoResult<SecretBytes<X25519_SHARED_BYTES>>;
    fn mlkem768_keypair(
        &self,
    ) -> CryptoResult<(
        [u8; MLKEM768_PUBLIC_BYTES],
        SecretBytes<MLKEM768_SECRET_BYTES>,
    )>;
    fn mlkem768_encapsulate(
        &self,
        public_key: &[u8; MLKEM768_PUBLIC_BYTES],
    ) -> CryptoResult<(
        [u8; MLKEM768_CIPHERTEXT_BYTES],
        SecretBytes<MLKEM_SHARED_BYTES>,
    )>;
    fn mlkem768_decapsulate(
        &self,
        secret_key: &SecretBytes<MLKEM768_SECRET_BYTES>,
        ciphertext: &[u8; MLKEM768_CIPHERTEXT_BYTES],
    ) -> CryptoResult<SecretBytes<MLKEM_SHARED_BYTES>>;
    fn argon2id(
        &self,
        password: &SecretVec,
        salt: &[u8; ARGON2_SALT_BYTES],
    ) -> CryptoResult<SecretBytes<ARGON2_OUTPUT_BYTES>>;
    fn xchacha20poly1305_encrypt(
        &self,
        key: &SecretBytes<XCHACHA_KEY_BYTES>,
        nonce: &[u8; XCHACHA_NONCE_BYTES],
        plaintext: &SecretVec,
        associated_data: &[u8],
    ) -> CryptoResult<Vec<u8>>;
    fn xchacha20poly1305_decrypt(
        &self,
        key: &SecretBytes<XCHACHA_KEY_BYTES>,
        nonce: &[u8; XCHACHA_NONCE_BYTES],
        ciphertext: &[u8],
        associated_data: &[u8],
    ) -> CryptoResult<SecretVec>;
    fn sha256(&self, input: &[u8]) -> CryptoResult<[u8; 32]>;
    fn sha384(&self, input: &[u8]) -> CryptoResult<[u8; 48]>;
    fn hkdf_sha256(
        &self,
        salt: &[u8],
        input_key_material: &SecretVec,
        info: &[u8],
    ) -> CryptoResult<SecretVec>;
    fn hkdf_sha384(
        &self,
        salt: &[u8],
        input_key_material: &SecretVec,
        info: &[u8],
    ) -> CryptoResult<SecretVec>;
}

pub struct RustCryptoProvider<R = OsRandomProvider> {
    random: R,
}

impl Default for RustCryptoProvider<OsRandomProvider> {
    fn default() -> Self {
        Self::new(OsRandomProvider)
    }
}

impl<R: RandomProvider> RustCryptoProvider<R> {
    pub const fn new(random: R) -> Self {
        Self { random }
    }

    fn bounded(input: &[u8]) -> CryptoResult<BoundedBytes<'_>> {
        BoundedBytes::new(input, MAX_INPUT_BYTES)
    }
}

impl<R: RandomProvider> CryptoProvider for RustCryptoProvider<R> {
    fn random_bytes(&self, output: &mut [u8]) -> CryptoResult<()> {
        if output.len() > MAX_INPUT_BYTES {
            return Err(CryptoError::InputTooLarge);
        }
        self.random.fill(output)
    }

    fn ed25519_sign(
        &self,
        secret: &SecretBytes<ED25519_SECRET_BYTES>,
        message: &[u8],
    ) -> CryptoResult<[u8; ED25519_SIGNATURE_BYTES]> {
        let message = Self::bounded(message)?.as_slice();
        let signing_key = SigningKey::from_bytes(secret.expose());
        Ok(signing_key.sign(message).to_bytes())
    }

    fn ed25519_verify(
        &self,
        public_key: &[u8; ED25519_PUBLIC_BYTES],
        message: &[u8],
        signature: &[u8; ED25519_SIGNATURE_BYTES],
    ) -> CryptoResult<()> {
        let message = Self::bounded(message)?.as_slice();
        let verifying_key =
            VerifyingKey::from_bytes(public_key).map_err(|_| CryptoError::MalformedInput)?;
        let signature = Signature::from_bytes(signature);
        verifying_key
            .verify_strict(message, &signature)
            .map_err(|_| CryptoError::AuthenticationFailed)
    }

    fn x25519_public(
        &self,
        secret: &SecretBytes<X25519_SECRET_BYTES>,
    ) -> CryptoResult<[u8; X25519_PUBLIC_BYTES]> {
        let static_secret = StaticSecret::from(*secret.expose());
        Ok(X25519PublicKey::from(&static_secret).to_bytes())
    }

    fn x25519_shared(
        &self,
        secret: &SecretBytes<X25519_SECRET_BYTES>,
        peer_public: &[u8; X25519_PUBLIC_BYTES],
    ) -> CryptoResult<SecretBytes<X25519_SHARED_BYTES>> {
        let static_secret = StaticSecret::from(*secret.expose());
        let peer_public = X25519PublicKey::from(*peer_public);
        let shared = static_secret.diffie_hellman(&peer_public);
        if bool::from(shared.as_bytes().ct_eq(&[0; X25519_SHARED_BYTES])) {
            return Err(CryptoError::AuthenticationFailed);
        }
        Ok(SecretBytes::new(shared.to_bytes()))
    }

    fn mlkem768_keypair(
        &self,
    ) -> CryptoResult<(
        [u8; MLKEM768_PUBLIC_BYTES],
        SecretBytes<MLKEM768_SECRET_BYTES>,
    )> {
        let mut public_key = [0u8; MLKEM768_PUBLIC_BYTES];
        let mut secret_key = SecretBytes::zeroed();
        let mut coins = SecretBytes::<64>::zeroed();
        self.random.fill(coins.expose_mut())?;
        // SAFETY: all buffers are fixed-size arrays matching mlkem-native's
        // ML-KEM-768 API, and the deterministic function does not retain them.
        let result = unsafe {
            CP_CRYPTO_MLKEM_keypair_derand(
                public_key.as_mut_ptr(),
                secret_key.expose_mut().as_mut_ptr(),
                coins.expose().as_ptr(),
            )
        };
        coins.zeroize_in_place();
        if result != 0 {
            return Err(CryptoError::InternalFailure);
        }
        Ok((public_key, secret_key))
    }

    fn mlkem768_encapsulate(
        &self,
        public_key: &[u8; MLKEM768_PUBLIC_BYTES],
    ) -> CryptoResult<(
        [u8; MLKEM768_CIPHERTEXT_BYTES],
        SecretBytes<MLKEM_SHARED_BYTES>,
    )> {
        let mut ciphertext = [0u8; MLKEM768_CIPHERTEXT_BYTES];
        let mut shared_secret = SecretBytes::zeroed();
        let mut coins = SecretBytes::<32>::zeroed();
        self.random.fill(coins.expose_mut())?;
        // SAFETY: all buffers are fixed-size arrays matching the upstream API.
        let result = unsafe {
            CP_CRYPTO_MLKEM_enc_derand(
                ciphertext.as_mut_ptr(),
                shared_secret.expose_mut().as_mut_ptr(),
                public_key.as_ptr(),
                coins.expose().as_ptr(),
            )
        };
        coins.zeroize_in_place();
        if result != 0 {
            return Err(CryptoError::MalformedInput);
        }
        Ok((ciphertext, shared_secret))
    }

    fn mlkem768_decapsulate(
        &self,
        secret_key: &SecretBytes<MLKEM768_SECRET_BYTES>,
        ciphertext: &[u8; MLKEM768_CIPHERTEXT_BYTES],
    ) -> CryptoResult<SecretBytes<MLKEM_SHARED_BYTES>> {
        let mut shared_secret = SecretBytes::zeroed();
        // SAFETY: all buffers are fixed-size arrays matching the upstream API.
        let result = unsafe {
            CP_CRYPTO_MLKEM_dec(
                shared_secret.expose_mut().as_mut_ptr(),
                ciphertext.as_ptr(),
                secret_key.expose().as_ptr(),
            )
        };
        if result != 0 {
            return Err(CryptoError::MalformedInput);
        }
        Ok(shared_secret)
    }

    fn argon2id(
        &self,
        password: &SecretVec,
        salt: &[u8; ARGON2_SALT_BYTES],
    ) -> CryptoResult<SecretBytes<ARGON2_OUTPUT_BYTES>> {
        BoundedBytes::new(password.expose(), MAX_PASSWORD_BYTES)?;
        let params = Params::new(65_536, 3, 4, Some(ARGON2_OUTPUT_BYTES))
            .map_err(|_| CryptoError::InternalFailure)?;
        let block_count = params.block_count();
        let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
        let mut output = SecretBytes::zeroed();
        let mut memory_blocks = Vec::new();
        memory_blocks
            .try_reserve_exact(block_count)
            .map_err(|_| CryptoError::ResourceExhausted)?;
        memory_blocks.resize_with(block_count, Block::default);
        let mut memory = Zeroizing::new(memory_blocks);
        argon
            .hash_password_into_with_memory(
                password.expose(),
                salt,
                output.expose_mut(),
                &mut *memory,
            )
            .map_err(|_| CryptoError::InvalidArgument)?;
        Ok(output)
    }

    fn xchacha20poly1305_encrypt(
        &self,
        key: &SecretBytes<XCHACHA_KEY_BYTES>,
        nonce: &[u8; XCHACHA_NONCE_BYTES],
        plaintext: &SecretVec,
        associated_data: &[u8],
    ) -> CryptoResult<Vec<u8>> {
        let plaintext = Self::bounded(plaintext.expose())?.as_slice();
        let associated_data = Self::bounded(associated_data)?.as_slice();
        if plaintext
            .len()
            .checked_add(XCHACHA_ABYTES)
            .ok_or(CryptoError::InputTooLarge)?
            > MAX_INPUT_BYTES
        {
            return Err(CryptoError::InputTooLarge);
        }
        let output_len = plaintext
            .len()
            .checked_add(XCHACHA_ABYTES)
            .ok_or(CryptoError::InputTooLarge)?;
        let mut output = Vec::new();
        output
            .try_reserve_exact(output_len)
            .map_err(|_| CryptoError::ResourceExhausted)?;
        output.extend_from_slice(plaintext);

        let cipher_key = ZeroizingBuffer(
            Key::try_from(key.expose().as_slice()).map_err(|_| CryptoError::InvalidArgument)?,
        );
        let cipher_nonce =
            XNonce::try_from(nonce.as_slice()).map_err(|_| CryptoError::InvalidArgument)?;
        let cipher = XChaCha20Poly1305::new(&cipher_key.0);
        cipher
            .encrypt_in_place(&cipher_nonce, associated_data, &mut output)
            .map_err(|_| CryptoError::InternalFailure)?;
        Ok(output)
    }

    fn xchacha20poly1305_decrypt(
        &self,
        key: &SecretBytes<XCHACHA_KEY_BYTES>,
        nonce: &[u8; XCHACHA_NONCE_BYTES],
        ciphertext: &[u8],
        associated_data: &[u8],
    ) -> CryptoResult<SecretVec> {
        let ciphertext = Self::bounded(ciphertext)?.as_slice();
        let associated_data = Self::bounded(associated_data)?.as_slice();
        if ciphertext.len() < XCHACHA_ABYTES {
            return Err(CryptoError::MalformedInput);
        }
        let mut plaintext = Vec::new();
        plaintext
            .try_reserve_exact(ciphertext.len())
            .map_err(|_| CryptoError::ResourceExhausted)?;
        plaintext.extend_from_slice(ciphertext);

        let cipher_key = ZeroizingBuffer(
            Key::try_from(key.expose().as_slice()).map_err(|_| CryptoError::InvalidArgument)?,
        );
        let cipher_nonce =
            XNonce::try_from(nonce.as_slice()).map_err(|_| CryptoError::InvalidArgument)?;
        let cipher = XChaCha20Poly1305::new(&cipher_key.0);
        if cipher
            .decrypt_in_place(&cipher_nonce, associated_data, &mut plaintext)
            .is_err()
        {
            plaintext.zeroize();
            return Err(CryptoError::AuthenticationFailed);
        }
        SecretVec::from_vec(plaintext, MAX_INPUT_BYTES)
    }

    fn sha256(&self, input: &[u8]) -> CryptoResult<[u8; 32]> {
        let input = Self::bounded(input)?.as_slice();
        Ok(Sha256::digest(input).into())
    }

    fn sha384(&self, input: &[u8]) -> CryptoResult<[u8; 48]> {
        let input = Self::bounded(input)?.as_slice();
        Ok(Sha384::digest(input).into())
    }

    fn hkdf_sha256(
        &self,
        salt: &[u8],
        input_key_material: &SecretVec,
        info: &[u8],
    ) -> CryptoResult<SecretVec> {
        let salt = Self::bounded(salt)?.as_slice();
        let info = Self::bounded(info)?.as_slice();
        let mut output = Vec::new();
        output
            .try_reserve_exact(32)
            .map_err(|_| CryptoError::ResourceExhausted)?;
        output.resize(32, 0);
        BoundedBytes::new(input_key_material.expose(), MAX_INPUT_BYTES)?;
        let (prk, hkdf) = Hkdf::<Sha256>::extract(Some(salt), input_key_material.expose());
        let _prk = ZeroizingBuffer(prk);
        hkdf.expand(info, &mut output)
            .map_err(|_| CryptoError::OutputTooSmall)?;
        SecretVec::from_vec(output, MAX_INPUT_BYTES)
    }

    fn hkdf_sha384(
        &self,
        salt: &[u8],
        input_key_material: &SecretVec,
        info: &[u8],
    ) -> CryptoResult<SecretVec> {
        let salt = Self::bounded(salt)?.as_slice();
        let info = Self::bounded(info)?.as_slice();
        let mut output = Vec::new();
        output
            .try_reserve_exact(48)
            .map_err(|_| CryptoError::ResourceExhausted)?;
        output.resize(48, 0);
        BoundedBytes::new(input_key_material.expose(), MAX_INPUT_BYTES)?;
        let (prk, hkdf) = Hkdf::<Sha384>::extract(Some(salt), input_key_material.expose());
        let _prk = ZeroizingBuffer(prk);
        hkdf.expand(info, &mut output)
            .map_err(|_| CryptoError::OutputTooSmall)?;
        SecretVec::from_vec(output, MAX_INPUT_BYTES)
    }
}

pub struct SecretStreamPush {
    state: Box<libsodium_sys::crypto_secretstream_xchacha20poly1305_state>,
}

pub struct SecretStreamPull {
    state: Box<libsodium_sys::crypto_secretstream_xchacha20poly1305_state>,
}

impl Drop for SecretStreamPush {
    fn drop(&mut self) {
        // SAFETY: state points to an initialized libsodium state owned by this
        // object; sodium_memzero accepts any valid byte range.
        unsafe {
            libsodium_sys::sodium_memzero(
                ptr::from_mut(self.state.as_mut()).cast(),
                mem::size_of_val(self.state.as_ref()),
            );
        }
    }
}

impl Drop for SecretStreamPull {
    fn drop(&mut self) {
        // SAFETY: see SecretStreamPush::drop.
        unsafe {
            libsodium_sys::sodium_memzero(
                ptr::from_mut(self.state.as_mut()).cast(),
                mem::size_of_val(self.state.as_ref()),
            );
        }
    }
}

pub fn secretstream_push_init(
    key: &SecretBytes<SECRETSTREAM_KEY_BYTES>,
) -> CryptoResult<(SecretStreamPush, [u8; SECRETSTREAM_HEADER_BYTES])> {
    ensure_sodium()?;
    let mut state = Box::new(unsafe {
        // SAFETY: the C state is a plain byte-compatible struct and is fully
        // initialized by init_push before use.
        MaybeUninit::<libsodium_sys::crypto_secretstream_xchacha20poly1305_state>::zeroed()
            .assume_init()
    });
    let mut header = [0u8; SECRETSTREAM_HEADER_BYTES];
    // SAFETY: state, header, and key all point to correctly sized writable/read
    // buffers owned for the duration of this call.
    let result = unsafe {
        libsodium_sys::crypto_secretstream_xchacha20poly1305_init_push(
            state.as_mut(),
            header.as_mut_ptr(),
            key.expose().as_ptr(),
        )
    };
    if result != 0 {
        return Err(CryptoError::InternalFailure);
    }
    Ok((SecretStreamPush { state }, header))
}

pub fn secretstream_push(
    stream: &mut SecretStreamPush,
    plaintext: &SecretVec,
    associated_data: &[u8],
    final_message: bool,
) -> CryptoResult<Vec<u8>> {
    let plaintext = BoundedBytes::new(plaintext.expose(), MAX_INPUT_BYTES)?.as_slice();
    let associated_data = BoundedBytes::new(associated_data, MAX_INPUT_BYTES)?.as_slice();
    let ciphertext_len = plaintext
        .len()
        .checked_add(SECRETSTREAM_ABYTES)
        .ok_or(CryptoError::InputTooLarge)?;
    if ciphertext_len > MAX_INPUT_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    let mut ciphertext = Vec::new();
    ciphertext
        .try_reserve_exact(ciphertext_len)
        .map_err(|_| CryptoError::ResourceExhausted)?;
    ciphertext.resize(ciphertext_len, 0);
    let mut ciphertext_len = 0u64;
    let tag = if final_message {
        // SAFETY: constant-returning libsodium function.
        unsafe { libsodium_sys::crypto_secretstream_xchacha20poly1305_tag_final() }
    } else {
        0
    };
    // SAFETY: buffers and lengths are bounded and valid; empty associated data
    // is represented by a null pointer as required by libsodium.
    let result = unsafe {
        libsodium_sys::crypto_secretstream_xchacha20poly1305_push(
            stream.state.as_mut(),
            ciphertext.as_mut_ptr(),
            &raw mut ciphertext_len,
            plaintext.as_ptr(),
            plaintext.len() as u64,
            if associated_data.is_empty() {
                ptr::null()
            } else {
                associated_data.as_ptr()
            },
            associated_data.len() as u64,
            tag,
        )
    };
    if result != 0 {
        return Err(CryptoError::StateViolation);
    }
    ciphertext.truncate(usize::try_from(ciphertext_len).map_err(|_| CryptoError::InternalFailure)?);
    Ok(ciphertext)
}

pub fn secretstream_pull_init(
    key: &SecretBytes<SECRETSTREAM_KEY_BYTES>,
    header: &[u8; SECRETSTREAM_HEADER_BYTES],
) -> CryptoResult<SecretStreamPull> {
    ensure_sodium()?;
    let mut state = Box::new(unsafe {
        // SAFETY: see secretstream_push_init.
        MaybeUninit::<libsodium_sys::crypto_secretstream_xchacha20poly1305_state>::zeroed()
            .assume_init()
    });
    // SAFETY: all pointers refer to fixed-size initialized buffers.
    let result = unsafe {
        libsodium_sys::crypto_secretstream_xchacha20poly1305_init_pull(
            state.as_mut(),
            header.as_ptr(),
            key.expose().as_ptr(),
        )
    };
    if result != 0 {
        return Err(CryptoError::AuthenticationFailed);
    }
    Ok(SecretStreamPull { state })
}

pub fn secretstream_pull(
    stream: &mut SecretStreamPull,
    ciphertext: &[u8],
    associated_data: &[u8],
) -> CryptoResult<(SecretVec, bool)> {
    if ciphertext.len() < SECRETSTREAM_ABYTES {
        return Err(CryptoError::MalformedInput);
    }
    let ciphertext = BoundedBytes::new(ciphertext, MAX_INPUT_BYTES)?.as_slice();
    let associated_data = BoundedBytes::new(associated_data, MAX_INPUT_BYTES)?.as_slice();
    let plaintext_len = ciphertext
        .len()
        .checked_sub(SECRETSTREAM_ABYTES)
        .ok_or(CryptoError::MalformedInput)?;
    let mut plaintext = Vec::new();
    plaintext
        .try_reserve_exact(plaintext_len)
        .map_err(|_| CryptoError::ResourceExhausted)?;
    plaintext.resize(plaintext_len, 0);
    let mut plaintext_len = 0u64;
    let mut tag = 0u8;
    // SAFETY: buffers and lengths are bounded and valid.
    let result = unsafe {
        libsodium_sys::crypto_secretstream_xchacha20poly1305_pull(
            stream.state.as_mut(),
            plaintext.as_mut_ptr(),
            &raw mut plaintext_len,
            &raw mut tag,
            ciphertext.as_ptr(),
            ciphertext.len() as u64,
            if associated_data.is_empty() {
                ptr::null()
            } else {
                associated_data.as_ptr()
            },
            associated_data.len() as u64,
        )
    };
    if result != 0 {
        plaintext.zeroize();
        return Err(CryptoError::AuthenticationFailed);
    }
    plaintext.truncate(usize::try_from(plaintext_len).map_err(|_| CryptoError::InternalFailure)?);
    let final_tag = unsafe {
        // SAFETY: constant-returning libsodium function.
        libsodium_sys::crypto_secretstream_xchacha20poly1305_tag_final()
    };
    Ok((
        SecretVec::from_vec(plaintext, MAX_INPUT_BYTES)?,
        tag == final_tag,
    ))
}

#[cfg(test)]
mod tests {
    use super::{
        ARGON2_SALT_BYTES, CryptoProvider, RustCryptoProvider, X25519_SHARED_BYTES, XCHACHA_ABYTES,
        secretstream_pull, secretstream_pull_init, secretstream_push, secretstream_push_init,
    };
    use crate::{
        bounds::{MAX_INPUT_BYTES, MAX_PASSWORD_BYTES},
        error::CryptoError,
        random::FixedRandomProvider,
        secret::{SecretBytes, SecretVec},
    };
    use hex_literal::hex;
    use sha2::Digest;

    fn provider() -> RustCryptoProvider<FixedRandomProvider> {
        RustCryptoProvider::new(FixedRandomProvider::new(vec![7; 4096]))
    }

    #[test]
    fn ed25519_rfc8032_vector_and_strict_rejection() {
        let provider = provider();
        let secret = SecretBytes::new(hex!(
            "9d61b19deffd5a60ba844af492ec2cc4"
            "4449c5697b326919703bac031cae7f60"
        ));
        let public = hex!("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
        let expected = hex!(
            "e5564300c360ac729086e2cc806e828a"
            "84877f1eb8e5d974d873e06522490155"
            "5fb8821590a33bacc61e39701cf9b46b"
            "d25bf5f0595bbe24655141438e7a100b"
        );
        let signature = provider.ed25519_sign(&secret, b"").unwrap();
        assert_eq!(signature, expected);
        provider.ed25519_verify(&public, b"", &signature).unwrap();
        let mut altered = signature;
        altered[0] ^= 1;
        assert_eq!(
            provider.ed25519_verify(&public, b"", &altered).unwrap_err(),
            CryptoError::AuthenticationFailed
        );
    }

    #[test]
    fn x25519_rfc7748_vector_and_all_zero_rejection() {
        let provider = provider();
        let alice_secret = SecretBytes::new(hex!(
            "77076d0a7318a57d3c16c17251b26645"
            "df4c2f87ebc0992ab177fba51db92c2a"
        ));
        let bob_public = hex!(
            "de9edb7d7b7dc1b4d35b61c2ece43537"
            "3f8343c85b78674dadfc7e146f882b4f"
        );
        assert_eq!(
            provider.x25519_public(&alice_secret).unwrap(),
            hex!("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
        );
        assert_eq!(
            provider
                .x25519_shared(&alice_secret, &bob_public)
                .unwrap()
                .expose(),
            &hex!("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
        );
        assert_eq!(
            match provider.x25519_shared(&alice_secret, &[0; X25519_SHARED_BYTES]) {
                Err(error) => error,
                Ok(_) => panic!("all-zero X25519 shared secret was accepted"),
            },
            CryptoError::AuthenticationFailed
        );
    }

    #[test]
    fn sha_and_hkdf_rfc5869_vectors() {
        let provider = provider();
        assert_eq!(
            provider.sha256(b"").unwrap(),
            hex!("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        );
        assert_eq!(
            provider.sha384(b"").unwrap(),
            hex!(
                "38b060a751ac96384cd9327eb1b1e36a"
                "21fdb71114be07434c0cc7bf63f6e1da"
                "274edebfe76f65fbd51ad2f14898b95b"
            )
        );
        let ikm = SecretVec::input(&[0x0b; 22]).unwrap();
        let output = provider
            .hkdf_sha256(
                &hex!("000102030405060708090a0b0c"),
                &ikm,
                &hex!("f0f1f2f3f4f5f6f7f8f9"),
            )
            .unwrap();
        assert_eq!(
            output.expose(),
            &hex!("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf")
        );

        // Independent SHA-384 fixture generated from the RFC 5869 case-1
        // inputs. RFC 5869 publishes the SHA-256 case; this expected value
        // is pinned separately so the provider cannot validate itself only
        // by round-tripping.
        let output = provider
            .hkdf_sha384(
                &hex!("000102030405060708090a0b0c"),
                &ikm,
                &hex!("f0f1f2f3f4f5f6f7f8f9"),
            )
            .unwrap();
        assert_eq!(
            output.expose(),
            &hex!(
                "9b5097a86038b805309076a44b3a9f38"
                "063e25b516dcbf369f394cfab43685f7"
                "48b6457763e4f0204fc5d95d1da3e625"
            )
        );
        assert!(matches!(
            provider.hkdf_sha384(&vec![0; MAX_INPUT_BYTES + 1], &ikm, b""),
            Err(CryptoError::InputTooLarge)
        ));
    }

    #[test]
    fn xchacha20poly1305_draft_vector_round_trip_and_tamper_rejection() {
        let provider = provider();

        // draft-irtf-cfrg-xchacha-03, Appendix A.1.
        let vector_key = SecretBytes::new(hex!(
            "808182838485868788898a8b8c8d8e8f"
            "909192939495969798999a9b9c9d9e9f"
        ));
        let vector_nonce = hex!(
            "404142434445464748494a4b4c4d4e4f"
            "5051525354555657"
        );
        let vector_aad = hex!("50515253c0c1c2c3c4c5c6c7");
        let vector_plaintext = SecretVec::input(
            b"Ladies and Gentlemen of the class of '99: \
              If I could offer you only one tip for the future, sunscreen would be it.",
        )
        .unwrap();
        let expected = hex!(
            "bd6d179d3e83d43b9576579493c0e939"
            "572a1700252bfaccbed2902c21396cbb"
            "731c7f1b0b4aa6440bf3a82f4eda7e39"
            "ae64c6708c54c216cb96b72e1213b452"
            "2f8c9ba40db5d945b11b69b982c1bb9e"
            "3f3fac2bc369488f76b2383565d3fff9"
            "21f9664c97637da9768812f615c68b13"
            "b52ec0875924c1c7987947deafd8780a"
            "cf49"
        );
        assert_eq!(
            provider
                .xchacha20poly1305_encrypt(
                    &vector_key,
                    &vector_nonce,
                    &vector_plaintext,
                    &vector_aad,
                )
                .unwrap(),
            expected
        );
        assert_eq!(
            provider
                .xchacha20poly1305_decrypt(&vector_key, &vector_nonce, &expected, &vector_aad,)
                .unwrap()
                .expose(),
            vector_plaintext.expose()
        );

        let key = SecretBytes::new([11; 32]);
        let nonce = [13; 24];
        let plaintext = SecretVec::input(b"plaintext").unwrap();
        let ciphertext = provider
            .xchacha20poly1305_encrypt(&key, &nonce, &plaintext, b"aad")
            .unwrap();
        let plaintext = provider
            .xchacha20poly1305_decrypt(&key, &nonce, &ciphertext, b"aad")
            .unwrap();
        assert_eq!(plaintext.expose(), b"plaintext");
        assert_eq!(
            match provider.xchacha20poly1305_decrypt(&key, &nonce, &ciphertext, b"bad") {
                Err(error) => error,
                Ok(_) => panic!("ciphertext authenticated with the wrong associated data"),
            },
            CryptoError::AuthenticationFailed
        );
        assert!(matches!(
            provider.xchacha20poly1305_decrypt(&key, &nonce, &[0; XCHACHA_ABYTES - 1], b""),
            Err(CryptoError::MalformedInput)
        ));

        let boundary_plaintext =
            SecretVec::input(&vec![0x5a; MAX_INPUT_BYTES - XCHACHA_ABYTES]).unwrap();
        let boundary_ciphertext = provider
            .xchacha20poly1305_encrypt(&key, &nonce, &boundary_plaintext, b"")
            .unwrap();
        assert_eq!(boundary_ciphertext.len(), MAX_INPUT_BYTES);
        assert_eq!(
            provider
                .xchacha20poly1305_decrypt(&key, &nonce, &boundary_ciphertext, b"")
                .unwrap()
                .expose(),
            boundary_plaintext.expose()
        );
        let oversized_plaintext =
            SecretVec::input(&vec![0x5a; MAX_INPUT_BYTES - XCHACHA_ABYTES + 1]).unwrap();
        assert_eq!(
            provider.xchacha20poly1305_encrypt(&key, &nonce, &oversized_plaintext, b""),
            Err(CryptoError::InputTooLarge)
        );
    }

    #[test]
    fn argon2id_profile_is_deterministic_and_bounded() {
        let provider = provider();
        let password = SecretVec::password(b"correct horse battery staple").unwrap();
        let salt = [0x42; ARGON2_SALT_BYTES];
        let output = provider.argon2id(&password, &salt).unwrap();
        // Exact RFC 9106 profile required by the protocol: Argon2id v1.3,
        // m=65536 KiB, t=3, p=4, salt=16 bytes, output=32 bytes.
        assert_eq!(
            output.expose(),
            &hex!("dde64ab2660a0dedd449fa0414587bd0407e68ebe4a3f1595f2c167f1f7ff3cd")
        );
        assert!(matches!(
            SecretVec::password(&vec![0; MAX_PASSWORD_BYTES + 1]),
            Err(CryptoError::InputTooLarge)
        ));
    }

    #[test]
    fn provider_enforces_input_bounds_and_rng_failures() {
        let provider = provider();
        let at_limit = vec![0u8; MAX_INPUT_BYTES];
        assert_eq!(provider.sha256(&at_limit).unwrap().len(), 32);
        assert_eq!(
            provider.sha256(&vec![0; MAX_INPUT_BYTES + 1]),
            Err(CryptoError::InputTooLarge)
        );
        let oversized_plaintext = vec![0; MAX_INPUT_BYTES + 1];
        assert_eq!(
            match SecretVec::input(&oversized_plaintext) {
                Err(error) => error,
                Ok(_) => panic!("oversized plaintext was accepted"),
            },
            CryptoError::InputTooLarge
        );

        let no_entropy = RustCryptoProvider::new(FixedRandomProvider::new(Vec::new()));
        let mut random_output = [0u8; 1];
        assert_eq!(
            no_entropy.random_bytes(&mut random_output).unwrap_err(),
            CryptoError::EntropyUnavailable
        );
        assert_eq!(
            match no_entropy.mlkem768_keypair() {
                Err(error) => error,
                Ok(_) => panic!("ML-KEM key generation unexpectedly succeeded without entropy"),
            },
            CryptoError::EntropyUnavailable
        );
    }

    #[test]
    fn mlkem768_nist_acvp_keygen_vector() {
        // NIST ACVP-Server v1.1.0.41, ML-KEM-keyGen-FIPS203,
        // ML-KEM-768 tgId 2 / tcId 26. The published ek/dk are large, so
        // their independently computed SHA-256 fingerprints are pinned.
        let provider = RustCryptoProvider::new(FixedRandomProvider::new(
            [
                hex!("a2b4bca315a6ea4600b4a316e09a2578aa1e8bce919c8df3a96c71c843f5b38b").as_slice(),
                hex!("d6bf055cb7b375e3271ed131f1ba31f83fef533a239878a71074578b891265d1").as_slice(),
            ]
            .concat(),
        ));
        let (public_key, secret_key) = provider.mlkem768_keypair().unwrap();
        assert_eq!(
            sha2::Sha256::digest(public_key).as_slice(),
            &hex!("ed2430c8bd81af5cb02a8968db7319bf6e62d0a9a0c9492015610c209b5b3b15")
        );
        assert_eq!(
            sha2::Sha256::digest(secret_key.expose()).as_slice(),
            &hex!("bd8662d4ae7210025a68e5634f0b53ba2f9e0331e8078ca075f4b51a06e8403f")
        );
    }

    #[test]
    fn mlkem768_deterministic_fixture_round_trips() {
        let provider = RustCryptoProvider::new(FixedRandomProvider::new(
            [[0x11; 64].as_slice(), [0x22; 32].as_slice()].concat(),
        ));
        let (public_key, secret_key) = provider.mlkem768_keypair().unwrap();
        let (ciphertext, sender_shared) = provider.mlkem768_encapsulate(&public_key).unwrap();
        let receiver_shared = provider
            .mlkem768_decapsulate(&secret_key, &ciphertext)
            .unwrap();
        assert_eq!(sender_shared.expose(), receiver_shared.expose());
        assert_eq!(
            sha2::Sha256::digest(public_key).as_slice(),
            &hex!("27ee97675ef5c87eab6f25d7348c278ff46ed744eb5ffd7076edc87a00bffa3b")
        );
        assert_eq!(
            sha2::Sha256::digest(ciphertext).as_slice(),
            &hex!("14b7eda9214fab4cab79c273965221e916ea5e2f8a0b1f6534a288c2f14212d2")
        );
        assert_eq!(
            sender_shared.expose(),
            &hex!("7705e8b459a747e14e5c2e545caa2fe5950bcdc9ca4d78853ba51160297a4f30")
        );
        let mut modified_ciphertext = ciphertext;
        modified_ciphertext[0] ^= 1;
        let rejected_shared = provider
            .mlkem768_decapsulate(&secret_key, &modified_ciphertext)
            .unwrap();
        assert_ne!(rejected_shared.expose(), sender_shared.expose());
    }

    #[test]
    fn secretstream_round_trip_and_tamper_rejection() {
        let key = SecretBytes::new([0x42; 32]);
        let plaintext = SecretVec::input(b"stream data").unwrap();
        let (mut push, header) = secretstream_push_init(&key).unwrap();
        let ciphertext = secretstream_push(&mut push, &plaintext, b"header", true).unwrap();
        let mut pull = secretstream_pull_init(&key, &header).unwrap();
        let (plaintext, is_final) = secretstream_pull(&mut pull, &ciphertext, b"header").unwrap();
        assert_eq!(plaintext.expose(), b"stream data");
        assert!(is_final);
        let mut altered = ciphertext;
        altered[0] ^= 1;
        let mut tamper_pull = secretstream_pull_init(&key, &header).unwrap();
        assert_eq!(
            match secretstream_pull(&mut tamper_pull, &altered, b"header") {
                Err(error) => error,
                Ok(_) => panic!("tampered secretstream message was accepted"),
            },
            CryptoError::AuthenticationFailed
        );

        let boundary_plaintext =
            SecretVec::input(&vec![0x5a; MAX_INPUT_BYTES - super::SECRETSTREAM_ABYTES]).unwrap();
        let (mut boundary_push, boundary_header) = secretstream_push_init(&key).unwrap();
        let boundary_ciphertext =
            secretstream_push(&mut boundary_push, &boundary_plaintext, b"", true).unwrap();
        assert_eq!(boundary_ciphertext.len(), MAX_INPUT_BYTES);
        let mut boundary_pull = secretstream_pull_init(&key, &boundary_header).unwrap();
        let (round_trip, is_final) =
            secretstream_pull(&mut boundary_pull, &boundary_ciphertext, b"").unwrap();
        assert_eq!(round_trip.expose(), boundary_plaintext.expose());
        assert!(is_final);

        let oversized_plaintext =
            SecretVec::input(&vec![
                0x5a;
                MAX_INPUT_BYTES - super::SECRETSTREAM_ABYTES + 1
            ])
            .unwrap();
        let (mut oversized_push, _) = secretstream_push_init(&key).unwrap();
        assert_eq!(
            secretstream_push(&mut oversized_push, &oversized_plaintext, b"", false),
            Err(CryptoError::InputTooLarge)
        );
        assert_eq!(
            match secretstream_pull(
                &mut boundary_pull,
                &[0; super::SECRETSTREAM_ABYTES - 1],
                b"",
            ) {
                Err(error) => error,
                Ok(_) => panic!("undersized secretstream ciphertext was accepted"),
            },
            CryptoError::MalformedInput
        );
    }

    #[test]
    fn secretstream_libsodium_1022_pull_fixture_and_tamper_rejection() {
        // The secretstream header is intentionally random, so the primitive
        // has no deterministic encryption KAT. This fixed decrypt fixture was
        // captured from libsodium 1.0.22's public API with a test-only key and
        // pins the cross-language pull representation instead.
        let key = SecretBytes::new([0x42; 32]);
        let header = hex!(
            "9a34b491d9699acf3cdfa03b6e2fe804"
            "94c52ffdb8ada0c4"
        );
        let ciphertext = hex!(
            "f53cf87b9cceea8a44d55ee796340082"
            "3a0075e070e468a39827927c9ac09d65"
            "b3c875f94bb388659063c104ddb6"
        );
        let mut pull = secretstream_pull_init(&key, &header).unwrap();
        let (plaintext, is_final) =
            secretstream_pull(&mut pull, &ciphertext, b"piece-07 aad").unwrap();
        assert_eq!(plaintext.expose(), b"piece-07 secretstream fixture");
        assert!(is_final);

        let mut altered = ciphertext;
        altered[0] ^= 1;
        let mut tamper_pull = secretstream_pull_init(&key, &header).unwrap();
        assert_eq!(
            match secretstream_pull(&mut tamper_pull, &altered, b"piece-07 aad") {
                Err(error) => error,
                Ok(_) => panic!("tampered fixed secretstream fixture was accepted"),
            },
            CryptoError::AuthenticationFailed
        );
    }
}
