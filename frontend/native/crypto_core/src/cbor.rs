use minicbor::{data::Type, decode::Decoder, encode::Encoder};

use crate::{
    bounds::{BoundedBytes, MAX_CBOR_BYTES, MAX_CBOR_ITEMS},
    error::{CryptoError, CryptoResult},
};

#[derive(Clone, Eq, PartialEq)]
pub struct FoundationRecord {
    pub version: u8,
    pub kind: u8,
    pub payload: Vec<u8>,
}

impl std::fmt::Debug for FoundationRecord {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("FoundationRecord")
            .field("version", &self.version)
            .field("kind", &self.kind)
            .field("payload_len", &self.payload.len())
            .finish()
    }
}

pub fn encode_foundation_record(version: u8, kind: u8, payload: &[u8]) -> CryptoResult<Vec<u8>> {
    let bounded = BoundedBytes::new(payload, MAX_CBOR_BYTES)?;
    let capacity = payload
        .len()
        .checked_add(16)
        .ok_or(CryptoError::InputTooLarge)?;
    let mut encoded = Vec::new();
    encoded
        .try_reserve_exact(capacity)
        .map_err(|_| CryptoError::ResourceExhausted)?;
    let mut writer = Encoder::new(&mut encoded);
    writer.map(3).map_err(|_| CryptoError::InternalFailure)?;
    writer.u8(0).map_err(|_| CryptoError::InternalFailure)?;
    writer
        .u8(version)
        .map_err(|_| CryptoError::InternalFailure)?;
    writer.u8(1).map_err(|_| CryptoError::InternalFailure)?;
    writer.u8(kind).map_err(|_| CryptoError::InternalFailure)?;
    writer.u8(2).map_err(|_| CryptoError::InternalFailure)?;
    writer
        .bytes(bounded.as_slice())
        .map_err(|_| CryptoError::InternalFailure)?;
    if encoded.len() > MAX_CBOR_BYTES {
        return Err(CryptoError::InputTooLarge);
    }
    Ok(encoded)
}

pub fn decode_foundation_record(input: &[u8]) -> CryptoResult<FoundationRecord> {
    let bounded = BoundedBytes::new(input, MAX_CBOR_BYTES)?;
    let mut decoder = Decoder::new(bounded.as_slice());
    if bounded.as_slice().first() != Some(&0xa3) {
        return Err(CryptoError::MalformedInput);
    }
    let map_len = decoder.map().map_err(|_| CryptoError::MalformedInput)?;
    if map_len != Some(3) {
        return Err(CryptoError::MalformedInput);
    }

    let mut next_key = 0u8;
    let mut version = None;
    let mut kind = None;
    let mut payload = None;
    for _ in 0..MAX_CBOR_ITEMS.min(3) {
        let key = read_canonical_u8(&mut decoder)?;
        if key != next_key {
            return Err(CryptoError::MalformedInput);
        }
        next_key = next_key.saturating_add(1);
        match key {
            0 => version = Some(read_canonical_u8(&mut decoder)?),
            1 => kind = Some(read_canonical_u8(&mut decoder)?),
            2 => {
                let bytes = read_canonical_bytes(&mut decoder)?;
                if bytes.len() > MAX_CBOR_BYTES {
                    return Err(CryptoError::InputTooLarge);
                }
                let mut owned = Vec::new();
                owned
                    .try_reserve_exact(bytes.len())
                    .map_err(|_| CryptoError::ResourceExhausted)?;
                owned.extend_from_slice(bytes);
                payload = Some(owned);
            }
            _ => return Err(CryptoError::MalformedInput),
        }
    }

    if decoder.position() != bounded.as_slice().len()
        || version.is_none()
        || kind.is_none()
        || payload.is_none()
    {
        return Err(CryptoError::MalformedInput);
    }

    Ok(FoundationRecord {
        version: version.ok_or(CryptoError::MalformedInput)?,
        kind: kind.ok_or(CryptoError::MalformedInput)?,
        payload: payload.ok_or(CryptoError::MalformedInput)?,
    })
}

fn read_canonical_u8(decoder: &mut Decoder<'_>) -> CryptoResult<u8> {
    let first = *decoder
        .input()
        .get(decoder.position())
        .ok_or(CryptoError::MalformedInput)?;
    if first > 23 {
        return Err(CryptoError::MalformedInput);
    }
    if decoder
        .datatype()
        .map_err(|_| CryptoError::MalformedInput)?
        != Type::U8
    {
        return Err(CryptoError::MalformedInput);
    }
    decoder.u8().map_err(|_| CryptoError::MalformedInput)
}

