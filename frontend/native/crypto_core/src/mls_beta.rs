//! Closed-beta-only MLS ciphersuite assembly.
//!
//! The MLS identifier is from the RFC 9420 Private Use range. It must never be
//! accepted by the production composition root.
//!
//! This suite is modelled on `draft-ietf-mls-pq-ciphersuites-06` TBD2; it does not
//! implement it. The signature, AEAD, KDF, and hash choices match TBD2 exactly, but the
//! hybrid KEM does not, so beta groups are not wire-compatible with TBD2 and never have
//! been. `BetaMlsCryptoProvider::cipher_suite_provider` summarizes the divergences;
//! `docs/mls-profile.md` rows D1-D10 are the complete binding set with per-row evidence,
//! and ADR-040 (2026-08-17) resolves that this KEM is not changed. Replacing any mapping
//! is an explicit protocol/ADR change and requires reinitializing all beta groups.

use std::{
    collections::BTreeMap,
    error::Error,
    fmt,
    sync::{Arc, Mutex, MutexGuard},
};

use minicbor::{Decoder, Encoder};
use mls_rs::{
    CipherSuite, Client, CryptoProvider, ExtensionList, GroupStateStorage, IdentityProvider,
    KeyPackageStorage, MlsMessage,
    client_builder::MlsConfig,
    extension::{ExtensionType, recommended::LastResortKeyPackageExt},
    group::{Group, ProposalSender, ReceivedMessage},
    identity::{CredentialType, SigningIdentity, basic::BasicCredential},
    mls_rules::{DefaultMlsRules, EncryptionOptions},
};
use mls_rs_codec::{MlsDecode, MlsEncode};
use mls_rs_core::{
    crypto::SignatureSecretKey,
    error::IntoAnyError,
    group::{EpochRecord, GroupState as StoredMlsGroupState},
    identity::MemberValidationContext,
    key_package::KeyPackageData,
    time::MlsTime,
};
use mls_rs_crypto_awslc::{
    AwsLcCipherSuite, AwsLcCipherSuiteBuilder, AwsLcHash, AwsLcHmac, MlKem, Sha3,
};
use mls_rs_crypto_traits::{AeadId, Curve, KdfId};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

use crate::{
    device_signatures::{DeviceBundle, PublicPrekey, RawUuid, encode_cross_signature},
    enrollment::inspect_verified_claimed_device_bundle,
    error::CryptoError,
    prekey_state::decode_device_state,
    protocol::{Reader, push_frame, push_u16, push_u32, push_u64, reserve},
    provider::{CryptoProvider as FoundationCryptoProvider, RustCryptoProvider},
    secret::{SecretBytes, SecretVec},
};

/// `0xFE4C`, allocated by mls-rs from the MLS Private Use range.
pub const BETA_CIPHERSUITE: CipherSuite = CipherSuite::ML_KEM_768_X25519;
pub const BETA_CIPHERSUITE_ID: u16 = 0xFE4C;
pub const BETA_STATE_FORMAT_VERSION: u16 = 1;
const CREDENTIAL_PROTOCOL_VERSION: u8 = 1;
const BETA_STATE_MAGIC: &[u8; 8] = b"CPMLSV01";
const MAX_RETAINED_EPOCHS: usize = 8;
const KEY_PACKAGE_WRAPPER_MAGIC: &[u8; 8] = b"CPMKPV01";
const KEY_PACKAGE_WRAPPER_VERSION: u16 = 2;
const KEY_PACKAGE_STORE_MAGIC: &[u8; 8] = b"CPMLSK01";
const KEY_PACKAGE_STORE_VERSION: u16 = 2;
const MAX_STORED_KEY_PACKAGES: usize = 101;
const GROUP_STATE_ENVELOPE_MAGIC: &[u8; 8] = b"CPMLSG01";
const GROUP_STATE_ENVELOPE_VERSION: u16 = 1;
const STATE_BINDING_MAGIC: &[u8; 8] = b"CPMLSB01";
const MAX_GROUP_AUTHENTICATION_PROOFS: usize = 50;
pub const KEY_PACKAGE_BUCKETS: [usize; 2] = [4096, 16_384];
pub(crate) const MLS_MAX_IO_BYTES: usize = crate::bounds::MAX_INPUT_BYTES;
const OPERATION_REQUEST_MAGIC: &[u8; 8] = b"CPMLR001";
const OPERATION_RESPONSE_MAGIC: &[u8; 8] = b"CPMLO001";
const OPERATION_VERSION: u16 = 1;
const OP_GENERATE_CONSUMABLE_KEY_PACKAGES: u32 = 1;
const OP_GENERATE_LAST_RESORT_KEY_PACKAGE: u32 = 2;
const OP_CREATE_GROUP: u32 = 3;
const OP_JOIN_GROUP: u32 = 4;
const OP_ADD_MEMBERS: u32 = 5;
const OP_REMOVE_MEMBERS: u32 = 6;
const OP_SEND_APPLICATION: u32 = 7;
const OP_PROCESS_MESSAGE: u32 = 8;
const OP_PROPOSE_UPDATE: u32 = 9;
const OP_COMMIT_PENDING_PROPOSALS: u32 = 10;
const OP_SIGN_GROUP_CONTROL: u32 = 11;
const OP_VERIFY_GROUP_CONTROL: u32 = 12;
const OP_HASH_MLS_OBJECT: u32 = 13;
const GROUP_CONTROL_PAYLOAD_MAGIC: &[u8; 8] = b"CPGCV001";
const GROUP_CONTROL_SIGNATURE_DOMAIN: &[u8] = b"chat:v1:group-control";
const GROUP_CONTROL_STATE_DOMAIN: &[u8] = b"chat:v1:group-control-state";
const SEALED_STATE_MAGIC: &[u8; 8] = b"CPMLSE01";
const SEALED_STATE_VERSION: u16 = 2;
const SEALED_STATE_KEY_DOMAIN: &[u8] = b"chat:v1:beta-pq-mls-state-wrap";
const XCHACHA_NONCE_BYTES: usize = 24;
const XCHACHA_TAG_BYTES: usize = 16;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SealedStateKind {
    KeyPackages = 1,
    Group = 2,
}

/// Provider exposing only the beta suite, never a classical fallback.
#[derive(Clone, Debug, Default)]
pub struct BetaMlsCryptoProvider;

impl CryptoProvider for BetaMlsCryptoProvider {
    type CipherSuiteProvider = AwsLcCipherSuite;

    fn supported_cipher_suites(&self) -> Vec<CipherSuite> {
        vec![BETA_CIPHERSUITE]
    }

    fn cipher_suite_provider(
        &self,
        cipher_suite: CipherSuite,
    ) -> Option<Self::CipherSuiteProvider> {
        if cipher_suite != BETA_CIPHERSUITE {
            return None;
        }

        // These four match draft-ietf-mls-pq-ciphersuites-06 TBD2 exactly: Ed25519,
        // AES-256-GCM (0x0002), HKDF-SHA384 (0x0002), and SHA-384.
        let sha384_suite = CipherSuite::P384_AES256;
        AwsLcCipherSuiteBuilder::new()
            .signing(Curve::Ed25519)
            .aead(AeadId::Aes256Gcm)
            .kdf(KdfId::HkdfSha384)
            .hmac(AwsLcHmac::new(sha384_suite)?)
            .hash(AwsLcHash::new(sha384_suite)?)
            // The KEM does not. TBD2 names HPKE KEM 0x647a, which draft-ietf-hpke-pq-05
            // defines as MLKEM768-X25519 and draft-irtf-cfrg-concrete-hybrid-kems
            // states is identical to X-Wing. This call builds something else. Verified
            // on 2026-08-17 against the vendored mls-rs-crypto-hpke 0.21.0 sources and
            // the X-Wing draft text, which agrees at -06 and -10 on every point below:
            //
            // - the combiner hashes label || ss_mlkem || ss_x || enc_x || pk_x, label
            //   first, where X-Wing appends its label last (kem_combiner/xwing.rs:100);
            // - that label is the 7 bytes 5c2e2f0a2f5e5c, not XWingLabel's 6 bytes
            //   5c2e2f2f5e5c (kem_combiner/xwing.rs:107);
            // - ss_x is a DHKEM(X25519, HKDF-SHA256) secret, not the raw X25519 output
            //   X-Wing requires (dhkem.rs:111);
            // - key generation adds an HPKE dkp_prk extraction X-Wing does not have
            //   (hpke.rs:208), expands with SHAKE-128 rather than SHAKE-256
            //   (kem_combiner/xwing.rs:300), and labeled-expands the X25519 scalar
            //   instead of using it raw (dhkem.rs:208);
            // - no encapsulation-key check is performed, though X-Wing makes the ML-KEM
            //   check a MUST (kem_combiner/xwing.rs:242); and
            // - the combined KEM reports HPKE kem_id 15 (0x000F, unassigned at IANA)
            //   rather than 0x647a (kem_combiner/xwing.rs:149). That value is bound into
            //   the HPKE suite_id and the KEM dkp_prk label (hpke.rs:89), so it reaches
            //   every beta key schedule and every derived HPKE key pair.
            //
            // The upstream combiner also cites X-Wing draft-01, five revisions behind
            // the draft-06 that IANA references for 0x647a and nine behind the current
            // -10. These pinned crypto crates are already the newest published ones, so
            // no maintained upstream fix exists; ADR-040 keeps this mapping and rejects
            // authoring a conformant KEM here, which would be a project-local fork.
            // Do not describe any of this as TBD2 conformance; rows D1-D10 of
            // docs/mls-profile.md hold the full comparison.
            .combined_hpke(
                CipherSuite::CURVE25519_AES128,
                MlKem::MlKem768,
                KdfId::HkdfSha384,
                AeadId::Aes256Gcm,
                AwsLcHash::new_sha3(Sha3::SHA3_256)?,
            )
            .build(BETA_CIPHERSUITE)
    }
}

/// One active device identity already accepted by the client Authentication Service.
///
/// Construction of this value belongs after account-master, device-bundle, active-list,
/// and device-log verification. MLS still verifies every LeafNode/KeyPackage signature;
/// this record binds the signing key to the exact verified application credential.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AuthenticatedDevice {
    user_id: [u8; 16],
    device_id: [u8; 16],
    bundle_hash: [u8; 32],
    signature_public: Vec<u8>,
}

impl AuthenticatedDevice {
    pub fn from_verified_bundle(
        user_id: [u8; 16],
        device_id: [u8; 16],
        canonical_device_bundle: &[u8],
        signature_public: &[u8],
    ) -> Result<Self, AuthenticationServiceError> {
        if signature_public.len() != 32 || canonical_device_bundle.is_empty() {
            return Err(AuthenticationServiceError::MalformedRecord);
        }
        Ok(Self {
            user_id,
            device_id,
            bundle_hash: Sha256::digest(canonical_device_bundle).into(),
            signature_public: signature_public.to_vec(),
        })
    }

    pub fn credential_identifier(&self) -> Result<Vec<u8>, AuthenticationServiceError> {
        encode_credential_identifier(self.user_id, self.device_id, self.bundle_hash)
    }
}

/// `BasicCredential` validator backed exclusively by Authentication-Service-approved devices.
#[derive(Clone, Debug, Default)]
pub struct AuthenticatedDeviceIdentityProvider {
    by_credential: BTreeMap<Vec<u8>, AuthenticatedDevice>,
}

impl AuthenticatedDeviceIdentityProvider {
    pub fn new(
        devices: impl IntoIterator<Item = AuthenticatedDevice>,
    ) -> Result<Self, AuthenticationServiceError> {
        let mut by_credential = BTreeMap::new();
        for device in devices {
            let identifier = device.credential_identifier()?;
            if by_credential.insert(identifier, device).is_some() {
                return Err(AuthenticationServiceError::DuplicateCredential);
            }
        }
        if by_credential.is_empty() {
            return Err(AuthenticationServiceError::EmptyDirectory);
        }
        Ok(Self { by_credential })
    }

    fn resolve<'a>(
        &'a self,
        signing_identity: &SigningIdentity,
    ) -> Result<&'a AuthenticatedDevice, AuthenticationServiceError> {
        let credential = signing_identity
            .credential
            .as_basic()
            .ok_or(AuthenticationServiceError::UnsupportedCredential)?;
        let identifier = credential.identifier();
        let device = self
            .by_credential
            .get(identifier)
            .ok_or(AuthenticationServiceError::UnauthenticatedDevice)?;
        if signing_identity.signature_key.as_ref() != device.signature_public {
            return Err(AuthenticationServiceError::SignatureKeyMismatch);
        }
        Ok(device)
    }
}

/// Fully authenticated material needed to instantiate a stateless beta MLS client.
/// The local signer is copied only inside Rust and zeroized by mls-rs on drop.
#[derive(Clone)]
pub struct BetaMlsAuthenticationContext {
    local_device: AuthenticatedDevice,
    local_credential_identifier: Vec<u8>,
    local_bundle_request: Vec<u8>,
    signer: SignatureSecretKey,
    identity_provider: AuthenticatedDeviceIdentityProvider,
    bundle_proofs: Vec<Vec<u8>>,
}

impl fmt::Debug for BetaMlsAuthenticationContext {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("BetaMlsAuthenticationContext")
            .finish_non_exhaustive()
    }
}

impl BetaMlsAuthenticationContext {
    pub fn from_verified_bundle_requests(
        opaque_device_state: &[u8],
        migration_unix_day: u32,
        local_bundle_request: &[u8],
        additional_bundle_requests: &[Vec<u8>],
    ) -> Result<Self, BetaMlsEngineError> {
        if additional_bundle_requests.len() >= 50 {
            return Err(BetaMlsEngineError::ResourceLimit);
        }
        let state = decode_device_state(
            &RustCryptoProvider::default(),
            opaque_device_state,
            migration_unix_day,
        )
        .map_err(map_engine_crypto)?;
        let local = inspect_verified_claimed_device_bundle(local_bundle_request)
            .map_err(map_engine_crypto)?;
        if local.user_id != state.user_id || local.signing_public != state.device_signing_public {
            return Err(BetaMlsEngineError::AuthenticationFailed);
        }
        let expected_bundle = encode_cross_signature(&DeviceBundle {
            user_id: RawUuid::new(state.user_id),
            device_id: RawUuid::new(local.device_id),
            ik_public: state.ik_public(),
            spk_id: state.current_classical.id,
            spk_public: &state.current_classical.public,
            pq_signed_prekey: Some(PublicPrekey {
                id: state.current_pq.id,
                public: &state.current_pq.public,
            }),
            registration_id: state.registration_id,
            bundle_version: state.bundle_version,
        })
        .map_err(map_engine_crypto)?;
        if expected_bundle != local.canonical_bundle
            || state.cross_signature != local.cross_signature
            || state.cross_signature.iter().all(|byte| *byte == 0)
        {
            return Err(BetaMlsEngineError::AuthenticationFailed);
        }

        let local_device = authenticated_device(&local)?;
        let mut devices = Vec::with_capacity(additional_bundle_requests.len() + 1);
        devices.push(local_device.clone());
        for request in additional_bundle_requests {
            let verified =
                inspect_verified_claimed_device_bundle(request).map_err(map_engine_crypto)?;
            let device = authenticated_device(&verified)?;
            if !devices.contains(&device) {
                devices.push(device);
            }
        }
        let local_credential_identifier = local_device
            .credential_identifier()
            .map_err(map_authentication_error)?;
        let identity_provider =
            AuthenticatedDeviceIdentityProvider::new(devices).map_err(map_authentication_error)?;
        // mls-rs-crypto-awslc represents an Ed25519 private key as the
        // provider-native 64-byte seed || public-key form. Reuse the enrolled
        // device key; never generate a parallel MLS signing identity.
        let mut provider_signer = Zeroizing::new(Vec::with_capacity(64));
        provider_signer.extend_from_slice(&state.device_signing_secret);
        provider_signer.extend_from_slice(&state.device_signing_public);
        let signer = SignatureSecretKey::new_slice(&provider_signer);
        let mut bundle_proofs = vec![local_bundle_request.to_vec()];
        for request in additional_bundle_requests {
            if !bundle_proofs.iter().any(|existing| existing == request) {
                bundle_proofs.push(request.clone());
            }
        }
        Ok(Self {
            local_device,
            local_credential_identifier,
            local_bundle_request: local_bundle_request.to_vec(),
            signer,
            identity_provider,
            bundle_proofs,
        })
    }

    fn with_key_package_proofs(
        &self,
        proofs: impl IntoIterator<Item = Vec<u8>>,
    ) -> Result<Self, BetaMlsEngineError> {
        let mut next = self.clone();
        for proof in proofs {
            let verified =
                inspect_verified_claimed_device_bundle(&proof).map_err(map_engine_crypto)?;
            let historical = authenticated_device(&verified)?;
            let active = self
                .identity_provider
                .by_credential
                .values()
                .find(|candidate| {
                    candidate.user_id == historical.user_id
                        && candidate.device_id == historical.device_id
                })
                .ok_or(BetaMlsEngineError::AuthenticationFailed)?;
            if active.signature_public != historical.signature_public {
                return Err(BetaMlsEngineError::AuthenticationFailed);
            }
            let identifier = historical
                .credential_identifier()
                .map_err(map_authentication_error)?;
            if let Some(existing) = next
                .identity_provider
                .by_credential
                .insert(identifier, historical.clone())
                && existing != historical
            {
                return Err(BetaMlsEngineError::AuthenticationFailed);
            }
            if !next.bundle_proofs.iter().any(|existing| existing == &proof) {
                next.bundle_proofs.push(proof);
            }
        }
        Ok(next)
    }

    fn with_local_key_package_proof(&self, proof: Vec<u8>) -> Result<Self, BetaMlsEngineError> {
        let verified = inspect_verified_claimed_device_bundle(&proof).map_err(map_engine_crypto)?;
        let historical = authenticated_device(&verified)?;
        if historical.user_id != self.local_device.user_id
            || historical.device_id != self.local_device.device_id
            || historical.signature_public != self.local_device.signature_public
        {
            return Err(BetaMlsEngineError::AuthenticationFailed);
        }
        let mut next = self.with_key_package_proofs([proof])?;
        next.local_credential_identifier = historical
            .credential_identifier()
            .map_err(map_authentication_error)?;
        next.local_device = historical;
        Ok(next)
    }

    fn with_persisted_group_proofs(
        &self,
        proofs: Vec<Vec<u8>>,
        local_credential_identifier: &[u8],
    ) -> Result<Self, BetaMlsEngineError> {
        if proofs.is_empty() || proofs.len() > MAX_GROUP_AUTHENTICATION_PROOFS {
            return Err(BetaMlsEngineError::ResourceLimit);
        }
        let mut next = self.clone();
        for proof in proofs {
            let verified =
                inspect_verified_claimed_device_bundle(&proof).map_err(map_engine_crypto)?;
            let historical = authenticated_device(&verified)?;
            let identifier = historical
                .credential_identifier()
                .map_err(map_authentication_error)?;
            if let Some(existing) = next
                .identity_provider
                .by_credential
                .insert(identifier, historical.clone())
                && existing != historical
            {
                return Err(BetaMlsEngineError::AuthenticationFailed);
            }
            if !next.bundle_proofs.iter().any(|existing| existing == &proof) {
                next.bundle_proofs.push(proof);
            }
        }
        let local = next
            .identity_provider
            .by_credential
            .get(local_credential_identifier)
            .cloned()
            .ok_or(BetaMlsEngineError::AuthenticationFailed)?;
        if local.user_id != self.local_device.user_id
            || local.device_id != self.local_device.device_id
            || local.signature_public != self.local_device.signature_public
        {
            return Err(BetaMlsEngineError::AuthenticationFailed);
        }
        next.local_credential_identifier = local_credential_identifier.to_vec();
        next.local_device = local;
        Ok(next)
    }

    fn state_binding_identifier(&self) -> Result<Vec<u8>, CryptoError> {
        let mut binding = Vec::new();
        reserve(
            &mut binding,
            STATE_BINDING_MAGIC.len() + 16 + 16 + self.local_device.signature_public.len(),
        )?;
        binding.extend_from_slice(STATE_BINDING_MAGIC);
        binding.extend_from_slice(&self.local_device.user_id);
        binding.extend_from_slice(&self.local_device.device_id);
        binding.extend_from_slice(&self.local_device.signature_public);
        Ok(binding)
    }

    fn client(
        &self,
        group_storage: OpaqueMlsStateStorage,
        key_package_storage: OpaqueKeyPackageStorage,
    ) -> Client<impl MlsConfig + use<>> {
        let credential = BasicCredential::new(self.local_credential_identifier.clone());
        let signing_identity = SigningIdentity::new(
            credential.into_credential(),
            self.local_device.signature_public.clone().into(),
        );
        let mut encryption_options = EncryptionOptions::default();
        encryption_options.encrypt_control_messages = true;
        let rules = DefaultMlsRules::default().with_encryption_options(encryption_options);
        Client::builder()
            .identity_provider(self.identity_provider.clone())
            .mls_rules(rules)
            .crypto_provider(BetaMlsCryptoProvider)
            .key_package_repo(key_package_storage)
            .group_state_storage(group_storage)
            .signing_identity(signing_identity, self.signer.clone(), BETA_CIPHERSUITE)
            .build()
    }
}

