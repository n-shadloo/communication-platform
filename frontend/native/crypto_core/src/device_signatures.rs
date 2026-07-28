//! Canonical device-signature encodings defined by the backend client contract.
//!
//! This module is intentionally the only owner of these byte encodings.  Callers
//! provide already-decoded protocol values; no UUID text, base64, or signature
//! framing is accepted here.

#![allow(
    clippy::missing_errors_doc,
    reason = "All public protocol operations return the shared payload-free CryptoError contract."
)]

use crate::{
    bounds::MAX_INPUT_BYTES,
    error::{CryptoError, CryptoResult},
    provider::{
        CryptoProvider, ED25519_PUBLIC_BYTES, ED25519_SIGNATURE_BYTES, X25519_PUBLIC_BYTES,
    },
};
use serde_json::Value;

pub const DEVICE_SIGNING_PUBLIC_KEY_BYTES: usize = ED25519_PUBLIC_BYTES;
pub const IDENTITY_PUBLIC_KEY_BYTES: usize = X25519_PUBLIC_BYTES;
pub const IK_PUBLIC_BYTES: usize = DEVICE_SIGNING_PUBLIC_KEY_BYTES + IDENTITY_PUBLIC_KEY_BYTES;
pub const UUID_BYTES: usize = 16;

const CROSS_SIGNATURE_DOMAIN: &[u8] = b"chat:v1:device-bundle";
const MASTER_SIGNATURE_DOMAIN: &[u8] = b"chat:v1:cross-signing-keys";
const SIGNED_PREKEY_DOMAIN: &[u8] = b"chat:v1:signed-prekey";
const PQ_SIGNED_PREKEY_DOMAIN: &[u8] = b"chat:v1:pq-signed-prekey";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawUuid([u8; UUID_BYTES]);

impl RawUuid {
    #[must_use]
    pub const fn new(bytes: [u8; UUID_BYTES]) -> Self {
        Self(bytes)
    }

    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; UUID_BYTES] {
        &self.0
    }
}

/// The public device identity used by the devices API.
///
/// The fixed representation prevents callers from accidentally changing the
/// signing/X25519 half order while crossing the FFI boundary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct IkPublic([u8; IK_PUBLIC_BYTES]);

impl IkPublic {
    #[must_use]
    pub const fn from_halves(
        device_signing_public: [u8; DEVICE_SIGNING_PUBLIC_KEY_BYTES],
        identity_public: [u8; IDENTITY_PUBLIC_KEY_BYTES],
    ) -> Self {
        let mut bytes = [0; IK_PUBLIC_BYTES];
        let mut index = 0;
        while index < DEVICE_SIGNING_PUBLIC_KEY_BYTES {
            bytes[index] = device_signing_public[index];
            index += 1;
        }
        index = 0;
        while index < IDENTITY_PUBLIC_KEY_BYTES {
            bytes[DEVICE_SIGNING_PUBLIC_KEY_BYTES + index] = identity_public[index];
            index += 1;
        }
        Self(bytes)
    }

