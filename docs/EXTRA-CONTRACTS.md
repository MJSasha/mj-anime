# Дополнительные API-контракты и TV-настройки

Источники: статический опубликованный `work/api-probe/main.dart.js` (сборка `main.dart.3d59eb9f15.js`), ASCII-строки arm64 APK `work/libapp.so.strings`. Дополнительно выполнены четыре публичных GET с User-Agent `Dart/3.14 (dart:io)`; ответы сохранены в `work/api-probe/extra-{genres,studios,schedule,characters}.json`. Пользовательские данные не запрашивались, мутаций не выполнялось.

## Настройки: ключи, типы, defaults

Ключи ниже **наблюдаются в TV libapp.so**, а типы/defaults подтверждены веб-реализацией общих предпочтений. Само наличие строки не гарантирует, что TV использует каждый web-default без изменения.

| Ключ SharedPreferences (точное написание) | Тип / web-default | Источник JS | Строка TV |
|---|---|---|---|
| `preferredQuality` | String, `auto` | 83634–83652 | 9274 |
| `lastTranslationName` | String?; trim, пустое→null | 83653–83668 | 1727 |
| `doubleTapSeekSeconds` | Int; один из 5,10,15,20, иначе 10 | 83670–83696; допустимые 230404 | 16863 |
| `playerVolume` | Double clamp 0..1; default 1 | 83698–83720 | 2566 |
| `prefferedTitle` | **Опечатка в ключе намеренная**, Int enum 0 ruTitle, 1 origTitle; default 0 | 83722–83745; enum 230897–230899 | 5112 |
| `animeKindBadgeStyle` | String enum `rating`/`type`/`episodes`; default `type` | 83746–83769; 227993,231392–231393; parser 12211–12214 | 3028 |
| `checkUpdatesOnStartup` | Bool default true | 83771–83784 | 2386 |
| `searchHistoryEnabled` | Bool default true | 83786–83810 | 4713 |
| `miniPlayerEnabled` | Bool default true | 83812–83837 | 11654 |
| `autoSkipOpeningEnding` | Bool default false | 83815–83841 | 550 |
| `autoNextEpisode` | Bool default true | 83843–83865 | 10870 |
| `autoNextSeason` | Bool default false | 83867–83889 | 173 |

TV-only ключи, по строкам: `tv_theme_brightness` (9503), `tv_guest_mode` (11373), `tv_cast_device_label` (3334). Их типы/значения в данном проходе не декомпилированы. Имена методов подтверждают `toggleBrightness`, `fetchTitle`, `fetchCheckUpdatesOnStartup`, `fetchAnimeCardBadgeField`, `fetchDoubleTapSeekSeconds`, `fetchAutoNextEpisode`.

`autoSkipOpeningEnding` следует привязывать к `skipdata` конкретной серии, а не фиксированным 90 секундам: web-парсер отрезка читает `start`, `stop`, принимает только stop>start (83467–83480); `EpisodeSkipdata` присутствует в TV (строка 3101). Код TV применения skipdata пока не восстановлен.

## Новые серии / обновления

**Не установлен отдельный endpoint новых серий.** Найденный web-метод `aRC` вызывает обычный расширенный search с preset `B.bbf`, limit=a и offset=0 (10520–10538). Preset явно содержит `order='[["id","DESC"]]'` (235553), а не `updated_at DESC`. Это наблюдаемый web-путь, но он не доказывает, что вкладка «Новые серии» TV использует тот же preset. `updated_at` поддерживается как поле сортировки (230325), и есть fallback сортировок: если запрос с `kinopoisk_votes` или `updated_at` падает, web повторяет с `shikimori_votes` и тем же направлением (10401–10429). Не выдавать такую fallback-выдачу за достоверную хронологию появления серий.

