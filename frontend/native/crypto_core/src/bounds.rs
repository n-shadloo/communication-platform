use crate::error::{CryptoError, CryptoResult};

pub const MAX_INPUT_BYTES: usize = 1_048_576;
#[allow(dead_code)] // Enforced by the staged Argon2id provider method.
pub const MAX_PASSWORD_BYTES: usize = 4096;
pub const MAX_CBOR_DEPTH: u32 = 32;
pub const MAX_CBOR_ITEMS: u32 = 4096;
pub const MAX_CBOR_BYTES: usize = MAX_INPUT_BYTES;

pub struct BoundedBytes<'a> {
    bytes: &'a [u8],
}

impl<'a> BoundedBytes<'a> {
    pub fn new(bytes: &'a [u8], max: usize) -> CryptoResult<Self> {
        if bytes.len() > max {
            return Err(CryptoError::InputTooLarge);
        }
        Ok(Self { bytes })
    }

    pub fn as_slice(&self) -> &'a [u8] {
        self.bytes
    }
}