    /// Returns malformed input unless `bytes` is exactly 64 bytes.
    ///
    /// # Errors
    ///
    /// Returns [`CryptoError::MalformedInput`] for any other length.
    pub fn try_from_bytes(bytes: &[u8]) -> CryptoResult<Self> {
        let bytes: [u8; IK_PUBLIC_BYTES] =
            bytes.try_into().map_err(|_| CryptoError::MalformedInput)?;
        Ok(Self(bytes))
    }

    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; IK_PUBLIC_BYTES] {
        &self.0
    }

    #[must_use]
    pub fn device_signing_public(&self) -> [u8; DEVICE_SIGNING_PUBLIC_KEY_BYTES] {
        let mut public = [0; DEVICE_SIGNING_PUBLIC_KEY_BYTES];
        public.copy_from_slice(&self.0[..DEVICE_SIGNING_PUBLIC_KEY_BYTES]);
        public
    }

    #[must_use]
    pub fn identity_public(&self) -> [u8; IDENTITY_PUBLIC_KEY_BYTES] {
        let mut public = [0; IDENTITY_PUBLIC_KEY_BYTES];
        public.copy_from_slice(&self.0[DEVICE_SIGNING_PUBLIC_KEY_BYTES..]);
        public
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Ed25519Signature([u8; ED25519_SIGNATURE_BYTES]);

impl Ed25519Signature {
    #[must_use]
    pub const fn new(bytes: [u8; ED25519_SIGNATURE_BYTES]) -> Self {
        Self(bytes)
    }

    /// Returns malformed input unless `bytes` is exactly 64 bytes.
    ///
    /// # Errors
    ///
    /// Returns [`CryptoError::MalformedInput`] for any other length.
    pub fn try_from_bytes(bytes: &[u8]) -> CryptoResult<Self> {
        let bytes = bytes.try_into().map_err(|_| CryptoError::MalformedInput)?;
        Ok(Self(bytes))
    }

    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; ED25519_SIGNATURE_BYTES] {
        &self.0
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DeviceBundle<'a> {
    pub user_id: RawUuid,
    pub device_id: RawUuid,
    pub ik_public: IkPublic,
    pub spk_id: u32,
    pub spk_public: &'a [u8],
    /// Both PQ fields are absent together.  Their two zero-length frames remain
    /// part of the canonical encoding.
    pub pq_signed_prekey: Option<PublicPrekey<'a>>,
    pub registration_id: u32,
    pub bundle_version: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PublicPrekey<'a> {
    pub id: u32,
    pub public: &'a [u8],
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CrossSigningIdentity<'a> {
    pub user_id: RawUuid,
    pub self_signing_public: &'a [u8],
    pub user_signing_public: &'a [u8],
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SignedPrekey<'a> {
    pub user_id: RawUuid,
    pub prekey: PublicPrekey<'a>,
}

pub fn encode_cross_signature(bundle: &DeviceBundle<'_>) -> CryptoResult<Vec<u8>> {
    let mut encoder = Encoder::new(CROSS_SIGNATURE_DOMAIN)?;
    encoder.field(bundle.user_id.as_bytes())?;
    encoder.field(bundle.device_id.as_bytes())?;
    encoder.field(bundle.ik_public.as_bytes())?;
    encoder.field(&bundle.spk_id.to_be_bytes())?;
    encoder.field(bundle.spk_public)?;
    if let Some(prekey) = bundle.pq_signed_prekey {
        encoder.field(&prekey.id.to_be_bytes())?;
        encoder.field(prekey.public)?;
    } else {
        encoder.field(&[])?;
        encoder.field(&[])?;
    }
    encoder.field(&bundle.registration_id.to_be_bytes())?;
    encoder.field(&bundle.bundle_version.to_be_bytes())?;
    Ok(encoder.finish())
}

/// `version` is deliberately absent: it is a server anti-accident check, not
/// a signed identity property.
pub fn encode_master_signature(identity: &CrossSigningIdentity<'_>) -> CryptoResult<Vec<u8>> {
    let mut encoder = Encoder::new(MASTER_SIGNATURE_DOMAIN)?;
    encoder.field(identity.user_id.as_bytes())?;
    encoder.field(identity.self_signing_public)?;
    encoder.field(identity.user_signing_public)?;
    Ok(encoder.finish())
}

pub fn encode_signed_prekey(prekey: &SignedPrekey<'_>) -> CryptoResult<Vec<u8>> {
    encode_prekey(SIGNED_PREKEY_DOMAIN, prekey)
}

pub fn encode_pq_signed_prekey(prekey: &SignedPrekey<'_>) -> CryptoResult<Vec<u8>> {
    encode_prekey(PQ_SIGNED_PREKEY_DOMAIN, prekey)
}

pub fn verify_cross_signature<P: CryptoProvider>(
    provider: &P,
    bundle: &DeviceBundle<'_>,
    self_signing_public: &[u8; ED25519_PUBLIC_BYTES],
    signature: &Ed25519Signature,
) -> CryptoResult<()> {
    let signed_bytes = encode_cross_signature(bundle)?;
    verify(provider, self_signing_public, &signed_bytes, signature)
}

pub fn verify_master_signature<P: CryptoProvider>(
    provider: &P,
    identity: &CrossSigningIdentity<'_>,
    master_public: &[u8; ED25519_PUBLIC_BYTES],
    signature: &Ed25519Signature,
) -> CryptoResult<()> {
    let signed_bytes = encode_master_signature(identity)?;
    verify(provider, master_public, &signed_bytes, signature)
}

pub fn verify_signed_prekey<P: CryptoProvider>(
    provider: &P,
    prekey: &SignedPrekey<'_>,
    ik_public: &IkPublic,
    signature: &Ed25519Signature,
) -> CryptoResult<()> {
    let signed_bytes = encode_signed_prekey(prekey)?;
    verify(
        provider,
        &ik_public.device_signing_public(),
        &signed_bytes,
        signature,
    )
}

pub fn verify_pq_signed_prekey<P: CryptoProvider>(
    provider: &P,
    prekey: &SignedPrekey<'_>,
    ik_public: &IkPublic,
    signature: &Ed25519Signature,
) -> CryptoResult<()> {
    let signed_bytes = encode_pq_signed_prekey(prekey)?;
    verify(
        provider,
        &ik_public.device_signing_public(),
        &signed_bytes,
        signature,
    )
}

fn encode_prekey(domain: &[u8], prekey: &SignedPrekey<'_>) -> CryptoResult<Vec<u8>> {
    let mut encoder = Encoder::new(domain)?;
    encoder.field(prekey.user_id.as_bytes())?;
    encoder.field(&prekey.prekey.id.to_be_bytes())?;
    encoder.field(prekey.prekey.public)?;
    Ok(encoder.finish())
}

fn verify<P: CryptoProvider>(
    provider: &P,
    signer: &[u8; ED25519_PUBLIC_BYTES],
    signed_bytes: &[u8],
    signature: &Ed25519Signature,
) -> CryptoResult<()> {
    provider.ed25519_verify(signer, signed_bytes, signature.as_bytes())
}

struct Encoder {
    bytes: Vec<u8>,
}

impl Encoder {
    fn new(domain: &[u8]) -> CryptoResult<Self> {
        if domain.len() > MAX_INPUT_BYTES {
            return Err(CryptoError::InputTooLarge);
        }
        Ok(Self {
            bytes: domain.to_vec(),
        })
    }

    fn field(&mut self, field: &[u8]) -> CryptoResult<()> {
        let field_length = u32::try_from(field.len()).map_err(|_| CryptoError::InputTooLarge)?;
        let appended = 4usize
            .checked_add(field.len())
            .ok_or(CryptoError::InputTooLarge)?;
        let encoded_length = self
            .bytes
            .len()
            .checked_add(appended)
            .ok_or(CryptoError::InputTooLarge)?;
        if encoded_length > MAX_INPUT_BYTES {
            return Err(CryptoError::InputTooLarge);
        }
        self.bytes.extend_from_slice(&field_length.to_be_bytes());
        self.bytes.extend_from_slice(field);
        Ok(())
    }

    fn finish(self) -> Vec<u8> {
        self.bytes
    }
}

const BACKEND_VECTORS_JSON: &str =
    include_str!(concat!(env!("OUT_DIR"), "/backend_device_vectors.json"));

/// Verifies the authoritative backend fixture file without maintaining a second
/// hand-edited vector table.  The native ABI self-test invokes this so the
/// packaged Android isolate exercises the same fixtures as Rust unit tests.
pub(crate) fn verify_backend_vectors<P: CryptoProvider>(provider: &P) -> CryptoResult<()> {
    let root: Value =
        serde_json::from_str(BACKEND_VECTORS_JSON).map_err(|_| CryptoError::InternalFailure)?;
    let vectors = root
        .get("vectors")
        .and_then(Value::as_array)
        .ok_or(CryptoError::InternalFailure)?;
    for value in vectors {
        let fixture = Fixture::from_json(value)?;
        let encoded = fixture.encode()?;
        if encoded != fixture.signed_bytes {
            return Err(CryptoError::InternalFailure);
        }
        fixture.verify(provider)?;
    }
    Ok(())
}

#[derive(Clone, Debug)]
struct Fixture {
    name: String,
    user_id: RawUuid,
    device_id: Option<RawUuid>,
    ik_public: Option<IkPublic>,
    spk_id: Option<u32>,
    spk_public: Option<Vec<u8>>,
    pq_spk_id: Option<u32>,
    pq_spk_public: Option<Vec<u8>>,
    registration_id: Option<u32>,
    bundle_version: Option<u32>,
    self_signing_public: Option<Vec<u8>>,
    user_signing_public: Option<Vec<u8>>,
    signer_public: [u8; ED25519_PUBLIC_BYTES],
    signature: Ed25519Signature,
    signed_bytes: Vec<u8>,
}

impl Fixture {
    fn from_json(value: &Value) -> CryptoResult<Self> {
        let fields = value
            .get("fields")
            .and_then(Value::as_object)
            .ok_or(CryptoError::InternalFailure)?;
        let name = field_text(value, "name")?.to_owned();
        let user_id = parse_uuid(field_text_in(fields, "user_id")?)?;
        let device_id = optional_text_in(fields, "device_id")
            .map(parse_uuid)
            .transpose()?;
        let ik_public = optional_text_in(fields, "ik_pub_hex")
            .map(hex_decode)
            .transpose()?
            .map(|bytes| IkPublic::try_from_bytes(&bytes))
            .transpose()?;
        let signer_public =
            fixed::<ED25519_PUBLIC_BYTES>(&hex_decode(field_text(value, "verify_with_pub_hex")?)?)?;
        let signature =
            Ed25519Signature::try_from_bytes(&hex_decode(field_text(value, "signature_hex")?)?)?;
        Ok(Self {
            name,
            user_id,
            device_id,
            ik_public,
            spk_id: optional_u32_in(fields, "spk_id")?,
            spk_public: optional_text_in(fields, "spk_pub_hex")
                .map(hex_decode)
                .transpose()?,
            pq_spk_id: optional_u32_in(fields, "pq_spk_id")?,
            pq_spk_public: optional_text_in(fields, "pq_spk_pub_hex")
                .map(hex_decode)
                .transpose()?,
            registration_id: optional_u32_in(fields, "registration_id")?,
            bundle_version: optional_u32_in(fields, "bundle_version")?,
            self_signing_public: optional_text_in(fields, "self_signing_pub_hex")
                .map(hex_decode)
                .transpose()?,
            user_signing_public: optional_text_in(fields, "user_signing_pub_hex")
                .map(hex_decode)
                .transpose()?,
            signer_public,
            signature,
            signed_bytes: hex_decode(field_text(value, "signed_bytes_hex")?)?,
        })
    }

    fn encode(&self) -> CryptoResult<Vec<u8>> {
        match self.name.as_str() {
            "device_bundle_hybrid" | "device_bundle_classical_only" => {
                let bundle = self.bundle()?;
                encode_cross_signature(&bundle)
            }
            "master_sig" => {
                let identity = self.identity()?;
                encode_master_signature(&identity)
            }
            "spk_sig" => encode_signed_prekey(&self.prekey()?),
            "pq_spk_sig" => encode_pq_signed_prekey(&self.prekey()?),
            _ => Err(CryptoError::InternalFailure),
        }
    }

    fn verify<P: CryptoProvider>(&self, provider: &P) -> CryptoResult<()> {
        match self.name.as_str() {
            "device_bundle_hybrid" | "device_bundle_classical_only" => verify_cross_signature(
                provider,
                &self.bundle()?,
                &self.signer_public,
                &self.signature,
            ),
            "master_sig" => verify_master_signature(
                provider,
                &self.identity()?,
                &self.signer_public,
                &self.signature,
            ),
            "spk_sig" => verify_signed_prekey(
                provider,
                &self.prekey()?,
                &self.signer_ik_public(),
                &self.signature,
            ),
            "pq_spk_sig" => verify_pq_signed_prekey(
                provider,
                &self.prekey()?,
                &self.signer_ik_public(),
                &self.signature,
            ),
            _ => Err(CryptoError::InternalFailure),
        }
    }

    fn bundle(&self) -> CryptoResult<DeviceBundle<'_>> {
        let pq_signed_prekey = match (self.pq_spk_id, self.pq_spk_public.as_deref()) {
            (None, None) => None,
            (Some(id), Some(public)) => Some(PublicPrekey { id, public }),
            _ => return Err(CryptoError::InternalFailure),
        };
        Ok(DeviceBundle {
            user_id: self.user_id,
            device_id: self.device_id.ok_or(CryptoError::InternalFailure)?,
            ik_public: self.ik_public.ok_or(CryptoError::InternalFailure)?,
            spk_id: self.spk_id.ok_or(CryptoError::InternalFailure)?,
            spk_public: self
                .spk_public
                .as_deref()
                .ok_or(CryptoError::InternalFailure)?,
            pq_signed_prekey,
            registration_id: self.registration_id.ok_or(CryptoError::InternalFailure)?,
            bundle_version: self.bundle_version.ok_or(CryptoError::InternalFailure)?,
        })
    }

    fn identity(&self) -> CryptoResult<CrossSigningIdentity<'_>> {
        Ok(CrossSigningIdentity {
            user_id: self.user_id,
            self_signing_public: self
                .self_signing_public
                .as_deref()
                .ok_or(CryptoError::InternalFailure)?,
            user_signing_public: self
                .user_signing_public
                .as_deref()
                .ok_or(CryptoError::InternalFailure)?,
        })
    }

    fn prekey(&self) -> CryptoResult<SignedPrekey<'_>> {
        let (id, public) = if self.name == "pq_spk_sig" {
            (self.pq_spk_id, self.pq_spk_public.as_deref())
        } else {
            (self.spk_id, self.spk_public.as_deref())
        };
        Ok(SignedPrekey {
            user_id: self.user_id,
            prekey: PublicPrekey {
                id: id.ok_or(CryptoError::InternalFailure)?,
                public: public.ok_or(CryptoError::InternalFailure)?,
            },
        })
    }

    fn signer_ik_public(&self) -> IkPublic {
        self.ik_public.unwrap_or_else(|| {
            IkPublic::from_halves(self.signer_public, [0; IDENTITY_PUBLIC_KEY_BYTES])
        })
    }
}

