#!/usr/bin/env bash
# Build, sign and verify one distributable Private Experimental Beta artifact.
#
# This is the only supported way to produce an APK for beta users. It fails
# closed on missing provisioning, missing signing material, or any identity
# mismatch, and it refuses to emit an artifact it has not verified.

set -euo pipefail
set +x

source "$(dirname "${BASH_SOURCE[0]}")/release_env.sh"

build_number=""
build_name=""

usage() {
  cat <<'USAGE'
Usage: tool/build_beta_release.sh --build-number N [--build-name X]

  --build-number N   Android versionCode. MUST be strictly greater than the last
                     released Beta build number; Android refuses downgrades.
  --build-name X     Human version name (default: the pubspec version).

Required environment (public provisioning values, never secrets):
  BETA_SERVER_ORIGIN         https origin, no path or query
  BETA_PRIVATE_CA_SHA256     64 hex characters
  BETA_PRIMARY_SPKI_SHA256   base64 SHA-256 pin
  BETA_BACKUP_SPKI_SHA256    base64 SHA-256 pin, different from the primary
  BETA_PRIVATE_CA_PEM        path to the private CA certificate, PEM form

Required signing material, supplied one of two ways:
  CP_BETA_SIGNING_PROPERTIES pointing at an untracked properties file, or
  CP_BETA_KEYSTORE_FILE + CP_BETA_KEYSTORE_PASSWORD + CP_BETA_KEY_ALIAS +
  CP_BETA_KEY_PASSWORD.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-number) build_number="$2"; shift 2 ;;
    --build-name) build_name="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$build_number" ]] || { usage >&2; fail "--build-number is required."; }
[[ "$build_number" =~ ^[0-9]+$ ]] || fail "--build-number must be a positive integer."

# --- Preconditions -----------------------------------------------------------

[[ -n "$beta_certificate_sha256" ]] ||
  fail "No Beta signing identity is recorded in android/beta-release-identity.properties.
       Create one once with tool/create_beta_keystore.sh, commit the fingerprint,
       and back the keystore up before building anything for users."

missing_provisioning=()
for name in BETA_SERVER_ORIGIN BETA_PRIVATE_CA_SHA256 BETA_PRIMARY_SPKI_SHA256 \
  BETA_BACKUP_SPKI_SHA256 BETA_PRIVATE_CA_PEM; do
  [[ -n "${!name:-}" ]] || missing_provisioning+=("$name")
done
if [[ "${#missing_provisioning[@]}" -gt 0 ]]; then
  fail "Missing Beta provisioning: ${missing_provisioning[*]}.
       A build without complete provisioning stops at the blocking Connection
       screen and is useless to a beta user."
fi

# Check that signing material exists before spending build time on it. Only
# presence is checked here; nothing reads or prints a password.
signing_properties="${CP_BETA_SIGNING_PROPERTIES:-$android_root/beta-signing.properties}"
if [[ -z "${CP_BETA_KEYSTORE_FILE:-}" && ! -f "$signing_properties" ]]; then
  fail "No Beta signing material. Expected $signing_properties or the
       CP_BETA_KEYSTORE_* environment variables. See docs/release-signing.md."
fi

# --- Build -------------------------------------------------------------------

cd "$frontend_root"

# Render the native trust resources from the same values compiled into Dart, on
# every build. Dart cannot enforce a pin; Android does that from a compiled
# resource, so a stale or absent one would silently ship an unpinned artifact.
echo
"$frontend_root/tool/render_beta_trust.sh"
echo

readonly source_revision="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
readonly source_dirty="$(git status --porcelain 2>/dev/null | head -n 1)"
if [[ -n "$source_dirty" ]]; then
  echo "warning: the working tree has uncommitted changes, so this artifact is" >&2
  echo "         not reproducible from $source_revision alone." >&2
fi

build_arguments=(
  build apk
  --release
  --flavor beta
  --target lib/main_beta.dart
  --build-number "$build_number"
  "--dart-define=BETA_SERVER_ORIGIN=$BETA_SERVER_ORIGIN"
  "--dart-define=BETA_PRIVATE_CA_SHA256=$BETA_PRIVATE_CA_SHA256"
  "--dart-define=BETA_PRIMARY_SPKI_SHA256=$BETA_PRIMARY_SPKI_SHA256"
  "--dart-define=BETA_BACKUP_SPKI_SHA256=$BETA_BACKUP_SPKI_SHA256"
)
[[ -n "$build_name" ]] && build_arguments+=(--build-name "$build_name")

export JAVA_HOME="$jdk_home"
echo "Building Beta release, build number $build_number."
flutter "${build_arguments[@]}"

readonly built_apk="$frontend_root/build/app/outputs/flutter-apk/app-beta-release.apk"
[[ -f "$built_apk" ]] || fail "Expected artifact not produced: $built_apk"

# --- Verify before publishing anywhere ---------------------------------------

echo
"$frontend_root/tool/verify_release_apk.sh" --beta "$built_apk"

# --- Publish the verified artifact -------------------------------------------

readonly release_directory="$frontend_root/build/beta-release"
mkdir -p "$release_directory"

resolved_version_name="$(aapt2 dump badging "$(to_native_path "$built_apk")" |
  sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -n 1)"
readonly artifact_name="communication-platform-beta-$resolved_version_name-$build_number.apk"
readonly artifact_path="$release_directory/$artifact_name"

cp "$built_apk" "$artifact_path"
(cd "$release_directory" && sha256sum "$artifact_name" > "$artifact_name.sha256")

cat > "$artifact_path.metadata.txt" <<METADATA
Communication Platform - Private Experimental Beta
Artifact:             $artifact_name
Built (UTC):          $(date -u +%Y-%m-%dT%H:%M:%SZ)
Source revision:      $source_revision${source_dirty:+ (working tree dirty)}
Application ID:       $beta_application_id
Version name:         $resolved_version_name
Version code:         $build_number
Signing certificate:  $beta_certificate_sha256
SHA-256:              $(cut -d' ' -f1 < "$artifact_path.sha256")
Server origin:        $BETA_SERVER_ORIGIN

Verified by tool/verify_release_apk.sh --beta before publication.
Recipients should check the SHA-256 above, and may confirm the signing
certificate themselves with:
  apksigner verify --print-certs $artifact_name
METADATA

cat <<SUMMARY

Beta release artifact ready.

  $artifact_path
  $artifact_path.sha256
  $artifact_path.metadata.txt

Before handing it to users, confirm the upgrade path on a device:
  tool/verify_upgrade_continuity.sh --old <previous release apk> --new $artifact_path
SUMMARY