fn authenticated_device(
    verified: &crate::enrollment::VerifiedClaimedDeviceBundle,
) -> Result<AuthenticatedDevice, BetaMlsEngineError> {
    AuthenticatedDevice::from_verified_bundle(
        verified.user_id,
        verified.device_id,
        &verified.canonical_bundle,
        &verified.signing_public,
    )
    .map_err(map_authentication_error)
}

pub struct GeneratedBetaKeyPackages {
    pub wrapped_key_packages: Vec<Vec<u8>>,
    pub opaque_key_package_state: Zeroizing<Vec<u8>>,
}

impl fmt::Debug for GeneratedBetaKeyPackages {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("GeneratedBetaKeyPackages")
            .field("count", &self.wrapped_key_packages.len())
            .finish_non_exhaustive()
    }
}

pub fn generate_key_packages(
    authentication: &BetaMlsAuthenticationContext,
    prior_opaque_key_package_state: Option<&[u8]>,
    count: usize,
    kind: BetaKeyPackageKind,
) -> Result<GeneratedBetaKeyPackages, BetaMlsEngineError> {
    if count == 0 || count > 100 || (kind == BetaKeyPackageKind::LastResort && count != 1) {
        return Err(BetaMlsEngineError::ResourceLimit);
    }
    let key_package_storage = match prior_opaque_key_package_state {
        Some(snapshot) => OpaqueKeyPackageStorage::import_snapshot(snapshot)
            .map_err(map_key_package_state_error)?,
        None => OpaqueKeyPackageStorage::default(),
    };
    let client = authentication.client(
        OpaqueMlsStateStorage::default(),
        key_package_storage.clone(),
    );
    let mut wrapped_key_packages = Vec::with_capacity(count);
    for _ in 0..count {
        let mut extensions = ExtensionList::new();
        if kind == BetaKeyPackageKind::LastResort {
            extensions
                .set_from(LastResortKeyPackageExt)
                .map_err(|_| BetaMlsEngineError::CryptoFailure)?;
        }
        let package = client
            .generate_key_package_message(extensions, ExtensionList::new(), None)
            .map_err(|_| BetaMlsEngineError::CryptoFailure)?;
        let suite = BetaMlsCryptoProvider
            .cipher_suite_provider(BETA_CIPHERSUITE)
            .ok_or(BetaMlsEngineError::CryptoFailure)?;
        let reference = package
            .key_package_reference(&suite)
            .map_err(|_| BetaMlsEngineError::CryptoFailure)?
            .ok_or(BetaMlsEngineError::CryptoFailure)?;
        key_package_storage
            .record_proof(reference.as_ref(), &authentication.local_bundle_request)
            .map_err(map_key_package_state_error)?;
        wrapped_key_packages.push(
            wrap_key_package(&package, kind, &authentication.local_bundle_request)
                .map_err(map_key_package_error)?,
        );
    }
    Ok(GeneratedBetaKeyPackages {
        wrapped_key_packages,
        opaque_key_package_state: key_package_storage
            .export_snapshot()
            .map_err(map_key_package_state_error)?,
    })
}

#[allow(clippy::too_many_lines)] // One bounded ABI dispatcher keeps every accepted operation discriminator explicit.
pub(crate) fn operation(operation: u32, input: &[u8]) -> Result<Vec<u8>, CryptoError> {
    if input.len() > MLS_MAX_IO_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    if !(OP_GENERATE_CONSUMABLE_KEY_PACKAGES..=OP_HASH_MLS_OBJECT).contains(&operation) {
        return Err(CryptoError::UnsupportedOperation);
    }
    let mut reader = Reader::new(input);
    reader.expect(OPERATION_REQUEST_MAGIC)?;
    if reader.u16()? != OPERATION_VERSION {
        return Err(CryptoError::UnsupportedVersion);
    }
    let opaque_device_state = reader.framed()?;
    let migration_unix_day = reader.u32()?;
    let local_bundle_request = reader.framed()?;
    let additional_count = usize::from(reader.u16()?);
    if additional_count >= 50 {
        return Err(CryptoError::InputTooLarge);
    }
    let mut additional_bundle_requests = Vec::with_capacity(additional_count);
    for _ in 0..additional_count {
        additional_bundle_requests.push(reader.framed()?.to_vec());
    }
    let authentication = BetaMlsAuthenticationContext::from_verified_bundle_requests(
        opaque_device_state,
        migration_unix_day,
        local_bundle_request,
        &additional_bundle_requests,
    )
    .map_err(map_engine_error)?;
    let provider = RustCryptoProvider::default();
    let state_key = derive_state_key(&provider, opaque_device_state, migration_unix_day)?;
    match operation {
        OP_GENERATE_CONSUMABLE_KEY_PACKAGES | OP_GENERATE_LAST_RESORT_KEY_PACKAGE => {
            let kind = if operation == OP_GENERATE_CONSUMABLE_KEY_PACKAGES {
                BetaKeyPackageKind::Consumable
            } else {
                BetaKeyPackageKind::LastResort
            };
            let prior_sealed_key_package_state = if reader.boolean()? {
                Some(reader.framed()?)
            } else {
                None
            };
            let count = usize::from(reader.u16()?);
            if !reader.is_finished() {
                return Err(CryptoError::MalformedInput);
            }
            generate_key_package_operation(
                operation,
                &provider,
                &state_key,
                &authentication,
                prior_sealed_key_package_state,
                count,
                kind,
            )
        }
        OP_CREATE_GROUP => create_group_operation(
            operation,
            &provider,
            &state_key,
            &authentication,
            &mut reader,
        ),
        OP_JOIN_GROUP => join_group_operation(
            operation,
            &provider,
            &state_key,
            &authentication,
            &mut reader,
        ),
        OP_ADD_MEMBERS => add_members_operation(
            operation,
            &provider,
            &state_key,
            &authentication,
            &mut reader,
        ),
        OP_REMOVE_MEMBERS => remove_members_operation(
            operation,
            &provider,
            &state_key,
            &authentication,
            &mut reader,
        ),
        OP_SEND_APPLICATION => send_application_operation(
            operation,
            &provider,
            &state_key,
            &authentication,
            &mut reader,
        ),
        OP_PROCESS_MESSAGE => process_message_operation(
            operation,
            &provider,
            &state_key,
            &authentication,
            &mut reader,
        ),
        OP_PROPOSE_UPDATE => propose_update_operation(
            operation,
            &provider,
            &state_key,
            &authentication,
            &mut reader,
        ),
        OP_COMMIT_PENDING_PROPOSALS => commit_pending_operation(
            operation,
            &provider,
            &state_key,
            &authentication,
            &mut reader,
        ),
        OP_SIGN_GROUP_CONTROL => {
            sign_group_control_operation(operation, &provider, &authentication, &mut reader)
        }
        OP_VERIFY_GROUP_CONTROL => {
            verify_group_control_operation(operation, &provider, &authentication, &mut reader)
        }
        OP_HASH_MLS_OBJECT => hash_mls_object_operation(operation, &provider, &mut reader),
        _ => Err(CryptoError::UnsupportedOperation),
    }
}

fn hash_mls_object_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let exact = reader.framed()?;
    if !reader.is_finished() || exact.is_empty() {
        return Err(CryptoError::MalformedInput);
    }
    let message = MlsMessage::from_bytes(exact).map_err(|_| CryptoError::MalformedInput)?;
    if message
        .to_bytes()
        .map_err(|_| CryptoError::MalformedInput)?
        != exact
    {
        return Err(CryptoError::MalformedInput);
    }
    let mut output = operation_response_header(operation)?;
    push_frame(&mut output, &provider.sha256(exact)?)?;
    bounded_operation_output(output)
}

fn generate_key_package_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    prior_sealed_key_package_state: Option<&[u8]>,
    count: usize,
    kind: BetaKeyPackageKind,
) -> Result<Vec<u8>, CryptoError> {
    let prior_opaque_key_package_state = prior_sealed_key_package_state
        .map(|sealed| {
            open_device_secret_snapshot(
                provider,
                state_key,
                SealedStateKind::KeyPackages,
                authentication,
                sealed,
            )
        })
        .transpose()?;
    let generated = generate_key_packages(
        authentication,
        prior_opaque_key_package_state
            .as_ref()
            .map(SecretVec::expose),
        count,
        kind,
    )
    .map_err(map_engine_error)?;
    let sealed_key_package_state = seal_device_secret_snapshot(
        provider,
        state_key,
        SealedStateKind::KeyPackages,
        authentication,
        &generated.opaque_key_package_state,
    )?;

    let mut output = Vec::new();
    reserve(&mut output, OPERATION_RESPONSE_MAGIC.len() + 3)?;
    output.extend_from_slice(OPERATION_RESPONSE_MAGIC);
    push_u16(&mut output, OPERATION_VERSION);
    output.push(u8::try_from(operation).map_err(|_| CryptoError::UnsupportedOperation)?);
    push_frame(&mut output, &sealed_key_package_state)?;
    push_u16(
        &mut output,
        u16::try_from(generated.wrapped_key_packages.len())
            .map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for package in generated.wrapped_key_packages {
        push_frame(&mut output, &package)?;
    }
    if output.len() > MLS_MAX_IO_BYTES {
        return Err(CryptoError::ResourceExhausted);
    }
    Ok(output)
}

fn create_group_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let key_packages = read_wrapped_key_packages(reader)?;
    let authenticated_data = reader.framed()?.to_vec();
    if !reader.is_finished() || key_packages.is_empty() || authenticated_data.len() > 64 * 1024 {
        return Err(CryptoError::MalformedInput);
    }
    let authentication = authentication
        .with_key_package_proofs(key_packages.iter().map(|(_, proof)| proof.clone()))
        .map_err(map_engine_error)?;
    let group_storage = OpaqueMlsStateStorage::default();
    let client = authentication.client(group_storage.clone(), OpaqueKeyPackageStorage::default());
    let mut group_id = [0_u8; 32];
    provider.random_bytes(&mut group_id)?;
    let mut group = client
        .create_group_with_id(
            group_id.to_vec(),
            ExtensionList::new(),
            ExtensionList::new(),
            None,
        )
        .map_err(|_| CryptoError::AuthenticationFailed)?;
    let mut builder = group.commit_builder();
    for (package, _) in key_packages {
        builder = builder
            .add_member(package)
            .map_err(|_| CryptoError::AuthenticationFailed)?;
    }
    let commit = builder
        .authenticated_data(authenticated_data)
        .build()
        .map_err(|_| CryptoError::AuthenticationFailed)?;
    group
        .apply_pending_commit()
        .map_err(|_| CryptoError::StateViolation)?;
    group
        .write_to_storage()
        .map_err(|_| CryptoError::StateViolation)?;
    encode_commit_operation_response(
        operation,
        provider,
        state_key,
        &authentication,
        &group_storage,
        &group,
        &commit.commit_message,
        commit.welcome_messages,
    )
}

fn join_group_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let sealed_key_package_state = reader.framed()?;
    let welcome_bytes = reader.framed()?;
    if !reader.is_finished() {
        return Err(CryptoError::MalformedInput);
    }
    let plaintext_key_packages = open_device_secret_snapshot(
        provider,
        state_key,
        SealedStateKind::KeyPackages,
        authentication,
        sealed_key_package_state,
    )?;
    let key_package_storage =
        OpaqueKeyPackageStorage::import_snapshot(plaintext_key_packages.expose())
            .map_err(map_key_package_state_crypto_error)?;
    let group_storage = OpaqueMlsStateStorage::default();
    let welcome = MlsMessage::from_bytes(welcome_bytes).map_err(|_| CryptoError::MalformedInput)?;
    let local_proof = welcome
        .welcome_key_package_references()
        .into_iter()
        .find_map(|reference| key_package_storage.proof(reference.as_ref()).transpose())
        .transpose()
        .map_err(map_key_package_state_crypto_error)?;
    let authentication = if let Some(proof) = local_proof {
        authentication
            .with_local_key_package_proof(proof)
            .map_err(map_engine_error)?
    } else {
        authentication.clone()
    };
    let client = authentication.client(group_storage.clone(), key_package_storage.clone());
    let (mut group, _) = client
        .join_group(None, &welcome, None)
        .map_err(|_| CryptoError::AuthenticationFailed)?;
    group
        .write_to_storage()
        .map_err(|_| CryptoError::StateViolation)?;
    let raw_group_state = export_group_state_envelope(&authentication, &group_storage, &group)?;
    let sealed_group_state = seal_device_secret_snapshot(
        provider,
        state_key,
        SealedStateKind::Group,
        &authentication,
        &raw_group_state,
    )?;
    let raw_key_package_state = key_package_storage
        .export_snapshot()
        .map_err(map_key_package_state_crypto_error)?;
    let sealed_key_package_state = seal_device_secret_snapshot(
        provider,
        state_key,
        SealedStateKind::KeyPackages,
        &authentication,
        &raw_key_package_state,
    )?;
    let mut output = operation_response_header(operation)?;
    push_frame(&mut output, &sealed_group_state)?;
    push_frame(&mut output, &sealed_key_package_state)?;
    push_frame(&mut output, group.group_id())?;
    push_u64(&mut output, group.current_epoch());
    let roster = group_roster_subjects(&group)?;
    push_u16(
        &mut output,
        u16::try_from(roster.len()).map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for (user_id, device_id) in roster {
        push_frame(&mut output, &user_id)?;
        push_frame(&mut output, &device_id)?;
    }
    output.extend_from_slice(&exporter_confirmation(provider, &group)?);
    bounded_operation_output(output)
}

fn add_members_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let sealed_group_state = reader.framed()?;
    let key_packages = read_wrapped_key_packages(reader)?;
    let authenticated_data = reader.framed()?.to_vec();
    if !reader.is_finished() || key_packages.is_empty() || authenticated_data.len() > 64 * 1024 {
        return Err(CryptoError::MalformedInput);
    }
    let authentication = authentication
        .with_key_package_proofs(key_packages.iter().map(|(_, proof)| proof.clone()))
        .map_err(map_engine_error)?;
    let (group_storage, client, group_id, authentication) =
        restore_group_client(provider, state_key, &authentication, sealed_group_state)?;
    let mut group = client
        .load_group(&group_id)
        .map_err(|_| CryptoError::StateViolation)?;
    let mut builder = group.commit_builder();
    for (package, _) in key_packages {
        builder = builder
            .add_member(package)
            .map_err(|_| CryptoError::AuthenticationFailed)?;
    }
    let commit = builder
        .authenticated_data(authenticated_data)
        .build()
        .map_err(|_| CryptoError::AuthenticationFailed)?;
    group
        .apply_pending_commit()
        .map_err(|_| CryptoError::StateViolation)?;
    group
        .write_to_storage()
        .map_err(|_| CryptoError::StateViolation)?;
    encode_commit_operation_response(
        operation,
        provider,
        state_key,
        &authentication,
        &group_storage,
        &group,
        &commit.commit_message,
        commit.welcome_messages,
    )
}

fn remove_members_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let sealed_group_state = reader.framed()?;
    let target_count = usize::from(reader.u16()?);
    if target_count == 0 || target_count >= 50 {
        return Err(CryptoError::MalformedInput);
    }
    let mut targets = Vec::with_capacity(target_count);
    for _ in 0..target_count {
        let target = reader.framed()?.to_vec();
        if target.len() != 16 || targets.iter().any(|existing| existing == &target) {
            return Err(CryptoError::MalformedInput);
        }
        targets.push(target);
    }
    let authenticated_data = reader.framed()?.to_vec();
    if !reader.is_finished() || authenticated_data.len() > 64 * 1024 {
        return Err(CryptoError::MalformedInput);
    }
    let (group_storage, client, group_id, authentication) =
        restore_group_client(provider, state_key, authentication, sealed_group_state)?;
    let mut group = client
        .load_group(&group_id)
        .map_err(|_| CryptoError::StateViolation)?;
    let roster = group.roster().members();
    let mut matched_targets = vec![false; targets.len()];
    let mut indexes = Vec::new();
    for member in &roster {
        let Some(credential) = member.signing_identity.credential.as_basic() else {
            return Err(CryptoError::AuthenticationFailed);
        };
        let user_id = credential_user_id(credential.identifier())?;
        if let Some(target_index) = targets.iter().position(|target| target == &user_id) {
            if member.index == group.current_member_index() {
                return Err(CryptoError::StateViolation);
            }
            matched_targets[target_index] = true;
            indexes.push(member.index);
        }
    }
    if matched_targets.iter().any(|matched| !matched) || indexes.is_empty() {
        return Err(CryptoError::AuthenticationFailed);
    }
    indexes.sort_unstable();
    let mut builder = group.commit_builder();
    for index in indexes {
        builder = builder
            .remove_member(index)
            .map_err(|_| CryptoError::StateViolation)?;
    }
    let commit = builder
        .authenticated_data(authenticated_data)
        .build()
        .map_err(|_| CryptoError::AuthenticationFailed)?;
    group
        .apply_pending_commit()
        .map_err(|_| CryptoError::StateViolation)?;
    group
        .write_to_storage()
        .map_err(|_| CryptoError::StateViolation)?;
    encode_commit_operation_response(
        operation,
        provider,
        state_key,
        &authentication,
        &group_storage,
        &group,
        &commit.commit_message,
        Vec::new(),
    )
}

fn send_application_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let sealed_group_state = reader.framed()?;
    let application_data = reader.framed()?.to_vec();
    let authenticated_data = reader.framed()?.to_vec();
    if !reader.is_finished() || application_data.is_empty() || authenticated_data.len() > 64 * 1024
    {
        return Err(CryptoError::MalformedInput);
    }
    let (group_storage, client, group_id, authentication) =
        restore_group_client(provider, state_key, authentication, sealed_group_state)?;
    let mut group = client
        .load_group(&group_id)
        .map_err(|_| CryptoError::StateViolation)?;
    let message = group
        .encrypt_application_message(&application_data, authenticated_data)
        .map_err(|_| CryptoError::StateViolation)?;
    group
        .write_to_storage()
        .map_err(|_| CryptoError::StateViolation)?;
    encode_message_operation_response(
        operation,
        provider,
        state_key,
        &authentication,
        &group_storage,
        &group,
        &message,
    )
}

fn process_message_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let sealed_group_state = reader.framed()?;
    let message_bytes = reader.framed()?;
    let message_digest = provider.sha256(message_bytes)?;
    let message = MlsMessage::from_bytes(message_bytes).map_err(|_| CryptoError::MalformedInput)?;
    if !reader.is_finished() {
        return Err(CryptoError::MalformedInput);
    }
    let (group_storage, client, group_id, authentication) =
        restore_group_client(provider, state_key, authentication, sealed_group_state)?;
    let mut group = client
        .load_group(&group_id)
        .map_err(|_| CryptoError::StateViolation)?;
    let received = group
        .process_incoming_message(message)
        .map_err(|_| CryptoError::AuthenticationFailed)?;
    let (kind, sender, data, authenticated_data) = match received {
        ReceivedMessage::ApplicationMessage(message) => (
            1_u8,
            message.sender_index,
            message.data().to_vec(),
            message.authenticated_data,
        ),
        ReceivedMessage::Commit(message) => {
            (2, message.committer, Vec::new(), message.authenticated_data)
        }
        ReceivedMessage::Proposal(message) => {
            let ProposalSender::Member(sender) = message.sender else {
                return Err(CryptoError::AuthenticationFailed);
            };
            (3, sender, Vec::new(), message.authenticated_data)
        }
        ReceivedMessage::GroupInfo(_) => (4, u32::MAX, Vec::new(), Vec::new()),
        ReceivedMessage::Welcome | ReceivedMessage::KeyPackage(_) => {
            return Err(CryptoError::MalformedInput);
        }
    };
    let (sender_user_id, sender_device_id) = if sender == u32::MAX {
        (Vec::new(), Vec::new())
    } else {
        let roster = group.roster().members();
        let sender_member = roster
            .iter()
            .find(|member| member.index == sender)
            .ok_or(CryptoError::AuthenticationFailed)?;
        let credential = sender_member
            .signing_identity
            .credential
            .as_basic()
            .ok_or(CryptoError::AuthenticationFailed)?;
        credential_subject(credential.identifier())?
    };
    group
        .write_to_storage()
        .map_err(|_| CryptoError::StateViolation)?;
    let raw_state = export_group_state_envelope(&authentication, &group_storage, &group)?;
    let sealed_state = seal_device_secret_snapshot(
        provider,
        state_key,
        SealedStateKind::Group,
        &authentication,
        &raw_state,
    )?;
    let mut output = operation_response_header(operation)?;
    push_frame(&mut output, &sealed_state)?;
    push_frame(&mut output, &message_digest)?;
    output.push(kind);
    push_u32(&mut output, sender);
    push_frame(&mut output, &sender_user_id)?;
    push_frame(&mut output, &sender_device_id)?;
    push_frame(&mut output, &data)?;
    push_frame(&mut output, &authenticated_data)?;
    push_frame(&mut output, group.group_id())?;
    push_u64(&mut output, group.current_epoch());
    output.extend_from_slice(&exporter_confirmation(provider, &group)?);
    bounded_operation_output(output)
}

