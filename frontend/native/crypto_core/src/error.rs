#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[allow(dead_code)] // Every numeric value is reserved by the stable v1 C ABI.
pub enum CryptoError {
    Ok = 0,
    InvalidArgument = 1,
    InputTooLarge = 2,
    OutputTooSmall = 3,
    MalformedInput = 4,
    InvalidHandle = 5,
    WrongHandleType = 6,
    AuthenticationFailed = 7,
    UnsupportedVersion = 8,
    UnsupportedOperation = 9,
    ResourceExhausted = 10,
    EntropyUnavailable = 11,
    StateViolation = 12,
    InternalFailure = 13,
    PanicContained = 14,
}

impl CryptoError {
    pub const fn code(self) -> i32 {
        self as i32
    }
}

pub type CryptoResult<T> = Result<T, CryptoError>;

impl From<getrandom::Error> for CryptoError {
    fn from(_: getrandom::Error) -> Self {
        Self::EntropyUnavailable
    }
}
