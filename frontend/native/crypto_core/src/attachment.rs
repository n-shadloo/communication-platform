//! Bounded, stateful secretstream framing for encrypted attachments.
//!
//! Dart never implements the primitive. It supplies one bounded plaintext or
//! ciphertext chunk at a time and receives one bounded result chunk at a time.

use std::{
    collections::HashMap,
    sync::{Mutex, OnceLock},
};

use sha2::{Digest, Sha256};
use zeroize::Zeroize;

use crate::{
    error::{CryptoError, CryptoResult},
    protocol::Reader,
    provider::{
        CryptoProvider, RustCryptoProvider, SECRETSTREAM_ABYTES, SECRETSTREAM_HEADER_BYTES,
        SECRETSTREAM_KEY_BYTES, SecretStreamPull, SecretStreamPush, secretstream_pull,
        secretstream_pull_init, secretstream_push, secretstream_push_init,
    },
    secret::{SecretBytes, SecretVec},
};

pub const ATTACHMENT_MAX_IO_BYTES: usize = 262_144;
pub const ATTACHMENT_CHUNK_BYTES: usize = 64 * 1024;
pub const ATTACHMENT_HEADER_BYTES: usize = 66;
pub const ATTACHMENT_BUCKETS: [u64; 6] = [
    65_536, 262_144, 1_048_576, 4_194_304, 16_777_216, 67_108_864,
];

const REQUEST_CREATE: &[u8; 8] = b"CPARQ001";
const REQUEST_PUSH: &[u8; 8] = b"CPAPR001";
const REQUEST_PULL: &[u8; 8] = b"CPAPD001";
const REQUEST_CHUNK: &[u8; 8] = b"CPAPC001";
const REQUEST_CLOSE: &[u8; 8] = b"CPAPX001";
const REQUEST_RANDOM: &[u8; 8] = b"CPAPN001";

const RESPONSE_CREATE: &[u8; 8] = b"CPARE001";
const RESPONSE_CHUNK: &[u8; 8] = b"CPARO001";
const RESPONSE_CLOSE: &[u8; 8] = b"CPARX001";
const RESPONSE_RANDOM: &[u8; 8] = b"CPARN001";
const FORMAT_VERSION: u8 = 1;

#[derive(Clone, Copy)]
struct AttachmentHeader {
    bytes: [u8; ATTACHMENT_HEADER_BYTES],
    plaintext_size: u64,
    stream_size: u64,
    bucket_size: u64,
    chunk_size: u32,
}

enum Session {
    Push {
        stream: SecretStreamPush,
        header: AttachmentHeader,
        plaintext_seen: u64,
        stream_seen: u64,
        final_seen: bool,
    },
    Pull {
        stream: SecretStreamPull,
        header: AttachmentHeader,
        plaintext_seen: u64,
        stream_seen: u64,
        final_seen: bool,
    },
}

static SESSIONS: OnceLock<Mutex<HashMap<u64, Session>>> = OnceLock::new();

fn sessions() -> &'static Mutex<HashMap<u64, Session>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn operation(operation: u32, input: &[u8]) -> CryptoResult<Vec<u8>> {
    if input.len() > ATTACHMENT_MAX_IO_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    match operation {
        1 => create_push(input),
        2 => push_chunk(input),
        3 => create_pull(input),
        4 => pull_chunk(input),
        5 => close_session(input),
        6 => random_bytes(input),
        _ => Err(CryptoError::UnsupportedOperation),
    }
}

