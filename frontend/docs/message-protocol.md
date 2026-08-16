# Application-message protocol

## Purpose and status

The backend routes opaque per-device blobs and intentionally has no conversation schema.
This document defines the encrypted version-1 application events carried inside the
cryptographic protocol. Exact deterministic-CBOR CDDL and golden byte fixtures MUST be
generated with the shared protocol package before implementation is considered stable.

## Layering

```text
logical event
  -> DM: deterministic-CBOR application bytes
  -> group: MLS PrivateMessage bytes
  -> TransportPlaintextV1(real length, inner bytes, random padding)
  -> per-recipient Double Ratchet authenticated encryption
  -> EnvelopeV1 outer frame in an allowed backend bucket
  -> base64 in POST /api/v1/envelopes
```

The application event, sender, conversation, and content type are encrypted. The backend
sees the target device, timing, and final size bucket only.

## Common logical-event header

Every event has these authenticated fields:

| Field | Meaning |
|---|---|
| `v` | Protocol major version, initially `1` |
| `event_id` | 16 cryptographically random bytes; global deduplication identity |
| `conversation_id` | 32-byte conversation identifier |
| `kind` | Registered integer event kind |
| `sender_user_id` | Authenticated account UUID |
| `sender_device_id` | Authenticated device UUID |
| `sender_counter` | Monotonic per-device counter, persisted before send |
| `created_ms` | Sender wall-clock milliseconds for display, not authorization |
| `references` | Bounded list of event/message IDs this event depends on |
| `body` | Kind-specific deterministic-CBOR map |

The decrypted sender identity MUST match the authenticated pairwise/MLS credential.
Timestamps never grant permission and are clamped for display when implausibly skewed.
`sender_counter` detects sender-state rollback but does not create a global conversation
order and is never, by itself, a reason to reject a lower counter: delayed messages are
valid. Durable `event_id` uniqueness provides application deduplication; the Double
Ratchet message number and bounded skipped-key store provide cryptographic replay and
out-of-order handling. Within the retained event horizon, reuse of one sender counter
with a different event ID is quarantined as sender-state rollback. Reuse with the same
event ID is an idempotent duplicate.

DM IDs are a domain-separated hash of the sorted pair of account IDs. Saved Messages
uses a domain-separated hash of the account ID. Group IDs are random 256-bit values.
Voice room capability IDs remain backend UUIDs but are hashed into protocol contexts.

## Event registry

| Kind | Purpose | Durable? |
|---|---|---|
| `message.create` | Text, attachment, or structured message | yes |
| `message.edit` | Replace editable content of an earlier own message | yes |
| `message.delete` | Best-effort remote deletion request | yes |
| `message.reaction_set` | Set or remove the sender user's reaction | yes |
| `message.pin_set` | Pin or unpin a message | yes |
| `receipt.delivered` | Explicit delivered message IDs | yes |
| `receipt.read` | Explicit read message IDs | yes |
| `typing.set` | Short-lived typing state | no, signal only |
| `profile.publish` | Profile version/key/material announcement | yes |
| `contact.master_verify` | User-signing-key signature over a verified peer master key | yes, own devices and optionally peer |
| `group.control` | Signed group metadata, role, policy, or membership transition | yes |
| `group.history_batch` | Re-shared past events for a new member | yes |
| `history.transfer_manifest` | Authorize and describe own-device history transfer | yes |
| `history.transfer_batch` | Bounded own-device history content batch | yes |
| `device_log.gossip` | Latest verified contact device-log heads | yes |
| `room.invite` | Voice-room capability and encrypted membership material | yes |
| `room.control` | Room metadata or removal event | yes |
| `session.repair` | Authenticated request/response for pairwise repair | yes |
| `protocol.notice` | Supported-version/capability announcement | yes |
| `contact.block_set` | Synchronize private block state to the user's other devices | yes, own devices only |

Unknown kinds are stored as unsupported encrypted events, bounded in size, and never
partially interpreted.

`contact.master_verify` contains the exact peer user ID, master-key bytes/fingerprint,
verification protocol version, and user-signing-key signature. It is created only after
successful out-of-band SAS/QR confirmation, synchronized to the user's own cross-signed
devices, and included in the recovery-protected identity material. It never makes a
server-supplied first-seen key trusted.

