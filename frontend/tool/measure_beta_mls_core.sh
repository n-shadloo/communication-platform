#!/usr/bin/env bash
# Runs the closed-beta PQ MLS core's own test suite on a connected Android
# device, and writes the run record that `GroupExperimentalGate` reads.
#
# ## Why this exists
#
# `cp_crypto_v1_beta_mls_operation` is the one part of this application that has
# never executed on the architecture it ships to. It is also the only part whose
# native profile links `aws-lc-sys` — C and assembly, cross-compiled per ABI —
# under `mls-rs`. Everything above it is evidenced by host tests; whether the
# arithmetic is right on an ARM phone is evidenced by nothing (ADR-055).
#
# ## What it does, and what it deliberately does not
#
# It cross-compiles the crate's **own** `--features beta-pq-mls` test binary for
# one Android ABI, pushes that binary to the device, and runs it there. The code
# under test is the code that ships, built by the same toolchain, at the same
# pins. Nothing is added to the application to make this observable and nothing
# has to be removed afterwards, which is the same rule
# `tool/measure_sustained_delivery.sh` follows.
#
# It does not install the APK, does not touch a backend, does not need an
# account, and does not need root. It answers exactly one question — does this
# library compute correctly on this CPU — and leaves the multi-device,
# live-backend half of piece 19 where it is.
#
# ## Usage
#
#   tool/measure_beta_mls_core.sh <abi> [serial]
#
#   abi     arm64-v8a | armeabi-v7a | x86_64
#   serial  adb device serial; required when more than one device is attached
#
# A run that passes prints the record path. Transcribe its fields into
# `GroupExperimentalGate.ledger` in
# `lib/app/config/group_production_gate.dart` to open that cell. A record with
# "emulated": true can be committed and will never open anything — the gate's
# admissibility rule refuses it, because an emulator on an x86 host does not run
# the ARM assembly this measurement is about.
set -euo pipefail

readonly RUST_VERSION="1.97.1"
readonly NDK_VERSION="28.2.13676358"
readonly ANDROID_API="24"
readonly SCHEMA="beta-mls-core-run/1"
readonly DEVICE_DIR="/data/local/tmp/cp-beta-mls"

requested_abi="${1:-}"
device_serial="${2:-}"

case "$requested_abi" in
  arm64-v8a)
    rust_target="aarch64-linux-android"
    clang_wrapper="aarch64-linux-android$ANDROID_API-clang"
    ;;
  armeabi-v7a)
    rust_target="armv7-linux-androideabi"
    clang_wrapper="armv7a-linux-androideabi$ANDROID_API-clang"
    ;;
  x86_64)
    rust_target="x86_64-linux-android"
    clang_wrapper="x86_64-linux-android$ANDROID_API-clang"
    ;;
  *)
    echo "Usage: $0 <arm64-v8a|armeabi-v7a|x86_64> [adb-serial]" >&2
    exit 2
    ;;
esac
readonly requested_abi rust_target clang_wrapper

frontend_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly frontend_root
readonly manifest="$frontend_root/native/crypto_core/Cargo.toml"
readonly build_root="$frontend_root/build/rust-android/beta-mls-measurement"
readonly cargo_target_dir="$build_root/cargo-target"
readonly sodium_root="$frontend_root/build/rust-android/libsodium"
readonly records_root="$frontend_root/docs/validation/beta-mls-core"
readonly cargo_command="${CARGO:-cargo}"

host_kernel="$(uname -s)"
case "$host_kernel" in
  MINGW* | MSYS*)
    host_tag="windows-x86_64"
    executable_suffix=".exe"
    clang_wrapper_suffix=".cmd"
    to_tool_path() { cygpath -w "$1"; }
    to_clang_path() { cygpath -m "$1"; }
    ;;
  Linux*)
    host_tag="linux-x86_64"
    executable_suffix=""
    clang_wrapper_suffix=""
    to_tool_path() { printf '%s\n' "$1"; }
    to_clang_path() { printf '%s\n' "$1"; }
    ;;
  Darwin*)
    host_tag="darwin-x86_64"
    executable_suffix=""
    clang_wrapper_suffix=""
    to_tool_path() { printf '%s\n' "$1"; }
    to_clang_path() { printf '%s\n' "$1"; }
    ;;
  *)
    echo "Unsupported build host: $host_kernel" >&2
    exit 2
    ;;
esac
readonly host_tag executable_suffix clang_wrapper_suffix

adb_command="${ADB:-adb}"
if ! command -v "$adb_command" >/dev/null 2>&1; then
  if [[ -n "${LOCALAPPDATA:-}" && -x "$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" ]]; then
    adb_command="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
  else
    echo "adb is not on PATH; set ADB to its location." >&2
    exit 2
  fi
fi
readonly adb_command