fn create_push(input: &[u8]) -> CryptoResult<Vec<u8>> {
    let mut reader = Reader::new(input);
    reader.expect(REQUEST_CREATE)?;
    let plaintext_size = reader.u64()?;
    let chunk_size = reader.u32()?;
    let bucket_size = reader.u64()?;
    let metadata = reader.framed()?;
    if metadata.len() > 4096 {
        return Err(CryptoError::InputTooLarge);
    }
    if !reader.is_finished() || chunk_size as usize != ATTACHMENT_CHUNK_BYTES {
        return Err(CryptoError::MalformedInput);
    }
    let metadata_hash = Sha256::digest(metadata);
    let stream_size = encrypted_stream_size(plaintext_size, chunk_size)?;
    if bucket_size != bucket_for_stream(stream_size)? {
        return Err(CryptoError::MalformedInput);
    }
    let header = make_header(
        plaintext_size,
        stream_size,
        bucket_size,
        chunk_size,
        metadata_hash.as_slice(),
    )?;
    let mut key = SecretBytes::zeroed();
    RustCryptoProvider::default().random_bytes(key.expose_mut())?;
    let (stream, stream_header) = secretstream_push_init(&key)?;
    let handle = allocate_handle(Session::Push {
        stream,
        header,
        plaintext_seen: 0,
        stream_seen: 0,
        final_seen: false,
    })?;
    let mut output = Vec::with_capacity(8 + 8 + 32 + ATTACHMENT_HEADER_BYTES + 24 + 8);
    output.extend_from_slice(RESPONSE_CREATE);
    output.extend_from_slice(&handle.to_be_bytes());
    output.extend_from_slice(key.expose());
    output.extend_from_slice(&header.bytes);
    output.extend_from_slice(&stream_header);
    output.extend_from_slice(&stream_size.to_be_bytes());
    Ok(output)
}

fn push_chunk(input: &[u8]) -> CryptoResult<Vec<u8>> {
    let mut reader = Reader::new(input);
    reader.expect(REQUEST_PUSH)?;
    let handle = reader.u64()?;
    let final_message = reader.u8()? != 0;
    let plaintext = reader.take(reader.remaining())?;
    if plaintext.len() > ATTACHMENT_CHUNK_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    let mut locked = sessions()
        .lock()
        .map_err(|_| CryptoError::InternalFailure)?;
    let session = locked.get_mut(&handle).ok_or(CryptoError::InvalidHandle)?;
    let Session::Push {
        stream,
        header,
        plaintext_seen,
        stream_seen,
        final_seen,
    } = session
    else {
        return Err(CryptoError::WrongHandleType);
    };
    if *final_seen || (*plaintext_seen + plaintext.len() as u64 > header.plaintext_size) {
        return Err(CryptoError::StateViolation);
    }
    if !final_message && *plaintext_seen + plaintext.len() as u64 >= header.plaintext_size {
        return Err(CryptoError::StateViolation);
    }
    if final_message && *plaintext_seen + plaintext.len() as u64 != header.plaintext_size {
        return Err(CryptoError::StateViolation);
    }
    let encrypted = secretstream_push(
        stream,
        &SecretVec::input(plaintext)?,
        &header.bytes,
        final_message,
    )?;
    *plaintext_seen += plaintext.len() as u64;
    *stream_seen += encrypted.len() as u64;
    if *stream_seen > header.stream_size {
        return Err(CryptoError::StateViolation);
    }
    *final_seen = final_message;
    let mut output = Vec::with_capacity(8 + 1 + encrypted.len());
    output.extend_from_slice(RESPONSE_CHUNK);
    output.push(0);
    output.extend_from_slice(&encrypted);
    Ok(output)
}

fn create_pull(input: &[u8]) -> CryptoResult<Vec<u8>> {
    let mut reader = Reader::new(input);
    reader.expect(REQUEST_PULL)?;
    let key: [u8; SECRETSTREAM_KEY_BYTES] = reader.array()?;
    let header_bytes: [u8; ATTACHMENT_HEADER_BYTES] = reader.array()?;
    let stream_header: [u8; SECRETSTREAM_HEADER_BYTES] = reader.array()?;
    let metadata = reader.framed()?;
    if metadata.len() > 4096 {
        return Err(CryptoError::InputTooLarge);
    }
    if !reader.is_finished() {
        return Err(CryptoError::MalformedInput);
    }
    let header = parse_header(&header_bytes)?;
    if Sha256::digest(metadata).as_slice() != &header.bytes[34..66] {
        return Err(CryptoError::AuthenticationFailed);
    }
    let stream = secretstream_pull_init(&SecretBytes::new(key), &stream_header)?;
    let handle = allocate_handle(Session::Pull {
        stream,
        header,
        plaintext_seen: 0,
        stream_seen: 0,
        final_seen: false,
    })?;
    let mut output = Vec::with_capacity(16);
    output.extend_from_slice(RESPONSE_CREATE);
    output.extend_from_slice(&handle.to_be_bytes());
    Ok(output)
}

