#!/usr/bin/env bash
# ops/offline_install.sh — rebuild the venv with NO network (during a shutdown).
#
# Installs only what vendor/wheels holds: --no-index forbids pip from reaching any
# package index, and --require-hashes fails the install loudly on a wheel that is
# missing or does not match its pin. Build the cache first with ops/vendor.sh, on
# this host, while the network is still up — a wheel set is per-platform.
set -euo pipefail

python -m venv .venv && . .venv/bin/activate
python -m pip install --no-index --find-links vendor/wheels --require-hashes \
    -r requirements/dev.txt

echo "Offline install complete."
