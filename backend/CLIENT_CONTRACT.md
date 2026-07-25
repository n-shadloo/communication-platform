# CLIENT_CONTRACT.md — What the Flutter client must implement

This backend is a blind relay: it stores and serves key material and ciphertext as
opaque bytes and **verifies none of it**. Every security property below therefore lives
in the client. This document is the binding list of those client-side halves, written
for the Flutter developer. The server-side halves are specified in `ARCHITECTURE.md` and
the per-app `API.md` files; the residual-risk statement (what none of this protects) is
`ARCHITECTURE.md` §A16.

A server-side sanity check (length, bucket, monotonic version) is never a security
control. If the client ever skips a verification because "the server already checks
that," the design has failed — the server is the adversary.

## A. Key generation and storage

- On first install: generate **master**, **self-signing**, and **user-signing** Ed25519
  keys. Private keys go to platform secure storage (Keychain/Keystore) and **never**
  leave the device except inside the recovery-protected key backup blob
  (`PUT /me/keybackup`).
- Per device: an Ed25519 device signing key, X25519 identity + prekeys, ML-KEM-768
  prekeys, and the MLS credential/leaf key.
- **Libraries:** use `mlkem_native` (FFI to the formally-verified pq-code-package
  mlkem-native, FIPS 203) for ML-KEM. Use `cryptography` or `pinenacl` for
  Ed25519/X25519. **Do not** use pure-Dart ML-KEM implementations such as `kyber-py` or
  `mlkem` — they are explicitly educational and **not side-channel safe**.

## B. What the client signs

- The **self-signing key** signs the canonical device-bundle encoding (below).
- The **master key** signs the self-signing and user-signing public keys.
- The **user-signing key** signs another user's master key after out-of-band
  verification.
- **Device-log records** are hash-chained and signed by the self-signing key.

### Canonical device-bundle encoding

Domain separator: the ASCII string `chat:v1:device-bundle`, followed by the
length-prefixed concatenation (4-byte big-endian length before each field) of, in this
exact order:

| # | Field | Encoding |
|---|-------|----------|
| 1 | `user_id` | 16 bytes, UUID raw |
| 2 | `device_id` | 16 bytes, UUID raw |
| 3 | `ik_pub` | raw bytes |
| 4 | `spk_id` | 4 bytes, big-endian |
| 5 | `spk_pub` | raw bytes |
| 6 | `pq_spk_id` | 4 bytes, big-endian; zero-length field if absent |
| 7 | `pq_spk_pub` | raw bytes; zero-length field if absent |
| 8 | `registration_id` | 4 bytes, big-endian |
| 9 | `bundle_version` | 4 bytes, big-endian |

The encoding is deliberately self-contained: every signed key appears as its **bytes**,
never as an identifier to be resolved later.

## C. What the client verifies

- Before encrypting to, or accepting a message from, any peer device: verify the device
  bundle signature chains self-signing → master, and that the master key equals the one
  confirmed out-of-band. Reject otherwise.
- **Verify the key bytes, never a server-supplied identifier.** CVE-2022-39250
  (matrix-js-sdk cross-signing identity injection, CVSS 8.6) happened because checking
  and signing were two separate steps, letting a malicious homeserver substitute the key
  in between.
- On device-list fetch: verify the log head signature and that it **extends** the
  last-seen head. A fork is proof of server equivocation.

## D. Verification UX

- **SAS:** display a short emoji/number string derived from both parties' master keys;
  both users confirm out-of-band.
- **QR:** encode the master key fingerprint; scanning cross-signs.
- This is the **only** defense against first-contact MITM. It must be prominent, not
  buried.
- **Safety-number-style change warning:** if a contact's master key or a device's
  cross-signature changes, **block sending** and require re-verification.

## E. Behavior on verification failure

| Condition | Required behavior |
|-----------|-------------------|
| Unsigned / invalidly-signed device | Refuse to encrypt to it; show "unverified device — messages withheld" |
| Master key change | Block the conversation pending re-verification. Never silently re-trust. |
| Log fork detected | Global alert state; halt sensitive operations pending an out-of-band check |

## F. Post-quantum

- Always use hybrid **X25519 + ML-KEM-768** (PQXDH-style) for DM session establishment.
  If a claimed bundle lacks PQ material, either refuse or clearly flag the session as
  classical-only. **Never silently downgrade.**
- Use an MLS PQ ciphersuite for groups. Pad KeyPackages to the current
  `KEYPACKAGE_BUCKETS` `[4096, 16384]`.

## G. History sync — changed; the server no longer stores history

- On new-device enrollment, transfer history **client-to-client**, encrypted and
  authorized by cross-signing, over the ordinary envelope endpoint. There is no server
  history API.
- A new device has **no history** until an existing device is online to send it.
- The key backup blob no longer contains a history key; it carries cross-signing private
  key material.

## H. Queue gap handling — new, load-bearing for MLS

- `GET /me/envelopes` returns `pruned_through`. If the client's last acked seq is
  **below** `pruned_through`, envelopes were lost to the 7-day cap.
- Lost envelopes may have included MLS commits. The device is then permanently desynced
  from affected groups and **cannot** self-recover — client-to-client transfer moves
  content, not ratchet/epoch state. It must signal peers to remove and re-add it to each
  group (generating a fresh Welcome).
- Surface this to the user as a recoverable state, not a silent failure.

## I. Cross-signature freshness

- Rotating the signed prekey (`spk`) changes a signed field in the device bundle. The
  client **must** supply a fresh `cross_sig` and an incremented `bundle_version` in the
  same `PUT /me/devices/{id}/prekeys` call, or peers will correctly reject the device.

## J. Device-list log maintenance

- Append a signed record on every device-set change (add, remove, revoke) and on
  identity rotation.
- Piggyback the latest known heads of contacts on ordinary E2EE messages; on receipt,
  compare against the local view and raise the fork alarm on mismatch.

## K. Padding

- Pad every ciphertext to the exact bucket lengths defined in `core/buckets.py` before
  upload. A non-bucket length is rejected with `400 bad_bucket`.

## L. Polling

- No foreign push (FCM/APNs) is available. Background polling only.

## M. Enrollment ordering (server-imposed)

- The **first** device registers without a published identity (a register-scope token
  reaches only `POST /me/devices`); the client must `PUT /me/identity` immediately after
  receiving its full-scope tokens.
- Every later registration requires the identity to already be published
  (`400 {"code":"identity_required"}` otherwise) and always requires `cross_sig` +
  `bundle_version`. These are completeness checks against mis-sequenced clients, not
  security controls — a modified server would skip them, and peers must verify
  regardless.
