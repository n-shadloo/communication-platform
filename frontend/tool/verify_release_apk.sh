#!/usr/bin/env bash
# Verify a built release artifact against the frozen release identity.
#
# This is the gate that decides whether an APK may be handed to a beta user.
# It answers three separate questions, all of which must hold:
#
#   * is this the application it claims to be (application ID)?
#   * is it signed by the one identity every existing install already trusts?
#   * is the Beta/Production native separation intact in the packaged artifact?
#
# Every check fails closed. A check that cannot be performed is an error, never
# a pass.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/release_env.sh"

mode=""
apk_path=""

usage() {
  cat <<'USAGE'
Usage: tool/verify_release_apk.sh (--beta | --production) <apk>

  --beta         Verify a distributable Beta artifact: correct application ID,
                 signed by the frozen Beta identity, Beta MLS core present.
  --production   Verify a Production artifact: correct application ID, NOT
                 signed (so it cannot be installed), Beta MLS core absent.

Both modes additionally check what the merged manifest declares - permissions
and components, including everything a dependency contributed - against the set
ADR-054 recorded.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --beta) mode="beta"; shift ;;
    --production) mode="production"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) apk_path="$1"; shift ;;
  esac
done

[[ -n "$mode" ]] || { usage >&2; fail "Choose --beta or --production."; }
[[ -n "$apk_path" ]] || { usage >&2; fail "No APK given."; }
[[ -f "$apk_path" ]] || fail "APK not found: $apk_path"

readonly native_apk_path="$(to_native_path "$apk_path")"
checks_passed=0

pass() {
  checks_passed=$((checks_passed + 1))
  echo "  ok    $*"
}

echo "Verifying $(basename "$apk_path") as $mode"
echo

# --- Application identity ----------------------------------------------------

badging="$(aapt2 dump badging "$native_apk_path")"
actual_application_id="$(printf '%s' "$badging" |
  sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)"
version_code="$(printf '%s' "$badging" |
  sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" | head -n 1)"
version_name="$(printf '%s' "$badging" |
  sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -n 1)"

if [[ "$mode" == "beta" ]]; then
  expected_application_id="$beta_application_id"
else
  # Production is the Beta ID with the trailing environment segment removed.
  expected_application_id="${beta_application_id%.beta}"
fi

[[ "$actual_application_id" == "$expected_application_id" ]] ||
  fail "Application ID is '$actual_application_id' but must be '$expected_application_id'.
       An artifact with the wrong application ID is a different application to
       Android and cannot update an existing install."
pass "application ID $actual_application_id"
pass "version $version_name ($version_code)"

# --- Signature ---------------------------------------------------------------

signature_report=""
if signature_report="$(apksigner verify --verbose --print-certs "$native_apk_path" 2>&1)"; then
  signature_verified=1
else
  signature_verified=0
fi

scheme_state() {
  printf '%s' "$signature_report" |
    sed -n "s/^Verified using $1 scheme ([^)]*): \(.*\)$/\1/p" | head -n 1 | tr -d '\r'
}

if [[ "$mode" == "production" ]]; then
  # Production must stay undistributable. An unsigned APK is refused by the
  # package installer, which is exactly the fail-closed property we want.
  [[ "$signature_verified" -eq 0 ]] ||
    fail "The Production artifact is signed. Production must remain unsigned so it
         cannot be installed or distributed. Check that buildTypes.release does
         not set a signingConfig and that no signing config reached the
         production flavor."
  pass "unsigned, so the OS cannot install it"
else
  [[ "$signature_verified" -eq 1 ]] ||
    fail "apksigner could not verify the artifact:
$signature_report"
  pass "apksigner verifies the signature"

  signer_count="$(printf '%s' "$signature_report" |
    sed -n 's/^Number of signers: \(.*\)$/\1/p' | head -n 1 | tr -d '\r')"
  [[ "$signer_count" == "1" ]] ||
    fail "Expected exactly one signer, found '$signer_count'."
  pass "exactly one signer"

  v1_state="$(scheme_state v1)"
  v2_state="$(scheme_state v2)"
  v3_state="$(scheme_state v3)"
  [[ "$v2_state" == "true" ]] || fail "APK Signature Scheme v2 is not present."
  [[ "$v3_state" == "true" ]] || fail "APK Signature Scheme v3 is not present."
  [[ "$v1_state" == "false" ]] ||
    fail "The legacy JAR (v1) signature is present. minSdk 24 makes it unnecessary;
         it was disabled deliberately."
  pass "signed with v2 and v3, without the legacy v1 scheme"

  signer_dn="$(printf '%s' "$signature_report" |
    sed -n 's/^Signer #1 certificate DN: \(.*\)$/\1/p' | head -n 1 | tr -d '\r')"
  case "$signer_dn" in
    *"Android Debug"*)
      fail "This artifact is DEBUG SIGNED ($signer_dn). A debug-signed build must
           never reach a beta user: the debug key is regenerated per machine, so
           the next release could not update it."
      ;;
  esac
  pass "not debug signed"

  actual_fingerprint="$(normalize_fingerprint "$(printf '%s' "$signature_report" |
    sed -n 's/^Signer #1 certificate SHA-256 digest: \(.*\)$/\1/p' | head -n 1)")"

  if [[ -z "$beta_certificate_sha256" ]]; then
    fail "No expected certificate is recorded in
       android/beta-release-identity.properties, so this artifact's identity
       cannot be checked against anything. This artifact signs as:
         $actual_fingerprint
       If this is the very first Beta identity, record that value there and
       commit it. Never release an artifact whose identity is unverified."
  fi

  [[ "$actual_fingerprint" == "$beta_certificate_sha256" ]] ||
    fail "SIGNING IDENTITY MISMATCH.
         expected $beta_certificate_sha256
         actual   $actual_fingerprint
       This artifact is signed by a different key than the released Beta. Android
       will refuse to install it over an existing install, and the only way to
       apply it would be an uninstall that permanently destroys every beta
       user's local data. Do not distribute it. Find the real keystore."
  pass "signed by the frozen Beta identity $actual_fingerprint"