fn field_text<'a>(value: &'a Value, key: &str) -> CryptoResult<&'a str> {
    value
        .get(key)
        .and_then(Value::as_str)
        .ok_or(CryptoError::InternalFailure)
}

fn field_text_in<'a>(
    fields: &'a serde_json::Map<String, Value>,
    key: &str,
) -> CryptoResult<&'a str> {
    fields
        .get(key)
        .and_then(Value::as_str)
        .ok_or(CryptoError::InternalFailure)
}

fn optional_text_in<'a>(fields: &'a serde_json::Map<String, Value>, key: &str) -> Option<&'a str> {
    fields.get(key).and_then(Value::as_str)
}

fn optional_u32_in(
    fields: &serde_json::Map<String, Value>,
    key: &str,
) -> CryptoResult<Option<u32>> {
    match fields.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_u64()
            .and_then(|value| u32::try_from(value).ok())
            .map(Some)
            .ok_or(CryptoError::InternalFailure),
    }
}

fn parse_uuid(value: &str) -> CryptoResult<RawUuid> {
    let compact: String = value
        .chars()
        .filter(|character| *character != '-')
        .collect();
    Ok(RawUuid::new(fixed::<UUID_BYTES>(&hex_decode(&compact)?)?))
}

fn fixed<const LENGTH: usize>(bytes: &[u8]) -> CryptoResult<[u8; LENGTH]> {
    bytes.try_into().map_err(|_| CryptoError::InternalFailure)
}

