# Архитектура и карта изменений

## Поток выполнения

```text
main → SharedPreferences + миграция обработки → TvApp
  ├─ LoginScreen → Session
  ├─ Shell → API / локальная история → DetailsScreen → PlayerScreen
  └─ LocalVideoCheckHome → тот же PlayerScreen → встроенный H.264

PlayerScreen → video_player → локальный video_player_android → Media3
                                                      ├─ Off → Surface
                                                      └─ AnimeEffect → GPU → Surface → Flutter texture
```

`Session` в `api.dart` — текущий аккаунт/настройки/локальный прогресс и история. UI использует существующие StatefulWidget/FocusNode/FutureBuilder; отдельного DI-контейнера или state-management framework нет.

## Где менять

| Задача | Код | Основные регрессии |
|---|---|---|
| Главная, поиск, история, списки, настройки | `lib/main.dart` | `cinema_test`, `shell_test`, `full_tv_fixes_test` |
| Баннер | `lib/main.dart`, метод `home` | `cinema_test`: координаты и рендеры |
| Боковое меню, карусели, системный ввод | `lib/cinema.dart` | `cinema_test`, `remote_navigation_test` |
| Тема, общие кнопки, карточки, фокус | `lib/ui.dart` | `tv_ui_test`, `full_tv_fixes_test` |
| Аниме, номера, голоса, сезоны | `lib/details.dart` | `cinema_test`, `remote_navigation_test` |
| Жизненный цикл видео/прогресс/ошибки/панели | `lib/player.dart` | `remote_navigation_test` |
| Пульт, шкала, transport UI, опенинг/конец | `lib/tv_playback.dart` | `remote_navigation_test`, `audit_fixes_test` |
| HTTP, JSON, Session, история | `lib/api.dart` | `widget_test`, `cinema_test`, `auth_test` |
| Вход и нативный MethodChannel | `lib/auth.dart`, `android/app/src/main/kotlin/dev/independent/animetka_tv/MainActivity.kt` | `auth_test`, `full_tv_fixes_test` |
| Профиль, фильтры | `lib/account.dart`, `lib/filters.dart` | `full_tv_fixes_test` |
| GitHub обновления | `lib/updates.dart`, `ReleaseDownload.kt`, существующий установщик `MainActivity.kt` | `updates_test`, `ReleaseDownloadTest`, `NativeRecoveryTest` |
| Cast и защита от чужих событий | `lib/cast.dart` | `cast_protocol_test`, `cast_navigation_test` |
| Селектор/канал GPU | `lib/anime_upscale.dart` | `anime_upscale_test`, `remote_navigation_test` |
| Реальная локальная проверка APK | `lib/local_video_check.dart`, `assets/video_check.mp4` | `tools/apk_smoke.py` |
| Android decoder/Surface/размеры/шейдеры | `packages/video_player_android/` | нативные JVM + установленный APK |

Точные имена файлов тестов: суффикс `_test.dart` в `test/`.

## Контракты, которые легко сломать

- `timestamp` истории — секунды позиции, `duration` истории — секунды; `duration` объекта аниме может быть минутами. Нормализация: `historyAnime`.
- `markOpened` пишет отдельные даты открытия; `recentHistory` объединяет свежий прогресс и стабильно сортирует. Не менять прогресс при простом открытии страницы.
- Версия приложения — `pubspec.yaml`; package и подпись Android — существующие release-идентификаторы. Не менять ключи каналов/протокола при переименовании UI.
- Native channels: `dev.independent.animetka/native`, `dev.independent.animetka/upscale`. Kotlin обрабатывает Back и платформенные действия; Pigeon/video API находится в локальном fork.
- Media3 READY может прийти с неизвестным размером: нельзя отправлять Flutter `initialized(0,0)`. Действительная GPU-текстура при нулевой площади виджета выглядит как чёрный экран.
- Обработанную Surface нужно получать после resize и привязывать заново. CNN feature maps — signed FP16 и NEAREST sampling; отрицательные признаки не обрезать.
- Off не подключает effects; native 1080p не нуждается в CNN x2, HDR обходит обработку. Фактический fallback виден в статусе, его нельзя выдавать за CNN.

## Данные и ресурсы

`pubspec.lock` и локальный fork — часть исходников. `assets/` содержит шрифты/лицензию и маленький немой тестовый ролик. `test/fixtures/tv/` — локальные публичные metadata/изображения для тестов, не аккаунт. `docs/*CONTRACT*.md` — результаты исследования с указанием ограничений, не разрешение выполнять запросы. Документы в `docs/history/` могут ссылаться на внешние локальные артефакты, которые не входят в checkout.
