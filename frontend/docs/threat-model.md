# Client threat model

## Security objective

Protect content confidentiality and integrity when the backend, database, attachment
store, SFU, TURN relay, or network is observed or later seized. The system does not hide
that a device contacted the service or eliminate traffic-analysis metadata.

## Protected assets

- Message, profile, group, room, attachment, locally held history, and voice plaintext.
- Cross-signing, device identity, ML-KEM, ratchet, MLS, attachment, and media private
  keys.
- Login and refresh credentials.
- Recovery secrets.
- Local decrypted indexes, thumbnails, drafts, and notification previews.
- The fact that background delivery is armed. Two different exposures, and they are not
  equal. The shipped floor (ADR-049) leaves nothing on the device to see — one record in
  the platform's own job store holding an id, an interval and a component name — but it
  does make this device's *online periods* visible to the server on a roughly
  fifteen-minute cadence whether or not its owner is present, so an idle device now looks
  like an active one to a relay that already saw every drain. The unbuilt opt-in
  `specialUse` foreground service (ADR-046 Layer 2) is the heavier one: it posts a
  persistent, visible notification, which is a durable on-device indication that this
  application is running, and that is why that layer is opt-in rather than default; its
  channel must be low importance, silent, and neutrally worded.
- Who is talking to whom, as it would appear in a message alert. The shipped alert
  (ADR-048) is a single sender-neutral notification whose entire content is "New message"
  or "New messages": no sender, no conversation, no text, no count, no timestamp, one
  constant id and tag, and a tap intent carrying no identifier. That is what a bystander
  sees on a locked or unlocked screen, what an Android 15+ screen-sharing session shows,
  and what an application holding notification access can read. Conversation notifications,
  `MessagingStyle` and long-lived conversation shortcuts are excluded by decision, because
  each publishes a stable per-contact identifier outside the encrypted database.

## Adversaries considered

- A passive network observer.
- An active network attacker without the provisioned trust anchors.
- A malicious or seized backend that returns forged keys, drops, reorders, duplicates,
  delays, or replays traffic.
- A state actor with live root access to the VPS, including TLS-terminated request
  metadata, authenticated routing, timing, IP addresses, and the ability to modify server
  responses.
- Theft of backend disks, database dumps, Redis state, attachment storage, or logs.
- A recipient who retains content after a deletion request.
- A person with filesystem access to a locked but otherwise uncompromised Android device.
- Malformed ciphertext and protocol input intended to crash or exhaust a client.
- Dependency or web-content injection attempts.

## Explicitly outside the guarantee

- A device compromised while it can decrypt content.
- A user voluntarily sharing plaintext, screenshots, or a recovery secret.
- Traffic-analysis resistance, anonymity, or cover traffic.
- Availability against a server or network that refuses service.
- Guaranteed remote deletion after another device decrypted content.
- Reliable delivery to a force-stopped Android process or closed browser without a push
  service. Background delivery remains best-effort at every tier (ADR-046), and no tier
  is a guarantee.
- Hiding the social graph, group fan-out, or communication timing from live server root.

## Trust boundaries

### Backend

The backend is trusted to authenticate accounts and attempt delivery, but not trusted
with content. Clients validate signatures, identity changes, protocol versions, group
authorization, replay identifiers, and authenticated encryption independently.

### Android

The signed application binary and Android Keystore are trusted within documented OS
limits. A random database-wrapping key is non-exportable where supported. Hardware
backing is preferred but not assumed on every device.

### Web

The browser origin, browser implementation, and served application code are trusted for
the duration of a session. Non-extractable WebCrypto keys reduce accidental extraction;
they do not defend against malicious JavaScript executing in the same origin. A server
that can replace the web bundle can compromise future sessions. The UI MUST disclose
that the installed Android client has a stronger distribution trust boundary.

### Dependencies

Dependencies are pinned, checksummed, cached for offline builds, license-reviewed, and
scanned. Crypto debug features and sensitive logging features are forbidden in release
builds.

Version 1 implements only the shared Rust primitive foundation and Android FFI/isolate
adapter. The Web/Wasm boundary is deferred to post-v1 and crypto-dependent Web behavior
remains fail-closed; Android completion is sufficient for the Android release but is not
evidence for a future Web trust boundary or its browser vectors.

## Required controls

- TLS 1.3, provisioned private CA, native SPKI pins with a backup pin, and strict
  Android origin/network controls. Strict Web origin controls are post-v1.
- Authenticated end-to-end encryption with domain-separated associated data.
- Safety-number verification and prominent identity-change state.
- Cross-signing of the exact canonical device-bundle key bytes against an out-of-band
  confirmed account master key; unsigned devices are never messaged.
- Client-signed device-log verification and encrypted head gossip; a fork raises a global
  blocking equivocation alert.
- Hybrid X25519 + ML-KEM-768 session establishment with no silent classical downgrade.
- Exact replay and duplicate handling with bounded caches.
- Explicit `pruned_through` mailbox-gap detection and fresh-Welcome group recovery.
- Limits on message size, nesting, skipped ratchet keys, pending epochs, attachments,
  retries, and decompression.
- Encrypted local Android database; a future Web client must not persist plaintext.
- Redacted local diagnostics and hidden notification previews by default.
- Clipboard warnings/expiry where supported for recovery secrets.
- Screenshots blocked on Android screens that expose recovery secrets or raw keys.
- Local wipe on logout, self-revocation, remote revocation, and unrecoverable key errors.
- Reproducible release artifacts and independent security review.

## Residual metadata

The server can observe usernames, public device bundles, day-level activity, recipient
device IDs for pending envelopes, timing, IP addresses, size buckets, room IDs presented
to room endpoints, attachment capabilities during download, and voice connection
metadata. Live root can observe which authenticated connection writes to which device
queues and infer the social graph and group fan-out. At rest there is no sender column or
conversation graph, but that does not protect routing metadata from a live operator. The
client MUST not claim otherwise.

## Security release gates

These are gates on a **release**. ADR-044 defines the initial Private Experimental
deployment, which is not one: it is private, named, disclosed distribution of an
artifact that states its own maturity, and it leaves every gate below closed and
unsatisfied. Nothing in that decision may be read as clearing one of them, and the
written disclosure it requires is what makes distributing under them acceptable.

- No handwritten cryptographic primitive.
- No shipping an unreviewed cross-platform protocol implementation.
- All official and project test vectors pass on Android for the version-1 release.
- Fuzzing covers binary decoders and state-machine transitions.
- Dependency audit and SBOM are clean or formally accepted.
- An independent reviewer signs off the protocol, implementation boundary, Android key
  storage, and release configuration. Web limitations and browser configuration are
  reviewed only when the post-v1 Web release is reopened.

## Primary references

- [Backend security contract](../../backend/SECURITY.md)
- [Binding client contract](../../backend/CLIENT_CONTRACT.md)
- [OWASP MASVS](https://mas.owasp.org/MASVS/)
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [Web Cryptography API](https://www.w3.org/TR/WebCryptoAPI/)
