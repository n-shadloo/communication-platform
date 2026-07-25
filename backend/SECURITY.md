# SECURITY.md — What this server protects, and what it does not

This document states the security properties of the backend exactly as the code keeps
them — no more. Where a property is best-effort, it says best-effort. Honesty is a
feature of this system, not a disclaimer.

## Threat model

The adversary is a **state actor with full root access to the running VPS** — not just a
forensic disk image but a live system: all storage, all memory, all logs, all traffic in
and out, and the ability to run modified server code.

**In scope — protected even under that adversary:** message content (text, files,
voice), past and future; group membership and group contents as *content*; any per-user
action or state that could identify a user as the author of specific content.

**Out of scope:** hiding user IP addresses (connection-level visibility to the ISP is
accepted); hiding that the service exists or that a given IP connects to it; client
device compromise (a seized, unlocked phone bypasses everything).

**Operational constraint:** the system runs fully during a total national internet
shutdown, with only domestic network access — no public STUN/TURN, no FCM/APNs, no
external CDN, no external CA contact, no third-party API at runtime.

## What is protected

Message, group, profile, attachment, and voice **content** is end-to-end encrypted by
the client. The server is a blind relay and blind warehouse: it authenticates accounts,
stores opaque padded ciphertext in exact size buckets, routes ciphertext to devices, and
relays volatile encrypted signals. It cannot read any content. **At rest** it also
stores no conversation graph — no sender column, no membership table, no recipient
lists, no shared-blob linkage — which is a real property of a seized disk, but it is
**not** social-graph protection against the live adversary: see the residual-risk
section below.

The server enforces **nothing security-relevant**. Cross-signing keys, device-bundle
signatures, and device-list log records are stored and relayed as opaque blobs, never
parsed, never verified — all verification is client-side (`CLIENT_CONTRACT.md`), against
keys the server has never seen. Server-side sanity checks (lengths, buckets, monotonic
versions) are malformed-input and anti-accident guards; a modified server would simply
not apply them, so no client may ever rely on one.

Session establishment is hybrid **X25519 + ML-KEM-768** (PQXDH-style), so recorded
ciphertext stays confidential against harvest-now-decrypt-later unless the attacker
breaks *both* primitives. PQ signatures are deliberately not used: forgery must happen
live, before the primitive is broken, so classical Ed25519 remains sufficient there.

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
| Cross-signing master / self-signing / user-signing keys (private halves) | content | client secure storage; wrapped inside the recovery-protected key backup | never (public halves + signatures stored opaquely) | forge identity/device attestations for that user until re-verified out-of-band |
| Device identity key (ik), signed prekeys, one-time prekeys (private halves) | content | client secure storage only | never (only public halves uploaded) | that device's future DMs until healed (PCS) |
| ML-KEM-768 prekeys (decapsulation halves) | content | client secure storage only | never (only 1184-byte encapsulation keys uploaded) | strips the PQ layer of new sessions to that device; the classical layer still holds |
| Double-Ratchet / session keys | content | client memory/storage | never | past msgs safe (FS); heals (PCS) |
| MLS group & epoch secrets, exporter secrets | content | client | never | that epoch's group msgs; heals on Update/rekey |
| Voice SFrame / per-sender media keys | content | client (derived from live MLS subgroup) | never (not in token, not to SFU) | that live session's audio only |
| Attachment content keys | content | inside E2E messages | never | that attachment only |
| Recovery secret | content | user-held only | never | can unwrap the key backup → cross-signing private keys |
| TLS private key | infrastructure | server (nginx) | yes (by definition) | impersonate transport (mitigated by client SPKI pinning); no message content |
| JWT signing key | infrastructure | server env | yes | mint tokens → account access; cannot decrypt any message |
| Django `SECRET_KEY`, Argon2 params | infrastructure | server env | yes | session/signing integrity; no message content |
| Password hashes (Argon2id) | auth (not a key) | DB | yes (hash only) | offline guessing per account; no message content |

`core/tests/test_seizure_guard.py` enforces the at-rest half of this table against every
model in the app registry, permanently.

## What a seizure of the disk and database yields

There is no sender column on any stored envelope, no group or membership table, no
recipient list, and no shared-blob linkage between co-recipients (each recipient device
gets an independent row copy). Sealed sender is structural **at rest**: sender identity
exists only inside ciphertext. There is **no server-side message history of any kind**;
message ciphertext exists only in the delivery queue, deleted on ack and capped at
**7 days** for devices that never collect it.

A full seizure of this server (disk + database) reveals, in total:

- the **user list** — usernames, Argon2id password hashes, activation flags,
  day-granularity account creation (irreducible for an authenticating server);
- per-user **device counts and public key material** — identity/prekey/ML-KEM public
  keys, cross-signing public keys and their opaque signatures, day-granularity activity;
- per-user **device-list log records** — opaque client-signed blobs, day-coarse dates;
- that **delivery happened, to which device, at hour granularity** — pending queue rows
  (at most 7 days deep) tie an opaque blob to a recipient device, never to a sender or
  a conversation; acked rows are deleted outright;
- **token-issue ≈ login times** (refresh-token bookkeeping, pruned hourly on expiry);
- that **rooms exist**, each an ID plus an encrypted name — no membership, no
  participant history;
- per-user **attachment upload counts, bucketed sizes, and days** — no recipient data
  of any kind.

No plaintext, no content key, no sender↔recipient pair, no group roster — anywhere at
rest.

