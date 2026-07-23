# Cryptographic protocol

## Status

This is the normative version-1 client design. It deliberately composes established
protocols instead of inventing cryptographic primitives. Exact CDDL schemas and test
vectors MUST be frozen with the crypto-core implementation before interoperability is
declared. Independent review is a production release gate.

## Implementation boundary

A shared memory-safe crypto core MUST expose a narrow FFI/Wasm API to Flutter. Dart code
may orchestrate operations but MUST NOT implement X3DH, ratchets, MLS, signatures, KDFs,
AEAD, secretstream, or secret zeroization.

The preferred implementation direction is Rust:

- a reviewed Signal-compatible implementation for X3DH and Double Ratchet;
- OpenMLS for RFC 9420 group state;
- reviewed primitives for canonical CBOR, Argon2id, and XChaCha20-Poly1305;
- Android native libraries and a browser Wasm build produced from the same source and
  test vectors.

Signal's official `libsignal` supports Android but does not present a supported browser
runtime contract. OpenMLS builds for Android and Wasm but lists those targets as built,
not fully tested. Therefore dependency selection remains a mandatory implementation
spike; inability to produce one interoperable reviewed core blocks Web release rather
than causing a fallback to ad-hoc Dart cryptography.

## Protocol suite

| Purpose | Version-1 choice |
|---|---|
| Encoding | Deterministic CBOR (RFC 8949) |
| Random IDs | 128 random bits, encoded as UUIDv4 at UI/API boundaries |
| Two-device setup | X3DH with X25519 and SHA-256/HKDF-SHA-256 |
| Two-device messaging | Signal Double Ratchet, bounded skipped-key storage |
| Group key agreement | MLS 1.0 (RFC 9420) |
| MLS suite | `MLS_128_DHKEMX25519_CHACHA20POLY1305_SHA256_Ed25519` when implementation/interoperability validation passes; otherwise the RFC mandatory-to-implement suite |
| Application signatures | Ed25519, only for authorization/control events that require durable attribution |
| Archive/backup AEAD | XChaCha20-Poly1305 with random 192-bit nonces |
| Password/recovery KDF | Argon2id (RFC 9106), parameters calibrated per platform and stored with the blob |
| File streaming | libsodium `secretstream_xchacha20poly1305` |
| Media framing | RFC 9605 SFrame or the LiveKit E2EE implementation after wire-level validation |

Every KDF and signature input starts with an ASCII domain label containing the product
protocol and major version, for example `cp/v1/device-spk`. Labels are constants in the
shared crypto core and covered by test vectors.

## Device identity

Each device owns independent key material:

- an X25519/XEdDSA-compatible X3DH identity key;
- an Ed25519 application/MLS credential signing key;
- a signed X25519 prekey and a bounded one-time-prekey pool;
- MLS leaf secrets and key packages;
- pairwise Double Ratchet sessions;
- a random local storage key protected by the platform keystore;
- access to the account archive key only after recovery or secure synchronization.

The backend `ik_pub` is a versioned, canonical public device bundle containing the
public identity/credential keys and algorithms. It contains no secret. The signed-prekey
signature covers the protocol label, device public bundle hash, signed-prekey ID, and
signed-prekey bytes. Recipients abort before session creation if verification fails.

Identity changes are not silently accepted. A first-seen key is stored as unverified; a
change marks the contact/device changed, invalidates affected sessions, and requires
visible re-verification for a verified contact.

## Direct messages and per-device channels

X3DH establishes an asynchronous session from a claimed prekey bundle. The resulting
secret initializes a Double Ratchet. The initial ciphertext carries the X3DH metadata
needed by the recipient and the first ratchet message. One-time private prekeys are
deleted after successful use. Signed prekeys rotate every seven days. Superseded private
signed prekeys are retained for 31 days, matching the default maximum delayed-envelope
window plus one day, and are then securely erased; a deployment with a longer envelope
TTL MUST increase this retention before rollout.

