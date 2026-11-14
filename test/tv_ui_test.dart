import 'dart:async';
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
import 'package:animetka_tv/ui.dart';
import 'package:animetka_tv/tv_playback.dart';

class CatalogApi extends Api {
  final List<Json> catalog;
  final List<String> requested = [];
  CatalogApi(this.catalog);
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? query,
    dynamic body,
    bool auth = false,
  }) async {
    requested.add(path);
    return catalog;
  }

  @override
  Future<Json> detail(int id) async => catalog.first;
  @override
  Future<Json> playlist(int id, [int? translation]) async => {
    'list': List.generate(
      28,
      (i) => {
        'title': 'Серия ${i + 1}',
        'image': catalog.first['screenshots'][0],
      },
    ),
    'translations': [
      {'name': 'AniLibria', 'value': 1, 'selected': true},
      {'name': 'StudioBand', 'value': 2},
    ],
  };
}

class ImageClient extends Fake implements HttpClient {
  final Map<String, List<int>> images;
  ImageClient(this.images);
  @override
  set autoUncompress(bool value) {}
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      ImageRequest(images[url.toString()] ?? images.values.first);
  @override
  void close({bool force = false}) {}
}

class ImageRequest extends Fake implements HttpClientRequest {
  final List<int> bytes;
  ImageRequest(this.bytes);
  @override
  HttpHeaders get headers => ImageHeaders();
  @override
  Future<HttpClientResponse> close() async => ImageResponse(bytes);
}

class ImageHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  final List<int> bytes;
  ImageResponse(this.bytes);
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageOverrides extends HttpOverrides {
  final Map<String, List<int>> images;
  ImageOverrides(this.images);
  @override
  HttpClient createHttpClient(SecurityContext? context) => ImageClient(images);
}

