import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animetka_tv/api.dart';
import 'package:animetka_tv/main.dart';
import 'package:animetka_tv/details.dart';
import 'package:animetka_tv/cinema.dart';
import 'package:animetka_tv/ui.dart';

import 'tv_ui_test.dart' show CatalogApi, ImageOverrides;

class CinemaApi extends CatalogApi {
  CinemaApi(super.catalog);
  @override
  Future<Json> detail(int id) async => {
    ...catalog.firstWhere((a) => animeId(a) == id, orElse: () => catalog.first),
    'franchise': [
      for (final a in catalog.take(2)) {'id': animeId(a), 'title': title(a)},
    ],
  };
  @override
  Future<Json> playlist(int id, [int? translation]) async => {
    'list': List.generate(
      22,
      (i) => {
        'title': i == 0 ? 'Преступный коэффициент' : 'Серия ${i + 1}',
        'image': scenery(
          catalog.firstWhere(
            (a) => animeId(a) == id,
            orElse: () => catalog.first,
          ),
        ),
      },
    ),
    'translations': [
      {'name': 'AniLibria', 'value': 1, 'selected': true},
    ],
  };
  @override
  Future<List<Json>> search(
    String name, {
    int offset = 0,
    Json filters = const {},
  }) async => catalog.take(2).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = Directory('test/fixtures/tv');
  final catalog = objects(
    jsonDecode(File('${fixture.path}/catalog.json').readAsStringSync()),
  );
  final urls = List<String>.from(
    jsonDecode(File('${fixture.path}/urls.json').readAsStringSync()),
  );
  final images = {
    for (var i = 0; i < urls.length; i++)
      urls[i]: File('${fixture.path}/$i.img').readAsBytesSync(),
  };
  for (final a in catalog) {
    final bytes = images[poster(a)];
    if (bytes != null) images.putIfAbsent(scenery(a), () => bytes);
  }
  late Session session;
  late CinemaApi api;
  setUp(() async {
    HttpOverrides.global = ImageOverrides(images);
    SharedPreferences.setMockInitialValues({'guest': true});
    api = CinemaApi(catalog);
    session = Session(await SharedPreferences.getInstance(), api);
  });
  tearDown(() {
    HttpOverrides.global = null;
  });
  Future<void> settle(WidgetTester t) async {
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> mount(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(() async {
      await (FontLoader('MJSans')
            ..addFont(rootBundle.load('assets/Roboto-Regular.ttf'))
            ..addFont(rootBundle.load('assets/Roboto-Medium.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    await t.pumpWidget(
      RepaintBoundary(key: const ValueKey('capture'), child: child),
    );
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (Platform.environment['UPDATE_CINEMA_PREVIEWS'] != '1') return;
    await t.runAsync(() async {
      final image = await t
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          )
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        Platform.environment['MJANIME_PREVIEW_DIR'] ??
            'test-output/previews/cinema',
      );
      dir.createSync(recursive: true);
      File('${dir.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyEvent(key);
    await settle(t);
  }

  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t);
  }

  test('Opening reorders history without changing saved episode or playback position', () async {
    final rows = [
      {
        'animetka_id': 1,
        'episode': 4,
        'timestamp': 754,
        'updated_at': '2026-01-01T12:00:00Z',
      },
      {
        'animetka_id': 2,
        'episode': 2,
        'timestamp': 5,
        'updated_at': '2026-01-02T12:00:00Z',
      },
    ];
    expect(session.recentHistory(rows).map(animeId), [2, 1]);
    await session.markOpened(1);
    final sorted = session.recentHistory(rows);
    expect(sorted.map(animeId), [1, 2]);
    expect(sorted.first['timestamp'], 754);
    expect(sorted.first['episode'], 4);
    final restored = Session(session.prefs, api);
    expect(restored.recentHistory(rows).map(animeId), [1, 2]);
  });
  test('History merges fresher local progress, removes duplicate titles and stably preserves undated order', () async {
    await session.prefs.setString(
      'history',
      jsonEncode([
        {
          'animetka_id': 1,
          'episode': 6,
          'timestamp': 300,
          'updated': '2026-01-03T12:00:00Z',
        },
      ]),
    );
    final sorted = session.recentHistory([
      {'animetka_id': 2},
      {'animetka_id': 1, 'episode': 1, 'updated_at': '2026-01-01T12:00:00Z'},
      {'animetka_id': 3},
    ]);
    expect(sorted.map(animeId), [1, 2, 3]);
    expect(sorted.first['episode'], 6);
  });
  testWidgets(
    'Remote scrolls through a lazy carousel and returns to its first card',
    (t) async {
      final items = List.generate(
        24,
        (i) => {'id': i + 1, 'title': 'Тайтл ${i + 1}'},
      );
      int? opened;
      await mount(
        t,
        MaterialApp(
          theme: mjTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 310,
                child: AnimeCarousel(
                  items: items,
                  onOpen: (a) => opened = animeId(a),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 23; i++) {
        await press(t, LogicalKeyboardKey.arrowRight);
      }
      await press(t, LogicalKeyboardKey.select);
      expect(opened, 24);
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scroll.position.pixels, greaterThan(0));
      for (var i = 0; i < 23; i++) {
        await press(t, LogicalKeyboardKey.arrowLeft);
      }
      await press(t, LogicalKeyboardKey.select);
      expect(opened, 1);
      expect(scroll.position.pixels, 0);
      await clean(t);
    },
  );
  testWidgets(
    'Native IME accepts search action, preserves cancelled draft and returns focus',
    (t) async {
      await mount(t, TvApp(session: session));
      await t.tap(find.byTooltip('Поиск'));
      await settle(t);
      await t.tap(find.text('Клавиатура'));
      await settle(t);
      expect(find.byType(TvSearchKeyboard), findsNothing);
      expect(t.testTextInput.isVisible, true);
      await t.enterText(find.byType(TextField), 'Фрирен');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await settle(t);
      expect(find.byType(NativeSearchDialog), findsNothing);
      expect(t.widget<TvTextEntry>(find.byType(TvTextEntry)).value, 'Фрирен');
      await t.tap(find.text('Клавиатура'));
      await settle(t);
      await t.enterText(find.byType(TextField), 'Психопаспорт');
      await t.binding.handlePopRoute();
      await settle(t);
      expect(
        t.widget<TvTextEntry>(find.byType(TvTextEntry)).value,
        'Психопаспорт',
      );
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await clean(t);
    },
  );
  testWidgets(
    'Rail navigation leaves nested seasons and opens the requested shell section',
    (t) async {
      await mount(t, TvApp(session: session));
      await t.tap(find.text('Открыть тайтл'));
      await settle(t);
      await t.tap(find.text('Сезоны'));
      await settle(t);
      await t.tap(
        find
            .descendant(
              of: find.byType(AnimeCard).first,
              matching: find.byType(InkWell),
            )
            .first,
      );
      await settle(t);
      expect(find.byType(DetailsScreen, skipOffstage: false), findsNWidgets(2));
      await t.tap(find.byTooltip('Поиск'));
      await settle(t);
      expect(find.byType(DetailsScreen), findsNothing);
      expect(find.text('Поиск аниме'), findsOneWidget);
      await clean(t);
    },
  );

  test('Banner candidates stay within the title and skip empty artwork', () {
    expect(
      sceneryImages({
        'banner_url': '  ',
        'screenshots': [
          '',
          {'url': '/own-shot.jpg'},
        ],
        'anime_poster_url': '',
        'poster_url': '/own-poster.jpg',
      }),
      ['/own-shot.jpg', '/own-poster.jpg'],
    );
    expect(
      sceneryImages({
        'banner_url': '/own-banner.jpg',
        'screenshots': ['/own-shot.jpg'],
        'poster_url': '/own-poster.jpg',
      }),
      ['/own-banner.jpg', '/own-shot.jpg', '/own-poster.jpg'],
    );
    expect(sceneryImages({}), isEmpty);
  });

  testWidgets(
    'Home uses the focused history title even when it is absent from the catalog',
    (t) async {
      final ownPoster = poster(catalog[1]);
      await session.prefs.setString(
        'history',
        jsonEncode([
          {
            'animetka_id': 987654,
            'material': {
              'id': 987654,
              'title': 'Другой тайтл без баннера',
              'anime_poster_url': '',
              'poster_url': ownPoster,
            },
            'episode': 2,
            'timestamp': 30,
            'duration': 1440,
          },
        ]),
      );
      await mount(t, TvApp(session: session));
      final card = find.byWidgetPredicate(
        (w) => w is AnimeCard && animeId(w.anime) == 987654,
      );
      Focus.of(
        t.element(
          find.descendant(of: card, matching: find.byType(InkWell)).first,
        ),
      ).requestFocus();
      await settle(t);
      final hero = find.byKey(const ValueKey('home-hero'));
      expect(
        find.descendant(
          of: hero,
          matching: find.text('Другой тайтл без баннера'),
        ),
        findsOneWidget,
      );
      final image = t.widget<Image>(
        find.descendant(of: hero, matching: find.byType(Image)).first,
      );
      final provider = image.image is ResizeImage
          ? (image.image as ResizeImage).imageProvider
          : image.image;
      expect((provider as NetworkImage).url, absolute(ownPoster));
      expect(find.byKey(const ValueKey('hero-bottom-blend')), findsOneWidget);
      final catalogCard = find
          .descendant(
            of: find.byKey(const ValueKey('home-catalog')),
            matching: find.byType(AnimeCard),
          )
          .at(1);
      Focus.of(
        t.element(
          find
              .descendant(of: catalogCard, matching: find.byType(InkWell))
              .first,
        ),
      ).requestFocus();
      await settle(t);
      final scroll = t.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('home-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(0);
      await settle(t);
      expect(
        find.descendant(of: hero, matching: find.text(title(catalog[1]))),
        findsOneWidget,
      );
      await clean(t);
    },
  );

  testWidgets(
    'Broken banner tries its own poster and empty artwork has a neutral placeholder',
    (t) async {
      final bad = 'https://fixtures.invalid/broken-banner.jpg';
      final good = poster(catalog[1]);
      images[bad] = Uint8List(0);
      addTearDown(() => images.remove(bad));
      await mount(
        t,
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: photo(bad, fallbacks: [good]),
            ),
          ),
        ),
      );
      expect(find.byKey(ValueKey(good)), findsOneWidget);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: photo(''))));
      await settle(t);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await clean(t);
    },
  );