fn pull_chunk(input: &[u8]) -> CryptoResult<Vec<u8>> {
    let mut reader = Reader::new(input);
    reader.expect(REQUEST_CHUNK)?;
    let handle = reader.u64()?;
    let ciphertext = reader.take(reader.remaining())?;
    if ciphertext.len() < SECRETSTREAM_ABYTES {
        return Err(CryptoError::MalformedInput);
    }
    let mut locked = sessions()
        .lock()
        .map_err(|_| CryptoError::InternalFailure)?;
    let session = locked.get_mut(&handle).ok_or(CryptoError::InvalidHandle)?;
    let Session::Pull {
        stream,
        header,
        plaintext_seen,
        stream_seen,
        final_seen,
    } = session
    else {
        return Err(CryptoError::WrongHandleType);
    };
    if *final_seen || ciphertext.len() > ATTACHMENT_CHUNK_BYTES + SECRETSTREAM_ABYTES {
        return Err(CryptoError::StateViolation);
    }
    let (plaintext, final_message) = secretstream_pull(stream, ciphertext, &header.bytes)?;
    if *stream_seen + ciphertext.len() as u64 > header.stream_size
        || *plaintext_seen + plaintext.expose().len() as u64 > header.plaintext_size
    {
        return Err(CryptoError::StateViolation);
    }
    *stream_seen += ciphertext.len() as u64;
    *plaintext_seen += plaintext.expose().len() as u64;
    if final_message
        && (*stream_seen != header.stream_size || *plaintext_seen != header.plaintext_size)
    {
        return Err(CryptoError::StateViolation);
    }
    *final_seen = final_message;
    let mut output = Vec::with_capacity(9 + plaintext.expose().len());
    output.extend_from_slice(RESPONSE_CHUNK);
    output.push(u8::from(final_message));
    output.extend_from_slice(plaintext.expose());
    Ok(output)
}

fn close_session(input: &[u8]) -> CryptoResult<Vec<u8>> {
    let mut reader = Reader::new(input);
    reader.expect(REQUEST_CLOSE)?;
    let handle = reader.u64()?;
    let abort = reader.u8()? != 0;
    if !reader.is_finished() {
        return Err(CryptoError::MalformedInput);
    }
    let mut locked = sessions()
        .lock()
        .map_err(|_| CryptoError::InternalFailure)?;
    let completed = match locked.get(&handle) {
        Some(Session::Push { final_seen, .. } | Session::Pull { final_seen, .. }) => *final_seen,
        None => return Err(CryptoError::InvalidHandle),
    };
    if !abort && !completed {
        return Err(CryptoError::StateViolation);
    }
    locked.remove(&handle);
    Ok(RESPONSE_CLOSE.to_vec())
}

fn random_bytes(input: &[u8]) -> CryptoResult<Vec<u8>> {
    let mut reader = Reader::new(input);
    reader.expect(REQUEST_RANDOM)?;
    let length = usize::try_from(reader.u32()?).map_err(|_| CryptoError::InvalidArgument)?;
    if !reader.is_finished() || length > ATTACHMENT_CHUNK_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    let mut output = Vec::with_capacity(8 + length);
    output.extend_from_slice(RESPONSE_RANDOM);
    let mut bytes = vec![0u8; length];
    RustCryptoProvider::default().random_bytes(&mut bytes)?;
    output.extend_from_slice(&bytes);
    bytes.zeroize();
    Ok(output)
}

fn allocate_handle(session: Session) -> CryptoResult<u64> {
    let mut handle_bytes = [0u8; 8];
    RustCryptoProvider::default().random_bytes(&mut handle_bytes)?;
    let mut handle = u64::from_be_bytes(handle_bytes);
    if handle == 0 {
        handle = 1;
    }
    let mut locked = sessions()
        .lock()
        .map_err(|_| CryptoError::InternalFailure)?;
    if locked.len() >= 64 {
        return Err(CryptoError::ResourceExhausted);
    }
    if locked.contains_key(&handle) {
        return Err(CryptoError::ResourceExhausted);
    }
    locked.insert(handle, session);
    Ok(handle)
}

