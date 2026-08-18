//! Real closed-beta protocol artifacts, built once per test process.
//!
//! Fuzzing the beta operations from random bytes is worthless: the dispatcher
//! rejects anything that fails the magic, the version, the device-state HMAC,
//! and the peer bundle signatures long before a decoder under test runs. The
//! harness therefore builds one genuine two-device group with the engine
//! itself, then mutates only the fields an untrusted relay actually supplies.
//!
//! Every artifact here comes from `operation`, never from hand-written bytes,
//! so the seed corpus cannot drift away from the wire format.

use std::sync::OnceLock;

use crate::{
    error::CryptoError,
    mls_beta::{
        BetaMlsAuthenticationContext, GROUP_STATE_ENVELOPE_MAGIC, OP_CREATE_GROUP,
        OP_GENERATE_CONSUMABLE_KEY_PACKAGES, OP_JOIN_GROUP, OP_PROCESS_MESSAGE,
        OP_SEND_APPLICATION, OP_SIGN_GROUP_CONTROL, OP_VERIFY_GROUP_CONTROL,
        OPERATION_RESPONSE_MAGIC, OPERATION_VERSION, SealedStateKind, derive_state_key,
        open_device_secret_snapshot, operation,
        tests::{
            OPERATION_DAY, enrolled_operation_device, operation_prefix,
            push_group_control_descriptor,
        },
    },
    protocol::{Reader, push_frame, push_u16},
    provider::RustCryptoProvider,
    secret::SecretBytes,
};

const ALICE_USER: [u8; 16] = [0x41; 16];
const ALICE_DEVICE: [u8; 16] = [0x51; 16];
const BOB_USER: [u8; 16] = [0x42; 16];
const BOB_DEVICE: [u8; 16] = [0x52; 16];

/// One built beta group and every value a relay can put in front of it.
pub(crate) struct Fixture {
    pub(crate) alice_state: Vec<u8>,
    pub(crate) alice_bundle: Vec<u8>,
    pub(crate) bob_state: Vec<u8>,
    pub(crate) bob_bundle: Vec<u8>,
    /// A padded, bucket-sized wrapped `KeyPackage`, exactly as published.
    pub(crate) wrapped_key_package: Vec<u8>,
    pub(crate) bob_sealed_key_package_state: Vec<u8>,
    pub(crate) alice_sealed_group_state: Vec<u8>,
    pub(crate) bob_sealed_group_state: Vec<u8>,
    pub(crate) welcome: Vec<u8>,
    pub(crate) commit: Vec<u8>,
    pub(crate) group_info: Vec<u8>,
    /// A `PrivateMessage` Alice sent that Bob can genuinely process.
    pub(crate) application_message: Vec<u8>,
    /// A complete, signature-valid `OP_VERIFY_GROUP_CONTROL` tail.
    pub(crate) group_control_tail: Vec<u8>,
    /// Just the descriptor inside that tail, for the direct reader target.
    pub(crate) group_control_descriptor: Vec<u8>,
    /// The `CPMLSG01` plaintext inside the sealed group state.
    pub(crate) group_state_envelope: Vec<u8>,
    /// The `CPMLSV01` snapshot nested inside that envelope.
    pub(crate) group_state_snapshot: Vec<u8>,
    /// The `CPMLSK01` plaintext inside the sealed `KeyPackage` state.
    pub(crate) key_package_store_snapshot: Vec<u8>,
    /// One complete valid request per reachable operation discriminator.
    pub(crate) requests: Vec<(u32, Vec<u8>)>,
    /// The context the state-restoration decoders authenticate against.
    pub(crate) alice_authentication: BetaMlsAuthenticationContext,
    pub(crate) alice_state_key: SecretBytes<32>,
}