fi

# --- What the artifact declares, including what came from outside ----------

# The source manifest is not the artifact's manifest. Every dependency merges
# its own elements in, and the only place the result can be read is the packaged
# file. ADR-054 enumerated what belongs there; this refuses anything else, so a
# permission, a component or an exported entry point that arrives with a future
# dependency upgrade fails the release rather than shipping unnoticed.

expected_permissions="$(printf '%s\n' \
  "android.permission.ACCESS_NETWORK_STATE" \
  "android.permission.FOREGROUND_SERVICE" \
  "android.permission.FOREGROUND_SERVICE_SPECIAL_USE" \
  "android.permission.INTERNET" \
  "android.permission.POST_NOTIFICATIONS" \
  "android.permission.RECEIVE_BOOT_COMPLETED" \
  "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" \
  "android.permission.VIBRATE" \
  "$actual_application_id.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" |
  sort)"

actual_permissions="$(printf '%s' "$badging" |
  sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" | sort)"

if [[ "$actual_permissions" != "$expected_permissions" ]]; then
  fail "The packaged artifact does not ask for the permissions ADR-054 recorded.
$(diff <(printf '%s\n' "$expected_permissions") <(printf '%s\n' "$actual_permissions") |
    sed 's/^</       expected only: /; s/^>/       present but unrecorded: /' | grep -E 'expected only|unrecorded')
       A permission that arrived from a dependency is still a permission this
       application asks its users for. Read where it came from, decide it, and
       record it in the manifest and in ADR-054 - or remove what brought it."
fi
pass "declares exactly the $(printf '%s\n' "$actual_permissions" | wc -l | tr -d ' ') recorded permissions"

manifest_tree="$(aapt2 dump xmltree "$native_apk_path" --file AndroidManifest.xml)"

