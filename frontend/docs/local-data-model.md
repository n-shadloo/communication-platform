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
| `messages` | Current logical message projection, plus the columns the projector preserves rather than rebuilds: `deleted_for_me`, `pinned`, `starred`, `unread`, `alerted` (the durable one-shot marker that stops an arrival being announced twice, ADR-048), `delivered_receipt_sent` ([ADR-060](decisions.md)), and `status` ([ADR-061](decisions.md)) |
| `message_events` | Immutable create/edit/delete/reaction/control facts |
| `attachments` | Encrypted descriptor, transfer state, bounded cache handle |
| `inbox_envelopes` | Backend envelope ID/seq, processing and ack state |
| `outbox_operations` | Durable logical sends, deterministic <=256-target batches, and per-recipient attempts/ciphertext. Authoritative for a message's transport state |
| `pending_send_preparations` | Sends whose event is committed and whose per-recipient ciphertext is still owed: audience, attempt count and due time, keyed by the same operation id as the payload in `pairwise_local_applications`. A row exists while the fan-out is owed and is deleted in the transaction that writes the outbox rows; a terminally failed one is kept, because it is the only durable record that a visible message has no route to the wire ([ADR-061](decisions.md)) |
| `receipts` | Per-message/device/user delivered/read projection |
| `voice_rooms` | Local room capability, encrypted metadata, live state |
| `history_transfers` | Device-to-device content transfer manifests, event progress, source completeness |
| `sync_checkpoint` | Highest contiguous acked seq, `pruned_through`, ETags, retry state, protocol version |
| `local_preferences` | Theme and language (`appearance.theme.v1`, `appearance.language.v1`), mute, pin, star, preview policy, the accepted disclosure revision, and whether the notification permission prompt has ever been shown. Client-only display values live here rather than in a plain file so that the logout wipe, which destroys the database key, destroys them too |
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

**Two transactions, and the request between them is what makes that safe.** The first —
the local echo — writes the logical event, the opaque payload, a `pending_send_preparations`
row, and the message projection. It touches no network, so the message is on the timeline
at the speed of a local write. The second, run by the delivery cycle after it has resolved
the recipient set and sealed one envelope per device, writes the outbox rows and deletes
the preparation row *in the same transaction*. A process killed anywhere between them comes
back to a send that is either owed or queued, never both and never neither
([ADR-061](decisions.md)).

Encryption and network execution still occur outside any database transaction, and the
result is still committed in a second one; what changed is which side of the first
transaction the user's message is on.

A message's transport state is derived from `outbox_operations` when it has rows there and
from `pending_send_preparations` before it does. It is written to `messages.status` at
projection time and updated narrowly on every attempt transition, and a projection rebuild
carries the existing value through rather than re-deriving it — the same rule `alerted`,
`starred` and `delivered_receipt_sent` already follow.

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
- Schema version 14 adds `inbox_envelopes.inspection_failures` and carries a one-shot,
  idempotent repair for the devices that ran the delivery engine before
  [ADR-060](decisions.md): non-terminal inbox and outbox rows are reset to a zero attempt
  count with no due time, a conversation that has messages is un-tombstoned, and a
  conversation whose row is missing entirely is rebuilt minimally from `MAX(ordering_ms)`.
  It touches no message content, no envelope ciphertext and no projection ciphertext, and
  is safe to run twice.
- Schema version 15 adds `messages.delivered_receipt_sent`, a durable one-shot marker in the
  style of `messages.alerted`. Whether a delivered receipt was owed used to be re-derived on
  every projection rebuild from properties of the message that never change, so every rebuild
  re-queued one for every message the conversation had received — and a receipt is an event
  at the far end, so two devices sustained the loop indefinitely ([ADR-060](decisions.md)).
  The upgrade marks every existing message as already acknowledged and empties the pending
  queue, so it does not itself send one more round.

- Schema version 16 adds `pending_send_preparations`, the durable request for a fan-out a
  committed message is still owed ([ADR-061](decisions.md)). Nothing is back-filled and
  nothing is repaired: every message already on a device either has its outbox rows or has
  reached a terminal state, so there is no send this table would have been holding.

## Retention and deletion

- Acked raw envelopes are removed after their logical event and local projection are safe.
- Retained pairwise metadata is pruned on a sixteen-day cutoff, **except** the opaque
  payload of a send whose preparation is still owed. Discarding those bytes would leave a
  message on screen that nothing can ever seal.
- Ratchet skipped keys and old MLS states obey strict protocol bounds.
- Decrypted attachment files and thumbnails use bounded LRU caches with explicit expiry.
- Delete-for-me creates a tombstone before cache cleanup.
- Logout/revocation closes handles, deletes the database key, then removes database and
  cache files. Key destruction is the primary cryptographic erasure boundary.

## Search

The encrypted database **is** the index. `messages` holds the decrypted message
projection inside SQLCipher, under the Keystore-wrapped key, and a search is a filter
over rows that are already there; a conversation's stream carries no limit, so an
in-conversation search covers the whole of that conversation's local history. No separate
index structure is built: it would hold a second copy of every message body, enlarge what
a wipe has to reach, and buy nothing at this scale ([ADR-057](decisions.md)). A future Web
build uses an in-memory index from decrypted session content. Search input and results
never leave the device. Each surface states its own scope.
