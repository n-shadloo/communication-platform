//! One target per decoder an untrusted relay can reach.
//!
//! Trust boundary, verified against `docs/threat-model.md` and the request
//! layout in `mls_beta::operation`:
//!
//! | request field | source | fuzzed by |
//! |---|---|---|
//! | operation discriminator, magic, version, framing | local Dart adapter | `abi_entry`, `operation_envelope` |
//! | `opaque_device_state` | local storage, HMAC bound | `operation_envelope`, `device_state` |
//! | `local_bundle_request` | local storage | `operation_envelope` |
//! | additional bundle requests | peer bundles from the relay | `peer_bundle` |
//! | wrapped `KeyPackage`s | relay | `key_package_wrapper`, `create_group_tail` |
//! | Welcome | relay | `welcome_join` |
//! | MLS message to process | relay | `process_message` |
//! | MLS object to hash | relay | `mls_object_hash` |
//! | signed group control | relay | `group_control_verify`, `group_control_descriptor` |
//! | sealed group / `KeyPackage` state | local storage, AEAD bound | `state_restoration` |
//!
//! Sealed state is not relay reachable: it is XChaCha20-Poly1305 sealed under
//! a key derived from the device identity secret and bound to the device
//! signing key, so a relay cannot produce a value that opens. Its plaintext
//! layers are still fuzzed directly, because `docs/testing-strategy.md`
//! requires state-restoration fuzzing and a local storage-tamper attacker is a
//! separate boundary from the relay.

use std::ptr;

use crate::{
    enrollment::inspect_verified_claimed_device_bundle,
    mls_beta::{
        MLS_MAX_IO_BYTES, OP_CREATE_GROUP, OP_HASH_MLS_OBJECT, OP_JOIN_GROUP, OP_PROCESS_MESSAGE,
        OP_VERIFY_GROUP_CONTROL, OpaqueKeyPackageStorage, OpaqueMlsStateStorage, SealedStateKind,
        encode_group_control, import_group_state_envelope, open_device_secret_snapshot, operation,
        read_group_control_descriptor, tests::OPERATION_DAY, unwrap_key_package,
    },
    prekey_state::decode_device_state,
    protocol::{Reader, push_frame},
    provider::RustCryptoProvider,
};

use super::{Observation, fixture::Fixture};

/// How much work one input costs, which sets how many inputs a target gets.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Depth {
    /// Drives its decoder through the whole `operation` dispatcher, so every
    /// input also pays device-state decoding and peer-bundle signature
    /// verification. That is the realistic path, and it is the expensive one.
    Dispatcher,
    /// Calls one decoder directly. Orders of magnitude cheaper per input, so
    /// these targets earn proportionally more of the iteration budget.
    Decoder,
}

impl Depth {
    /// Chosen from the measured per-input cost of each class in the debug
    /// profile: a dispatcher input is roughly forty times a decoder input.
    const fn iteration_multiplier(self) -> u64 {
        match self {
            Self::Dispatcher => 1,
            Self::Decoder => 40,
        }
    }
}

/// One fuzz target: a name, its seed corpus, and the decoder it drives.
pub(crate) struct Target {
    pub(crate) name: &'static str,
    pub(crate) depth: Depth,
    pub(crate) seeds: fn(&Fixture) -> Vec<Vec<u8>>,
    pub(crate) run: fn(&Fixture, &[u8]) -> Observation,
}

impl Target {
    /// How many inputs this target runs for a base budget.
    pub(crate) fn iterations(&self, base: u64) -> u64 {
        base.saturating_mul(self.depth.iteration_multiplier())
    }

    /// Gives each target an independent mutation stream from one root seed.
    pub(crate) fn stream_seed(&self) -> u64 {
        let mut hash = 0xCBF2_9CE4_8422_2325_u64;
        for byte in self.name.as_bytes() {
            hash ^= u64::from(*byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01B3);
        }
        hash
    }
}