impl Fixture {
    pub(crate) fn shared() -> &'static Self {
        static FIXTURE: OnceLock<Fixture> = OnceLock::new();
        FIXTURE.get_or_init(Self::build)
    }

    /// A request prefix that authenticates Alice and admits Bob as a peer.
    pub(crate) fn alice_prefix(&self) -> Vec<u8> {
        operation_prefix(
            &self.alice_state,
            &self.alice_bundle,
            &[self.bob_bundle.as_slice()],
        )
    }

    /// A request prefix that authenticates Alice alone. Operations that only
    /// parse a relay-supplied object need no peer directory, and skipping one
    /// costs four fewer signature verifications per fuzz input.
    pub(crate) fn alice_solo_prefix(&self) -> Vec<u8> {
        operation_prefix(&self.alice_state, &self.alice_bundle, &[])
    }

    /// A request prefix that authenticates Bob and admits Alice as a peer.
    pub(crate) fn bob_prefix(&self) -> Vec<u8> {
        operation_prefix(
            &self.bob_state,
            &self.bob_bundle,
            &[self.alice_bundle.as_slice()],
        )
    }

    #[allow(clippy::too_many_lines)] // Building the group is one linear script; splitting it hides the order.
    fn build() -> Self {
        let (alice_state, alice_bundle) = enrolled_operation_device(ALICE_USER, ALICE_DEVICE, 211);
        let (bob_state, bob_bundle) = enrolled_operation_device(BOB_USER, BOB_DEVICE, 233);

        let mut generate = operation_prefix(&bob_state, &bob_bundle, &[]);
        generate.push(0);
        push_u16(&mut generate, 1);
        let generated = run(OP_GENERATE_CONSUMABLE_KEY_PACKAGES, &generate);
        let (bob_sealed_key_package_state, wrapped_key_packages) =
            decode_generated(OP_GENERATE_CONSUMABLE_KEY_PACKAGES, &generated);
        let wrapped_key_package = wrapped_key_packages
            .into_iter()
            .next()
            .expect("the fixture generates one wrapped KeyPackage");

        let alice_prefix = operation_prefix(&alice_state, &alice_bundle, &[bob_bundle.as_slice()]);
        let bob_prefix = operation_prefix(&bob_state, &bob_bundle, &[alice_bundle.as_slice()]);

        let mut create = alice_prefix.clone();
        push_u16(&mut create, 1);
        frame(&mut create, &wrapped_key_package);
        frame(&mut create, b"cp-fuzz-create");
        let created = run(OP_CREATE_GROUP, &create);
        let created = decode_commit(OP_CREATE_GROUP, &created);
        let welcome = created
            .welcomes
            .into_iter()
            .next()
            .expect("creating the group produces one Welcome");

        let mut join = bob_prefix.clone();
        frame(&mut join, &bob_sealed_key_package_state);
        frame(&mut join, &welcome);
        let joined = run(OP_JOIN_GROUP, &join);
        let bob_sealed_group_state = decode_joined(&joined);

        let mut send = alice_prefix.clone();
        frame(&mut send, &created.sealed_state);
        frame(&mut send, b"cp-fuzz-application-plaintext");
        frame(&mut send, b"cp-fuzz-authenticated-data");
        let application_response = run(OP_SEND_APPLICATION, &send);
        let (alice_sealed_group_state, application_message) =
            decode_message(OP_SEND_APPLICATION, &application_response);

        let mut descriptor = Vec::new();
        push_group_control_descriptor(
            &mut descriptor,
            [(ALICE_USER, ALICE_DEVICE), (BOB_USER, BOB_DEVICE)],
        );
        let mut sign = alice_prefix.clone();
        sign.extend_from_slice(&descriptor);
        let signed = run(OP_SIGN_GROUP_CONTROL, &sign);
        let payload = decode_signed_control(OP_SIGN_GROUP_CONTROL, &signed);
        let mut group_control_tail = Vec::new();
        frame(&mut group_control_tail, &ALICE_USER);
        frame(&mut group_control_tail, &ALICE_DEVICE);
        group_control_tail.extend_from_slice(&descriptor);
        frame(&mut group_control_tail, &payload);

        let plaintext = open_plaintext_state(&PlaintextStateInputs {
            alice_state: &alice_state,
            alice_bundle: &alice_bundle,
            bob_bundle: &bob_bundle,
            alice_sealed_group_state: &alice_sealed_group_state,
            bob_state: &bob_state,
            bob_sealed_key_package_state: &bob_sealed_key_package_state,
        });
        let group_state_snapshot = nested_snapshot(&plaintext.group_state_envelope);

        let mut process = bob_prefix;
        frame(&mut process, &bob_sealed_group_state);
        frame(&mut process, &application_message);

        let mut verify = alice_prefix;
        verify.extend_from_slice(&group_control_tail);

        let requests = vec![
            (OP_GENERATE_CONSUMABLE_KEY_PACKAGES, generate),
            (OP_CREATE_GROUP, create),
            (OP_JOIN_GROUP, join),
            (OP_SEND_APPLICATION, send),
            (OP_PROCESS_MESSAGE, process),
            (OP_SIGN_GROUP_CONTROL, sign),
            (OP_VERIFY_GROUP_CONTROL, verify),
        ];

        Self {
            alice_state,
            alice_bundle,
            bob_state,
            bob_bundle,
            wrapped_key_package,
            bob_sealed_key_package_state,
            alice_sealed_group_state,
            bob_sealed_group_state,
            welcome,
            commit: created.commit,
            group_info: created.group_info,
            application_message,
            group_control_tail,
            group_control_descriptor: descriptor,
            group_state_envelope: plaintext.group_state_envelope,
            group_state_snapshot,
            key_package_store_snapshot: plaintext.key_package_store_snapshot,
            requests,
            alice_authentication: plaintext.alice_authentication,
            alice_state_key: plaintext.alice_state_key,
        }
    }
}