Главная / топ: GET `/api/anime/main`, `/api/anime/top`, `/api/anime/top/films`, `/api/anime/top/season`; условные query `limit`, `offset`. Парсер принимает массив или объект с `results` (10670–10702). Персональные рекомендации — GET `/api/anime/for-you` с Bearer, `limit`, положительным `offset`, optional `force=1` (10490–10517).

Расписание — GET `/api/anime/schedule`, refresh-вариант `/api/anime/schedule?force=1` (10715–10745). Живой GET вернул 150 объектов. Пример формы:

```json
{"shikimori_id":65119,"name":"Maomao no Hitorigoto 3rd Season","russian":"Монолог Маомао 3","aired_on":"2026-10-05","episodes":12,"episodes_aired":0,"next_episode_at":"2026-10-05T06:00:00.000Z","next_episode":1,"status":"ongoing","poster_url":"/api/images/posters/small/shiki_65119.webp","is_premiere":true,"kind":"ona","anime_poster_url":"/api/images/posters/small/shiki_65119.webp"}
```

В этом sample **нет animetka_id**. Нельзя передавать shikimori_id в `/api/anime/{id}` как material id. Нужно штатное сопоставление, а не предположение о совпадении идентификаторов. Некоторые next_episode_at в текущем ответе относятся к прошлому: это серверные данные, не следует искусственно заменять даты.

## Жанры, студии и фильтры

GET `/api/anime/genres`: optional `query`, `limit`; параметр offset в текущем wrapper всегда null и не отправляется (10909–10937). Живой GET `?limit=3` вернул массив объектов `{id:79,name:"Выживание"}`.

GET `/api/anime/studios`: `limit`, `offset`, optional query, но текущий wrapper держит query=null и не отправляет (10963–10990). Живой GET `?limit=3&offset=0` вернул **массив строк**, первый `"100studio"`. Web дополнительно принимает object с name/title как fallback (45662–45666), но нельзя требовать ID у студии.

Расширенный search строится в `ctJ` (10363–10394):

- Scalar `name`.
- Повторяющиеся query-параметры `anime_genres`, `exclude_anime_genres`, `anime_studios`, `exclude_anime_studios`.
- Один или несколько `anime_kind`, `all_status` (при нескольких каждый передаётся отдельным query entry).
- `greater_year`, `lesser_year`, `greater_shikimori_rating`, `lesser_shikimori_rating`, `greater_episodes_total`, `lesser_episodes_total`, `greater_shikimori_votes`, `lesser_shikimori_votes`.
- Повторяющийся `rating_mpaa`.
- Случайная выдача `order=random`; иначе `order=<JSON string>`, например `[["id","DESC"]]`.
- `limit`, `offset`; repeated `attributes` для каждого из 17 полей карточки.

Пустые/null scalar и пустые элементы repeated списков не отправляются (aRd/aRc:84614-84625). Формы параметров наблюдаются статически; серверное AND/OR между несколькими жанрами, диапазоны и максимальные limits не установлены.

## Профиль и любимые персонажи

Все следующие запросы требуют штатной авторизованной сессии:

- GET `/api/user/profile/me` → profile (62969–62979).
- PATCH `/api/user/profile/me` с сериализатором aHH (63002–63012; форма ниже).
- POST `/api/user/profile/favorite-characters` JSON `{ "character_shikimori_id": <int> }` → полный profile (63086–63099).
- DELETE `/api/user/profile/favorite-characters/{character_shikimori_id}` → полный profile (63100–63110).

Список персонажей тайтла: GET `/api/anime/{material_id}/characters` (10748–10775). Живой GET `/api/anime/2778/characters` вернул 62 объекта; поля: `character_shikimori_id`, `name`, `russian`, `japanese`, `poster_url`, `roles_en`, `roles_ru`, `description`. Роли в ответе могут оставаться `Main` даже в roles_ru; description содержит теги `[character=196826]...[/character]`, а не готовый HTML.

Детали отдельного персонажа: GET `/api/anime/characters/{character_shikimori_id}` (10777–10802). **Разные пространства ID** для аниме и персонажа.