fn read_canonical_bytes<'a>(decoder: &mut Decoder<'a>) -> CryptoResult<&'a [u8]> {
    let input = decoder.input();
    let position = decoder.position();
    let first = *input.get(position).ok_or(CryptoError::MalformedInput)?;
    if first >> 5 != 2 {
        return Err(CryptoError::MalformedInput);
    }
    let additional = first & 0x1f;
    let header_len = match additional {
        0..=23 => 1,
        24 => 2,
        25 => 3,
        26 => 5,
        27 => 9,
        _ => return Err(CryptoError::MalformedInput),
    };
    let declared_len = match header_len {
        1 => usize::from(additional),
        2 => usize::from(*input.get(position + 1).ok_or(CryptoError::MalformedInput)?),
        3 => usize::from(u16::from_be_bytes([
            *input.get(position + 1).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 2).ok_or(CryptoError::MalformedInput)?,
        ])),
        5 => usize::try_from(u32::from_be_bytes([
            *input.get(position + 1).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 2).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 3).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 4).ok_or(CryptoError::MalformedInput)?,
        ]))
        .map_err(|_| CryptoError::MalformedInput)?,
        9 => usize::try_from(u64::from_be_bytes([
            *input.get(position + 1).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 2).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 3).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 4).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 5).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 6).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 7).ok_or(CryptoError::MalformedInput)?,
            *input.get(position + 8).ok_or(CryptoError::MalformedInput)?,
        ]))
        .map_err(|_| CryptoError::MalformedInput)?,
        _ => return Err(CryptoError::MalformedInput),
    };
    let canonical = match declared_len {
        0..=23 => header_len == 1,
        24..=0xff => header_len == 2,
        0x100..=0xffff => header_len == 3,
        0x1_0000..=0xffff_ffff => header_len == 5,
        _ => header_len == 9,
    };
    if !canonical {
        return Err(CryptoError::MalformedInput);
    }
    decoder.bytes().map_err(|_| CryptoError::MalformedInput)
}

#[cfg(test)]
mod tests {
    use super::{decode_foundation_record, encode_foundation_record};
    use crate::error::CryptoError;

    #[test]
    fn typed_record_is_deterministic() {
        let encoded = encode_foundation_record(1, 7, b"payload").unwrap();
        assert_eq!(
            encoded,
            [
                0xa3, 0x00, 0x01, 0x01, 0x07, 0x02, 0x47, b'p', b'a', b'y', b'l', b'o', b'a', b'd'
            ]
        );
        assert_eq!(
            decode_foundation_record(&encoded).unwrap(),
            super::FoundationRecord {
                version: 1,
                kind: 7,
                payload: b"payload".to_vec()
            }
        );
    }

    #[test]
    fn rejects_indefinite_maps_noncanonical_encodings_and_trailing_bytes() {
        for input in [
            vec![0xbf, 0x00, 0x01, 0x01, 0x07, 0x02, 0x40, 0xff],
            vec![0xa3, 0x01, 0x01, 0x00, 0x07, 0x02, 0x40],
            vec![0xa3, 0x18, 0x00, 0x01, 0x01, 0x07, 0x02, 0x40],
            vec![0xa3, 0x00, 0x18, 0x01, 0x01, 0x07, 0x02, 0x40],
            vec![0xa3, 0x00, 0x01, 0x01, 0x07, 0x02, 0x58, 0x00],
            vec![0xa3, 0x00, 0x01, 0x01, 0x07, 0x02, 0x40, 0x00],
        ] {
            assert_eq!(
                decode_foundation_record(&input),
                Err(CryptoError::MalformedInput)
            );
        }
    }

    #[test]
    fn rejects_oversized_payload_before_encoding() {
        let payload = vec![0u8; crate::bounds::MAX_CBOR_BYTES + 1];
        assert_eq!(
            encode_foundation_record(1, 1, &payload),
            Err(CryptoError::InputTooLarge)
        );
    }

    #[test]
    fn accepts_the_largest_record_that_fits_the_cbor_boundary() {
        // map + three one-byte keys + two one-byte values + a five-byte
        // byte-string header = eleven bytes of deterministic encoding overhead.
        let payload = vec![0x5a; crate::bounds::MAX_CBOR_BYTES - 11];
        let encoded = encode_foundation_record(1, 1, &payload).unwrap();
        assert_eq!(encoded.len(), crate::bounds::MAX_CBOR_BYTES);
        let decoded = decode_foundation_record(&encoded).unwrap();
        assert_eq!(decoded.payload.len(), payload.len());

        let oversized_input = vec![0u8; crate::bounds::MAX_CBOR_BYTES + 1];
        assert_eq!(
            decode_foundation_record(&oversized_input),
            Err(CryptoError::InputTooLarge)
        );
    }
}
