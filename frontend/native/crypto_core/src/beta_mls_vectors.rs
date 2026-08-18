//! Project-generated MLS test vectors in the upstream MLS working group schema.
//!
//! # These are project vectors. They are not upstream vectors.
//!
//! Every byte emitted here was produced by this repository, by
//! [`crate::mls_beta`], for the closed-beta Private Use ciphersuite `0xFE4C`.
//! Nothing in these files is published by the MLS working group, the IETF, or
//! any other external party, and no upstream vector exists for this suite to
//! compare against: `0xFE4C` is a Private Use identifier and the beta hybrid KEM
//! diverges from `draft-ietf-mls-pq-ciphersuites` `TBD2` in the ten ways
//! recorded as rows D1-D10 of `docs/mls-profile.md`.
//!
//! The files therefore prove **schema conformance and self-consistency**, not
//! interoperability. They must never be cited as external validation. The
//! disclaimer is repeated inside every emitted object under the `_provenance`
//! key so a single extracted vector still carries it.
//!
//! # Why the schema, then
//!
//! Writing the beta artifacts in the upstream shape is still worth doing: it
//! fixes the encodings this implementation would have to satisfy at a future
//! interop event, it makes the beta `Welcome` and follow-along behaviour
//! machine-checkable against a published contract rather than an ad-hoc one, and
//! it surfaces encoding mismatches early. One such mismatch is already recorded
//! in `signature_priv` below.
//!
//! # Schema
//!
//! The authority is `test-vectors.md` in <https://github.com/mlswg/mls-implementations>,
//! read at revision `main` on 2026-08-18, cross-checked field by field against
//! the serde structures `mls-rs 0.55.2` uses to consume the same files
//! (`src/group/interop_test_vectors/`). `vectors/mls-beta-upstream-schema/README.md`
//! records the per-category evidence and the categories deliberately skipped.
//!
//! Two encoding rules from that document drive the code below:
//!
//! - Signature and HPKE public keys are raw binary, with no length prefix.
//! - `EdDSA` private keys use "their native byte string representation" — the
//!   32-byte RFC 8032 seed. The beta suite's `AWS-LC` provider represents an
//!   Ed25519 private key as the 64-byte `seed || public key` concatenation
//!   instead, so emission truncates to the seed and consumption rebuilds the
//!   provider-native form by re-appending the public key. `mls-rs`'s own
//!   passive-client generator writes the provider-native key straight out, which
//!   would be non-conformant for this suite.

use std::{fs, time::Duration};

use ed25519_dalek::SigningKey;
use mls_rs::{
    CipherSuiteProvider, Client, CryptoProvider, ExtensionList, KeyPackageStorage, MlsMessage,
    client_builder::MlsConfig,
    identity::{SigningIdentity, basic::BasicCredential},
    mls_rules::{DefaultMlsRules, EncryptionOptions},
};
use mls_rs_codec::{MlsDecode, MlsEncode, VarInt};
use mls_rs_core::{
    crypto::{HpkePublicKey, HpkeSecretKey, SignaturePublicKey, SignatureSecretKey},
    key_package::KeyPackageData,
};
use serde_json::{Value, json};
use zeroize::Zeroizing;

use crate::mls_beta::{
    AuthenticatedDevice, AuthenticatedDeviceIdentityProvider, BETA_CIPHERSUITE,
    BETA_CIPHERSUITE_ID, BetaMlsCryptoProvider, OpaqueKeyPackageStorage, OpaqueMlsStateStorage,
};

const WELCOME_VECTORS: &str = include_str!("../vectors/mls-beta-upstream-schema/welcome.json");
const PASSIVE_CLIENT_VECTORS: &str =
    include_str!("../vectors/mls-beta-upstream-schema/passive-client.json");
const DESERIALIZATION_VECTORS: &str =
    include_str!("../vectors/mls-beta-upstream-schema/deserialization.json");

const VECTOR_DIR: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/vectors/mls-beta-upstream-schema"
);

/// The one key added to every emitted object beyond the upstream field set.
const PROVENANCE_KEY: &str = "_provenance";

/// Repeated verbatim in every emitted object. The schema test asserts it.
const PROVENANCE: &str = concat!(
    "PROJECT-GENERATED VECTOR. NOT AN UPSTREAM MLS WORKING GROUP VECTOR AND NOT ",
    "EXTERNAL INTEROPERABILITY EVIDENCE. Produced by this repository ",
    "(native/crypto_core) for the closed-beta MLS Private Use ciphersuite 0xFE4C, ",
    "which is not draft-ietf-mls-pq-ciphersuites TBD2 and is not wire-compatible ",
    "with it; see docs/mls-profile.md rows D1-D10. Regression and schema-conformance ",
    "evidence only."
);

const ED25519_SEED_BYTES: usize = 32;
const ED25519_PUBLIC_BYTES: usize = 32;
/// The beta hybrid KEM private key: ML-KEM-768 plus the X25519 half.
const BETA_HPKE_SECRET_BYTES: usize = 2432;
/// `HKDF-SHA384` extract size, which is the width of every beta key-schedule secret.
const BETA_SECRET_BYTES: usize = 48;

