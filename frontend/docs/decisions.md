# Architecture decisions

This file is the initial ADR register. A changed accepted decision gets a dated ADR; it
is not silently edited out of history.

| ID | Status | Decision | Reason |
|---|---|---|---|
| ADR-001 | Accepted | Feature-first Clean Architecture | Keeps security, sync, UI, and platform concerns independently testable. |
| ADR-002 | Accepted | Drift is the local source of truth | Prevents REST, socket, and optimistic state from diverging in widgets. |
| ADR-003 | Accepted | Riverpod for DI and reactive application state | Supports testable scopes and database-stream projections without global singletons. |
| ADR-004 | Accepted | Dio for REST and a dedicated WebSocket gateway | Centralizes authentication, redaction, refresh, retries, and protocol limits. |
| ADR-005 | Accepted | `go_router` with route guards | Supports deep links and adaptive navigation without navigation in domain code. |
| ADR-006 | Accepted | Forui behind app-owned components | Gains consistent primitives without coupling product design directly to a package. |
| ADR-007 | Accepted | Flyer Chat behind a timeline adapter | Reuses virtualization while allowing exclusive builders or full replacement. |
| ADR-008 | Accepted | Canonical CBOR for encrypted application payloads | Compact, deterministic, binary-safe, and versionable. |
| ADR-009 | Superseded by ADR-025 | X3DH + Double Ratchet for device-pair channels | The binding backend client contract now requires hybrid PQXDH session establishment. |
| ADR-010 | Accepted | RFC 9420 MLS for group membership/key state | Provides standardized asynchronous group FS/PCS and matches backend key packages. |
| ADR-011 | Accepted | Per-recipient pairwise transport wrapping | Prevents identical MLS ciphertext from linking a sender's recipient set at rest. |
| ADR-012 | Accepted | Local-only search | The server never receives content or search terms. |
| ADR-013 | Accepted | No foreign push or telemetry | Required for operation during international disconnection and privacy. |
| ADR-014 | Superseded by ADR-029 | Explicit Android foreground connection mode | The binding backend client contract now requires background polling for messaging. |
| ADR-015 | Accepted | Web is online-session-first | Browser background execution cannot provide native-style delivery guarantees. |
| ADR-016 | Accepted | English and Persian at first release | RTL and mixed-direction behavior must be structural, not retrofitted. |
| ADR-017 | Release gate | Shared reviewed crypto core and independent assessment | A custom, unaudited cryptographic implementation is not production-ready. |
| ADR-018 | Accepted | Padding is authenticated inside each pairwise transport envelope | Prevents ambiguous/unprotected trailing bytes while preserving backend size buckets. |
| ADR-019 | Accepted | Logical fan-out uses durable per-device targets and deterministic batches of at most 256 | Supports the backend limit, partial progress, and crash-safe retries for large multi-device groups. |
| ADR-020 | Accepted | Event IDs and ratchet state reject replay; sender counters do not reject delayed messages | Preserves legitimate out-of-order delivery without losing rollback detection. |
| ADR-021 | Accepted | Missing profile keys render username plus a deterministic local avatar | Avoids presenting unauthenticated profile identity during contact bootstrap. |
| ADR-022 | Superseded by ADR-028 and ADR-030 | Recovery restores history separately from current secure membership | The server no longer stores history; history transfer and identity recovery are separate. |
| ADR-023 | Accepted | Voice-room leave is client membership/key removal, not backend room deletion | Matches the capability-only backend and gives users an honest consequence statement. |
| ADR-024 | Accepted | A restrained neutral/indigo app-owned visual system is the production baseline | Gives Forui and Flyer builders one reproducible identity while allowing later brand assets to replace only brand tokens. |
| ADR-025 | Accepted | Hybrid X25519 + ML-KEM-768 PQXDH establishes every DM session | Protects recorded sessions against harvest-now-decrypt-later and forbids silent downgrade. |
| ADR-026 | Release gate | Groups use a reviewed interoperable PQ MLS ciphersuite | PQ KeyPackages and Android/Web interoperability must be proven before group release. |
| ADR-027 | Accepted | Account cross-signing and a client-signed device log authenticate devices | A hostile server cannot make an unsigned device or identity substitution trusted by clients. |
| ADR-028 | Accepted | History exists only on clients and transfers device-to-device | Matches the backend's removal of server history and states the online existing-device dependency honestly. |
| ADR-029 | Accepted | Android background messaging uses best-effort polling, not a persistent service | Matches the client contract and avoids false delivery guarantees; active voice remains foreground. |
| ADR-030 | Accepted | Recovery backup contains cross-signing identity material, not history keys | Recovery preserves verifiable account identity but cannot recreate local message history. |

## Dependency opinion

The mandated Flutter stack is appropriate. The main qualification is that packages are
replaceable infrastructure/presentation adapters. No package's model is allowed to become
the product protocol. Versions are selected and pinned during scaffolding after platform
spikes, not guessed in this document.

## Decisions that do not block development

- Product name, logo, and final Android application ID remain placeholders.
- Direct APK and self-hosted web distribution are the initial release channels.
- Django Admin remains the administration surface; a client admin feature is out of
  scope.
