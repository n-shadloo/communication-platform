//! Authenticated mutable device/prekey state for the pairwise transport.
//!
//! `CPDVV001` is accepted only as a migration input. Every successful operation
//! emits `CPDVV002`, whose canonical byte representation is authenticated with a
//! device-local key derived from the X25519 identity secret.

#![allow(
    clippy::too_many_lines,
    reason = "Strict versioned state decoders and the atomic rotation projection are intentionally linear for independent byte-level review."
)]

use ed25519_dalek::SigningKey;
use subtle::ConstantTimeEq;
use zeroize::Zeroize;

use crate::{
    device_signatures::{
        CrossSigningIdentity, DeviceBundle, IkPublic, PublicPrekey, RawUuid, SignedPrekey,
        encode_cross_signature, encode_master_signature, encode_pq_signed_prekey,
        encode_signed_prekey,
    },
    error::{CryptoError, CryptoResult},
    protocol::{Reader, hkdf_sha256, hmac_sha256, push_frame, push_u16, push_u32, reserve},
    provider::{
        CryptoProvider, ED25519_SIGNATURE_BYTES, MLKEM768_PUBLIC_BYTES, MLKEM768_SECRET_BYTES,
        X25519_PUBLIC_BYTES, X25519_SECRET_BYTES,
    },
    secret::SecretBytes,
};

pub(crate) const DEVICE_V1_MAGIC: &[u8; 8] = b"CPDVV001";
pub(crate) const DEVICE_V2_MAGIC: &[u8; 8] = b"CPDVV002";
pub(crate) const UPLOAD_MAGIC: &[u8; 8] = b"CPKUV001";
const STATE_AUTH_DOMAIN: &[u8] = b"chat:v1:device-prekey-state-auth";
const STATE_AUTH_TAG_BYTES: usize = 32;
const MAX_CLASSICAL_ONE_TIME: usize = 400;
const MAX_PQ_ONE_TIME: usize = 240;
const MAX_RETIRED_SIGNED_PAIRS: usize = 3;
pub(crate) const MAX_BACKEND_CLASSICAL_ONE_TIME: u16 = 200;
pub(crate) const MAX_BACKEND_PQ_ONE_TIME: u16 = 100;
pub(crate) const KEY_ID_MAX: u32 = 0x7fff_ffff;
const UPLOAD_REPLENISH: u8 = 1;
const UPLOAD_ROTATION: u8 = 2;

pub(crate) struct ClassicalSignedKey {
    pub(crate) id: u32,
    pub(crate) created_day: u32,
    pub(crate) public: [u8; X25519_PUBLIC_BYTES],
    pub(crate) signature: [u8; ED25519_SIGNATURE_BYTES],
    pub(crate) secret: [u8; X25519_SECRET_BYTES],
}

impl Drop for ClassicalSignedKey {
    fn drop(&mut self) {
        self.secret.zeroize();
    }
}

pub(crate) struct PqSignedKey {
    pub(crate) id: u32,
    pub(crate) created_day: u32,
    pub(crate) public: [u8; MLKEM768_PUBLIC_BYTES],
    pub(crate) signature: [u8; ED25519_SIGNATURE_BYTES],
    pub(crate) secret: [u8; MLKEM768_SECRET_BYTES],
}

impl Drop for PqSignedKey {
    fn drop(&mut self) {
        self.secret.zeroize();
    }
}

pub(crate) struct RetiredSignedPair {
    pub(crate) retain_through_day: u32,
    pub(crate) classical: ClassicalSignedKey,
    pub(crate) pq: PqSignedKey,
}

pub(crate) struct ClassicalOneTimeKey {
    pub(crate) id: u32,
    pub(crate) public: [u8; X25519_PUBLIC_BYTES],
    pub(crate) secret: [u8; X25519_SECRET_BYTES],
}

impl Drop for ClassicalOneTimeKey {
    fn drop(&mut self) {
        self.secret.zeroize();
    }
}

pub(crate) struct PqOneTimeKey {
    pub(crate) id: u32,
    pub(crate) public: [u8; MLKEM768_PUBLIC_BYTES],
    pub(crate) secret: [u8; MLKEM768_SECRET_BYTES],
}

impl Drop for PqOneTimeKey {
    fn drop(&mut self) {
        self.secret.zeroize();
    }
}

pub(crate) struct PendingUpload {
    pub(crate) batch_id: [u8; 16],
    pub(crate) kind: u8,
    pub(crate) exact_projection: Vec<u8>,
}

impl PendingUpload {
    pub(crate) const fn is_rotation(&self) -> bool {
        self.kind == UPLOAD_ROTATION
    }
}

pub(crate) struct DeviceState {
    pub(crate) user_id: [u8; 16],
    pub(crate) registration_id: u32,
    pub(crate) bundle_version: u32,
    pub(crate) next_classical_one_time_id: u32,
    pub(crate) next_pq_one_time_id: u32,
    pub(crate) device_signing_public: [u8; 32],
    pub(crate) identity_public: [u8; 32],
    pub(crate) device_signing_secret: [u8; 32],
    pub(crate) identity_secret: [u8; 32],
    pub(crate) current_classical: ClassicalSignedKey,
    pub(crate) current_pq: PqSignedKey,
    pub(crate) cross_signature: [u8; 64],
    pub(crate) retired: Vec<RetiredSignedPair>,
    pub(crate) classical_one_time: Vec<ClassicalOneTimeKey>,
    pub(crate) pq_one_time: Vec<PqOneTimeKey>,
    pub(crate) pending: Option<PendingUpload>,
}