# `MSYS_NO_PATHCONV` and `MSYS2_ARG_CONV_EXCL` are not decoration. On a Git Bash
# or MSYS2 host every argument that looks like an absolute POSIX path is
# rewritten to a Windows one before the process sees it, so
# `adb push … /data/local/tmp/x` silently becomes
# `C:/Program Files/Git/data/local/tmp/x` and fails with
# `remote secure_mkdirs() failed: No such file or directory`. Found by running
# this script against a real phone, which is the only way it could have been
# found. Both variables are inert on Linux and macOS.
adb() {
  if [[ -n "$device_serial" ]]; then
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
      "$adb_command" -s "$device_serial" "$@"
  else
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$adb_command" "$@"
  fi
}

attached="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }' | wc -l | tr -d '[:space:]')"
if [[ "$attached" == "0" ]]; then
  echo "No Android device is attached. This measurement cannot be simulated." >&2
  exit 3
fi
if [[ "$attached" != "1" && -z "$device_serial" ]]; then
  echo "More than one device is attached; pass the serial as the second argument." >&2
  exit 2
fi

ndk_root="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$ndk_root" && "$host_tag" == "windows-x86_64" ]]; then
  ndk_root="${LOCALAPPDATA:-}/Android/Sdk/ndk/$NDK_VERSION"
fi
if [[ -z "$ndk_root" ]]; then
  echo "ANDROID_NDK_HOME or ANDROID_NDK_ROOT must point to NDK $NDK_VERSION." >&2
  exit 2
fi
if [[ "$host_tag" == "windows-x86_64" ]]; then
  ndk_root="$(cygpath -u "$ndk_root")"
fi
readonly ndk_root
if [[ "$(basename "$ndk_root")" != "$NDK_VERSION" ]]; then
  echo "Expected Android NDK $NDK_VERSION, found: $ndk_root" >&2
  exit 2
fi

actual_rustc_version="$(rustc --version)"
case "$actual_rustc_version" in
  "rustc $RUST_VERSION "*) ;;
  *)
    echo "Expected Rust $RUST_VERSION, found: $actual_rustc_version" >&2
    exit 2
    ;;
esac

# The beta profile links libsodium exactly as the shipped library does; reusing
# the same cache key keeps the measured binary and the packaged one on one set
# of C dependencies rather than two.
bash "$frontend_root/tool/build_libsodium_android.sh" "$requested_abi"
libsodium_script_sha256="$(sha256sum "$frontend_root/tool/build_libsodium_android.sh" | awk '{print $1}')"
libsodium_archive_sha256="$(sha256sum "$frontend_root/native/crypto_core/vendor/libsodium/LATEST.tar.gz" | awk '{print $1}')"
readonly libsodium_cache_key="${libsodium_script_sha256:0:16}-${libsodium_archive_sha256:0:16}"

readonly toolchain="$ndk_root/toolchains/llvm/prebuilt/$host_tag"
cargo_target_key="$(printf '%s' "$rust_target" | tr '[:lower:]-' '[:upper:]_')"
cc_target_key="$(printf '%s' "$rust_target" | tr '-' '_')"
linker="$(to_tool_path "$toolchain/bin/$clang_wrapper$clang_wrapper_suffix")"
archiver="$(to_tool_path "$toolchain/bin/llvm-ar$executable_suffix")"
clang_target="${clang_wrapper%"$ANDROID_API-clang"}"
cxx_wrapper="$(to_tool_path "$toolchain/bin/${clang_wrapper}++$clang_wrapper_suffix")"
bindgen_args="--target=$clang_target --sysroot=$(to_clang_path "$toolchain/sysroot") -D__ANDROID_API__=$ANDROID_API"
sodium_lib_dir="$(to_tool_path "$sodium_root/$libsodium_cache_key/$requested_abi/install/lib")"

echo "Building the beta PQ MLS test binary for $requested_abi ..."
build_output="$(
  env \
    "CARGO_TARGET_${cargo_target_key}_LINKER=$linker" \
    "CC_${cc_target_key}=$linker" \
    "CXX_${cc_target_key}=$cxx_wrapper" \
    "AR_${cc_target_key}=$archiver" \
    "BINDGEN_EXTRA_CLANG_ARGS_${cc_target_key}=$bindgen_args" \
    "SODIUM_LIB_DIR=$sodium_lib_dir" \
    "ANDROID_NDK_ROOT=$(to_tool_path "$ndk_root")" \
    "ANDROID_NDK=$(to_tool_path "$ndk_root")" \
    "CMAKE_GENERATOR=Ninja" \
    "CARGO_TARGET_DIR=$(to_tool_path "$cargo_target_dir")" \
    "$cargo_command" test \
    --locked \
    --manifest-path "$(to_tool_path "$manifest")" \
    --target "$rust_target" \
    --features beta-pq-mls \
    --no-run \
    --message-format=json
)"

test_binary="$(
  printf '%s\n' "$build_output" |
    python -c '