/// Vectors are checked-in artifacts replayed long after they were written, so the
/// generator issues `KeyPackage` lifetimes that will not lapse. Nothing in
/// production uses this value.
const HARNESS_KEY_PACKAGE_LIFETIME: Duration = Duration::from_hours(100 * 365 * 24);

/// Fixed harness identities.
///
/// The upstream schema has no field for an identity or Authentication-Service
/// context, because upstream harnesses accept any `BasicCredential`. This
/// implementation does not: [`AuthenticatedDeviceIdentityProvider`] resolves a
/// credential to an approved device and checks its signature key. The roster is
/// therefore harness input rather than vector data, and it is deterministic so
/// that a replay rebuilds byte-identical credentials from the seed alone.
#[derive(Clone, Copy)]
struct HarnessDevice {
    user_id: [u8; 16],
    device_id: [u8; 16],
    bundle: &'static [u8],
    signature_seed: [u8; ED25519_SEED_BYTES],
}

const ALICE: HarnessDevice = HarnessDevice {
    user_id: [0xA1; 16],
    device_id: [0xA2; 16],
    bundle: b"beta vector harness canonical device bundle: alice",
    signature_seed: [0x11; ED25519_SEED_BYTES],
};

const BOB: HarnessDevice = HarnessDevice {
    user_id: [0xB1; 16],
    device_id: [0xB2; 16],
    bundle: b"beta vector harness canonical device bundle: bob",
    signature_seed: [0x22; ED25519_SEED_BYTES],
};

const CAROL: HarnessDevice = HarnessDevice {
    user_id: [0xC1; 16],
    device_id: [0xC2; 16],
    bundle: b"beta vector harness canonical device bundle: carol",
    signature_seed: [0x33; ED25519_SEED_BYTES],
};

impl HarnessDevice {
    /// The Ed25519 public key, derived from the seed exactly as RFC 8032 does.
    fn signature_public(self) -> [u8; ED25519_PUBLIC_BYTES] {
        SigningKey::from_bytes(&self.signature_seed)
            .verifying_key()
            .to_bytes()
    }

    /// The provider-native 64-byte `seed || public key` form `AWS-LC` expects.
    fn provider_secret(self) -> SignatureSecretKey {
        provider_secret_key(&self.signature_seed, &self.signature_public())
    }

    fn authenticated(self) -> AuthenticatedDevice {
        AuthenticatedDevice::from_verified_bundle(
            self.user_id,
            self.device_id,
            self.bundle,
            &self.signature_public(),
        )
        .expect("harness device record is well formed")
    }

    fn signing_identity(self) -> SigningIdentity {
        let credential = BasicCredential::new(
            self.authenticated()
                .credential_identifier()
                .expect("credential identifier encoding succeeds"),
        );
        SigningIdentity::new(
            credential.into_credential(),
            SignaturePublicKey::from(self.signature_public().to_vec()),
        )
    }
}

/// Rebuilds the `AWS-LC` Ed25519 secret from the schema's 32-byte seed.
fn provider_secret_key(seed: &[u8], public: &[u8]) -> SignatureSecretKey {
    let mut native = Zeroizing::new(Vec::with_capacity(seed.len() + public.len()));
    native.extend_from_slice(seed);
    native.extend_from_slice(public);
    SignatureSecretKey::new_slice(&native)
}

fn beta_suite() -> impl CipherSuiteProvider {
    BetaMlsCryptoProvider
        .cipher_suite_provider(BETA_CIPHERSUITE)
        .expect("beta suite is configured")
}

fn directory() -> AuthenticatedDeviceIdentityProvider {
    AuthenticatedDeviceIdentityProvider::new([
        ALICE.authenticated(),
        BOB.authenticated(),
        CAROL.authenticated(),
    ])
    .expect("harness device directory is valid")
}

/// Mirrors [`crate::mls_beta::BetaMlsAuthenticationContext::client`]'s configuration:
/// the same identity provider type, crypto provider, encryption options, and suite.
/// Only the `KeyPackage` lifetime differs, and only so checked-in vectors keep
/// replaying.
fn harness_client(
    identity_provider: AuthenticatedDeviceIdentityProvider,
    signing_identity: SigningIdentity,
    signer: SignatureSecretKey,
    key_package_storage: OpaqueKeyPackageStorage,
) -> Client<impl MlsConfig + use<>> {
    let mut encryption_options = EncryptionOptions::default();
    encryption_options.encrypt_control_messages = true;
    let rules = DefaultMlsRules::default().with_encryption_options(encryption_options);
    Client::builder()
        .identity_provider(identity_provider)
        .mls_rules(rules)
        .crypto_provider(BetaMlsCryptoProvider)
        .key_package_repo(key_package_storage)
        .group_state_storage(OpaqueMlsStateStorage::default())
        .key_package_lifetime(HARNESS_KEY_PACKAGE_LIFETIME)
        .signing_identity(signing_identity, signer, BETA_CIPHERSUITE)
        .build()
}

