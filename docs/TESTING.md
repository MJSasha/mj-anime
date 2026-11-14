# Проверка изменений

## По умолчанию: без устройств и сервера

Нужны Flutter 3.50.0 / Dart 3.14.0 и Python 3.9+. После первого `flutter pub get`:

```sh
make check
# Отдельный сценарий:
"${FLUTTER_SDK:+$FLUTTER_SDK/bin/}flutter" test --no-pub test/cinema_test.dart
```

Тесты подменяют API, HTTP-изображения, video platform и native channels. Они проверяют логику/рендер и не доказывают вывод GPU Android или доступность сервера. `make check` не обновляет зависимости, не запускает ADB и не создаёт ключи. Если пакеты отсутствуют, сначала явно выполнить `pub get`; подготовка зависимостей может потребовать сеть.

| Изменение | Минимальная целевая проверка |
|---|---|
| Карусель/баннер/IME/история/номера | `test/cinema_test.dart` |
| Фокус пульта, Back, перемотка, подсказки, видео-fallback | `test/remote_navigation_test.dart` |
| Остальные экраны, формы, списки, профиль | `test/full_tv_fixes_test.dart`, `test/tv_ui_test.dart` |
| Cast | `test/cast_protocol_test.dart`, `test/cast_navigation_test.dart` |
| Вход | `test/auth_test.dart` |
| Селектор апскейлера | `test/anime_upscale_test.dart` |
| Surface/размеры Media3 | JVM + установленный APK ниже |

Перед коммитом — полный `make check`. Для документальных правок не нужно пересобирать/публиковать APK.

## Локальные рендеры

```sh
UPDATE_CINEMA_PREVIEWS=1 MJANIME_PREVIEW_DIR=test-output/previews/cinema \
  "${FLUTTER_SDK:+$FLUTTER_SDK/bin/}flutter" test --no-pub test/cinema_test.dart
UPDATE_TV_PREVIEWS=1 MJANIME_PREVIEW_DIR=test-output/previews/tv \
  "${FLUTTER_SDK:+$FLUTTER_SDK/bin/}flutter" test --no-pub test/tv_ui_test.dart
```

Выход по умолчанию — эти же игнорируемые каталоги. Реальные Flutter-виджеты, локальные fixture-изображения, обе темы. Системная Android IME в widget-test не рисуется: проверяется TextInput contract, настоящее окно проверяется в APK отдельно. Сравнивать выбранный макет и новый рендер при одинаковых размере/состоянии, не выдавать fixture-контент за реальные данные аккаунта.

## Нативные регрессии, без эмулятора

После `pub get`, с JDK 21, Android SDK и подготовленным Gradle cache:

```sh
make native-test
```

Запускаются `UpscaleSurfaceTest` и `ProcessedVideoSizeTest` (8 проверок), затем `NativeRecoveryTest` (8 проверок Back и защиты установки обновлений): порядок resize/bind, восстановление, watchdog и ненулевые размеры инициализации. Первый Gradle/Robolectric запуск может получать зависимости; после заполнения cache возможен `GRADLE` запуск с `--offline`. Эти JVM-тесты не исполняют настоящий Android GL.

## GPU-математика на macOS (не Android-совместимость)

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r tool/upscale/requirements.txt
python3 tool/upscale/check.py
```

Нужны Xcode command-line tools/OpenGL. Сверяется настоящий GLSL с независимым NumPy-расчётом исходных весов. Это не замер FPS и не Android APK-тест.

## Точный APK на разрешённом изолированном эмуляторе

Только когда пользователь разрешил такую проверку для задачи. **Проектор/TV не трогать.** Скрипт не создаёт AVD, не открывает сеть, не подключается к устройствам и не получает аккаунт. Сначала подготовить отдельный headless/no-audio AVD ARM64, 1920×1080, и отключить Wi-Fi/mobile data именно в нём. Не пользоваться чужим пользовательским AVD.

```sh
# Только пример serial; использовать serial своего явно разрешённого эмулятора.
python3 tools/apk_smoke.py --serial emulator-5582 \
  --apk dist/MJAnime-1.7.0.apk --out test-output/apk-smoke
```

`adb` нужен в PATH или передаётся `--adb /path/to/adb`. Нужны опциональные numpy/Pillow из requirements выше. Все команды ADB имеют явный serial; до установки проверяются `ro.kernel.qemu=1`, размер экрана и выключенная сеть. Другие устройства отвергаются. Скрипт устанавливает переданный APK и запускает настоящий PlayerScreen со встроенным немым H.264 720p. В конце останавливает только тестовое приложение; AVD закрывается отдельно владельцем, ADB server не трогать.

Для каждого Off/Light/CNN S/CNN M сохраняются два кадра, положение движущейся метки и logcat. Успех: цветное движущееся видео, ненулевой размер, ровно один ExoPlayer без скрытого fallback; фактические CNN S/M и 720p → 1080p подтверждены статусами. JSON содержит SHA-256 **установленного файла**. Не менять APK между прогоном и выдачей; проверять совпадение хеша.

Диагностическое действие `dev.independent.animetka_tv.VIDEO_CHECK` с extra `mode` (`off/light/cnn_s/cnn_m`) открывает локальную проверку без аккаунта; обычный путь — «Настройки → Приложение → Проверить воспроизведение». Данные аккаунта/истории не записываются. Порядок серий/пульт/системную IME проверять дополнительно по затронутой задаче.

Последняя подтверждённая база — [STATUS.md](../STATUS.md). Невыполненные проверки прямо обозначать. Офлайн-DNS ошибка эмулятора не означает поломку боевого сервера.