fn propose_update_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let sealed_group_state = reader.framed()?;
    let authenticated_data = reader.framed()?.to_vec();
    if !reader.is_finished() || authenticated_data.len() > 64 * 1024 {
        return Err(CryptoError::MalformedInput);
    }
    let (group_storage, client, group_id, authentication) =
        restore_group_client(provider, state_key, authentication, sealed_group_state)?;
    let mut group = client
        .load_group(&group_id)
        .map_err(|_| CryptoError::StateViolation)?;
    let proposal = group
        .propose_update(authenticated_data)
        .map_err(|_| CryptoError::StateViolation)?;
    group
        .write_to_storage()
        .map_err(|_| CryptoError::StateViolation)?;
    encode_message_operation_response(
        operation,
        provider,
        state_key,
        &authentication,
        &group_storage,
        &group,
        &proposal,
    )
}

fn commit_pending_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let sealed_group_state = reader.framed()?;
    let authenticated_data = reader.framed()?.to_vec();
    if !reader.is_finished() || authenticated_data.len() > 64 * 1024 {
        return Err(CryptoError::MalformedInput);
    }
    let (group_storage, client, group_id, authentication) =
        restore_group_client(provider, state_key, authentication, sealed_group_state)?;
    let mut group = client
        .load_group(&group_id)
        .map_err(|_| CryptoError::StateViolation)?;
    let commit = group
        .commit(authenticated_data)
        .map_err(|_| CryptoError::StateViolation)?;
    group
        .apply_pending_commit()
        .map_err(|_| CryptoError::StateViolation)?;
    group
        .write_to_storage()
        .map_err(|_| CryptoError::StateViolation)?;
    encode_commit_operation_response(
        operation,
        provider,
        state_key,
        &authentication,
        &group_storage,
        &group,
        &commit.commit_message,
        commit.welcome_messages,
    )
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct GroupControlMetadata {
    name: String,
    description: String,
    photo_capability: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct GroupControlMember {
    user_id: [u8; 16],
    display_name: String,
    role: u8,
    membership: u8,
    verified: bool,
    device_ids: Vec<[u8; 16]>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum GroupControlOperation {
    Create {
        metadata: GroupControlMetadata,
        invitation_policy: u8,
        history_policy: u8,
        members: Vec<GroupControlMember>,
    },
    UpdateMetadata(GroupControlMetadata),
    UpdatePolicies {
        invitation_policy: u8,
        history_policy: u8,
    },
    Invite(Vec<GroupControlMember>),
    Remove([u8; 16]),
    Leave,
    ChangeRole {
        target: [u8; 16],
        role: u8,
    },
    TransferOwnership([u8; 16]),
}

impl GroupControlOperation {
    /// Whether the control carries its own MLS Commit.
    ///
    /// `Leave` deliberately does not. RFC 9420 section 12.4 forbids a Commit
    /// that removes its own committer, because the committer must know the new
    /// epoch secrets, so a departing member cannot produce the Commit that
    /// evicts it. A leave is therefore an authenticated announcement signed at
    /// the current epoch; a remaining member issues the `Remove` Commit that
    /// actually evicts the leaf.
    fn changes_membership(&self) -> bool {
        matches!(
            self,
            Self::Create { .. } | Self::Invite(_) | Self::Remove(_)
        )
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct GroupControlDescriptor {
    event_id: [u8; 16],
    group_id: [u8; 32],
    revision: u32,
    previous_control_state_hash: Option<[u8; 32]>,
    mls_epoch: u64,
    mls_commit_hash: Option<[u8; 32]>,
    signer_user_id: [u8; 16],
    signer_device_id: [u8; 16],
    created_ms: u64,
    operation: GroupControlOperation,
}

fn sign_group_control_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let descriptor = read_group_control_descriptor(
        reader,
        authentication.local_device.user_id,
        authentication.local_device.device_id,
    )?;
    if !reader.is_finished() {
        return Err(CryptoError::MalformedInput);
    }
    let canonical = encode_group_control(&descriptor)?;
    let signature_input = group_control_signature_input(&canonical)?;
    let signer_bytes = authentication.signer.as_bytes();
    let signer_seed: [u8; 32] = signer_bytes
        .get(..32)
        .ok_or(CryptoError::StateViolation)?
        .try_into()
        .map_err(|_| CryptoError::StateViolation)?;
    let signer_seed = SecretBytes::new(signer_seed);
    let signature = provider.ed25519_sign(&signer_seed, &signature_input)?;
    encode_group_control_response(operation, provider, &descriptor, &canonical, &signature)
}

fn verify_group_control_operation(
    operation: u32,
    provider: &RustCryptoProvider,
    authentication: &BetaMlsAuthenticationContext,
    reader: &mut Reader<'_>,
) -> Result<Vec<u8>, CryptoError> {
    let signer_user_id = exact_frame::<16>(reader)?;
    let signer_device_id = exact_frame::<16>(reader)?;
    let descriptor = read_group_control_descriptor(reader, signer_user_id, signer_device_id)?;
    let payload = reader.framed()?;
    if !reader.is_finished() {
        return Err(CryptoError::MalformedInput);
    }
    let mut payload_reader = Reader::new(payload);
    payload_reader.expect(GROUP_CONTROL_PAYLOAD_MAGIC)?;
    if payload_reader.u16()? != 1 {
        return Err(CryptoError::UnsupportedVersion);
    }
    let supplied_canonical = payload_reader.framed()?;
    let signature: [u8; 64] = exact_frame(&mut payload_reader)?;
    if !payload_reader.is_finished() {
        return Err(CryptoError::MalformedInput);
    }
    let canonical = encode_group_control(&descriptor)?;
    if supplied_canonical != canonical {
        return Err(CryptoError::AuthenticationFailed);
    }
    let signer = authentication
        .identity_provider
        .by_credential
        .values()
        .find(|device| device.user_id == signer_user_id && device.device_id == signer_device_id)
        .ok_or(CryptoError::AuthenticationFailed)?;
    let signer_public: &[u8; 32] = signer
        .signature_public
        .as_slice()
        .try_into()
        .map_err(|_| CryptoError::AuthenticationFailed)?;
    provider.ed25519_verify(
        signer_public,
        &group_control_signature_input(&canonical)?,
        &signature,
    )?;
    encode_group_control_response(operation, provider, &descriptor, &canonical, &signature)
}

fn encode_group_control_response(
    operation: u32,
    provider: &RustCryptoProvider,
    descriptor: &GroupControlDescriptor,
    canonical: &[u8],
    signature: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    if signature.len() != 64 {
        return Err(CryptoError::InternalFailure);
    }
    let mut state_input = Vec::new();
    reserve(
        &mut state_input,
        GROUP_CONTROL_STATE_DOMAIN.len() + canonical.len() + signature.len() + 8,
    )?;
    state_input.extend_from_slice(GROUP_CONTROL_STATE_DOMAIN);
    push_frame(&mut state_input, canonical)?;
    push_frame(&mut state_input, signature)?;
    let control_state_hash = provider.sha256(&state_input)?;
    let mut payload = Vec::new();
    payload.extend_from_slice(GROUP_CONTROL_PAYLOAD_MAGIC);
    push_u16(&mut payload, 1);
    push_frame(&mut payload, canonical)?;
    push_frame(&mut payload, signature)?;
    let mut output = operation_response_header(operation)?;
    push_frame(&mut output, canonical)?;
    push_frame(&mut output, signature)?;
    push_frame(&mut output, &control_state_hash)?;
    push_frame(&mut output, &payload)?;
    push_frame(&mut output, &descriptor.signer_user_id)?;
    push_frame(&mut output, &descriptor.signer_device_id)?;
    bounded_operation_output(output)
}

fn group_control_signature_input(canonical: &[u8]) -> Result<Vec<u8>, CryptoError> {
    let mut output = Vec::new();
    reserve(
        &mut output,
        GROUP_CONTROL_SIGNATURE_DOMAIN.len() + canonical.len() + 4,
    )?;
    output.extend_from_slice(GROUP_CONTROL_SIGNATURE_DOMAIN);
    push_frame(&mut output, canonical)?;
    Ok(output)
}

fn read_group_control_descriptor(
    reader: &mut Reader<'_>,
    signer_user_id: [u8; 16],
    signer_device_id: [u8; 16],
) -> Result<GroupControlDescriptor, CryptoError> {
    let event_id = exact_frame(reader)?;
    let group_id = exact_frame(reader)?;
    let revision = reader.u32()?;
    let previous_control_state_hash = if reader.boolean()? {
        Some(exact_frame(reader)?)
    } else {
        None
    };
    let mls_epoch = reader.u64()?;
    let mls_commit_hash = if reader.boolean()? {
        Some(exact_frame(reader)?)
    } else {
        None
    };
    let created_ms = reader.u64()?;
    let operation = read_group_control_operation(reader)?;
    if revision == 0
        || operation.changes_membership() != mls_commit_hash.is_some()
        || matches!(operation, GroupControlOperation::Create { .. })
            != (revision == 1 && previous_control_state_hash.is_none())
    {
        return Err(CryptoError::MalformedInput);
    }
    Ok(GroupControlDescriptor {
        event_id,
        group_id,
        revision,
        previous_control_state_hash,
        mls_epoch,
        mls_commit_hash,
        signer_user_id,
        signer_device_id,
        created_ms,
        operation,
    })
}

fn read_group_control_operation(
    reader: &mut Reader<'_>,
) -> Result<GroupControlOperation, CryptoError> {
    match reader.u8()? {
        1 => Ok(GroupControlOperation::Create {
            metadata: read_group_control_metadata(reader)?,
            invitation_policy: read_policy(reader)?,
            history_policy: read_history_policy(reader)?,
            members: read_group_control_members(reader)?,
        }),
        2 => Ok(GroupControlOperation::UpdateMetadata(
            read_group_control_metadata(reader)?,
        )),
        3 => Ok(GroupControlOperation::UpdatePolicies {
            invitation_policy: read_policy(reader)?,
            history_policy: read_history_policy(reader)?,
        }),
        4 => Ok(GroupControlOperation::Invite(read_group_control_members(
            reader,
        )?)),
        5 => Ok(GroupControlOperation::Remove(exact_frame(reader)?)),
        6 => Ok(GroupControlOperation::Leave),
        7 => {
            let target = exact_frame(reader)?;
            let role = reader.u8()?;
            if role > 2 {
                return Err(CryptoError::MalformedInput);
            }
            Ok(GroupControlOperation::ChangeRole { target, role })
        }
        8 => Ok(GroupControlOperation::TransferOwnership(exact_frame(
            reader,
        )?)),
        _ => Err(CryptoError::UnsupportedOperation),
    }
}

fn read_group_control_metadata(
    reader: &mut Reader<'_>,
) -> Result<GroupControlMetadata, CryptoError> {
    let name = read_group_text(reader, 400, 100, true)?;
    let description = read_group_text(reader, 4_000, 1_000, false)?;
    let photo_capability = if reader.boolean()? {
        Some(read_group_text(reader, 4_096, 1_024, true)?)
    } else {
        None
    };
    if name.trim() != name || description.trim() != description {
        return Err(CryptoError::MalformedInput);
    }
    Ok(GroupControlMetadata {
        name,
        description,
        photo_capability,
    })
}

fn read_group_control_members(
    reader: &mut Reader<'_>,
) -> Result<Vec<GroupControlMember>, CryptoError> {
    let count = usize::from(reader.u16()?);
    if count == 0 || count > 50 {
        return Err(CryptoError::MalformedInput);
    }
    let mut members = Vec::with_capacity(count);
    for _ in 0..count {
        let user_id = exact_frame(reader)?;
        let display_name = read_group_text(reader, 1_024, 256, true)?;
        let role = reader.u8()?;
        let membership = reader.u8()?;
        let verified = reader.boolean()?;
        let device_count = usize::from(reader.u16()?);
        if role > 2 || membership > 2 || device_count == 0 || device_count > 50 {
            return Err(CryptoError::MalformedInput);
        }
        let mut device_ids = Vec::with_capacity(device_count);
        for _ in 0..device_count {
            device_ids.push(exact_frame(reader)?);
        }
        device_ids.sort_unstable();
        if device_ids.windows(2).any(|pair| pair[0] == pair[1]) {
            return Err(CryptoError::MalformedInput);
        }
        members.push(GroupControlMember {
            user_id,
            display_name,
            role,
            membership,
            verified,
            device_ids,
        });
    }
    members.sort_by_key(|member| member.user_id);
    if members
        .windows(2)
        .any(|pair| pair[0].user_id == pair[1].user_id)
    {
        return Err(CryptoError::MalformedInput);
    }
    Ok(members)
}

fn read_group_text(
    reader: &mut Reader<'_>,
    maximum_bytes: usize,
    maximum_scalars: usize,
    require_non_empty: bool,
) -> Result<String, CryptoError> {
    let bytes = reader.framed()?;
    if bytes.len() > maximum_bytes {
        return Err(CryptoError::InputTooLarge);
    }
    let value = std::str::from_utf8(bytes).map_err(|_| CryptoError::MalformedInput)?;
    if value.chars().count() > maximum_scalars || (require_non_empty && value.is_empty()) {
        return Err(CryptoError::MalformedInput);
    }
    Ok(value.to_owned())
}

fn read_policy(reader: &mut Reader<'_>) -> Result<u8, CryptoError> {
    let value = reader.u8()?;
    if value > 2 {
        return Err(CryptoError::MalformedInput);
    }
    Ok(value)
}

fn read_history_policy(reader: &mut Reader<'_>) -> Result<u8, CryptoError> {
    let value = reader.u8()?;
    if value > 1 {
        return Err(CryptoError::MalformedInput);
    }
    Ok(value)
}

fn exact_frame<const LENGTH: usize>(reader: &mut Reader<'_>) -> Result<[u8; LENGTH], CryptoError> {
    reader
        .framed()?
        .try_into()
        .map_err(|_| CryptoError::MalformedInput)
}

fn encode_group_control(descriptor: &GroupControlDescriptor) -> Result<Vec<u8>, CryptoError> {
    let mut output = Vec::new();
    let mut encoder = Encoder::new(&mut output);
    encoder
        .array(11)
        .map_err(|_| CryptoError::InternalFailure)?;
    encoder.u8(1).map_err(|_| CryptoError::InternalFailure)?;
    encoder
        .bytes(&descriptor.event_id)
        .map_err(|_| CryptoError::InternalFailure)?;
    encoder
        .bytes(&descriptor.group_id)
        .map_err(|_| CryptoError::InternalFailure)?;
    encoder
        .u32(descriptor.revision)
        .map_err(|_| CryptoError::InternalFailure)?;
    encode_optional_bytes(
        &mut encoder,
        descriptor.previous_control_state_hash.as_ref(),
    )?;
    encoder
        .u64(descriptor.mls_epoch)
        .map_err(|_| CryptoError::InternalFailure)?;
    encode_optional_bytes(&mut encoder, descriptor.mls_commit_hash.as_ref())?;
    encoder
        .bytes(&descriptor.signer_user_id)
        .map_err(|_| CryptoError::InternalFailure)?;
    encoder
        .bytes(&descriptor.signer_device_id)
        .map_err(|_| CryptoError::InternalFailure)?;
    encoder
        .u64(descriptor.created_ms)
        .map_err(|_| CryptoError::InternalFailure)?;
    encode_group_control_operation(&mut encoder, &descriptor.operation)?;
    if output.len() > 64 * 1024 {
        return Err(CryptoError::InputTooLarge);
    }
    Ok(output)
}

fn encode_group_control_operation(
    encoder: &mut Encoder<&mut Vec<u8>>,
    operation: &GroupControlOperation,
) -> Result<(), CryptoError> {
    match operation {
        GroupControlOperation::Create {
            metadata,
            invitation_policy,
            history_policy,
            members,
        } => {
            encoder.array(5).map_err(|_| CryptoError::InternalFailure)?;
            encoder.u8(1).map_err(|_| CryptoError::InternalFailure)?;
            encode_group_control_metadata(encoder, metadata)?;
            encoder
                .u8(*invitation_policy)
                .map_err(|_| CryptoError::InternalFailure)?;
            encoder
                .u8(*history_policy)
                .map_err(|_| CryptoError::InternalFailure)?;
            encode_group_control_members(encoder, members)?;
        }
        GroupControlOperation::UpdateMetadata(metadata) => {
            encoder.array(2).map_err(|_| CryptoError::InternalFailure)?;
            encoder.u8(2).map_err(|_| CryptoError::InternalFailure)?;
            encode_group_control_metadata(encoder, metadata)?;
        }
        GroupControlOperation::UpdatePolicies {
            invitation_policy,
            history_policy,
        } => {
            encoder.array(3).map_err(|_| CryptoError::InternalFailure)?;
            encoder.u8(3).map_err(|_| CryptoError::InternalFailure)?;
            encoder
                .u8(*invitation_policy)
                .map_err(|_| CryptoError::InternalFailure)?;
            encoder
                .u8(*history_policy)
                .map_err(|_| CryptoError::InternalFailure)?;
        }
        GroupControlOperation::Invite(members) => {
            encoder.array(2).map_err(|_| CryptoError::InternalFailure)?;
            encoder.u8(4).map_err(|_| CryptoError::InternalFailure)?;
            encode_group_control_members(encoder, members)?;
        }
        GroupControlOperation::Remove(target) => {
            encoder.array(2).map_err(|_| CryptoError::InternalFailure)?;
            encoder.u8(5).map_err(|_| CryptoError::InternalFailure)?;
            encoder
                .bytes(target)
                .map_err(|_| CryptoError::InternalFailure)?;
        }
        GroupControlOperation::Leave => {
            encoder.array(1).map_err(|_| CryptoError::InternalFailure)?;
            encoder.u8(6).map_err(|_| CryptoError::InternalFailure)?;
        }
        GroupControlOperation::ChangeRole { target, role } => {
            encoder.array(3).map_err(|_| CryptoError::InternalFailure)?;
            encoder.u8(7).map_err(|_| CryptoError::InternalFailure)?;
            encoder
                .bytes(target)
                .map_err(|_| CryptoError::InternalFailure)?;
            encoder
                .u8(*role)
                .map_err(|_| CryptoError::InternalFailure)?;
        }
        GroupControlOperation::TransferOwnership(target) => {
            encoder.array(2).map_err(|_| CryptoError::InternalFailure)?;
            encoder.u8(8).map_err(|_| CryptoError::InternalFailure)?;
            encoder
                .bytes(target)
                .map_err(|_| CryptoError::InternalFailure)?;
        }
    }
    Ok(())
}

fn encode_group_control_metadata(
    encoder: &mut Encoder<&mut Vec<u8>>,
    metadata: &GroupControlMetadata,
) -> Result<(), CryptoError> {
    encoder.array(3).map_err(|_| CryptoError::InternalFailure)?;
    encoder
        .str(&metadata.name)
        .map_err(|_| CryptoError::InternalFailure)?;
    encoder
        .str(&metadata.description)
        .map_err(|_| CryptoError::InternalFailure)?;
    if let Some(photo) = metadata.photo_capability.as_deref() {
        encoder
            .str(photo)
            .map_err(|_| CryptoError::InternalFailure)?;
    } else {
        encoder.null().map_err(|_| CryptoError::InternalFailure)?;
    }
    Ok(())
}

fn encode_group_control_members(
    encoder: &mut Encoder<&mut Vec<u8>>,
    members: &[GroupControlMember],
) -> Result<(), CryptoError> {
    encoder
        .array(u64::try_from(members.len()).map_err(|_| CryptoError::InputTooLarge)?)
        .map_err(|_| CryptoError::InternalFailure)?;
    for member in members {
        encoder.array(6).map_err(|_| CryptoError::InternalFailure)?;
        encoder
            .bytes(&member.user_id)
            .map_err(|_| CryptoError::InternalFailure)?;
        encoder
            .str(&member.display_name)
            .map_err(|_| CryptoError::InternalFailure)?;
        encoder
            .u8(member.role)
            .map_err(|_| CryptoError::InternalFailure)?;
        encoder
            .u8(member.membership)
            .map_err(|_| CryptoError::InternalFailure)?;
        encoder
            .bool(member.verified)
            .map_err(|_| CryptoError::InternalFailure)?;
        encoder
            .array(u64::try_from(member.device_ids.len()).map_err(|_| CryptoError::InputTooLarge)?)
            .map_err(|_| CryptoError::InternalFailure)?;
        for device_id in &member.device_ids {
            encoder
                .bytes(device_id)
                .map_err(|_| CryptoError::InternalFailure)?;
        }
    }
    Ok(())
}

fn encode_optional_bytes<const LENGTH: usize>(
    encoder: &mut Encoder<&mut Vec<u8>>,
    value: Option<&[u8; LENGTH]>,
) -> Result<(), CryptoError> {
    if let Some(value) = value {
        encoder
            .bytes(value)
            .map_err(|_| CryptoError::InternalFailure)?;
    } else {
        encoder.null().map_err(|_| CryptoError::InternalFailure)?;
    }
    Ok(())
}

fn read_wrapped_key_packages(
    reader: &mut Reader<'_>,
) -> Result<Vec<(MlsMessage, Vec<u8>)>, CryptoError> {
    let count = usize::from(reader.u16()?);
    if count == 0 || count >= 50 {
        return Err(CryptoError::MalformedInput);
    }
    let mut packages = Vec::with_capacity(count);
    for _ in 0..count {
        let package = reader.framed()?;
        if !KEY_PACKAGE_BUCKETS.contains(&package.len()) {
            return Err(CryptoError::MalformedInput);
        }
        let (_, message, proof) =
            unwrap_key_package(package).map_err(map_key_package_crypto_error)?;
        packages.push((message, proof));
    }
    Ok(packages)
}

fn restore_group_client(
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    sealed_group_state: &[u8],
) -> Result<
    (
        OpaqueMlsStateStorage,
        Client<impl MlsConfig>,
        Vec<u8>,
        BetaMlsAuthenticationContext,
    ),
    CryptoError,
> {
    let plaintext = open_device_secret_snapshot(
        provider,
        state_key,
        SealedStateKind::Group,
        authentication,
        sealed_group_state,
    )?;
    let (storage, group_id, authentication) =
        import_group_state_envelope(authentication, plaintext.expose())?;
    let client = authentication.client(storage.clone(), OpaqueKeyPackageStorage::default());
    Ok((storage, client, group_id, authentication))
}

fn group_authentication_proofs<C: MlsConfig>(
    authentication: &BetaMlsAuthenticationContext,
    group: &Group<C>,
) -> Result<Vec<Vec<u8>>, CryptoError> {
    let mut available = BTreeMap::new();
    for proof in &authentication.bundle_proofs {
        let verified = inspect_verified_claimed_device_bundle(proof)
            .map_err(map_engine_crypto)
            .map_err(map_engine_error)?;
        let device = authenticated_device(&verified).map_err(map_engine_error)?;
        let identifier = device
            .credential_identifier()
            .map_err(map_authentication_error)
            .map_err(map_engine_error)?;
        if let Some(existing) = available.insert(identifier, proof.clone())
            && existing != *proof
        {
            return Err(CryptoError::AuthenticationFailed);
        }
    }

    let roster = group.roster().members();
    if roster.is_empty() || roster.len() > MAX_GROUP_AUTHENTICATION_PROOFS {
        return Err(CryptoError::ResourceExhausted);
    }
    let mut selected = BTreeMap::new();
    for member in roster {
        let credential = member
            .signing_identity
            .credential
            .as_basic()
            .ok_or(CryptoError::AuthenticationFailed)?;
        let identifier = credential.identifier().to_vec();
        let proof = available
            .get(&identifier)
            .cloned()
            .ok_or(CryptoError::AuthenticationFailed)?;
        selected.insert(identifier, proof);
    }
    Ok(selected.into_values().collect())
}

type RosterSubject = (Vec<u8>, Vec<u8>);

fn group_roster_subjects<C: MlsConfig>(
    group: &Group<C>,
) -> Result<Vec<RosterSubject>, CryptoError> {
    let roster = group.roster().members();
    if roster.is_empty() || roster.len() > MAX_GROUP_AUTHENTICATION_PROOFS {
        return Err(CryptoError::ResourceExhausted);
    }
    let mut subjects = Vec::with_capacity(roster.len());
    for member in roster {
        let credential = member
            .signing_identity
            .credential
            .as_basic()
            .ok_or(CryptoError::AuthenticationFailed)?;
        let subject = credential_subject(credential.identifier())?;
        if subjects.contains(&subject) {
            return Err(CryptoError::AuthenticationFailed);
        }
        subjects.push(subject);
    }
    subjects.sort();
    Ok(subjects)
}

fn export_group_state_envelope<C: MlsConfig>(
    authentication: &BetaMlsAuthenticationContext,
    group_storage: &OpaqueMlsStateStorage,
    group: &Group<C>,
) -> Result<Zeroizing<Vec<u8>>, CryptoError> {
    let raw_state = group_storage
        .export_snapshot(group.group_id())
        .map_err(map_group_state_crypto_error)?;
    let proofs = group_authentication_proofs(authentication, group)?;
    let mut output = Vec::new();
    output.extend_from_slice(GROUP_STATE_ENVELOPE_MAGIC);
    push_u16(&mut output, GROUP_STATE_ENVELOPE_VERSION);
    push_u16(&mut output, BETA_CIPHERSUITE_ID);
    push_frame(&mut output, &authentication.local_credential_identifier)?;
    push_u16(
        &mut output,
        u16::try_from(proofs.len()).map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for proof in proofs {
        push_frame(&mut output, &proof)?;
    }
    push_frame(&mut output, &raw_state)?;
    if output.len() > MLS_MAX_IO_BYTES {
        return Err(CryptoError::ResourceExhausted);
    }
    Ok(Zeroizing::new(output))
}

fn import_group_state_envelope(
    authentication: &BetaMlsAuthenticationContext,
    plaintext: &[u8],
) -> Result<(OpaqueMlsStateStorage, Vec<u8>, BetaMlsAuthenticationContext), CryptoError> {
    // Explicit migration for the piece-18/beta-preflight state layout. The
    // next successful operation always rewrites it as CPMLSG01.
    if plaintext.starts_with(BETA_STATE_MAGIC) {
        let (storage, group_id) = OpaqueMlsStateStorage::import_snapshot(plaintext)
            .map_err(map_group_state_crypto_error)?;
        return Ok((storage, group_id, authentication.clone()));
    }

    let mut reader = Reader::new(plaintext);
    reader.expect(GROUP_STATE_ENVELOPE_MAGIC)?;
    if reader.u16()? != GROUP_STATE_ENVELOPE_VERSION {
        return Err(CryptoError::UnsupportedVersion);
    }
    if reader.u16()? != BETA_CIPHERSUITE_ID {
        return Err(CryptoError::UnsupportedOperation);
    }
    let local_credential_identifier = reader.framed()?.to_vec();
    let proof_count = usize::from(reader.u16()?);
    if local_credential_identifier.is_empty()
        || proof_count == 0
        || proof_count > MAX_GROUP_AUTHENTICATION_PROOFS
    {
        return Err(CryptoError::MalformedInput);
    }
    let mut proofs = Vec::with_capacity(proof_count);
    for _ in 0..proof_count {
        let proof = reader.framed()?.to_vec();
        validate_bundle_proof(&proof).map_err(map_key_package_crypto_error)?;
        if proofs.iter().any(|existing| existing == &proof) {
            return Err(CryptoError::MalformedInput);
        }
        proofs.push(proof);
    }
    let raw_state = reader.framed()?;
    if raw_state.is_empty() || !reader.is_finished() {
        return Err(CryptoError::MalformedInput);
    }
    let authentication = authentication
        .with_persisted_group_proofs(proofs, &local_credential_identifier)
        .map_err(map_engine_error)?;
    let (storage, group_id) =
        OpaqueMlsStateStorage::import_snapshot(raw_state).map_err(map_group_state_crypto_error)?;
    Ok((storage, group_id, authentication))
}

#[allow(clippy::too_many_arguments)] // The response must bind the exact state, group, Commit, and Welcome set in one encoder.
fn encode_commit_operation_response<C: MlsConfig>(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    group_storage: &OpaqueMlsStateStorage,
    group: &Group<C>,
    commit: &MlsMessage,
    welcomes: Vec<MlsMessage>,
) -> Result<Vec<u8>, CryptoError> {
    let raw_state = export_group_state_envelope(authentication, group_storage, group)?;
    let sealed_state = seal_device_secret_snapshot(
        provider,
        state_key,
        SealedStateKind::Group,
        authentication,
        &raw_state,
    )?;
    let commit = commit
        .to_bytes()
        .map_err(|_| CryptoError::InternalFailure)?;
    let commit_digest = provider.sha256(&commit)?;
    let group_info = group
        .group_info_message(true)
        .map_err(|_| CryptoError::StateViolation)?
        .to_bytes()
        .map_err(|_| CryptoError::InternalFailure)?;
    let mut output = operation_response_header(operation)?;
    push_frame(&mut output, &sealed_state)?;
    push_frame(&mut output, &commit)?;
    push_frame(&mut output, &commit_digest)?;
    let authentication_proofs = group_authentication_proofs(authentication, group)?;
    push_u16(
        &mut output,
        u16::try_from(authentication_proofs.len()).map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for proof in authentication_proofs {
        push_frame(&mut output, &proof)?;
    }
    push_u16(
        &mut output,
        u16::try_from(welcomes.len()).map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for welcome in welcomes {
        let welcome = welcome
            .to_bytes()
            .map_err(|_| CryptoError::InternalFailure)?;
        push_frame(&mut output, &welcome)?;
    }
    push_frame(&mut output, &group_info)?;
    push_frame(&mut output, group.group_id())?;
    push_u64(&mut output, group.current_epoch());
    output.extend_from_slice(&exporter_confirmation(provider, group)?);
    bounded_operation_output(output)
}

fn encode_message_operation_response<C: MlsConfig>(
    operation: u32,
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    authentication: &BetaMlsAuthenticationContext,
    group_storage: &OpaqueMlsStateStorage,
    group: &Group<C>,
    message: &MlsMessage,
) -> Result<Vec<u8>, CryptoError> {
    let raw_state = export_group_state_envelope(authentication, group_storage, group)?;
    let sealed_state = seal_device_secret_snapshot(
        provider,
        state_key,
        SealedStateKind::Group,
        authentication,
        &raw_state,
    )?;
    let message = message
        .to_bytes()
        .map_err(|_| CryptoError::InternalFailure)?;
    let mut output = operation_response_header(operation)?;
    push_frame(&mut output, &sealed_state)?;
    push_frame(&mut output, &message)?;
    push_frame(&mut output, group.group_id())?;
    push_u64(&mut output, group.current_epoch());
    output.extend_from_slice(&exporter_confirmation(provider, group)?);
    bounded_operation_output(output)
}

fn operation_response_header(operation: u32) -> Result<Vec<u8>, CryptoError> {
    let mut output = Vec::new();
    reserve(&mut output, OPERATION_RESPONSE_MAGIC.len() + 3)?;
    output.extend_from_slice(OPERATION_RESPONSE_MAGIC);
    push_u16(&mut output, OPERATION_VERSION);
    output.push(u8::try_from(operation).map_err(|_| CryptoError::UnsupportedOperation)?);
    Ok(output)
}

fn bounded_operation_output(output: Vec<u8>) -> Result<Vec<u8>, CryptoError> {
    if output.len() > MLS_MAX_IO_BYTES {
        Err(CryptoError::ResourceExhausted)
    } else {
        Ok(output)
    }
}

fn exporter_confirmation<C: MlsConfig>(
    provider: &RustCryptoProvider,
    group: &Group<C>,
) -> Result<[u8; 32], CryptoError> {
    let exporter = group
        .export_secret(b"chat:v1:beta-group-export", group.group_id(), 32)
        .map_err(|_| CryptoError::StateViolation)?;
    provider.sha256(exporter.as_ref())
}

fn credential_user_id(identifier: &[u8]) -> Result<Vec<u8>, CryptoError> {
    credential_subject(identifier).map(|(user_id, _)| user_id)
}

fn credential_subject(identifier: &[u8]) -> Result<(Vec<u8>, Vec<u8>), CryptoError> {
    let mut decoder = Decoder::new(identifier);
    if decoder.array().map_err(|_| CryptoError::MalformedInput)? != Some(4)
        || decoder.u8().map_err(|_| CryptoError::MalformedInput)? != CREDENTIAL_PROTOCOL_VERSION
    {
        return Err(CryptoError::MalformedInput);
    }
    let user_id = decoder
        .bytes()
        .map_err(|_| CryptoError::MalformedInput)?
        .to_vec();
    let device_id = decoder
        .bytes()
        .map_err(|_| CryptoError::MalformedInput)?
        .to_vec();
    let bundle_hash = decoder.bytes().map_err(|_| CryptoError::MalformedInput)?;
    if user_id.len() != 16
        || device_id.len() != 16
        || bundle_hash.len() != 32
        || decoder.position() != identifier.len()
    {
        return Err(CryptoError::MalformedInput);
    }
    Ok((user_id, device_id))
}

const fn map_key_package_crypto_error(error: BetaKeyPackageError) -> CryptoError {
    match error {
        BetaKeyPackageError::EntropyUnavailable => CryptoError::EntropyUnavailable,
        BetaKeyPackageError::TooLarge | BetaKeyPackageError::WrongBucket => {
            CryptoError::InputTooLarge
        }
        BetaKeyPackageError::UnsupportedVersion => CryptoError::UnsupportedVersion,
        BetaKeyPackageError::KindMismatch
        | BetaKeyPackageError::Malformed
        | BetaKeyPackageError::NonCanonical
        | BetaKeyPackageError::NotKeyPackage
        | BetaKeyPackageError::SuiteMismatch => CryptoError::MalformedInput,
    }
}

const fn map_key_package_state_crypto_error(error: BetaKeyPackageStateError) -> CryptoError {
    match error {
        BetaKeyPackageStateError::ResourceLimit => CryptoError::ResourceExhausted,
        BetaKeyPackageStateError::UnsupportedVersion => CryptoError::UnsupportedVersion,
        BetaKeyPackageStateError::Poisoned => CryptoError::InternalFailure,
        BetaKeyPackageStateError::Malformed | BetaKeyPackageStateError::SuiteMismatch => {
            CryptoError::MalformedInput
        }
    }
}

const fn map_group_state_crypto_error(error: BetaMlsStateError) -> CryptoError {
    match error {
        BetaMlsStateError::ResourceLimit => CryptoError::ResourceExhausted,
        BetaMlsStateError::UnsupportedVersion => CryptoError::UnsupportedVersion,
        BetaMlsStateError::Poisoned => CryptoError::InternalFailure,
        BetaMlsStateError::NotFound => CryptoError::StateViolation,
        BetaMlsStateError::Malformed | BetaMlsStateError::SuiteMismatch => {
            CryptoError::MalformedInput
        }
    }
}

fn derive_state_key(
    provider: &RustCryptoProvider,
    opaque_device_state: &[u8],
    migration_unix_day: u32,
) -> Result<SecretBytes<32>, CryptoError> {
    let state = decode_device_state(provider, opaque_device_state, migration_unix_day)?;
    let input_key_material = SecretVec::input(&state.identity_secret)?;
    let derived = provider.hkdf_sha256(&[0; 32], &input_key_material, SEALED_STATE_KEY_DOMAIN)?;
    let key: [u8; 32] = derived
        .expose()
        .try_into()
        .map_err(|_| CryptoError::InternalFailure)?;
    Ok(SecretBytes::new(key))
}

fn seal_secret_snapshot(
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    kind: SealedStateKind,
    credential_identifier: &[u8],
    plaintext: &[u8],
) -> Result<Zeroizing<Vec<u8>>, CryptoError> {
    if plaintext.is_empty() || plaintext.len() > MLS_MAX_IO_BYTES {
        return Err(CryptoError::MalformedInput);
    }
    let mut header = Vec::new();
    reserve(&mut header, SEALED_STATE_MAGIC.len() + 2 + 2 + 1 + 32)?;
    header.extend_from_slice(SEALED_STATE_MAGIC);
    push_u16(&mut header, SEALED_STATE_VERSION);
    push_u16(&mut header, BETA_CIPHERSUITE_ID);
    header.push(kind as u8);
    header.extend_from_slice(&provider.sha256(credential_identifier)?);

    let mut nonce = [0_u8; XCHACHA_NONCE_BYTES];
    provider.random_bytes(&mut nonce)?;
    let plaintext = SecretVec::input(plaintext)?;
    let ciphertext = provider.xchacha20poly1305_encrypt(state_key, &nonce, &plaintext, &header)?;
    let total = header
        .len()
        .checked_add(nonce.len())
        .and_then(|length| length.checked_add(ciphertext.len()))
        .ok_or(CryptoError::ResourceExhausted)?;
    if total > MLS_MAX_IO_BYTES {
        return Err(CryptoError::ResourceExhausted);
    }
    let mut sealed = Vec::new();
    reserve(&mut sealed, total)?;
    sealed.extend_from_slice(&header);
    sealed.extend_from_slice(&nonce);
    sealed.extend_from_slice(&ciphertext);
    Ok(Zeroizing::new(sealed))
}

fn open_secret_snapshot(
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    expected_kind: SealedStateKind,
    credential_identifier: &[u8],
    sealed: &[u8],
) -> Result<SecretVec, CryptoError> {
    const HEADER_BYTES: usize = 8 + 2 + 2 + 1 + 32;
    if sealed.len() < HEADER_BYTES + XCHACHA_NONCE_BYTES + XCHACHA_TAG_BYTES
        || sealed.len() > MLS_MAX_IO_BYTES
    {
        return Err(CryptoError::MalformedInput);
    }
    let (header, body) = sealed.split_at(HEADER_BYTES);
    let mut reader = Reader::new(header);
    reader.expect(SEALED_STATE_MAGIC)?;
    let version = reader.u16()?;
    if version != 1 && version != SEALED_STATE_VERSION {
        return Err(CryptoError::UnsupportedVersion);
    }
    if reader.u16()? != BETA_CIPHERSUITE_ID {
        return Err(CryptoError::UnsupportedOperation);
    }
    if reader.u8()? != expected_kind as u8 {
        return Err(CryptoError::MalformedInput);
    }
    let expected_credential_hash = provider.sha256(credential_identifier)?;
    if reader.take(expected_credential_hash.len())? != expected_credential_hash
        || !reader.is_finished()
    {
        return Err(CryptoError::AuthenticationFailed);
    }
    let (nonce, ciphertext) = body.split_at(XCHACHA_NONCE_BYTES);
    let nonce: &[u8; XCHACHA_NONCE_BYTES] =
        nonce.try_into().map_err(|_| CryptoError::MalformedInput)?;
    provider.xchacha20poly1305_decrypt(state_key, nonce, ciphertext, header)
}

fn open_device_secret_snapshot(
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    expected_kind: SealedStateKind,
    authentication: &BetaMlsAuthenticationContext,
    sealed: &[u8],
) -> Result<SecretVec, CryptoError> {
    let mut reader = Reader::new(sealed);
    reader.expect(SEALED_STATE_MAGIC)?;
    let version = reader.u16()?;
    let binding = match version {
        // Version 1 bound state to the complete BasicCredential identifier.
        // It remains readable until the local signed-prekey bundle rotates and
        // is migrated to the stable device-signing-key binding on next write.
        1 => authentication.local_credential_identifier.clone(),
        SEALED_STATE_VERSION => authentication.state_binding_identifier()?,
        _ => return Err(CryptoError::UnsupportedVersion),
    };
    open_secret_snapshot(provider, state_key, expected_kind, &binding, sealed)
}

fn seal_device_secret_snapshot(
    provider: &RustCryptoProvider,
    state_key: &SecretBytes<32>,
    kind: SealedStateKind,
    authentication: &BetaMlsAuthenticationContext,
    plaintext: &[u8],
) -> Result<Zeroizing<Vec<u8>>, CryptoError> {
    seal_secret_snapshot(
        provider,
        state_key,
        kind,
        &authentication.state_binding_identifier()?,
        plaintext,
    )
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BetaMlsEngineError {
    AuthenticationFailed,
    CryptoFailure,
    EntropyUnavailable,
    Malformed,
    ResourceLimit,
    StateFailure,
    UnsupportedVersion,
}

impl fmt::Display for BetaMlsEngineError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::AuthenticationFailed => "beta MLS device authentication failed",
            Self::CryptoFailure => "beta MLS cryptographic operation failed",
            Self::EntropyUnavailable => "secure randomness unavailable",
            Self::Malformed => "malformed beta MLS input",
            Self::ResourceLimit => "beta MLS resource limit exceeded",
            Self::StateFailure => "beta MLS state operation failed",
            Self::UnsupportedVersion => "unsupported beta MLS state version",
        })
    }
}

impl Error for BetaMlsEngineError {}

const fn map_engine_crypto(error: CryptoError) -> BetaMlsEngineError {
    match error {
        CryptoError::AuthenticationFailed => BetaMlsEngineError::AuthenticationFailed,
        CryptoError::EntropyUnavailable => BetaMlsEngineError::EntropyUnavailable,
        CryptoError::InputTooLarge | CryptoError::ResourceExhausted => {
            BetaMlsEngineError::ResourceLimit
        }
        CryptoError::UnsupportedVersion => BetaMlsEngineError::UnsupportedVersion,
        _ => BetaMlsEngineError::Malformed,
    }
}

const fn map_authentication_error(_: AuthenticationServiceError) -> BetaMlsEngineError {
    BetaMlsEngineError::AuthenticationFailed
}

const fn map_key_package_error(error: BetaKeyPackageError) -> BetaMlsEngineError {
    match error {
        BetaKeyPackageError::EntropyUnavailable => BetaMlsEngineError::EntropyUnavailable,
        BetaKeyPackageError::TooLarge => BetaMlsEngineError::ResourceLimit,
        BetaKeyPackageError::UnsupportedVersion => BetaMlsEngineError::UnsupportedVersion,
        _ => BetaMlsEngineError::Malformed,
    }
}

const fn map_key_package_state_error(error: BetaKeyPackageStateError) -> BetaMlsEngineError {
    match error {
        BetaKeyPackageStateError::ResourceLimit => BetaMlsEngineError::ResourceLimit,
        BetaKeyPackageStateError::UnsupportedVersion => BetaMlsEngineError::UnsupportedVersion,
        BetaKeyPackageStateError::Poisoned => BetaMlsEngineError::StateFailure,
        BetaKeyPackageStateError::Malformed | BetaKeyPackageStateError::SuiteMismatch => {
            BetaMlsEngineError::Malformed
        }
    }
}

const fn map_engine_error(error: BetaMlsEngineError) -> CryptoError {
    match error {
        BetaMlsEngineError::AuthenticationFailed => CryptoError::AuthenticationFailed,
        BetaMlsEngineError::EntropyUnavailable => CryptoError::EntropyUnavailable,
        BetaMlsEngineError::ResourceLimit => CryptoError::ResourceExhausted,
        BetaMlsEngineError::StateFailure => CryptoError::StateViolation,
        BetaMlsEngineError::UnsupportedVersion => CryptoError::UnsupportedVersion,
        BetaMlsEngineError::CryptoFailure | BetaMlsEngineError::Malformed => {
            CryptoError::MalformedInput
        }
    }
}

impl IdentityProvider for AuthenticatedDeviceIdentityProvider {
    type Error = AuthenticationServiceError;

    fn validate_member(
        &self,
        signing_identity: &SigningIdentity,
        _timestamp: Option<MlsTime>,
        _context: MemberValidationContext<'_>,
    ) -> Result<(), Self::Error> {
        self.resolve(signing_identity).map(|_| ())
    }

    fn validate_external_sender(
        &self,
        signing_identity: &SigningIdentity,
        _timestamp: Option<MlsTime>,
        _extensions: Option<&ExtensionList>,
    ) -> Result<(), Self::Error> {
        self.resolve(signing_identity).map(|_| ())
    }

    fn identity(
        &self,
        signing_identity: &SigningIdentity,
        _extensions: &ExtensionList,
    ) -> Result<Vec<u8>, Self::Error> {
        self.resolve(signing_identity)?;
        signing_identity
            .credential
            .as_basic()
            .map(|credential| credential.identifier().to_vec())
            .ok_or(AuthenticationServiceError::UnsupportedCredential)
    }

    fn valid_successor(
        &self,
        predecessor: &SigningIdentity,
        successor: &SigningIdentity,
        _extensions: &ExtensionList,
    ) -> Result<bool, Self::Error> {
        let predecessor = self.resolve(predecessor)?;
        let successor = self.resolve(successor)?;
        Ok(
            predecessor.user_id == successor.user_id
                && predecessor.device_id == successor.device_id,
        )
    }

    fn supported_types(&self) -> Vec<CredentialType> {
        vec![BasicCredential::credential_type()]
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthenticationServiceError {
    DuplicateCredential,
    EmptyDirectory,
    MalformedRecord,
    SignatureKeyMismatch,
    UnauthenticatedDevice,
    UnsupportedCredential,
}

impl fmt::Display for AuthenticationServiceError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::DuplicateCredential => "duplicate authenticated MLS credential",
            Self::EmptyDirectory => "empty authenticated device directory",
            Self::MalformedRecord => "malformed authenticated device record",
            Self::SignatureKeyMismatch => "MLS signature key does not match device bundle",
            Self::UnauthenticatedDevice => "device is not Authentication-Service approved",
            Self::UnsupportedCredential => "unsupported MLS credential type",
        })
    }
}

impl Error for AuthenticationServiceError {}

impl IntoAnyError for AuthenticationServiceError {
    fn into_dyn_error(self) -> Result<Box<dyn Error + Send + Sync>, Self> {
        Ok(Box::new(self))
    }
}

#[derive(Clone, Debug)]
struct StoredGroup {
    state: Zeroizing<Vec<u8>>,
    epochs: BTreeMap<u64, Zeroizing<Vec<u8>>>,
}

/// Cloneable MLS storage whose exact state and retained prior epochs can be
/// exported as one opaque, versioned database value.
#[derive(Clone, Default)]
pub struct OpaqueMlsStateStorage {
    groups: Arc<Mutex<BTreeMap<Vec<u8>, StoredGroup>>>,
}

impl fmt::Debug for OpaqueMlsStateStorage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OpaqueMlsStateStorage")
            .finish_non_exhaustive()
    }
}