fn device_client(
    device: HarnessDevice,
    key_package_storage: OpaqueKeyPackageStorage,
) -> Client<impl MlsConfig + use<>> {
    harness_client(
        directory(),
        device.signing_identity(),
        device.provider_secret(),
        key_package_storage,
    )
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut text = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        text.push(char::from(DIGITS[usize::from(byte >> 4)]));
        text.push(char::from(DIGITS[usize::from(byte & 0x0f)]));
    }
    text
}

fn decode_hex(text: &str) -> Vec<u8> {
    assert!(text.len().is_multiple_of(2), "hex has an even length");
    assert!(
        text.bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)),
        "the upstream schema uses lower-case hex"
    );
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            u8::from_str_radix(std::str::from_utf8(pair).expect("vector hex is ASCII"), 16)
                .expect("vector hex is valid")
        })
        .collect()
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/// Everything one run of the beta group flow contributes to the fixtures.
struct GeneratedScenario {
    welcome: Value,
    passive_client: Value,
}

/// Runs one complete beta group scenario and captures it in both schemas.
///
/// Alice creates the group and adds Bob, which produces the `Welcome` vector.
/// Bob is then the passive client: Alice adds Carol, Carol proposes an update
/// that Alice commits, and Alice finally removes Carol. Each epoch records the
/// authenticator Alice computes, which is the value Bob must reproduce.
#[allow(clippy::too_many_lines)] // One linear scenario; splitting it would hide the message order.
fn generate_scenario() -> GeneratedScenario {
    let suite = beta_suite();

    let alice_client = device_client(ALICE, OpaqueKeyPackageStorage::default());
    let mut alice_group = alice_client
        .create_group(ExtensionList::new(), ExtensionList::default(), None)
        .expect("Alice creates the beta group");

    let bob_storage = OpaqueKeyPackageStorage::default();
    let bob_client = device_client(BOB, bob_storage.clone());
    let bob_key_package = bob_client
        .generate_key_package_message(ExtensionList::default(), ExtensionList::default(), None)
        .expect("Bob generates an authenticated KeyPackage");
    let bob_secrets = key_package_secrets(&suite, &bob_storage, &bob_key_package);

    let add_bob = alice_group
        .commit_builder()
        .add_member(bob_key_package.clone())
        .expect("Bob's KeyPackage is accepted")
        .build()
        .expect("the add Commit is generated");
    alice_group
        .apply_pending_commit()
        .expect("Alice applies the add Commit");
    let welcome = add_bob
        .welcome_messages
        .first()
        .expect("adding Bob produces a Welcome")
        .clone();
    let initial_epoch_authenticator = epoch_authenticator_at(&alice_group, 1);

    let welcome_vector = json!({
        PROVENANCE_KEY: PROVENANCE,
        "cipher_suite": BETA_CIPHERSUITE_ID,
        "init_priv": hex(&bob_secrets.init_key),
        "signer_pub": hex(&ALICE.signature_public()),
        "key_package": hex(&message_bytes(&bob_key_package)),
        "welcome": hex(&message_bytes(&welcome)),
    });

    // Epoch 1: Alice adds Carol.
    let carol_storage = OpaqueKeyPackageStorage::default();
    let carol_client = device_client(CAROL, carol_storage.clone());
    let carol_key_package = carol_client
        .generate_key_package_message(ExtensionList::default(), ExtensionList::default(), None)
        .expect("Carol generates an authenticated KeyPackage");
    let add_carol = alice_group
        .commit_builder()
        .add_member(carol_key_package)
        .expect("Carol's KeyPackage is accepted")
        .build()
        .expect("the second add Commit is generated");
    alice_group
        .apply_pending_commit()
        .expect("Alice applies the second add Commit");
    let authenticator_after_adding_carol = epoch_authenticator_at(&alice_group, 2);
    let (mut carol_group, _) = carol_client
        .join_group(
            None,
            add_carol
                .welcome_messages
                .first()
                .expect("adding Carol produces a Welcome"),
            None,
        )
        .expect("Carol joins the beta group");

    // Epoch 2: Carol proposes an update by reference and Alice commits it.
    let carol_update = carol_group
        .propose_update(b"beta vector update".to_vec())
        .expect("Carol proposes an update");
    alice_group
        .process_incoming_message(carol_update.clone())
        .expect("Alice authenticates Carol's Proposal");
    let update_commit = alice_group
        .commit(b"beta vector commit".to_vec())
        .expect("Alice commits Carol's Proposal");
    alice_group
        .apply_pending_commit()
        .expect("Alice applies the update Commit");
    let authenticator_after_update = epoch_authenticator_at(&alice_group, 3);
    carol_group
        .process_incoming_message(update_commit.commit_message.clone())
        .expect("Carol authenticates the update Commit");

    // Epoch 3: Alice removes Carol.
    let remove_commit = alice_group
        .commit_builder()
        .remove_member(carol_group.current_member_index())
        .expect("Carol's leaf is present")
        .build()
        .expect("the remove Commit is generated");
    alice_group
        .apply_pending_commit()
        .expect("Alice applies the remove Commit");
    let authenticator_after_removing_carol = epoch_authenticator_at(&alice_group, 4);

    let passive_client_vector = json!({
        PROVENANCE_KEY: PROVENANCE,
        "cipher_suite": BETA_CIPHERSUITE_ID,
        "external_psks": [],
        "key_package": hex(&message_bytes(&bob_key_package)),
        // The 32-byte RFC 8032 seed, not the provider-native 64-byte form.
        "signature_priv": hex(&BOB.signature_seed),
        "encryption_priv": hex(&bob_secrets.leaf_node_key),
        "init_priv": hex(&bob_secrets.init_key),
        "welcome": hex(&message_bytes(&welcome)),
        // The beta client publishes the ratchet tree in the Welcome's GroupInfo,
        // which the schema represents as a null out-of-band tree.
        "ratchet_tree": Value::Null,
        "initial_epoch_authenticator": hex(&initial_epoch_authenticator),
        "epochs": [
            {
                "proposals": [],
                "commit": hex(&message_bytes(&add_carol.commit_message)),
                "epoch_authenticator": hex(&authenticator_after_adding_carol),
            },
            {
                "proposals": [hex(&message_bytes(&carol_update))],
                "commit": hex(&message_bytes(&update_commit.commit_message)),
                "epoch_authenticator": hex(&authenticator_after_update),
            },
            {
                "proposals": [],
                "commit": hex(&message_bytes(&remove_commit.commit_message)),
                "epoch_authenticator": hex(&authenticator_after_removing_carol),
            },
        ],
    });

    GeneratedScenario {
        welcome: json!([welcome_vector]),
        passive_client: json!([passive_client_vector]),
    }
}

