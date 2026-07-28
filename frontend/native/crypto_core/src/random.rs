use crate::error::CryptoResult;

pub trait RandomProvider: Send + Sync {
    fn fill(&self, output: &mut [u8]) -> CryptoResult<()>;
}

#[derive(Default)]
pub struct OsRandomProvider;

impl RandomProvider for OsRandomProvider {
    fn fill(&self, output: &mut [u8]) -> CryptoResult<()> {
        getrandom::fill(output)?;
        Ok(())
    }
}

#[cfg(test)]
pub struct FixedRandomProvider {
    bytes: std::sync::Mutex<Vec<u8>>,
}

#[cfg(test)]
impl FixedRandomProvider {
    pub fn new(bytes: Vec<u8>) -> Self {
        Self {
            bytes: std::sync::Mutex::new(bytes),
        }
    }
}

#[cfg(test)]
impl RandomProvider for FixedRandomProvider {
    fn fill(&self, output: &mut [u8]) -> CryptoResult<()> {
        let mut bytes = self
            .bytes
            .lock()
            .map_err(|_| crate::error::CryptoError::InternalFailure)?;
        if bytes.len() < output.len() {
            return Err(crate::error::CryptoError::EntropyUnavailable);
        }
        output.copy_from_slice(&bytes[..output.len()]);
        bytes.drain(..output.len());
        Ok(())
    }
}
