# SECURITY.md — What this server protects, and what it does not

This document states the security properties of the backend exactly as the code keeps
them — no more. Where a property is best-effort, it says best-effort. Honesty is a
feature of this system, not a disclaimer.

## What is protected

Message, group, profile, attachment, and voice **content** is end-to-end encrypted by
the client. The server is a blind relay and blind warehouse: it authenticates accounts,
stores opaque padded ciphertext in exact size buckets, routes ciphertext to devices, and
relays volatile encrypted signals. It cannot read any content, and it is engineered so
that it also cannot learn the social graph — nothing at rest links a sender to a
recipient, group membership is not a server concept, and a voice room persists as
nothing but an ID plus an encrypted name.

## The precise key invariant

The literal "no private or symmetric keys anywhere on the server" is corrected here
to the precise, testable form — a TLS-terminating, authenticating server necessarily
holds *infrastructure* secrets:

> **No content-encryption key is ever transmitted to, stored by, or derivable by the
> server.** The server holds only infrastructure secrets and public key material. A
> disk/DB dump contains message data solely as ciphertext; a memory dump may additionally
> contain live infrastructure secrets and in-flight TLS-decrypted request bytes (auth
> tokens, the ciphertext blobs themselves) — which does not compromise message content.

| Key / secret | Class | Where it lives | Server sees it? | Compromise impact |
|---|---|---|---|---|
| Device identity key (ik), signed prekeys, one-time prekeys (private halves) | content | client secure storage only | never (only public halves uploaded) | that device's future DMs until healed (PCS) |
| Double-Ratchet / session keys | content | client memory/storage | never | past msgs safe (FS); heals (PCS) |
| MLS group & epoch secrets, exporter secrets | content | client | never | that epoch's group msgs; heals on Update/rekey |
| Voice SFrame / per-sender media keys | content | client (derived from live MLS subgroup) | never (not in token, not to SFU) | that live session's audio only |
| History/archive key | content | client; wrapped inside the recovery-protected key backup | never (only the opaque backup blob is stored) | archived history readable only with recovery secret **and** backup blob |
| Attachment content keys | content | inside E2E messages | never | that attachment only |
| Recovery secret | content | user-held only | never | can unwrap the key backup → history |
| TLS private key | infrastructure | server (nginx) | yes (by definition) | impersonate transport (mitigated by client SPKI pinning); no message content |
| JWT signing key | infrastructure | server env | yes | mint tokens → account access; cannot decrypt any message |
| Django `SECRET_KEY`, Argon2 params | infrastructure | server env | yes | session/signing integrity; no message content |
| Password hashes (Argon2id) | auth (not a key) | DB | yes (hash only) | offline guessing per account; no message content |

`core/tests/test_seizure_guard.py` enforces the at-rest half of this table against every
model in the app registry, permanently.

## No social graph at rest

There is no sender column on any stored envelope, no group or membership table, no
recipient list, and no shared-blob linkage between co-recipients (each recipient device
gets an independent row copy). Sealed sender is structural: sender identity exists only
inside ciphertext.

A full seizure of this server (disk + database) reveals, in total:

- the **user list** — usernames, Argon2id password hashes, activation flags,
  day-granularity account creation (irreducible for an authenticating server);
- per-user **device counts and public keys**, with day-granularity activity dates;
- that **delivery happened, to which device, at hour granularity** — pending queue rows
  tie an opaque blob to a recipient device (never to a sender or a conversation), and
  acked rows are deleted outright;
- per-user **encrypted history log sizes and days** (bucketed blob sizes, day-coarse
  dates). Two correspondents' logs share no stored key; only statistical size/day
  correlation remains, blunted by bucketing and coarse timestamps;
- **token-issue ≈ login times** (refresh-token bookkeeping, pruned hourly on expiry);
- that **rooms exist**, each an ID plus an encrypted name — no membership, no
  participant history;
- per-user **attachment upload counts, bucketed sizes, and days** — no recipient data
  of any kind.

No plaintext, no content key, no sender↔recipient pair, no group roster — anywhere.

## What is explicitly NOT protected

- **The fact and timing of use.** Connecting to this server, and when, is observable to
  any network operator. Cover traffic / anti-traffic-analysis is deliberately out of
  scope. This system protects *content*, not the fact of talking.
- **Voice connection metadata.** Joining a voice room is visible to the self-hosted
  SFU/TURN and to the network — who connected to the media server and when — even though
  the audio itself is SFrame-encrypted end-to-end and no media key ever reaches the
  server or SFU.
- **Presence lag and socket metadata.** Presence is derived from socket connect/
  disconnect and relayed only to devices the client authorized; the server inherently
  sees which devices hold sockets (a device may hold more than one) and when.

## Best-effort features, worded honestly

Three deletion meanings are kept distinct in code, docs, and every client-facing
string:

1. **Remote-deletion request** (delete-for-everyone) — a best-effort message asking
   peers to drop content. It cannot force a device that already decrypted content to
   forget it.
2. **Server ciphertext deletion** — removing blobs from this server: on ack, by TTL
   (queue 30 days, attachments 30 days, optional history TTL), or via
   `POST /me/history/delete`. This frees storage and bounds what a later seizure holds;
   it is not a remote wipe.
3. **Cryptographic erasure** — content becomes undecryptable only once every surviving
   key copy is destroyed (e.g. room session keys after a room empties).

None of these is ever described as one of the others.

- **Ephemeral room text** is best-effort: never stored server-side, dropped by clients
  when the room empties; not a guarantee every device instantly forgets.
- **Recovery is all-or-nothing and unrecoverable by design.** Losing the recovery secret
  loses archived history; no server-side reset or "check secret" endpoint exists.
  Conversely, possession of **both** the recovery secret and the backup blob reveals the
  archived history. A password reset (an owner admin action) affects authentication only
  and never recovers history.

## Trust boundaries

- **A fully compromised client endpoint is outside the threat model.** If a device's OS
  or the app itself is hostile, no server property can help.
- **A malicious or seized server cannot read content.** It can observe the metadata
  residuals listed above, drop or delay traffic, and refuse service. It could also
  attempt to serve a modified web client; native clients pin the server's SPKI (with a
  backup pin) against transport substitution, and the robust defense against a
  server-forged *device* is client-side safety-number verification / cross-signing —
  the server exposes the authenticated device list + ETag so every addition is visible
  to the user's other devices, but visibility is not proof.
- **Transport** is TLS 1.3 only, 0-RTT disabled, HSTS on, terminated by nginx under a
  private CA whose root is pre-distributed to clients. No live foreign CA, no CDN, no
  telemetry, no foreign STUN/TURN/SFU, no push relays — the system has no runtime
  dependency on any non-local network.
- **Authentication vs encryption identity are never conflated.** The password authorizes
  the account (Argon2id-hashed, device-bound short-lived JWTs, rotated+blacklisted
  refresh); a device's cryptographic identity is created client-side and only its public
  keys are uploaded. Owner activation gates every account; revoking a device bumps its
  token generation (access dies ≤ 15 min, refresh immediately) and deletes its queue and
  key material.

## Verification

The properties above are enforced by the test suite, not by this document:
`core/tests/test_seizure_guard.py` (no plaintext/key/graph column can ever appear),
`core/tests/test_log_silence.py` + per-app log-silence suites (no identifier, blob, or
token reaches any log line), `core/tests/test_settings_posture.py` + `manage.py check
--deploy` (deploy posture, including a hard error on an empty WebSocket origin
allowlist), per-app at-rest and no-graph suites, and
`ops/audit/offline_rehearsal.sh` (the repo rebuilds and passes with no network).
