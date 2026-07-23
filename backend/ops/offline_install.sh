# ops/offline_install.sh — rebuild the venv with NO network (during a shutdown).
# NOTE: vendor/wheels/ currently holds macOS arm64 wheels, which will not install on
# the Linux VPS. Re-run ops/vendor.sh ON THE VPS to produce a usable offline set there.
set -euo pipefail
python -m venv .venv && . .venv/bin/activate
python -m pip install --no-index --find-links vendor/wheels --require-hashes \
    -r requirements/dev.txt
echo "Offline install complete."
