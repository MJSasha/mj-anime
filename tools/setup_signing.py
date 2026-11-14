#!/usr/bin/env python3
"""Create a private, stable local signing identity once. Never prints passwords."""
from pathlib import Path
import os
import secrets
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
directory = root / '.signing'
key = directory / 'release.jks'
properties = directory / 'key.properties'
if key.exists() or properties.exists():
    if not (key.exists() and properties.exists()):
        raise SystemExit('Incomplete signing identity; restore the matching key and properties from your backup.')
    print('Using existing local signing identity.')
else:
    keytool = shutil.which('keytool')
    if not keytool:
        raise SystemExit('JDK keytool is required. Put an installed JDK on PATH.')
    directory.mkdir(exist_ok=True)
    password = secrets.token_urlsafe(32)
    environment = dict(os.environ, INDEPENDENT_TV_SIGNING_PASSWORD=password)
    subprocess.run([keytool, '-genkeypair', '-keystore', str(key), '-alias', 'release',
                    '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
                    '-storepass:env', 'INDEPENDENT_TV_SIGNING_PASSWORD',
                    '-keypass:env', 'INDEPENDENT_TV_SIGNING_PASSWORD',
                    '-dname', 'CN=Independent Android TV Client'],
                   env=environment, check=True, capture_output=True)
    properties.write_text('storePassword=' + password + '\nkeyPassword=' + password +
                          '\nkeyAlias=release\n')
    os.chmod(key, 0o600)
    os.chmod(properties, 0o600)
    print('Created private signing identity in .signing/. Keep a private backup for future updates.')