pub(crate) static TARGETS: &[Target] = &[
    Target {
        name: "abi_entry",
        depth: Depth::Dispatcher,
        seeds: abi_entry_seeds,
        run: abi_entry_run,
    },
    Target {
        name: "operation_envelope",
        depth: Depth::Dispatcher,
        seeds: operation_envelope_seeds,
        run: operation_envelope_run,
    },
    Target {
        name: "peer_bundle",
        depth: Depth::Decoder,
        seeds: peer_bundle_seeds,
        run: peer_bundle_run,
    },
    Target {
        name: "key_package_wrapper",
        depth: Depth::Decoder,
        seeds: key_package_wrapper_seeds,
        run: key_package_wrapper_run,
    },
    Target {
        name: "create_group_tail",
        depth: Depth::Dispatcher,
        seeds: create_group_tail_seeds,
        run: create_group_tail_run,
    },
    Target {
        name: "welcome_join",
        depth: Depth::Dispatcher,
        seeds: welcome_join_seeds,
        run: welcome_join_run,
    },
    Target {
        name: "process_message",
        depth: Depth::Dispatcher,
        seeds: process_message_seeds,
        run: process_message_run,
    },
    Target {
        name: "mls_object_hash",
        depth: Depth::Dispatcher,
        seeds: mls_object_hash_seeds,
        run: mls_object_hash_run,
    },
    Target {
        name: "group_control_verify",
        depth: Depth::Dispatcher,
        seeds: group_control_verify_seeds,
        run: group_control_verify_run,
    },
    Target {
        name: "state_restoration",
        depth: Depth::Decoder,
        seeds: state_restoration_seeds,
        run: state_restoration_run,
    },
    Target {
        name: "device_state",
        depth: Depth::Decoder,
        seeds: device_state_seeds,
        run: device_state_run,
    },
    Target {
        name: "group_control_descriptor",
        depth: Depth::Decoder,
        seeds: group_control_descriptor_seeds,
        run: group_control_descriptor_run,
    },
];

/// Turns a `Result` from `operation` into an observation.
fn observe(result: Result<Vec<u8>, crate::error::CryptoError>) -> Observation {
    match result {
        Ok(output) => Observation::accepted(output.len()),
        Err(error) => Observation::status(error.code()),
    }
}

/// Runs the operation-specific `tail` behind a genuine authenticated prefix.
fn with_prefix(prefix: Vec<u8>, discriminator: u32, tail: &[u8]) -> Observation {
    let mut request = prefix;
    request.extend_from_slice(tail);
    observe(operation(discriminator, &request))
}

/// Wraps `value` in one length-prefixed frame, saturating at the bound so a
/// mutated input can still express an over-long frame.
fn framed(value: &[u8]) -> Vec<u8> {
    let mut output = Vec::new();
    if push_frame(&mut output, value).is_err() {
        output.clear();
        output.extend_from_slice(&u32::MAX.to_be_bytes());
        output.extend_from_slice(value);
    }
    output
}

// -------------------------------------------------------------------------
// The C ABI entry point.
// -------------------------------------------------------------------------

/// Output-buffer sizes the ABI must survive, including the null buffer and
/// one byte short of the response.
const OUTPUT_SIZES: [usize; 5] = [0, 1, 64, 4_096, MLS_MAX_IO_BYTES];

fn abi_entry_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    let mut seeds = vec![Vec::new(), vec![0x00, 0x04]];
    for (discriminator, request) in &fixture.requests {
        for size in 0..OUTPUT_SIZES.len() {
            let mut seed = Vec::with_capacity(request.len() + 2);
            seed.push(u8::try_from(*discriminator).unwrap_or(u8::MAX));
            seed.push(u8::try_from(size).unwrap_or_default());
            seed.extend_from_slice(request);
            seeds.push(seed);
        }
    }
    seeds
}