impl Drop for DeviceState {
    fn drop(&mut self) {
        self.device_signing_secret.zeroize();
        self.identity_secret.zeroize();
    }
}

impl DeviceState {
    pub(crate) fn ik_public(&self) -> IkPublic {
        IkPublic::from_halves(self.device_signing_public, self.identity_public)
    }

    pub(crate) fn signed_classical(&self, id: u32) -> Option<&ClassicalSignedKey> {
        if self.current_classical.id == id {
            return Some(&self.current_classical);
        }
        self.retired
            .iter()
            .find(|pair| pair.classical.id == id)
            .map(|pair| &pair.classical)
    }

    pub(crate) fn signed_pq(&self, id: u32) -> Option<&PqSignedKey> {
        if self.current_pq.id == id {
            return Some(&self.current_pq);
        }
        self.retired
            .iter()
            .find(|pair| pair.pq.id == id)
            .map(|pair| &pair.pq)
    }

    pub(crate) fn classical_one_time(&self, id: u32) -> Option<&ClassicalOneTimeKey> {
        self.classical_one_time.iter().find(|key| key.id == id)
    }

    pub(crate) fn pq_one_time(&self, id: u32) -> Option<&PqOneTimeKey> {
        self.pq_one_time.iter().find(|key| key.id == id)
    }

    pub(crate) fn consume_classical_one_time(&mut self, id: u32) -> CryptoResult<()> {
        let position = self
            .classical_one_time
            .iter()
            .position(|key| key.id == id)
            .ok_or(CryptoError::StateViolation)?;
        self.classical_one_time.remove(position);
        Ok(())
    }

    pub(crate) fn consume_pq_one_time(&mut self, id: u32) -> CryptoResult<()> {
        let position = self
            .pq_one_time
            .iter()
            .position(|key| key.id == id)
            .ok_or(CryptoError::StateViolation)?;
        self.pq_one_time.remove(position);
        Ok(())
    }

    pub(crate) fn prune_retired(&mut self, coarse_day: u32) {
        self.retired
            .retain(|pair| coarse_day <= pair.retain_through_day);
    }
}

fn initial_next_id<'a>(ids: impl Iterator<Item = &'a u32>) -> CryptoResult<u32> {
    let current = ids.copied().max().unwrap_or(0);
    if current == KEY_ID_MAX {
        Ok(u32::MAX)
    } else {
        current.checked_add(1).ok_or(CryptoError::StateViolation)
    }
}

fn take_next_id(high_water: &mut u32) -> CryptoResult<u32> {
    if *high_water > KEY_ID_MAX {
        return Err(CryptoError::StateViolation);
    }
    let value = *high_water;
    *high_water = if value == KEY_ID_MAX {
        u32::MAX
    } else {
        value.checked_add(1).ok_or(CryptoError::StateViolation)?
    };
    Ok(value)
}

pub(crate) fn decode_device_state<P: CryptoProvider>(
    provider: &P,
    input: &[u8],
    migration_day: u32,
) -> CryptoResult<DeviceState> {
    match input.get(..8) {
        Some(magic) if magic == DEVICE_V1_MAGIC => decode_v1(provider, input, migration_day),
        Some(magic) if magic == DEVICE_V2_MAGIC => decode_v2(provider, input),
        _ => Err(CryptoError::UnsupportedVersion),
    }
}