## Residual risk — what remains exposed to live root

The following are **not** protected, and no document or code comment in this repository
may claim otherwise. In particular, the social graph is **not** hidden, protected,
private, or unlinkable.

1. **The social graph is not hidden from live root.** An adversary running modified
   server code sees, in real time, which authenticated connection writes to and reads
   from which device queue, and can log who-talks-to-whom and when. This is fundamental
   to a single box the adversary controls.
2. **Group membership metadata leaks at the transport/routing layer** even though MLS
   hides it cryptographically: the adversary sees which connections receive the same
   group's commits and can infer membership from delivery fan-out.
3. **Fact and timing of communication** (who is online, when messages flow, message
   sizes up to the padding bucket) are visible. Padding hides exact length; nothing
   here hides timing at 20 users.
4. **The server can deny service, and can equivocate** within a single client's view if
   it also controls whether that client reaches peers; device-list gossip detects
   equivocation only once two honest clients compare heads — detection, not prevention.
5. **Account existence and coarse metadata** (that an account exists, roughly when
   active) remain visible to root.
6. **Live root reads TLS session keys** and any plaintext transiently in memory
   (routing metadata, not E2EE content). Memory hygiene does not stop this.
7. **First-contact MITM is prevented only if users actually perform SAS/QR
   verification**; unverified contacts remain exposed to a one-time key substitution.
8. **Client device compromise** (out of scope) bypasses everything above.

In short: content is well protected; the social graph and communication timing are not,
and cannot be, on a single box under live root.

Also visible, below the live-root bar: **voice connection metadata** (who connected to
the self-hosted SFU/TURN and when — audio itself is SFrame-encrypted end-to-end) and
**socket/presence metadata** (which devices hold sockets and when; presence is relayed
only to devices the client authorized).

## Best-effort features, worded honestly

Three deletion meanings are kept distinct in code, docs, and every client-facing
string:

1. **Remote-deletion request** (delete-for-everyone) — a best-effort message asking
   peers to drop content. It cannot force a device that already decrypted content to
   forget it.
2. **Server ciphertext deletion** — removing blobs from this server: on ack, or by TTL
   (queue 7 days, attachments 30 days, non-last-resort KeyPackages 30 days). This frees
   storage and bounds what a later seizure holds; it is not a remote wipe.
3. **Cryptographic erasure** — content becomes undecryptable only once every surviving
   key copy is destroyed (e.g. room session keys after a room empties).

None of these is ever described as one of the others.

- **Ephemeral room text** is best-effort: never stored server-side, dropped by clients
  when the room empties; not a guarantee every device instantly forgets.
- **Recovery is all-or-nothing and unrecoverable by design.** The key backup wraps the
  cross-signing private keys and identity material; losing the recovery secret loses
  them. Message history lives only on devices — a new device gets history only from an
  existing device that is online to transfer it, and there is no server copy to restore.
  No server-side reset or "check secret" endpoint exists. A password reset (an owner
  admin action) affects authentication only and never recovers keys or history.
- **The last-resort MLS KeyPackage trades forward secrecy for reachability.** When a
  device's consumable KeyPackage pool is exhausted, its single last-resort package is
  served repeatedly instead of nothing. Every group join that reuses it shares one KEM
  secret, so a later compromise of that key exposes each such join's Welcome. It is a
  fallback, not an equivalent.

## Trust boundaries

- **A fully compromised client endpoint is outside the threat model.** If a device's OS
  or the app itself is hostile, no server property can help.
- **A malicious or seized server cannot read content.** It can observe everything in the
  residual-risk list, drop or delay traffic, and refuse service. Against a
  server-*forged* device, the defense is client-side: cross-signing (peers refuse
  unsigned devices), SAS/QR verification of master keys (the only first-contact MITM
  defense), and the client-signed device-list log, whose in-band head gossip turns
  server equivocation into cryptographic evidence once two honest clients compare.
  The server stores and relays all of that material without verifying any of it —
  a check it applied would be one a modified server could skip, and trusting it would
  be the failure mode.
- **Transport** is TLS 1.3 only, 0-RTT disabled, HSTS on, terminated by nginx under a
  private CA whose root is pre-distributed to clients. No live foreign CA, no CDN, no
  telemetry, no foreign STUN/TURN/SFU, no push relays — the system has no runtime
  dependency on any non-local network.
- **Authentication vs encryption identity are never conflated.** The password authorizes
  the account (Argon2id-hashed, device-bound short-lived JWTs, rotated+blacklisted
  refresh); a device's cryptographic identity is created client-side and only its public
  keys are uploaded. Owner activation gates every account; revoking a device bumps its
  token generation (access dies ≤ 15 min, refresh immediately) and deletes its queue,
  classical and PQ prekeys, and KeyPackages in one transaction.

## Verification

The properties above are enforced by the test suite, not by this document:
`core/tests/test_seizure_guard.py` (no plaintext/key/graph column can ever appear),
`core/tests/test_log_silence.py` + per-app log-silence suites (no identifier, blob, or
token reaches any log line), `core/tests/test_settings_posture.py` + `manage.py check
--deploy` (deploy posture, including a hard error on an empty WebSocket origin
allowlist), per-app at-rest, no-graph, and no-history suites, the adversarial
cross-signing/PQ/device-log suites in `devices/tests/`, and
`ops/audit/offline_rehearsal.sh` (the repo rebuilds and passes with no network).
