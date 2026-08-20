#!/usr/bin/env bash
# Render the Beta flavor's Android trust resources from the provisioning values.
#
# Android performs certificate-chain trust and the SPKI pin match natively, from
# a resource compiled into the APK. Dart carries the same values but cannot
# enforce them, so without these resources a Beta build trusts the system CA
# store and pins nothing - while still looking correctly provisioned.
#
# The rendered files are provisioning artifacts, not source: they are ignored by
# Git, exactly as android/provisioning/README.md requires for the other flavors.
# tool/build_beta_release.sh runs this on every release build, so the compiled
# trust can never drift from the values compiled into Dart.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/release_env.sh"

readonly template="$android_root/provisioning/network_security_config.xml.template"
readonly beta_res="$android_root/app/src/beta/res"
readonly rendered_config="$beta_res/xml/network_security_config.xml"
readonly rendered_ca="$beta_res/raw/provisioned_private_ca.pem"

usage() {
  cat <<'USAGE'
Usage: tool/render_beta_trust.sh

Required environment:
  BETA_SERVER_ORIGIN        https origin whose host is pinned
  BETA_PRIVATE_CA_SHA256    expected SHA-256 of the CA certificate, 64 hex chars
  BETA_PRIMARY_SPKI_SHA256  base64 SHA-256 SPKI pin
  BETA_BACKUP_SPKI_SHA256   base64 SHA-256 SPKI pin, different from the primary
  BETA_PRIVATE_CA_PEM       path to the private CA certificate in PEM form
USAGE
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }

missing=()
for name in BETA_SERVER_ORIGIN BETA_PRIVATE_CA_SHA256 BETA_PRIMARY_SPKI_SHA256 \
  BETA_BACKUP_SPKI_SHA256 BETA_PRIVATE_CA_PEM; do
  [[ -n "${!name:-}" ]] || missing+=("$name")
done
[[ "${#missing[@]}" -eq 0 ]] || { usage >&2; fail "Missing: ${missing[*]}"; }

[[ -f "$template" ]] || fail "Missing trust template: $template"
[[ -f "$BETA_PRIVATE_CA_PEM" ]] || fail "CA certificate not found: $BETA_PRIVATE_CA_PEM"

# --- The CA must be the one the provisioning values describe --------------------

actual_ca_sha256="$(openssl x509 -in "$BETA_PRIVATE_CA_PEM" -outform DER |
  openssl dgst -sha256 | sed 's/^.*= *//' | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')"
expected_ca_sha256="$(printf '%s' "$BETA_PRIVATE_CA_SHA256" | tr '[:upper:]' '[:lower:]')"

[[ "$actual_ca_sha256" == "$expected_ca_sha256" ]] ||
  fail "The CA certificate does not match BETA_PRIVATE_CA_SHA256.
         expected $expected_ca_sha256
         actual   $actual_ca_sha256
       Pinning the wrong root would either break every connection or trust the
       wrong issuer. Resolve which CA is actually deployed before building."

openssl x509 -in "$BETA_PRIVATE_CA_PEM" -noout -checkend 0 >/dev/null 2>&1 ||
  fail "The CA certificate has expired."

# --- Host --------------------------------------------------------------------

# The template pins one exact host, so strip scheme, any port, and any path.
server_host="${BETA_SERVER_ORIGIN#https://}"
server_host="${server_host%%/*}"
server_host="${server_host%%:*}"
[[ -n "$server_host" ]] || fail "Could not read a host from BETA_SERVER_ORIGIN."

[[ "$BETA_PRIMARY_SPKI_SHA256" != "$BETA_BACKUP_SPKI_SHA256" ]] ||
  fail "The primary and backup pins are identical, so pin rotation is impossible."

# --- Render ------------------------------------------------------------------

mkdir -p "$beta_res/xml" "$beta_res/raw"

# `sed` would need every value escaped; awk substitutes literal strings.
awk -v host="$server_host" \
  -v primary="$BETA_PRIMARY_SPKI_SHA256" \
  -v backup="$BETA_BACKUP_SPKI_SHA256" '
  {
    sub(/@@SERVER_HOST@@/, host)
    sub(/@@PRIMARY_SPKI_SHA256@@/, primary)
    sub(/@@BACKUP_SPKI_SHA256@@/, backup)
    print
  }
' "$template" > "$rendered_config"

grep -q '@@' "$rendered_config" &&
  fail "The rendered trust config still contains an unsubstituted placeholder."

cp "$BETA_PRIVATE_CA_PEM" "$rendered_ca"

echo "Rendered Beta trust resources:"
echo "  $rendered_config"
echo "    host          $server_host"
echo "    primary pin   $BETA_PRIMARY_SPKI_SHA256"
echo "    backup pin    $BETA_BACKUP_SPKI_SHA256"
echo "  $rendered_ca"
echo "    CA SHA-256    $actual_ca_sha256"
