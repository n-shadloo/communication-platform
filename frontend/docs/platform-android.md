# Android platform contract

## Baseline

Use the Flutter stable version pinned during scaffolding and target the current Android
SDK required for distribution. The minimum SDK is chosen after crypto, Keystore, and
LiveKit device testing; lowering it may not weaken required security controls silently.

## Key and data protection

- Generate a non-exportable Android Keystore AES-256 key to wrap the random local database
  key. Prefer StrongBox/TEE when available and record only coarse capability state.
- Do not require hardware attestation or Google services; operation during disconnection
  takes precedence and the documented threat model does not trust a remote Google check.
- Store identity/ratchet/MLS material only through the encrypted database/crypto-core
  boundary.
- Disable Android Auto Backup/data extraction for databases, keys, tokens, caches, and
  attachments.
- Use internal app storage and scoped `content://` sharing only.
- Apply `FLAG_SECURE` to recovery-secret/key-verification surfaces and privacy-sensitive
  app-switcher content.
- Clear clipboard recovery data after a short interval when platform behavior permits.

## Network trust

Production accepts only the provisioned origin and private CA. Native network security
configuration and the HTTP/WebSocket clients enforce primary and backup SPKI pins. Pin
failure is blocking and never offers "continue anyway". Development trust is compiled
only into visibly non-production flavors.

## Background delivery

There is no FCM/APNs fallback. Correctness therefore relies on the backend durable queue,
not instant background notification.

Modes:

- **Normal:** socket while app is active; on resume reconnect and drain. WorkManager may
  perform best-effort maintenance/catch-up under network constraints.
- **Stay connected:** explicitly enabled by the user and represented by a persistent
  notification. A native foreground service owns the socket and hands encrypted
  envelopes to the same transactional inbox pipeline.
- **Active voice:** microphone/communication foreground service for the duration of the
  joined room with visible controls.

The implementation spike MUST select truthful Android foreground-service types and comply
with the targeted OS rules. Android 14+ requires declared types/permissions;
`remoteMessaging` is evaluated for message transfer, and `microphone` is used only while
capturing. The app MUST NOT mislabel perpetual work as `dataSync` to evade Android 15
timeouts or distribution policy. If the OS/user stops the service, the UI reports that
instant background delivery is unavailable and later drains safely.

## Notifications

- Local notifications are created only after authenticated decryption and durable local
  commit.
- Default preview is hidden: app name, sender-neutral "New message", and open action.
- User may opt into decrypted previews with a clear lock-screen warning.
- Conversation IDs/people shortcuts never expose backend capabilities or raw identifiers.
- Tapping routes through unlock/session validation before opening content.
- Notification actions are bounded signed local intents, validated again by application
  use cases.

## Permissions

Request only at point of use:

- notifications for message alerts/foreground connection disclosure;
- microphone for joining voice;
- camera for capture/optional safety QR;
- media/files through system pickers without broad storage permission.

Denial has a functional fallback and never blocks unrelated messaging.

## Lifecycle and reliability

- Process death at any inbox/outbox stage is recoverable from Drift.
- App upgrade closes old crypto workers before migration and validates stored protocol
  state after migration.
- Network switching, captive/no-internet local networks, Doze, standby, force-stop,
  reboot, permission revocation, clock skew, and low storage have explicit tests.
- The client never contacts a public internet endpoint to classify connectivity.

## Distribution

Initial distribution is a reproducibly signed direct APK plus self-hosted update
metadata, all usable on the local network. Update signatures are verified independently
of TLS. A store channel may be added later but cannot become a runtime dependency.

## Primary references

- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [Android background work](https://developer.android.com/develop/background-work)
- [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Foreground-service timeouts](https://developer.android.com/develop/background-work/services/fgs/timeout)
