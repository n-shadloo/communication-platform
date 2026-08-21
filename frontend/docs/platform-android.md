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
- Store cross-signing private keys in platform-protected storage and in the
  recovery-encrypted backup only; device X25519/ML-KEM/ratchet/MLS private state never
  enters that backup.
- Disable Android Auto Backup/data extraction for databases, keys, tokens, caches, and
  attachments.
- Use internal app storage and scoped `content://` sharing only.
- Apply `FLAG_SECURE` to recovery-secret/key-verification surfaces and privacy-sensitive
  app-switcher content.
- Clear clipboard recovery data after a short interval when platform behavior permits.

### Piece-05 storage baseline

The pinned `sqlite3` 3.5.0 build hook selects its SQLCipher community build. Drift opens
the database only after a 32-byte random database key has been authenticated and
unwrapped by an Android Keystore AES-256-GCM key. The Keystore adapter prefers StrongBox
on API 28+ and retries with the ordinary Android Keystore provider when StrongBox is not
available. Wrapped key material lives in `noBackupFilesDir`; application backup is
disabled. Logout, self-revocation, remote revocation, wrapping-key loss, and wrapping
envelope authentication failure close database handles, destroy the Keystore alias,
and then remove database/cache artifacts.

This baseline was verified on 2026-07-27 against the Android Keystore documentation and
the `sqlite3` 3.5.0 build-hook documentation. Hardware-backed behavior still requires
the physical-device matrix; no hardware guarantee is inferred from compilation alone.

### Piece-07 crypto-core delivery scope

Piece 07 is intentionally limited to the shared Rust primitive core and its versioned
Android native FFI boundary, invoked away from the Flutter UI isolate. The Android
adapter MUST expose failures only as stable payload-free status codes and secret state
only as opaque handles, contain Rust panics at every exported boundary, reject
out-of-bound or malformed inputs before state mutation or unbounded allocation, and
destroy Rust-owned secret state through an explicit lifecycle. Dart may orchestrate calls
and carry opaque bytes or handles but does not implement primitives, export private-key
material, select weaker parameters, or receive native error strings.

The verified foundation is locked to Rust 1.97.1, Cargo's committed lockfile, Android
NDK 28.2.13676358, API 24, and `arm64-v8a`, `armeabi-v7a`, and `x86_64`. The native
library statically links the signed libsodium 1.0.22 source archive, compiles
`mlkem-native` v1.2.0 at commit
`0ba906cb14b1c241476134d7403a811b382ca498`, and pins the RustCrypto,
`minicbor`, and binding crates in `native/crypto_core/Cargo.toml`. The build rejects an
unexpected toolchain, archive hash/signature, dynamic libsodium dependency, ELF load
alignment, or exported symbol.

ABI version 1's exact export allowlist for the `foundation` crypto profile — the profile
packaged into the development and production flavors — is `cp_crypto_v1_abi_version`,
`cp_crypto_v1_application_operation`, `cp_crypto_v1_attachment_operation`,
`cp_crypto_v1_attest_peer_master`, `cp_crypto_v1_capabilities`,
`cp_crypto_v1_create_device_log_record`, `cp_crypto_v1_cross_sign_device`,
`cp_crypto_v1_identity_operation`, `cp_crypto_v1_inspect_device_log_record`,
`cp_crypto_v1_pairwise_operation`, `cp_crypto_v1_prepare_device`,
`cp_crypto_v1_prepare_first_identity`, `cp_crypto_v1_restore_identity`,
`cp_crypto_v1_sanitize_identity`, and `cp_crypto_v1_self_test`.

