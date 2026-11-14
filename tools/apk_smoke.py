#!/usr/bin/env python3
"""Exercise the exact MJAnime APK on an explicitly authorized, offline 1080p emulator.

Does not discover/connect devices, start an AVD, change network state or use an account.
Requires numpy/Pillow from tool/upscale/requirements.txt. Output may contain device logs.
"""
import argparse
import hashlib
import io
import json
import re
import shutil
import subprocess
import time
from pathlib import Path

PACKAGE = 'dev.independent.animetka_tv'
MODES = {'off': '', 'light': 'Лёгкий', 'cnn_s': 'Anime4K CNN S', 'cnn_m': 'Anime4K CNN M'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True, help='Explicit isolated emulator-NNNN serial')
    parser.add_argument('--apk', type=Path, required=True, help='Exact release APK to install and test')
    parser.add_argument('--out', type=Path, required=True, help='Private output directory; images/logcat/results.json')
    parser.add_argument('--adb', default=shutil.which('adb'), help='Path to Android SDK adb')
    args = parser.parse_args()
    if not re.fullmatch(r'emulator-\d+', args.serial):
        parser.error('Refusing non-emulator serial. Never target the projector.')
    if not args.adb or not args.apk.is_file():
        parser.error('A valid adb executable and APK file are required.')

    def adb(*words):
        return subprocess.check_output([args.adb, '-s', args.serial, *words], timeout=60)

    if adb('shell', 'getprop', 'ro.kernel.qemu').strip() != b'1':
        parser.error('Target is not an Android emulator.')
    for setting in ['wifi_on', 'mobile_data']:
        if adb('shell', 'settings', 'get', 'global', setting).strip() != b'0':
            parser.error(f'{setting} must already be disabled in the isolated emulator.')
    if b'1920x1080' not in adb('shell', 'wm', 'size'):
        parser.error('This deterministic fixture check requires a 1920x1080 emulator.')
    # Load optional dependencies before installing anything.
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        parser.error('Install optional dependencies: pip install -r tool/upscale/requirements.txt')
    args.out.mkdir(parents=True, exist_ok=True)
    report = {
        'apk_sha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(),
        'serial': args.serial,
        'android_api': adb('shell', 'getprop', 'ro.build.version.sdk').decode().strip(),
        'network': 'disabled', 'clip': 'embedded silent H264 1280x720', 'modes': [],
    }

    def save():
        (args.out / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')

    def frame(name=None):
        raw = adb('exec-out', 'screencap', '-p')
        if name:
            (args.out / name).write_bytes(raw)
        return np.asarray(Image.open(io.BytesIO(raw))).astype(float)

    adb('install', '-r', str(args.apk.resolve()))
    try:
        for mode, actual in MODES.items():
            adb('shell', 'am', 'force-stop', PACKAGE)
            adb('logcat', '-c')
            adb('shell', 'am', 'start', '-S', '-W', '-n', f'{PACKAGE}/.MainActivity',
                '-a', f'{PACKAGE}.VIDEO_CHECK', '--es', 'mode', mode)
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                button = frame()[590:680, 495:860, :3]
                if ((button[:, :, 1] > 200) & (button[:, :, 0] > 150) & (button[:, :, 2] < 170)).sum() > 5000:
                    break
                time.sleep(.25)
            else:
                raise RuntimeError('Local diagnostic home did not appear; refusing blind input.')
            adb('shell', 'input', 'tap', '680', '630')
            # Let controls hide; compare two real rendered frames, not initialization alone.
            time.sleep(8)
            frames = [frame(f'{mode}-a.png')]
            time.sleep(5)
            frames.append(frame(f'{mode}-b.png'))
            logs = adb('logcat', '-d', '-v', 'brief').decode('utf-8', errors='replace')
            (args.out / f'{mode}.log').write_text(logs, encoding='utf-8')
            statuses = [line for line in logs.splitlines() if 'MJAnimeUpscale' in line]
            errors = [line for line in logs.splitlines() if any(v in line for v in [
                'VideoFrameProcessingException', 'GlException', 'VideoError', 'FATAL EXCEPTION', 'failed to compile'])]
            colored, positions = [], []
            for im in frames:
                roi = im[400:1000, 10:1900, :3]
                colored.append(int(((roi[:, :, 0] > 100) & (roi[:, :, 1] < 80)).sum()
                                   + ((roi[:, :, 1] > 100) & (roi[:, :, 0] < 80)).sum()))
                _, xs = np.where((im[440:820, :, :3] > 220).all(axis=2))
                positions.append(float(xs.mean()) if len(xs) > 1000 else None)
            initializations = sum('ExoPlayerImpl' in line and 'Init ' in line for line in logs.splitlines())
            passed = (not errors and initializations == 1 and min(colored) > 400000
                      and all(v is not None for v in positions) and abs(positions[0] - positions[1]) > 10
                      and 'Initialized visible texture ' in logs
                      and (not actual or any(actual in line and '1280×720 → 1920×1080' in line for line in statuses)))
            report['modes'].append({'mode': mode, 'passed': passed, 'actual_status': statuses,
                                   'initializations': initializations, 'colored_pixels': colored,
                                   'marker_x': positions, 'errors': errors})
            save()
            print(f'{mode}: {"PASS" if passed else "FAIL"}', flush=True)
        if not all(row['passed'] for row in report['modes']):
            raise SystemExit('APK verification failed. Inspect private output; do not distribute this binary.')
        print('PASS: all modes, exact APK SHA-256:', report['apk_sha256'])
    finally:
        adb('shell', 'am', 'force-stop', PACKAGE)


if __name__ == '__main__':
    main()
