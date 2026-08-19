# ops/tls/make_ca.sh — private CA + server certificate for the network-shutdown
# posture (see ops/tls/README.md; this is what the nginx site is configured for).
#
# The root generated here is pre-distributed to client devices, and clients SPKI-pin
# the server key. Everything lands in ops/tls/out/, which is gitignored — the private
# keys must never be committed.
#
# Usage: DOMAIN=chat.example.internal bash ops/tls/make_ca.sh
set -euo pipefail

DOMAIN="${DOMAIN:-YOUR_DOMAIN}"
OUT="$(dirname "$0")/out"
CA_DAYS="${CA_DAYS:-3650}"
SERVER_DAYS="${SERVER_DAYS:-825}"

mkdir -p "$OUT"
umask 077

if [ ! -f "$OUT/ca.key" ]; then
  openssl req -x509 -newkey rsa:4096 -sha256 -days "$CA_DAYS" -nodes \
    -keyout "$OUT/ca.key" -out "$OUT/ca.crt" \
    -subj "/CN=chat private root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
  echo "Generated a new root CA. Keep ca.key offline; it is the trust anchor."
else
  echo "Reusing the existing root CA in $OUT."
fi

openssl req -newkey rsa:4096 -sha256 -nodes \
  -keyout "$OUT/server.key" -out "$OUT/server.csr" \
  -subj "/CN=$DOMAIN"

openssl x509 -req -in "$OUT/server.csr" -sha256 -days "$SERVER_DAYS" \
  -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" -CAcreateserial \
  -out "$OUT/server.crt" \
  -extfile <(printf 'subjectAltName=DNS:%s\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nbasicConstraints=critical,CA:FALSE\n' "$DOMAIN")

rm -f "$OUT/server.csr"

# Backup key: pin two SPKIs so rotating the server key cannot lock every client out.
if [ ! -f "$OUT/backup.key" ]; then
  openssl genrsa -out "$OUT/backup.key" 4096 2>/dev/null
fi

spki() {
  openssl x509 -in "$1" -pubkey -noout 2>/dev/null \
    | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 -binary \
    | base64
}

spki_from_key() {
  openssl pkey -in "$1" -pubout -outform der \
    | openssl dgst -sha256 -binary \
    | base64
}

echo
echo "Install ops/tls/out/server.crt and server.key at /etc/chat/tls/ (nginx)."
echo "Pre-distribute ops/tls/out/ca.crt to client devices as the trust anchor."
echo
echo "SPKI pin (primary, pin this in the client):"
echo "  sha256/$(spki "$OUT/server.crt")"
echo "SPKI pin (backup key — pin this too, then rotate onto it):"
echo "  sha256/$(spki_from_key "$OUT/backup.key")"