impl OpaqueMlsStateStorage {
    pub fn export_snapshot(
        &self,
        group_id: &[u8],
    ) -> Result<Zeroizing<Vec<u8>>, BetaMlsStateError> {
        let groups = self.lock()?;
        let group = groups.get(group_id).ok_or(BetaMlsStateError::NotFound)?;
        let mut output = Vec::new();
        output.extend_from_slice(BETA_STATE_MAGIC);
        push_u16(&mut output, BETA_STATE_FORMAT_VERSION);
        push_u16(&mut output, BETA_CIPHERSUITE_ID);
        push_frame(&mut output, group_id).map_err(|_| BetaMlsStateError::ResourceLimit)?;
        push_frame(&mut output, &group.state).map_err(|_| BetaMlsStateError::ResourceLimit)?;
        push_u32(
            &mut output,
            u32::try_from(group.epochs.len()).map_err(|_| BetaMlsStateError::ResourceLimit)?,
        );
        for (epoch_id, epoch) in &group.epochs {
            push_u64(&mut output, *epoch_id);
            push_frame(&mut output, epoch).map_err(|_| BetaMlsStateError::ResourceLimit)?;
        }
        Ok(Zeroizing::new(output))
    }

    pub fn import_snapshot(snapshot: &[u8]) -> Result<(Self, Vec<u8>), BetaMlsStateError> {
        let mut reader = Reader::new(snapshot);
        if reader
            .take(BETA_STATE_MAGIC.len())
            .map_err(map_state_parse)?
            != BETA_STATE_MAGIC
        {
            return Err(BetaMlsStateError::Malformed);
        }
        let version = reader.u16().map_err(map_state_parse)?;
        if version != BETA_STATE_FORMAT_VERSION {
            return Err(BetaMlsStateError::UnsupportedVersion);
        }
        if reader.u16().map_err(map_state_parse)? != BETA_CIPHERSUITE_ID {
            return Err(BetaMlsStateError::SuiteMismatch);
        }
        let group_id = reader.framed().map_err(map_state_parse)?.to_vec();
        let state = Zeroizing::new(reader.framed().map_err(map_state_parse)?.to_vec());
        let epoch_count = usize::try_from(reader.u32().map_err(map_state_parse)?)
            .map_err(|_| BetaMlsStateError::ResourceLimit)?;
        if group_id.is_empty() || state.is_empty() || epoch_count > MAX_RETAINED_EPOCHS {
            return Err(BetaMlsStateError::Malformed);
        }
        let mut epochs = BTreeMap::new();
        for _ in 0..epoch_count {
            let epoch_id = reader.u64().map_err(map_state_parse)?;
            let epoch = Zeroizing::new(reader.framed().map_err(map_state_parse)?.to_vec());
            if epoch.is_empty() || epochs.insert(epoch_id, epoch).is_some() {
                return Err(BetaMlsStateError::Malformed);
            }
        }
        if !reader.is_finished() {
            return Err(BetaMlsStateError::Malformed);
        }
        let storage = Self::default();
        storage
            .lock()?
            .insert(group_id.clone(), StoredGroup { state, epochs });
        Ok((storage, group_id))
    }