fn encrypted_stream_size(plaintext_size: u64, chunk_size: u32) -> CryptoResult<u64> {
    let chunk = u64::from(chunk_size);
    let chunk_count = if plaintext_size == 0 {
        1
    } else {
        plaintext_size
            .checked_add(chunk - 1)
            .ok_or(CryptoError::InputTooLarge)?
            / chunk
    };
    chunk_count
        .checked_mul(u64::try_from(SECRETSTREAM_ABYTES).map_err(|_| CryptoError::InternalFailure)?)
        .and_then(|value| value.checked_add(plaintext_size))
        .ok_or(CryptoError::InputTooLarge)
}

fn bucket_for_stream(stream_size: u64) -> CryptoResult<u64> {
    let required = stream_size
        .checked_add(
            u64::try_from(ATTACHMENT_HEADER_BYTES + SECRETSTREAM_HEADER_BYTES)
                .map_err(|_| CryptoError::InternalFailure)?,
        )
        .ok_or(CryptoError::InputTooLarge)?;
    ATTACHMENT_BUCKETS
        .into_iter()
        .find(|bucket| *bucket >= required)
        .ok_or(CryptoError::InputTooLarge)
}

fn make_header(
    plaintext_size: u64,
    stream_size: u64,
    bucket_size: u64,
    chunk_size: u32,
    metadata_hash: &[u8],
) -> CryptoResult<AttachmentHeader> {
    if metadata_hash.len() != 32
        || stream_size
            .checked_add(
                u64::try_from(ATTACHMENT_HEADER_BYTES + SECRETSTREAM_HEADER_BYTES).unwrap(),
            )
            .is_none_or(|required| required > bucket_size)
    {
        return Err(CryptoError::InputTooLarge);
    }
    let mut bytes = [0u8; ATTACHMENT_HEADER_BYTES];
    bytes[..8].copy_from_slice(b"CPAFV001");
    bytes[8] = FORMAT_VERSION;
    bytes[9] = 0;
    bytes[10..14].copy_from_slice(&chunk_size.to_be_bytes());
    bytes[14..22].copy_from_slice(&plaintext_size.to_be_bytes());
    bytes[22..30].copy_from_slice(&stream_size.to_be_bytes());
    bytes[30..34].copy_from_slice(&(bucket_size as u32).to_be_bytes());
    bytes[34..66].copy_from_slice(metadata_hash);
    Ok(AttachmentHeader {
        bytes,
        plaintext_size,
        stream_size,
        bucket_size,
        chunk_size,
    })
}

fn parse_header(bytes: &[u8; ATTACHMENT_HEADER_BYTES]) -> CryptoResult<AttachmentHeader> {
    if &bytes[..8] != b"CPAFV001" || bytes[8] != FORMAT_VERSION || bytes[9] != 0 {
        return Err(CryptoError::UnsupportedVersion);
    }
    let chunk_size = u32::from_be_bytes(bytes[10..14].try_into().unwrap());
    let plaintext_size = u64::from_be_bytes(bytes[14..22].try_into().unwrap());
    let stream_size = u64::from_be_bytes(bytes[22..30].try_into().unwrap());
    let bucket_size = u64::from(u32::from_be_bytes(bytes[30..34].try_into().unwrap()));
    if chunk_size as usize != ATTACHMENT_CHUNK_BYTES
        || bucket_for_stream(stream_size)? != bucket_size
        || encrypted_stream_size(plaintext_size, chunk_size)? != stream_size
    {
        return Err(CryptoError::MalformedInput);
    }
    make_header(
        plaintext_size,
        stream_size,
        bucket_size,
        chunk_size,
        &bytes[34..66],
    )
}

#[cfg(test)]
mod tests {
    use hex_literal::hex;

    use super::*;

