# Client work

What the client developer owes, and nothing else. The server cannot change a file
under `frontend/`, so an obligation that lands there is recorded here instead.

This file routes; it never repeats. The contract the client implements is
[`backend/CLIENT_CONTRACT.md`](backend/CLIENT_CONTRACT.md), the observable changes
are in [`API_CHANGES.md`](API_CHANGES.md), and the endpoint reference is the per-app
`API.md` files with [`backend/openapi.json`](backend/openapi.json) beside them.

Each run of the server appends its section. Nothing is removed from this file except
by the developer who did the work.

## Remove the web target

The product is one Flutter application for Android
([ADR-0020](docs/architecture/decisions/0020-one-android-client-and-no-browser-surface.md)).
The server no longer carries a browser-only surface, so a web build of the client
cannot connect: the `/ws` gateway refuses a handshake that presents no
`Authorization: Bearer` header, and a browser cannot set one.

### The `/ws` handshake — this is the breaking one

The client already authenticates the native socket with the header, so the Android
build is unaffected. What must go is the second path beside it and the two close
codes it produced.

| Path | What is there |
|---|---|
| `frontend/lib/features/networking/infrastructure/realtime/socket_connector.dart` | `enum SocketAuthenticationMode { nativeBearerHeader, webFirstFrame }` and the `authenticationMode` getter on the connector interface. With one mode left, the enum and the getter have nothing to select |
| `frontend/lib/features/networking/infrastructure/realtime/dio_websocket_gateway.dart` | The `SocketAuthenticationMode.webFirstFrame` branch that sends the in-band `{"type": "auth", "access": …}` frame, and the close-code mapping for `4001` and `4403`, including the `code == 4001` recovery branch. Both codes are retired: authentication is now decided before the accept, so a refusal reaches the client as a failed upgrade (`403 Forbidden`) and never as a close frame |
| `frontend/lib/app/dependencies/networking_foundation.dart` | The comment describing the coordinator's `4001` refresh path |

The remaining behaviour a client needs is
[`backend/CLIENT_CONTRACT.md`](backend/CLIENT_CONTRACT.md) §O.

### The response headers the client may assert on

`X-Content-Type-Options`, `Referrer-Policy` and — on the attachment download —
`Content-Disposition` are no longer set. Any client test that asserts on one will
fail. `Cache-Control: no-store`, `Cache-Control: private, no-store` and
`X-Accel-Redirect` are unchanged. `API_CHANGES.md` § "The web target is gone" is the
full list.

### The web platform files

| Path | What is there |
|---|---|
| `frontend/web/` | The web application shell: `index.html`, `manifest.json`, `favicon.png`, `icons/`, and the two runtime assets the storage layer loads — `sqlite3.wasm` and `drift_worker.js` — plus `protected_storage.js` |
| `frontend/docs/platform-web.md` | The web platform note |

### The conditional-import stubs

Each of these five is an `export … if (dart.library.js_interop) …` trio: the
selector, the native implementation, the stub and the web implementation. With no web
target the selector and the stub have one implementation to choose between.

| Selector | Web implementation to remove |
|---|---|
| `frontend/lib/app/config/runtime_abi.dart` (with `runtime_abi_stub.dart`) | `frontend/lib/app/config/runtime_abi_web.dart` |
| `frontend/lib/features/local_storage/infrastructure/platform/platform_local_storage.dart` (with `platform_local_storage_stub.dart`) | `frontend/lib/features/local_storage/infrastructure/platform/platform_local_storage_web.dart` |
| `frontend/lib/features/networking/infrastructure/realtime/platform_socket_connector.dart` (with `platform_socket_connector_stub.dart`) | `frontend/lib/features/networking/infrastructure/realtime/platform_socket_connector_web.dart` |
| `frontend/lib/features/networking/infrastructure/tls/transport_security.dart` (with `transport_security_stub.dart`) | `frontend/lib/features/networking/infrastructure/tls/transport_security_web.dart` |
| `frontend/lib/shared/infrastructure/crypto/platform_crypto_core.dart` (with `platform_crypto_core_stub.dart`) | `frontend/lib/shared/infrastructure/crypto/platform_crypto_core_web.dart` |

### The build

| Path | What is there |
|---|---|
| `frontend/tool/ci.sh` | `flutter build web --release --target lib/main_production.dart` |
| `frontend/tool/ci.ps1` | The same build, as an `Invoke-CheckedCommand 'flutter' @('build', 'web', '--release', '--target', 'lib/main_production.dart')` |

### The wording

