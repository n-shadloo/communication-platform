#!/usr/bin/env bash
# ops/vendor.sh — run while the internet is available (pre-shutdown).
#
# Run it ON THE HOST that will install from the result: a wheel set is built for
# one platform and one interpreter, and the macOS arm64 wheels a developer
# machine downloads do not install on the Linux VPS.
#
# --only-binary=:all: refuses a source distribution outright. The VPS has no
# compiler and, at install time, no network to fetch a build backend with, so an
# sdist that lands here is a build that fails during a shutdown rather than a
# download that fails now. It is the same flag the CI offline-install job uses,
# so what CI proves and what the operator carries are the same set.
set -euo pipefail

python -m pip download --require-hashes --only-binary=:all: \
    -r requirements/prod.txt -d vendor/wheels
python -m pip download --require-hashes --only-binary=:all: \
    -r requirements/dev.txt -d vendor/wheels

echo "Vendored $(find vendor/wheels -name '*.whl' | wc -l | tr -d ' ') wheels into vendor/wheels/."
