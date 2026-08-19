#!/usr/bin/env bash
# Prove that a new Beta artifact upgrades an existing Beta install in place,
# without an uninstall, and without losing local state.
#
# This is the check that signing exists for. A signed APK proves nothing on its
# own: what matters is that the OS accepts it as an update to what users already
# have, because for this app an uninstall is unrecoverable. Uninstalling erases
# all app data, here both the SQLCipher database and the envelope holding its
# key, and the manifest disables backup, so nothing restores either. The
# database key is protected by a non-exportable AndroidKeyStore key, so no
# exportable copy of it exists anywhere.
#
# Three tiers of evidence, reported separately and honestly:
#
#   Tier 1  always. The OS accepts the upgrade, the install identity is
#           preserved, and an artifact signed by a different key is rejected.
#   Tier 2  when the device allows adb root. The wrapped storage key and the
#           encrypted database survive the upgrade byte for byte, and still
#           survive after the upgraded build has launched and unwrapped them.
#   Tier 3  manual, documented in docs/release-signing.md. Real account, group
#           and message history across the upgrade against a live backend.
#
# A tier that cannot run is reported as SKIPPED. It is never reported as passed.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/release_env.sh"

old_apk=""
new_apk=""
device_serial="${ANDROID_SERIAL:-}"
assume_yes=0
run_negative_control=1

usage() {
  cat <<'USAGE'
Usage: tool/verify_upgrade_continuity.sh --old <apk> --new <apk> [options]

  --old APK                 The already-released artifact users have installed.
  --new APK                 The candidate artifact to upgrade them to.
  --serial S                Target device/emulator (default: the only one attached).
  --yes                     Do not prompt before uninstalling the app under test.
  --skip-negative-control   Skip proving that a wrong-key artifact is rejected.

THIS UNINSTALLS the application under test on the target device to establish a
clean baseline. Never point it at a device holding real beta data.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --old) old_apk="$2"; shift 2 ;;
    --new) new_apk="$2"; shift 2 ;;
    --serial) device_serial="$2"; shift 2 ;;
    --yes) assume_yes=1; shift ;;
    --skip-negative-control) run_negative_control=0; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$old_apk" && -n "$new_apk" ]] || { usage >&2; fail "--old and --new are required."; }
[[ -f "$old_apk" ]] || fail "Not found: $old_apk"
[[ -f "$new_apk" ]] || fail "Not found: $new_apk"
[[ -x "$adb_tool" ]] || fail "adb not found at $adb_tool"

adb() {
  if [[ -n "$device_serial" ]]; then
    "$adb_tool" -s "$device_serial" "$@"
  else
    "$adb_tool" "$@"
  fi
}

tier1_results=()
tier2_results=()
tier2_state="skipped"
failures=0

record() {
  local -n bucket="$1"
  bucket+=("$2 $3")
  [[ "$2" == "FAIL" ]] && failures=$((failures + 1))
  return 0
}

expect() {
  local bucket="$1" description="$2" actual="$3" expected="$4"
  if [[ "$actual" == "$expected" ]]; then
    record "$bucket" "PASS" "$description"
  else
    record "$bucket" "FAIL" "$description (expected '$expected', got '$actual')"
  fi
}

# --- Artifact preconditions --------------------------------------------------

echo "== Artifact verification =="
"$frontend_root/tool/verify_release_apk.sh" --beta "$old_apk" > /dev/null ||
  fail "The --old artifact does not verify as a Beta release."
"$frontend_root/tool/verify_release_apk.sh" --beta "$new_apk" > /dev/null ||
  fail "The --new artifact does not verify as a Beta release."
echo "  ok    both artifacts carry the frozen Beta identity $beta_certificate_sha256"

apk_version_code() {
  aapt2 dump badging "$(to_native_path "$1")" |
    sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" | head -n 1
}

old_version_code="$(apk_version_code "$old_apk")"
new_version_code="$(apk_version_code "$new_apk")"
[[ "$new_version_code" -gt "$old_version_code" ]] ||
  fail "The new version code ($new_version_code) must be greater than the old one
       ($old_version_code). Android refuses to install a downgrade."
echo "  ok    version code advances $old_version_code -> $new_version_code"
echo

