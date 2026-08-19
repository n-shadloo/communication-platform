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

| Environment | Dart entry point | Android application ID |
|---|---|---|
| Development | `lib/main_development.dart` | `dev.nimashadloo.chat.development` |
| Closed beta | `lib/main_beta.dart` | `dev.nimashadloo.chat.beta` |
| Production | `lib/main_production.dart` | `dev.nimashadloo.chat` |

The three are separate, coexisting applications; none upgrades into another. The
closed-beta ID is **frozen** and lives in `android/beta-release-identity.properties`,
which the build reads and the release verification checks against. Changing it after
the first external install would force every beta user through an uninstall that
permanently destroys their local state — see
[Beta release signing and key continuity](docs/release-signing.md).

The Android `namespace` is still `com.example.communication_platform`. That is only
the build-time Kotlin/resource package and is not part of the installed identity.

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

`<ENVIRONMENT>` is `DEVELOPMENT`, `BETA`, or `PRODUCTION`; one artifact reads only its own prefix.
The beta artifact uses a distinct backend origin, Android application ID, and local
storage namespace. Its closed-beta PQ MLS state is disposable and is never migrated into
production state. That beta suite is hybrid ML-KEM-768/X25519 on a Private Use
identifier; it is not the IETF draft suite the production profile selects, and
`docs/mls-profile.md` records exactly how the two differ.
Closed-beta MLS transport v3 authenticates later Welcome/re-add with
the complete bounded signed control transcript. V2 beta groups and queued group objects
lack that evidence and must be recreated/rejoined rather than silently migrated.
Android also requires the build-local resource generation described in
`android/provisioning/README.md`. Web has no CA-install or pinning API: the operator must
install the private CA into the OS/browser trust store out of band before the page can
connect, and a trust failure has no bypass.

```sh
flutter run --flavor development --target lib/main_development.dart
flutter build apk --release --flavor beta --target lib/main_beta.dart
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
