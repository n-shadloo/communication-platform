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
| `secure_secrets` | Wrapped cross-signing/device/PQ/storage key handles; never raw loggable bytes |
| `account_identity` | Verified master/self/user-signing public state, backup version, recovery status |
| `users` | Activated directory entries and local presentation state |
| `profiles` | Encrypted/decrypted profile cache, version, verification state |
| `devices` | Own and peer public bundles, ETags, labels, revocation state |
| `device_log` | Verified signed hash-chain records, last head/hash, fork state, gossip state |
| `pairwise_sessions` | Opaque crypto-core Double Ratchet state per device pair |
| `prekeys` | Local private prekey handles and upload/use state |
| `mls_groups` | Opaque crypto-core MLS state and accepted epoch |
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

### MLS state

New MLS state, control event, membership projection, and processed-event marker commit
atomically. A process crash cannot expose an application message from an epoch whose
state was not persisted.

## Migrations

- Every schema change has forward and rollback/restore tests using representative
  encrypted databases.
- Migrations are transactional where SQLite permits.
- Crypto-format changes are separate from SQL schema changes.
- A failed migration leaves the previous database recoverable and blocks normal startup
  with a non-destructive error.
- Release builds never auto-delete a database to "fix" migration failure.

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
