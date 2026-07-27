#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
flutter gen-l10n
dart run build_runner build
