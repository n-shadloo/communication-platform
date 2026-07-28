#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_ARCHIVE_SHA256="b20a92e7ec25b285eafa349d721a5bb27e3a8ba94c0816630a127883f1d1b3ab"
readonly NDK_VERSION="28.2.13676358"
readonly ANDROID_API="24"

frontend_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly frontend_root
readonly archive="$frontend_root/native/crypto_core/vendor/libsodium/LATEST.tar.gz"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
archive_sha256="$(sha256sum "$archive" | awk '{print $1}')"
readonly libsodium_cache_key="${script_sha256:0:16}-${archive_sha256:0:16}"
readonly build_root="$frontend_root/build/rust-android/libsodium/$libsodium_cache_key"
mkdir -p "$build_root"

host_kernel="$(uname -s)"
case "$host_kernel" in
  MINGW* | MSYS*)
    readonly host_tag="windows-x86_64"
    readonly executable_suffix=".exe"
    to_shell_path() { cygpath -u "$1"; }
    ;;
  Linux*)
    readonly host_tag="linux-x86_64"
    readonly executable_suffix=""
    to_shell_path() { printf '%s\n' "$1"; }
    ;;
  Darwin*)
    readonly host_tag="darwin-x86_64"
    readonly executable_suffix=""
    to_shell_path() { printf '%s\n' "$1"; }
    ;;
  *)
    echo "Unsupported build host: $host_kernel" >&2
    exit 2
    ;;
esac

ndk_root="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$ndk_root" && "$host_tag" == "windows-x86_64" ]]; then
  ndk_root="${LOCALAPPDATA:-}/Android/Sdk/ndk/$NDK_VERSION"
fi
if [[ -z "$ndk_root" ]]; then
  echo "ANDROID_NDK_HOME or ANDROID_NDK_ROOT must point to NDK $NDK_VERSION." >&2
  exit 2
fi
ndk_root="$(to_shell_path "$ndk_root")"
readonly ndk_root

if [[ "$(basename "$ndk_root")" != "$NDK_VERSION" ]]; then
  echo "Expected Android NDK $NDK_VERSION, found: $ndk_root" >&2
  exit 2
fi
if [[ ! -x "$ndk_root/toolchains/llvm/prebuilt/$host_tag/bin/clang$executable_suffix" ]]; then
  echo "Pinned Android NDK compiler is unavailable under: $ndk_root" >&2
  exit 2
fi

if [[ "$archive_sha256" != "$EXPECTED_ARCHIVE_SHA256" ]]; then
  echo "libsodium archive hash mismatch." >&2
  exit 3
fi

readonly toolchain="$ndk_root/toolchains/llvm/prebuilt/$host_tag"
readonly clang="$toolchain/bin/clang$executable_suffix"
readonly llvm_ar="$toolchain/bin/llvm-ar$executable_suffix"
readonly llvm_nm="$toolchain/bin/llvm-nm$executable_suffix"
readonly llvm_objdump="$toolchain/bin/llvm-objdump$executable_suffix"
readonly llvm_ranlib="$toolchain/bin/llvm-ranlib$executable_suffix"
readonly llvm_strip="$toolchain/bin/llvm-strip$executable_suffix"
if [[ "$host_tag" == "windows-x86_64" ]]; then
  readonly make_command="$ndk_root/prebuilt/windows-x86_64/bin/make.exe"
  readonly shell_command="$build_root/sh.exe"
  if [[ ! -f "$shell_command" ]]; then
    cp "$(command -v sh.exe)" "$shell_command"
  fi
else
  readonly make_command="make"
  readonly shell_command="/bin/sh"
fi

build_abi() {
  local abi="$1"
  local compiler_target="$2"
  local configure_host="$3"
  local architecture_flags="$4"
  local abi_root="$build_root/$abi"
  local source_parent="$abi_root/source"
  local source_root="$source_parent/libsodium-stable"
  local install_root="$abi_root/install"
  local static_library="$install_root/lib/libsodium.a"

  if [[ -f "$static_library" ]]; then
    return
  fi

  mkdir -p "$source_parent" "$install_root"
  if [[ ! -f "$source_root/configure" ]]; then
    tar -xzf "$archive" -C "$source_parent"
  fi

  (
    cd "$source_root"
    export SHELL="$shell_command"
    export CONFIG_SHELL="$shell_command"
    CC="$clang --target=$compiler_target" \
      AR="$llvm_ar" \
      NM="$llvm_nm" \
      OBJDUMP="$llvm_objdump" \
      RANLIB="$llvm_ranlib" \
      STRIP="$llvm_strip" \
      MAKE="$make_command" \
      CFLAGS="-fPIC -Os $architecture_flags" \
      LDFLAGS="-Wl,-z,max-page-size=16384" \
      ./configure \
        --disable-shared \
        --enable-static \
        --disable-soname-versions \
        --disable-pie \
        --enable-minimal \
        "--host=$configure_host" \
        "--prefix=$install_root" \
        "--with-sysroot=$toolchain/sysroot"
    "$make_command" "SHELL=$shell_command" -j"${CARGO_BUILD_JOBS:-4}" install
  )

  if [[ ! -f "$static_library" ]]; then
    echo "libsodium did not produce the expected library for $abi." >&2
    exit 4
  fi
}

requested_abi="${1:-all}"
case "$requested_abi" in
  all)
    build_abi "arm64-v8a" "aarch64-linux-android$ANDROID_API" \
      "aarch64-linux-android" "-march=armv8-a+crypto"
    build_abi "armeabi-v7a" "armv7a-linux-androideabi$ANDROID_API" \
      "arm-linux-androideabi" "-march=armv7-a -mthumb"
    build_abi "x86_64" "x86_64-linux-android$ANDROID_API" \
      "x86_64-linux-android" "-march=x86-64"
    ;;
  arm64-v8a)
    build_abi "$requested_abi" "aarch64-linux-android$ANDROID_API" \
      "aarch64-linux-android" "-march=armv8-a+crypto"
    ;;
  armeabi-v7a)
    build_abi "$requested_abi" "armv7a-linux-androideabi$ANDROID_API" \
      "arm-linux-androideabi" "-march=armv7-a -mthumb"
    ;;
  x86_64)
    build_abi "$requested_abi" "x86_64-linux-android$ANDROID_API" \
      "x86_64-linux-android" "-march=x86-64"
    ;;
  *)
    echo "Unsupported Android ABI: $requested_abi" >&2
    exit 2
    ;;
esac
