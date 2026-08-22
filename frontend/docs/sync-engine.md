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
5. Open WebSocket; Android sends the bearer header. A future Web client sends the
   required first auth frame within the backend deadline.
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
6. clears the state only after each group is safely rejoined or explicitly left; in
   that same transaction it advances the acknowledged loss baseline through the
   observed `pruned_through` value and releases locally retained MLS-blocked envelopes,
   preventing the already-recovered permanent gap from reopening on every drain.

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
- Refresh begins shortly before expiry and is guarded by one mutex inside the owning
  isolate. That mutex does not span isolates. ADR-046's durable delivery lease, which an
  earlier revision of this document credited with covering that gap, was removed by
  ADR-049 and never shipped; what prevents two coordinators from racing the rotating
  refresh token is ADR-050's in-process ownership gate, asked for by the *entry point*
  before storage is opened or a token is read.
- Every successful refresh atomically replaces both access and rotated refresh tokens, and
  compares against the durable row rather than the isolate's own cache, so a rotation
  cannot overwrite a newer pair another owner persisted while it was in flight.
- An invalid/replayed refresh token ends the session; it is not retried indefinitely. One
  case is excepted, because the backend blacklists a refresh token the moment it is
  rotated and so answers a lost race and a real session ending identically: if the durable
  row no longer holds the token just presented, another owner in this process rotated
  first, and the coordinator adopts what that owner wrote instead of ending the session
  (ADR-050). It waits a bounded number of re-reads for the row to move; a row that never
  moves means no working token exists, and the session is ended exactly as before.
  `token_revoked` is never repaired this way — a revoked device or a dead account cannot be
  fixed by presenting a different token.
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
  `bundle_version`, then appends the prepared device-log record before maintenance is
  considered complete. A peer observing the narrow intermediate state waits for an
  extending log record; it does not convert an otherwise exact monotonic rotation into
  permanent fork evidence.
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

## Android lifecycle and post-v1 Web direction

ADR-046 makes delivery layered, and every layer drives this same engine.

- **Foreground.** Android holds the WebSocket while the application lifecycle permits.
  Socket frames are wake-up hints; the authoritative REST drain is what moves messages.
