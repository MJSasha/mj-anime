#!/usr/bin/env bash
# Host JVM regressions; no emulator, ADB or live server.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f .dart_tool/package_config.json ]]; then
  echo 'Run flutter pub get before native tests.' >&2
  exit 1
fi
cd android
./gradlew :video_player_android:testDebugUnitTest \
  --tests '*UpscaleSurfaceTest' --tests '*ProcessedVideoSizeTest'

./gradlew :app:testDebugUnitTest --tests '*NativeRecoveryTest'