fn run(discriminator: u32, request: &[u8]) -> Vec<u8> {
    operation(discriminator, request)
        .unwrap_or_else(|error| panic!("fixture operation {discriminator} failed: {error:?}"))
}

fn frame(output: &mut Vec<u8>, value: &[u8]) {
    push_frame(output, value).expect("the fixture stays inside the frame bound");
}

fn response(discriminator: u32, bytes: &[u8]) -> Reader<'_> {
    let mut reader = Reader::new(bytes);
    reader
        .expect(OPERATION_RESPONSE_MAGIC)
        .expect("operation response magic");
    assert_eq!(
        reader.u16().expect("operation response version"),
        OPERATION_VERSION
    );
    assert_eq!(
        u32::from(reader.u8().expect("operation response discriminator")),
        discriminator
    );
    reader
}

fn decode_generated(discriminator: u32, bytes: &[u8]) -> (Vec<u8>, Vec<Vec<u8>>) {
    let mut reader = response(discriminator, bytes);
    let state = reader.framed().expect("sealed KeyPackage state").to_vec();
    let count = usize::from(reader.u16().expect("KeyPackage count"));
    let packages = (0..count)
        .map(|_| reader.framed().expect("wrapped KeyPackage").to_vec())
        .collect();
    assert!(reader.is_finished());
    (state, packages)
}

struct CommitResponse {
    sealed_state: Vec<u8>,
    commit: Vec<u8>,
    welcomes: Vec<Vec<u8>>,
    group_info: Vec<u8>,
}

fn decode_commit(discriminator: u32, bytes: &[u8]) -> CommitResponse {
    let mut reader = response(discriminator, bytes);
    let sealed_state = reader.framed().expect("sealed group state").to_vec();
    let commit = reader.framed().expect("Commit message").to_vec();
    reader.framed().expect("Commit digest");
    let proofs = usize::from(reader.u16().expect("authentication proof count"));
    for _ in 0..proofs {
        reader.framed().expect("authentication proof");
    }
    let welcome_count = usize::from(reader.u16().expect("Welcome count"));
    let welcomes = (0..welcome_count)
        .map(|_| reader.framed().expect("Welcome message").to_vec())
        .collect();
    let group_info = reader.framed().expect("GroupInfo message").to_vec();
    CommitResponse {
        sealed_state,
        commit,
        welcomes,
        group_info,
    }
}

fn decode_joined(bytes: &[u8]) -> Vec<u8> {
    let mut reader = response(OP_JOIN_GROUP, bytes);
    reader.framed().expect("sealed group state").to_vec()
}

fn decode_message(discriminator: u32, bytes: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let mut reader = response(discriminator, bytes);
    let sealed_state = reader.framed().expect("sealed group state").to_vec();
    let message = reader.framed().expect("MLS message").to_vec();
    (sealed_state, message)
}

/// Returns the signed control payload, which is the exact value a peer
/// receives through the relay and hands back to `OP_VERIFY_GROUP_CONTROL`.
fn decode_signed_control(discriminator: u32, bytes: &[u8]) -> Vec<u8> {
    let mut reader = response(discriminator, bytes);
    reader.framed().expect("canonical control");
    reader.framed().expect("control signature");
    reader.framed().expect("control state hash");
    reader.framed().expect("control payload").to_vec()
}