- **Background floor.** A persisted periodic `JobScheduler` job performs one best-effort
  drain behind the `AndroidPollingScheduler` port (ADR-049, which replaces ADR-046's
  `WorkManager` mechanism: `JobInfo` is in the framework at `minSdk` 24 and
  `setPersisted(true)` survives a reboot with no receiver of this application's own). It
  is not instant, not exact-periodic, and not reliable after force-stop; its floor is the
  platform's 15 minutes, Doze defers it to maintenance windows that thin out, the *rare*
  and *restricted* standby buckets give it no network at all, and Android 13+ moves an
  application into *restricted* after eight days without user interaction. The job is
  armed once for the life of a signed-in session rather than on each background
  transition, because registering a periodic job restarts its window.
- **Background near-real-time, opt-in and off by default.** A `specialUse` foreground
  service keeps the process out of the cached state so the same socket survives — a frozen
  app's TCP sockets are terminated by the system — and gives the process the one app state
  Android documents as having unrestricted background network. It hosts the same isolate
  and the same supervisor. Messaging still never starts a `dataSync` or `remoteMessaging`
  service.
- **Exactly one delivery owner at a time**, arbitrated in the process rather than in the
  database (ADR-049, replacing ADR-046's durable lease; placement corrected by ADR-050).
  Concurrent owners would race `TokenCoordinator` instances on a *rotating* refresh token
  — the loser presents a retired one, the backend answers 401 `invalid_token`, and the
  session ends — and would hand the same envelope to the ratchet twice, because
  `beginNextEnvelopeInspection` deliberately re-offers rows left `inspecting` by a crash.
  The job service runs in the default process and the Flutter engine documents one Dart VM
  per process, so every owner is on one main looper: a wake-up goes to the isolate that
  already exists, and a headless engine starts only when none does.
- **The foreground asks for ownership at the entry point, not at the delivery session.**
  ADR-049 placed that question in `MessageDeliverySession.compose`, which is reached only
  after `AuthenticationController.restore()` — and that restore is itself a rotation of the
  shared refresh token, so the gate sat downstream of the damage it existed to prevent.
  `bootstrap()` now asks before `ApplicationRuntime` is built, which covers restoration,
  delivery, alerts and anything added later with one gate. The session-level check remains
  as a second, normally instant one.
- **The catch-up is the owner that gives way, and it is asked rather than killed.** A
  deferred run exists only because nobody was looking; the moment somebody is, the
  foreground drains the same mailbox within seconds. Attaching a foreground engine —
  which happens in `configureFlutterEngine`, before that engine's Dart entry point runs —
  asks the run in flight to stand down. `DurableSyncEngine` reads that signal *between*
  units of work: before each envelope inspection, each drain page and each outbox batch. A
  displaced cycle finishes the transaction it holds, reports `deferred`, and stops; the
  run reports `displaced`, skips its alert pass because the foreground now owns the shade,
  and reports finished. Abandoning mid-flight is what `onStopJob` and the engine deadline
  do, because the platform has already taken that decision; it is never the ordinary path,
  because a call into the shared native cryptographic core must be allowed to finish.
- **Nothing about the arbitration is durable, deliberately.** Every owner it arbitrates
  between lives in the one process, so process death releases all of it at once and there
  is no stale holder to detect, expire or displace — and no clock to be wrong about. Every
  wait it imposes is bounded, and every bound expires into *proceeding* rather than into
  stopping, so the mechanism cannot wedge delivery. What that costs when it fails is one
  redundant token rotation, which the coordinator repairs, rather than a sign-out.
- **A deferred wake-up is acknowledged, not fired and forgotten.** The platform lets the
  process be frozen again once the job is finished, so an unacknowledged tick is a drain
  the system stops part-way. `BestEffortDeliveryTick.complete()` is called unconditionally,
  including when the cycle failed.
- **Notifications are a projection of committed state.** Implemented 2026-08-21 under
  ADR-048, which amends this line: the trigger is a durable-state signal rather than
  post-inbox-commit work, because that hook fires only when the engine runs and so can
  announce but never *withdraw* — and reading elsewhere, a sender withdrawing content,
  opening the conversation and muting it are all changes to committed state no post-drain
  hook observes. Drift dispatches table updates only after `COMMIT`, so the signal is
  strictly post-commit. Deduplication is a durable boolean marker, recovery is by query
  rather than replay, and no transport event can produce an alert.
- An active voice session alone uses the required microphone/communication foreground
  service.
- A future Web client listens while the page is active. Visibility resume and network
  recovery refresh auth, reconnect, and drain.
- A future browser service-worker background sync is optional enhancement only; limited
  cross-browser availability means correctness never depends on it.

## Composition and ownership

ADR-046's Layer 0 was implemented on 2026-08-21 (ADR-047). Before that the supervisor, the
socket gateway and the realtime adapter were constructed only in tests and
`durableSyncEngineProvider` was read by nothing, so the artifact neither drained its
mailbox nor transmitted its outbox. What runs now:

- **One networking foundation.** `AuthenticationAssembly` owns a single
  `NetworkingFoundation` — one `DioRestClient`, one `TokenCoordinator`, one provisioned
  trust context — and builds the delivery socket from it. There is no second client and
  no second coordinator: two coordinators would both rotate the same refresh token, and
  the loser would present one the server has already retired, ending the session for
  both.
- **The application root owns delivery, not a screen.** `MessageDeliveryController` is a
  Riverpod notifier that the root holds through `listenManual`, because subscriptions
  created in `build` are paused when their widget leaves the view and a paused controller
  would stop starting and stopping sessions. It runs exactly one
  `MessageDeliverySession` at a time, serializing transitions onto one queue and
  re-checking the wanted scope after every await.
- **A session exists only for a device-bound full session.** It starts on `fullScope` or
  `offlineFullScope` and stops when logout *begins* rather than when it completes,
  because `TokenCoordinator.logout` wipes protected storage and closes the database
  before it emits the termination.
- **Sending is a durable write, not a call.** A composer writes exact per-recipient
  ciphertext rows and returns; the supervisor watches the durable projection and requests
  a cycle when the outbox depth *increases*. That is what makes a queued message leave
  the device with no further stimulus, what drains rows queued before a restart, and what
  keeps a row waiting out its backoff from spinning the engine — only a new durable
  target grows the depth, while every engine run re-emits the projection.
- **Platform edges are one port.** Connectivity, application lifecycle, wall-clock delay
  and the deferred scheduler resolve and release together as `DeliveryPlatformPorts`. An
  unreported platform lifecycle state at launch is read as foreground, because Flutter
  leaves `lifecycleState` null until the first platform message and reading it as
  background would make a session started at launch stand itself down. Every foreground
  transition re-reads connectivity, because Android 8.0 and above does not deliver
  connectivity changes to a backgrounded app.
- **Layer 1 is built; Layer 2 is not.** The Android build composes
  `PlatformDeferredDeliveryScheduler` behind `AndroidBestEffortPollingPort`, so a
  backgrounded application performs an *eventual* catch-up. Every other target composes
  `UnscheduledBestEffortPolling`, which schedules nothing and says so. Near-real-time
  background delivery would need ADR-046's opt-in `specialUse` foreground service, which
  remains unbuilt, and the enrollment disclosure states the difference at revision 3.
- **A headless catch-up composes from the same root.** `ApplicationRuntime` builds the
  provisioned trust context, the single `TokenCoordinator` and the environment-gated
  crypto core for both entry points, so the background path cannot quietly establish a
  weaker posture than the foreground one. It opens no socket — a cached process is frozen
  and its TCP sockets are terminated — and runs one `synchronize()` followed by one alert
  reconciliation. Its container takes exactly one override the activity's does not: the
  signal that tells it it is no longer the delivery owner.
- **One SQLCipher connection, shared, not two.** `drift_flutter`'s `shareAcrossIsolates`
  resolves through `IsolateNameServer`, which the Flutter engine owns per Dart VM and
  therefore per process, so a headless isolate connects to the *same* database server
  isolate rather than opening a second connection to the same file. Drift serializes
  transactions across every connected client, so a transaction is already mutually
  exclusive between owners. That is a precise limit: it makes writes atomic, and it does
  nothing for a logical operation that spans transactions with network I/O in between —
  read token, rotate, write token; claim envelope, decrypt, commit. Those are exactly the
  operations ADR-050 excludes.
- **Layer 3 is built and is not part of the delivery session.** ADR-048 composes
  `MessageAlertController` at the application root, beside `MessageDeliveryController` and
  deliberately not inside it: a delivery session that fails to compose still leaves
  messages in the database that arrived before it and have never been announced. It
  observes committed rows, not the engine, so it needs nothing from the transport and
  announces nothing when the process is not alive.

## Observability

Metrics are local counters with coarse, non-identifying categories: connection attempts,
queue depth, retry cause, processing latency bucket, and migration status. A user may
explicitly export a redacted diagnostic report. Automatic external telemetry is
forbidden.
