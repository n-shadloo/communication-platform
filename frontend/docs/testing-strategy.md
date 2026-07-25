# Testing strategy

## Principles

- Test externally visible behavior and protocol invariants, not provider implementation
  details.
- Use deterministic clocks, CSPRNG fixtures only in tests, fake networks, and fault
  injection.
- Every production bug adds a regression test at the lowest useful layer plus an
  integration test when the failure crossed a boundary.
- Real-secret fixtures are forbidden.

## Test layers

### Domain and application unit tests

- Authentication, connection, outbox, inbox, group-role, receipt, and voice state
  machines.
- Authorization of every event kind.
- Ordering, idempotency, duplicate/replay, delayed lower sender counters, sender-counter
  reuse with a different event ID, stale revision, clock skew, and unknown-version
  behavior.
- Error-code mapping and localized honest wording selection.
- Riverpod use cases with in-memory/fake ports; no widget is required to test domain
  behavior.

### Crypto-core tests

- FIPS 203 ML-KEM, hybrid PQXDH/Double Ratchet, PQ MLS/OpenMLS, Argon2id, CBOR,
  secretstream, and SFrame vectors applicable to the selected implementation.
- Project golden vectors for canonical cross-signing/device bundles, master signatures,
  SAS/QR values, device-log records/gossip, every event, history-transfer batches,
  attachment headers, and protocol upgrades.
- Cross-target byte equality between Android `mlkem_native`/shared native code and the
  reviewed browser Wasm implementation.
- Interoperability between independent devices/versions and, where available, independent
  MLS implementations.
- Property tests for encode/decode, encrypt/decrypt, state serialization, replay, skipped
  messages, and epoch transitions.
- Coverage-guided fuzzing of all untrusted binary parsers and state restoration.
- Negative vectors for altered headers, signatures, associated data, padding, counters,
  final tags, credentials, and group commits.

### Database tests

- Constraints and exactly-once event application.
- Atomic send/receive/MLS boundaries with failure at each statement.
- Migration from every supported released schema and restoration after interrupted
  migration.
- Encrypted database/wrapping-key loss behavior.
- Retention, logout/revocation wipe, and bounded cache cleanup.
- Long-history query plans and stream invalidation.

### Backend contract tests

Run against the real Django development stack, PostgreSQL, Redis, nginx attachment path,
and LiveKit/coturn where applicable:

- every documented status/error and auth scope;
- rotating refresh and concurrent single-flight requests;
- device registration/revocation and 4003 close;
- explicit failure test for the current circular device-ID/cross-signing enrollment
  contract, replaced by successful bootstrap tests once the backend is corrected;
- identity versioning, ETag/device-log-head invalidation, device-log paging, and opaque
  record behavior;
- classical/PQ prekey races, atomic signed-prekey/cross-signature rotation, consumable
  KeyPackage depletion, last-resort reuse, and 4096/16384 buckets;
- envelope fan-out above 256 targets, partial-batch progress, ambiguous retry with exact
  ciphertext reuse, drain pagination, duplicates, ack, stale devices, and TTL behavior;
- WebSocket frame/size/rate limits and all close codes;
- attachment buckets, quota, nginx streaming, expiry;
- seven-day pruning, `pruned_through` detection, and no-history-endpoint assertions;
- voice token expiration/reconnect and disabled configuration.

Contract fixtures MUST fail when backend documentation and behavior diverge.

### Widget and golden tests

- Widgetbook story for every reusable component and state.
- Goldens for narrow/medium/wide widths, light/dark/high-contrast, English/Persian,
  maximum text scale, own/peer/group messages, and all delivery/security states.
- Semantics, keyboard order, focus restoration, shortcuts, context menus, and reduced
  motion.
- Flyer Chat pagination, anchoring, media resolution, jump-to-message, and builder output.

### End-to-end tests

Use at least two accounts and multiple Android/browser devices:

- register, activate, first-device identity publication, cross-signing backup, and
  recovery-secret handling after the enrollment blocker is resolved;
- SAS/QR cross-signing, unsigned-device withholding, master-key change, device-log gossip,
  and server-equivocation fork alarm;
- DM send offline/online, process death, ambiguous retry, delivery/read;
- add/revoke devices, verify valid cross-signed additions, and reject invalid/PQ-missing
  devices;
- create group, concurrent admin changes, add/remove, epoch rotation, history sharing;
- attachment upload/download/corruption/expiry;
- device-to-device full/partial history transfer, no source online, wrong/lost recovery
  secret, identity recovered without history, and mailbox-gap fresh-Welcome recovery;
- voice create/invite/join/reconnect/remove with encrypted media validation;
- logout, remote revocation, local wipe, deep links, and hidden notifications.

Patrol may drive Android native flows. Browser E2E uses a standards-based browser runner
against each supported engine; one browser is not a sufficient web test.

## Adverse-environment matrix

- No network, local-only server, high latency, packet loss, reordering, duplicate frames,
  proxy reset, TLS/pin failure, Redis/backend restart.
- Expired access during REST/WS, refresh response loss, revoked refresh, clock skew.
- Android Doze/standby/force-stop/reboot/permission changes/background-poll delay and
  active-voice foreground-service stop.
- Web tab sleep/reload/multiple tabs/storage eviction/private mode/browser upgrade.
- Low disk, database full/corrupt, attachment cancellation, OOM pressure.
- Malicious peer sending maximum valid and malformed payloads.

## Performance gates

Release budgets are measured on a representative low/mid Android device and supported
browsers:

- startup and database unlock;
- 50,000-message conversation open/search/pagination;
- steady 60 fps interaction for target displays with bounded jank;
- encryption/decryption latency and memory for largest envelope/attachment;
- background battery/network use of best-effort polling;
- voice join time and sustained audio quality;
- no unbounded growth in providers, stream subscriptions, skipped keys, inbox, or cache.

## Security verification

- Static analysis, dependency/license audit, SBOM, secret scan, and release-config audit.
- Confirm no foreign DNS/network attempt in an isolated-network rehearsal.
- Inspect logs, notifications, crash paths, backups, screenshots, clipboard, and temporary
  files for forbidden data.
- Independent security assessment and remediation sign-off.

## Merge and release gates

Pull requests require formatting, analysis, affected unit/widget tests, and documentation
updates. Release additionally requires all target builds, crypto vectors, migrations,
backend contracts, E2E matrix, accessibility, performance, offline rehearsal, and
security review to pass. Coverage percentage alone cannot waive an invariant test.
