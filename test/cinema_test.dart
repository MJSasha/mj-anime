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
      await t.tap(find.text('Сначала старые'));
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
