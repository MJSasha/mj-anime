#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${FLUTTER_SDK:-}" ]]; then
  flutter_bin="$FLUTTER_SDK/bin/flutter"
else
  flutter_bin="$(command -v flutter)"
fi
python3 tools/setup_signing.py
"$flutter_bin" pub get
"$flutter_bin" analyze
"$flutter_bin" test
"$flutter_bin" build apk --release --target-platform android-arm,android-arm64
python3 tools/package_release.py
cp build/app/outputs/flutter-apk/app-release.apk dist/MJAnime.apk
cp build/app/outputs/flutter-apk/app-release.apk dist/animetka-tv-independent.apk
