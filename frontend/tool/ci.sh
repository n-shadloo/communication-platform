#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
sh ./tool/generate.sh
git diff --exit-code -- lib
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build apk --debug --flavor development --target lib/main_development.dart
flutter build apk --release --flavor production --target lib/main_production.dart
flutter build web --release --target lib/main_production.dart
