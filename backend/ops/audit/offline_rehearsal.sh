#!/usr/bin/env bash
# ops/audit/offline_rehearsal.sh — prove the no-foreign-dependency build (§1A.1, §10.9).
#
# Rebuilds a throwaway venv STRICTLY from vendor/wheels: --no-index forbids pip from
# touching any package index or the network at all, and --require-hashes pins every
# artifact, so one missing or tampered wheel fails the install loudly. Then the full
# suite runs inside that venv. PASS means: with the internet gone, this repo still
# builds and every test still holds.
#
# Prereqs: vendor/wheels populated (run ops/vendor.sh while still online), .env filled
# in, and the native PostgreSQL 16 + Redis 7 from CLAUDE.md "Running things" listening
# on localhost.
set -euo pipefail

cd "$(dirname "$0")/../.."          # …/backend
[ -f manage.py ] || { echo "FAIL: not at the backend root"; exit 1; }

wheel_count=$(find vendor/wheels -name '*.whl' 2>/dev/null | wc -l | tr -d ' ')
if [ "${wheel_count}" -eq 0 ]; then
    echo "FAIL: vendor/wheels is empty — run ops/vendor.sh while online first."
    exit 1
fi
echo "vendor/wheels: ${wheel_count} wheels"

if [ -f .env ]; then
    set -a; . ./.env; set +a
else
    echo "FAIL: .env missing — the suite needs DB/Redis settings (see .env.example)."
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Seed with the interpreter the wheels were vendored for, falling back to python3.
seed=".venv/bin/python"; [ -x "$seed" ] || seed="python3"
"$seed" -m venv "$tmp/venv"

echo "installing from vendor/wheels only (--no-index --require-hashes)…"
PIP_DISABLE_PIP_VERSION_CHECK=1 "$tmp/venv/bin/python" -m pip install --quiet \
    --no-index --find-links vendor/wheels --require-hashes -r requirements/dev.txt

echo "running the full suite inside the offline-built venv…"
if "$tmp/venv/bin/python" -m pytest -q; then
    echo "PASS: offline rebuild + full suite green (§10.9)."
else
    echo "FAIL: suite failed inside the offline-built venv."
    exit 1
fi