# One line per declared component: "type|name|exported". Attributes always
# precede nested elements in an aapt2 tree, so the next element boundary is
# where the previous component is complete.
components="$(printf '%s' "$manifest_tree" | awk '
  function flush() {
    if (type != "") { printf "%s|%s|%s\n", type, name, exported }
    type = ""
  }
  /^[[:space:]]*E: / {
    flush()
    if ($0 ~ /E: (activity|activity-alias|service|receiver|provider) \(line=/) {
      match($0, /E: [a-z-]+/)
      type = substr($0, RSTART + 3, RLENGTH - 3)
      name = "(unnamed)"
      exported = "unset"
    }
    next
  }
  type != "" && /android:name\(0x01010003\)=/ {
    if (name == "(unnamed)") { match($0, /="[^"]*"/); name = substr($0, RSTART + 2, RLENGTH - 3) }
  }
  type != "" && /android:exported\(0x01010010\)=/ {
    match($0, /=(true|false)/); exported = substr($0, RSTART + 1, RLENGTH - 1)
  }
  END { flush() }
' | sort)"

expected_components="$(printf '%s\n' \
  "activity|com.example.communication_platform.MainActivity|true" \
  "provider|androidx.core.content.FileProvider|false" \
  "provider|androidx.startup.InitializationProvider|false" \
  "service|com.example.communication_platform.DeferredDeliveryJobService|false" \
  "service|com.example.communication_platform.SustainedDeliveryService|false" |
  sort)"

if [[ "$components" != "$expected_components" ]]; then
  fail "The packaged artifact does not declare the components ADR-054 recorded.
$(diff <(printf '%s\n' "$expected_components") <(printf '%s\n' "$components") |
    sed 's/^</       expected only: /; s/^>/       present but unrecorded: /' | grep -E 'expected only|unrecorded')
       An entry point this project did not declare is reachable in the
       artifact. androidx.profileinstaller's exported ProfileInstallReceiver is
       the one this happened with before, and it is refused in the manifest
       with tools:node=\"remove\"."
fi
pass "declares exactly the 5 recorded components"

exported_components="$(printf '%s\n' "$components" | awk -F'|' '$3 == "true" { print $2 }')"
[[ "$exported_components" == "com.example.communication_platform.MainActivity" ]] ||
  fail "Exported components are '$exported_components'. Exactly one component may
       be exported - the launcher activity - because everything else in this
       artifact is started by this application or by the platform binding to it."
pass "one exported component, the launcher activity"

# --- Native trust, read out of the packaged artifact -------------------------

# This resource governs the platform's Java HTTP stacks and WebView. It does NOT
# govern dart:io, which is what this app's REST and WebSocket traffic runs on -
# that trust is installed in Dart from the provisioned authority instead, and is
# covered by test/features/networking/transport_security_test.dart. These checks
# therefore confirm the declarative Android configuration is correct and
# consistent with provisioning; they are not evidence that the app's own traffic
# is pinned.
if [[ "$mode" == "beta" ]]; then
  # Resource file names are obfuscated in a release build, so resolve the real
  # path through the resource table rather than guessing it.
  trust_resource="$(aapt2 dump resources "$native_apk_path" 2>/dev/null |
    grep -A1 'xml/network_security_config' |
    sed -n 's/.*(file) \(res\/[^ ]*\.xml\).*/\1/p' | head -n 1)"
  [[ -n "$trust_resource" ]] ||
    fail "The artifact has no network_security_config resource, so Android would
         apply its platform default and pin nothing."

  trust_tree="$(aapt2 dump xmltree "$native_apk_path" --file "$trust_resource" 2>&1)"

  printf '%s' "$trust_tree" | grep -q 'domain-config' ||
    fail "The packaged trust config has no domain-config, so this artifact trusts
         the system CA store and pins nothing. Run tool/render_beta_trust.sh."

  expected_host="${BETA_SERVER_ORIGIN:-}"
  expected_host="${expected_host#https://}"
  expected_host="${expected_host%%/*}"
  expected_host="${expected_host%%:*}"
  if [[ -n "$expected_host" ]]; then
    # aapt2 renders the domain as a quoted text node. Match the quotes too, so a
    # superstring such as evil-chat.example.com cannot satisfy the check.
    printf '%s' "$trust_tree" | grep -qF "'$expected_host'" ||
      fail "The packaged trust config does not pin $expected_host."
    pass "declared Android trust config pins $expected_host"
  else
    pass "packaged trust config carries a domain-config"
  fi

  pin_count="$(printf '%s' "$trust_tree" | grep -c 'digest="SHA-256"' || true)"
  [[ "$pin_count" -ge 2 ]] ||
    fail "The packaged trust config carries $pin_count pin(s); a primary and a
         backup are both required, or rotating the server key locks every
         client out."
  pass "declared Android trust config carries $pin_count SPKI pins"

  for pin_name in BETA_PRIMARY_SPKI_SHA256 BETA_BACKUP_SPKI_SHA256; do
    pin_value="${!pin_name:-}"
    [[ -n "$pin_value" ]] || continue
    printf '%s' "$trust_tree" | grep -qF "$pin_value" ||
      fail "$pin_name is not present in the packaged trust config, so the
           artifact pins something other than what was provisioned."
  done

  printf '%s' "$trust_tree" | grep -q 'cleartextTrafficPermitted=false' ||
    fail "The packaged trust config does not disable cleartext traffic."
  pass "declared Android trust config disables cleartext traffic"

  # The packaged file name is obfuscated in a release build, so the resource
  # table is the only reliable place to look for the trust anchor.
  aapt2 dump resources "$native_apk_path" 2>/dev/null |
    grep -q 'raw/provisioned_private_ca' ||
    fail "The provisioned private CA is not packaged, so the pinned domain has
         no trust anchor and every connection to it would fail."
  pass "provisioned private CA is packaged as a trust anchor"
fi

# --- Beta/Production native separation ---------------------------------------

[[ -n "$llvm_nm_tool" ]] ||
  fail "llvm-nm from Android NDK $RELEASE_NDK_VERSION is required to prove
       Beta/Production native separation. Set ANDROID_NDK_HOME."

readonly beta_symbol="cp_crypto_v1_beta_mls_operation"
readonly native_library="lib/arm64-v8a/libcommunication_crypto_core.so"

extracted="$(mktemp -d)"
trap 'rm -rf "$extracted"' EXIT INT TERM
unzip -p "$apk_path" "$native_library" > "$extracted/core.so" 2>/dev/null ||
  fail "$native_library is missing from the artifact."
[[ -s "$extracted/core.so" ]] || fail "$native_library is empty in the artifact."

exported_symbols="$("$llvm_nm_tool" -D --defined-only "$(to_native_path "$extracted/core.so")" |
  awk '{print $NF}')"

if [[ "$mode" == "beta" ]]; then
  printf '%s\n' "$exported_symbols" | grep -qx "$beta_symbol" ||
    fail "The packaged native core does not export $beta_symbol, so this artifact
         does not actually contain the Beta MLS core."
  pass "packaged native core exports $beta_symbol"
else
  if printf '%s\n' "$exported_symbols" | grep -qx "$beta_symbol"; then
    fail "The Production artifact's packaged native core exports $beta_symbol.
         Production must be provably unable to execute the Beta MLS
         implementation. Do not ship or accept this build."
  fi
  pass "packaged native core does not export $beta_symbol"
fi

echo
echo "$checks_passed checks passed."
