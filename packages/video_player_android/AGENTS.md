# Локальный fork video_player_android

Наследуются правила корневого AGENTS.md. Это vendored fork 2.12.4, не общий Pub cache. Публичный Dart/Pigeon API без необходимости не менять.

- Исходники: `android/src/main/java/io/flutter/plugins/videoplayer/`; GPU — `upscale/AnimeEffect.java`, размеры/Surface — `texture/` и `VideoPlayer.java`.
- Весовые GLSL: `android/src/main/assets/anime_upscale/`. Сохранять MIT/BSD notices и provenance. Не регенерировать веса ради косметики.
- При READY с VideoSize.UNKNOWN нельзя выдавать initialized(0,0). Resize → getSurface → bind, включая восстановление поверхности.
- Feature textures signed FP16, NEAREST после sampler binding. Не clamp отрицательные CNN-признаки. Off не подключает эффекты.
- Проверки из корня: `make check`, `make native-test`; для видео/GPU — точный APK с локальным роликом во всех режимах в отдельно разрешённом эмуляторе (`docs/TESTING.md`). JVM/mocks не доказывают изображение на GPU, Mac GPU не доказывает Android-совместимость.
- Без разрешения не запускать эмулятор, не подключать реальные устройства/проектор.
- Объяснять изменения в `MJANIME_CHANGES.md`; не обновлять upstream/Media3 попутно.
