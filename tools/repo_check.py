#!/usr/bin/env python3
"""Check repository boundaries and links without network, secrets or device access."""
import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ['pubspec.yaml', 'pubspec.lock', 'lib/main.dart', 'android/settings.gradle.kts',
            'android/build.gradle.kts', 'android/app/build.gradle.kts', 'android/gradlew',
            'android/gradle/wrapper/gradle-wrapper.jar', 'android/app/src/main/AndroidManifest.xml',
            'android/app/src/main/kotlin/dev/independent/animetka_tv/MainActivity.kt',
            'packages/video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/VideoPlayer.java',
            'assets/video_check.mp4']
DOCS = ['AGENTS.md', 'README.md', 'STATUS.md', 'docs/ARCHITECTURE.md', 'docs/DEVELOPMENT.md', 'docs/TESTING.md', 'CONTRIBUTING.md', 'docs/RELEASING.md', 'CHANGELOG.md', 'docs/MJANIME-DESIGN.md', 'docs/ANDROID-RECOVERY.md']


def forbidden(name):
    p = Path(name)
    if any(part in {'.signing', '.dart_tool', '.gradle', 'build', 'dist', 'test-output', '__pycache__'} for part in p.parts):
        return True
    return (p.name in {'local.properties', 'key.properties'}
            or (p.name.startswith('.env') and p.name != '.env.example')
            or p.suffix.lower() in {'.jks', '.keystore', '.p12', '.pfx', '.pem', '.apk', '.aab'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        assert all(forbidden(v) for v in ['.signing/release.jks', 'android/local.properties', 'packages/p/build/output', '.env', '.env.production', 'dist/app.apk'])
        assert not any(forbidden(v) for v in ['.env.example', 'lib/main.dart', 'tools/build.sh', 'android/gradle/wrapper/gradle-wrapper.jar'])
        print('PASS: repository guard regression cases')
        return
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    errors = [f'Missing required source/build file: {name}' for name in REQUIRED if not (ROOT / name).is_file()]
    for name in filter(None, names):
        p = ROOT / name
        if forbidden(name):
            errors.append(f'Private/generated path in Git index: {name}')
        if p.is_file() and p.stat().st_size > 5 * 1024 * 1024:
            errors.append(f'Unexpected file over 5 MiB in Git index: {name}')
    for name in DOCS:
        p = ROOT / name
        if not p.is_file():
            errors.append(f'Missing entry-point document: {name}')
            continue
        for target in re.findall(r'\]\(([^)]+)\)', p.read_text(encoding='utf-8')):
            target = target.split('#', 1)[0]
            if not target or re.match(r'\w+://|mailto:', target):
                continue
            path = (p.parent / target).resolve()
            if not path.is_relative_to(ROOT) or not path.exists():
                errors.append(f'Broken/non-portable documentation link in {name}: {target}')
    if errors:
        raise SystemExit('\n'.join(errors))
    print('PASS: indexed paths, file sizes and current documentation links')


if __name__ == '__main__':
    main()
