# Communication Platform frontend

Minimal Flutter foundation for the Android and Web client. The product name and all
brand assets remain provisional. Piece 03 adds the adaptive application shell and an
explicitly non-shipping structural placeholder; no product feature screens or service
integrations are present.

The app bundles Vazirmatn `v33.003` and its SIL OFL 1.1 license under
`assets/fonts/vazirmatn/`. The exact artifact and checksum provenance is recorded in
`docs/visual-design-system.md`; neither Android nor Web fetches fonts or visual assets at
runtime.

## Toolchain

- Flutter `3.44.7` (also recorded in `.fvmrc`)
- Dart `3.12.2`
- Android and Web targets only

Run dependency resolution from this directory:

```sh
flutter pub get --enforce-lockfile
```

The repository `pubspec.lock` is authoritative. Release and isolated build environments
must provide Flutter, Pub, Gradle, and Android artifacts from an approved local cache or
mirror; the application has no foreign runtime dependency.

## Environments and identifiers

The Android namespace and application IDs deliberately use the reserved `com.example`
placeholder until final branding is approved:

| Environment | Dart entry point | Android application ID |
|---|---|---|
| Development | `lib/main_development.dart` | `com.example.communication_platform.development` |
| Production | `lib/main_production.dart` | `com.example.communication_platform` |

Plain `flutter run` uses `lib/main.dart`, which delegates to development and always
shows a visible non-production label. Production builds must select the production
entry point explicitly.

Both entry points load exactly one HTTPS origin from environment-specific compile-time
defines. There is no runtime server selector, remote configuration, certificate bypass,
public connectivity probe, telemetry, or third-party runtime resource loader. A build
without complete provisioning stops at the blocking Connection screen.

The controlled build environment supplies these public provisioning values (never
credentials or private keys):

- `<ENVIRONMENT>_SERVER_ORIGIN` (an HTTPS origin with no path/query/fragment);
- `<ENVIRONMENT>_PRIVATE_CA_SHA256` (64 hexadecimal characters);
- Android only: `<ENVIRONMENT>_PRIMARY_SPKI_SHA256` and
  `<ENVIRONMENT>_BACKUP_SPKI_SHA256` (distinct base64 SHA-256 digests).

`<ENVIRONMENT>` is `DEVELOPMENT` or `PRODUCTION`; one artifact reads only its own prefix.
Android also requires the build-local resource generation described in
`android/provisioning/README.md`. Web has no CA-install or pinning API: the operator must
install the private CA into the OS/browser trust store out of band before the page can
connect, and a trust failure has no bypass.

```sh
flutter run --flavor development --target lib/main_development.dart
flutter build apk --release --flavor production --target lib/main_production.dart
flutter build web --release --target lib/main_production.dart
```

Android release signing is intentionally absent until the reviewed release piece.

## Generation and verification

Localization and builder output are deterministic under the pinned SDK, constraints,
and lockfile. Run the repository generator command after editing ARB or annotated files:

```powershell
./tool/generate.ps1
```

```sh
sh ./tool/generate.sh
```

The local CI commands run locked dependency resolution, generation with a clean-diff
check, strict Flutter analysis, widget/unit tests, a development Android build,
production Android compilation, and a production Web build:

```powershell
./tool/ci.ps1
```

```sh
sh ./tool/ci.sh
```