fn hex_decode(value: &str) -> CryptoResult<Vec<u8>> {
    if !value.len().is_multiple_of(2) {
        return Err(CryptoError::InternalFailure);
    }
    let mut decoded = Vec::with_capacity(value.len() / 2);
    for pair in value.as_bytes().chunks_exact(2) {
        let high = hex_nibble(pair[0])?;
        let low = hex_nibble(pair[1])?;
        decoded.push((high << 4) | low);
    }
    Ok(decoded)
}

fn hex_nibble(value: u8) -> CryptoResult<u8> {
    match value {
        b'0'..=b'9' => Ok(value - b'0'),
        b'a'..=b'f' => Ok(value - b'a' + 10),
        b'A'..=b'F' => Ok(value - b'A' + 10),
        _ => Err(CryptoError::InternalFailure),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        CROSS_SIGNATURE_DOMAIN, Encoder, Fixture, IkPublic, RawUuid, SignedPrekey,
        encode_pq_signed_prekey, encode_signed_prekey, verify_backend_vectors,
        verify_cross_signature, verify_master_signature, verify_pq_signed_prekey,
        verify_signed_prekey,
    };
    use crate::{
        error::CryptoError,
        provider::{CryptoProvider, RustCryptoProvider},
    };

    fn fixtures() -> Vec<Fixture> {
        let root: serde_json::Value = serde_json::from_str(super::BACKEND_VECTORS_JSON).unwrap();
        root["vectors"]
            .as_array()
            .unwrap()
            .iter()
            .map(Fixture::from_json)
            .collect::<Result<_, _>>()
            .unwrap()
    }

    #[test]
    fn backend_vectors_reproduce_and_verify() {
        verify_backend_vectors(&RustCryptoProvider::default()).unwrap();
    }

    #[test]
    #[allow(clippy::too_many_lines)] // Each required adversarial mutation is named in one audit test.
    fn fixture_mutations_are_rejected() {
        let provider = RustCryptoProvider::default();
        let fixtures = fixtures();
        let hybrid = fixtures
            .iter()
            .find(|fixture| fixture.name == "device_bundle_hybrid")
            .unwrap();
        let classical = fixtures
            .iter()
            .find(|fixture| fixture.name == "device_bundle_classical_only")
            .unwrap();
        let master = fixtures
            .iter()
            .find(|fixture| fixture.name == "master_sig")
            .unwrap();
        let spk = fixtures
            .iter()
            .find(|fixture| fixture.name == "spk_sig")
            .unwrap();
        let pq = fixtures
            .iter()
            .find(|fixture| fixture.name == "pq_spk_sig")
            .unwrap();

        // Wrong domain: distinct prekey contexts never authenticate each other.
        assert_eq!(
            verify_pq_signed_prekey(
                &provider,
                &pq.prekey().unwrap(),
                &pq.signer_ik_public(),
                &spk.signature,
            ),
            Err(CryptoError::AuthenticationFailed)
        );
        assert_eq!(
            provider.ed25519_verify(
                &spk.signer_public,
                &encode_pq_signed_prekey(&spk.prekey().unwrap()).unwrap(),
                spk.signature.as_bytes(),
            ),
            Err(CryptoError::AuthenticationFailed)
        );

        // Field order and each frame length are covered by the signature.
        let bundle = hybrid.bundle().unwrap();
        let mut wrong_order = CROSS_SIGNATURE_DOMAIN.to_vec();
        for field in [
            bundle.device_id.as_bytes().as_slice(),
            bundle.user_id.as_bytes().as_slice(),
            bundle.ik_public.as_bytes().as_slice(),
        ] {
            let field_length = u32::try_from(field.len()).unwrap();
            wrong_order.extend_from_slice(&field_length.to_be_bytes());
            wrong_order.extend_from_slice(field);
        }
        assert_eq!(
            provider.ed25519_verify(
                &hybrid.signer_public,
                &wrong_order,
                hybrid.signature.as_bytes()
            ),
            Err(CryptoError::AuthenticationFailed)
        );
        let mut wrong_length = hybrid.signed_bytes.clone();
        let domain_length = CROSS_SIGNATURE_DOMAIN.len();
        wrong_length[domain_length + 3] ^= 1;
        assert_eq!(
            provider.ed25519_verify(
                &hybrid.signer_public,
                &wrong_length,
                hybrid.signature.as_bytes()
            ),
            Err(CryptoError::AuthenticationFailed)
        );

        // UUID text is not signed; the raw 16 bytes are, including their byte order.
        let mut uuid_bytes = *bundle.user_id.as_bytes();
        uuid_bytes.reverse();
        let mut altered_bundle = bundle;
        altered_bundle.user_id = RawUuid::new(uuid_bytes);
        assert_eq!(
            verify_cross_signature(
                &provider,
                &altered_bundle,
                &hybrid.signer_public,
                &hybrid.signature
            ),
            Err(CryptoError::AuthenticationFailed)
        );

        // Optional PQ fields are two explicit zero-length frames, never omitted.
        let classical_bundle = classical.bundle().unwrap();
        let mut omitted_optional = Encoder::new(CROSS_SIGNATURE_DOMAIN).unwrap();
        omitted_optional
            .field(classical_bundle.user_id.as_bytes())
            .unwrap();
        omitted_optional
            .field(classical_bundle.device_id.as_bytes())
            .unwrap();
        omitted_optional
            .field(classical_bundle.ik_public.as_bytes())
            .unwrap();
        omitted_optional
            .field(&classical_bundle.spk_id.to_be_bytes())
            .unwrap();
        omitted_optional.field(classical_bundle.spk_public).unwrap();
        omitted_optional
            .field(&classical_bundle.registration_id.to_be_bytes())
            .unwrap();
        omitted_optional
            .field(&classical_bundle.bundle_version.to_be_bytes())
            .unwrap();
        assert_eq!(
            provider.ed25519_verify(
                &classical.signer_public,
                &omitted_optional.finish(),
                classical.signature.as_bytes(),
            ),
            Err(CryptoError::AuthenticationFailed)
        );

        // ik_pub order is fixed: the Ed25519 half is the prekey signer.
        let original_ik = *hybrid.ik_public.as_ref().unwrap().as_bytes();
        let swapped = IkPublic::from_halves(
            hybrid.ik_public.as_ref().unwrap().identity_public(),
            hybrid.ik_public.as_ref().unwrap().device_signing_public(),
        );
        assert_ne!(swapped.as_bytes(), &original_ik);
        let mut swapped_bundle = bundle;
        swapped_bundle.ik_public = swapped;
        assert_eq!(
            verify_cross_signature(
                &provider,
                &swapped_bundle,
                &hybrid.signer_public,
                &hybrid.signature
            ),
            Err(CryptoError::AuthenticationFailed)
        );

        // Server-provided key bytes and signer bytes are both authenticated inputs.
        let mut changed_prekey = spk.prekey().unwrap();
        let mut changed_prekey_bytes = changed_prekey.prekey.public.to_vec();
        changed_prekey_bytes[0] ^= 1;
        changed_prekey.prekey.public = &changed_prekey_bytes;
        assert_eq!(
            verify_signed_prekey(
                &provider,
                &changed_prekey,
                &spk.signer_ik_public(),
                &spk.signature
            ),
            Err(CryptoError::AuthenticationFailed)
        );
        let mut wrong_signer = master.signer_public;
        wrong_signer[0] ^= 1;
        assert_eq!(
            verify_master_signature(
                &provider,
                &master.identity().unwrap(),
                &wrong_signer,
                &master.signature
            ),
            Err(CryptoError::AuthenticationFailed)
        );

        // Malformed signature length is rejected before verification.
        assert_eq!(
            super::Ed25519Signature::try_from_bytes(&hybrid.signature.as_bytes()[..63]),
            Err(CryptoError::MalformedInput)
        );

        // The ordinary prekey vector itself remains valid under its own domain.
        verify_signed_prekey(
            &provider,
            &spk.prekey().unwrap(),
            &spk.signer_ik_public(),
            &spk.signature,
        )
        .unwrap();
        let _ = encode_signed_prekey(&SignedPrekey {
            user_id: spk.user_id,
            prekey: spk.prekey().unwrap().prekey,
        })
        .unwrap();
    }
}
