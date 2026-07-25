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

## Known contract blockers

The current device-registration request cannot satisfy its own canonical-signature
requirement because the server-generated `device_id` is returned only after the request,
although `cross_sig` must cover that ID before the request. Later-device recovery is also
circular because register-scope tokens cannot read the key backup needed to recover the
self-signing key. The exact canonical input for `master_sig` and the representation of
the contract's separate Ed25519 device-signing and X25519 identity keys in the single
`ik_pub` field are not defined. These issues are release blockers; see
[Cryptographic protocol: Enrollment contract blocker](cryptographic-protocol.md#enrollment-contract-blocker)
and the [implementation checklist](implementation-checklist.md#required-spikes-before-broad-implementation).
