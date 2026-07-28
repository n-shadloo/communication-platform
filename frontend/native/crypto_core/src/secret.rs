use zeroize::Zeroize;

use crate::{
    bounds::{MAX_INPUT_BYTES, MAX_PASSWORD_BYTES},
    error::{CryptoError, CryptoResult},
};

pub struct SecretBytes<const N: usize>(Box<[u8; N]>);

impl<const N: usize> SecretBytes<N> {
    pub fn new(bytes: [u8; N]) -> Self {
        Self(Box::new(bytes))
    }

    pub fn zeroed() -> Self {
        Self::new([0; N])
    }

    pub fn expose(&self) -> &[u8; N] {
        self.0.as_ref()
    }

    pub fn expose_mut(&mut self) -> &mut [u8; N] {
        self.0.as_mut()
    }

    pub fn zeroize_in_place(&mut self) {
        self.0.as_mut().zeroize();
    }
}

impl<const N: usize> Drop for SecretBytes<N> {
    fn drop(&mut self) {
        self.0.as_mut().zeroize();
    }
}

pub struct SecretVec(Vec<u8>);

impl SecretVec {
    pub(crate) fn from_vec(mut bytes: Vec<u8>, max: usize) -> CryptoResult<Self> {
        if bytes.len() > max {
            bytes.zeroize();
            return Err(CryptoError::InputTooLarge);
        }
        Ok(Self(bytes))
    }

    pub(crate) fn from_slice(bytes: &[u8], max: usize) -> CryptoResult<Self> {
        if bytes.len() > max {
            return Err(CryptoError::InputTooLarge);
        }
        let mut owned = Vec::new();
        owned
            .try_reserve_exact(bytes.len())
            .map_err(|_| CryptoError::ResourceExhausted)?;
        owned.extend_from_slice(bytes);
        Ok(Self(owned))
    }

    pub(crate) fn input(bytes: &[u8]) -> CryptoResult<Self> {
        Self::from_slice(bytes, MAX_INPUT_BYTES)
    }

    #[allow(dead_code)] // Password derivation is wired through a future typed handle.
    pub(crate) fn password(bytes: &[u8]) -> CryptoResult<Self> {
        Self::from_slice(bytes, MAX_PASSWORD_BYTES)
    }

    pub fn expose(&self) -> &[u8] {
        &self.0
    }
}

impl Drop for SecretVec {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

#[cfg(test)]
mod tests {
    use super::{SecretBytes, SecretVec};
    use crate::error::CryptoError;

    #[test]
    fn secret_types_accept_bounded_material_without_debug_or_clone_traits() {
        let secret = SecretBytes::<32>::new([0xa5; 32]);
        assert_eq!(secret.expose(), &[0xa5; 32]);
        let vector = SecretVec::input(&[0xa5; 32]).unwrap();
        assert_eq!(vector.expose(), &[0xa5; 32]);
        // Neither secret type implements Debug or Clone.  This is deliberate:
        // any diagnostic that needs to identify a secret must use an opaque
        // handle/type tag rather than a value-bearing Rust formatter.
    }

    #[test]
    fn secret_zeroization_can_be_requested_before_drop() {
        let mut secret = SecretBytes::<16>::new([0xa5; 16]);
        secret.zeroize_in_place();
        assert_eq!(secret.expose(), &[0; 16]);
    }

    #[test]
    fn secret_vector_enforces_input_and_password_bounds() {
        assert!(matches!(
            SecretVec::input(&vec![0; crate::bounds::MAX_INPUT_BYTES + 1]),
            Err(CryptoError::InputTooLarge)
        ));
        assert!(matches!(
            SecretVec::password(&vec![0; crate::bounds::MAX_PASSWORD_BYTES + 1]),
            Err(CryptoError::InputTooLarge)
        ));
    }
}
