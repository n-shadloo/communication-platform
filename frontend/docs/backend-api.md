# Backend API Documentation

Reference these API specifications when implementing or changing frontend API integrations.

The following backend-wide documents are authoritative before the per-app endpoint
references:

- [Backend overview](../../backend/README.md)
- [Binding client security contract](../../backend/CLIENT_CONTRACT.md)
- [Backend threat model and residual risk](../../backend/SECURITY.md)

These files define transport only. Encrypted content formats and client synchronization
rules are defined by [cryptographic-protocol.md](cryptographic-protocol.md),
[message-protocol.md](message-protocol.md), and [sync-engine.md](sync-engine.md).
Handoff copies MUST NOT be duplicated here; these repository paths remain the single
source of truth.

- [Accounts API](../../backend/accounts/API.md)
- [Attachments API](../../backend/attachments/API.md)
- [Core API](../../backend/core/API.md)
- [Devices API](../../backend/devices/API.md)
- [Messaging API](../../backend/messaging/API.md)
- [Realtime API](../../backend/realtime/API.md)
- [Vault API](../../backend/vault/API.md)
- [Voice Rooms API](../../backend/voicerooms/API.md)

## Contract status

The former device-enrollment circularity is resolved. The binding flow is now
two-phase: register without `cross_sig`/`bundle_version`, receive the backend-assigned
`device_id` and full-scope tokens, then submit the valid signature and version through
`PUT /me/devices/{device_id}/prekeys`. A later device retrieves the recovery backup only
after registration gives it full scope. Until the follow-up succeeds, peers see
`cross_sig: null` and withhold messages.

The Devices API and its [golden vectors](../../backend/devices/vectors/README.md) now
freeze the four canonical signature encodings and the 64-byte `ik_pub` layout (Ed25519
followed by X25519). The Android version-1 implementation MUST reproduce those vectors
byte-for-byte; a future Web implementation must reproduce the same bytes before Web
release.

One client-side security gate remains: the backend requires a reviewed PQ MLS
ciphersuite for groups. The frontend-owned [PQ MLS profile](mls-profile.md) selects the
IETF hybrid ML-KEM-768/X25519 candidate, but its ciphersuite identifier is still
unassigned and maintained Android library support and interoperability evidence are not
yet available. Android group production release remains blocked by that profile's
Android gates; Web gates are post-v1. The client MUST NOT invent an identifier or
silently use a classical MLS suite.
the client MUST NOT invent an identifier or silently use a classical MLS suite.