/// Deterministic `VarInt` headers covering every width the MLS codec emits and
/// both sides of each boundary between them.
fn deserialization_vectors() -> Value {
    let lengths: [u32; 8] = [
        0,
        1,
        63,            // widest one-byte length
        64,            // narrowest two-byte length
        1_024,         // an interior two-byte length
        16_383,        // widest two-byte length
        16_384,        // narrowest four-byte length
        1_073_741_823, // VarInt::MAX, the widest length MLS encodes
    ];
    let cases: Vec<Value> = lengths
        .iter()
        .map(|length| {
            let header = VarInt(*length)
                .mls_encode_to_vec()
                .expect("VarInt within range encodes");
            json!({
                PROVENANCE_KEY: PROVENANCE,
                "vlbytes_header": hex(&header),
                "length": length,
            })
        })
        .collect();
    Value::Array(cases)
}

/// The private halves mls-rs stored for a freshly generated `KeyPackage`.
struct KeyPackageSecrets {
    init_key: Vec<u8>,
    leaf_node_key: Vec<u8>,
}

fn key_package_secrets(
    suite: &impl CipherSuiteProvider,
    storage: &OpaqueKeyPackageStorage,
    message: &MlsMessage,
) -> KeyPackageSecrets {
    let key_package = message
        .clone()
        .into_key_package()
        .expect("the generated message carries a KeyPackage");
    let reference = key_package
        .to_reference(suite)
        .expect("the KeyPackage reference is computable");
    let stored = storage
        .get(&reference)
        .expect("the KeyPackage repository is readable")
        .expect("generation stored the KeyPackage secrets");
    KeyPackageSecrets {
        init_key: stored.init_key.to_vec(),
        leaf_node_key: stored.leaf_node_key.to_vec(),
    }
}

fn message_bytes(message: &MlsMessage) -> Vec<u8> {
    message.to_bytes().expect("an MLSMessage re-encodes")
}

fn epoch_authenticator(group: &mls_rs::Group<impl MlsConfig>) -> Vec<u8> {
    group
        .epoch_authenticator()
        .expect("the epoch authenticator is available")
        .to_vec()
}

/// Records the authenticator for an epoch the group has already advanced past.
///
/// `mls-rs` exposes only the current epoch, so the generator captures the value
/// while it is current; this helper asserts the expectation rather than reading
/// history, and the caller invokes it in epoch order.
fn epoch_authenticator_at(group: &mls_rs::Group<impl MlsConfig>, epoch: u64) -> Vec<u8> {
    assert_eq!(
        group.current_epoch(),
        epoch,
        "the generator captures each epoch authenticator while that epoch is current"
    );
    epoch_authenticator(group)
}

fn write_vector_file(name: &str, value: &Value) {
    let mut text = serde_json::to_string_pretty(value).expect("emitted vectors serialize");
    text.push('\n');
    fs::write(format!("{VECTOR_DIR}/{name}"), text)
        .unwrap_or_else(|error| panic!("writing {name} succeeds: {error}"));
}