## Message creation

`message.create` contains:

- a content discriminator: text, attachment, image, system, or supported custom type;
- UTF-8 text/caption limited to 16,384 Unicode scalar values and 65,536 encoded bytes;
- optional reply target and bounded quote fallback;
- zero to 32 encrypted attachment descriptors;
- optional client accessibility metadata that contains no untrusted markup.

The common `references` list contains at most 64 IDs. Deterministic-CBOR input is limited
to 16 levels of nesting, 64 entries per map, definite lengths only, and the smallest
valid integer encoding. Duplicate map keys, tags not registered by this protocol,
indefinite-length items, non-finite floats, and invalid UTF-8 are rejected. The complete
transport plaintext must fit one backend envelope bucket after fixed suite overhead;
larger content is sent as an encrypted attachment rather than fragmented application
events.

Messages are immutable facts. Editing and deletion produce new events. HTML, executable
markup, remote image URLs, and arbitrary widget payloads are forbidden.

The sender writes the logical message and outbox jobs in one local transaction before
network work. Retrying may create duplicate backend envelopes after an ambiguous HTTP
response; recipients deduplicate by `event_id` and the sender treats the operation as one
logical message.

## Edits, reactions, pins, and deletion

- An edit is accepted only from the original sender identity and contains the target ID,
  replacement content, and a monotonically increasing edit revision. Concurrent valid
  edits resolve by `(revision, sender_counter, event_id)`.
- A reaction event is a set operation for `(target, reacting_user)`, not an increment.
  Its value is one normalized emoji grapheme or null. This makes replay idempotent.
- DM pins are shared conversation events; group pins require the role allowed by current
  group policy. Stars are local-only and never sent.
- Delete for me is a local tombstone. Delete for everyone is an authenticated request
  accepted only from the original sender or an explicitly authorized group moderator.
  It replaces local display with a tombstone and requests attachment-cache deletion; it
  cannot force a recipient to erase previously decrypted content.

## Receipts, typing, and presence

Delivery/read receipts name bounded explicit message-ID sets. A delivered receipt is
sent after durable local application, not merely socket arrival. A read receipt is sent
only after the conversation is visibly read and user privacy settings allow it.

Typing is an encrypted volatile signal containing conversation ID, boolean state, and a
short expiry. It is never queued. Presence uses the backend device subscription but the
meaning shown to users is conservative: online means a subscribed device currently has
a socket, not that the person is actively viewing a chat.

## Blocking

Blocking is private account state, not a backend ACL. `contact.block_set` contains the
target user ID, blocked boolean, monotonic revision, and event ID and is encrypted only
to the user's other live devices. It remains in each device's local history and is never
sent to the blocked contact.

For a blocked DM sender, the client still authenticates/decrypts enough to prevent queue
abuse, records the envelope as processed, and acknowledges it, but does not persist or
display message content, send receipts, subscribe/share presence, show typing, or create
notifications. Blocking does not claim to stop the sender from submitting ciphertext.
In shared groups, required MLS/control state is still processed; blocked authors' ordinary
content may be locally collapsed without corrupting group state.

## Groups

The MLS roster is the cryptographic membership authority. `group.control` adds product
state:

- encrypted name, description, and photo capability;
- owner, admin, and member roles;
- invitation policy;
- history-for-new-members policy;
- membership intent paired to the corresponding MLS commit hash/epoch.

Control events are signed with the device credential key. A new state includes a
revision, previous control-state hash, MLS group ID/epoch, and operation. Clients verify
the signer was authorized in the previous accepted state. The owner alone may transfer
ownership; owners/admins may perform only policy-authorized actions.

Closed-beta group transport v3 makes later Welcome/re-add authentication self-contained.
An Invite carries the complete preceding accepted control transcript plus the current
signed control, exact deterministic projection, and signer Authentication Service
proof. The joining device verifies and replays that bounded transcript from no state,
verifies the current Invite, joins the Welcome, processes the corresponding MLS control,
and requires the BasicCredential `(user_id, device_id)` roster returned by Rust to equal
the reconstructed product roster before committing the new opaque state, transcript,
projections, consumed KeyPackage, and exact outbound work in one transaction. Existing
members verify the same embedded transcript before advancing. The maximum is 512 control
entries; missing evidence, a duplicate, chain disagreement, invalid authorization, or a
roster mismatch fails closed. Long-running groups require a reviewed checkpoint format
before that bound can be raised.