struct PlaintextStateInputs<'a> {
    alice_state: &'a [u8],
    alice_bundle: &'a [u8],
    bob_bundle: &'a [u8],
    alice_sealed_group_state: &'a [u8],
    bob_state: &'a [u8],
    bob_sealed_key_package_state: &'a [u8],
}

struct PlaintextState {
    group_state_envelope: Vec<u8>,
    key_package_store_snapshot: Vec<u8>,
    alice_authentication: BetaMlsAuthenticationContext,
    alice_state_key: SecretBytes<32>,
}

/// Opens both sealed values so the state-restoration target can fuzz the
/// plaintext layers directly. Those layers sit behind XChaCha20-Poly1305 and a
/// device-bound key, so a relay cannot reach them; fuzzing them models the
/// local storage-tamper boundary and keeps the parsers themselves covered.
fn open_plaintext_state(inputs: &PlaintextStateInputs<'_>) -> PlaintextState {
    let provider = RustCryptoProvider::default();
    let peers = [inputs.bob_bundle.to_vec()];
    let alice = BetaMlsAuthenticationContext::from_verified_bundle_requests(
        inputs.alice_state,
        OPERATION_DAY,
        inputs.alice_bundle,
        &peers,
    )
    .expect("the local authentication context rebuilds");
    let alice_state_key = derive_state_key(&provider, inputs.alice_state, OPERATION_DAY)
        .expect("state key derivation succeeds");
    let group_state_envelope = open_device_secret_snapshot(
        &provider,
        &alice_state_key,
        SealedStateKind::Group,
        &alice,
        inputs.alice_sealed_group_state,
    )
    .expect("the sealed group state opens")
    .expose()
    .to_vec();

    let bob = BetaMlsAuthenticationContext::from_verified_bundle_requests(
        inputs.bob_state,
        OPERATION_DAY,
        inputs.bob_bundle,
        &[],
    )
    .expect("the peer authentication context rebuilds");
    let bob_key = derive_state_key(&provider, inputs.bob_state, OPERATION_DAY)
        .expect("peer state key derivation succeeds");
    let key_package_store_snapshot = open_device_secret_snapshot(
        &provider,
        &bob_key,
        SealedStateKind::KeyPackages,
        &bob,
        inputs.bob_sealed_key_package_state,
    )
    .expect("the sealed KeyPackage state opens")
    .expose()
    .to_vec();

    PlaintextState {
        group_state_envelope,
        key_package_store_snapshot,
        alice_authentication: alice,
        alice_state_key,
    }
}

/// Extracts the `CPMLSV01` snapshot that a `CPMLSG01` envelope carries last.
fn nested_snapshot(envelope: &[u8]) -> Vec<u8> {
    let mut reader = Reader::new(envelope);
    reader
        .expect(GROUP_STATE_ENVELOPE_MAGIC)
        .expect("group state envelope magic");
    reader.u16().expect("envelope version");
    reader.u16().expect("envelope suite");
    reader.framed().expect("local credential identifier");
    let proofs = usize::from(reader.u16().expect("authentication proof count"));
    for _ in 0..proofs {
        reader.framed().expect("authentication proof");
    }
    let snapshot = reader.framed().expect("nested MLS snapshot").to_vec();
    assert!(reader.is_finished());
    snapshot
}

#[cfg(test)]
mod tests {
    use super::{CryptoError, Fixture, operation};

    #[test]
    fn every_seed_request_is_a_genuinely_accepted_operation() {
        let fixture = Fixture::shared();
        for (discriminator, request) in &fixture.requests {
            assert!(
                !matches!(
                    operation(*discriminator, request),
                    Err(CryptoError::MalformedInput
                        | CryptoError::UnsupportedOperation
                        | CryptoError::UnsupportedVersion)
                ),
                "seed request for operation {discriminator} is not well formed"
            );
        }
    }

    #[test]
    fn the_plaintext_state_layers_carry_their_own_magic() {
        let fixture = Fixture::shared();
        assert!(fixture.group_state_envelope.starts_with(b"CPMLSG01"));
        assert!(fixture.group_state_snapshot.starts_with(b"CPMLSV01"));
        assert!(fixture.key_package_store_snapshot.starts_with(b"CPMLSK01"));
        assert!(fixture.alice_sealed_group_state.starts_with(b"CPMLSE01"));
        assert!(fixture.wrapped_key_package.starts_with(b"CPMKPV01"));
    }
}