The isolated `beta` crypto profile is the same list plus exactly one additional symbol,
`cp_crypto_v1_beta_mls_operation`, produced only by the non-default `beta-pq-mls` Cargo
feature and packaged only into the separate `beta` flavor's `jniLibs` source set. The
build script fails the build on any deviation from either list, so a production artifact
that exported the closed-beta PQ MLS entry point could not be produced. Its public status
range is the payload-free integer set 0
through 14 frozen in `native/crypto_core/include/communication_crypto.h`. Enrollment,
peer identity/device/prekey/log verification, safety fingerprints, and user-signing
attestation cross only through these bounded typed operations; private key material
remains inside opaque Rust identity packages. Rust-owned `SecretBytes` and `SecretVec` values are
non-`Debug`, non-`Clone`, and zeroized on drop, while the testable provider owns secure
randomness, allocation/input bounds, and primitive implementations.

### Windows host prerequisites

Cargo compiles build scripts and proc-macros for the **host** even when
cross-compiling, so every gate — including the Android cross-builds — needs a
complete host toolchain. `rust-toolchain.toml` pins Rust 1.97.1 and the host is
`x86_64-pc-windows-msvc`, so install these once and use the pinned toolchain
unmodified. Do not override `RUSTUP_TOOLCHAIN`.

| Prerequisite | Needed by | Install |
|---|---|---|
| VS 2022 Build Tools, `VC.Tools.x86.x64` + Windows SDK | host `link.exe`/`cl.exe`; without it nothing links | `winget install Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"` |
| LLVM (`libclang.dll`) | the `aws-lc-sys` `bindgen` feature used by the beta profile | `winget install LLVM.LLVM`, then set `LIBCLANG_PATH=C:\Program Files\LLVM\bin` |
| NASM | `aws-lc-sys` x86-64 assembly when building the beta feature for the host | `winget install NASM.NASM` |
| Ninja | CMake generator for AWS-LC; Windows CMake otherwise picks a Visual Studio generator that cannot drive the NDK cross-compiler | `winget install Ninja-build.Ninja` |
| CMake, Android NDK 28.2.13676358 | AWS-LC configure; Android targets | Android Studio SDK manager / CMake installer |

Put `%USERPROFILE%\.cargo\bin`, `C:\Program Files\LLVM\bin`, the NASM directory,
and `%LOCALAPPDATA%\Microsoft\WinGet\Links` on `PATH`, and Git's `bash.exe` must
be resolvable for the POSIX build scripts.

Two cross-compilation details are handled by the build scripts rather than the
environment. `libsodium-sys-stable` 1.24.0 picks its link name with
`cfg!(target_env = "msvc")`, which a build script evaluates against the host
instead of the target, so `build_libsodium_android.sh` installs the archive as
both `libsodium.a` and `liblibsodium.a`. `aws-lc-sys` needs a target C++
compiler, `ANDROID_NDK_ROOT`, and an explicit generator, so
`build_rust_android.sh` exports `CXX_<target>`, `ANDROID_NDK_ROOT`,
`ANDROID_NDK`, and `CMAKE_GENERATOR=Ninja` for the beta profile.

CMake caches its generator in the build directory. After changing generators,
delete `build/rust-android/<profile>` before rebuilding.

Verification on 2026-07-28 passed:

- `cargo fmt --manifest-path native/crypto_core/Cargo.toml -- --check`;
- `cargo test --locked --manifest-path native/crypto_core/Cargo.toml`;
- `cargo clippy --locked --all-targets --all-features --manifest-path
  native/crypto_core/Cargo.toml -- -D warnings`;
- `powershell -File tool/build_rust_android.ps1 all`;
- debug and production-release APK builds with all three native ABIs; and
- `flutter test integration_test/crypto_core_android_smoke_test.dart -d
  <android-device> --flavor development` on an Android 15/API 35 x86_64 emulator.

This Android scope does not implement PQXDH, Double Ratchet, MLS state,
application-message schemas, production KeyPackages, or the post-v1 Web/Wasm adapter.
It is sufficient for the Android-only version-1 foundation; browser interoperability
remains a post-v1 release gate.

## Network trust

Production accepts only the provisioned origin and private CA. Native network security
configuration and the HTTP/WebSocket clients enforce primary and backup SPKI pins. Pin
failure is blocking and never offers "continue anyway". Development trust is compiled
only into visibly non-production flavors.

