# ops/offline_install.sh — rebuild the venv with NO network (during a shutdown).
set -euo pipefail
python -m venv .venv && . .venv/bin/activate
python -m pip install --no-index --find-links vendor/wheels --require-hashes \
    -r requirements/dev.txt
echo "Offline install complete."