# --- Device ------------------------------------------------------------------

attached="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
[[ -n "$attached" ]] || fail "No device or emulator is attached."
if [[ -z "$device_serial" && "$(printf '%s\n' "$attached" | wc -l)" -gt 1 ]]; then
  fail "More than one device is attached. Choose one with --serial."
fi
echo "== Device $(adb shell getprop ro.product.model | tr -d '\r') (API $(adb shell getprop ro.build.version.sdk | tr -d '\r')) =="

if [[ "$assume_yes" -ne 1 ]]; then
  echo
  echo "This will UNINSTALL $beta_application_id on the target device."
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || fail "Aborted."
fi

adb uninstall "$beta_application_id" > /dev/null 2>&1 || true

package_field() {
  adb shell dumpsys package "$beta_application_id" |
    tr -d '\r' |
    sed -n "s/^[[:space:]]*$1=\([^[:space:]]*\).*/\1/p" |
    head -n 1
}

launch_and_settle() {
  adb shell monkey -p "$beta_application_id" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
  # The bootstrap flow creates the AndroidKeyStore key and the encrypted
  # database before it reaches any blocking screen.
  sleep 12
  adb shell am force-stop "$beta_application_id"
  sleep 2
}

# --- Tier 1: the OS accepts the upgrade --------------------------------------

echo
echo "== Tier 1: install and upgrade semantics =="

adb install "$(to_native_path "$old_apk")" > /dev/null ||
  fail "The previous artifact would not install on a clean device."
record tier1_results "PASS" "baseline artifact installs on a clean device"

launch_and_settle

baseline_first_install="$(package_field firstInstallTime)"
baseline_version_code="$(package_field versionCode)"
expect tier1_results "baseline reports version code $old_version_code" \
  "$baseline_version_code" "$old_version_code"

# --- Tier 2 capture (root only) ---------------------------------------------

readonly data_root="/data/data/$beta_application_id"
readonly wrapped_key_path="$data_root/no_backup/storage_key_v1.bin"
readonly database_path="$data_root/app_flutter/communication_platform_secure_local.sqlite"

device_digest() {
  adb shell "sha256sum '$1' 2>/dev/null | cut -d' ' -f1" | tr -d '\r'
}

if adb root > /dev/null 2>&1 && sleep 3 && adb wait-for-device &&
  [[ "$(adb shell id -u | tr -d '\r')" == "0" ]]; then
  tier2_state="ran"
else
  tier2_state="skipped"
fi

if [[ "$tier2_state" == "ran" ]]; then
  baseline_key_digest="$(device_digest "$wrapped_key_path")"
  baseline_database_digest="$(device_digest "$database_path")"
  if [[ -z "$baseline_key_digest" || -z "$baseline_database_digest" ]]; then
    record tier2_results "FAIL" \
      "the baseline install did not create its protected storage (key='$baseline_key_digest' db='$baseline_database_digest')"
    tier2_state="incomplete"
  else
    record tier2_results "PASS" "baseline created the wrapped storage key and encrypted database"
  fi
fi

# --- The upgrade itself ------------------------------------------------------

# No -d (downgrade), no uninstall: exactly what a beta user's device would do.
if upgrade_output="$(adb install -r "$(to_native_path "$new_apk")" 2>&1)"; then
  record tier1_results "PASS" "the OS accepted the upgrade in place, with no uninstall"
else
  record tier1_results "FAIL" "the OS rejected the upgrade: $upgrade_output"
fi

upgraded_first_install="$(package_field firstInstallTime)"
upgraded_version_code="$(package_field versionCode)"

expect tier1_results "version code advanced to $new_version_code" \
  "$upgraded_version_code" "$new_version_code"
expect tier1_results "firstInstallTime unchanged, so this was an update and not a reinstall" \
  "$upgraded_first_install" "$baseline_first_install"

