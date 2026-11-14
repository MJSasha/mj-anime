#!/usr/bin/env python3
"""Small stdlib regression: APK safety gates must reject targets before install."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mjanime-guard-') as folder:
    tmp = Path(folder)
    apk = tmp / 'fixture.apk'
    apk.write_bytes(b'not an APK; installation must never be reached')
    adb = tmp / 'adb'
    adb.write_text('''#!/usr/bin/env python3
import os, sys
from pathlib import Path
a = sys.argv[1:]
assert a[:2] == ['-s', 'emulator-5582'], 'missing explicit serial'
with Path(os.environ['MJANIME_FAKE_ADB_LOG']).open('a') as f: f.write(repr(a) + '\\n')
command = a[2:]
if command == ['shell', 'getprop', 'ro.kernel.qemu']: print(os.environ.get('MJANIME_FAKE_QEMU', '1'))
elif command == ['shell', 'settings', 'get', 'global', 'wifi_on']: print(os.environ.get('MJANIME_FAKE_WIFI', '0'))
elif command == ['shell', 'settings', 'get', 'global', 'mobile_data']: print('0')
elif command == ['shell', 'wm', 'size']: print('Physical size: 1280x720')
else: raise SystemExit('Forbidden side effect in guard test: ' + repr(command))
''', encoding='utf-8')
    adb.chmod(0o755)
    for serial, qemu, wifi, message in [
        ('192.168.1.10:5555', '1', '0', 'Refusing non-emulator'),
        ('emulator-5582', '0', '0', 'not an Android emulator'),
        ('emulator-5582', '1', '1', 'wifi_on must already be disabled'),
        ('emulator-5582', '1', '0', 'requires a 1920x1080 emulator'),
    ]:
        log = tmp / 'calls.log'
        log.write_text('')
        env = dict(os.environ, MJANIME_FAKE_ADB_LOG=str(log), MJANIME_FAKE_QEMU=qemu, MJANIME_FAKE_WIFI=wifi)
        result = subprocess.run([sys.executable, str(ROOT / 'tools/apk_smoke.py'), '--serial', serial,
                                 '--apk', str(apk), '--adb', str(adb), '--out', str(tmp / 'out')],
                                env=env, capture_output=True, text=True, timeout=10)
        assert result.returncode != 0 and message in result.stderr, result.stderr
        assert 'install' not in log.read_text() and not (tmp / 'out').exists()
        if not serial.startswith('emulator-'):
            assert not log.read_text(), 'ADB must not be called for a real target'
print('PASS: real target, non-qemu, online emulator and wrong viewport blocked before install')