/// Rewrites the checked-in fixtures. Deliberately `#[ignore]`d: no ordinary
/// `cargo test` run may rewrite an expected value, and `cargo test --all-features`
/// does not run ignored tests. Invoke it explicitly:
///
/// ```text
/// cargo test --locked --all-features -- --ignored emit_project_vectors
/// ```
#[test]
#[ignore = "rewrites the checked-in fixtures; run deliberately"]
fn emit_project_vectors_in_the_upstream_schema() {
    let scenario = generate_scenario();
    write_vector_file("welcome.json", &scenario.welcome);
    write_vector_file("passive-client.json", &scenario.passive_client);
    write_vector_file("deserialization.json", &deserialization_vectors());
}

// ---------------------------------------------------------------------------
// Schema conformance
// ---------------------------------------------------------------------------

fn objects(text: &str, file: &str) -> Vec<Value> {
    let parsed: Value =
        serde_json::from_str(text).unwrap_or_else(|error| panic!("{file} is valid JSON: {error}"));
    let cases = parsed
        .as_array()
        .unwrap_or_else(|| panic!("{file} is a JSON array, which the upstream schema requires"))
        .clone();
    assert!(!cases.is_empty(), "{file} carries at least one vector");
    cases
}

/// Asserts the object carries exactly the upstream field set, plus the one
/// documented non-upstream key.
fn assert_field_set(case: &Value, file: &str, upstream: &[&str]) {
    let object = case
        .as_object()
        .unwrap_or_else(|| panic!("every {file} entry is a JSON object"));
    let mut present: Vec<&str> = object.keys().map(String::as_str).collect();
    present.sort_unstable();
    let mut expected: Vec<&str> = upstream.to_vec();
    expected.push(PROVENANCE_KEY);
    expected.sort_unstable();
    assert_eq!(
        present, expected,
        "{file} carries exactly the upstream fields plus {PROVENANCE_KEY}"
    );
}

fn hex_field(case: &Value, file: &str, field: &str) -> Vec<u8> {
    decode_hex(
        case[field]
            .as_str()
            .unwrap_or_else(|| panic!("{file} field {field} is a hex string")),
    )
}

fn assert_width(bytes: &[u8], file: &str, field: &str, width: usize) {
    assert_eq!(
        bytes.len(),
        width,
        "{file} field {field} is {width} bytes in the beta suite"
    );
}

/// Every emitted object states its provenance, in every file.
#[test]
fn every_emitted_vector_declares_project_provenance() {
    for (text, file) in [
        (WELCOME_VECTORS, "welcome.json"),
        (PASSIVE_CLIENT_VECTORS, "passive-client.json"),
        (DESERIALIZATION_VECTORS, "deserialization.json"),
    ] {
        for case in objects(text, file) {
            let note = case[PROVENANCE_KEY]
                .as_str()
                .unwrap_or_else(|| panic!("{file} entry carries {PROVENANCE_KEY}"));
            assert_eq!(note, PROVENANCE, "{file} carries the exact disclaimer");
            for required in [
                "PROJECT-GENERATED VECTOR",
                "NOT AN UPSTREAM MLS WORKING GROUP VECTOR",
                "NOT EXTERNAL INTEROPERABILITY EVIDENCE",
                "0xFE4C",
            ] {
                assert!(
                    note.contains(required),
                    "{file} disclaimer still states {required}"
                );
            }
        }
    }
}

#[test]
fn welcome_vectors_match_the_upstream_schema() {
    let file = "welcome.json";
    for case in objects(WELCOME_VECTORS, file) {
        assert_field_set(
            &case,
            file,
            &[
                "cipher_suite",
                "init_priv",
                "signer_pub",
                "key_package",
                "welcome",
            ],
        );
        assert_eq!(
            case["cipher_suite"].as_u64(),
            Some(u64::from(BETA_CIPHERSUITE_ID)),
            "the Welcome category is ciphersuite-parameterized and pinned to the beta suite"
        );
        assert_width(
            &hex_field(&case, file, "init_priv"),
            file,
            "init_priv",
            BETA_HPKE_SECRET_BYTES,
        );
        assert_width(
            &hex_field(&case, file, "signer_pub"),
            file,
            "signer_pub",
            ED25519_PUBLIC_BYTES,
        );
        assert_mls_message_round_trips(&hex_field(&case, file, "key_package"), "key_package");
        assert_mls_message_round_trips(&hex_field(&case, file, "welcome"), "welcome");
    }
}