    fn create_request(size: u64, bucket: u64, metadata: &[u8]) -> Vec<u8> {
        let mut request = Vec::new();
        request.extend_from_slice(REQUEST_CREATE);
        request.extend_from_slice(&size.to_be_bytes());
        request.extend_from_slice(&(ATTACHMENT_CHUNK_BYTES as u32).to_be_bytes());
        request.extend_from_slice(&bucket.to_be_bytes());
        request.extend_from_slice(&(metadata.len() as u32).to_be_bytes());
        request.extend_from_slice(metadata);
        request
    }

    fn pull_request(created: &[u8], metadata: &[u8]) -> Vec<u8> {
        let mut request = Vec::new();
        request.extend_from_slice(REQUEST_PULL);
        request.extend_from_slice(&created[16..48]);
        request.extend_from_slice(&created[48..114]);
        request.extend_from_slice(&created[114..138]);
        request.extend_from_slice(&(metadata.len() as u32).to_be_bytes());
        request.extend_from_slice(metadata);
        request
    }

    fn pull_chunk_request(handle: u64, ciphertext: &[u8]) -> Vec<u8> {
        let mut request = Vec::new();
        request.extend_from_slice(REQUEST_CHUNK);
        request.extend_from_slice(&handle.to_be_bytes());
        request.extend_from_slice(ciphertext);
        request
    }

    fn close_request(handle: u64, abort: bool) -> Vec<u8> {
        let mut request = Vec::new();
        request.extend_from_slice(REQUEST_CLOSE);
        request.extend_from_slice(&handle.to_be_bytes());
        request.push(u8::from(abort));
        request
    }

    #[test]
    fn header_and_stream_round_trip_are_bounded() {
        let plaintext = b"attachment test".to_vec();
        let stream_size =
            encrypted_stream_size(plaintext.len() as u64, ATTACHMENT_CHUNK_BYTES as u32).unwrap();
        let bucket = ATTACHMENT_BUCKETS
            .into_iter()
            .find(|bucket| {
                *bucket
                    >= (ATTACHMENT_HEADER_BYTES + SECRETSTREAM_HEADER_BYTES) as u64 + stream_size
            })
            .unwrap();
        let created =
            operation(1, &create_request(plaintext.len() as u64, bucket, b"meta")).unwrap();
        let handle = u64::from_be_bytes(created[8..16].try_into().unwrap());
        let key = &created[16..48];
        let header = &created[48..114];
        let stream_header = &created[114..138];
        assert_eq!(
            header,
            hex!(
                "4350414656303031 01 00 00010000
                 000000000000000f 0000000000000020 00010000
                 ea3bd73e2b506e00527232b3ed743c066da83a8e3066f62a71e75eb9b4aa1db6"
            )
        );
        let mut push = Vec::new();
        push.extend_from_slice(REQUEST_PUSH);
        push.extend_from_slice(&handle.to_be_bytes());
        push.push(1);
        push.extend_from_slice(&plaintext);
        let encrypted = operation(2, &push).unwrap();
        assert_eq!(
            operation(5, &close_request(handle, false)),
            Ok(RESPONSE_CLOSE.to_vec())
        );

        let mut pull_create_request = Vec::new();
        pull_create_request.extend_from_slice(REQUEST_PULL);
        pull_create_request.extend_from_slice(key);
        pull_create_request.extend_from_slice(header);
        pull_create_request.extend_from_slice(stream_header);
        pull_create_request.extend_from_slice(&4_u32.to_be_bytes());
        pull_create_request.extend_from_slice(b"meta");
        let pull_created = operation(3, &pull_create_request).unwrap();
        let pull_handle = u64::from_be_bytes(pull_created[8..16].try_into().unwrap());
        let mut pull = Vec::new();
        pull.extend_from_slice(REQUEST_CHUNK);
        pull.extend_from_slice(&pull_handle.to_be_bytes());
        pull.extend_from_slice(&encrypted[9..]);
        let decrypted = operation(4, &pull).unwrap();
        assert_eq!(&decrypted[9..], plaintext);
        assert_eq!(decrypted[8], 1);
        assert_eq!(
            operation(5, &close_request(pull_handle, false)),
            Ok(RESPONSE_CLOSE.to_vec())
        );

        assert_eq!(
            operation(3, &pull_request(&created, b"changed")),
            Err(CryptoError::AuthenticationFailed)
        );
    }

