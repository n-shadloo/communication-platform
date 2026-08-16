# Local data model

## Principle

Drift is the durable source of truth. REST, WebSocket, user commands, crypto results, and
background work may modify UI-visible state only through repositories that execute Drift
transactions. Riverpod observes database queries and exposes immutable projections.

## Storage classes

### Android

Use SQLite encryption with a random database key. Wrap that key with an Android Keystore
AES key, preferring hardware-backed storage when available. Exclude the database,
wrapping material, attachments, and key files from Android backup. Plaintext may exist
inside the unlocked encrypted database and process memory, never in ordinary files.

### Web (post-v1)

Persist device state and content only as encrypted records. Store a non-extractable
WebCrypto wrapping key in IndexedDB when supported and wrap the local storage key. Drift
Wasm may store ciphertext/index metadata, but decrypted message bodies and the search
index remain memory-only and are cleared on logout/page teardown as far as the browser
allows. Same-origin malicious code remains an acknowledged limit.

## Logical tables

Names are conceptual; migrations may refine physical layout without changing ownership.

| Table | Purpose |
|---|---|
| `account_session` | Current user/device IDs, scope, token metadata, server profile |
| `enrollment_intents` | Resumable first/later-device phase, generated opaque device/identity state, assigned device ID, backup, and exact pending device-log append |
| `secure_secrets` | Wrapped cross-signing/device/PQ/storage key handles; never raw loggable bytes |
| `account_identity` | Verified master/self/user-signing public state, backup version, recovery status |
| `users` | Activated directory entries and local presentation state |
| `profiles` | Encrypted/decrypted profile cache, version, verification state |
| `devices` | Own and peer public bundles, ETags, labels, revocation state |
| `device_log` | Verified signed hash-chain records, last head/hash, fork state, gossip state |
| `pairwise_sessions` | Opaque crypto-core Double Ratchet state per device pair |
| `prekeys` | Local private prekey handles and upload/use state |
| `mls_groups` | Opaque crypto-core MLS state, accepted epoch, control revision/hash, lifecycle/quarantine state, and pending mutation CAS marker |
| `group_control_events` | Deterministic accepted control projection, exact signed-control payload, and signer Authentication Service proof |
| `group_outbound_objects` | Exact prepared opaque group object and send-readiness state; piece 18 never marks development preview data production-ready |
| `conversations` | DM/group/saved identity and list projection |
| `memberships` | Decrypted current group roles/policy projection |
| `messages` | Current logical message projection and status |
| `message_events` | Immutable create/edit/delete/reaction/control facts |
| `attachments` | Encrypted descriptor, transfer state, bounded cache handle |
| `inbox_envelopes` | Backend envelope ID/seq, processing and ack state |
| `outbox_operations` | Durable logical sends, deterministic <=256-target batches, and per-recipient attempts/ciphertext |
| `receipts` | Per-message/device/user delivered/read projection |
| `voice_rooms` | Local room capability, encrypted metadata, live state |
| `history_transfers` | Device-to-device content transfer manifests, event progress, source completeness |
| `sync_checkpoint` | Highest contiguous acked seq, `pruned_through`, ETags, retry state, protocol version |
| `local_preferences` | Theme, language, mute, pin, star, preview policy |
| `quarantine` | Bounded metadata about rejected input; never plaintext or raw secrets |

## Identity and uniqueness

- `event_id` and logical `message_id` are globally unique random IDs.
- Backend envelope IDs are unique inbox keys.
- Applying the same event more than once is a no-op.
- Outbox uniqueness includes logical operation and recipient device, so a refreshed
  device list can add work without duplicating accepted recipients.
- Each target persists the exact encrypted blob until terminal acceptance/staleness so an
  ambiguous retry cannot advance the Double Ratchet a second time.
- Database constraints enforce uniqueness; application pre-checks alone are insufficient.

## Transaction boundaries

### Send

One transaction creates/updates the logical event, optimistic message projection, and
outbox operation. Encryption/network execution occurs outside the DB
transaction; its result is committed in a second transaction.

### Receive

One transaction records the envelope, applies a verified event, updates projections,
creates receipts, advances the contiguous sequence checkpoint when allowed, and marks
the envelope ready to acknowledge. The ack is
sent only after commit. A crash before ack causes a safe duplicate.

### Device enrollment

Before the registration POST, one encrypted-database transaction persists the flow,
phase, public-key fingerprint, and complete Rust-owned device key package. The POST is
never automatically replayed after an in-flight process death or transport response
loss. Its assigned device ID, full-scope refresh material, and `registeredUnsigned`
journal phase commit in one transaction; an in-flight row observed after restart is
converted to the explicit ambiguous-outcome reconciliation phase.

Every later phase is persisted before its network side effect can be retried. In
particular, the exact device-log record and predicted sequence are durable before
append. Completion atomically moves the opaque device and cross-signing identity
packages to `secure_secrets`, writes the verified local public projections, deletes the
enrollment row and new-account marker, and only then releases the route-level messaging
withhold. The entered recovery secret is never a column. The first-device display
secret exists only inside the encrypted, resumable identity package until explicit
confirmation, after which display material is sanitized and overwritten.

### MLS state

New MLS state, control event, membership projection, conversation projection, and exact
outbound object commit atomically with a control revision/hash compare-and-swap. A
process crash or persistence failure cannot expose a group transition or application
message from an epoch whose complete opaque state was not persisted. Queue gaps and
invalid or concurrent controls move the projection to a blocking quarantine state
without guessing or replacing crypto-core state.

A later closed-beta Welcome transaction additionally consumes the claimed KeyPackage and
stores the complete verified control transcript with the joined opaque state and roster
projection. Transcript rows redundantly preserve the deterministic projection, exact
signed payload, and signer authentication proof so a new device can reconstruct and
cross-check authorization rather than trusting a server-supplied projection.

## Migrations

- Every schema change has forward and rollback/restore tests using representative
  encrypted databases.
- Migrations are transactional where SQLite permits.
- Crypto-format changes are separate from SQL schema changes.
- A failed migration leaves the previous database recoverable and blocks normal startup
  with a non-destructive error.
- Release builds never auto-delete a database to "fix" migration failure.
- Schema version 11 adds nullable deterministic-projection, signed-payload, and signer-
  proof columns to `group_control_events` while preserving older rows. An older row may
  remain readable as local history, but absent cryptographic evidence cannot construct a
  verified v3 Welcome transcript and therefore fails closed. Disposable v2 beta groups
  must be recreated/rejoined; no opaque MLS state is silently rewritten.

## Retention and deletion

- Acked raw envelopes are removed after their logical event and local projection are safe.
- Ratchet skipped keys and old MLS states obey strict protocol bounds.
- Decrypted attachment files and thumbnails use bounded LRU caches with explicit expiry.
- Delete-for-me creates a tombstone before cache cleanup.
- Logout/revocation closes handles, deletes the database key, then removes database and
  cache files. Key destruction is the primary cryptographic erasure boundary.

## Search

Android maintains a local index inside the encrypted database. A future Web build uses an
in-memory index from decrypted session content. Search input/results never leave the
device. The UI states that results cover only history available on this device.