#[test]
fn passive_client_vectors_match_the_upstream_schema() {
    let file = "passive-client.json";
    for case in objects(PASSIVE_CLIENT_VECTORS, file) {
        assert_field_set(
            &case,
            file,
            &[
                "cipher_suite",
                "external_psks",
                "key_package",
                "signature_priv",
                "encryption_priv",
                "init_priv",
                "welcome",
                "ratchet_tree",
                "initial_epoch_authenticator",
                "epochs",
            ],
        );
        assert_eq!(
            case["cipher_suite"].as_u64(),
            Some(u64::from(BETA_CIPHERSUITE_ID)),
            "the passive-client category is ciphersuite-parameterized and pinned to the beta suite"
        );
        assert!(
            case["external_psks"]
                .as_array()
                .expect("external_psks is an array")
                .is_empty(),
            "the beta client builds no PSK, so the array is empty rather than absent"
        );
        assert!(
            case["ratchet_tree"].is_null(),
            "the beta Welcome carries the ratchet tree, which the schema records as null"
        );
        assert_width(
            &hex_field(&case, file, "signature_priv"),
            file,
            "signature_priv",
            ED25519_SEED_BYTES,
        );
        assert_width(
            &hex_field(&case, file, "encryption_priv"),
            file,
            "encryption_priv",
            BETA_HPKE_SECRET_BYTES,
        );
        assert_width(
            &hex_field(&case, file, "init_priv"),
            file,
            "init_priv",
            BETA_HPKE_SECRET_BYTES,
        );
        assert_width(
            &hex_field(&case, file, "initial_epoch_authenticator"),
            file,
            "initial_epoch_authenticator",
            BETA_SECRET_BYTES,
        );
        assert_mls_message_round_trips(&hex_field(&case, file, "key_package"), "key_package");
        assert_mls_message_round_trips(&hex_field(&case, file, "welcome"), "welcome");

        let epochs = case["epochs"].as_array().expect("epochs is an array");
        assert!(
            !epochs.is_empty(),
            "the scenario advances at least one epoch"
        );
        for epoch in epochs {
            assert_epoch_matches_the_upstream_schema(epoch, file);
        }
    }
}

/// One entry of the passive-client `epochs` array.
fn assert_epoch_matches_the_upstream_schema(epoch: &Value, file: &str) {
    let mut present: Vec<&str> = epoch
        .as_object()
        .expect("each epoch is an object")
        .keys()
        .map(String::as_str)
        .collect();
    present.sort_unstable();
    assert_eq!(
        present,
        ["commit", "epoch_authenticator", "proposals"],
        "each epoch carries exactly the upstream epoch fields"
    );
    for proposal in epoch["proposals"]
        .as_array()
        .expect("proposals is an array")
    {
        let bytes = decode_hex(proposal.as_str().expect("each proposal is a hex string"));
        assert_mls_message_round_trips(&bytes, "proposal");
    }
    assert_mls_message_round_trips(
        &decode_hex(epoch["commit"].as_str().expect("commit is a hex string")),
        "commit",
    );
    assert_width(
        &decode_hex(
            epoch["epoch_authenticator"]
                .as_str()
                .expect("epoch_authenticator is a hex string"),
        ),
        file,
        "epoch_authenticator",
        BETA_SECRET_BYTES,
    );
}

#[test]
fn deserialization_vectors_match_the_upstream_schema() {
    let file = "deserialization.json";
    for case in objects(DESERIALIZATION_VECTORS, file) {
        assert_field_set(&case, file, &["vlbytes_header", "length"]);
        assert!(
            case.get("cipher_suite").is_none(),
            "the deserialization category is not ciphersuite-parameterized"
        );
        let header = hex_field(&case, file, "vlbytes_header");
        assert!(
            matches!(header.len(), 1 | 2 | 4),
            "an MLS variable-length header is one, two, or four bytes"
        );
        assert!(
            case["length"].as_u64().is_some(),
            "length is an unsigned integer"
        );
    }
}

/// Every serialized object in the fixtures decodes and re-encodes to itself,
/// which is the upstream `Messages` verification rule applied to the objects
/// these categories carry.
fn assert_mls_message_round_trips(bytes: &[u8], field: &str) {
    let message = MlsMessage::from_bytes(bytes)
        .unwrap_or_else(|error| panic!("{field} decodes as an MLSMessage: {error}"));
    assert_eq!(
        message.to_bytes().expect("an MLSMessage re-encodes"),
        bytes,
        "{field} re-encodes to the exact bytes in the fixture"
    );
}

// ---------------------------------------------------------------------------
// Round trips through the implementation
// ---------------------------------------------------------------------------

/// Rebuilds the joining client from nothing but the vector's own fields plus the
/// harness device directory, checking the correspondences the upstream
/// passive-client verification calls for on the way.
fn joining_client(
    key_package_bytes: &[u8],
    signature_priv: &[u8],
    encryption_priv: &[u8],
    init_priv: &[u8],
) -> Client<impl MlsConfig + use<>> {
    let suite = beta_suite();
    let key_package = MlsMessage::from_bytes(key_package_bytes)
        .expect("the vector KeyPackage decodes")
        .into_key_package()
        .expect("the vector carries an MLSMessage(KeyPackage)");

    // The schema's 32-byte seed must reproduce the KeyPackage's public key.
    let seed: [u8; ED25519_SEED_BYTES] = signature_priv
        .try_into()
        .expect("signature_priv is a 32-byte EdDSA seed");
    assert_eq!(
        SigningKey::from_bytes(&seed).verifying_key().to_bytes()[..],
        *key_package.signing_identity().signature_key.as_ref(),
        "signature_priv corresponds to the signature_key in the KeyPackage"
    );

    // init_priv must open a ciphertext sealed to the KeyPackage's init key.
    assert_hpke_key_pair_matches(&suite, &key_package.hpke_init_key, init_priv);

    client_with_secrets(
        key_package_bytes,
        signature_priv,
        encryption_priv,
        init_priv,
    )
}