void main() {
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
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['UPDATE_TV_PREVIEWS'] != '1') return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        Platform.environment['MJANIME_PREVIEW_DIR'] ??
            'test-output/previews/tv',
      );
      dir.createSync(recursive: true);
      File('${dir.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> fonts(WidgetTester tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('MJSans')
        ..addFont(rootBundle.load('assets/Roboto-Regular.ttf'))
        ..addFont(rootBundle.load('assets/Roboto-Medium.ttf'));
      await loader.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }

  for (final size in [
    const Size(1280, 720),
    const Size(1920, 1080),
    const Size(3840, 2160),
  ]) {
    testWidgets(
      'TV catalog and detail layout at ${size.width.toInt()} with no schedule or new episodes',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        HttpOverrides.global = ImageOverrides(images);
        addTearDown(() => HttpOverrides.global = null);
        await fonts(tester);
        SharedPreferences.setMockInitialValues({'guest': true});
        final api = CatalogApi(catalog);
        final session = Session(await SharedPreferences.getInstance(), api);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture'),
            child: TvApp(session: session),
          ),
        );
        await settle(tester);
        expect(find.text('Расписание'), findsNothing);
        expect(find.text('Новые серии'), findsNothing);
        expect(api.requested, ['/api/anime/main']);
        expect(tester.takeException(), isNull);
        if (size.width == 1920) await capture(tester, 'mjanime-home');
        if (size.width == 1920) {
          await session.prefs.setString(
            'history',
            jsonEncode([
              {'animetka_id': 2778, 'episode': 7, 'timestamp': 754, 'tid': 1},
            ]),
          );
        }
        // The first library card opens with the remote, without an extra Watch action.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await settle(tester);
        expect(find.text('В список'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (size.width == 1920) {
          await capture(tester, 'mjanime-details');
          await tester.tap(find.text('Назад'));
          await settle(tester);
          await tester.tap(find.byTooltip('Настройки'));
          await settle(tester);
          await capture(tester, 'mjanime-settings');
          await tester.scrollUntilVisible(find.text('Сменить тему'), 250);
          await settle(tester);
          await tester.tap(find.text('Сменить тему'));
          await settle(tester);
          await tester.tap(find.byTooltip('Главная'));
          await settle(tester);
          await capture(tester, 'mjanime-home-light');
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      },
    );
  }

  testWidgets(
    'Remote timeline previews, accelerates, commits, clamps and cancels',
    (tester) async {
      final key = GlobalKey<TvSeekBarState>();
      final seeks = <Duration>[];
      final states = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvSeekBar(
              key: key,
              position: const Duration(seconds: 50),
              duration: const Duration(seconds: 100),
              onSeek: seeks.add,
              onScrub: states.add,
            ),
          ),
        ),
      );
      key.currentState!.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(seeks, isEmpty);
      expect(key.currentState!.draft, 60000);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(seeks, [const Duration(seconds: 60)]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(seeks.length, 1);
      expect(key.currentState!.draft, isNull);
      for (var i = 0; i < 30; i++) {
        key.currentState!.nudge(1);
      }
      expect(key.currentState!.draft, 100000);
      key.currentState!.finish();
      expect(seeks.last, const Duration(seconds: 100));
      key.currentState!.nudge(-1);
      key.currentState!.focusNode.unfocus();
      await tester.pump();
      expect(key.currentState!.draft, isNull);
      expect(states.last, false);
      expect(tester.takeException(), isNull);
    },
  );
  test('Timeline formats hours correctly', () {
    expect(playbackTime(const Duration(seconds: 3661)), '1:01:01');
  });
  testWidgets('Player controls fit TV and remote selects pause', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await fonts(tester);
    var toggled = false;
    int? panel;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: mjTheme(),
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(images[urls.last]!, fit: BoxFit.cover),
                TvPlaybackControls(
                  title: 'Фрирен: путешествие продолжается',
                  episode: 7,
                  count: 28,
                  quality: '1080',
                  speed: 1,
                  position: const Duration(minutes: 12, seconds: 34),
                  duration: const Duration(minutes: 24),
                  playing: true,
                  onBack: () {},
                  onToggle: () => toggled = true,
                  onInteraction: () {},
                  onPanel: (v) => panel = v,
                  onSeek: (_) {},
                  onScrub: (_) {},
                  onPrevious: () {},
                  onNext: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await capture(tester, 'mjanime-player');
    if (Platform.environment['UPDATE_TV_PREVIEWS'] == '1') {
      final action = FocusNode(), dismiss = FocusNode();
      final overlay = Overlay.of(
        tester.element(find.byType(TvPlaybackControls)),
      );
      final entry = OverlayEntry(
        builder: (_) => Positioned(
          right: 42,
          bottom: 285,
          child: Material(
            type: MaterialType.transparency,
            child: TvEpisodePrompt(
              nextEpisode: 8,
              seconds: 10,
              onAction: () {},
              onDismiss: () {},
              onControls: () {},
              actionFocus: action,
              dismissFocus: dismiss,
            ),
          ),
        ),
      );
      overlay.insert(entry);
      await settle(tester);
      await capture(tester, 'mjanime-next-episode');
      entry.remove();
      await settle(tester);
      action.dispose();
      dismiss.dispose();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(toggled, true);
    await tester.tap(find.byTooltip('Озвучка'));
    await tester.pump();
    expect(panel, 1);
  });
  test('MJAnime uses the MJReader semantic colors and shared type', () {
    final dark = mjTheme(), light = mjTheme(light: true);
    expect(dark.colorScheme.primary.toARGB32(), 0xffc7ff68);
    expect(dark.scaffoldBackgroundColor.toARGB32(), 0xff0c0e15);
    expect(dark.colorScheme.surfaceContainerLow.toARGB32(), 0xff191e29);
    expect(light.colorScheme.primary.toARGB32(), 0xff345a05);
    expect(light.scaffoldBackgroundColor.toARGB32(), 0xfffafaf7);
    expect(dark.textTheme.bodyMedium!.fontFamily, 'MJSans');
  });
  testWidgets('MJAnime TV banner has the launcher dimensions and brand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await fonts(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: mjTheme(),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  const Icon(
                    Icons.play_circle_outline_rounded,
                    size: 52,
                    color: accent,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MJ / ANIME',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2,
                            color: accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'MJAnime',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Аниме на большом экране',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('MJAnime'), findsOneWidget);
    await capture(tester, 'mjanime-tv-banner');
  });
}
