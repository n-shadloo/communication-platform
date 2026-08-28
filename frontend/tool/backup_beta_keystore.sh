#!/usr/bin/env bash
# Produce an encrypted, self-describing backup of the Beta signing identity.
#
# The backup is a GnuPG AES-256 symmetric blob, so restoring it needs only gpg
# and the backup passphrase - no key server, no account, no vendor. Run it once
# per storage location, and verify a restore at least once a year.

set -euo pipefail
set +x

source "$(dirname "${BASH_SOURCE[0]}")/release_env.sh"

readonly default_material_root="${CP_BETA_MATERIAL_ROOT:-$HOME/.communication-platform/beta-signing}"
keystore_path="${CP_BETA_KEYSTORE_FILE:-$default_material_root/communication-platform-beta.p12}"
output_directory="."

usage() {
  cat <<'USAGE'
Usage: tool/backup_beta_keystore.sh [options]

  --keystore PATH   Keystore to back up.
  --out DIR         Directory to write the encrypted backup into (default: .).
  -h, --help        Show this message.

Writes <name>.tar.gz.gpg, its .sha256, and an unencrypted .txt label that
identifies the backup without revealing anything secret.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keystore) keystore_path="$2"; shift 2 ;;
    --out) output_directory="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; fail "Unknown argument: $1" ;;
  esac
done

command -v gpg >/dev/null 2>&1 || fail "gpg is required to encrypt the backup."
[[ -f "$keystore_path" ]] || fail "Keystore not found: $keystore_path"
[[ -n "$beta_certificate_sha256" ]] ||
  fail "No certificate fingerprint recorded in android/beta-release-identity.properties.
       Back up an identity only after it has been recorded there."

readonly stamp="$(date -u +%Y%m%dT%H%M%SZ)"
readonly backup_name="communication-platform-beta-signing-$stamp"
mkdir -p "$output_directory"
readonly archive_path="$output_directory/$backup_name.tar.gz.gpg"
[[ -e "$archive_path" ]] && fail "$archive_path already exists."

staging="$(mktemp -d)"
# The staging directory holds the private key in the clear; remove it whatever
# happens, including on interrupt.
cleanup() { rm -rf "$staging"; }
trap cleanup EXIT INT TERM

readonly payload="$staging/$backup_name"
mkdir -p "$payload"
cp "$keystore_path" "$payload/$(basename "$keystore_path")"

# A restore card travels inside the encrypted blob so whoever opens it in five
# years knows exactly what it is and what to do with it.
cat > "$payload/RESTORE.txt" <<CARD
Communication Platform - Private Experimental Beta signing identity
Created (UTC):        $stamp
Application ID:       $beta_application_id
Key alias:            communication-platform-beta
Certificate SHA-256:  $beta_certificate_sha256
Keystore file:        $(basename "$keystore_path")
Keystore format:      PKCS12

WHAT THIS IS
  The only signing key that can publish an update to an installed Private
  Experimental Beta build. Without it, existing installs can never be updated
  again, and users would have to uninstall - which erases all app data,
  including the encrypted database and the envelope holding its key. Backup is
  disabled in the manifest and the database key has no exportable copy, so that
  loss is permanent.

TO RESTORE
  1. gpg --output $backup_name.tar.gz --decrypt $backup_name.tar.gz.gpg
  2. tar -xzf $backup_name.tar.gz
  3. Put the keystore somewhere private, then create a signing properties file:
       storeFile=<path to the keystore>
       storePassword=<keystore passphrase>
       keyAlias=communication-platform-beta
       keyPassword=<keystore passphrase>
  4. export CP_BETA_SIGNING_PROPERTIES=<path to that file>
  5. Confirm the identity matches before releasing anything:
       frontend/tool/verify_release_apk.sh --beta <a previously released apk>
     The certificate SHA-256 it reports must equal the value above.

THE KEYSTORE PASSPHRASE IS NOT IN THIS ARCHIVE.
  It is held separately on purpose. Without it this file is useless.
CARD

tar -czf "$staging/$backup_name.tar.gz" -C "$staging" "$backup_name"

echo "Choose a passphrase for the backup archive."
echo "It may differ from the keystore passphrase; if it does, record both."
gpg --symmetric \
  --cipher-algo AES256 \
  --digest-algo SHA512 \
  --s2k-mode 3 \
  --s2k-count 65011712 \
  --output "$archive_path" \
  "$staging/$backup_name.tar.gz"

(cd "$output_directory" && sha256sum "$backup_name.tar.gz.gpg" > "$backup_name.tar.gz.gpg.sha256")

# Public label so a maintainer can identify a backup medium without decrypting.
cat > "$output_directory/$backup_name.txt" <<LABEL
Communication Platform - Private Experimental Beta signing identity backup
Created (UTC):        $stamp
Application ID:       $beta_application_id
Certificate SHA-256:  $beta_certificate_sha256
Encrypted archive:    $backup_name.tar.gz.gpg
Archive SHA-256:      $(cut -d' ' -f1 < "$output_directory/$backup_name.tar.gz.gpg.sha256")
Contains no secret. The archive needs its own passphrase; the keystore inside
needs the keystore passphrase.
LABEL

cat <<SUMMARY

Encrypted backup written.

  $archive_path
  $archive_path.sha256
  $output_directory/$backup_name.txt

Now copy the .gpg and .sha256 to a storage location that is not this machine,
and record the backup passphrase separately from the archive itself.
A backup that lives only on the machine that holds the original is not a backup.
SUMMARY
