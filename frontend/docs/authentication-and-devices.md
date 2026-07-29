# Authentication and devices

## Trust configuration

The application ships with one provisioned server origin, private-CA trust anchor, and
native primary/backup SPKI pins. Users cannot bypass trust failures or enter arbitrary
servers. Development configuration is separate, visibly branded, and cannot be built as
a production artifact accidentally.

## Bootstrap routing

1. Load trust configuration and protected storage.
2. If configuration is absent or invalid, show the blocking not-provisioned state.
3. Check `/api/v1/health` on the configured server only.
4. If unreachable with no usable identity, remain on the connection screen with Retry.
   With a usable Android identity, open cached content in offline mode. The Web client is
   online-session-first and remains at the connection gate.
5. If a valid device session exists, refresh if required and enter the app.
6. Otherwise show Login; a remembered username is non-secret and may be prefilled.

## Registration

- Normalize username to lowercase for presentation consistent with the backend.
- Enforce the documented character/length rules locally for feedback; the server remains
  authoritative.
- Never probe username existence separately.
- After `POST /api/v1/auth/register`, show Pending Activation.
- "Check again" returns to Login with the username prefilled and requires the password
  again; there is no activation polling endpoint and the pending screen does not retain
  credentials.
- Password UI states clearly that the password authenticates the account and cannot
  recover cryptographic identity or message history.

## Login and first device

Login without a known live device ID returns register scope. Before registration, the
client generates the device Ed25519/X25519 identity, classical and ML-KEM-768 prekeys,
and—only after the [PQ MLS production gates](mls-profile.md#production-gates) pass—MLS
KeyPackages. It calls `POST /api/v1/me/devices` without `cross_sig` or `bundle_version`;
the `201` response supplies the assigned `device_id` and full-scope tokens.

For the first device, the client publishes the account identity, signs the canonical
bundle containing the assigned ID, sends `cross_sig` plus `bundle_version: 1` through
the prekey endpoint, uploads the recovery-protected key backup, and appends the first
device-log record. A later device registers unsigned, retrieves and unwraps the backup
with its new full-scope token, then cross-signs itself and appends the device-log change.
Until the cross-signature follow-up succeeds, the device remains in a resumable
"finishing secure setup" state and sensitive messaging stays withheld. The client never
sends a placeholder signature.

A failure before server registration keeps uncommitted keys in a resumable pending
state. The client persists the registration intent and generated public-key fingerprint
before sending the request. If the registration outcome is ambiguous, it does not erase
that state or blindly create devices until the account cap is exhausted; recovery must
reconcile unsigned devices by the same key fingerprint after a full-scope session is
obtained, revoke an orphan explicitly, and append the corresponding device-log changes.

## Returning device

Login supplies the stored device ID. A full-scope response resumes the session. If the
server treats the device as unknown/revoked and returns register scope, the UI explains
that this installation must register as a new device; it does not reuse revoked private
state.

## Token handling

- Android stores refresh material encrypted under a Keystore-wrapped storage key.
- Web stores encrypted token material under the origin's non-extractable wrapping key;
  page code can still use it while trusted code is running.
- Access tokens live in memory where possible.
- Dio authentication, proactive refresh, retry, logout, and WebSocket reconnect share one
  token coordinator.
- Tokens and decoded claims never enter logs or crash reports.
- Logout posts the current refresh token when possible, then wipes locally even if the
  network request fails.

## Linked devices

The Linked Devices screen uses `GET /api/v1/me/devices` with ETag caching. Labels are decrypted
locally. Removing a device requires confirmation and calls DELETE. Removing this device
transitions directly to revoked cleanup.

Peer device lists also use ETags covering both the live set and device-log head. Before
use, every device bundle is verified against the peer's out-of-band-confirmed master key,
fetched from `/api/v1/users/{user_id}/identity`, and the paged
`/api/v1/users/{user_id}/devicelog` must extend the last verified head. A legitimately
cross-signed addition does not invalidate master-key verification. Invalid/unsigned
devices are withheld; master-key change or log fork blocks sensitive operations.
Unknown/foreign/revoked IDs are treated identically in UI to avoid exposing server
existence distinctions.

## Prekey and key-package policy

Concrete low/target watermarks are configuration constants below the classical cap of
200, ML-KEM cap of 100, and consumable KeyPackage cap of 100. The crypto core generates
material; a maintenance use case uploads it only for the current device. Signed
classical/PQ prekeys rotate on schedule and after suspicion of compromise, atomically
with a fresh device `cross_sig` and incremented `bundle_version`. Each device maintains
one last-resort PQ MLS KeyPackage outside the consumable count after the
[PQ MLS production gates](mls-profile.md#production-gates) pass; reuse is recorded as a
forward-secrecy degradation, not treated as equivalent inventory. Failed signature or
cross-signature verification blocks session setup. No production KeyPackage is generated
or uploaded while those gates remain open.

A routine prekey rotation does not reset the contact's confirmed master key only when
the user/device ID, `ik_pub`, and registration ID are unchanged, the new classical/PQ
prekey signatures and device `cross_sig` all verify, `bundle_version` increments by
exactly one, and the device log extends to the new canonical live-set hash. A peer that
observes the prekey PUT before its separately appended log record treats the state as a
temporary security block and retries; it does not persist a fork alarm. Any other
cross-signature change remains a blocking safety-number change requiring explicit
out-of-band resolution.

## Recovery

Recovery requires the server key-backup blob and user-held recovery secret. The client
performs Argon2id and authenticated decryption locally. A wrong secret produces a generic
local failure. The blob restores cross-signing private keys and identity material only;
there is no history key or server history. There is no server check/reset and the UI
never suggests one.

Message history arrives only from an existing online, cross-signing-authorized device
over ordinary per-device envelopes. Without one, the new device starts with no history.
Pairwise sessions start fresh; missing MLS state requires peers to remove and re-add the
device with a fresh Welcome. The UI separates `identity recovered`, `waiting for existing
device`, `history transferring`, `group rejoin required`, and `ready`.

## Error mapping

Transport and backend error codes map to typed application failures. Required UX cases
include invalid credentials, inactive account, username taken, rate limited, scope
forbidden, device cap, revoked token/device, stale version, unreachable server, trust
failure, `identity_required`, unsigned/invalid device, master-key change, device-log
fork, missing PQ material, mailbox gap, malformed server response, and unsupported
protocol.

Backend error detail is safe for diagnostics only after redaction; UI uses reviewed
localized messages rather than displaying arbitrary server strings.

## API references

- [Accounts API](../../backend/accounts/API.md)
- [Devices API](../../backend/devices/API.md)
- [Vault API](../../backend/vault/API.md)
