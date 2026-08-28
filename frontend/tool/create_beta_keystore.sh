#!/usr/bin/env bash
# Create the one persistent Private Experimental Beta signing identity.
#
# Run this exactly once, ever. The key this produces is the only key that can
# update any Beta install it reaches. Replacing it later forces every beta user
# through an uninstall, and this app's local state cannot survive one.
#
# Nothing here writes a password to a command line, to the terminal, or to the
# repository.

set -euo pipefail
# Defence in depth: a shell trace would print the passphrase.
set +x

source "$(dirname "${BASH_SOURCE[0]}")/release_env.sh"

readonly default_material_root="${CP_BETA_MATERIAL_ROOT:-$HOME/.communication-platform/beta-signing}"
keystore_path="${CP_BETA_KEYSTORE_FILE:-$default_material_root/communication-platform-beta.p12}"
properties_path="${CP_BETA_SIGNING_PROPERTIES:-$default_material_root/beta-signing.properties}"
key_alias="communication-platform-beta"

usage() {
  cat <<'USAGE'
Usage: tool/create_beta_keystore.sh [options]

  --keystore PATH     Where to write the keystore (default: outside the repository,
                      under ~/.communication-platform/beta-signing).
  --properties PATH   Where to write the untracked signing properties file.
  --alias NAME        Key alias (default: communication-platform-beta).
  -h, --help          Show this message.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keystore) keystore_path="$2"; shift 2 ;;
    --properties) properties_path="$2"; shift 2 ;;
    --alias) key_alias="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; fail "Unknown argument: $1" ;;
  esac
done

# --- Refuse to create a second identity --------------------------------------

if [[ -e "$keystore_path" ]]; then
  fail "$keystore_path already exists. Never overwrite a Beta keystore: doing so
       destroys the only key that can update existing installs. If you believe a
       new identity is genuinely required, read the 'Losing the signing key'
       section of docs/release-signing.md first."
fi

if [[ -n "$beta_certificate_sha256" ]]; then
  fail "A Beta signing identity is already recorded in
       android/beta-release-identity.properties:
         $beta_certificate_sha256
       Creating a second key would orphan every existing install. Restore the
       existing keystore from backup instead; see docs/release-signing.md."
fi

# --- Passphrase --------------------------------------------------------------

echo "Creating the persistent Beta signing identity."
echo "Application ID (frozen): $beta_application_id"
echo
echo "Choose a passphrase of at least 16 characters and store it in your password"
echo "manager before continuing. If the passphrase is lost the key is lost."
echo

read -r -s -p "Passphrase: " passphrase
echo
read -r -s -p "Confirm passphrase: " passphrase_confirmation
echo

[[ "$passphrase" == "$passphrase_confirmation" ]] || fail "Passphrases do not match."
[[ "${#passphrase}" -ge 16 ]] || fail "Passphrase must be at least 16 characters."
unset passphrase_confirmation

# keytool reads these from the environment, so they never appear in the process
# list where any local user could read them.
export CP_KEYSTORE_PASSPHRASE="$passphrase"
unset passphrase

# --- Generate ----------------------------------------------------------------

mkdir -p "$(dirname "$keystore_path")"
chmod 700 "$(dirname "$keystore_path")" 2>/dev/null || true

# 10000 days is a little over 27 years, comfortably past Android's guidance that
# a signing key outlive the app. PKCS12 is the current standard keystore format;
# the proprietary JKS format is deprecated.
keytool -genkeypair \
  -alias "$key_alias" \
  -keyalg RSA \
  -keysize 4096 \
  -sigalg SHA384withRSA \
  -validity 10000 \
  -storetype PKCS12 \
  -keystore "$(to_native_path "$keystore_path")" \
  -dname "CN=$beta_application_id, OU=Private Experimental Beta, O=Communication Platform" \
  -storepass:env CP_KEYSTORE_PASSPHRASE \
  -keypass:env CP_KEYSTORE_PASSPHRASE

chmod 600 "$keystore_path" 2>/dev/null || true

# --- Record the public identity ----------------------------------------------

fingerprint="$(normalize_fingerprint "$(
  keytool -list -v \
    -alias "$key_alias" \
    -keystore "$(to_native_path "$keystore_path")" \
    -storepass:env CP_KEYSTORE_PASSPHRASE |
    sed -n 's/^[[:space:]]*SHA256:[[:space:]]*\(.*\)$/\1/p' | head -n 1
)")"

[[ "${#fingerprint}" -eq 64 ]] || fail "Could not read the certificate SHA-256 digest."

# The fingerprint is public. Recording it in source control is what lets every
# later build prove it used the same identity.
tmp_identity="$(mktemp)"
sed "s/^signing\.certificate\.sha256=.*$/signing.certificate.sha256=$fingerprint/" \
  "$release_identity_file" > "$tmp_identity"
mv "$tmp_identity" "$release_identity_file"

# --- Untracked signing properties --------------------------------------------

mkdir -p "$(dirname "$properties_path")"
umask 077
cat > "$properties_path" <<PROPERTIES
# Private Beta signing material. NEVER commit this file.
# Consumed by android/app/build.gradle.kts via CP_BETA_SIGNING_PROPERTIES.
storeFile=$(to_properties_path "$keystore_path")
storePassword=$CP_KEYSTORE_PASSPHRASE
keyAlias=$key_alias
keyPassword=$CP_KEYSTORE_PASSPHRASE
PROPERTIES
chmod 600 "$properties_path" 2>/dev/null || true
unset CP_KEYSTORE_PASSPHRASE

cat <<SUMMARY

Beta signing identity created.

  Keystore     $keystore_path
  Alias        $key_alias
  Properties   $properties_path
  Certificate  $fingerprint

The fingerprint has been written to android/beta-release-identity.properties.
Commit that change: it is public, and every later release is verified against it.

Point builds at the material with:

  export CP_BETA_SIGNING_PROPERTIES="$properties_path"

Do these now, before the first release build:

  1. Store the passphrase in your password manager.
  2. Make at least two encrypted offline backups:
       tool/backup_beta_keystore.sh --keystore "$keystore_path"
     and copy the result to two separate physical locations.
  3. Read docs/release-signing.md, in particular 'Losing the signing key'.

SUMMARY