/// The same reconstruction with no correspondence assertions, so a negative test
/// can supply a deliberately wrong secret and observe the failure.
fn client_with_secrets(
    key_package_bytes: &[u8],
    signature_priv: &[u8],
    encryption_priv: &[u8],
    init_priv: &[u8],
) -> Client<impl MlsConfig + use<>> {
    let suite = beta_suite();
    let key_package = MlsMessage::from_bytes(key_package_bytes)
        .expect("the vector KeyPackage decodes")
        .into_key_package()
        .expect("the vector carries an MLSMessage(KeyPackage)");
    let signing_identity = key_package.signing_identity().clone();
    let signature_public = signing_identity.signature_key.as_ref().to_vec();

    let reference = key_package
        .to_reference(&suite)
        .expect("the KeyPackage reference is computable");
    let expiration = key_package
        .expiration()
        .expect("the KeyPackage lifetime is readable");
    let stored = KeyPackageData::new(
        key_package
            .mls_encode_to_vec()
            .expect("the KeyPackage re-encodes"),
        HpkeSecretKey::from(init_priv.to_vec()),
        HpkeSecretKey::from(encryption_priv.to_vec()),
        expiration.seconds_since_epoch(),
    );

    let mut storage = OpaqueKeyPackageStorage::default();
    storage
        .insert(reference.to_vec(), stored)
        .expect("the harness stores the vector's KeyPackage secrets");

    harness_client(
        directory(),
        signing_identity,
        provider_secret_key(signature_priv, &signature_public),
        storage,
    )
}

/// Proves an HPKE private key belongs to a public key by using both halves.
fn assert_hpke_key_pair_matches(
    suite: &impl CipherSuiteProvider,
    public: &HpkePublicKey,
    private: &[u8],
) {
    let plaintext = b"beta vector HPKE key-pair check";
    let sealed = suite
        .hpke_seal(public, b"vector-check", None, plaintext)
        .expect("sealing to the vector public key succeeds");
    let opened = suite
        .hpke_open(
            &sealed,
            &HpkeSecretKey::from(private.to_vec()),
            public,
            b"vector-check",
            None,
        )
        .expect("the vector private key opens what its public key sealed");
    assert_eq!(
        opened.as_slice(),
        plaintext,
        "the HPKE key pair in the vector is consistent"
    );
}

#[test]
fn welcome_vectors_round_trip_through_the_beta_implementation() {
    let file = "welcome.json";
    for case in objects(WELCOME_VECTORS, file) {
        let key_package = hex_field(&case, file, "key_package");
        let init_priv = hex_field(&case, file, "init_priv");
        let signer_pub = hex_field(&case, file, "signer_pub");
        let welcome = MlsMessage::from_bytes(&hex_field(&case, file, "welcome"))
            .expect("the vector Welcome decodes");

        // The Welcome category carries no leaf secret: the upstream verification
        // only decrypts the Welcome, checks the GroupInfo signature against
        // `signer_pub`, and recomputes the confirmation tag. A client still needs
        // some stored leaf key, so the harness reuses the init key.
        // `welcome_vectors_need_the_recorded_init_priv` shows which half is
        // actually load-bearing here.
        let client = joining_client(&key_package, &BOB.signature_seed, &init_priv, &init_priv);
        let (group, _info) = client
            .join_group(None, &welcome, None)
            .expect("the vector Welcome decrypts, verifies, and joins");

        let signers: Vec<Vec<u8>> = group
            .roster()
            .members()
            .into_iter()
            .map(|member| member.signing_identity.signature_key.as_ref().to_vec())
            .collect();
        assert!(
            signers.contains(&signer_pub),
            "signer_pub is a member of the group the Welcome admits"
        );
    }
}

/// A `Welcome` vector that joined under any init key would prove nothing about
/// `init_priv`, so corrupting it must break the join.
#[test]
fn welcome_vectors_need_the_recorded_init_priv() {
    let file = "welcome.json";
    for case in objects(WELCOME_VECTORS, file) {
        let key_package = hex_field(&case, file, "key_package");
        let mut init_priv = hex_field(&case, file, "init_priv");
        init_priv[0] ^= 0x01;
        let welcome = MlsMessage::from_bytes(&hex_field(&case, file, "welcome"))
            .expect("the vector Welcome decodes");
        let client = client_with_secrets(&key_package, &BOB.signature_seed, &init_priv, &init_priv);
        assert!(
            client.join_group(None, &welcome, None).is_err(),
            "the recorded init_priv is required to open the vector Welcome"
        );
    }
}

