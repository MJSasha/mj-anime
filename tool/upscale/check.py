#!/usr/bin/env python3
"""Local Mac GPU / NumPy check. No network, devices, windows or Android execution."""
from pathlib import Path
import os, subprocess, sys, tempfile
import numpy as np

if sys.platform != 'darwin':
    raise SystemExit('This standalone shader check requires macOS OpenGL. Flutter tests are cross-platform.')
root = Path(__file__).resolve().parents[2]
assets = root / 'packages/video_player_android/android/src/main/assets/anime_upscale'
with tempfile.TemporaryDirectory(prefix='mjanime-cnn-') as folder:
    out = Path(folder)
    y,x = np.mgrid[:18,:32]
    image = np.stack([30+x*5, 50+y*8, 80+((x+y)%7)*14, np.full_like(x,255)],axis=-1).astype('uint8')
    image[3:13,12:15,:3] = 15
    image[10:12,4:27,:3] = 230
    (out/'small.rgba').write_bytes(image.tobytes())
    subprocess.run(['clang++','-std=c++17','-O2',str(Path(__file__).with_name('gpu_check.mm')),'-framework','OpenGL','-o',str(out/'gpu_check')],check=True)
    subprocess.run([str(out/'gpu_check'),str(assets),str(out/'small.rgba'),'32','18','64','36',str(out/'small')],check=True)
    env = dict(os.environ, UPSCALER_TEST_OUTPUT=str(out), UPSCALER_MODELS=str(assets))
    subprocess.run([sys.executable,str(Path(__file__).with_name('validate_cnn.py'))],env=env,check=True)
