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
mkdir -p dist
release_version="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
cp build/app/outputs/flutter-apk/app-release.apk "dist/MJAnime-$release_version.apk"
cp build/app/outputs/flutter-apk/app-release.apk dist/MJAnime.apk
cp build/app/outputs/flutter-apk/app-release.apk dist/animetka-tv-independent.apk
cd dist
shasum -a 256 "MJAnime-$release_version.apk" MJAnime.apk animetka-tv-independent.apk > SHA256SUMS