pub(crate) fn encode_device_state(state: &DeviceState) -> CryptoResult<Vec<u8>> {
    let mut output = Vec::new();
    reserve(&mut output, 512)?;
    output.extend_from_slice(DEVICE_V2_MAGIC);
    output.extend_from_slice(&state.user_id);
    push_u32(&mut output, state.registration_id);
    push_u32(&mut output, state.bundle_version);
    push_u32(&mut output, state.next_classical_one_time_id);
    push_u32(&mut output, state.next_pq_one_time_id);
    output.extend_from_slice(&state.device_signing_public);
    output.extend_from_slice(&state.identity_public);
    output.extend_from_slice(&state.device_signing_secret);
    output.extend_from_slice(&state.identity_secret);
    encode_classical_signed(&mut output, &state.current_classical);
    encode_pq_signed(&mut output, &state.current_pq);
    output.extend_from_slice(&state.cross_signature);
    output.push(u8::try_from(state.retired.len()).map_err(|_| CryptoError::ResourceExhausted)?);
    for pair in &state.retired {
        push_u32(&mut output, pair.retain_through_day);
        encode_classical_signed(&mut output, &pair.classical);
        encode_pq_signed(&mut output, &pair.pq);
    }
    push_u16(
        &mut output,
        u16::try_from(state.classical_one_time.len())
            .map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for key in &state.classical_one_time {
        push_u32(&mut output, key.id);
        output.extend_from_slice(&key.public);
        output.extend_from_slice(&key.secret);
    }
    push_u16(
        &mut output,
        u16::try_from(state.pq_one_time.len()).map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for key in &state.pq_one_time {
        push_u32(&mut output, key.id);
        output.extend_from_slice(&key.public);
        output.extend_from_slice(&key.secret);
    }
    match &state.pending {
        None => output.push(0),
        Some(pending) => {
            output.push(1);
            output.push(pending.kind);
            output.extend_from_slice(&pending.batch_id);
            push_frame(&mut output, &pending.exact_projection)?;
        }
    }
    let auth_key = device_auth_key(&state.identity_secret)?;
    let tag = hmac_sha256(&auth_key, &output)?;
    output.extend_from_slice(&tag);
    if output.len() > crate::bounds::MAX_INPUT_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    Ok(output)
}

fn decode_v1<P: CryptoProvider>(
    provider: &P,
    input: &[u8],
    migration_day: u32,
) -> CryptoResult<DeviceState> {
    // CPDVV001 did not persist an authoritative signed-prekey creation day.
    // Treat an upgraded legacy pair as exactly rotation-due so migration can
    // immediately publish one atomic classical/PQ rotation. Stamping it as
    // newly-created would incorrectly postpone that mandatory maintenance for
    // seven days and could let stale legacy metadata win over native state.
    let migrated_created_day = migration_day.saturating_sub(7);
    let mut reader = Reader::new(input);
    if reader.take(8)? != DEVICE_V1_MAGIC {
        return Err(CryptoError::UnsupportedVersion);
    }
    let user_id = reader.array()?;
    let registration_id = reader.u32()?;
    let spk_id = valid_key_id(reader.u32()?)?;
    let pq_spk_id = valid_key_id(reader.u32()?)?;
    let classical_count = usize::from(reader.u16()?);
    let pq_count = usize::from(reader.u16()?);
    if classical_count == 0
        || classical_count > 8
        || pq_count == 0
        || pq_count > 4
        || user_id.iter().all(|byte| *byte == 0)
    {
        return Err(CryptoError::MalformedInput);
    }
    let device_signing_public = reader.array()?;
    let identity_public = reader.array()?;
    let spk_public = reader.array()?;
    let spk_signature = reader.array()?;
    let pq_spk_public = reader.array()?;
    let pq_spk_signature = reader.array()?;
    let fingerprint: [u8; 32] = reader.array()?;
    let mut classical_public = Vec::new();
    for _ in 0..classical_count {
        classical_public.push((valid_key_id(reader.u32()?)?, reader.array()?));
    }
    let mut pq_public = Vec::new();
    for _ in 0..pq_count {
        pq_public.push((valid_key_id(reader.u32()?)?, reader.array()?));
    }
    let device_signing_secret: [u8; 32] = reader.array()?;
    let identity_secret: [u8; 32] = reader.array()?;
    let spk_secret = reader.array()?;
    let pq_spk_secret = reader.array()?;
    let mut classical_one_time = Vec::new();
    for (id, public) in classical_public {
        classical_one_time.push(ClassicalOneTimeKey {
            id,
            public,
            secret: reader.array()?,
        });
    }
    let mut pq_one_time = Vec::new();
    for (id, public) in pq_public {
        pq_one_time.push(PqOneTimeKey {
            id,
            public,
            secret: reader.array()?,
        });
    }
    if !reader.is_finished()
        || SigningKey::from_bytes(&device_signing_secret)
            .verifying_key()
            .to_bytes()
            != device_signing_public
        || provider.x25519_public(&SecretBytes::new(identity_secret))? != identity_public
        || provider.x25519_public(&SecretBytes::new(spk_secret))? != spk_public
        || provider.sha256(&[device_signing_public, identity_public].concat())? != fingerprint
    {
        return Err(CryptoError::AuthenticationFailed);
    }
    validate_sorted_classical(&classical_one_time)?;
    validate_sorted_pq(&pq_one_time)?;
    let ik = IkPublic::from_halves(device_signing_public, identity_public);
    let raw_user = RawUuid::new(user_id);
    provider.ed25519_verify(
        &device_signing_public,
        &encode_signed_prekey(&SignedPrekey {
            user_id: raw_user,
            prekey: PublicPrekey {
                id: spk_id,
                public: &spk_public,
            },
        })?,
        &spk_signature,
    )?;
    provider.ed25519_verify(
        &ik.device_signing_public(),
        &encode_pq_signed_prekey(&SignedPrekey {
            user_id: raw_user,
            prekey: PublicPrekey {
                id: pq_spk_id,
                public: &pq_spk_public,
            },
        })?,
        &pq_spk_signature,
    )?;
    let next_classical_one_time_id = initial_next_id(classical_one_time.iter().map(|key| &key.id))?;
    let next_pq_one_time_id = initial_next_id(pq_one_time.iter().map(|key| &key.id))?;
    let state = DeviceState {
        user_id,
        registration_id,
        bundle_version: 1,
        next_classical_one_time_id,
        next_pq_one_time_id,
        device_signing_public,
        identity_public,
        device_signing_secret,
        identity_secret,
        current_classical: ClassicalSignedKey {
            id: spk_id,
            created_day: migrated_created_day,
            public: spk_public,
            signature: spk_signature,
            secret: spk_secret,
        },
        current_pq: PqSignedKey {
            id: pq_spk_id,
            created_day: migrated_created_day,
            public: pq_spk_public,
            signature: pq_spk_signature,
            secret: pq_spk_secret,
        },
        cross_signature: [0; 64],
        retired: Vec::new(),
        classical_one_time,
        pq_one_time,
        pending: None,
    };
    validate_device_material(provider, &state)?;
    Ok(state)
}

fn decode_v2<P: CryptoProvider>(provider: &P, input: &[u8]) -> CryptoResult<DeviceState> {
    if input.len() < STATE_AUTH_TAG_BYTES + 8 {
        return Err(CryptoError::MalformedInput);
    }
    let authenticated_len = input.len() - STATE_AUTH_TAG_BYTES;
    let (encoded, supplied_tag) = input.split_at(authenticated_len);
    let mut reader = Reader::new(encoded);
    if reader.take(8)? != DEVICE_V2_MAGIC {
        return Err(CryptoError::UnsupportedVersion);
    }
    let user_id = reader.array()?;
    let registration_id = reader.u32()?;
    let bundle_version = reader.u32()?;
    let next_classical_one_time_id = reader.u32()?;
    let next_pq_one_time_id = reader.u32()?;
    let device_signing_public = reader.array()?;
    let identity_public = reader.array()?;
    let device_signing_secret = reader.array()?;
    let identity_secret = reader.array()?;
    let current_classical = decode_classical_signed(&mut reader)?;
    let current_pq = decode_pq_signed(&mut reader)?;
    let cross_signature = reader.array()?;
    let retired_count = usize::from(reader.u8()?);
    if retired_count > MAX_RETIRED_SIGNED_PAIRS {
        return Err(CryptoError::ResourceExhausted);
    }
    let mut retired = Vec::new();
    retired
        .try_reserve_exact(retired_count)
        .map_err(|_| CryptoError::ResourceExhausted)?;
    for _ in 0..retired_count {
        retired.push(RetiredSignedPair {
            retain_through_day: reader.u32()?,
            classical: decode_classical_signed(&mut reader)?,
            pq: decode_pq_signed(&mut reader)?,
        });
    }
    let classical_count = usize::from(reader.u16()?);
    if classical_count > MAX_CLASSICAL_ONE_TIME {
        return Err(CryptoError::ResourceExhausted);
    }
    let mut classical_one_time = Vec::new();
    classical_one_time
        .try_reserve_exact(classical_count)
        .map_err(|_| CryptoError::ResourceExhausted)?;
    for _ in 0..classical_count {
        classical_one_time.push(ClassicalOneTimeKey {
            id: valid_key_id(reader.u32()?)?,
            public: reader.array()?,
            secret: reader.array()?,
        });
    }
    let pq_count = usize::from(reader.u16()?);
    if pq_count > MAX_PQ_ONE_TIME {
        return Err(CryptoError::ResourceExhausted);
    }
    let mut pq_one_time = Vec::new();
    pq_one_time
        .try_reserve_exact(pq_count)
        .map_err(|_| CryptoError::ResourceExhausted)?;
    for _ in 0..pq_count {
        pq_one_time.push(PqOneTimeKey {
            id: valid_key_id(reader.u32()?)?,
            public: reader.array()?,
            secret: reader.array()?,
        });
    }
    let pending = if reader.boolean()? {
        let kind = reader.u8()?;
        if !matches!(kind, UPLOAD_REPLENISH | UPLOAD_ROTATION) {
            return Err(CryptoError::MalformedInput);
        }
        Some(PendingUpload {
            kind,
            batch_id: reader.array()?,
            exact_projection: reader.framed()?.to_vec(),
        })
    } else {
        None
    };
    if !reader.is_finished()
        || bundle_version == 0
        || user_id.iter().all(|byte| *byte == 0)
        || (next_classical_one_time_id != u32::MAX && next_classical_one_time_id > KEY_ID_MAX)
        || (next_pq_one_time_id != u32::MAX && next_pq_one_time_id > KEY_ID_MAX)
        || classical_one_time
            .iter()
            .any(|key| next_classical_one_time_id <= key.id)
        || pq_one_time.iter().any(|key| next_pq_one_time_id <= key.id)
    {
        return Err(CryptoError::MalformedInput);
    }
    let auth_key = device_auth_key(&identity_secret)?;
    let expected_tag = hmac_sha256(&auth_key, encoded)?;
    if !bool::from(expected_tag.ct_eq(supplied_tag)) {
        return Err(CryptoError::AuthenticationFailed);
    }
    if SigningKey::from_bytes(&device_signing_secret)
        .verifying_key()
        .to_bytes()
        != device_signing_public
        || provider.x25519_public(&SecretBytes::new(identity_secret))? != identity_public
        || provider.x25519_public(&SecretBytes::new(current_classical.secret))?
            != current_classical.public
    {
        return Err(CryptoError::AuthenticationFailed);
    }
    validate_sorted_classical(&classical_one_time)?;
    validate_sorted_pq(&pq_one_time)?;
    let state = DeviceState {
        user_id,
        registration_id,
        bundle_version,
        next_classical_one_time_id,
        next_pq_one_time_id,
        device_signing_public,
        identity_public,
        device_signing_secret,
        identity_secret,
        current_classical,
        current_pq,
        cross_signature,
        retired,
        classical_one_time,
        pq_one_time,
        pending,
    };
    validate_device_material(provider, &state)?;
    Ok(state)
}

fn validate_device_material<P: CryptoProvider>(
    provider: &P,
    state: &DeviceState,
) -> CryptoResult<()> {
    let ik = state.ik_public();
    let user_id = RawUuid::new(state.user_id);
    validate_classical_signed(provider, &ik, user_id, &state.current_classical)?;
    validate_pq_signed(provider, &ik, user_id, &state.current_pq)?;
    if state
        .retired
        .windows(2)
        .any(|pair| pair[0].classical.id >= pair[1].classical.id || pair[0].pq.id >= pair[1].pq.id)
    {
        return Err(CryptoError::MalformedInput);
    }
    for pair in &state.retired {
        validate_classical_signed(provider, &ik, user_id, &pair.classical)?;
        validate_pq_signed(provider, &ik, user_id, &pair.pq)?;
    }
    for key in &state.classical_one_time {
        if provider.x25519_public(&SecretBytes::new(key.secret))? != key.public {
            return Err(CryptoError::AuthenticationFailed);
        }
    }
    for key in &state.pq_one_time {
        validate_pq_public_in_secret(&key.secret, &key.public)?;
    }
    Ok(())
}

fn validate_classical_signed<P: CryptoProvider>(
    provider: &P,
    ik: &IkPublic,
    user_id: RawUuid,
    key: &ClassicalSignedKey,
) -> CryptoResult<()> {
    if provider.x25519_public(&SecretBytes::new(key.secret))? != key.public {
        return Err(CryptoError::AuthenticationFailed);
    }
    provider.ed25519_verify(
        &ik.device_signing_public(),
        &encode_signed_prekey(&SignedPrekey {
            user_id,
            prekey: PublicPrekey {
                id: key.id,
                public: &key.public,
            },
        })?,
        &key.signature,
    )
}

fn validate_pq_signed<P: CryptoProvider>(
    provider: &P,
    ik: &IkPublic,
    user_id: RawUuid,
    key: &PqSignedKey,
) -> CryptoResult<()> {
    validate_pq_public_in_secret(&key.secret, &key.public)?;
    provider.ed25519_verify(
        &ik.device_signing_public(),
        &encode_pq_signed_prekey(&SignedPrekey {
            user_id,
            prekey: PublicPrekey {
                id: key.id,
                public: &key.public,
            },
        })?,
        &key.signature,
    )
}

fn validate_pq_public_in_secret(
    secret: &[u8; MLKEM768_SECRET_BYTES],
    public: &[u8; MLKEM768_PUBLIC_BYTES],
) -> CryptoResult<()> {
    // FIPS 203 ML-KEM-768 dk is dkPKE(1152) || ek(1184) || H(ek) || z.
    const PKE_SECRET_BYTES: usize = 1_152;
    let embedded_public = secret
        .get(PKE_SECRET_BYTES..PKE_SECRET_BYTES + MLKEM768_PUBLIC_BYTES)
        .ok_or(CryptoError::MalformedInput)?;
    if bool::from(embedded_public.ct_eq(public)) {
        Ok(())
    } else {
        Err(CryptoError::AuthenticationFailed)
    }
}

pub(crate) fn prepare_replenishment<P: CryptoProvider>(
    provider: &P,
    state: &mut DeviceState,
    server_classical_count: u16,
    server_pq_count: u16,
    target_classical: u16,
    target_pq: u16,
) -> CryptoResult<([u8; 16], Vec<u8>)> {
    if let Some(pending) = &state.pending {
        return Ok((pending.batch_id, pending.exact_projection.clone()));
    }
    if target_classical > MAX_BACKEND_CLASSICAL_ONE_TIME
        || target_pq > MAX_BACKEND_PQ_ONE_TIME
        || server_classical_count > MAX_BACKEND_CLASSICAL_ONE_TIME
        || server_pq_count > MAX_BACKEND_PQ_ONE_TIME
    {
        return Err(CryptoError::InvalidArgument);
    }
    let add_classical = usize::from(target_classical.saturating_sub(server_classical_count));
    let add_pq = usize::from(target_pq.saturating_sub(server_pq_count));
    if state.classical_one_time.len().saturating_add(add_classical) > MAX_CLASSICAL_ONE_TIME
        || state.pq_one_time.len().saturating_add(add_pq) > MAX_PQ_ONE_TIME
    {
        return Err(CryptoError::ResourceExhausted);
    }
    let mut batch_id = [0u8; 16];
    provider.random_bytes(&mut batch_id)?;
    let mut generated_classical = Vec::new();
    for _ in 0..add_classical {
        let next_classical = take_next_id(&mut state.next_classical_one_time_id)?;
        let mut secret = SecretBytes::zeroed();
        provider.random_bytes(secret.expose_mut())?;
        let public = provider.x25519_public(&secret)?;
        generated_classical.push((next_classical, public));
        state.classical_one_time.push(ClassicalOneTimeKey {
            id: next_classical,
            public,
            secret: *secret.expose(),
        });
    }
    let mut generated_pq = Vec::new();
    for _ in 0..add_pq {
        let next_pq = take_next_id(&mut state.next_pq_one_time_id)?;
        let (public, secret) = provider.mlkem768_keypair()?;
        generated_pq.push((next_pq, public));
        state.pq_one_time.push(PqOneTimeKey {
            id: next_pq,
            public,
            secret: *secret.expose(),
        });
    }
    state.classical_one_time.sort_unstable_by_key(|key| key.id);
    state.pq_one_time.sort_unstable_by_key(|key| key.id);
    let mut projection = Vec::new();
    projection.extend_from_slice(UPLOAD_MAGIC);
    projection.extend_from_slice(&batch_id);
    projection.push(UPLOAD_REPLENISH);
    push_u32(&mut projection, state.bundle_version);
    push_u16(
        &mut projection,
        u16::try_from(generated_classical.len()).map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for (id, public) in generated_classical {
        push_u32(&mut projection, id);
        projection.extend_from_slice(&public);
    }
    push_u16(
        &mut projection,
        u16::try_from(generated_pq.len()).map_err(|_| CryptoError::ResourceExhausted)?,
    );
    for (id, public) in generated_pq {
        push_u32(&mut projection, id);
        projection.extend_from_slice(&public);
    }
    state.pending = Some(PendingUpload {
        batch_id,
        kind: UPLOAD_REPLENISH,
        exact_projection: projection.clone(),
    });
    Ok((batch_id, projection))
}

pub(crate) fn commit_pending_upload(
    state: &mut DeviceState,
    batch_id: &[u8; 16],
) -> CryptoResult<()> {
    let pending = state.pending.as_ref().ok_or(CryptoError::StateViolation)?;
    if !bool::from(pending.batch_id.ct_eq(batch_id)) {
        return Err(CryptoError::StateViolation);
    }
    state.pending = None;
    Ok(())
}

pub(crate) fn prepare_rotation<P: CryptoProvider>(
    provider: &P,
    state: &mut DeviceState,
    identity_package: &[u8],
    device_id: [u8; 16],
    coarse_day: u32,
) -> CryptoResult<([u8; 16], Vec<u8>)> {
    if let Some(pending) = &state.pending {
        if pending.is_rotation() {
            return Ok((pending.batch_id, pending.exact_projection.clone()));
        }
        return Err(CryptoError::StateViolation);
    }
    if coarse_day < state.current_classical.created_day.saturating_add(7)
        || coarse_day < state.current_pq.created_day.saturating_add(7)
    {
        return Err(CryptoError::StateViolation);
    }
    state.prune_retired(coarse_day);
    if state.retired.len() >= MAX_RETIRED_SIGNED_PAIRS {
        return Err(CryptoError::ResourceExhausted);
    }
    let self_signing_secret =
        parse_self_signing_secret(provider, identity_package, &state.user_id)?;
    let next_spk_id = state
        .current_classical
        .id
        .checked_add(1)
        .filter(|id| *id <= KEY_ID_MAX)
        .ok_or(CryptoError::StateViolation)?;
    let next_pq_id = state
        .current_pq
        .id
        .checked_add(1)
        .filter(|id| *id <= KEY_ID_MAX)
        .ok_or(CryptoError::StateViolation)?;
    let next_bundle_version = state
        .bundle_version
        .checked_add(1)
        .ok_or(CryptoError::StateViolation)?;
    let mut spk_secret = SecretBytes::zeroed();
    provider.random_bytes(spk_secret.expose_mut())?;
    let spk_public = provider.x25519_public(&spk_secret)?;
    let user_id = RawUuid::new(state.user_id);
    let device_signing_secret = SecretBytes::new(state.device_signing_secret);
    let spk_signature = provider.ed25519_sign(
        &device_signing_secret,
        &encode_signed_prekey(&SignedPrekey {
            user_id,
            prekey: PublicPrekey {
                id: next_spk_id,
                public: &spk_public,
            },
        })?,
    )?;
    let (pq_public, pq_secret) = provider.mlkem768_keypair()?;
    let pq_signature = provider.ed25519_sign(
        &device_signing_secret,
        &encode_pq_signed_prekey(&SignedPrekey {
            user_id,
            prekey: PublicPrekey {
                id: next_pq_id,
                public: &pq_public,
            },
        })?,
    )?;
    let cross_bytes = encode_cross_signature(&DeviceBundle {
        user_id,
        device_id: RawUuid::new(device_id),
        ik_public: state.ik_public(),
        spk_id: next_spk_id,
        spk_public: &spk_public,
        pq_signed_prekey: Some(PublicPrekey {
            id: next_pq_id,
            public: &pq_public,
        }),
        registration_id: state.registration_id,
        bundle_version: next_bundle_version,
    })?;
    let cross_signature =
        provider.ed25519_sign(&SecretBytes::new(self_signing_secret), &cross_bytes)?;
    let replacement_classical = ClassicalSignedKey {
        id: next_spk_id,
        created_day: coarse_day,
        public: spk_public,
        signature: spk_signature,
        secret: *spk_secret.expose(),
    };
    let replacement_pq = PqSignedKey {
        id: next_pq_id,
        created_day: coarse_day,
        public: pq_public,
        signature: pq_signature,
        secret: *pq_secret.expose(),
    };
    let old_classical = std::mem::replace(&mut state.current_classical, replacement_classical);
    let old_pq = std::mem::replace(&mut state.current_pq, replacement_pq);
    state.retired.push(RetiredSignedPair {
        retain_through_day: coarse_day.saturating_add(8),
        classical: old_classical,
        pq: old_pq,
    });
    state.bundle_version = next_bundle_version;
    state.cross_signature = cross_signature;
    let mut batch_id = [0u8; 16];
    provider.random_bytes(&mut batch_id)?;
    let mut projection = Vec::new();
    projection.extend_from_slice(UPLOAD_MAGIC);
    projection.extend_from_slice(&batch_id);
    projection.push(UPLOAD_ROTATION);
    push_u32(&mut projection, next_bundle_version);
    push_u32(&mut projection, next_spk_id);
    projection.extend_from_slice(&state.current_classical.public);
    projection.extend_from_slice(&state.current_classical.signature);
    push_u32(&mut projection, next_pq_id);
    projection.extend_from_slice(&state.current_pq.public);
    projection.extend_from_slice(&state.current_pq.signature);
    projection.extend_from_slice(&cross_signature);
    state.pending = Some(PendingUpload {
        batch_id,
        kind: UPLOAD_ROTATION,
        exact_projection: projection.clone(),
    });
    Ok((batch_id, projection))
}

fn parse_self_signing_secret<P: CryptoProvider>(
    provider: &P,
    package: &[u8],
    expected_user_id: &[u8; 16],
) -> CryptoResult<[u8; 32]> {
    let mut reader = Reader::new(package);
    if reader.take(8)? != b"CPIDV001" {
        return Err(CryptoError::UnsupportedVersion);
    }
    let flags = reader.u8()?;
    if flags & !0b11 != 0 || reader.take(16)? != expected_user_id {
        return Err(CryptoError::AuthenticationFailed);
    }
    let master_public: [u8; 32] = reader.array()?;
    let self_signing_public: [u8; 32] = reader.array()?;
    let user_signing_public: [u8; 32] = reader.array()?;
    let master_signature: [u8; 64] = reader.array()?;
    let recovery_len = usize::from(reader.u16()?);
    let backup_len = usize::try_from(reader.u32()?).map_err(|_| CryptoError::MalformedInput)?;
    let master_secret: [u8; 32] = reader.array()?;
    let self_signing_secret: [u8; 32] = reader.array()?;
    let user_signing_secret: [u8; 32] = reader.array()?;
    let recovery_secret = reader.take(recovery_len)?;
    let backup = reader.take(backup_len)?;
    if !reader.is_finished()
        || ((flags & 1 != 0) == recovery_secret.is_empty())
        || ((flags & 2 != 0) == backup.is_empty())
        || SigningKey::from_bytes(&master_secret)
            .verifying_key()
            .to_bytes()
            != master_public
        || SigningKey::from_bytes(&self_signing_secret)
            .verifying_key()
            .to_bytes()
            != self_signing_public
        || SigningKey::from_bytes(&user_signing_secret)
            .verifying_key()
            .to_bytes()
            != user_signing_public
    {
        return Err(CryptoError::AuthenticationFailed);
    }
    provider.ed25519_verify(
        &master_public,
        &encode_master_signature(&CrossSigningIdentity {
            user_id: RawUuid::new(*expected_user_id),
            self_signing_public: &self_signing_public,
            user_signing_public: &user_signing_public,
        })?,
        &master_signature,
    )?;
    Ok(self_signing_secret)
}

fn device_auth_key(identity_secret: &[u8; 32]) -> CryptoResult<[u8; 32]> {
    let value = hkdf_sha256(&[0; 32], identity_secret, STATE_AUTH_DOMAIN, 32)?;
    value
        .as_slice()
        .try_into()
        .map_err(|_| CryptoError::InternalFailure)
}

fn valid_key_id(id: u32) -> CryptoResult<u32> {
    if id > KEY_ID_MAX {
        Err(CryptoError::MalformedInput)
    } else {
        Ok(id)
    }
}

fn encode_classical_signed(output: &mut Vec<u8>, key: &ClassicalSignedKey) {
    push_u32(output, key.id);
    push_u32(output, key.created_day);
    output.extend_from_slice(&key.public);
    output.extend_from_slice(&key.signature);
    output.extend_from_slice(&key.secret);
}

fn decode_classical_signed(reader: &mut Reader<'_>) -> CryptoResult<ClassicalSignedKey> {
    Ok(ClassicalSignedKey {
        id: valid_key_id(reader.u32()?)?,
        created_day: reader.u32()?,
        public: reader.array()?,
        signature: reader.array()?,
        secret: reader.array()?,
    })
}

fn encode_pq_signed(output: &mut Vec<u8>, key: &PqSignedKey) {
    push_u32(output, key.id);
    push_u32(output, key.created_day);
    output.extend_from_slice(&key.public);
    output.extend_from_slice(&key.signature);
    output.extend_from_slice(&key.secret);
}

fn decode_pq_signed(reader: &mut Reader<'_>) -> CryptoResult<PqSignedKey> {
    Ok(PqSignedKey {
        id: valid_key_id(reader.u32()?)?,
        created_day: reader.u32()?,
        public: reader.array()?,
        signature: reader.array()?,
        secret: reader.array()?,
    })
}

fn validate_sorted_classical(keys: &[ClassicalOneTimeKey]) -> CryptoResult<()> {
    if keys.windows(2).any(|pair| pair[0].id >= pair[1].id) {
        return Err(CryptoError::MalformedInput);
    }
    Ok(())
}

fn validate_sorted_pq(keys: &[PqOneTimeKey]) -> CryptoResult<()> {
    if keys.windows(2).any(|pair| pair[0].id >= pair[1].id) {
        return Err(CryptoError::MalformedInput);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use ed25519_dalek::SigningKey;

    use super::*;
    use crate::{
        device_signatures::{CrossSigningIdentity, RawUuid, encode_master_signature},
        enrollment::prepare_device_with_provider,
        provider::RustCryptoProvider,
        random::FixedRandomProvider,
    };

    const USER_ID: [u8; 16] = [0x77; 16];
    const DEVICE_ID: [u8; 16] = [0x88; 16];
    const DAY: u32 = 20_302;

    fn bytes(seed: u8, length: usize) -> Vec<u8> {
        (0..length)
            .map(|index| seed.wrapping_add(u8::try_from(index % 251).unwrap().wrapping_mul(29)))
            .collect()
    }

    fn provider(seed: u8, length: usize) -> RustCryptoProvider<FixedRandomProvider> {
        RustCryptoProvider::new(FixedRandomProvider::new(bytes(seed, length)))
    }

    fn identity_package() -> Vec<u8> {
        let crypto = RustCryptoProvider::default();
        let master = [0x31; 32];
        let self_signing = [0x42; 32];
        let user_signing = [0x53; 32];
        let master_public = SigningKey::from_bytes(&master).verifying_key().to_bytes();
        let self_signing_public = SigningKey::from_bytes(&self_signing)
            .verifying_key()
            .to_bytes();
        let user_signing_public = SigningKey::from_bytes(&user_signing)
            .verifying_key()
            .to_bytes();
        let signature = crypto
            .ed25519_sign(
                &SecretBytes::new(master),
                &encode_master_signature(&CrossSigningIdentity {
                    user_id: RawUuid::new(USER_ID),
                    self_signing_public: &self_signing_public,
                    user_signing_public: &user_signing_public,
                })
                .unwrap(),
            )
            .unwrap();
        let mut output = Vec::new();
        output.extend_from_slice(b"CPIDV001");
        output.push(0);
        output.extend_from_slice(&USER_ID);
        output.extend_from_slice(&master_public);
        output.extend_from_slice(&self_signing_public);
        output.extend_from_slice(&user_signing_public);
        output.extend_from_slice(&signature);
        push_u16(&mut output, 0);
        push_u32(&mut output, 0);
        output.extend_from_slice(&master);
        output.extend_from_slice(&self_signing);
        output.extend_from_slice(&user_signing);
        output
    }

    fn state() -> DeviceState {
        let package = prepare_device_with_provider(&provider(7, 20_000), &USER_ID).unwrap();
        decode_device_state(&RustCryptoProvider::default(), &package, DAY).unwrap()
    }

    #[test]
    fn replenishment_is_exact_retry_and_high_water_ids_never_reuse() {
        let mut state = state();
        let old_high_water = state.next_classical_one_time_id;
        let (batch, projection) =
            prepare_replenishment(&provider(17, 50_000), &mut state, 0, 0, 2, 2).unwrap();
        let encoded_once = encode_device_state(&state).unwrap();
        let (retry_batch, retry_projection) =
            prepare_replenishment(&provider(0, 0), &mut state, 200, 100, 200, 100).unwrap();
        assert_eq!(batch, retry_batch);
        assert_eq!(projection, retry_projection);
        assert_eq!(encoded_once, encode_device_state(&state).unwrap());
        commit_pending_upload(&mut state, &batch).unwrap();

        state.classical_one_time.clear();
        let (next_batch, next_projection) =
            prepare_replenishment(&provider(23, 50_000), &mut state, 0, 0, 1, 0).unwrap();
        assert_ne!(next_batch, batch);
        let mut reader = Reader::new(&next_projection);
        assert_eq!(reader.take(8).unwrap(), UPLOAD_MAGIC);
        reader.take(16 + 1 + 4).unwrap();
        assert_eq!(reader.u16().unwrap(), 1);
        assert!(reader.u32().unwrap() >= old_high_water);
    }

    #[test]
    fn signed_rotation_is_atomic_retried_and_retained_through_day_eight() {
        let mut state = state();
        // This test exercises the ordinary seven-day cadence. Legacy decode is
        // intentionally rotation-due and is covered separately below.
        state.current_classical.created_day = DAY;
        state.current_pq.created_day = DAY;
        assert!(matches!(
            prepare_rotation(
                &provider(31, 20_000),
                &mut state,
                &identity_package(),
                DEVICE_ID,
                DAY + 6,
            ),
            Err(CryptoError::StateViolation)
        ));
        let (batch, projection) = prepare_rotation(
            &provider(37, 50_000),
            &mut state,
            &identity_package(),
            DEVICE_ID,
            DAY + 7,
        )
        .unwrap();
        assert_eq!(state.bundle_version, 2);
        assert_eq!(state.retired.len(), 1);
        assert_eq!(state.retired[0].retain_through_day, DAY + 15);
        let (retry_batch, retry_projection) = prepare_rotation(
            &provider(0, 0),
            &mut state,
            &identity_package(),
            DEVICE_ID,
            DAY + 99,
        )
        .unwrap();
        assert_eq!(retry_batch, batch);
        assert_eq!(retry_projection, projection);
        let encoded = encode_device_state(&state).unwrap();
        let decoded = decode_device_state(&RustCryptoProvider::default(), &encoded, DAY).unwrap();
        assert_eq!(decoded.bundle_version, 2);
        assert_eq!(decoded.retired.len(), 1);

        state.prune_retired(DAY + 15);
        assert_eq!(state.retired.len(), 1);
        state.prune_retired(DAY + 16);
        assert!(state.retired.is_empty());
    }

    #[test]
    fn identity_substitution_cannot_authorize_rotation() {
        let mut state = state();
        let mut identity = identity_package();
        identity[8 + 1 + 16 + 32 + 5] ^= 1;
        assert!(matches!(
            prepare_rotation(
                &provider(41, 50_000),
                &mut state,
                &identity,
                DEVICE_ID,
                DAY + 7,
            ),
            Err(CryptoError::AuthenticationFailed)
        ));
    }

    #[test]
    fn legacy_upgrade_is_immediately_rotation_due_and_reports_authoritative_day() {
        let package = prepare_device_with_provider(&provider(73, 20_000), &USER_ID).unwrap();
        let mut migrated =
            decode_device_state(&RustCryptoProvider::default(), &package, DAY).unwrap();
        assert_eq!(migrated.current_classical.created_day, DAY - 7);
        assert_eq!(migrated.current_pq.created_day, DAY - 7);

        let old_bundle_version = migrated.bundle_version;
        prepare_rotation(
            &provider(79, 50_000),
            &mut migrated,
            &identity_package(),
            DEVICE_ID,
            DAY,
        )
        .unwrap();
        assert_eq!(migrated.bundle_version, old_bundle_version + 1);
        assert_eq!(migrated.current_classical.created_day, DAY);
        assert_eq!(migrated.current_pq.created_day, DAY);
    }
}