**Android's network security configuration does not govern this app's API
traffic.** It applies to the platform's Java HTTP stacks and WebView. Both of
this client's transports — Dio for REST and `IOWebSocketChannel` for the socket
— run on `dart:io`, which does not consult it. Release validation established
this against a live server: every network precondition held and the connection
still failed, and removing the pin-set changed nothing (ADR-043).

Trust for the app's own traffic is therefore installed in Dart, at
`features/networking/infrastructure/tls/`. `TransportSecurity.provisioned`
builds a `SecurityContext` with `withTrustedRoots: false` and the provisioned
authority, so the built-in root store is **replaced**, not extended: no public
authority can issue a certificate this client accepts. Chain construction,
expiry, and hostname verification are still performed in full by the platform
TLS implementation. The REST client and the WebSocket connector share one
context, so neither can be left on default trust.

The authority reaches the app as `<ENVIRONMENT>_PRIVATE_CA_PEM_BASE64`, because
`dart:io` verifies against a certificate rather than the fingerprint the
configuration carries. Absent or malformed authority material blocks at
configuration rather than falling back to public roots.

The closed-beta flavor still renders the Android resources from its `BETA_*`
values — `tool/render_beta_trust.sh` refuses to run unless the supplied CA file
matches `BETA_PRIVATE_CA_SHA256`, and `tool/verify_release_apk.sh --beta` reads
the pin-set back out of the artifact — but that configuration is retained as
defence in depth for any future WebView or Java-side traffic. It is not what
protects the API traffic, and must not be described as though it were.

Leaf SPKI pinning is deliberately not reimplemented in Dart: `X509Certificate`
exposes no SPKI accessor and no SHA-256, so it would take hand-written ASN.1
parsing and a hashing dependency inside the TLS path. Anchoring exclusively to
one offline private root is the stronger constraint; see ADR-043 for the
residual exposure that choice accepts.

## Background delivery

There is no FCM/APNs fallback and there never will be: the transport this deployment must
survive without is exactly the one FCM depends on. Correctness therefore rests on the
backend durable queue, not on instant background notification.

ADR-046 replaces ADR-029's single mechanism with three layers, because measurement of the
platform showed one mechanism cannot span the range. A backgrounded process with no
running component is cached, and a frozen app's "active TCP sockets" are terminated by the
system, so an unattended socket is closed rather than merely slow. `WorkManager`'s
periodic floor is 15 minutes, Doze defers `JobScheduler` to maintenance windows that
thin out over time, Android 16 enforces job runtime quota even in the *active* standby
bucket, and the *rare* and *restricted* buckets disable background network entirely. The
one app state Android documents as having unrestricted background network is "app process
is running a foreground service".

Modes:

- **Active app:** WebSocket wake-up hints plus authoritative REST drain. This is Layer 0
  and is mandatory; it is also, as of 2026-08-21, not yet composed — see the piece-12
  note below.
- **Background floor (Layer 1, no user action):** `WorkManager` behind the existing
  `AndroidPollingScheduler` port — one periodic request at the platform floor with a
  connected-network constraint, plus one-shots on connectivity recovery and
  `ACTION_BOOT_COMPLETED`. It is never advertised as instant or exact-periodic and starts
  no service. Its honest tier is *eventual*, and in the *rare* and *restricted* buckets it
  is nothing at all.
- **Background near-real-time (Layer 2, opt-in, off by default):** a `specialUse`
  foreground service that keeps the process non-cached so the same composed socket
  survives, declared with a truthful `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE`. It
  hosts the same isolate and the same supervisor and adds no second delivery
  implementation. Enabling it asks for `POST_NOTIFICATIONS`, asks for the
  battery-optimization exemption through `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`,
  and explains the vendor settings the app cannot check for itself.
- **Active voice:** microphone/communication foreground service for the duration of the
  joined room with visible controls.

