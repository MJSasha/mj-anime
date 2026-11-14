> Архив прежней рабочей сессии, сохранённый 14.11.2026. Это историческое свидетельство, не текущая инструкция. Начинать с [AGENTS.md](../../AGENTS.md). Старые локальные пути и относительные ссылки могут не существовать в новом checkout.

# MJAnime 1.7.0 — design QA

Source visual truth: /Users/bloba/Documents/Codex/2026-11-13/new-chat/outputs/mjanime-mockups-20261114/02-cinema.png; последующие инструкции пользователя: убрать подписи в левом меню, баннер без скруглённой карточки, затемнение только внизу слева.

Implementation screenshots: /Users/bloba/Documents/Codex/2026-11-13/new-chat/outputs/mjanime-1.7.0/01-home.png, 02-history.png, 03-episodes.png, 06-search.png, 07-home-light.png. Native installed-APK evidence: 08-android-ime.png, 09-ime-submitted.png, android-ime-state.txt, apk-verification.json.

Viewport: Flutter 1280×720 logical/pixel, DPR 1; TV root scales to 1920×1080. Source board 1672×941, four approximately 836×470 TV frames. Comparisons normalize each 1280×720 capture proportionally to its source quadrant, without stretching. Native emulator capture 1920×1080, Android 11/API 30.

State: dark home with continue shelf, dark history first card focused, detail episode 3 focused, search results; light home separately. Mock content is illustrative: real title names and server images differ. Offline captures use stored artwork and API fixtures; cached posters stand in for unavailable scene URLs for the same title. Native keyboard is OS-owned, not emulated in the widget screenshots; its actual appearance is evidenced separately in the installed APK with network disabled.

Full-view comparison evidence: compare-01-home.jpg, compare-02-history.jpg, compare-03-episodes.jpg, compare-06-search.jpg in the screenshot directory. Focused comparison evidence: compare-episode-focus.jpg shows the constant number badge, readable caption and focus outline. The source and implementation are combined in each comparison input.

## Comparison history and fixes

- P1: initial banner was a rounded, globally dimmed card. Removed container shape and upper category row; image now reaches the content edges, heading is above and title enlarged. After the user's clarification, replaced broad horizontal/vertical masks with one clipped elliptical gradient under the lower-left controls. Post-fix: 01-home.png / compare-01-home.jpg.
- P2: autofocus scrolled a visible hero out of view; reverse carousel navigation failed. Reveal either edge only when necessary, suppress deferred scroll after focus changes. Post-fix: full hero capture, automated 24-title round trip.
- P2: lower episode row clipped and long voice names overflowed. Adjusted the grid, bounded voice text and allowed control wrapping; all six initial numbers/captions fit. Post-fix: 03-episodes.png and viewport-coordinate assertions.
- P2: initial history cards had square images; fixed shelf height restores wide stills. Post-fix: 02-history.png.
- P2: text labels in the rail departed from the selected image. Removed labels everywhere; retained tooltips/accessibility names. Post-fix: all current captures and explicit no-label regression.
- P2: side navigation from nested seasons could return to the wrong page. Forwarded the shell callback through seasons and collections, pop to shell before selecting section. Post-fix: nested-season navigation regression.

## Required fidelity surfaces

- Fonts/typography: existing licensed Roboto family, regular/medium weights; large hero title, readable episode numbers, bounded captions and metadata. Unsupported text-star glyph replaced by real Material icon.
- Spacing/layout: compact icon rail, edge-to-edge background hero, horizontal shelves, three episode columns; no retained layout overflow in either theme. Category controls and existing detail tabs remain accessible below the first home shelf / in their original feature grouping.
- Colors/tokens: MJReader dark/light theme tokens and lime focus. Local lower-left darkening follows the user's latest instruction; remaining image is not globally dimmed. Selected navigation tone differs from current focus.
- Image quality/assets: real catalog artwork, sized decoding and lazy card construction; no generated mock image substituted for working UI. Per-title scene/poster fallback remains data-driven.
- Copy/content: real titles retained, permanent series number plus title; history recency separate from playback seconds. Native Search action and cancelled draft tested. Existing filters, voice, lists, related seasons and player retained.

## Validation and limits

89 offline Flutter tests passed; flutter analyze clean. Final signed APK c9f4d4804761fa9219f201d938e7532466a3ed303d82b4497cd74c8502d02527 tested in isolated Android 11: all video modes with local 720p clip, moving frames, one ExoPlayer per launch and native CNN status; real system IME visible, test query submitted. Native keyboard styling differs by installed IME. Live catalog/account synchronization and projector performance were not tested. Projector was not accessed.

No remaining actionable P0/P1/P2 differences in the requested redesign. P3 follow-up: artwork composition varies with the available server image; precise font/image matching to illustrative mock data is not claimed. Existing offline network-error wording is outside the selected normal-state design.

Implementation checklist: selected composition implemented; supplied label/banner corrections applied; directional focus and long-OK checked; keyboard is OS-owned; signed exact APK verified; evidence saved.

final result: passed
