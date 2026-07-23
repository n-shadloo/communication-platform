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
  recover encrypted history.

## Login and first device

Login without a known live device ID returns register scope. The client then:

1. Generates the device identity bundle, signed prekey, one-time prekeys, MLS credential,
   and key packages inside the crypto boundary.
2. Creates an encrypted device label.
3. Calls `POST /api/v1/me/devices` with the complete initial public bundle.
4. Atomically stores the returned device ID/full token pair and the local private state.
5. Creates the archive key/recovery secret for a new account, or offers recovery for an
   existing account with a backup.
6. Uploads/updates the encrypted backup and completes mandatory security notice.

A failure before server registration keeps uncommitted keys in a resumable pending state.
A failure after a 201 but before local commit is resolved by login/device discovery; the
client never blindly registers devices until the account cap is exhausted.

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

Peer device lists also use ETags. An addition or key change invalidates aggregate safety
verification. Unknown/foreign/revoked IDs are treated identically in UI to avoid exposing
server existence distinctions.

## Prekey and key-package policy

Concrete low/target watermarks are configuration constants below backend caps and are
covered by concurrency tests. The crypto core generates material; a maintenance use case
uploads it only for the current device. Signed prekeys rotate on schedule and after
suspicion of compromise. Failed signature verification blocks session setup.

## Recovery

Recovery requires both the server backup blob and the user-held recovery secret. The
client performs Argon2id and authenticated decryption locally. A wrong secret produces a
generic local failure. There is no server check/reset and the UI never suggests one.

Restored history does not resurrect revoked identities or old live sessions. The new
device receives current group membership through authenticated member devices and starts
new pairwise sessions. The restore result separates `history restored` from `secure
sessions ready`: archived group timelines may be readable while their composers remain
disabled. If no authenticated current member can provide the present MLS state, the UI
requires a new invitation and never labels recovery alone as complete group restoration.

## Error mapping

Transport and backend error codes map to typed application failures. Required UX cases
include invalid credentials, inactive account, username taken, rate limited, scope
forbidden, device cap, revoked token/device, stale version, unreachable server, trust
failure, malformed server response, and unsupported protocol.

Backend error detail is safe for diagnostics only after redaction; UI uses reviewed
localized messages rather than displaying arbitrary server strings.

## API references

- [Accounts API](../../backend/accounts/API.md)
- [Devices API](../../backend/devices/API.md)
- [Vault API](../../backend/vault/API.md)
