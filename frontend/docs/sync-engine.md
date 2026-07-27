# Synchronization engine

## Goals

The sync engine turns at-least-once REST/WebSocket delivery into exactly-once logical
application, preserves offline sends, and converges devices without treating volatile
signals as durable truth.

## Connection state machine

```text
booting -> unreachable
   |
   v
anonymous -> register_scope -> registering_device -> full_session
                                              |
                                              v
                    refreshing <-> connecting_socket
                                              |
                                              v
                      draining <-> online <-> reconnecting
                                              |
                                              v
                                   revoked / signed_out
```

States and transitions are explicit domain values. UI text is derived from them. No
boolean combination such as `isLoading && !hasToken` defines authentication behavior.

## Startup sequence

1. Load provisioned trust configuration and open protected local storage.
2. Validate local schema and key handles.
3. Call anonymous health only against the configured server.
4. Load/refresh the device-bound session through a single-flight token coordinator.
5. Open WebSocket; native sends the bearer header and web sends the required first auth
   frame within the backend deadline.
6. Drain `GET /api/v1/me/envelopes`; before processing a page, compare its
   `pruned_through` with the durable highest contiguous acked sequence.
7. If `last_acked_seq < pruned_through`, enter queue-gap recovery before accepting
   potentially dependent MLS traffic; otherwise drain until `has_more` is false.
8. Process persisted outbox work, cross-signing/device-log verification, and
   classical/PQ prekey and KeyPackage maintenance.
9. Subscribe to only the presence/rooms required by visible or active features.

Socket events may arrive during drain. Inbox uniqueness and event IDs make ordering safe.

## Incoming durable envelopes

For each envelope:

1. Reject impossible bucket/size metadata before decoding.
2. Insert the envelope ID with `received` state; duplicates reuse the existing row.
3. Ask the crypto core to authenticate/decrypt using bounded work.
4. Validate protocol schema, sender binding, replay state, authorization, and
   dependencies.
5. In one transaction apply the event and mark the envelope `applied`.
6. Queue any delivered receipt; local message history is already durable in Drift and is
   never uploaded to a history API.
7. Ack via WebSocket or REST only after the transaction commits.
8. Mark acked locally; an ambiguous ack is retried idempotently.

Authentication failure, unknown session, missing MLS epoch, and unsupported version are
different quarantine reasons. Recoverable dependency gaps trigger bounded repair; forged
or malformed input never triggers an unbounded network loop.

## Queue-gap recovery

The backend retains undelivered envelopes for seven days. `pruned_through` is the highest
sequence pruned from this device mailbox. If the durable highest contiguous acked
sequence is lower, at least one envelope is permanently missing and may have been an MLS
commit. The client:

1. persists a blocking `queue_gap` security state and stops group sends/epoch mutation;
2. keeps safely decryptable DM/local content but never guesses missing MLS state;
3. marks every current group as potentially affected until peers confirm otherwise;
4. sends authenticated recovery signals where sessions remain usable;
5. asks peers to remove and re-add this device to affected groups, producing fresh
   Welcomes; and
6. clears the state only after each group is safely rejoined or explicitly left.

Device-to-device history transfer cannot repair ratchets or MLS epochs and is not used as
a substitute for this flow.

## Outbox

Outbox operations use these states:

```text
queued -> preparing -> ready -> sending -> accepted
                  \                 \
                   -> blocked        -> retry_wait -> sending
                                          \
                                           -> permanently_failed
```

- `preparing` refreshes identity, device list, and device-log head; refuses unsigned,
  unverified, forked, or classical-only peers; then creates/repairs hybrid sessions and
  encrypts independently for each recipient.
- The operation snapshots eligible devices, sorts targets by UUID bytes, and creates one
  durable target row containing the exact encrypted blob for every recipient. Pending
  targets are sent in deterministic batches of at most 256, matching the backend limit.
- An HTTP 202 marks every target in that request except returned `stale_devices` accepted;
  returned stale targets are terminal and their sessions are invalidated. The accepted
  count must equal `request targets - stale_devices`, otherwise the response is treated
  as a protocol error.
- A logical send becomes `accepted` only after every target is accepted, stale, or
  explicitly removed by a refreshed eligibility decision. Earlier successful batches
  are never resent merely because a later batch fails.
