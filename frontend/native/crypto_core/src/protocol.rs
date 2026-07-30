//! Strict byte framing and keyed derivation helpers for native protocols.

use hkdf::Hkdf;
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;
use zeroize::Zeroizing;

use crate::{
    bounds::MAX_INPUT_BYTES,
    error::{CryptoError, CryptoResult},
};

pub(crate) struct Reader<'a> {
    input: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    pub(crate) const fn new(input: &'a [u8]) -> Self {
        Self { input, position: 0 }
    }

    pub(crate) fn take(&mut self, length: usize) -> CryptoResult<&'a [u8]> {
        let end = self
            .position
            .checked_add(length)
            .ok_or(CryptoError::MalformedInput)?;
        let value = self
            .input
            .get(self.position..end)
            .ok_or(CryptoError::MalformedInput)?;
        self.position = end;
        Ok(value)
    }

    pub(crate) fn array<const LENGTH: usize>(&mut self) -> CryptoResult<[u8; LENGTH]> {
        self.take(LENGTH)?
            .try_into()
            .map_err(|_| CryptoError::MalformedInput)
    }

    pub(crate) fn u8(&mut self) -> CryptoResult<u8> {
        Ok(self.take(1)?[0])
    }

    pub(crate) fn boolean(&mut self) -> CryptoResult<bool> {
        match self.u8()? {
            0 => Ok(false),
            1 => Ok(true),
            _ => Err(CryptoError::MalformedInput),
        }
    }

    pub(crate) fn u16(&mut self) -> CryptoResult<u16> {
        Ok(u16::from_be_bytes(self.array()?))
    }

    pub(crate) fn u32(&mut self) -> CryptoResult<u32> {
        Ok(u32::from_be_bytes(self.array()?))
    }

    pub(crate) fn u64(&mut self) -> CryptoResult<u64> {
        Ok(u64::from_be_bytes(self.array()?))
    }

    pub(crate) fn framed(&mut self) -> CryptoResult<&'a [u8]> {
        let length = usize::try_from(self.u32()?).map_err(|_| CryptoError::MalformedInput)?;
        if length > MAX_INPUT_BYTES {
            return Err(CryptoError::InputTooLarge);
        }
        self.take(length)
    }

    pub(crate) const fn is_finished(&self) -> bool {
        self.position == self.input.len()
    }

    pub(crate) const fn position(&self) -> usize {
        self.position
    }
}

pub(crate) fn push_u16(output: &mut Vec<u8>, value: u16) {
    output.extend_from_slice(&value.to_be_bytes());
}

pub(crate) fn push_u32(output: &mut Vec<u8>, value: u32) {
    output.extend_from_slice(&value.to_be_bytes());
}

pub(crate) fn push_u64(output: &mut Vec<u8>, value: u64) {
    output.extend_from_slice(&value.to_be_bytes());
}

pub(crate) fn push_frame(output: &mut Vec<u8>, value: &[u8]) -> CryptoResult<()> {
    push_u32(
        output,
        u32::try_from(value.len()).map_err(|_| CryptoError::InputTooLarge)?,
    );
    output.extend_from_slice(value);
    Ok(())
}

pub(crate) fn reserve(output: &mut Vec<u8>, additional: usize) -> CryptoResult<()> {
    let final_len = output
        .len()
        .checked_add(additional)
        .ok_or(CryptoError::InputTooLarge)?;
    if final_len > MAX_INPUT_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    output
        .try_reserve_exact(additional)
        .map_err(|_| CryptoError::ResourceExhausted)
}

pub(crate) fn hkdf_sha256(
    salt: &[u8],
    input_key_material: &[u8],
    info: &[u8],
    output_len: usize,
) -> CryptoResult<Zeroizing<Vec<u8>>> {
    if salt.len() > MAX_INPUT_BYTES
        || input_key_material.len() > MAX_INPUT_BYTES
        || info.len() > MAX_INPUT_BYTES
        || output_len > MAX_INPUT_BYTES
    {
        return Err(CryptoError::InputTooLarge);
    }
    let mut output = Zeroizing::new(Vec::new());
    output
        .try_reserve_exact(output_len)
        .map_err(|_| CryptoError::ResourceExhausted)?;
    output.resize(output_len, 0);
    let (_, hkdf) = Hkdf::<Sha256>::extract(Some(salt), input_key_material);
    hkdf.expand(info, output.as_mut_slice())
        .map_err(|_| CryptoError::OutputTooSmall)?;
    Ok(output)
}

pub(crate) fn hmac_sha256(key: &[u8], input: &[u8]) -> CryptoResult<[u8; 32]> {
    if key.len() > MAX_INPUT_BYTES || input.len() > MAX_INPUT_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    let mut mac = Hmac::<Sha256>::new_from_slice(key).map_err(|_| CryptoError::InvalidArgument)?;
    mac.update(input);
    let bytes = mac.finalize().into_bytes();
    let mut output = [0u8; 32];
    output.copy_from_slice(&bytes);
    Ok(output)
}