`specialUse` is chosen deliberately. `dataSync` is capped at six hours per twenty-four and
cannot be launched from a `BOOT_COMPLETED` receiver at `targetSdk` 35+; `remoteMessaging`
documents device-to-device message continuity, not holding a connection to the
application's own server; `systemExempted` is gated on device-owner, VPN or exact-alarm
roles this app does not have. **The app still MUST NOT label delivery work as
`remoteMessaging` or `dataSync`**, and `test/architecture/sync_platform_policy_test.dart`
continues to enforce that.

Exactly one delivery owner runs at a time — foreground isolate, service isolate, or
headless worker — held as a durable leased Drift row rather than an in-memory flag.
Concurrent owners would open several sockets and, far worse, race several
`TokenCoordinator` instances on a *rotating* refresh token, which can invalidate the
session.

Force-stop, Doze, standby buckets and OEM restrictions may delay messages or stop them
entirely; resume always drains the authoritative queue and checks `pruned_through`. What
the platform *guarantees* and what it merely *permits* are recorded separately in ADR-046
and may not be conflated in any user-facing string.

### Piece-12 synchronization baseline

Piece 12 pins `connectivity_plus` 6.0.5 for OS-reported link transitions. A reported
transport is only a scheduling hint: Android explicitly does not guarantee that an
available network can reach a particular server, so the provisioned backend REST result
remains authoritative and no public connectivity probe is added. The lifecycle
supervisor pauses reconnect timers while no transport is reported and always performs a
REST drain after foreground resume, network recovery, or a WebSocket envelope hint.

Android background polling is exposed through an app-owned best-effort scheduler port
whose headless callback must reconstruct its own database and network dependencies; it
never assumes foreground-isolate memory survived. The port makes no exact-periodic or
instant-delivery promise and grants no messaging foreground service. Concrete
WorkManager registration plus the physical-device Doze, standby, reboot, and force-stop
matrix remain release validation gates.