  testWidgets(
    'Category activation preserves neighbouring tab bounds and remote focus',
    (t) async {
      await session.prefs.setString(
        'history',
        jsonEncode([
          {
            'animetka_id': animeId(catalog.first),
            'material': catalog.first,
            'episode': 3,
            'timestamp': 239,
            'duration': 1440,
          },
        ]),
      );
      await mount(t, TvApp(session: session));
      final names = ['Подборка', 'Рекомендации', 'Топ', 'Фильмы', 'Онгоинги'];
      Finder button(String name) => find.widgetWithText(TvButton, name);
      final top = button('Топ');
      await t.ensureVisible(top);
      Focus.of(
        t.element(
          find.descendant(of: top, matching: find.byType(InkWell)).first,
        ),
      ).requestFocus();
      await settle(t);
      final before = [for (final name in names) t.getRect(button(name))];
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 16));
        for (var j = 0; j < names.length; j++) {
          expect(
            t.getRect(button(names[j])),
            before[j],
            reason: 'Category layout moved during selection',
          );
        }
      }
      await settle(t);
      expect(find.byKey(const ValueKey('home-catalog')), findsOneWidget);
      expect(
        Focus.of(
          t.element(
            find.descendant(of: top, matching: find.byType(InkWell)).first,
          ),
        ).hasFocus,
        isTrue,
      );
      await press(t, LogicalKeyboardKey.arrowRight);
      await press(t, LogicalKeyboardKey.select);
      for (var j = 0; j < names.length; j++) {
        expect(t.getRect(button(names[j])), before[j]);
      }
      await clean(t);
    },
  );

  testWidgets(
    'Cinematic screens render with real offline artwork; episode numbers survive reverse order',
    (t) async {
      final now = DateTime.now().toUtc();
      await session.prefs.setString(
        'history',
        jsonEncode([
          for (var i = 0; i < 4; i++)
            {
              'animetka_id': animeId(catalog[i]),
              'material': catalog[i],
              'episode': i + 3,
              'timestamp': 239 + i * 80,
              'duration': 1440,
              'updated': now.subtract(Duration(days: i)).toIso8601String(),
            },
        ]),
      );
      await mount(t, TvApp(session: session));
      await shot(t, '01-home');
      await t.tap(find.byTooltip('Продолжить'));
      await settle(t);
      await shot(t, '02-history');
      final first = find
          .descendant(
            of: find.byType(AnimeCard).first,
            matching: find.byType(InkWell),
          )
          .first;
      Focus.of(t.element(first)).requestFocus();
      await settle(t);
      await press(t, LogicalKeyboardKey.select);
      expect(find.byType(DetailsScreen), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('Серия 1 · Преступный коэффициент'), findsOneWidget);
      expect(t.getBottomRight(find.text('Серия 6')).dy, lessThanOrEqualTo(700));
      final episode = find
          .descendant(
            of: find.byKey(const ValueKey('episode-3')),
            matching: find.byType(InkWell),
          )
          .first;
      Focus.of(t.element(episode)).requestFocus();
      await settle(t);
      await shot(t, '03-episodes');
      expect(find.text('С первой серии'), findsNothing);
      final restart = find.byTooltip('С первой серии');
      expect(
        t.getTopLeft(restart).dy,
        lessThan(t.getTopLeft(find.text('Серии')).dy),
      );
      final voice = find.byTooltip('Озвучка');
      expect(
        (t.getCenter(voice).dy - t.getCenter(find.text('Сначала старые')).dy)
            .abs(),
        lessThan(2),
      );
      final voiceLabel = find.descendant(
        of: voice,
        matching: find.text('AniLibria'),
      );
      final voiceArrow = find.descendant(
        of: voice,
        matching: find.byIcon(Icons.expand_more_rounded),
      );
      expect(
        t.getTopLeft(voiceArrow).dx - t.getTopRight(voiceLabel).dx,
        closeTo(8, .01),
      );
      final voiceControl = find
          .descendant(of: voice, matching: find.byType(InkWell))
          .first;
      Focus.of(t.element(voiceControl)).requestFocus();
      await settle(t);
      await press(t, LogicalKeyboardKey.select);
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(Focus.of(t.element(voiceControl)).hasFocus, isTrue);
      await press(t, LogicalKeyboardKey.arrowRight);
      await press(t, LogicalKeyboardKey.select);
      await settle(t);
      expect(find.text('22'), findsOneWidget);
      await shot(t, '04-episodes-reversed');
      await t.binding.handlePopRoute();
      await settle(t);
      await t.tap(find.byTooltip('Поиск'));
      await settle(t);
      await t.tap(find.text('Клавиатура'));
      await settle(t);
      await t.enterText(find.byType(TextField), 'Фрирен');
      await shot(t, '05-native-search-field');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await settle(t);
      await shot(t, '06-search');
      await t.tap(find.byTooltip('Настройки'));
      await settle(t);
      await t.scrollUntilVisible(find.text('Сменить тему'), 250);
      await settle(t);
      await t.ensureVisible(find.text('Сменить тему'));
      await settle(t);
      await t.tap(find.text('Сменить тему'));
      await settle(t);
      await t.tap(find.byTooltip('Главная'));
      await settle(t);
      await shot(t, '07-home-light');
      await clean(t);
    },
  );
}