if [[ "$tier2_state" == "ran" ]]; then
  upgraded_key_digest="$(device_digest "$wrapped_key_path")"
  upgraded_database_digest="$(device_digest "$database_path")"
  expect tier2_results "the wrapped storage key survived the upgrade byte for byte" \
    "$upgraded_key_digest" "$baseline_key_digest"
  expect tier2_results "the encrypted database survived the upgrade byte for byte" \
    "$upgraded_database_digest" "$baseline_database_digest"

  # The decisive one. If the AndroidKeyStore alias had not survived, the storage
  # runtime would report wrappingKeyLost and wipe local state on this launch, so
  # an unchanged digest after a real launch proves the upgraded build actually
  # unwrapped the existing key rather than starting over.
  launch_and_settle
  relaunched_key_digest="$(device_digest "$wrapped_key_path")"
  relaunched_database_digest="$(device_digest "$database_path")"
  expect tier2_results "the upgraded build unwrapped the existing storage key instead of wiping" \
    "$relaunched_key_digest" "$baseline_key_digest"
  expect tier2_results "the encrypted database is still intact after the upgraded build ran" \
    "$relaunched_database_digest" "$baseline_database_digest"
fi

# --- Negative control: a different key must be refused -----------------------

if [[ "$run_negative_control" -eq 1 ]]; then
  echo
  echo "== Negative control: an artifact signed by a different key =="
  control_directory="$(mktemp -d)"
  trap 'rm -rf "$control_directory"' EXIT INT TERM
  export CP_CONTROL_PASSPHRASE="negative-control-$RANDOM$RANDOM"

  keytool -genkeypair \
    -alias control \
    -keyalg RSA -keysize 2048 -validity 30 \
    -storetype PKCS12 \
    -keystore "$(to_native_path "$control_directory/control.p12")" \
    -dname "CN=upgrade continuity negative control" \
    -storepass:env CP_CONTROL_PASSPHRASE \
    -keypass:env CP_CONTROL_PASSPHRASE > /dev/null 2>&1

  apksigner sign \
    --ks "$(to_native_path "$control_directory/control.p12")" \
    --ks-key-alias control \
    --ks-pass env:CP_CONTROL_PASSPHRASE \
    --key-pass env:CP_CONTROL_PASSPHRASE \
    --out "$(to_native_path "$control_directory/wrong-key.apk")" \
    "$(to_native_path "$new_apk")" > /dev/null 2>&1
  unset CP_CONTROL_PASSPHRASE

  if control_output="$(adb install -r "$(to_native_path "$control_directory/wrong-key.apk")" 2>&1)"; then
    record tier1_results "FAIL" \
      "an artifact signed by a DIFFERENT key was accepted as an update; signature continuity is not being enforced"
  else
    case "$control_output" in
      *INSTALL_FAILED_UPDATE_INCOMPATIBLE* | *INCONSISTENT_CERTIFICATES* | *signatures*)
        record tier1_results "PASS" \
          "a differently signed artifact is rejected, so signing identity really is what gates the upgrade"
        ;;
      *)
        record tier1_results "FAIL" \
          "the differently signed artifact was rejected for an unexpected reason: $control_output"
        ;;
    esac
  fi
fi

# --- Report ------------------------------------------------------------------

echo
echo "================ upgrade continuity ================"
echo "Application ID    $beta_application_id"
echo "Signing identity  $beta_certificate_sha256"
echo "Upgrade           $old_version_code -> $new_version_code"
echo
echo "Tier 1: install and upgrade semantics"
for line in "${tier1_results[@]}"; do echo "  $line"; done
echo
echo "Tier 2: local state survival (requires adb root)"
case "$tier2_state" in
  ran) for line in "${tier2_results[@]}"; do echo "  $line"; done ;;
  incomplete)
    for line in "${tier2_results[@]}"; do echo "  $line"; done
    echo "  the tier did not complete"
    ;;
  skipped)
    echo "  SKIPPED  this device does not allow adb root, so file-level survival"
    echo "           was not observed. Google Play system images are always user"
    echo "           builds; use a google_apis (non-Play) emulator image to run"
    echo "           this tier. NOT counted as a pass."
    ;;
esac
echo
echo "Tier 3: real account, group and message history"
echo "  MANUAL   see 'Proving upgrade continuity' in docs/release-signing.md."
echo "===================================================="

if [[ "$failures" -gt 0 ]]; then
  echo
  echo "$failures check(s) FAILED. Do not distribute this artifact."
  exit 1
fi
echo
echo "All executed checks passed."
