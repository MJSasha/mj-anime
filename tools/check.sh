#!/usr/bin/env bash
# Offline checks only. Bootstrap dependencies with flutter pub get first.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${FLUTTER_SDK:-}" ]]; then
  flutter_bin="$FLUTTER_SDK/bin/flutter"
  dart_bin="$FLUTTER_SDK/bin/dart"
else
  flutter_bin="$(command -v flutter)"
  dart_bin="$(dirname "$flutter_bin")/dart"
fi
python3 tools/repo_check.py --self-test
python3 tools/repo_check.py
python3 tools/test_repo_tools.py
"$dart_bin" format --output=none --set-exit-if-changed lib test
"$flutter_bin" analyze --no-pub
"$flutter_bin" test --no-pub