fn abi_entry_run(_: &Fixture, input: &[u8]) -> Observation {
    let discriminator = u32::from(input.first().copied().unwrap_or_default());
    let size =
        OUTPUT_SIZES[usize::from(input.get(1).copied().unwrap_or_default()) % OUTPUT_SIZES.len()];
    let request = input.get(2..).unwrap_or_default();
    let mut output = vec![0_u8; size];
    let mut written = 0_usize;
    let output_pointer = if size == 0 {
        ptr::null_mut()
    } else {
        output.as_mut_ptr()
    };
    // SAFETY: `request` and `output` are live for the call, their lengths are
    // exactly the slices above, and `written` is one writable `usize`. This is
    // the same contract the Dart adapter upholds.
    let status = unsafe {
        crate::cp_crypto_v1_beta_mls_operation(
            discriminator,
            request.as_ptr(),
            request.len(),
            output_pointer,
            size,
            &raw mut written,
        )
    };
    assert!(
        status != 0 || written <= size,
        "the ABI reported success while writing {written} bytes into {size}"
    );
    Observation {
        status,
        produced: if status == 0 { written } else { 0 },
    }
}

// -------------------------------------------------------------------------
// The whole request envelope.
// -------------------------------------------------------------------------

fn operation_envelope_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    let mut seeds = vec![Vec::new()];
    for (discriminator, request) in &fixture.requests {
        let mut seed = Vec::with_capacity(request.len() + 1);
        seed.push(u8::try_from(*discriminator).unwrap_or(u8::MAX));
        seed.extend_from_slice(request);
        seeds.push(seed);
    }
    seeds
}

fn operation_envelope_run(_: &Fixture, input: &[u8]) -> Observation {
    let discriminator = u32::from(input.first().copied().unwrap_or_default());
    observe(operation(discriminator, input.get(1..).unwrap_or_default()))
}

// -------------------------------------------------------------------------
// Peer device bundles, which the relay serves.
// -------------------------------------------------------------------------

fn peer_bundle_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    vec![
        Vec::new(),
        b"CPBRV001".to_vec(),
        fixture.bob_bundle.clone(),
        fixture.alice_bundle.clone(),
    ]
}

fn peer_bundle_run(_: &Fixture, input: &[u8]) -> Observation {
    match inspect_verified_claimed_device_bundle(input) {
        Ok(bundle) => Observation::accepted(bundle.canonical_bundle.len()),
        Err(error) => Observation::status(error.code()),
    }
}

// -------------------------------------------------------------------------
// Published `KeyPackage` buckets, which the relay serves.
// -------------------------------------------------------------------------

fn key_package_wrapper_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    vec![
        Vec::new(),
        b"CPMKPV01".to_vec(),
        fixture.wrapped_key_package.clone(),
        vec![0; 4_096],
        vec![0; 16_384],
    ]
}

fn key_package_wrapper_run(_: &Fixture, input: &[u8]) -> Observation {
    match unwrap_key_package(input) {
        Ok((_, message, proof)) => Observation::accepted(
            message
                .to_bytes()
                .map(|bytes| bytes.len())
                .unwrap_or_default()
                + proof.len(),
        ),
        Err(error) => Observation::rejected_with(key_package_error_code(error)),
    }
}

const fn key_package_error_code(error: crate::mls_beta::BetaKeyPackageError) -> u8 {
    use crate::mls_beta::BetaKeyPackageError as Error;
    match error {
        Error::EntropyUnavailable => 0,
        Error::KindMismatch => 1,
        Error::Malformed => 2,
        Error::NonCanonical => 3,
        Error::NotKeyPackage => 4,
        Error::SuiteMismatch => 5,
        Error::TooLarge => 6,
        Error::UnsupportedVersion => 7,
        Error::WrongBucket => 8,
    }
}

// -------------------------------------------------------------------------
// Group creation from relay-served `KeyPackage`s.
// -------------------------------------------------------------------------