- A transport timeout after upload is ambiguous; retrying is safe because recipients
  deduplicate logical event IDs. The retry reuses the persisted ciphertext for the same
  target; it never advances that target's ratchet twice.
- Authentication failure enters single-flight refresh; it does not independently refresh
  in every request.
- 429 honors `Retry-After` when present and otherwise applies capped exponential backoff
  with full jitter.
- Validation/crypto errors are permanent until user action or a protocol repair changes
  their cause.

## Backoff and liveness

Realtime reconnect uses exponential backoff with full jitter, resets only after a stable
connection, and pauses when the OS reports no network. The client never pings a foreign
host. App-level liveness uses conservative WebSocket ping/traffic behavior compatible
with the backend/proxy configuration and a REST health probe only when necessary.

## Token lifecycle

- Access expiry is tracked from token claims with clock-skew allowance.
- Refresh begins shortly before expiry and is guarded by one process-wide mutex.
- Every successful refresh atomically replaces both access and rotated refresh tokens.
- An invalid/replayed refresh token ends the session; it is not retried indefinitely.
- WebSocket close 4001 attempts one valid refresh/reconnect cycle.
- Close 4003 or REST `token_revoked` immediately wipes the local device session.
- Close 4008 is a client protocol defect/security event and uses a circuit breaker.
- Close 4403 is a deployment-origin error and is not retried rapidly.

## Device maintenance

- Own/peer device ETags cover device sets and log heads and prevent unnecessary transfers.
- A changed peer list is accepted only after exact device cross-signature verification
  and device-log extension. A valid addition under the verified master creates sessions;
  a master-key change, invalid signature, or log fork blocks sensitive operations.
- One-time prekeys are replenished when the server count falls below 50, up to a target
  of 150, staying below the backend cap of 200.
- ML-KEM one-time prekeys are replenished below 25 up to a target of 75, staying below
  the backend cap of 100.
- Signed classical/PQ prekeys rotate every seven days with an eight-day delayed-message
  overlap. Rotation atomically supplies a new `cross_sig` and increments
  `bundle_version`.
- After the [PQ MLS production gates](mls-profile.md#production-gates) pass, MLS key
  packages are replenished when the server count falls below 25, up to a target of 75,
  staying below the backend cap of 100. Before then, no production package is uploaded.
- One PQ MLS last-resort KeyPackage is then maintained separately from the consumable
  count; its use is surfaced as degraded initial-join forward secrecy and triggers
  immediate consumable replenishment.
- Every own device-set/identity change appends a self-signing-key-signed hash-chain record.
  Verified peer log heads are piggybacked in ordinary encrypted events for equivocation
  detection.
- `stale_devices` responses immediately invalidate matching outbox targets and trigger one
  ETag refresh. Newly discovered eligible replacement devices receive independently
  encrypted target rows with the same logical event ID; already accepted targets do not.

## Device-to-device history transfer

The server has no history endpoint. After a new device is cross-signing-authorized, an
existing online device snapshots locally held history into bounded transfer events,
encrypts each to the new device through ordinary hybrid pairwise envelopes, and records
transfer progress by event ID. The receiver authenticates, stores, and deduplicates each
event before acknowledging it. Transfer is resumable, may be partial when the source
device has partial history, and never includes ratchet private state or MLS epoch secrets.

No online existing device means no history transfer. The UI states that limitation and
does not imply that the recovery secret or server can reconstruct content.

## Volatile signals

Typing, presence, and ephemeral room signals do not enter the durable inbox. They have
strict expiry, bounded maps, and are cleared on disconnect. UI never converts absence of
a signal into durable message or membership state.

## Android and web lifecycle

- Android keeps the WebSocket only while the application lifecycle permits. WorkManager
  performs best-effort background polling/drain; it is not instant, exact-periodic, or
  reliable after force-stop. Messaging never starts a persistent foreground service.
- An active voice session alone uses the required microphone/communication foreground
  service.
- Web listens while the page is active. Visibility resume and network recovery refresh
  auth, reconnect, and drain.
- Browser service-worker background sync is optional enhancement only; limited cross-
  browser availability means correctness never depends on it.

## Observability

Metrics are local counters with coarse, non-identifying categories: connection attempts,
queue depth, retry cause, processing latency bucket, and migration status. A user may
explicitly export a redacted diagnostic report. Automatic external telemetry is
forbidden.