Each pairwise session retains at most 2,000 skipped message keys and the client retains
at most 20,000 skipped keys across the account. A message beyond either bound enters the
authenticated session-repair path rather than causing unbounded allocation or silent
security downgrade.

Every logical DM is independently encrypted for:

- every live device belonging to the peer; and
- every other live device belonging to the sender.

The current device applies its own logical event locally and is not sent a redundant
envelope. Each recipient transport ciphertext binds, as associated data, the protocol
version, recipient device ID, ratchet header, and fixed `pairwise-transport-v1` domain
purpose. The event kind remains encrypted. The server does not
learn the sender or conversation ID.

Skipped message keys are capped at 1,000 per session, deleted deterministically after the
configured ratchet/event horizon, and never backed up. Exceeding a bound fails the
message and starts an authenticated session-repair flow; it never allocates without
limit.

## Groups

Each device is an MLS member with an authenticated credential bound to its device public
bundle. `BasicCredential.identity` is the deterministic-CBOR tuple
`[protocol_version, user_uuid, device_uuid, SHA-256(canonical_device_bundle)]`; its MLS
signature key is the Ed25519 credential key from that bundle. The client-side MLS
Authentication Service validates the KeyPackage/LeafNode signature, exact user/device
reference identifiers, bundle hash, active backend device listing, and the locally stored
TOFU/verification record whenever a credential is introduced or updated. A mismatch or
identity-key change quarantines the operation and requires visible re-verification; the
backend listing alone is never treated as cryptographic proof. A user with several
devices contributes several MLS leaves. Application group roles are validated by signed
control events in addition to MLS membership.

MLS `PrivateMessage` is used for application and handshake content wherever permitted.
Welcome, Commit, Proposal, GroupInfo, and application messages follow RFC 9420 processing
and state-persistence rules. A commit is persisted transactionally before dependent
application messages are accepted.

To preserve the backend's no-shared-ciphertext property, each MLS object is wrapped in a
fresh per-recipient Double Ratchet transport envelope. Sending identical MLS bytes as
identical backend blobs is forbidden because it would link the recipient set.

Member removal commits advance the epoch. A removed member cannot derive future epoch
secrets, but previously received plaintext cannot be remotely erased. Forks are
quarantined and resolved only by the specified MLS policy; the UI does not guess.

## Safety numbers

The safety-number input includes both users' stable IDs and the sorted set of active
device credential fingerprints. Display uses a human-comparable numeric/word form plus a
QR representation containing the exact canonical bytes and protocol version. Adding,
removing, or changing a device changes the aggregate fingerprint and clears verification
until the user acknowledges/re-verifies it.

## Recovery and history

At account setup the client generates:

- a random 256-bit archive key used only for client history records; and
- a random high-entropy recovery secret with a checksum and human-safe encoding.

Argon2id derives a wrapping key from the recovery secret and a random salt. Version 1 uses
a 16-byte salt and 32-byte output, with a floor of 64 MiB memory, three iterations, and
parallelism four on both targets. Implementations without parallel Wasm execution still
process the four lanes correctly rather than changing the stored parameter. Version 1
writers use those exact portable parameters so a backup created on one supported platform
cannot become unrestorable on the other. Stronger parameters require a later protocol
revision plus compatibility measurements across the supported device floor. The backup
blob stores its format version, KDF parameters, salt, nonce, and the archive key encrypted
with authenticated metadata. Restore rejects parameters below the version floor or above
the version's reviewed resource ceiling before allocation.

The server cannot validate the recovery secret. A wrong secret is detected only by AEAD
failure. Recovery never restores a revoked device identity or live ratchet state. History
records are encrypted snapshots/events under archive subkeys derived by record ID; a new
device may read history but establishes fresh live sessions. Historical group content may
be displayed from the archive, but sending remains disabled until an authenticated
current member supplies current MLS membership. If no such member is available, the user
must be re-invited; recovery alone never claims to restore current group authorization.

