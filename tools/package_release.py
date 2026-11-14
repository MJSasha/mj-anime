#!/usr/bin/env python3
"""Verify the signed final APK and produce immutable GitHub release assets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def version():
    match = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)$', (ROOT / 'pubspec.yaml').read_text(), re.M)
    if not match:
        raise ValueError('Expected stable versionName+versionCode')
    return match.group(1), int(match.group(2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', default='build/app/outputs/flutter-apk/app-release.apk')
    parser.add_argument('--out', default='dist')
    args = parser.parse_args()
    name, code = version()
    tag = os.environ.get('GITHUB_REF_NAME', '')
    if tag and tag != f'v{name}':
        raise SystemExit('Release tag does not match pubspec.yaml')
    sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
    build_tools = sdk / 'build-tools' / '36.0.0'
    apk = Path(args.apk)
    cert = subprocess.check_output([str(build_tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
    expected = (ROOT / 'docs/release-certificate.sha256').read_text().strip()
    actual = re.findall(r'^Signer #\d+ certificate SHA-256 digest: (\w+)$', cert, re.M)
    if actual != [expected]:
        raise SystemExit('APK signing certificate does not match release identity')
    badging = subprocess.check_output([str(build_tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
    if not package or package.groups() != ('dev.independent.animetka_tv', str(code), name):
        raise SystemExit('Unexpected APK package/version')
    abi_line = re.search(r'^native-code: (.+)$', badging, re.M)
    abis = set(re.findall(r"'([^']+)'", abi_line.group(1))) if abi_line else set()
    if 'application-debuggable' in badging or abis != {'armeabi-v7a', 'arm64-v8a'}:
        raise SystemExit('Unexpected APK debug flag or ABIs')
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    asset = out / f'MJAnime-{name}.apk'
    shutil.copyfile(apk, asset)
    digest = hashlib.sha256(asset.read_bytes()).hexdigest()
    (out / 'SHA256SUMS').write_text(f'{digest}  {asset.name}\n')
    (out / 'update.json').write_text(json.dumps({
        'version': name, 'versionCode': code, 'size': asset.stat().st_size,
        'sha256': digest,
        'url': f'https://github.com/MJSasha/mj-anime/releases/download/v{name}/{asset.name}',
    }, indent=2) + '\n')
    print(f'Verified {asset.name}: package, version, certificate, release mode, ARMv7/ARM64; SHA-256 {digest}')


if __name__ == '__main__':
    main()
