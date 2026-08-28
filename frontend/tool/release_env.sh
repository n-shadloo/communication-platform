#!/usr/bin/env bash
# Shared release-tooling environment for the Private Experimental Beta.
#
# Source this; do not execute it. It resolves the frozen release identity and
# the exact toolchain the signing and verification scripts need, and fails
# closed when anything required is missing. It never reads, prints, or stores a
# password.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "release_env.sh is a library; source it instead of running it." >&2
  exit 2
fi

set -euo pipefail

frontend_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly frontend_root
readonly android_root="$frontend_root/android"
readonly release_identity_file="$android_root/beta-release-identity.properties"

# The pinned NDK that tool/build_rust_android.sh already requires. Reused here
# only for llvm-nm, which proves Beta/Production native separation in the
# packaged artifact rather than only in the build tree.
readonly RELEASE_NDK_VERSION="28.2.13676358"

host_kernel="$(uname -s)"
case "$host_kernel" in
  MINGW* | MSYS*)
    readonly release_host_windows=1
    readonly release_exe_suffix=".exe"
    readonly release_bat_suffix=".bat"
    readonly release_ndk_host_tag="windows-x86_64"
    # Native Windows tools cannot read POSIX paths.
    to_native_path() { cygpath -w "$1"; }
    # Java treats /c/... as relative, so a path written into a properties file
    # needs a drive letter. Forward slashes, not backslashes: Properties.load()
    # reads a backslash as an escape character.
    to_properties_path() { cygpath -m "$1"; }
    ;;
  Linux*)
    readonly release_host_windows=0
    readonly release_exe_suffix=""
    readonly release_bat_suffix=""
    readonly release_ndk_host_tag="linux-x86_64"
    to_native_path() { printf '%s\n' "$1"; }
    to_properties_path() { printf '%s\n' "$1"; }
    ;;
  Darwin*)
    readonly release_host_windows=0
    readonly release_exe_suffix=""
    readonly release_bat_suffix=""
    readonly release_ndk_host_tag="darwin-x86_64"
    to_native_path() { printf '%s\n' "$1"; }
    to_properties_path() { printf '%s\n' "$1"; }
    ;;
  *)
    echo "Unsupported release host: $host_kernel" >&2
    exit 2
    ;;
esac

fail() {
  echo "error: $*" >&2
  exit 1
}

# --- Frozen release identity -------------------------------------------------

read_identity_property() {
  local key="$1"
  [[ -f "$release_identity_file" ]] ||
    fail "Missing $release_identity_file. The frozen Beta identity must be in source control."
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\(.*\)$/\1/p" "$release_identity_file" |
    tail -n 1 |
    tr -d '\r' |
    sed 's/[[:space:]]*$//'
}

# apksigner prints lower-case hex without separators; keytool prints upper-case
# colon-separated. Compare only after normalising both to the former.
normalize_fingerprint() {
  printf '%s' "$1" | tr -d ': \t\r\n' | tr '[:upper:]' '[:lower:]'
}

beta_application_id="$(read_identity_property 'application\.id')"
[[ -n "$beta_application_id" ]] ||
  fail "application.id is empty in $release_identity_file."
readonly beta_application_id

beta_certificate_sha256="$(normalize_fingerprint "$(read_identity_property 'signing\.certificate\.sha256')")"
readonly beta_certificate_sha256

# --- Android SDK -------------------------------------------------------------

resolve_android_sdk() {
  local candidate=""
  if [[ -f "$android_root/local.properties" ]]; then
    candidate="$(sed -n 's/^[[:space:]]*sdk\.dir[[:space:]]*=[[:space:]]*\(.*\)$/\1/p' \
      "$android_root/local.properties" | tail -n 1 | tr -d '\r')"
    # local.properties escapes Windows separators.
    candidate="${candidate//\\\\//}"
    candidate="${candidate//\\//}"
  fi
  if [[ -z "$candidate" ]]; then
    candidate="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  fi
  [[ -n "$candidate" ]] ||
    fail "Android SDK not found. Set ANDROID_SDK_ROOT or sdk.dir in android/local.properties."
  if [[ "$release_host_windows" == "1" && "$candidate" == ?:/* ]]; then
    candidate="$(cygpath -u "$candidate")"
  fi
  [[ -d "$candidate" ]] || fail "Android SDK directory does not exist: $candidate"
  printf '%s\n' "$candidate"
}

android_sdk_root="$(resolve_android_sdk)"
readonly android_sdk_root

# Highest installed build-tools that actually carries the tools we need.
resolve_build_tools() {
  local directory
  local version
  for directory in $(ls -1 "$android_sdk_root/build-tools" 2>/dev/null | sort -Vr); do
    version="$android_sdk_root/build-tools/$directory"
    if [[ -f "$version/apksigner$release_bat_suffix" && -f "$version/aapt2$release_exe_suffix" ]]; then
      printf '%s\n' "$version"
      return 0
    fi
  done
  fail "No Android build-tools with apksigner and aapt2 under $android_sdk_root/build-tools."
}

build_tools_root="$(resolve_build_tools)"
readonly build_tools_root
readonly apksigner_tool="$build_tools_root/apksigner$release_bat_suffix"
readonly aapt2_tool="$build_tools_root/aapt2$release_exe_suffix"
readonly adb_tool="$android_sdk_root/platform-tools/adb$release_exe_suffix"

apksigner() { "$apksigner_tool" "$@"; }
aapt2() { "$aapt2_tool" "$@"; }

# --- JDK ---------------------------------------------------------------------

# Gradle 9 and AGP 9 need a JDK 17 or newer, and the system `java` on a
# maintainer workstation is frequently older. Resolve one explicitly so the
# release path never depends on whatever happens to be first on PATH.
resolve_jdk_home() {
  local candidate
  local candidates=()
  [[ -n "${CP_RELEASE_JAVA_HOME:-}" ]] && candidates+=("$CP_RELEASE_JAVA_HOME")
  [[ -n "${JAVA_HOME:-}" ]] && candidates+=("$JAVA_HOME")
  if [[ "$release_host_windows" == "1" ]]; then
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(ls -d "/c/Program Files/Java"/jdk-* 2>/dev/null | sort -Vr)
  fi
  for candidate in "${candidates[@]:-}"; do
    [[ -n "$candidate" && -x "$candidate/bin/keytool$release_exe_suffix" ]] || continue
    local major
    major="$("$candidate/bin/java$release_exe_suffix" -version 2>&1 |
      sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n 1)"
    if [[ -n "$major" && "$major" -ge 17 ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  fail "No JDK 17 or newer found. Set CP_RELEASE_JAVA_HOME to one."
}

jdk_home="$(resolve_jdk_home)"
readonly jdk_home
readonly keytool_tool="$jdk_home/bin/keytool$release_exe_suffix"

keytool() { "$keytool_tool" "$@"; }

# --- Native symbol inspection ------------------------------------------------

resolve_llvm_nm() {
  local ndk_root="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
  if [[ -z "$ndk_root" ]]; then
    ndk_root="$android_sdk_root/ndk/$RELEASE_NDK_VERSION"
  fi
  if [[ "$release_host_windows" == "1" && "$ndk_root" == ?:/* ]]; then
    ndk_root="$(cygpath -u "$ndk_root")"
  fi
  local tool="$ndk_root/toolchains/llvm/prebuilt/$release_ndk_host_tag/bin/llvm-nm$release_exe_suffix"
  [[ -x "$tool" ]] || return 1
  printf '%s\n' "$tool"
}

llvm_nm_tool="$(resolve_llvm_nm || true)"
readonly llvm_nm_tool