An unlocked device may rotate recovery without changing the archive key: generate a new
recovery secret and salt, derive a new Argon2id wrapping key, upload a higher-version
backup, show the new secret once, and erase it from application storage. The prior secret
cannot unwrap the replaced backup. Rotation does not re-encrypt the full history log.

## Profiles and labels

Account profile, device labels, group metadata, and room names are encrypted with scoped
keys derived or distributed inside authenticated conversations. A profile payload may
contain an encrypted attachment capability for an avatar because the backend profile
bucket is intentionally small. Keys for different metadata classes are domain-separated.

The backend directory username is the only presentation identity available before an
authenticated profile key arrives. During that bootstrap state the UI shows the username
and a local deterministic placeholder avatar derived from a domain-separated hash of the
user ID. It does not show unverified cached display names. A pairwise session distributes
`profile.publish` to a DM peer; an MLS-authenticated profile announcement distributes it
to group peers. Only a successfully authenticated profile with a live-device signer may
replace the fallback.

Fixed-bucket metadata uses `MetadataBlobV1`:

```text
version-byte || 24-byte random nonce
  || XChaCha20-Poly1305(fixed-width real-length || canonical record || random padding)
```

The authenticated plaintext is deterministic CBOR containing scope, object ID, monotonic
revision, previous accepted record hash, author user/device IDs, content, and an Ed25519
signature over the domain label plus the unsigned canonical record. The complete result
is padded to the backend bucket; no plaintext author or revision is exposed to the
server. The outer version and bucket size are associated data; the real-length prefix is
inside the authenticated ciphertext and is validated before padding is removed.

For account profiles, the protocol revision equals the backend profile `version` and a
valid signer must be a live device of that account. For room names, all current client-
authenticated room peers may sign. Clients select the greatest valid
`(revision, author_device_id, record_hash)` successor and announce the accepted hash in a
durable `room.control` event. Because the backend does not compare room revisions, an
accepted peer repairs a stale or replayed `name_blob` with the converged record. A new
peer receives the current record and key in its authenticated invite.

Device-label blobs use an account-local label key and are readable only by the account's
devices. MLS key packages are placed in a versioned wrapper containing the exact RFC 9420
KeyPackage length and bytes, then randomly padded to an allowed 2,048- or 8,192-byte
backend bucket. The signed KeyPackage remains unmodified inside the wrapper.

## Key lifecycle

- Secrets are generated with the platform CSPRNG through the shared crypto core.
- Ratchet message keys and obsolete MLS epoch secrets are erased as soon as allowed by
  their protocols.
- Logout, revocation, database-key loss, or integrity failure wipes local content keys
  and session credentials.
- No key, plaintext, nonce-bearing capability, or secret buffer crosses a log boundary.
- Debug features capable of printing cryptographic state are disabled in all builds used
  with real accounts.

## Protocol upgrade policy

Encrypted objects carry a major version. Unknown major versions are retained as
unsupported and never interpreted. Minor additive fields are ignored only when the schema
marks them optional. Crypto-suite changes require a dual-read/controlled-write migration,
interoperability fixtures, and an ADR; silent algorithm substitution is forbidden.

## Primary references

- [Signal X3DH specification](https://signal.org/docs/specifications/x3dh/)
- [Signal Double Ratchet specification](https://signal.org/docs/specifications/doubleratchet/)
- [RFC 9420: Messaging Layer Security](https://www.rfc-editor.org/info/rfc9420/)
- [OpenMLS](https://github.com/openmls/openmls)
- [RFC 9605: SFrame](https://www.rfc-editor.org/info/rfc9605)
- [RFC 8949: CBOR](https://www.rfc-editor.org/info/rfc8949/)
- [RFC 9106: Argon2](https://www.rfc-editor.org/info/rfc9106/)
- [libsodium secretstream](https://libsodium.gitbook.io/doc/secret-key_cryptography/secretstream)