fn create_group_tail_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    let mut tail = 1_u16.to_be_bytes().to_vec();
    tail.extend_from_slice(&framed(&fixture.wrapped_key_package));
    tail.extend_from_slice(&framed(b"cp-fuzz-create"));
    vec![Vec::new(), tail]
}

fn create_group_tail_run(fixture: &Fixture, input: &[u8]) -> Observation {
    with_prefix(fixture.alice_prefix(), OP_CREATE_GROUP, input)
}

// -------------------------------------------------------------------------
// Welcome processing.
// -------------------------------------------------------------------------

fn welcome_join_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    vec![
        Vec::new(),
        fixture.welcome.clone(),
        fixture.commit.clone(),
        fixture.group_info.clone(),
    ]
}

fn welcome_join_run(fixture: &Fixture, input: &[u8]) -> Observation {
    let mut tail = framed(&fixture.bob_sealed_key_package_state);
    tail.extend_from_slice(&framed(input));
    with_prefix(fixture.bob_prefix(), OP_JOIN_GROUP, &tail)
}

// -------------------------------------------------------------------------
// Incoming group messages.
// -------------------------------------------------------------------------

fn process_message_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    vec![
        Vec::new(),
        fixture.application_message.clone(),
        fixture.commit.clone(),
        fixture.welcome.clone(),
        fixture.group_info.clone(),
    ]
}

fn process_message_run(fixture: &Fixture, input: &[u8]) -> Observation {
    let mut tail = framed(&fixture.bob_sealed_group_state);
    tail.extend_from_slice(&framed(input));
    with_prefix(fixture.bob_prefix(), OP_PROCESS_MESSAGE, &tail)
}

// -------------------------------------------------------------------------
// Bare MLS object hashing.
// -------------------------------------------------------------------------

fn mls_object_hash_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    vec![
        Vec::new(),
        fixture.commit.clone(),
        fixture.welcome.clone(),
        fixture.group_info.clone(),
        fixture.application_message.clone(),
    ]
}

fn mls_object_hash_run(fixture: &Fixture, input: &[u8]) -> Observation {
    with_prefix(
        fixture.alice_solo_prefix(),
        OP_HASH_MLS_OBJECT,
        &framed(input),
    )
}

// -------------------------------------------------------------------------
// Signed group-control transcripts.
// -------------------------------------------------------------------------

fn group_control_verify_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    vec![Vec::new(), fixture.group_control_tail.clone()]
}

fn group_control_verify_run(fixture: &Fixture, input: &[u8]) -> Observation {
    with_prefix(fixture.alice_solo_prefix(), OP_VERIFY_GROUP_CONTROL, input)
}

// -------------------------------------------------------------------------
// Persisted state restoration.
// -------------------------------------------------------------------------

fn state_restoration_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    let layers: [(u8, &Vec<u8>); 4] = [
        (0, &fixture.group_state_envelope),
        (1, &fixture.group_state_snapshot),
        (2, &fixture.key_package_store_snapshot),
        (3, &fixture.alice_sealed_group_state),
    ];
    let mut seeds = vec![Vec::new()];
    for (selector, layer) in layers {
        let mut seed = Vec::with_capacity(layer.len() + 1);
        seed.push(selector);
        seed.extend_from_slice(layer);
        seeds.push(seed);
    }
    seeds
}

fn state_restoration_run(fixture: &Fixture, input: &[u8]) -> Observation {
    let selector = input.first().copied().unwrap_or_default() % 4;
    let body = input.get(1..).unwrap_or_default();
    match selector {
        0 => match import_group_state_envelope(&fixture.alice_authentication, body) {
            Ok((_, group_id, _)) => Observation::accepted(group_id.len()),
            Err(error) => Observation::status(error.code()),
        },
        1 => match OpaqueMlsStateStorage::import_snapshot(body) {
            Ok((_, group_id)) => Observation::accepted(group_id.len()),
            Err(_) => Observation::rejected(),
        },
        2 => match OpaqueKeyPackageStorage::import_snapshot(body) {
            Ok(_) => Observation::accepted(0),
            Err(_) => Observation::rejected(),
        },
        _ => match open_device_secret_snapshot(
            &RustCryptoProvider::default(),
            &fixture.alice_state_key,
            SealedStateKind::Group,
            &fixture.alice_authentication,
            body,
        ) {
            Ok(plaintext) => Observation::accepted(plaintext.expose().len()),
            Err(error) => Observation::status(error.code()),
        },
    }
}

