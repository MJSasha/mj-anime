# MJAnime

Приложение для просмотра аниме на Android TV: поиск, аниме и связанные сезоны, история, списки, HLS/MP4-плеер, пропуск опенингов и опциональная обработка изображения. Интерфейс рассчитан на пульт и Full HD.

Flutter **3.50.0** / Dart **3.14.0**, Kotlin, локальный fork `video_player_android` с Media3. Android API 24+, ARMv7/ARM64. Текущая версия задаётся только в [pubspec.yaml](pubspec.yaml).

## Начать работу

1. Прочитать [AGENTS.md](AGENTS.md): карта проекта, инварианты и ограничения устройств.
2. Установить Flutter 3.50.0, JDK 21 и Android SDK; задать `JAVA_HOME` и `ANDROID_HOME`.
3. Если Flutter отсутствует в PATH, задать `FLUTTER_SDK` — каталог SDK.
4. Из корня репозитория:

```sh
# Первый запуск: получить закреплённые зависимости.
"${FLUTTER_SDK:+$FLUTTER_SDK/bin/}flutter" pub get
make check
```

`make check` проверяет структуру репозитория, формат, анализатор и офлайн-тесты. Не запускает устройства, не вызывает сервер и не создаёт ключ подписи. Для первого `pub get` нужны сеть либо заполненный Pub cache.

## Основные команды

| Команда | Назначение |
|---|---|
| `make check` | Безопасная проверка по умолчанию |
| `make hooks` | Включить быстрый локальный guard перед коммитом |
| `make test` | Офлайн Flutter-тесты |
| `make native-test` | Нативные регрессии Media3/JVM, без устройства |
| `make build` | Подписанный release APK, обе ARM ABI |
| `python3 tools/apk_smoke.py --help` | Проверка установленного APK, только разрешённый изолированный эмулятор |

`make build` использует [tools/build.sh](tools/build.sh); APK и SHA-256 появляются в `dist/`. Для обновления установленного MJAnime нужен **прежний** приватный ключ из `.signing/`. На новом checkout скрипт может создать отдельную подпись: такой APK не обновит прежнюю установку. Не пересоздавать существующий ключ.

## Документация

- [Вклад в проект](CONTRIBUTING.md), [выпуск и подпись](docs/RELEASING.md), [изменения](CHANGELOG.md)
- [Архитектура и карта изменений](docs/ARCHITECTURE.md)
- [Разработка, подпись и внешние границы](docs/DEVELOPMENT.md)
- [Тесты, рендеры и проверка APK](docs/TESTING.md)
- [Текущий статус и ограничения](STATUS.md)
- [Восстановление Android-платформы](docs/ANDROID-RECOVERY.md)
- [Дизайн MJReader/MJAnime](docs/MJANIME-DESIGN.md)
- [Cast-протокол](docs/CAST-CONTRACT.md), [дополнительные API-контракты](docs/EXTRA-CONTRACTS.md)
- [Исторические заметки](docs/history/README.md), [хронология](docs/history/STATUS.md)

Исторические файлы содержат решения и результаты прошлых версий; они не заменяют текущие инструкции. Токены, ключи, аккаунты, APK и кеши исключены из Git. Публичный remote не настроен.
