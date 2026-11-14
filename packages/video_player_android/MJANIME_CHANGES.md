# MJAnime video processing extension

Based on Flutter video_player_android 2.12.4 (BSD-3-Clause; LICENSE retained).
The Dart/Pigeon video API is unchanged. A separate MJAnime channel selects a GPU effect
before player creation; off does not attach any video effects.
Native Media3 1.9.2 effect dependency matches the existing decoder version.
Anime4K v4.0.1 S/M weights and their MIT license/provenance are in Android assets.
ES2 wrappers preserve signed feature values in FP16 FBOs; the output is capped at 1080p.
CNN runs only when both dimensions are enlarged by more than 1.2x; native 1080p sources use the light filter.

## Surface fix (1.6.1)

For processed video, call SurfaceProducer.setSize BEFORE getSurface, then explicitly bind
that current Surface. ImageReaderSurfaceProducer lazily creates a new Surface after resize;
setSize alone does not rebind ExoPlayer. Rebind on resize and surface restoration.
The READY/first-frame watchdog reports failure to Dart, which retries once with mode off.
JVM regression: android/gradlew :video_player_android:testDebugUnitTest --tests io.flutter.plugins.videoplayer.UpscaleSurfaceTest


## Real APK regression fix (1.6.2)

Custom GL effects may reach READY with VideoSize.UNKNOWN. Do not send initialized(0,0) to Flutter: valid GPU frames would render in an empty SizedBox. Use the known processed output size, pending video size or source Format; defer initialization until dimensions exist. Retain pixel aspect ratio for source metadata. Dart rejects empty initialized sizes as an additional recovery guard.

Media3 GlProgram binds sampler textures with LINEAR filtering. Explicitly restore NEAREST for signed FP16 CNN feature maps after binding, avoiding incomplete textures on ES2 devices without half-float linear filtering.

Regression tests: UpscaleSurfaceTest + ProcessedVideoSizeTest (8 JVM tests). Actual signed universal APK tested on API 30 and 37, local 720p asset: off/light/CNN S/CNN M, colored moving frames, native mode reports and no fallback/restart. No projector used; this is not a real-hardware FPS benchmark.