    fn lock(&self) -> Result<MutexGuard<'_, BTreeMap<Vec<u8>, StoredGroup>>, BetaMlsStateError> {
        self.groups.lock().map_err(|_| BetaMlsStateError::Poisoned)
    }
}

impl GroupStateStorage for OpaqueMlsStateStorage {
    type Error = BetaMlsStateError;

    fn state(&self, group_id: &[u8]) -> Result<Option<Zeroizing<Vec<u8>>>, Self::Error> {
        Ok(self.lock()?.get(group_id).map(|group| group.state.clone()))
    }

    fn epoch(
        &self,
        group_id: &[u8],
        epoch_id: u64,
    ) -> Result<Option<Zeroizing<Vec<u8>>>, Self::Error> {
        Ok(self
            .lock()?
            .get(group_id)
            .and_then(|group| group.epochs.get(&epoch_id).cloned()))
    }

    fn write(
        &mut self,
        state: StoredMlsGroupState,
        epoch_inserts: Vec<EpochRecord>,
        epoch_updates: Vec<EpochRecord>,
    ) -> Result<(), Self::Error> {
        let mut groups = self.lock()?;
        let group = groups.entry(state.id).or_insert_with(|| StoredGroup {
            state: Zeroizing::new(Vec::new()),
            epochs: BTreeMap::new(),
        });
        group.state = state.data;
        for epoch in epoch_inserts {
            group.epochs.insert(epoch.id, epoch.data);
        }
        for epoch in epoch_updates {
            if let Some(stored) = group.epochs.get_mut(&epoch.id) {
                *stored = epoch.data;
            }
        }
        while group.epochs.len() > MAX_RETAINED_EPOCHS {
            if let Some(oldest) = group.epochs.keys().next().copied() {
                group.epochs.remove(&oldest);
            }
        }
        Ok(())
    }

    fn max_epoch_id(&self, group_id: &[u8]) -> Result<Option<u64>, Self::Error> {
        Ok(self
            .lock()?
            .get(group_id)
            .and_then(|group| group.epochs.keys().next_back().copied()))
    }
}

/// `KeyPackage` secret repository with a single opaque export/import value.
/// Deleting an entry drops the HPKE secrets immediately; mls-rs deliberately
/// skips deletion when the standardized last-resort extension is present.
#[derive(Clone, Default)]
pub struct OpaqueKeyPackageStorage {
    packages: Arc<Mutex<BTreeMap<Vec<u8>, KeyPackageData>>>,
    proofs: Arc<Mutex<BTreeMap<Vec<u8>, Vec<u8>>>>,
}

impl fmt::Debug for OpaqueKeyPackageStorage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OpaqueKeyPackageStorage")
            .finish_non_exhaustive()
    }
}

impl OpaqueKeyPackageStorage {
    pub fn export_snapshot(&self) -> Result<Zeroizing<Vec<u8>>, BetaKeyPackageStateError> {
        let packages = self.lock()?;
        let mut output = Vec::new();
        output.extend_from_slice(KEY_PACKAGE_STORE_MAGIC);
        push_u16(&mut output, KEY_PACKAGE_STORE_VERSION);
        push_u16(&mut output, BETA_CIPHERSUITE_ID);
        push_u32(
            &mut output,
            u32::try_from(packages.len()).map_err(|_| BetaKeyPackageStateError::ResourceLimit)?,
        );
        for (reference, package) in packages.iter() {
            push_frame(&mut output, reference)
                .map_err(|_| BetaKeyPackageStateError::ResourceLimit)?;
            let encoded = Zeroizing::new(
                package
                    .mls_encode_to_vec()
                    .map_err(|_| BetaKeyPackageStateError::Malformed)?,
            );
            push_frame(&mut output, &encoded)
                .map_err(|_| BetaKeyPackageStateError::ResourceLimit)?;
            let proof = self
                .proofs
                .lock()
                .map_err(|_| BetaKeyPackageStateError::Poisoned)?
                .get(reference)
                .cloned()
                .unwrap_or_default();
            push_frame(&mut output, &proof).map_err(|_| BetaKeyPackageStateError::ResourceLimit)?;
        }
        Ok(Zeroizing::new(output))
    }

    pub fn import_snapshot(snapshot: &[u8]) -> Result<Self, BetaKeyPackageStateError> {
        let mut reader = Reader::new(snapshot);
        if reader
            .take(KEY_PACKAGE_STORE_MAGIC.len())
            .map_err(|_| BetaKeyPackageStateError::Malformed)?
            != KEY_PACKAGE_STORE_MAGIC
        {
            return Err(BetaKeyPackageStateError::Malformed);
        }
        let version = reader
            .u16()
            .map_err(|_| BetaKeyPackageStateError::Malformed)?;
        if version != 1 && version != KEY_PACKAGE_STORE_VERSION {
            return Err(BetaKeyPackageStateError::UnsupportedVersion);
        }
        if reader
            .u16()
            .map_err(|_| BetaKeyPackageStateError::Malformed)?
            != BETA_CIPHERSUITE_ID
        {
            return Err(BetaKeyPackageStateError::SuiteMismatch);
        }
        let count = usize::try_from(
            reader
                .u32()
                .map_err(|_| BetaKeyPackageStateError::Malformed)?,
        )
        .map_err(|_| BetaKeyPackageStateError::ResourceLimit)?;
        if count > MAX_STORED_KEY_PACKAGES {
            return Err(BetaKeyPackageStateError::ResourceLimit);
        }
        let mut packages = BTreeMap::new();
        let mut proofs = BTreeMap::new();
        for _ in 0..count {
            let reference = reader
                .framed()
                .map_err(|_| BetaKeyPackageStateError::Malformed)?
                .to_vec();
            let encoded = reader
                .framed()
                .map_err(|_| BetaKeyPackageStateError::Malformed)?;
            if reference.is_empty() || encoded.is_empty() {
                return Err(BetaKeyPackageStateError::Malformed);
            }
            let mut remaining = encoded;
            let package = KeyPackageData::mls_decode(&mut remaining)
                .map_err(|_| BetaKeyPackageStateError::Malformed)?;
            if !remaining.is_empty() || packages.insert(reference.clone(), package).is_some() {
                return Err(BetaKeyPackageStateError::Malformed);
            }
            if version >= 2 {
                let proof = reader
                    .framed()
                    .map_err(|_| BetaKeyPackageStateError::Malformed)?
                    .to_vec();
                if !proof.is_empty() {
                    validate_bundle_proof(&proof)
                        .map_err(|_| BetaKeyPackageStateError::Malformed)?;
                    proofs.insert(reference, proof);
                }
            }
        }
        if !reader.is_finished() {
            return Err(BetaKeyPackageStateError::Malformed);
        }
        Ok(Self {
            packages: Arc::new(Mutex::new(packages)),
            proofs: Arc::new(Mutex::new(proofs)),
        })
    }

    #[cfg(test)]
    pub fn len(&self) -> Result<usize, BetaKeyPackageStateError> {
        Ok(self.lock()?.len())
    }

    #[cfg(test)]
    pub fn is_empty(&self) -> Result<bool, BetaKeyPackageStateError> {
        Ok(self.lock()?.is_empty())
    }

    fn record_proof(&self, reference: &[u8], proof: &[u8]) -> Result<(), BetaKeyPackageStateError> {
        validate_bundle_proof(proof).map_err(|_| BetaKeyPackageStateError::Malformed)?;
        if !self.lock()?.contains_key(reference) {
            return Err(BetaKeyPackageStateError::Malformed);
        }
        self.proofs
            .lock()
            .map_err(|_| BetaKeyPackageStateError::Poisoned)?
            .insert(reference.to_vec(), proof.to_vec());
        Ok(())
    }

    fn proof(&self, reference: &[u8]) -> Result<Option<Vec<u8>>, BetaKeyPackageStateError> {
        Ok(self
            .proofs
            .lock()
            .map_err(|_| BetaKeyPackageStateError::Poisoned)?
            .get(reference)
            .cloned())
    }

    fn lock(
        &self,
    ) -> Result<MutexGuard<'_, BTreeMap<Vec<u8>, KeyPackageData>>, BetaKeyPackageStateError> {
        self.packages
            .lock()
            .map_err(|_| BetaKeyPackageStateError::Poisoned)
    }
}

impl KeyPackageStorage for OpaqueKeyPackageStorage {
    type Error = BetaKeyPackageStateError;

    fn delete(&mut self, id: &[u8]) -> Result<(), Self::Error> {
        self.lock()?.remove(id);
        self.proofs
            .lock()
            .map_err(|_| BetaKeyPackageStateError::Poisoned)?
            .remove(id);
        Ok(())
    }

    fn insert(&mut self, id: Vec<u8>, package: KeyPackageData) -> Result<(), Self::Error> {
        let mut packages = self.lock()?;
        if !packages.contains_key(&id) && packages.len() >= MAX_STORED_KEY_PACKAGES {
            return Err(BetaKeyPackageStateError::ResourceLimit);
        }
        packages.insert(id, package);
        Ok(())
    }

    fn get(&self, id: &[u8]) -> Result<Option<KeyPackageData>, Self::Error> {
        Ok(self.lock()?.get(id).cloned())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BetaKeyPackageStateError {
    Malformed,
    Poisoned,
    ResourceLimit,
    SuiteMismatch,
    UnsupportedVersion,
}

impl fmt::Display for BetaKeyPackageStateError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Malformed => "malformed beta MLS KeyPackage state",
            Self::Poisoned => "beta MLS KeyPackage state lock poisoned",
            Self::ResourceLimit => "beta MLS KeyPackage state limit exceeded",
            Self::SuiteMismatch => "beta MLS KeyPackage state suite mismatch",
            Self::UnsupportedVersion => "unsupported beta MLS KeyPackage state version",
        })
    }
}

impl Error for BetaKeyPackageStateError {}

impl IntoAnyError for BetaKeyPackageStateError {
    fn into_dyn_error(self) -> Result<Box<dyn Error + Send + Sync>, Self> {
        Ok(Box::new(self))
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BetaMlsStateError {
    Malformed,
    NotFound,
    Poisoned,
    ResourceLimit,
    SuiteMismatch,
    UnsupportedVersion,
}

impl fmt::Display for BetaMlsStateError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Malformed => "malformed beta MLS state",
            Self::NotFound => "beta MLS group state not found",
            Self::Poisoned => "beta MLS state lock poisoned",
            Self::ResourceLimit => "beta MLS state resource limit exceeded",
            Self::SuiteMismatch => "beta MLS state suite mismatch",
            Self::UnsupportedVersion => "unsupported beta MLS state version",
        })
    }
}

impl Error for BetaMlsStateError {}

impl IntoAnyError for BetaMlsStateError {
    fn into_dyn_error(self) -> Result<Box<dyn Error + Send + Sync>, Self> {
        Ok(Box::new(self))
    }
}

const fn map_state_parse(_: crate::error::CryptoError) -> BetaMlsStateError {
    BetaMlsStateError::Malformed
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum BetaKeyPackageKind {
    Consumable = 0,
    LastResort = 1,
}

impl TryFrom<u8> for BetaKeyPackageKind {
    type Error = BetaKeyPackageError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Consumable),
            1 => Ok(Self::LastResort),
            _ => Err(BetaKeyPackageError::Malformed),
        }
    }
}

/// Wrap one already-signed `KeyPackage` without changing its MLS bytes.
pub fn wrap_key_package(
    message: &MlsMessage,
    kind: BetaKeyPackageKind,
    verified_bundle_request: &[u8],
) -> Result<Vec<u8>, BetaKeyPackageError> {
    validate_key_package_kind(message, kind)?;
    validate_bundle_proof(verified_bundle_request)?;
    let exact = message
        .to_bytes()
        .map_err(|_| BetaKeyPackageError::Malformed)?;
    let used = KEY_PACKAGE_WRAPPER_MAGIC
        .len()
        .checked_add(2 + 2 + 1 + 4 + 4)
        .and_then(|header| header.checked_add(exact.len()))
        .and_then(|with_message| with_message.checked_add(verified_bundle_request.len()))
        .ok_or(BetaKeyPackageError::TooLarge)?;
    let bucket = key_package_bucket(used).ok_or(BetaKeyPackageError::TooLarge)?;
    wrap_key_package_in_bucket(message, kind, verified_bundle_request, bucket)
}

pub fn wrap_key_package_in_bucket(
    message: &MlsMessage,
    kind: BetaKeyPackageKind,
    verified_bundle_request: &[u8],
    bucket: usize,
) -> Result<Vec<u8>, BetaKeyPackageError> {
    validate_key_package_kind(message, kind)?;
    validate_bundle_proof(verified_bundle_request)?;
    if !KEY_PACKAGE_BUCKETS.contains(&bucket) {
        return Err(BetaKeyPackageError::WrongBucket);
    }
    let exact = message
        .to_bytes()
        .map_err(|_| BetaKeyPackageError::Malformed)?;
    let used = KEY_PACKAGE_WRAPPER_MAGIC
        .len()
        .checked_add(2 + 2 + 1 + 4 + 4)
        .and_then(|header| header.checked_add(exact.len()))
        .and_then(|with_message| with_message.checked_add(verified_bundle_request.len()))
        .ok_or(BetaKeyPackageError::TooLarge)?;
    if used > bucket {
        return Err(BetaKeyPackageError::TooLarge);
    }
    let mut wrapped = Vec::with_capacity(bucket);
    wrapped.extend_from_slice(KEY_PACKAGE_WRAPPER_MAGIC);
    push_u16(&mut wrapped, KEY_PACKAGE_WRAPPER_VERSION);
    push_u16(&mut wrapped, BETA_CIPHERSUITE_ID);
    wrapped.push(kind as u8);
    push_frame(&mut wrapped, &exact).map_err(|_| BetaKeyPackageError::TooLarge)?;
    push_frame(&mut wrapped, verified_bundle_request).map_err(|_| BetaKeyPackageError::TooLarge)?;
    let unpadded_len = wrapped.len();
    wrapped.resize(bucket, 0);
    getrandom::fill(&mut wrapped[unpadded_len..])
        .map_err(|_| BetaKeyPackageError::EntropyUnavailable)?;
    Ok(wrapped)
}