import json
import sys

selected = None
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get("reason") != "compiler-artifact":
        continue
    if not record.get("profile", {}).get("test"):
        continue
    if "communication-crypto-core" not in record.get("package_id", ""):
        continue
    for path in record.get("filenames") or []:
        if path:
            selected = path
print(selected or "")
'
)"

if [[ -z "$test_binary" || ! -f "$test_binary" ]]; then
  echo "Could not locate the cross-compiled test binary." >&2
  exit 1
fi
readonly test_binary

# The device's own identity, read rather than assumed. `ro.kernel.qemu` and the
# Google/generic fingerprints are what distinguish an emulator, and the record
# carries the answer so the gate can refuse it without anyone having to
# remember.
prop() { adb shell getprop "$1" 2>/dev/null | tr -d '\r\n'; }
manufacturer="$(prop ro.product.manufacturer)"
model="$(prop ro.product.model)"
platform_release="$(prop ro.build.version.release)"
api_level="$(prop ro.build.version.sdk)"
build_type="$(prop ro.build.type)"
device_abi="$(prop ro.product.cpu.abi)"
qemu="$(prop ro.kernel.qemu)"
fingerprint="$(prop ro.build.fingerprint)"
emulated="false"
if [[ "$qemu" == "1" ]] || [[ "$fingerprint" == *"generic"* ]] || [[ "$fingerprint" == *"emulator"* ]]; then
  emulated="true"
fi

echo "Running on $manufacturer $model (Android $platform_release, API $api_level, $device_abi) ..."
# Never discard a setup step's output. `adb shell` folds the remote command's
# stderr into its stdout, so `>/dev/null` on these three lines silences the only
# diagnostic a device-side failure produces — which is how the path-conversion
# bug above presented as a bare non-zero exit and nothing else.
staged() {
  local description="$1"
  shift
  local output
  if ! output="$("$@" 2>&1)"; then
    echo "$description failed:" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  # adb exits 0 on some device-side failures, so the text is checked too.
  case "$output" in
    *"secure_mkdirs() failed"* | *"Permission denied"* | *"No such file"*)
      echo "$description reported a device-side failure:" >&2
      printf '%s\n' "$output" >&2
      exit 1
      ;;
  esac
}

staged "creating $DEVICE_DIR" adb shell "mkdir -p $DEVICE_DIR"
staged "pushing the test binary" \
  adb push "$test_binary" "$DEVICE_DIR/beta_mls_tests"
staged "marking the test binary executable" \
  adb shell "chmod 700 $DEVICE_DIR/beta_mls_tests"

set +e
run_output="$(adb shell "cd $DEVICE_DIR && ./beta_mls_tests --test-threads 1 2>&1; echo CP_EXIT=\$?")"
set -e
adb shell "rm -rf $DEVICE_DIR" >/dev/null || true

exit_code="$(printf '%s\n' "$run_output" | sed -n 's/.*CP_EXIT=\([0-9]*\).*/\1/p' | tail -1)"
summary="$(printf '%s\n' "$run_output" | grep -E '^test result:' | tail -1 || true)"
passed="$(printf '%s\n' "$summary" | sed -n 's/.*result: ok\. \([0-9]*\) passed.*/\1/p')"
failed="$(printf '%s\n' "$summary" | sed -n 's/.* \([0-9]*\) failed.*/\1/p')"

record_dir="$records_root/$(date -u +%Y-%m-%d)-$(printf '%s' "${model:-device}" | tr -c '[:alnum:]' '-' | tr '[:upper:]' '[:lower:]' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')-$requested_abi"
mkdir -p "$record_dir"
printf '%s\n' "$run_output" >"$record_dir/test-output.txt"

cat >"$record_dir/run.json" <<JSON
{
  "schema": "$SCHEMA",
  "recorded_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "abi": "$requested_abi",
  "rust_target": "$rust_target",
  "rust_version": "$RUST_VERSION",
  "ndk_version": "$NDK_VERSION",
  "manufacturer": "$manufacturer",
  "model": "$model",
  "platform_release": "$platform_release",
  "api_level": "$api_level",
  "build_type": "$build_type",
  "device_primary_abi": "$device_abi",
  "emulated": $emulated,
  "exit_code": ${exit_code:-null},
  "tests_passed": ${passed:-null},
  "tests_failed": ${failed:-null},
  "summary": "${summary:-absent}"
}
JSON

echo
echo "Run record: $record_dir/run.json"
if [[ "${exit_code:-1}" != "0" ]]; then
  echo "FAILED on device. The gate stays closed and this record says why." >&2
  exit 1
fi
if [[ "$emulated" == "true" ]]; then
  echo "Passed, but on an emulator. This can never open a cell; run it on a phone."
  exit 0
fi
echo "Passed on hardware. Transcribe this record into GroupExperimentalGate.ledger."
