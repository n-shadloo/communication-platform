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
6. Drain `GET /api/v1/me/envelopes` until `has_more` is false.
7. Process persisted outbox work and prekey/key-package maintenance.
8. Subscribe to only the presence/rooms required by visible or active features.

Socket events may arrive during drain. Inbox uniqueness and event IDs make ordering safe.

## Incoming durable envelopes

For each envelope:

1. Reject impossible bucket/size metadata before decoding.
2. Insert the envelope ID with `received` state; duplicates reuse the existing row.
3. Ask the crypto core to authenticate/decrypt using bounded work.
4. Validate protocol schema, sender binding, replay state, authorization, and
   dependencies.
5. In one transaction apply the event and mark the envelope `applied`.
6. Queue any delivered receipt and encrypted history record.
7. Ack via WebSocket or REST only after the transaction commits.
8. Mark acked locally; an ambiguous ack is retried idempotently.

Authentication failure, unknown session, missing MLS epoch, and unsupported version are
different quarantine reasons. Recoverable dependency gaps trigger bounded repair; forged
or malformed input never triggers an unbounded network loop.

## Outbox

Outbox operations use these states:

```text
queued -> preparing -> ready -> sending -> accepted
                  \                 \
                   -> blocked        -> retry_wait -> sending
                                          \
                                           -> permanently_failed
```

- `preparing` refreshes device lists, creates/repairs sessions, and encrypts independently
  for each recipient.
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

- Own/peer device ETags prevent unnecessary transfers.
- A changed peer list creates sessions for additions, invalidates removals, and marks a
  verified safety number changed.
- One-time prekeys are replenished when the server count falls below 50, up to a target
  of 150, staying below the backend cap of 200.
- Signed prekeys rotate periodically with a bounded delayed-message overlap.
- MLS key packages are replenished when the server count falls below 25, up to a target
  of 75, staying below the backend cap of 100.
- `stale_devices` responses immediately invalidate matching outbox targets and trigger one
  ETag refresh. Newly discovered eligible replacement devices receive independently
  encrypted target rows with the same logical event ID; already accepted targets do not.

## History archive

After a durable event is applied, an encrypted archive record is queued. Records append
in bounded batches to `/api/v1/me/history`. The client tracks the server-assigned sequence
range only as an archive cursor. Restore pages from `after=-1` until `has_more=false`,
authenticates/decrypts each record, and applies it idempotently by event ID.

An archive failure never blocks live message acknowledgement once the local event is
durable, but remains visible in security/recovery status until retried.

## Volatile signals

Typing, presence, and ephemeral room signals do not enter the durable inbox. They have
strict expiry, bounded maps, and are cleared on disconnect. UI never converts absence of
a signal into durable message or membership state.

## Android and web lifecycle

- Android foreground mode may keep the socket and local notification pipeline active.
  Without it, resume performs a full drain.
- WorkManager may schedule best-effort catch-up but is not advertised as instant delivery.
- Web listens while the page is active. Visibility resume and network recovery refresh
  auth, reconnect, and drain.
- Browser service-worker background sync is optional enhancement only; limited cross-
  browser availability means correctness never depends on it.

## Observability

Metrics are local counters with coarse, non-identifying categories: connection attempts,
queue depth, retry cause, processing latency bucket, and migration status. A user may
explicitly export a redacted diagnostic report. Automatic external telemetry is
forbidden.