/// Parse the versioned backend bucket and return the exact signed MLS object.
pub fn unwrap_key_package(
    wrapped: &[u8],
) -> Result<(BetaKeyPackageKind, MlsMessage, Vec<u8>), BetaKeyPackageError> {
    if !KEY_PACKAGE_BUCKETS.contains(&wrapped.len()) {
        return Err(BetaKeyPackageError::WrongBucket);
    }
    let mut reader = Reader::new(wrapped);
    if reader
        .take(KEY_PACKAGE_WRAPPER_MAGIC.len())
        .map_err(|_| BetaKeyPackageError::Malformed)?
        != KEY_PACKAGE_WRAPPER_MAGIC
    {
        return Err(BetaKeyPackageError::Malformed);
    }
    if reader.u16().map_err(|_| BetaKeyPackageError::Malformed)? != KEY_PACKAGE_WRAPPER_VERSION {
        return Err(BetaKeyPackageError::UnsupportedVersion);
    }
    if reader.u16().map_err(|_| BetaKeyPackageError::Malformed)? != BETA_CIPHERSUITE_ID {
        return Err(BetaKeyPackageError::SuiteMismatch);
    }
    let kind =
        BetaKeyPackageKind::try_from(reader.u8().map_err(|_| BetaKeyPackageError::Malformed)?)?;
    let exact = reader
        .framed()
        .map_err(|_| BetaKeyPackageError::Malformed)?;
    let verified_bundle_request = reader
        .framed()
        .map_err(|_| BetaKeyPackageError::Malformed)?;
    if exact.is_empty() {
        return Err(BetaKeyPackageError::Malformed);
    }
    validate_bundle_proof(verified_bundle_request)?;
    let message = MlsMessage::from_bytes(exact).map_err(|_| BetaKeyPackageError::Malformed)?;
    if message
        .to_bytes()
        .map_err(|_| BetaKeyPackageError::Malformed)?
        != exact
    {
        return Err(BetaKeyPackageError::NonCanonical);
    }
    validate_key_package_kind(&message, kind)?;
    Ok((kind, message, verified_bundle_request.to_vec()))
}

fn validate_bundle_proof(value: &[u8]) -> Result<(), BetaKeyPackageError> {
    if value.len() < 8 || value.len() > 16 * 1024 || !value.starts_with(b"CPBRV001") {
        return Err(BetaKeyPackageError::Malformed);
    }
    Ok(())
}

fn validate_key_package_kind(
    message: &MlsMessage,
    kind: BetaKeyPackageKind,
) -> Result<(), BetaKeyPackageError> {
    let key_package = message
        .as_key_package()
        .ok_or(BetaKeyPackageError::NotKeyPackage)?;
    if key_package.cipher_suite() != BETA_CIPHERSUITE {
        return Err(BetaKeyPackageError::SuiteMismatch);
    }
    let marked_last_resort = key_package
        .extensions
        .has_extension(ExtensionType::LAST_RESORT_KEY_PACKAGE);
    if marked_last_resort != (kind == BetaKeyPackageKind::LastResort) {
        return Err(BetaKeyPackageError::KindMismatch);
    }
    Ok(())
}

const fn key_package_bucket(used: usize) -> Option<usize> {
    if used <= KEY_PACKAGE_BUCKETS[0] {
        Some(KEY_PACKAGE_BUCKETS[0])
    } else if used <= KEY_PACKAGE_BUCKETS[1] {
        Some(KEY_PACKAGE_BUCKETS[1])
    } else {
        None
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BetaKeyPackageError {
    EntropyUnavailable,
    KindMismatch,
    Malformed,
    NonCanonical,
    NotKeyPackage,
    SuiteMismatch,
    TooLarge,
    UnsupportedVersion,
    WrongBucket,
}

impl fmt::Display for BetaKeyPackageError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::EntropyUnavailable => "secure randomness unavailable for KeyPackage padding",
            Self::KindMismatch => "KeyPackage last-resort marker mismatch",
            Self::Malformed => "malformed KeyPackage wrapper",
            Self::NonCanonical => "non-canonical KeyPackage encoding",
            Self::NotKeyPackage => "MLS object is not a KeyPackage",
            Self::SuiteMismatch => "KeyPackage suite mismatch",
            Self::TooLarge => "KeyPackage does not fit an allowed backend bucket",
            Self::UnsupportedVersion => "unsupported KeyPackage wrapper version",
            Self::WrongBucket => "KeyPackage wrapper has a disallowed bucket size",
        })
    }
}

impl Error for BetaKeyPackageError {}

fn encode_credential_identifier(
    user_id: [u8; 16],
    device_id: [u8; 16],
    bundle_hash: [u8; 32],
) -> Result<Vec<u8>, AuthenticationServiceError> {
    let mut encoder = Encoder::new(Vec::with_capacity(71));
    encoder
        .array(4)
        .and_then(|encoder| encoder.u8(CREDENTIAL_PROTOCOL_VERSION))
        .and_then(|encoder| encoder.bytes(&user_id))
        .and_then(|encoder| encoder.bytes(&device_id))
        .and_then(|encoder| encoder.bytes(&bundle_hash))
        .map_err(|_| AuthenticationServiceError::MalformedRecord)?;
    Ok(encoder.into_writer())
}

#[cfg(test)]
mod tests {
    use mls_rs::{
        CipherSuiteProvider, Client, CryptoProvider, ExtensionList, GroupStateStorage,
        IdentityProvider, WireFormat,
        client_builder::MlsConfig,
        extension::recommended::LastResortKeyPackageExt,
        group::ReceivedMessage,
        identity::{SigningIdentity, basic::BasicCredential},
        mls_rules::{DefaultMlsRules, EncryptionOptions},
    };
    use mls_rs_core::crypto::{HpkePublicKey, SignaturePublicKey};
    use mls_rs_core::identity::MemberValidationContext;

    use crate::{
        enrollment::{prepare_device_with_provider, prepare_first_identity_with_provider},
        prekey_state::{
            commit_pending_upload, decode_device_state, encode_device_state, prepare_rotation,
        },
        protocol::{Reader, push_frame, push_u16, push_u32, push_u64},
        provider::RustCryptoProvider,
        random::FixedRandomProvider,
    };

    use super::{
        AuthenticatedDevice, AuthenticatedDeviceIdentityProvider, BETA_CIPHERSUITE,
        BETA_CIPHERSUITE_ID, BETA_STATE_MAGIC, BetaKeyPackageError, BetaKeyPackageKind,
        BetaMlsAuthenticationContext, BetaMlsCryptoProvider, BetaMlsStateError,
        KEY_PACKAGE_BUCKETS, OP_COMMIT_PENDING_PROPOSALS, OP_CREATE_GROUP,
        OP_GENERATE_CONSUMABLE_KEY_PACKAGES, OP_GENERATE_LAST_RESORT_KEY_PACKAGE, OP_JOIN_GROUP,
        OP_PROCESS_MESSAGE, OP_PROPOSE_UPDATE, OP_REMOVE_MEMBERS, OP_SEND_APPLICATION,
        OP_SIGN_GROUP_CONTROL, OP_VERIFY_GROUP_CONTROL, OPERATION_REQUEST_MAGIC,
        OPERATION_RESPONSE_MAGIC, OPERATION_VERSION, OpaqueKeyPackageStorage,
        OpaqueMlsStateStorage, SEALED_STATE_MAGIC, SealedStateKind, derive_state_key,
        generate_key_packages, open_secret_snapshot, operation, unwrap_key_package,
        wrap_key_package, wrap_key_package_in_bucket,
    };

    const OPERATION_DAY: u32 = 20_302;
    const OPERATION_USER: [u8; 16] = [0x61; 16];
    const OPERATION_DEVICE: [u8; 16] = [0x71; 16];
    const OPERATION_BOB_USER: [u8; 16] = [0x62; 16];
    const OPERATION_BOB_DEVICE: [u8; 16] = [0x72; 16];

    #[test]
    fn suite_is_private_use_and_has_exact_symmetric_mapping() {
        assert_eq!(BETA_CIPHERSUITE.raw_value(), BETA_CIPHERSUITE_ID);
        assert!((0xF000..=0xFFFF).contains(&BETA_CIPHERSUITE_ID));

        let provider = BetaMlsCryptoProvider;
        assert_eq!(provider.supported_cipher_suites(), [BETA_CIPHERSUITE]);
        assert!(
            provider
                .cipher_suite_provider(mls_rs::CipherSuite::CURVE25519_AES128)
                .is_none()
        );
        let suite = provider
            .cipher_suite_provider(BETA_CIPHERSUITE)
            .expect("beta suite is configured");
        assert_eq!(suite.aead_key_size(), 32);
        assert_eq!(suite.aead_nonce_size(), 12);
        assert_eq!(suite.kdf_extract_size(), 48);
    }

    #[test]
    fn suite_signs_with_ed25519_and_round_trips_hybrid_hpke() {
        let suite = BetaMlsCryptoProvider
            .cipher_suite_provider(BETA_CIPHERSUITE)
            .expect("beta suite is configured");
        let (signature_secret, signature_public) = suite
            .signature_key_generate()
            .expect("Ed25519 key generation succeeds");
        assert_eq!(signature_public.as_ref().len(), 32);
        let signature = suite
            .sign(&signature_secret, b"beta suite self-test")
            .expect("Ed25519 signing succeeds");
        assert_eq!(signature.len(), 64);
        suite
            .verify(
                &SignaturePublicKey::from(signature_public.as_ref().to_vec()),
                &signature,
                b"beta suite self-test",
            )
            .expect("Ed25519 verification succeeds");

        let (hpke_secret, hpke_public) = suite
            .kem_generate()
            .expect("hybrid key generation succeeds");
        assert_eq!(hpke_public.as_ref().len(), 1216);
        let ciphertext = suite
            .hpke_seal(
                &HpkePublicKey::from(hpke_public.as_ref().to_vec()),
                b"beta-hpke-info",
                Some(b"beta-hpke-aad"),
                b"hybrid secret",
            )
            .expect("hybrid HPKE seal succeeds");
        let opened = suite
            .hpke_open(
                &ciphertext,
                &hpke_secret,
                &hpke_public,
                b"beta-hpke-info",
                Some(b"beta-hpke-aad"),
            )
            .expect("hybrid HPKE open succeeds");
        assert_eq!(&*opened, b"hybrid secret");
    }

    #[test]
    fn authentication_service_rejects_unknown_or_substituted_device_keys() {
        let suite = BetaMlsCryptoProvider
            .cipher_suite_provider(BETA_CIPHERSUITE)
            .expect("beta suite is configured");
        let (_, approved_public) = suite
            .signature_key_generate()
            .expect("approved device key generation succeeds");
        let (_, substituted_public) = suite
            .signature_key_generate()
            .expect("substituted device key generation succeeds");
        let approved = AuthenticatedDevice::from_verified_bundle(
            [1; 16],
            [2; 16],
            b"canonical verified bundle",
            approved_public.as_ref(),
        )
        .expect("authenticated record is valid");
        let provider = AuthenticatedDeviceIdentityProvider::new([approved.clone()])
            .expect("authenticated directory is valid");
        let approved_credential = BasicCredential::new(
            approved
                .credential_identifier()
                .expect("credential encoding"),
        );
        let substituted_identity = SigningIdentity::new(
            approved_credential.clone().into_credential(),
            substituted_public,
        );
        assert!(
            provider
                .validate_member(&substituted_identity, None, MemberValidationContext::None)
                .is_err()
        );

        let unknown = AuthenticatedDevice::from_verified_bundle(
            [3; 16],
            [4; 16],
            b"different verified bundle",
            approved_public.as_ref(),
        )
        .expect("unknown record itself is well formed");
        let unknown_identity = SigningIdentity::new(
            BasicCredential::new(
                unknown
                    .credential_identifier()
                    .expect("credential encoding"),
            )
            .into_credential(),
            approved_public,
        );
        assert!(
            provider
                .validate_member(&unknown_identity, None, MemberValidationContext::None)
                .is_err()
        );
    }

    #[test]
    fn consumable_and_last_resort_key_packages_use_exact_backend_buckets() {
        let suite = BetaMlsCryptoProvider
            .cipher_suite_provider(BETA_CIPHERSUITE)
            .expect("beta suite is configured");
        let (secret, public) = suite
            .signature_key_generate()
            .expect("device key generation succeeds");
        let record = AuthenticatedDevice::from_verified_bundle(
            [0xD1; 16],
            [0xD2; 16],
            b"KeyPackage canonical authenticated device bundle",
            public.as_ref(),
        )
        .expect("authenticated record is valid");
        let authentication_service = AuthenticatedDeviceIdentityProvider::new([record.clone()])
            .expect("authenticated device directory is valid");
        let client = make_client(authentication_service, record, secret, public);

        let consumable = client
            .generate_key_package_message(ExtensionList::default(), ExtensionList::default(), None)
            .expect("consumable KeyPackage generation succeeds");
        let mut last_resort_extensions = ExtensionList::new();
        last_resort_extensions
            .set_from(LastResortKeyPackageExt)
            .expect("last-resort extension encoding succeeds");
        let last_resort = client
            .generate_key_package_message(last_resort_extensions, ExtensionList::default(), None)
            .expect("last-resort KeyPackage generation succeeds");

        let bundle_proof = b"CPBRV001";
        let consumable_4096 =
            wrap_key_package(&consumable, BetaKeyPackageKind::Consumable, bundle_proof)
                .expect("consumable KeyPackage wrapping succeeds");
        assert_eq!(consumable_4096.len(), KEY_PACKAGE_BUCKETS[0]);
        let (kind, decoded, decoded_proof) =
            unwrap_key_package(&consumable_4096).expect("consumable wrapper parses");
        assert_eq!(kind, BetaKeyPackageKind::Consumable);
        assert_eq!(decoded_proof, bundle_proof);
        assert_eq!(
            decoded.to_bytes().expect("decoded KeyPackage serializes"),
            consumable.to_bytes().expect("source KeyPackage serializes")
        );

        let last_resort_16k = wrap_key_package_in_bucket(
            &last_resort,
            BetaKeyPackageKind::LastResort,
            bundle_proof,
            KEY_PACKAGE_BUCKETS[1],
        )
        .expect("last-resort 16 KiB wrapping succeeds");
        assert_eq!(last_resort_16k.len(), KEY_PACKAGE_BUCKETS[1]);
        let (kind, decoded, decoded_proof) =
            unwrap_key_package(&last_resort_16k).expect("last-resort wrapper parses");
        assert_eq!(kind, BetaKeyPackageKind::LastResort);
        assert_eq!(decoded_proof, bundle_proof);
        assert_eq!(
            decoded.to_bytes().expect("decoded KeyPackage serializes"),
            last_resort
                .to_bytes()
                .expect("source KeyPackage serializes")
        );

        assert_eq!(
            wrap_key_package(&last_resort, BetaKeyPackageKind::Consumable, bundle_proof,)
                .expect_err("last-resort marker cannot enter consumable inventory"),
            BetaKeyPackageError::KindMismatch
        );
        let mut off_bucket = consumable_4096;
        off_bucket.pop();
        assert_eq!(
            unwrap_key_package(&off_bucket).expect_err("off-bucket wrapper must fail"),
            BetaKeyPackageError::WrongBucket
        );
    }

    #[test]
    #[allow(clippy::too_many_lines)] // One restart test contrasts consumable deletion with last-resort retention end to end.
    fn key_package_secrets_survive_restart_and_consumable_deletion_differs_from_last_resort() {
        let suite = BetaMlsCryptoProvider
            .cipher_suite_provider(BETA_CIPHERSUITE)
            .expect("beta suite is configured");
        let (alice_secret, alice_public) = suite
            .signature_key_generate()
            .expect("Alice key generation succeeds");
        let (bob_secret, bob_public) = suite
            .signature_key_generate()
            .expect("Bob key generation succeeds");
        let alice_record = AuthenticatedDevice::from_verified_bundle(
            [0xE1; 16],
            [0xE2; 16],
            b"Alice restart-test authenticated device bundle",
            alice_public.as_ref(),
        )
        .expect("Alice authenticated record is valid");
        let bob_record = AuthenticatedDevice::from_verified_bundle(
            [0xF1; 16],
            [0xF2; 16],
            b"Bob restart-test authenticated device bundle",
            bob_public.as_ref(),
        )
        .expect("Bob authenticated record is valid");
        let authentication_service =
            AuthenticatedDeviceIdentityProvider::new([alice_record.clone(), bob_record.clone()])
                .expect("authenticated directory is valid");
        let alice = make_client(
            authentication_service.clone(),
            alice_record,
            alice_secret,
            alice_public,
        );

        let initial_key_store = OpaqueKeyPackageStorage::default();
        let bob_before_restart = make_client_with_stores(
            authentication_service.clone(),
            bob_record.clone(),
            bob_secret.clone(),
            bob_public.clone(),
            OpaqueMlsStateStorage::default(),
            initial_key_store.clone(),
        );
        let consumable = bob_before_restart
            .generate_key_package_message(ExtensionList::default(), ExtensionList::default(), None)
            .expect("consumable KeyPackage generation succeeds");
        assert_eq!(initial_key_store.len().expect("key store read"), 1);
        let persisted = initial_key_store
            .export_snapshot()
            .expect("KeyPackage secret snapshot export succeeds");
        let restored_consumable_store = OpaqueKeyPackageStorage::import_snapshot(&persisted)
            .expect("KeyPackage secret snapshot import succeeds");
        let bob_after_restart = make_client_with_stores(
            authentication_service.clone(),
            bob_record.clone(),
            bob_secret.clone(),
            bob_public.clone(),
            OpaqueMlsStateStorage::default(),
            restored_consumable_store.clone(),
        );

        let mut consumable_group = alice
            .create_group(ExtensionList::new(), ExtensionList::default(), None)
            .expect("first group creation succeeds");
        let consumable_commit = consumable_group
            .commit_builder()
            .add_member(consumable)
            .expect("consumable KeyPackage is accepted")
            .build()
            .expect("consumable add Commit succeeds");
        let (mut joined_consumable, _) = bob_after_restart
            .join_group(None, &consumable_commit.welcome_messages[0], None)
            .expect("restored consumable secret decrypts Welcome");
        joined_consumable
            .write_to_storage()
            .expect("consumable join state persists");
        assert!(
            restored_consumable_store
                .is_empty()
                .expect("key store read"),
            "a used consumable KeyPackage must be securely removed"
        );

        let mut last_resort_extensions = ExtensionList::new();
        last_resort_extensions
            .set_from(LastResortKeyPackageExt)
            .expect("last-resort extension encoding succeeds");
        let last_resort = bob_after_restart
            .generate_key_package_message(last_resort_extensions, ExtensionList::default(), None)
            .expect("last-resort KeyPackage generation succeeds");
        let last_resort_snapshot = restored_consumable_store
            .export_snapshot()
            .expect("last-resort secret snapshot export succeeds");
        let restored_last_resort_store =
            OpaqueKeyPackageStorage::import_snapshot(&last_resort_snapshot)
                .expect("last-resort secret snapshot import succeeds");
        let bob_second_restart = make_client_with_stores(
            authentication_service,
            bob_record,
            bob_secret,
            bob_public,
            OpaqueMlsStateStorage::default(),
            restored_last_resort_store.clone(),
        );
        let mut fallback_group = alice
            .create_group(ExtensionList::new(), ExtensionList::default(), None)
            .expect("fallback group creation succeeds");
        let fallback_commit = fallback_group
            .commit_builder()
            .add_member(last_resort)
            .expect("last-resort KeyPackage is accepted")
            .build()
            .expect("last-resort add Commit succeeds");
        let (mut joined_fallback, _) = bob_second_restart
            .join_group(None, &fallback_commit.welcome_messages[0], None)
            .expect("restored last-resort secret decrypts Welcome");
        joined_fallback
            .write_to_storage()
            .expect("last-resort join state persists");
        assert_eq!(
            restored_last_resort_store.len().expect("key store read"),
            1,
            "the standardized last-resort secret remains reusable"
        );
    }

