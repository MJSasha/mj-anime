# Cast / WebSocket — восстановленный контракт

Статическое исследование 13 ноября 2026. Источники: `work/api-probe/main.dart.js` (опубликованный веб-клиент, сборка `main.dart.3d59eb9f15.js`) и `work/libapp.so.strings` (ASCII arm64 `libapp.so` из APK TV 1.0.5). Ни одно сообщение не отправлялось на сервер в этом исследовании. Живой вход и двухсторонний Cast не проверены.

**Граница версий:** формы сообщений ниже наблюдаются в веб-клиенте. Наличие соответствующих event-name строк в TV-бинарнике подтверждает общую систему, но не идентичность всех полей/веток. Полнота обработчиков TV неизвестна. JS-символы минифицированы; имена Dart-методов, восстановленные из `$async$...`, — подсказки, не исходные source map.

## Подключение и объявление устройства

1. Открыть `wss://animetka.com/api/voice/ws`. В JS URL получается заменой `^http` → `ws` у `https://animetka.com`. Первое прикладное сообщение: `{ "type": "auth", "token": "<account token>" }`. Токен передаётся в сообщении, **не в query string**. Код: main.dart.js:201081–201100.
2. На этой же JSON-сессии отправляется `{ "type":"device:hello", "device_id":"<persistent id>", "platform":"<platform>", "device_label":"<label>" }`. Код: 201020–201032. Веб-реализация `cN6()` возвращает `web`, `cN7()` — `Web` (61639–61640). Для TV значение платформы следует сверить в APK/живом соединении; строка TV-side `device:hello` присутствует (libapp.so.strings:9825).
3. `{ "type":"device:list" }` обновляет устройства (201012–201020 и 201035–201040). Входящие `device:presence` / `device:hello_ok` содержат `devices: [{device_id, platform, label}]`. Пустые device_id отбрасываются. Метки могут отсутствовать, default `Device`; platform default `web` (200976–200999).
4. **REST-регистрация устройства имеет другие поля, чем hello.** `POST /api/auth/device/register` с Bearer (11182–11196) сериализует только непустые `device_id`, `os`, `device_model`, `client_version` (85077–85088). Поля `platform` и `device_label` в этом REST-сериализаторе отсутствуют. Не следует переносить форму hello на register автоматически.

При обрыве сокет закрывается/подписка отменяется; retry с экспоненциальной задержкой, clamp 1..16 секунд. Повторно отправляются auth, сохранённые subscribe и room:join с метаданными (201081–201121; 201151–201165).

## Комнаты и приглашение на TV

Объявление/открытие устройств и приглашения:

```json
{"type":"cast:invite","room_id":123,"chat_id":"456","target_device_id":"tv-…"}
```

`target_device_id` добавляется, только если непустой. Форма наблюдается в 201036–201051. Ответ `cast:invite_sent` даёт `room_id` (парсится как число) и `chat_id` (строка) — 201000–201007. Это ответ отправителю, **не доказательство, что получатель получает `cast:invite`**. В TV-бинарнике есть строка `cast:invite`, но направление по одной строке неизвестно.

```json
{"type":"room:join","room_id":123,"platform":"tv","device_label":"…","device_id":"…"}
{"type":"room:leave","room_id":123}
{"type":"subscribe","chat_id":"456"}
```

Код join/leave: 177036–177083; subscribe: 201139–201143. Join вызывает connect, собирает метаданные platform/device_label, добавляет непустой device_id. room_id в комнате хранится числом; chat_id в watch-сессии — строкой. Эти идентификаторы различаются.

Входящие `room:presence` содержат room_id, `present_user_ids`; обработчик также читает `my_devices`. `room:my_devices_ready` аналогично обновляет состояние устройств выбранной комнаты (180621–180659; сериализация my_devices:177105–177126):

```json
{
 "room_id":123,
 "present_user_ids":[1,2],
 "my_devices":[{"device_id":"tv-…","platform":"tv","label":"TV","ready":true,"is_master":false}],
 "master_device_id":"…",
 "preferred_master_device_id":"…",
 "can_pick_master":true
}
```

При наличии прав выбора master клиент отправляет:

```json
{"type":"room:set_master","room_id":123,"device_id":"…"}
{"type":"room:set_preferred_master","room_id":123,"device_id":"…"}
```

Код: 177084–177100. Входящие `room:master` / `room:preferred_master` обновляют master_device_id/preferred_master_device_id и is_master устройств (180660–180675). Код TV может использовать лишь подмножество этих команд.

Отвязка:

```json
{"type":"cast:release","room_id":123,"chat_id":"456"}
```

chat_id условный; затем `room:leave`. Код: 176155–176181.

## Watch-состояние: запуск, пауза, серия, качество

`watch:start`, `watch:state`, `watch:accept`, `watch:ready` идут в общий обработчик состояния (180720). Веб-модель сериализуется (172160–172187) как:

```json
{
 "chat_id":"456",
 "anime_id":"2778",
 "anime_title":"…",
 "poster_url":"…",
 "episode":1,
 "translation_id":610,
 "translation_name":"AniLibria.TV",
 "quality":"720",
 "position_seconds":123,
 "duration_seconds":1440,
 "playback_rate":1,
 "paused":false,
 "phase":"<phase>",
 "host_user_id":1,
 "from_device_id":"device-…",
 "accepted_user_ids":[1],
 "ready_user_ids":[1],
 "ignored_user_ids":[],
 "wait_started_at":"<ISO UTC>",
 "updated_at":"<ISO UTC>"
}
```

`duration_seconds`, `from_device_id`, `wait_started_at` условные. Тип сообщения добавляется отдельно. `anime_id` и `chat_id` при разборе модели приводятся к строкам; translation_id к int; episode и playback_rate допускают числа/числовые строки. Код parse `aeR`:46201–46263. Парсер воспринимает только явное `paused:false` как воспроизведение; отсутствие paused означает паузу. `from_user_id` читается отдельно, но не сериализуется приведённым qf; его добавление сервером не подтверждено.

Полную отправку `watch:start` вызывает 179145–179147, `watch:state` — 179168–179170 через `aao(type,state)`. Функция aao создаёт объект с type, затем добавляет все поля qf без других преобразований (179616–179619). Значения phase: inviting, waiting, playing; неизвестное/отсутствующее значение парсится как inviting (46193–46196, 228695–228697).

Подтверждение готовности receiver:

```json
{"type":"watch:accept","chat_id":"456","accepted_user_ids":[1]}
{"type":"watch:ready","chat_id":"456","ready_user_ids":[1],"accepted_user_ids":[1]}
```

Если клиент — host, отправляется полная qf-модель вместо сокращённой формы. Код:179509–179515 и 179552–179560. Локальная готовность устройства также отмечается. Точная серверная проверка полномочий неизвестна.

## Позиция и синхронизация

```json
{"type":"watch:position","chat_id":"456","position_seconds":123,"paused":false,"playback_rate":1,"phase":"…"}
{"type":"watch:sync_request","chat_id":"456"}
```

Позицию публикует только controlling/master сторона. У наблюдаемой web-реализации throttling: обычное обновление не чаще ~0.8 с и только при изменении >=1 с; принудительное обновление обходит часть ограничений (179254–179275). Для TV heartbeat точный интервал не восстановлен.

Входящий `watch:sync` (180722–180761): `chat_id`, `position_seconds`, `paused`, `playback_rate`, условные `duration_seconds`, `quality`, `sent_at`. Обрабатывается только совпадающий chat_id; неподходящая/host-сессия может игнорировать его. Defaults: position 0, rate 1, paused true, если не передан явный false. Это **watch:sync**, а не простой входящий watch:position: последнего обработчика в обследованном web-source не найдено (поиск строки watch:position дал только отправителя).

В исходнике есть реализация применения позиции к видеоплееру с порогом расхождения ~800 мс и применение play/pause (200920–200941); передавать каждую позицию без порога вызовет seek-loop.

## Громкость

```json
{"type":"watch:volume","chat_id":"456","level":0.5}
```

Отправитель clamp 0..1 (201053–201063). Receiver принимает level или fallback volume, number/числовую строку, clamp 0..1 (201007–201012). Это уровень media, не абсолютное число Android stream-volume; TV должен преобразовать в диапазон AudioManager самостоятельно. Строка watch:volume есть в APK (libapp.so.strings:13093).

## Прочие состояния и ограничения

- `watch:end` очищает текущую сессию, если chat_id отсутствует или совпадает (180794–180802).
- `watch:error` содержит message, которое показывается пользователю (180790–180794).
- `watch:snapshot` восстанавливает состояние по общему parse (180611; callback 181343).
- `room:closed` удаляет/закрывает комнату (180675–180697).
- Предложение неконтролирующей стороны: `watch:propose` с kind = pause/play/speed/episode, chat_id, anime_id, anime_title, poster_url, episode, translation_id, translation_name, условным playback_rate и from_nickname (179219–179235; enum kind:172150–172156).
- TV-бинарник содержит watch:position, watch:sync_request, watch:end, watch:start, watch:ready, watch:sync, watch:state, room:join/leave/presence/my_devices_ready, device:hello, cast:invite/release. Имена подтверждены только как статические строки, не исполнение.
- Не проверены auth acknowledgement/error, первоначальная адресация входящего cast на TV, TV-specific дополнительные phases, серверные правила прав, обмен после приглашения и reconnect с реальным аккаунтом. Эти пробелы нельзя скрывать тестовыми заглушками.

## Уточнение по результатам ранней интеграционной проверки

Сервер подтверждает авторизацию событием `ready`. Отправка device:hello до этого события может приводить к Unauthorized. Объявление устройства перенесено после ready и покрыто офлайн-тестом. Позднее добавлены проверки адресата приглашения, активной комнаты/master-роли и защита от повторного watch:end; эти последние изменения проверены локальными тестами, без повторных команд на устройства.
