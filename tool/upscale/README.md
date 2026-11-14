# CNN port validation

Run `python3 tool/upscale/check.py` on macOS with Python NumPy and Xcode command-line tools.
It creates an offscreen OpenGL context, executes the actual S/M GLSL assets using signed FP16 buffers,
and compares against an independent NumPy calculation from the original MIT weights.
No network, window automation, account, emulator or Android device is used.
This validates shader mathematics and channel order, not Android GPU support or projector FPS.
Flutter tests separately cover mode persistence, pause/progress, delayed initialization, remote focus and fallback.