    #[test]
    fn truncation_and_reorder_fail() {
        let plaintext = vec![3u8; ATTACHMENT_CHUNK_BYTES * 2 + 7];
        let stream_size =
            encrypted_stream_size(plaintext.len() as u64, ATTACHMENT_CHUNK_BYTES as u32).unwrap();
        let bucket = ATTACHMENT_BUCKETS
            .into_iter()
            .find(|bucket| {
                *bucket
                    >= (ATTACHMENT_HEADER_BYTES + SECRETSTREAM_HEADER_BYTES) as u64 + stream_size
            })
            .unwrap();
        let created =
            operation(1, &create_request(plaintext.len() as u64, bucket, b"meta")).unwrap();
        let handle = u64::from_be_bytes(created[8..16].try_into().unwrap());
        let mut chunks = Vec::new();
        for (index, chunk) in plaintext.chunks(ATTACHMENT_CHUNK_BYTES).enumerate() {
            let mut request = Vec::new();
            request.extend_from_slice(REQUEST_PUSH);
            request.extend_from_slice(&handle.to_be_bytes());
            request.push(u8::from(
                index + 1 == plaintext.chunks(ATTACHMENT_CHUNK_BYTES).len(),
            ));
            request.extend_from_slice(chunk);
            chunks.push(operation(2, &request).unwrap());
        }
        assert_eq!(
            operation(5, &close_request(handle, false)),
            Ok(RESPONSE_CLOSE.to_vec())
        );

        let pull_created = operation(3, &pull_request(&created, b"meta")).unwrap();
        let pull_handle = u64::from_be_bytes(pull_created[8..16].try_into().unwrap());
        assert_eq!(
            operation(4, &pull_chunk_request(pull_handle, &chunks[1][9..])),
            Err(CryptoError::AuthenticationFailed)
        );
        let _ = operation(5, &close_request(pull_handle, true));

        let pull_created = operation(3, &pull_request(&created, b"meta")).unwrap();
        let pull_handle = u64::from_be_bytes(pull_created[8..16].try_into().unwrap());
        assert_eq!(
            operation(
                4,
                &pull_chunk_request(
                    pull_handle,
                    &chunks[0][9..chunks[0].len().saturating_sub(1)],
                ),
            ),
            Err(CryptoError::AuthenticationFailed)
        );
        let _ = operation(5, &close_request(pull_handle, true));

        let pull_created = operation(3, &pull_request(&created, b"meta")).unwrap();
        let pull_handle = u64::from_be_bytes(pull_created[8..16].try_into().unwrap());
        let mut corrupted = chunks[0][9..].to_vec();
        corrupted[0] ^= 1;
        assert_eq!(
            operation(4, &pull_chunk_request(pull_handle, &corrupted)),
            Err(CryptoError::AuthenticationFailed)
        );
        let _ = operation(5, &close_request(pull_handle, true));

        let pull_created = operation(3, &pull_request(&created, b"meta")).unwrap();
        let pull_handle = u64::from_be_bytes(pull_created[8..16].try_into().unwrap());
        for chunk in &chunks {
            operation(4, &pull_chunk_request(pull_handle, &chunk[9..])).unwrap();
        }
        assert_eq!(
            operation(4, &pull_chunk_request(pull_handle, &chunks[2][9..])),
            Err(CryptoError::StateViolation)
        );
        assert_eq!(
            operation(5, &close_request(pull_handle, false)),
            Ok(RESPONSE_CLOSE.to_vec())
        );

        let pull_created = operation(3, &pull_request(&created, b"meta")).unwrap();
        let pull_handle = u64::from_be_bytes(pull_created[8..16].try_into().unwrap());
        operation(4, &pull_chunk_request(pull_handle, &chunks[0][9..])).unwrap();
        assert_eq!(
            operation(5, &close_request(pull_handle, false)),
            Err(CryptoError::StateViolation)
        );
        assert_eq!(
            operation(5, &close_request(pull_handle, true)),
            Ok(RESPONSE_CLOSE.to_vec())
        );
    }
}