// -------------------------------------------------------------------------
// Persisted device state.
// -------------------------------------------------------------------------

/// `decode_device_state` parses the whole record before it checks the HMAC
/// tag, so every field reader here is genuinely reachable with a tampered
/// local state and is worth driving at decoder speed rather than only through
/// the dispatcher.
fn device_state_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    vec![
        Vec::new(),
        b"CPDVV001".to_vec(),
        b"CPDVV002".to_vec(),
        fixture.alice_state.clone(),
        fixture.bob_state.clone(),
    ]
}

fn device_state_run(_: &Fixture, input: &[u8]) -> Observation {
    match decode_device_state(&RustCryptoProvider::default(), input, OPERATION_DAY) {
        Ok(_) => Observation::accepted(0),
        Err(error) => Observation::status(error.code()),
    }
}

// -------------------------------------------------------------------------
// The group-control descriptor readers.
// -------------------------------------------------------------------------

fn group_control_descriptor_seeds(fixture: &Fixture) -> Vec<Vec<u8>> {
    vec![Vec::new(), fixture.group_control_descriptor.clone()]
}

/// Drives the descriptor, metadata, member, text, and policy readers directly,
/// and checks the two invariants the reader promises plus the determinism the
/// signature depends on. A descriptor that encodes differently on a second
/// call would let one signature cover two meanings.
fn group_control_descriptor_run(_: &Fixture, input: &[u8]) -> Observation {
    const SIGNER_USER: [u8; 16] = [0x41; 16];
    const SIGNER_DEVICE: [u8; 16] = [0x51; 16];

    let mut reader = Reader::new(input);
    let Ok(descriptor) = read_group_control_descriptor(&mut reader, SIGNER_USER, SIGNER_DEVICE)
    else {
        return Observation::rejected();
    };
    assert!(
        descriptor.revision != 0,
        "the reader accepted revision zero"
    );
    assert!(
        descriptor.operation.changes_membership() == descriptor.mls_commit_hash.is_some(),
        "the reader accepted a descriptor whose Commit hash and membership          change disagree"
    );
    match (
        encode_group_control(&descriptor),
        encode_group_control(&descriptor),
    ) {
        (Ok(first), Ok(second)) => {
            assert_eq!(
                first, second,
                "the canonical control encoding is not deterministic"
            );
            Observation::accepted(first.len())
        }
        (Err(error), _) | (_, Err(error)) => Observation::status(error.code()),
    }
}

#[cfg(test)]
mod tests {
    use super::{Fixture, TARGETS};

    #[test]
    fn every_target_has_a_distinct_name_and_stream() {
        let mut names: Vec<&str> = TARGETS.iter().map(|target| target.name).collect();
        let count = names.len();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), count, "target names must be distinct");

        let mut streams: Vec<u64> = TARGETS.iter().map(super::Target::stream_seed).collect();
        streams.sort_unstable();
        streams.dedup();
        assert_eq!(streams.len(), count, "target streams must be distinct");
    }

    #[test]
    fn every_target_accepts_at_least_one_of_its_own_seeds() {
        let fixture = Fixture::shared();
        for target in TARGETS {
            let seeds = (target.seeds)(fixture);
            assert!(!seeds.is_empty(), "{} has no seed", target.name);
            assert!(
                seeds
                    .iter()
                    .any(|seed| (target.run)(fixture, seed).status == 0),
                "{} never accepts one of its own seeds, so its mutations would \
                 only ever exercise the outermost rejection",
                target.name
            );
        }
    }
}