    #[test]
    #[allow(clippy::too_many_lines)] // The ABI test proves sealed KeyPackage continuity across multiple independent calls.
    fn operation_binds_enrolled_device_and_preserves_key_package_state_across_calls() {
        let device_provider = fixed_provider(7, 100_000);
        let device_v1 = prepare_device_with_provider(&device_provider, &OPERATION_USER)
            .expect("device preparation succeeds");
        let identity =
            prepare_first_identity_with_provider(&fixed_provider(19, 20_000), &OPERATION_USER)
                .expect("identity preparation succeeds");
        let provider = fixed_provider(31, 100_000);
        let mut state = decode_device_state(&provider, &device_v1, OPERATION_DAY)
            .expect("legacy device state decodes for explicit migration");
        prepare_rotation(
            &provider,
            &mut state,
            &identity,
            OPERATION_DEVICE,
            OPERATION_DAY,
        )
        .expect("rotation binds the device to the account self-signing key");
        let device_state = encode_device_state(&state).expect("device state encoding succeeds");
        let local_bundle = claimed_bundle_request(&state, &identity, OPERATION_DEVICE);

        let authentication = BetaMlsAuthenticationContext::from_verified_bundle_requests(
            &device_state,
            OPERATION_DAY,
            &local_bundle,
            &[],
        )
        .expect("the native enrollment state authenticates its exact claimed bundle");
        authentication
            .client(
                OpaqueMlsStateStorage::default(),
                OpaqueKeyPackageStorage::default(),
            )
            .generate_key_package_message(ExtensionList::default(), ExtensionList::default(), None)
            .expect("the enrolled device signer creates a valid KeyPackage");
        let direct =
            generate_key_packages(&authentication, None, 1, BetaKeyPackageKind::Consumable)
                .expect("direct authenticated KeyPackage generation succeeds");
        assert_eq!(direct.wrapped_key_packages.len(), 1);

        let first_request = operation_request(&device_state, &local_bundle, None, 2);
        let first_response = operation(OP_GENERATE_CONSUMABLE_KEY_PACKAGES, &first_request)
            .expect("authenticated consumable KeyPackages are generated");
        let (first_store, first_packages) =
            decode_operation_response(OP_GENERATE_CONSUMABLE_KEY_PACKAGES, &first_response);
        assert_eq!(first_packages.len(), 2);
        assert!(first_packages.iter().all(|package| {
            unwrap_key_package(package)
                .is_ok_and(|(kind, _, _)| kind == BetaKeyPackageKind::Consumable)
        }));
        assert!(first_store.starts_with(SEALED_STATE_MAGIC));
        assert!(
            !first_store
                .windows(super::KEY_PACKAGE_STORE_MAGIC.len())
                .any(|window| window == super::KEY_PACKAGE_STORE_MAGIC)
        );
        let state_key =
            derive_state_key(&RustCryptoProvider::default(), &device_state, OPERATION_DAY)
                .expect("device-bound state key derives");
        let first_plaintext = open_secret_snapshot(
            &RustCryptoProvider::default(),
            &state_key,
            SealedStateKind::KeyPackages,
            &authentication
                .state_binding_identifier()
                .expect("stable state binding derives"),
            &first_store,
        )
        .expect("first private state authenticates and decrypts only in Rust");
        assert_eq!(
            OpaqueKeyPackageStorage::import_snapshot(first_plaintext.expose())
                .expect("first private state imports")
                .len()
                .expect("first private state reads"),
            2
        );

        let second_request = operation_request(&device_state, &local_bundle, Some(&first_store), 1);
        let second_response = operation(OP_GENERATE_LAST_RESORT_KEY_PACKAGE, &second_request)
            .expect("authenticated last-resort KeyPackage is generated");
        let (second_store, second_packages) =
            decode_operation_response(OP_GENERATE_LAST_RESORT_KEY_PACKAGE, &second_response);
        assert_eq!(second_packages.len(), 1);
        assert!(
            unwrap_key_package(&second_packages[0])
                .is_ok_and(|(kind, _, _)| { kind == BetaKeyPackageKind::LastResort })
        );
        let second_plaintext = open_secret_snapshot(
            &RustCryptoProvider::default(),
            &state_key,
            SealedStateKind::KeyPackages,
            &authentication
                .state_binding_identifier()
                .expect("stable state binding derives"),
            &second_store,
        )
        .expect("combined private state authenticates and decrypts only in Rust");
        assert_eq!(
            OpaqueKeyPackageStorage::import_snapshot(second_plaintext.expose())
                .expect("combined private state imports")
                .len()
                .expect("combined private state reads"),
            3
        );

        let mut tampered_store = first_store.clone();
        *tampered_store
            .last_mut()
            .expect("sealed state is non-empty") ^= 1;
        let tampered_request =
            operation_request(&device_state, &local_bundle, Some(&tampered_store), 1);
        assert!(operation(OP_GENERATE_CONSUMABLE_KEY_PACKAGES, &tampered_request).is_err());

        let mut substituted_bundle = local_bundle;
        substituted_bundle[8 + 16 + 16 + 32] ^= 1;
        let rejected = operation_request(&device_state, &substituted_bundle, None, 1);
        assert!(operation(OP_GENERATE_CONSUMABLE_KEY_PACKAGES, &rejected).is_err());
    }

    #[test]
    #[allow(clippy::too_many_lines)] // The single lifecycle test preserves the exact create-to-remove transcript for auditability.
    fn operation_round_trips_create_join_private_message_proposal_commit_and_remove() {
        let (alice_state, alice_bundle, rotated_alice_state, rotated_alice_bundle) =
            enrolled_operation_device_with_rotation(OPERATION_USER, OPERATION_DEVICE, 41);
        let (bob_state, bob_bundle) =
            enrolled_operation_device(OPERATION_BOB_USER, OPERATION_BOB_DEVICE, 83);

        let mut bob_key_package_request = operation_prefix(&bob_state, &bob_bundle, &[]);
        bob_key_package_request.push(0);
        push_u16(&mut bob_key_package_request, 1);
        let bob_key_package_response = operation(
            OP_GENERATE_CONSUMABLE_KEY_PACKAGES,
            &bob_key_package_request,
        )
        .expect("Bob generates a restart-safe consumable KeyPackage");
        let (bob_key_package_state, bob_key_packages) = decode_operation_response(
            OP_GENERATE_CONSUMABLE_KEY_PACKAGES,
            &bob_key_package_response,
        );

        let mut create = operation_prefix(&alice_state, &alice_bundle, &[&bob_bundle]);
        push_u16(&mut create, 1);
        push_frame(&mut create, &bob_key_packages[0]).expect("Bob KeyPackage frame");
        push_frame(&mut create, b"create-control-binding").expect("create binding frame");
        let created = operation(OP_CREATE_GROUP, &create).expect("Alice creates the MLS group");
        let create_output = decode_commit_response(OP_CREATE_GROUP, &created);
        assert_eq!(create_output.epoch, 1);
        assert_eq!(create_output.group_id.len(), 32);
        assert_eq!(create_output.welcomes.len(), 1);
        assert!(!create_output.group_info.is_empty());
        assert!(create_output.sealed_state.starts_with(SEALED_STATE_MAGIC));
        assert!(
            !create_output
                .sealed_state
                .windows(BETA_STATE_MAGIC.len())
                .any(|window| window == BETA_STATE_MAGIC)
        );

        let join_proofs: Vec<&[u8]> = create_output
            .authentication_proofs
            .iter()
            .map(Vec::as_slice)
            .collect();
        let mut join = operation_prefix(&bob_state, &bob_bundle, &join_proofs);
        push_frame(&mut join, &bob_key_package_state).expect("Bob KeyPackage state frame");
        push_frame(&mut join, &create_output.welcomes[0]).expect("Welcome frame");
        let joined = operation(OP_JOIN_GROUP, &join).expect("Bob authenticates and joins");
        let join_output = decode_join_response(&joined);
        assert_eq!(join_output.group_id, create_output.group_id);
        assert_eq!(join_output.epoch, create_output.epoch);
        assert_eq!(join_output.roster.len(), 2);
        assert!(
            join_output
                .roster
                .contains(&(OPERATION_USER.to_vec(), OPERATION_DEVICE.to_vec()))
        );
        assert!(
            join_output
                .roster
                .contains(&(OPERATION_BOB_USER.to_vec(), OPERATION_BOB_DEVICE.to_vec()))
        );
        assert_eq!(join_output.confirmation, create_output.confirmation);

        let mut send_request = operation_prefix(&rotated_alice_state, &rotated_alice_bundle, &[]);
        push_frame(&mut send_request, &create_output.sealed_state)
            .expect("Alice group state frame");
        push_frame(&mut send_request, b"real operation-level private message")
            .expect("application frame");
        push_frame(&mut send_request, b"event-binding").expect("application AAD frame");
        let sent_application =
            operation(OP_SEND_APPLICATION, &send_request).expect("Alice encrypts application data");
        let sent_output = decode_message_response(OP_SEND_APPLICATION, &sent_application);
        assert_eq!(sent_output.epoch, 1);

        let mut receive = operation_prefix(&bob_state, &bob_bundle, &[]);
        push_frame(&mut receive, &join_output.sealed_group_state).expect("Bob group state frame");
        push_frame(&mut receive, &sent_output.message).expect("PrivateMessage frame");
        let received = operation(OP_PROCESS_MESSAGE, &receive)
            .expect("Bob authenticates and decrypts application data");
        let received_output = decode_processed_response(&received);
        assert_eq!(received_output.kind, 1);
        assert_eq!(received_output.sender_user_id, OPERATION_USER);
        assert_eq!(received_output.sender_device_id, OPERATION_DEVICE);
        assert_eq!(
            received_output.data,
            b"real operation-level private message"
        );
        assert_eq!(received_output.authenticated_data, b"event-binding");
        assert_eq!(received_output.confirmation, sent_output.confirmation);

        let mut propose = operation_prefix(&bob_state, &bob_bundle, &[]);
        push_frame(&mut propose, &received_output.sealed_state).expect("Bob group state frame");
        push_frame(&mut propose, b"canonical-reproposal-binding").expect("proposal AAD frame");
        let proposed = operation(OP_PROPOSE_UPDATE, &propose)
            .expect("Bob creates an encrypted update Proposal");
        let proposal_output = decode_message_response(OP_PROPOSE_UPDATE, &proposed);
        assert_eq!(proposal_output.epoch, 1);

        let mut inspect_proposal =
            operation_prefix(&rotated_alice_state, &rotated_alice_bundle, &[]);
        push_frame(&mut inspect_proposal, &sent_output.sealed_state)
            .expect("Alice group state frame");
        push_frame(&mut inspect_proposal, &proposal_output.message).expect("Proposal frame");
        let inspected_proposal = operation(OP_PROCESS_MESSAGE, &inspect_proposal)
            .expect("Alice authenticates Bob's Proposal");
        let proposal_inspection = decode_processed_response(&inspected_proposal);
        assert_eq!(proposal_inspection.kind, 3);
        assert_eq!(
            proposal_inspection.authenticated_data,
            b"canonical-reproposal-binding"
        );

        let mut commit = operation_prefix(&rotated_alice_state, &rotated_alice_bundle, &[]);
        push_frame(&mut commit, &proposal_inspection.sealed_state)
            .expect("Alice proposal state frame");
        push_frame(&mut commit, b"accepted-reproposal-binding").expect("commit AAD frame");
        let committed = operation(OP_COMMIT_PENDING_PROPOSALS, &commit)
            .expect("Alice commits the pending Proposal");
        let commit_output = decode_commit_response(OP_COMMIT_PENDING_PROPOSALS, &committed);
        assert_eq!(commit_output.epoch, 2);

        let mut receive_commit_request = operation_prefix(&bob_state, &bob_bundle, &[]);
        push_frame(&mut receive_commit_request, &proposal_output.sealed_state)
            .expect("Bob proposal state frame");
        push_frame(&mut receive_commit_request, &commit_output.commit).expect("Commit frame");
        let processed_commit = operation(OP_PROCESS_MESSAGE, &receive_commit_request)
            .expect("Bob authenticates the Commit");
        let received_commit_output = decode_processed_response(&processed_commit);
        assert_eq!(received_commit_output.kind, 2);
        assert_eq!(received_commit_output.message_digest.len(), 32);
        assert_eq!(received_commit_output.epoch, 2);
        assert_eq!(
            received_commit_output.confirmation,
            commit_output.confirmation
        );

        let mut remove = operation_prefix(&rotated_alice_state, &rotated_alice_bundle, &[]);
        push_frame(&mut remove, &commit_output.sealed_state).expect("Alice group state frame");
        push_u16(&mut remove, 1);
        push_frame(&mut remove, &OPERATION_BOB_USER).expect("removed user frame");
        push_frame(&mut remove, b"queue-gap-remove-binding").expect("remove AAD frame");
        let removed = operation(OP_REMOVE_MEMBERS, &remove)
            .expect("Alice removes every leaf authenticated to Bob's user");
        let remove_output = decode_commit_response(OP_REMOVE_MEMBERS, &removed);
        assert_eq!(remove_output.epoch, 3);

        let mut receive_remove = operation_prefix(&bob_state, &bob_bundle, &[]);
        push_frame(&mut receive_remove, &received_commit_output.sealed_state)
            .expect("Bob current state frame");
        push_frame(&mut receive_remove, &remove_output.commit).expect("remove Commit frame");
        let processed_remove = operation(OP_PROCESS_MESSAGE, &receive_remove)
            .expect("Bob authenticates his removal Commit");
        let processed_remove_output = decode_processed_response(&processed_remove);
        assert_eq!(processed_remove_output.kind, 2);
        // A removed client authenticates the epoch-advancing Commit but retains
        // only its prior usable epoch state; application policy marks it removed.
        assert_eq!(processed_remove_output.epoch, 2);
    }

    #[test]
    fn native_group_controls_are_deterministic_signed_and_tamper_evident() {
        let (device_state, local_bundle) =
            enrolled_operation_device(OPERATION_USER, OPERATION_DEVICE, 157);
        let first_request = group_control_sign_request(
            &device_state,
            &local_bundle,
            [
                (OPERATION_USER, OPERATION_DEVICE),
                (OPERATION_BOB_USER, OPERATION_BOB_DEVICE),
            ],
        );
        let second_request = group_control_sign_request(
            &device_state,
            &local_bundle,
            [
                (OPERATION_BOB_USER, OPERATION_BOB_DEVICE),
                (OPERATION_USER, OPERATION_DEVICE),
            ],
        );
        let first = operation(OP_SIGN_GROUP_CONTROL, &first_request)
            .expect("native group control signing succeeds");
        let second = operation(OP_SIGN_GROUP_CONTROL, &second_request)
            .expect("member input order cannot affect a canonical control");
        let (canonical, signature, state_hash, payload, signer_user, signer_device) =
            decode_group_control_response(OP_SIGN_GROUP_CONTROL, &first);
        let (second_canonical, second_signature, second_hash, _, _, _) =
            decode_group_control_response(OP_SIGN_GROUP_CONTROL, &second);
        assert_eq!(canonical, second_canonical);
        assert_eq!(signature, second_signature);
        assert_eq!(state_hash, second_hash);
        assert_eq!(signer_user, OPERATION_USER);
        assert_eq!(signer_device, OPERATION_DEVICE);

        let mut verify_request = operation_prefix(&device_state, &local_bundle, &[]);
        push_frame(&mut verify_request, &signer_user).expect("signer user frame");
        push_frame(&mut verify_request, &signer_device).expect("signer device frame");
        push_group_control_descriptor(
            &mut verify_request,
            [
                (OPERATION_BOB_USER, OPERATION_BOB_DEVICE),
                (OPERATION_USER, OPERATION_DEVICE),
            ],
        );
        push_frame(&mut verify_request, &payload).expect("signed control payload frame");
        let verified = operation(OP_VERIFY_GROUP_CONTROL, &verify_request)
            .expect("the authenticated signer verifies");
        let (verified_canonical, verified_signature, verified_hash, _, _, _) =
            decode_group_control_response(OP_VERIFY_GROUP_CONTROL, &verified);
        assert_eq!(verified_canonical, canonical);
        assert_eq!(verified_signature, signature);
        assert_eq!(verified_hash, state_hash);

        let mut tampered_payload = payload;
        let last = tampered_payload
            .last_mut()
            .expect("the signed payload is non-empty");
        *last ^= 1;
        let mut tampered_request = operation_prefix(&device_state, &local_bundle, &[]);
        push_frame(&mut tampered_request, &signer_user).expect("signer user frame");
        push_frame(&mut tampered_request, &signer_device).expect("signer device frame");
        push_group_control_descriptor(
            &mut tampered_request,
            [
                (OPERATION_USER, OPERATION_DEVICE),
                (OPERATION_BOB_USER, OPERATION_BOB_DEVICE),
            ],
        );
        push_frame(&mut tampered_request, &tampered_payload).expect("tampered payload frame");
        assert!(operation(OP_VERIFY_GROUP_CONTROL, &tampered_request).is_err());
    }

    #[test]
    #[allow(clippy::too_many_lines)] // This interoperable lifecycle test deliberately keeps both member views adjacent.
    fn authenticated_suite_runs_key_package_welcome_proposal_commit_private_message_and_exporter() {
        let suite = BetaMlsCryptoProvider
            .cipher_suite_provider(BETA_CIPHERSUITE)
            .expect("beta suite is configured");
        let (alice_secret, alice_public) = suite
            .signature_key_generate()
            .expect("Alice key generation succeeds");
        let (bob_secret, bob_public) = suite
            .signature_key_generate()
            .expect("Bob key generation succeeds");
        let alice_record = AuthenticatedDevice::from_verified_bundle(
            [0xA1; 16],
            [0xA2; 16],
            b"Alice canonical authenticated device bundle",
            alice_public.as_ref(),
        )
        .expect("Alice authenticated record is valid");
        let bob_record = AuthenticatedDevice::from_verified_bundle(
            [0xB1; 16],
            [0xB2; 16],
            b"Bob canonical authenticated device bundle",
            bob_public.as_ref(),
        )
        .expect("Bob authenticated record is valid");
        let authentication_service =
            AuthenticatedDeviceIdentityProvider::new([alice_record.clone(), bob_record.clone()])
                .expect("authenticated device directory is valid");

        let alice = make_client(
            authentication_service.clone(),
            alice_record,
            alice_secret,
            alice_public,
        );
        let bob = make_client(authentication_service, bob_record, bob_secret, bob_public);
        let mut alice_group = alice
            .create_group(ExtensionList::new(), ExtensionList::default(), None)
            .expect("Alice creates the group");
        let group_info = alice_group
            .group_info_message(true)
            .expect("GroupInfo generation succeeds");
        assert_eq!(group_info.wire_format(), WireFormat::GroupInfo);

        let bob_key_package = bob
            .generate_key_package_message(ExtensionList::default(), ExtensionList::default(), None)
            .expect("Bob creates an authenticated KeyPackage");
        assert_eq!(bob_key_package.wire_format(), WireFormat::KeyPackage);
        let add_commit = alice_group
            .commit_builder()
            .add_member(bob_key_package)
            .expect("Bob KeyPackage is accepted")
            .build()
            .expect("add Commit generation succeeds");
        assert_eq!(
            add_commit.commit_message.wire_format(),
            WireFormat::PrivateMessage
        );
        assert_eq!(add_commit.welcome_messages.len(), 1);
        assert_eq!(
            add_commit.welcome_messages[0].wire_format(),
            WireFormat::Welcome
        );
        alice_group
            .apply_pending_commit()
            .expect("Alice atomically accepts her add Commit");
        let (mut bob_group, _) = bob
            .join_group(None, &add_commit.welcome_messages[0], None)
            .expect("Bob authenticates the Welcome and joins");
        assert_eq!(alice_group.current_epoch(), 1);
        assert_eq!(bob_group.current_epoch(), 1);

        let proposal = bob_group
            .propose_update(b"beta control event".to_vec())
            .expect("Bob creates an encrypted update Proposal");
        assert_eq!(proposal.wire_format(), WireFormat::PrivateMessage);
        alice_group
            .process_incoming_message(proposal)
            .expect("Alice authenticates Bob's Proposal");
        let update_commit = alice_group
            .commit(b"accepted beta control event".to_vec())
            .expect("Alice commits Bob's Proposal");
        assert_eq!(
            update_commit.commit_message.wire_format(),
            WireFormat::PrivateMessage
        );
        bob_group
            .process_incoming_message(update_commit.commit_message.clone())
            .expect("Bob authenticates the Commit");
        alice_group
            .apply_pending_commit()
            .expect("Alice applies the accepted Commit");

        let alice_export = alice_group
            .export_secret(b"chat:v1:beta-group-export", b"control", 32)
            .expect("Alice exporter succeeds");
        let bob_export = bob_group
            .export_secret(b"chat:v1:beta-group-export", b"control", 32)
            .expect("Bob exporter succeeds");
        assert_eq!(alice_export.as_ref(), bob_export.as_ref());

        let message = alice_group
            .encrypt_application_message(b"real beta MLS message", b"event-id".to_vec())
            .expect("Alice encrypts an MLS PrivateMessage");
        assert_eq!(message.wire_format(), WireFormat::PrivateMessage);
        let received = bob_group
            .process_incoming_message(message)
            .expect("Bob authenticates and decrypts the application message");
        let ReceivedMessage::ApplicationMessage(received) = received else {
            panic!("expected an application message");
        };
        assert_eq!(received.data(), b"real beta MLS message");

        let remove_commit = alice_group
            .commit_builder()
            .remove_member(bob_group.current_member_index())
            .expect("Bob leaf is present")
            .build()
            .expect("remove Commit generation succeeds");
        bob_group
            .process_incoming_message(remove_commit.commit_message.clone())
            .expect("Bob processes his authenticated removal");
        alice_group
            .apply_pending_commit()
            .expect("Alice applies the accepted removal");
        assert_eq!(alice_group.current_epoch(), 3);
    }