V2 beta state and queued group objects do not contain sufficient transcript evidence and
are rejected. They are disposable under ADR-036/ADR-037: participants recreate or
rejoin the beta group. The client never guesses an upgrade or migrates that state into
production.

Concurrent MLS commits can fork. The application serializes its own membership mutations
per group and never emits dependent application data until the resulting MLS state and
control event commit atomically. A received sibling commit is quarantined rather than
resolved in Dart or UI code. The reviewed shared crypto core MUST supply the canonical
fork/re-proposal algorithm and prove convergence with Android interoperability and
delayed-delivery tests before Android group membership mutation is release-enabled. A
future Web release additionally requires cross-target convergence evidence. Until that
gate passes, the safe behavior is to block the mutation with "membership updating"; the
client never guesses, silently chooses arrival order, or combines incompatible rosters.

When history sharing is enabled, an existing authorized device sends bounded
`group.history_batch` records encrypted to the new epoch. Each item retains its original
event ID and author attribution and is marked as recovered history. The backend cannot
construct this history.

Own-device history transfer uses a cross-signing-authorized manifest followed by bounded
`history.transfer_batch` events over ordinary per-device envelopes. It transfers content
only, preserves original event IDs for deduplication, states source completeness, and
never contains Double Ratchet state or MLS epoch secrets. A mailbox `pruned_through` gap
is repaired by fresh sessions/group Welcomes, not by replaying history batches.

## Multi-device rules

- A user's devices are independent cryptographic recipients.
- The sender fans out to peer devices and their own other devices.
- Own-device sync uses the same logical event ID, preventing duplicates.
- Drafts are local by default. A future encrypted draft-sync event requires a separate
  ADR.
- Read state is merged as an idempotent set of explicit IDs; it is not inferred from one
  device's queue sequence.
- Revoked devices are removed from sessions and MLS at the next authenticated update.
- Each ordinary encrypted event may carry bounded `device_log.gossip` head tuples. A
  non-extending head or two valid heads for the same sequence triggers the global fork
  state; it is never resolved by arrival order.

## Ordering

The backend sequence is per recipient device and is only a drain checkpoint. It is not a
global chat sequence. Presentation order uses validated sender time with deterministic
ID tie-breaking and preserves explicit reply/edit dependencies. The client may annotate
late arrivals but MUST NOT rewrite cryptographic history to manufacture a false global
order.

## Padding and bounds

Padding is encrypted, not appended to ciphertext. `EnvelopeV1` is:

```text
version:u8 || suite:u8 || ratchet_header_length:u16be
  || ratchet_header
  || DoubleRatchetAEAD(
       real_inner_length:u32be || inner_bytes || CSPRNG_padding,
       associated_data = outer_fixed_fields || ratchet_header || recipient_device_id
     )
```

The encoder obtains the serialized ratchet-header size without advancing ratchet state,
chooses the smallest backend bucket in `1024, 4096, 16384, 65536, 262144` that can hold
the fixed outer fields, ratchet header, AEAD tag, length prefix, and inner bytes, and
fills the remaining authenticated plaintext with CSPRNG bytes. It then advances and
persists the send ratchet exactly once while producing the ciphertext. The outer frame
contains no real content length; ciphertext consumes the remainder of the bucket.

The decoder rejects an unknown version/suite, non-bucket total length, impossible header
length, failed AEAD, or inner length beyond the authenticated plaintext before allocating
kind-specific structures. The authenticated real length is used only after decryption to
remove padding. Application content is not compressed by default because compression
before encryption can create size side channels and decompression abuse.

## Compatibility

Event kinds and fields are centrally registered. Removing or changing a field requires a
new major protocol version. Additive optional fields require fixtures proving older
clients ignore them safely. Unsupported critical capability requirements prevent send
and show an upgrade explanation instead of downgrading security.