/// The `proposals` array is part of the scenario, not decoration: a `Commit` that
/// incorporates a `Proposal` by reference must not apply without it.
#[test]
fn passive_client_vectors_need_the_recorded_proposals() {
    let file = "passive-client.json";
    for case in objects(PASSIVE_CLIENT_VECTORS, file) {
        let client = joining_client(
            &hex_field(&case, file, "key_package"),
            &hex_field(&case, file, "signature_priv"),
            &hex_field(&case, file, "encryption_priv"),
            &hex_field(&case, file, "init_priv"),
        );
        let welcome = MlsMessage::from_bytes(&hex_field(&case, file, "welcome"))
            .expect("the vector Welcome decodes");
        let (mut group, _info) = client
            .join_group(None, &welcome, None)
            .expect("the passive client joins from the vector Welcome");

        let mut covered = false;
        for epoch in case["epochs"].as_array().expect("epochs is an array") {
            let commit =
                MlsMessage::from_bytes(&decode_hex(epoch["commit"].as_str().expect("hex string")))
                    .expect("the vector Commit decodes");
            if epoch["proposals"]
                .as_array()
                .expect("proposals is an array")
                .is_empty()
            {
                group
                    .process_incoming_message(commit)
                    .expect("the passive client applies a Commit that references nothing");
                continue;
            }
            covered = true;
            assert!(
                group.process_incoming_message(commit).is_err(),
                "a Commit referencing a Proposal must not apply without that Proposal"
            );
            break;
        }
        assert!(
            covered,
            "the scenario advances one epoch through a by-reference Proposal"
        );
    }
}

#[test]
fn passive_client_vectors_round_trip_through_the_beta_implementation() {
    let file = "passive-client.json";
    for case in objects(PASSIVE_CLIENT_VECTORS, file) {
        let client = joining_client(
            &hex_field(&case, file, "key_package"),
            &hex_field(&case, file, "signature_priv"),
            &hex_field(&case, file, "encryption_priv"),
            &hex_field(&case, file, "init_priv"),
        );
        let welcome = MlsMessage::from_bytes(&hex_field(&case, file, "welcome"))
            .expect("the vector Welcome decodes");
        let (mut group, _info) = client
            .join_group(None, &welcome, None)
            .expect("the passive client joins from the vector Welcome");
        assert_eq!(
            epoch_authenticator(&group),
            hex_field(&case, file, "initial_epoch_authenticator"),
            "the joined epoch authenticator matches the vector"
        );

        for epoch in case["epochs"].as_array().expect("epochs is an array") {
            for proposal in epoch["proposals"]
                .as_array()
                .expect("proposals is an array")
            {
                let message =
                    MlsMessage::from_bytes(&decode_hex(proposal.as_str().expect("hex string")))
                        .expect("the vector Proposal decodes");
                group
                    .process_incoming_message(message)
                    .expect("the passive client authenticates the Proposal");
            }
            let commit =
                MlsMessage::from_bytes(&decode_hex(epoch["commit"].as_str().expect("hex string")))
                    .expect("the vector Commit decodes");
            group
                .process_incoming_message(commit)
                .expect("the passive client authenticates and applies the Commit");
            assert_eq!(
                epoch_authenticator(&group),
                decode_hex(epoch["epoch_authenticator"].as_str().expect("hex string")),
                "the passive client reproduces the epoch authenticator"
            );
        }
    }
}

#[test]
fn deserialization_vectors_round_trip_through_the_beta_codec() {
    let file = "deserialization.json";
    for case in objects(DESERIALIZATION_VECTORS, file) {
        let header = hex_field(&case, file, "vlbytes_header");
        let length = case["length"].as_u64().expect("length is an integer");

        let decoded = VarInt::mls_decode(&mut header.as_slice())
            .expect("the vector header decodes as an MLS variable-length header");
        assert_eq!(
            u64::from(u32::from(decoded)),
            length,
            "the decoded header equals the recorded length"
        );
        assert_eq!(
            decoded.mls_encode_to_vec().expect("a VarInt re-encodes"),
            header,
            "the header is the canonical encoding of that length"
        );
    }
}

/// The emitted vectors must keep describing the suite they were generated for.
/// A mapping change in `mls_beta.rs` invalidates them, and this catches it.
#[test]
fn emitted_vectors_still_describe_the_built_beta_suite() {
    let suite = beta_suite();
    assert_eq!(
        u16::from(suite.cipher_suite()),
        BETA_CIPHERSUITE_ID,
        "the vectors record the suite the provider actually builds"
    );
    assert_eq!(
        suite.kdf_extract_size(),
        BETA_SECRET_BYTES,
        "the recorded epoch-authenticator width follows the suite KDF"
    );
    let (secret, public) = suite
        .signature_key_generate()
        .expect("the suite generates a signature key pair");
    assert_eq!(
        secret.as_ref().len(),
        ED25519_SEED_BYTES + ED25519_PUBLIC_BYTES,
        "the provider-native Ed25519 secret is seed || public, which is why emission truncates"
    );
    assert_eq!(
        public.as_ref().len(),
        ED25519_PUBLIC_BYTES,
        "the Ed25519 public key is raw 32-byte binary, as the schema requires"
    );
}