    #[test]
    fn opaque_state_round_trips_current_and_prior_epoch_and_rejects_unknown_version() {
        let suite = BetaMlsCryptoProvider
            .cipher_suite_provider(BETA_CIPHERSUITE)
            .expect("beta suite is configured");
        let (secret, public) = suite
            .signature_key_generate()
            .expect("device key generation succeeds");
        let record = AuthenticatedDevice::from_verified_bundle(
            [0xC1; 16],
            [0xC2; 16],
            b"persisted canonical authenticated device bundle",
            public.as_ref(),
        )
        .expect("authenticated record is valid");
        let authentication_service = AuthenticatedDeviceIdentityProvider::new([record.clone()])
            .expect("authenticated device directory is valid");
        let storage = OpaqueMlsStateStorage::default();
        let client = make_client_with_storage(
            authentication_service.clone(),
            record.clone(),
            secret.clone(),
            public.clone(),
            storage.clone(),
        );
        let mut group = client
            .create_group(ExtensionList::new(), ExtensionList::default(), None)
            .expect("group creation succeeds");
        let group_id = group.group_id().to_vec();
        group
            .commit(Vec::new())
            .expect("path-update Commit succeeds");
        group
            .apply_pending_commit()
            .expect("path-update Commit is accepted");
        group
            .write_to_storage()
            .expect("current and prior epoch state persist atomically");
        assert_eq!(
            storage.max_epoch_id(&group_id).expect("storage read"),
            Some(0)
        );

        let snapshot = storage
            .export_snapshot(&group_id)
            .expect("opaque snapshot export succeeds");
        let mut unknown_version = snapshot.to_vec();
        unknown_version[9] = 2;
        assert_eq!(
            OpaqueMlsStateStorage::import_snapshot(&unknown_version)
                .expect_err("version must fail"),
            BetaMlsStateError::UnsupportedVersion
        );

        let (restored_storage, restored_group_id) =
            OpaqueMlsStateStorage::import_snapshot(&snapshot)
                .expect("opaque snapshot import succeeds");
        assert_eq!(restored_group_id, group_id);
        assert_eq!(
            restored_storage
                .max_epoch_id(&restored_group_id)
                .expect("restored epoch read"),
            Some(0)
        );
        let restored_client = make_client_with_storage(
            authentication_service,
            record,
            secret,
            public,
            restored_storage,
        );
        let restored_group = restored_client
            .load_group(&restored_group_id)
            .expect("restored MLS group loads");
        assert_eq!(restored_group.current_epoch(), 1);
        assert_eq!(restored_group.cipher_suite(), BETA_CIPHERSUITE);
    }

    fn make_client(
        authentication_service: AuthenticatedDeviceIdentityProvider,
        record: AuthenticatedDevice,
        signer: mls_rs_core::crypto::SignatureSecretKey,
        signature_public: SignaturePublicKey,
    ) -> Client<impl MlsConfig> {
        make_client_with_storage(
            authentication_service,
            record,
            signer,
            signature_public,
            OpaqueMlsStateStorage::default(),
        )
    }

    fn fixed_provider(seed: u8, length: usize) -> RustCryptoProvider<FixedRandomProvider> {
        let bytes = (0..length)
            .map(|index| {
                seed.wrapping_add(
                    u8::try_from(index % 251)
                        .expect("modulo is byte sized")
                        .wrapping_mul(17),
                )
            })
            .collect();
        RustCryptoProvider::new(FixedRandomProvider::new(bytes))
    }

    fn claimed_bundle_request(
        state: &crate::prekey_state::DeviceState,
        identity: &[u8],
        device_id: [u8; 16],
    ) -> Vec<u8> {
        let mut identity_reader = Reader::new(identity);
        identity_reader.expect(b"CPIDV001").expect("identity magic");
        identity_reader.u8().expect("identity flags");
        identity_reader.take(16).expect("identity user id");
        identity_reader.take(32).expect("account master public key");
        let self_signing_public: [u8; 32] = identity_reader
            .array()
            .expect("account self-signing public key");

        let mut output = Vec::new();
        output.extend_from_slice(b"CPBRV001");
        output.extend_from_slice(&state.user_id);
        output.extend_from_slice(&device_id);
        output.extend_from_slice(&self_signing_public);
        output.extend_from_slice(state.ik_public().as_bytes());
        push_u32(&mut output, state.current_classical.id);
        push_frame(&mut output, &state.current_classical.public).expect("classical frame");
        output.extend_from_slice(&state.current_classical.signature);
        output.push(1);
        push_u32(&mut output, state.current_pq.id);
        push_frame(&mut output, &state.current_pq.public).expect("PQ frame");
        output.extend_from_slice(&state.current_pq.signature);
        push_u32(&mut output, state.registration_id);
        push_u32(&mut output, state.bundle_version);
        output.extend_from_slice(&state.cross_signature);
        output
    }

    fn operation_request(
        device_state: &[u8],
        local_bundle: &[u8],
        prior_key_package_state: Option<&[u8]>,
        count: u16,
    ) -> Vec<u8> {
        let mut output = operation_prefix(device_state, local_bundle, &[]);
        match prior_key_package_state {
            Some(state) => {
                output.push(1);
                push_frame(&mut output, state).expect("KeyPackage state frame");
            }
            None => output.push(0),
        }
        push_u16(&mut output, count);
        output
    }

    fn operation_prefix(
        device_state: &[u8],
        local_bundle: &[u8],
        additional_bundles: &[&[u8]],
    ) -> Vec<u8> {
        let mut output = Vec::new();
        output.extend_from_slice(OPERATION_REQUEST_MAGIC);
        push_u16(&mut output, OPERATION_VERSION);
        push_frame(&mut output, device_state).expect("device state frame");
        push_u32(&mut output, OPERATION_DAY);
        push_frame(&mut output, local_bundle).expect("local bundle frame");
        push_u16(
            &mut output,
            u16::try_from(additional_bundles.len()).expect("bundle count is bounded"),
        );
        for bundle in additional_bundles {
            push_frame(&mut output, bundle).expect("additional bundle frame");
        }
        output
    }

    fn group_control_sign_request(
        device_state: &[u8],
        local_bundle: &[u8],
        members: [([u8; 16], [u8; 16]); 2],
    ) -> Vec<u8> {
        let mut request = operation_prefix(device_state, local_bundle, &[]);
        push_group_control_descriptor(&mut request, members);
        request
    }

    /// A leave is signed at the current epoch and carries no Commit, because
    /// RFC 9420 section 12.4 forbids a Commit that removes its own committer.
    /// A leave that claims a Commit hash is malformed and must be refused.
    #[test]
    fn leave_controls_are_signed_without_a_commit_and_reject_a_claimed_commit() {
        let (device_state, local_bundle) =
            enrolled_operation_device(OPERATION_USER, OPERATION_DEVICE, 163);

        let mut request = operation_prefix(&device_state, &local_bundle, &[]);
        push_leave_control_descriptor(&mut request, false);
        let signed = operation(OP_SIGN_GROUP_CONTROL, &request)
            .expect("a departing member signs a leave without a Commit");
        let (canonical, signature, state_hash, payload, signer_user, signer_device) =
            decode_group_control_response(OP_SIGN_GROUP_CONTROL, &signed);
        assert!(!canonical.is_empty());
        assert!(!signature.is_empty());
        assert_eq!(state_hash.len(), 32);
        assert_eq!(signer_user, OPERATION_USER);
        assert_eq!(signer_device, OPERATION_DEVICE);

        let mut verify_request = operation_prefix(&device_state, &local_bundle, &[]);
        push_frame(&mut verify_request, &signer_user).expect("signer user frame");
        push_frame(&mut verify_request, &signer_device).expect("signer device frame");
        push_leave_control_descriptor(&mut verify_request, false);
        push_frame(&mut verify_request, &payload).expect("signed control payload frame");
        let verified = operation(OP_VERIFY_GROUP_CONTROL, &verify_request)
            .expect("a remaining member verifies the leave");
        let (verified_canonical, verified_signature, verified_hash, ..) =
            decode_group_control_response(OP_VERIFY_GROUP_CONTROL, &verified);
        assert_eq!(verified_canonical, canonical);
        assert_eq!(verified_signature, signature);
        assert_eq!(verified_hash, state_hash);

        let mut claimed_commit = operation_prefix(&device_state, &local_bundle, &[]);
        push_leave_control_descriptor(&mut claimed_commit, true);
        assert_eq!(
            operation(OP_SIGN_GROUP_CONTROL, &claimed_commit),
            Err(crate::error::CryptoError::MalformedInput),
            "a leave may never carry a Commit hash"
        );
    }

    fn push_leave_control_descriptor(request: &mut Vec<u8>, claim_commit: bool) {
        push_frame(request, &[0xA2; 16]).expect("event id frame");
        push_frame(request, &[0xB2; 32]).expect("group id frame");
        push_u32(request, 2);
        request.push(1);
        push_frame(request, &[0xD4; 32]).expect("previous control state hash frame");
        push_u64(request, 1);
        if claim_commit {
            request.push(1);
            push_frame(request, &[0xC3; 32]).expect("Commit hash frame");
        } else {
            request.push(0);
        }
        push_u64(request, 1_700_000_000_000);
        request.push(6);
    }

    fn push_group_control_descriptor(request: &mut Vec<u8>, members: [([u8; 16], [u8; 16]); 2]) {
        push_frame(request, &[0xA1; 16]).expect("event id frame");
        push_frame(request, &[0xB2; 32]).expect("group id frame");
        push_u32(request, 1);
        request.push(0);
        push_u64(request, 1);
        request.push(1);
        push_frame(request, &[0xC3; 32]).expect("Commit hash frame");
        push_u64(request, 1_700_000_000_000);
        request.push(1);
        push_frame(request, b"Beta group").expect("name frame");
        push_frame(request, b"description").expect("description frame");
        request.push(0);
        request.push(1);
        request.push(0);
        push_u16(request, 2);
        for (user_id, device_id) in members {
            push_frame(request, &user_id).expect("member user frame");
            push_frame(
                request,
                if user_id == OPERATION_USER {
                    b"Alice"
                } else {
                    b"Bob"
                },
            )
            .expect("member display name frame");
            request.push(if user_id == OPERATION_USER { 0 } else { 2 });
            request.push(0);
            request.push(1);
            push_u16(request, 1);
            push_frame(request, &device_id).expect("member device frame");
        }
    }

    #[allow(clippy::type_complexity)]
    fn decode_group_control_response(
        operation: u32,
        response: &[u8],
    ) -> (Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>, [u8; 16], [u8; 16]) {
        let mut reader = Reader::new(response);
        reader
            .expect(OPERATION_RESPONSE_MAGIC)
            .expect("operation response magic");
        assert_eq!(reader.u16().expect("response version"), OPERATION_VERSION);
        assert_eq!(
            u32::from(reader.u8().expect("response operation")),
            operation
        );
        let canonical = reader.framed().expect("canonical frame").to_vec();
        let signature = reader.framed().expect("signature frame").to_vec();
        let state_hash = reader.framed().expect("state hash frame").to_vec();
        let payload = reader.framed().expect("payload frame").to_vec();
        let signer_user = reader
            .framed()
            .expect("signer user frame")
            .try_into()
            .expect("signer user length");
        let signer_device = reader
            .framed()
            .expect("signer device frame")
            .try_into()
            .expect("signer device length");
        assert!(reader.is_finished());
        (
            canonical,
            signature,
            state_hash,
            payload,
            signer_user,
            signer_device,
        )
    }

    fn enrolled_operation_device(
        user_id: [u8; 16],
        device_id: [u8; 16],
        seed: u8,
    ) -> (Vec<u8>, Vec<u8>) {
        let device_v1 = prepare_device_with_provider(&fixed_provider(seed, 100_000), &user_id)
            .expect("device preparation succeeds");
        let identity = prepare_first_identity_with_provider(
            &fixed_provider(seed.wrapping_add(1), 20_000),
            &user_id,
        )
        .expect("identity preparation succeeds");
        let provider = fixed_provider(seed.wrapping_add(2), 100_000);
        let mut state = decode_device_state(&provider, &device_v1, OPERATION_DAY)
            .expect("legacy device state decodes for explicit migration");
        prepare_rotation(&provider, &mut state, &identity, device_id, OPERATION_DAY)
            .expect("rotation binds the device to the account self-signing key");
        let bundle = claimed_bundle_request(&state, &identity, device_id);
        let state = encode_device_state(&state).expect("device state encoding succeeds");
        (state, bundle)
    }

    fn enrolled_operation_device_with_rotation(
        user_id: [u8; 16],
        device_id: [u8; 16],
        seed: u8,
    ) -> (Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>) {
        let device_v1 = prepare_device_with_provider(&fixed_provider(seed, 100_000), &user_id)
            .expect("device preparation succeeds");
        let identity = prepare_first_identity_with_provider(
            &fixed_provider(seed.wrapping_add(1), 20_000),
            &user_id,
        )
        .expect("identity preparation succeeds");
        let provider = fixed_provider(seed.wrapping_add(2), 100_000);
        let mut state = decode_device_state(&provider, &device_v1, OPERATION_DAY)
            .expect("legacy device state decodes for explicit migration");
        let (first_batch, _) =
            prepare_rotation(&provider, &mut state, &identity, device_id, OPERATION_DAY)
                .expect("initial rotation binds the device to the account self-signing key");
        commit_pending_upload(&mut state, &first_batch)
            .expect("initial rotation upload commits atomically");
        let first_bundle = claimed_bundle_request(&state, &identity, device_id);
        let first_state = encode_device_state(&state).expect("first device state encodes");

        let (rotated_batch, _) = prepare_rotation(
            &fixed_provider(seed.wrapping_add(3), 100_000),
            &mut state,
            &identity,
            device_id,
            OPERATION_DAY + 7,
        )
        .expect("ordinary signed-prekey rotation succeeds");
        commit_pending_upload(&mut state, &rotated_batch)
            .expect("ordinary rotation upload commits atomically");
        let rotated_bundle = claimed_bundle_request(&state, &identity, device_id);
        let rotated_state = encode_device_state(&state).expect("rotated device state encodes");
        (first_state, first_bundle, rotated_state, rotated_bundle)
    }

    fn decode_operation_response(operation: u32, response: &[u8]) -> (Vec<u8>, Vec<Vec<u8>>) {
        let mut reader = Reader::new(response);
        reader
            .expect(OPERATION_RESPONSE_MAGIC)
            .expect("operation response magic");
        assert_eq!(reader.u16().expect("operation response version"), 1);
        assert_eq!(
            reader.u8().expect("operation response discriminator"),
            u8::try_from(operation).expect("test operation is byte sized")
        );
        let state = reader.framed().expect("opaque KeyPackage state").to_vec();
        let count = usize::from(reader.u16().expect("KeyPackage count"));
        let packages = (0..count)
            .map(|_| reader.framed().expect("wrapped KeyPackage").to_vec())
            .collect();
        assert!(reader.is_finished());
        (state, packages)
    }

    struct CommitOperationOutput {
        sealed_state: Vec<u8>,
        commit: Vec<u8>,
        authentication_proofs: Vec<Vec<u8>>,
        welcomes: Vec<Vec<u8>>,
        group_info: Vec<u8>,
        group_id: Vec<u8>,
        epoch: u64,
        confirmation: Vec<u8>,
    }

    fn decode_commit_response(operation: u32, response: &[u8]) -> CommitOperationOutput {
        let mut reader = response_reader(operation, response);
        let sealed_state = reader.framed().expect("sealed group state").to_vec();
        let commit = reader.framed().expect("Commit message").to_vec();
        let commit_digest = reader.framed().expect("Commit digest");
        assert_eq!(commit_digest.len(), 32);
        let proof_count = usize::from(reader.u16().expect("authentication proof count"));
        assert!((1..=super::MAX_GROUP_AUTHENTICATION_PROOFS).contains(&proof_count));
        let authentication_proofs = (0..proof_count)
            .map(|_| {
                let proof = reader.framed().expect("authentication proof");
                super::validate_bundle_proof(proof).expect("authentication proof is canonical");
                proof.to_vec()
            })
            .collect();
        let welcome_count = usize::from(reader.u16().expect("Welcome count"));
        let welcomes = (0..welcome_count)
            .map(|_| reader.framed().expect("Welcome message").to_vec())
            .collect();
        let group_info = reader.framed().expect("GroupInfo message").to_vec();
        let group_id = reader.framed().expect("group id").to_vec();
        let epoch = reader.u64().expect("epoch");
        let confirmation = reader.take(32).expect("exporter confirmation").to_vec();
        assert!(reader.is_finished());
        CommitOperationOutput {
            sealed_state,
            commit,
            authentication_proofs,
            welcomes,
            group_info,
            group_id,
            epoch,
            confirmation,
        }
    }

    struct JoinOperationOutput {
        sealed_group_state: Vec<u8>,
        group_id: Vec<u8>,
        epoch: u64,
        roster: Vec<(Vec<u8>, Vec<u8>)>,
        confirmation: Vec<u8>,
    }

    fn decode_join_response(response: &[u8]) -> JoinOperationOutput {
        let mut reader = response_reader(OP_JOIN_GROUP, response);
        let sealed_group_state = reader.framed().expect("sealed group state").to_vec();
        let sealed_key_package_state = reader.framed().expect("sealed KeyPackage state");
        assert!(sealed_key_package_state.starts_with(SEALED_STATE_MAGIC));
        let group_id = reader.framed().expect("group id").to_vec();
        let epoch = reader.u64().expect("epoch");
        let roster_count = reader.u16().expect("roster count");
        let roster = (0..roster_count)
            .map(|_| {
                (
                    reader.framed().expect("roster user id").to_vec(),
                    reader.framed().expect("roster device id").to_vec(),
                )
            })
            .collect();
        let confirmation = reader.take(32).expect("exporter confirmation").to_vec();
        assert!(reader.is_finished());
        JoinOperationOutput {
            sealed_group_state,
            group_id,
            epoch,
            roster,
            confirmation,
        }
    }

    struct MessageOperationOutput {
        sealed_state: Vec<u8>,
        message: Vec<u8>,
        epoch: u64,
        confirmation: Vec<u8>,
    }

    fn decode_message_response(operation: u32, response: &[u8]) -> MessageOperationOutput {
        let mut reader = response_reader(operation, response);
        let sealed_state = reader.framed().expect("sealed group state").to_vec();
        let message = reader.framed().expect("MLS message").to_vec();
        assert_eq!(reader.framed().expect("group id").len(), 32);
        let epoch = reader.u64().expect("epoch");
        let confirmation = reader.take(32).expect("exporter confirmation").to_vec();
        assert!(reader.is_finished());
        MessageOperationOutput {
            sealed_state,
            message,
            epoch,
            confirmation,
        }
    }

    struct ProcessedOperationOutput {
        sealed_state: Vec<u8>,
        message_digest: Vec<u8>,
        kind: u8,
        sender_user_id: Vec<u8>,
        sender_device_id: Vec<u8>,
        data: Vec<u8>,
        authenticated_data: Vec<u8>,
        epoch: u64,
        confirmation: Vec<u8>,
    }

    fn decode_processed_response(response: &[u8]) -> ProcessedOperationOutput {
        let mut reader = response_reader(OP_PROCESS_MESSAGE, response);
        let sealed_state = reader.framed().expect("sealed group state").to_vec();
        let message_digest = reader.framed().expect("MLS object digest").to_vec();
        assert_eq!(message_digest.len(), 32);
        let kind = reader.u8().expect("received message kind");
        reader.u32().expect("sender leaf index");
        let sender_user_id = reader.framed().expect("sender user id").to_vec();
        let sender_device_id = reader.framed().expect("sender device id").to_vec();
        let data = reader.framed().expect("application data").to_vec();
        let authenticated_data = reader.framed().expect("authenticated data").to_vec();
        assert_eq!(reader.framed().expect("group id").len(), 32);
        let epoch = reader.u64().expect("epoch");
        let confirmation = reader.take(32).expect("exporter confirmation").to_vec();
        assert!(reader.is_finished());
        ProcessedOperationOutput {
            sealed_state,
            message_digest,
            kind,
            sender_user_id,
            sender_device_id,
            data,
            authenticated_data,
            epoch,
            confirmation,
        }
    }

    fn response_reader(operation: u32, response: &[u8]) -> Reader<'_> {
        let mut reader = Reader::new(response);
        reader
            .expect(OPERATION_RESPONSE_MAGIC)
            .expect("operation response magic");
        assert_eq!(reader.u16().expect("operation response version"), 1);
        assert_eq!(
            reader.u8().expect("operation response discriminator"),
            u8::try_from(operation).expect("test operation is byte sized")
        );
        reader
    }

    fn make_client_with_storage(
        authentication_service: AuthenticatedDeviceIdentityProvider,
        record: AuthenticatedDevice,
        signer: mls_rs_core::crypto::SignatureSecretKey,
        signature_public: SignaturePublicKey,
        state_storage: OpaqueMlsStateStorage,
    ) -> Client<impl MlsConfig> {
        make_client_with_stores(
            authentication_service,
            record,
            signer,
            signature_public,
            state_storage,
            OpaqueKeyPackageStorage::default(),
        )
    }

    #[allow(clippy::needless_pass_by_value)] // Test builders intentionally mirror the owning client-construction API.
    fn make_client_with_stores(
        authentication_service: AuthenticatedDeviceIdentityProvider,
        record: AuthenticatedDevice,
        signer: mls_rs_core::crypto::SignatureSecretKey,
        signature_public: SignaturePublicKey,
        state_storage: OpaqueMlsStateStorage,
        key_package_storage: OpaqueKeyPackageStorage,
    ) -> Client<impl MlsConfig> {
        let credential = BasicCredential::new(
            record
                .credential_identifier()
                .expect("credential identifier encoding succeeds"),
        );
        let signing_identity = SigningIdentity::new(credential.into_credential(), signature_public);
        let mut encryption_options = EncryptionOptions::default();
        encryption_options.encrypt_control_messages = true;
        let rules = DefaultMlsRules::default().with_encryption_options(encryption_options);
        Client::builder()
            .identity_provider(authentication_service)
            .mls_rules(rules)
            .crypto_provider(BetaMlsCryptoProvider)
            .key_package_repo(key_package_storage)
            .group_state_storage(state_storage)
            .signing_identity(signing_identity, signer, BETA_CIPHERSUITE)
            .build()
    }
}