Profile response parser Bx (45680–45749) читает:

- `user_id`, `username`, `nickname`, `display_name`, `telegram_username`, `telegram_id`;
- `avatar_url`, `background_url`, `chat_wallpaper_url`, `bio`, `city`, `birthday`;
- `favorite_genres`, `favorite_voices`: массивы ID/name-элементов; сериализатор обновления сохраняет `.a` каждого элемента. Точные формы элементов входа нужно сверить через shared parser `cPB` перед сборкой формы редактирования.
- `favorite_characters`: `{character_shikimori_id,name,russian,poster_url}`; parser отбрасывает character ID<=0 (45667–45678).
- `links`: `{name,url}`.
- `private`: массив строк, **не bool**.
- `stats`: `{total,watching,completed,planned}`.
- `storage`: `{used_bytes,limit_bytes,free_bytes,ratio,voice_blocked,upload_blocked}`.
- `folders`, `friends_count`, `activity_visible`, `display_tag`, `display_tag_bg`, `display_tag_enabled`, `staff_badge_enabled`, `is_staff`, `is_vip`.

PATCH aHH (171880–171900) отправляет: nickname (trim, пустое→null), bio, city, birthday (`YYYY-MM-DD` либо null), favorite_genres, favorite_voices, links, private, display_tag, display_tag_bg, display_tag_enabled, staff_badge_enabled. Оно **не отправляет произвольную копию полного профиля**, user_id/telegram_id/is_vip и stats туда не входят.

## Папки / списки

GET `/api/user/folder` возвращает массив. Парсер `aTE` (9753–9770):

```json
{"id":12,"title":"Смотрю","color":"E921FF","is_default":false,"is_hidden":false,"anime_count":2,"AnimeHistories":[...]}
```

`AnimeHistories` регистрозависимо. Каждый элемент `d0x` (9728–9752) содержит историю и материал:

```json
{"id":321,"animetka_id":2778,"episode":3,"timestamp":120,"duration":1440,"tid":610,"translation":{"id":610,"title":"…"},"material":{"id":2778,"title":"…"}}
```

Fallback материала — весь элемент, если `material` отсутствует. material ID из animetka_id, затем material.animetka_id, затем material.id. Translation ID берётся из translation.id, затем tid. Не путать id записи истории с material ID.

Мутации (наблюдались только в статическом коде, не выполнялись):

- PUT `/api/user/folder`, `{title,color}` → folder (12159–12170; `aTY` -> aTZ -> diN -> crv, явный PUT:160517-160520).
- DELETE `/api/user/folder`, body `{folder_id}` (12171–12176).
- PATCH `/api/user/folder`, body `{folder_id, title?, color?, is_hidden?}` (12177–12192).
- POST `/api/user/folder/add`, `{folder_id,animetka_id}` (12193–12199).
- POST `/api/user/folder/delete`, `{folder_id,animetka_id}` (12200–12204).

Создание folder — PUT, а добавление материала — POST. Для is_default серверные ограничения удаления/переименования пока неизвестны. Отсутствующий AnimeHistories парсер превращает в [], а не делает дополнительный запрос содержимого; отдельный endpoint пагинации папки не установлен.

## Непроверенное

TV-defaults настроек, точный TV-путь «Новые серии», серверная логика фильтров, права на пользовательские мутации, свежесть профиля и поведение сохранения скрытых папок требуют живого теста с аккаунтом. Эти ветки не считаются готовыми на основании данного отчёта.

Дополнение по profile favorites: shared name-parser d43 (45659-45667) принимает строку либо объект с name/title и создаёт kh с именем. Сериализатор PATCH сохраняет поле .a этих моделей; поэтому нельзя самовольно заменять имена числовыми ID. Alias cPB не раскрыт непосредственно в минифицированном тексте; wire-форму необходимо подтвердить живым чтением профиля перед записью.