| Path | What is there |
|---|---|
| `frontend/README.md` | "Flutter client for Android, with a preserved post-v1 Web foundation", "Android and Web targets only" under **Toolchain**, the `flutter build web` line, the Web CA-install paragraph, and the Web step in the local-CI description |
| `frontend/pubspec.yaml` | `description: "Android and Web client foundation for Communication Platform."` |

`frontend/docs/implementation-checklist.md` carries the same "preserved post-v1 Web
scaffold" status in several rows. It is the client's live status document, so its
wording is the client developer's call — but it should stop describing a target the
server no longer serves.

## Voice

The server surface for voice is gone and the replacement lands in phase 7
([ADR-0021](docs/architecture/decisions/0021-relayed-webrtc-mesh-and-no-server-room.md)).
Nothing under `frontend/` implements voice today, so none of this is a removal: it is
what the client will need, recorded now because the decision that binds it has been
made and the evidence behind it was gathered on 2026-09-05.

**The client contract for voice is not written yet.** The wire shape of the offer, the
answer and the candidates, and the route that mints a coturn credential, land in phase
7 and will be `backend/CLIENT_CONTRACT.md` §N and the per-app `API.md` beside it. Build
nothing against a shape guessed from this file.

### The media package

`flutter_webrtc` 1.6.1 — pub.dev, published 2026-09-01 by the verified publisher
flutter-webrtc.org, MIT, Dart SDK 3.3 or later. It is the only maintained WebRTC
package for Flutter, and it is what the design assumes.

| What it brings | Detail |
|---|---|
| Android build | `compileSdkVersion 36`, `minSdkVersion 21` |
| Native dependencies | `io.github.webrtc-sdk:android:150.7871.01`; `com.github.davidliu:audioswitch` at commit `039a35aefab7747c557242fa216c9ea11743b604`, **from JitPack**; `androidx.annotation:annotation:1.1.0` |
| What it does **not** bring | No `androidx.core` dependency of its own, so the frozen `androidx.core` 1.16.0 and `connectivity_plus` 6.0.5 pins of `frontend/docs/decisions.md` ADR-054 both hold |
| The relay policy | Its Android plugin parses `iceTransportPolicy`, and `relay` is the value the design needs: every path crosses coturn, and no peer learns another peer's address |

**The offline Gradle mirror has to carry the JitPack artefact.** `audioswitch` is
resolved from JitPack by commit hash, not from Maven Central, so a mirror built only
from Central resolves everything else and fails on that one — during a shutdown, on a
build that has to work offline. Add the JitPack coordinate to the mirror while the
network is up, and prove it by building with the network off.

`livekit_client` is not the package to take. 2.11.0 requires `connectivity_plus
^7.0.0`, and 7.1.0 and later force `androidx.core` 1.18.0 and `compileSdk` 36.1 —
which is the bump ADR-054 froze against. It also pins `flutter_webrtc` 1.6.0 exactly
and adds twelve Dart packages, and its frame cipher is not RFC 9605 SFrame: it derives
a 128-bit AES-GCM key with PBKDF2-HMAC-SHA256 and leaves one byte of each audio frame
unencrypted. The mesh design needs none of it, because SRTP is keyed by DTLS between
the two endpoints of each connection.

### The manifest permissions

The manifest merger decides what the shipped application declares, so the set below is
what to keep and what to remove deliberately rather than by omission.

| Source manifest | What it declares | Keep or remove |
|---|---|---|
| `flutter_webrtc` 1.6.1 | Nothing | — |
| The libwebrtc AAR | Nothing | — |
| `audioswitch` | `BLUETOOTH` with `maxSdkVersion` 30 | Remove with `tools:node="remove"` unless a Bluetooth headset route is a feature you are shipping |
| `audioswitch` | `MODIFY_AUDIO_SETTINGS` | Keep. Audio routing during a call needs it |

`RECORD_AUDIO` is the client's own to declare, and it is the one a user is prompted
for. Nothing in the dependency set declares it for you.

### What the design assumes of the client

- Audio only. One `RTCPeerConnection` for each peer, so a room of ten participants is
  nine connections on each device.
- `iceTransportPolicy: relay`, with the coturn credential phase 7 issues as the only
  ICE server. No STUN, and no other TURN.
- The SDP offer, the SDP answer and the ICE candidates travel inside pairwise-session
  ciphertext over the `/ws` `signal` frames the client already has. The server relays
  that ciphertext and cannot read or replace a DTLS fingerprint.
- A room is client state: client-signed control events over ordinary envelopes,
  exactly as a group is. Ephemeral room text and join and leave announcements are
  `signal` frames the client fans out to each member device.
- No media key to distribute, rotate or store. A connection's keys die with it.
