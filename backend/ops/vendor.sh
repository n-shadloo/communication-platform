# ops/vendor.sh — run while the internet is available (pre-shutdown).
set -euo pipefail
python -m pip download --require-hashes -r requirements/prod.txt -d vendor/wheels
python -m pip download --require-hashes -r requirements/dev.txt  -d vendor/wheels
echo "Vendored wheels into vendor/wheels/. Commit or archive per your policy."