This choice was verified on 2026-07-29 against the
[`connectivity_plus` 6.0.5 release](https://pub.dev/packages/connectivity_plus/versions/6.0.5)
and Android's
[`ConnectivityManager.NetworkCallback`](https://developer.android.com/reference/android/net/ConnectivityManager.NetworkCallback)
and [network-state guidance](https://developer.android.com/develop/connectivity/network-ops/reading-network-state).

**Composed on 2026-08-21 (ADR-047), correcting the gap ADR-046 recorded.** Until then
`SyncLifecycleSupervisor`, `DioWebSocketGateway` and `GatewayRealtimeSyncAdapter` were
constructed only in tests and `durableSyncEngineProvider` was read by nothing, so the
artifact opened no socket, ran no drain, and — because `SendConversationEvents` ends at
`fanout.prepareAndQueue` — transmitted no outbox row either. ADR-046's Layer 0 is now
implemented: `MessageDeliveryController` starts one `MessageDeliverySession` per
device-bound full session and stops it on logout, and the two composition roots are
resolved into one, so the socket presents the same access token, refreshes through the
same single-flight `TokenCoordinator`, and terminates its TLS chain at the same
provisioned authority as every REST call. Layers 1 to 3 remain unbuilt: this build
composes `UnscheduledBestEffortPolling`, which schedules nothing, so a backgrounded
application still performs no catch-up and posts no notification.

## Notifications

- Local notifications are created only after authenticated decryption and durable local
  commit, and only from the existing post-inbox-commit work port — never from a transport
  event. A socket frame is a wake-up hint and can never produce a notification by itself.
- A notification is a projection of committed local state: rows that are committed,
  unread, and carry no durable `notified_at` marker. The marker is written in the same
  transaction, because the isolate that notifies may not be the one that returns.
- Missed notifications recover by query, not replay. Everything unread and un-notified is
  eligible at the next successful commit pass, with a bounded number of individual
  notifications and one grouped summary beyond that threshold.
- An envelope that was quarantined, rejected, or retained by queue-gap recovery never
  produces a notification.
- Default preview is hidden: app name, sender-neutral "New message", and open action.
- User may opt into decrypted previews with a clear lock-screen warning.
- The Layer 2 foreground-service notification is itself a privacy surface: it is a
  durable, visible indication on the device that this application is armed. Its channel is
  low importance, silent, and neutrally worded, and that trade is why background delivery
  is opt-in rather than default.
- Conversation IDs/people shortcuts never expose backend capabilities or raw identifiers.
- Tapping routes through unlock/session validation before opening content.
- Notification actions are bounded signed local intents, validated again by application
  use cases.

## Permissions

Request only at point of use:

- notifications (`POST_NOTIFICATIONS`, Android 13+) for locally received message alerts
  and active-voice disclosure. Notifications are off by default on a fresh install and a
  refusal blocks every non-exempt channel, so denial is a stated outcome, not a retry loop;
- the battery-optimization exemption, requested through
  `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` only when the user enables background
  delivery. Android's own Doze acceptable-use table rates this **acceptable** for a chat
  application that cannot use FCM for a technical reason, which is this application
  exactly; the grant is what lets the app "use the network and hold partial wake locks
  during Doze and App Standby". Losing it degrades Layer 2 to Layer 1 and must be surfaced,
  not hidden;
- microphone for joining voice;
- camera for capture/optional safety QR;
- media/files through system pickers without broad storage permission.

`RECEIVE_BOOT_COMPLETED` is declared for re-arming delivery after reboot. Only
`ACTION_BOOT_COMPLETED` is handled; `ACTION_LOCKED_BOOT_COMPLETED` is deliberately not,
because the database key is credential-encrypted and nothing can be decrypted before first
unlock — a direct-boot start must fail closed rather than degrade.

Vendor battery settings — Samsung's "put apps to sleep" and adaptive battery, Xiaomi's
autostart and battery saver — govern roughly 77% of the target fleet and cannot be read or
changed by the application. They are explained to the user once, as instructions, and never
presented as something the app has verified.

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

Because distribution is a direct APK rather than an App Bundle through a store,
Play App Signing does not apply: the application signing key is the distribution
identity permanently, and there is no upload-key reset if it is lost. The Private
Experimental Beta therefore has a frozen application ID and a single persistent
signing key, with `minSdk` 24 fixing the available signature schemes at v2 and
v3. Key custody, backup and recovery, the release procedure, artifact
verification, and the upgrade-continuity proof are specified in
[Beta release signing and key continuity](release-signing.md) under ADR-042.

## Primary references

- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [`sqlite3` 3.5.0 build-hook options](https://pub.dev/documentation/sqlite3/3.5.0/topics/hook-topic.html)
- [SQLCipher keying order](https://github.com/sqlcipher/sqlcipher#encrypting-a-database)
- [Android background work](https://developer.android.com/develop/background-work)
- [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Foreground-service timeouts](https://developer.android.com/develop/background-work/services/fgs/timeout)
- [Restrictions on starting a foreground service from the background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Power-management restrictions and app standby buckets](https://developer.android.com/topic/performance/power/power-details)
- [Doze and App Standby, including the exemption acceptable-use table](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Cached apps freezer (AOSP)](https://source.android.com/docs/core/perf/cached-apps-freezer)
- [Android 14 behavior changes: cached-app resource enforcement](https://developer.android.com/about/versions/14/behavior-changes-all)
- [Android 15 behavior changes: foreground-service boot restrictions and timeouts](https://developer.android.com/about/versions/15/behavior-changes-15)
- [Android 16 behavior changes: JobScheduler quota enforcement](https://developer.android.com/about/versions/16/behavior-changes-all)
- [Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)
- [WorkManager periodic work and constraints](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work)

The background-delivery and notification sources above were read at primary source on
2026-08-21 for ADR-046, against `minSdk` 24 / `targetSdk` 36 / `compileSdk` 36 as pinned
by Flutter 3.44.7.
