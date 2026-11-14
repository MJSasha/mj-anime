import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animetka_tv/api.dart';
import 'package:animetka_tv/anime_upscale.dart';
import 'package:animetka_tv/auth.dart';
import 'package:animetka_tv/details.dart';
import 'package:animetka_tv/filters.dart';
import 'package:animetka_tv/main.dart';
import 'package:animetka_tv/ui.dart';
import 'package:animetka_tv/player.dart';
import 'package:animetka_tv/tv_playback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Every video, HTTP response and native method is replaced; no device or socket.
class OfflineVideo extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  final sources = <String>[];
  final playing = <int, bool>{};
  int builds = 0;
  Duration initializeDelay = Duration.zero;
  int failInitializations = 0;
  int zeroSizeInitializations = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = streams.length;
    final stream = StreamController<VideoEvent>();
    streams[id] = stream;
    sources.add(options.dataSource.uri ?? 'asset:${options.dataSource.asset}');
    final size = zeroSizeInitializations > 0
        ? Size.zero
        : const Size(1920, 1080);
    if (zeroSizeInitializations > 0) zeroSizeInitializations--;
    final initialized = VideoEvent(
      eventType: VideoEventType.initialized,
      size: size,
      duration: const Duration(minutes: 24),
    );
    if (failInitializations > 0) {
      failInitializations--;
      stream.addError(
        PlatformException(
          code: 'VideoError',
          message: 'GPU video output failed',
        ),
      );
    } else if (initializeDelay == Duration.zero) {
      stream.add(initialized);
    } else {
      Timer(initializeDelay, () {
        if (!stream.isClosed) stream.add(initialized);
      });
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    await streams[playerId]?.close();
  }

  @override
  Future<void> play(int playerId) async {
    playing[playerId] = true;
  }

  @override
  Future<void> pause(int playerId) async {
    playing[playerId] = false;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
  @override
  Widget buildView(int playerId) {
    builds++;
    return const ColoredBox(color: Color(0xff141e2b));
  }
}

class OfflineHttp extends HttpOverrides {
  final urls = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) => StubClient(urls);
}

class StubClient extends Fake implements HttpClient {
  final List<String> urls;
  StubClient(this.urls);
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (url.host != 'example.invalid') {
      throw StateError('Unexpected network attempt: $url');
    }
    urls.add('$url');
    return StubRequest();
  }

  @override
  void close({bool force = false}) {}
}

class StubRequest extends Fake implements HttpClientRequest {
  @override
  HttpHeaders get headers => StubHeaders();
  @override
  set followRedirects(bool value) {}
  @override
  Future<HttpClientResponse> close() async {
    return StubResponse();
  }
}

class StubHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => null;
}

class StubResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  HttpHeaders get headers => StubHeaders();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => StubSubscription();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StubSubscription extends Fake implements StreamSubscription<List<int>> {
  @override
  Future<void> cancel() async {}
}

class NavigationApi extends Api {
  final calls = <String>[];
  final voices = <int?>[];
  Json skipdata = {};
  final anime = <String, dynamic>{
    'id': 1,
    'title': 'Первый сезон',
    'year': 2024,
    'episodes_total': 28,
    'franchise': [
      {'id': 1, 'title': 'Первый сезон'},
      {'id': 2, 'title': 'Второй сезон', 'year': 2025},
    ],
  };
  @override
  Future<Json> detail(int id) async {
    calls.add('detail:$id');
    return id == 1 ? anime : {...anime, 'id': 2, 'title': 'Второй сезон'};
  }

  @override
  Future<Json> playlist(int id, [int? translation]) async {
    voices.add(translation);
    return {
      'list': List.generate(
        28,
        (i) => {
          'file':
              '[720]https://example.invalid/$id/${i + 1}.m3u8,[1080]https://example.invalid/$id/${i + 1}-hd.m3u8',
          'title': 'Серия ${i + 1}',
          'skipdata': skipdata,
        },
      ),
      'translations': [
        {
          'value': 7,
          'name': 'Первая озвучка',
          'selected': translation == null || translation == 7,
        },
        {'value': 8, 'name': 'Вторая озвучка', 'selected': translation == 8},
      ],
    };
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? query,
    dynamic body,
    bool auth = false,
  }) async {
    calls.add(path);
    if (path.contains('genres')) {
      return [
        {'name': 'Приключения'},
      ];
    }
    if (path.contains('studios')) return ['Studio A'];
    if (path.contains('characters')) return <Json>[];
    if (path.contains('screenshots')) return {'items': []};
    return [anime];
  }

  @override
  Future<List<Json>> search(
    String name, {
    int offset = 0,
    Json filters = const {},
  }) async => [anime];
}

void main() {
  late OfflineVideo video;
  late NavigationApi api;
  late Session session;
  final native = <String>[];
  final upscaleCalls = <String>[];
  var rejectUpscale = false;
  setUp(() async {
    HttpOverrides.global = OfflineHttp();
    video = OfflineVideo();
    VideoPlayerPlatform.instance = video;
    SharedPreferences.setMockInitialValues({'guest': true});
    api = NavigationApi();
    session = Session(await SharedPreferences.getInstance(), api);
    native.clear();
    upscaleCalls.clear();
    rejectUpscale = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoUpscale.channel, (call) async {
          if (call.method != 'setMode' ||
              !upscaleModes.contains(call.arguments)) {
            throw StateError('Unexpected upscale call');
          }
          upscaleCalls.add(call.arguments as String);
          if (rejectUpscale && call.arguments != 'off') {
            throw PlatformException(code: 'unsupported');
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          native.add(call.method);
          if (call.method == 'appVersion') return '1.5.0';
          if (call.method != 'setKeepScreenOn') {
            throw StateError('Unexpected native method: ${call.method}');
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoUpscale.channel, null);
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
    expect(
      native.every((m) => m == 'setKeepScreenOn' || m == 'appVersion'),
      true,
    );
  });
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    // A playing controller schedules periodic frames; bounded pumping is intentional.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> focusText(WidgetTester tester, String text) async {
    if (text == 'Продолжить' &&
        find.byType(DetailsScreen).evaluate().isNotEmpty) {
      final button = find.byWidgetPredicate(
        (w) => w is TvButton && w.focusNode?.debugLabel == 'Detail playback',
      );
      final ink = find
          .descendant(of: button, matching: find.byType(InkWell))
          .first;
      Focus.of(tester.element(ink)).requestFocus();
      await settle(tester);
      return;
    }
    final textButtons = find.ancestor(
      of: find.text(text),
      matching: find.byType(InkWell),
    );
    final ink = textButtons.evaluate().isNotEmpty
        ? textButtons.first
        : find
              .descendant(
                of: find.byTooltip(text),
                matching: find.byType(InkWell),
              )
              .first;
    Focus.of(tester.element(ink)).requestFocus();
    await settle(tester);
  }

  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> launchPlayer(
    WidgetTester tester, {
    int index = 0,
    bool waitForRecovery = false,
  }) async {
    viewport(tester);
    expect(
      HttpClient(),
      isA<StubClient>(),
      reason: '${HttpOverrides.current.runtimeType}',
    );
    final playlist = await api.playlist(1);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    session: session,
                    anime: api.anime,
                    playlist: playlist,
                    index: index,
                  ),
                ),
              ),
              child: const Text('Root'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Root'));
    await settle(tester);
    expect(find.byType(TvPlaybackControls), findsOneWidget);
    expect(
      video.sources,
      isNotEmpty,
      reason: 'The offline video platform must receive the source',
    );
    if (waitForRecovery) {
      await settle(tester);
      await settle(tester);
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  Future<void> position(WidgetTester tester, int seconds) async {
    video.positions[video.streams.length - 1] = Duration(seconds: seconds);
    await tester.pump(const Duration(milliseconds: 250));
    await settle(tester);
  }

  testWidgets(
    'History opens details; remote resumes exact episode, time and voice; seasons remain accessible',
    (tester) async {
      viewport(tester);
      await session.prefs.setString(
        'history',
        jsonEncode([
          {
            'animetka_id': 1,
            'material': api.anime,
            'episode': 4,
            'timestamp': 754,
            'tid': 8,
          },
        ]),
      );
      await tester.pumpWidget(TvApp(session: session));
      await settle(tester);
      await focusText(tester, 'Продолжить');
      await press(tester, LogicalKeyboardKey.select);
      await focusText(tester, 'Первый сезон');
      final historyFocus = FocusManager.instance.primaryFocus;
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(DetailsScreen), findsOneWidget);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.text('Серия 4 · 12:34'), findsOneWidget);
      expect(api.voices.last, 8);
      await focusText(tester, 'Сезоны');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Второй сезон'), findsOneWidget);
      await focusText(tester, 'Второй сезон');
      await press(tester, LogicalKeyboardKey.select);
      expect(api.calls, contains('detail:2'));
      expect(find.byType(DetailsScreen, skipOffstage: false), findsNWidgets(2));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(DetailsScreen, skipOffstage: false), findsOneWidget);
      await focusText(tester, 'Продолжить');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(
        video.sources.single,
        contains('/1/4-hd.m3u8'),
      ); // default chooses last quality
      expect(video.positions.values.single, const Duration(seconds: 754));
      await position(tester, 300);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        find.byType(PlayerScreen),
        findsNothing,
        reason: 'Back leaves player',
      );
      expect(find.text('Серия 4 · 5:00'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Detail playback');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        find.byType(DetailsScreen),
        findsNothing,
        reason: 'Next Back leaves details',
      );
      expect(FocusManager.instance.primaryFocus, same(historyFocus));
      await cleanup(tester);
    },
  );

  testWidgets(
    'Player every arrow path, boundaries, seek cancel and disabled previous preserve focus',
    (tester) async {
      await launchPlayer(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Rewind');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Rewind',
      ); // disabled previous skipped
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Timeline');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        tester.state<TvSeekBarState>(find.byType(TvSeekBar)).draft,
        isNotNull,
      );
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(
        tester.state<TvSeekBarState>(find.byType(TvSeekBar)).draft,
        isNull,
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      for (var i = 0; i < 8; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Upscale panel');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Timeline');
      await cleanup(tester);
    },
  );

  testWidgets(
    'Panels trap focus, stay visible past timeout and restore the exact opener after Back',
    (tester) async {
      await launchPlayer(tester, index: 3);
      for (var tab = 0; tab < 3; tab++) {
        for (var i = 0; i < 3 + tab; i++) {
          await press(tester, LogicalKeyboardKey.arrowRight);
        }
        final opener = FocusManager.instance.primaryFocus;
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text('Ваш просмотр'), findsOneWidget);
        for (final key in [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowRight,
        ]) {
          await press(tester, key);
          final focus = FocusManager.instance.primaryFocus!;
          expect(focus, isNot(isA<FocusScopeNode>()));
          expect(ModalRoute.of(focus.context!)!.isCurrent, true);
        }
        await tester.pump(const Duration(seconds: 8));
        await settle(tester);
        expect(find.byType(TvPlaybackControls), findsOneWidget);
        expect(FocusManager.instance.primaryFocus, isNotNull);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(FocusManager.instance.primaryFocus, same(opener));
        final controls = tester.state<TvPlaybackControlsState>(
          find.byType(TvPlaybackControls),
        );
        controls.focusPlay();
        await settle(tester);
      }
      await cleanup(tester);
    },
  );

  testWidgets(
    'Last episode opens the list at the current item and skips disabled Next',
    (tester) async {
      await launchPlayer(tester, index: 27);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Forward');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Episodes panel');
      await press(tester, LogicalKeyboardKey.select);
      final current = find.text('Серия 28');
      expect(current, findsOneWidget);
      final ink = find
          .ancestor(of: current, matching: find.byType(InkWell))
          .first;
      expect(Focus.of(tester.element(ink)).hasFocus, true);
      expect(
        ModalRoute.of(FocusManager.instance.primaryFocus!.context!)!.isCurrent,
        true,
      );
      await cleanup(tester);
    },
  );

  testWidgets(
    'Auto-hide hands focus to surface; OK pauses and restores play; updates never rebuild video surface',
    (tester) async {
      await launchPlayer(tester);
      final built = video.builds;
      for (var i = 0; i < 8; i++) {
        video.positions[0] = Duration(seconds: i);
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(video.builds, built);
      await tester.pump(const Duration(seconds: 7));
      await settle(tester);
      expect(find.byType(TvPlaybackControls), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Playback surface',
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(video.playing[0], false);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Root'), findsOneWidget);
      await cleanup(tester);
    },
  );

  testWidgets(
    'Episode, voice and quality switches restore focus and retain position',
    (tester) async {
      await launchPlayer(tester, index: 3);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      expect(video.sources.last, contains('/1/5-hd.m3u8'));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      video.positions[video.streams.length - 1] = const Duration(seconds: 120);
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      await press(tester, LogicalKeyboardKey.select);
      await focusText(tester, 'Вторая озвучка');
      await press(tester, LogicalKeyboardKey.select);
      expect(api.voices.last, 8);
      expect(
        video.positions[video.streams.length - 1],
        const Duration(seconds: 120),
      );
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      await press(tester, LogicalKeyboardKey.select);
      await focusText(tester, '720p');
      await press(tester, LogicalKeyboardKey.select);
      expect(video.sources.last, endsWith('/1/5.m3u8'));
      expect(
        video.positions[video.streams.length - 1],
        const Duration(seconds: 120),
      );
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      await cleanup(tester);
    },
  );
  test('Saved history contains display metadata rather than entire franchise graphs', () async {
    await session.progress(
      {...api.anime, 'description': 'x' * 10000},
      4,
      120,
      1440,
      8,
    );
    final material = object(session.localHistory.single['material']);
    expect(material['title'], 'Первый сезон');
    expect(material.containsKey('franchise'), false);
    expect(material.containsKey('description'), false);
    expect(session.prefs.getString('history')!.length, lessThan(600));
  });

  testWidgets(
    'Opening skip uses markers, keeps paused state and restores focus',
    (tester) async {
      api.skipdata = {
        'opening': {'start': 30, 'stop': 110},
      };
      await launchPlayer(tester);
      await position(tester, 40);
      expect(find.text('Пропустить опенинг'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(video.playing[0], false);
      await focusText(tester, 'Пропустить опенинг');
      final promptButton = find.widgetWithText(TvButton, 'Пропустить опенинг');
      final box = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: promptButton,
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        ((box.decoration! as BoxDecoration).border! as Border).top.color,
        accent,
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(video.positions[0], const Duration(seconds: 110));
      expect(video.playing[0], false);
      expect(find.text('Пропустить опенинг'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      await cleanup(tester);
    },
  );
  testWidgets(
    'Unknown opening markers never invent a skip interval; automatic skip obeys setting',
    (tester) async {
      await launchPlayer(tester);
      await position(tester, 40);
      expect(find.text('Пропустить опенинг'), findsNothing);
      await cleanup(tester);
      api.skipdata = {
        'opening': {'start': 30, 'stop': 110},
      };
      await session.prefs.setBool('autoSkipOpeningEnding', true);
      await launchPlayer(tester);
      await position(tester, 40);
      expect(
        video.positions[video.streams.length - 1],
        const Duration(seconds: 110),
      );
      expect(find.text('Пропустить опенинг'), findsNothing);
      await cleanup(tester);
    },
  );
  testWidgets(
    'Next episode countdown advances once near ending and preserves focus',
    (tester) async {
      api.skipdata = {
        'ending': {'start': 1380, 'stop': 1440},
      };
      await launchPlayer(tester);
      await position(tester, 1381);
      expect(find.text('Начнётся через 10 сек'), findsOneWidget);
      await position(tester, 1385);
      expect(find.text('Начнётся через 6 сек'), findsOneWidget);
      await position(tester, 1391);
      expect(video.sources.length, 2);
      expect(video.sources.last, contains('/1/2-hd.m3u8'));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      await cleanup(tester);
    },
  );
  testWidgets(
    'Stay cancels automatic next even at EOF; seeking back resets the prompt',
    (tester) async {
      await launchPlayer(tester);
      await position(tester, 1411);
      expect(find.text('Следующая серия'), findsOneWidget);
      await focusText(tester, 'Остаться');
      await press(tester, LogicalKeyboardKey.select);
      await position(tester, 1440);
      expect(video.sources.length, 1);
      expect(find.text('Следующая серия'), findsNothing);
      await position(tester, 100);
      await position(tester, 1411);
      expect(find.text('Начнётся через 10 сек'), findsOneWidget);
      await cleanup(tester);
    },
  );
  testWidgets(
    'Auto-next off shows manual action; last episode never offers a nonexistent next',
    (tester) async {
      await session.prefs.setBool('autoNextEpisode', false);
      await launchPlayer(tester);
      await position(tester, 1411);
      expect(find.text('Продолжить просмотр?'), findsOneWidget);
      await position(tester, 1440);
      expect(video.sources.length, 1);
      await focusText(tester, 'Смотреть сейчас');
      await press(tester, LogicalKeyboardKey.select);
      expect(video.sources.length, 2);
      await cleanup(tester);
      await launchPlayer(tester, index: 27);
      await position(tester, 1430);
      expect(find.text('Следующая серия'), findsNothing);
      await cleanup(tester);
    },
  );

  testWidgets(
    'Fullscreen prompt Back cancels next without leaving playback; pause freezes countdown',
    (tester) async {
      await launchPlayer(tester);
      await tester.pump(const Duration(seconds: 7));
      await settle(tester);
      await position(tester, 1411);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Episode prompt action',
      );
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.byType(TvEpisodePrompt), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Playback surface',
      );
      await position(tester, 100);
      await position(tester, 1411);
      await press(tester, LogicalKeyboardKey.mediaPause);
      final before = video.sources.length;
      await tester.pump(const Duration(seconds: 15));
      await settle(tester);
      expect(video.sources.length, before);
      expect(find.text('Начнётся через 10 сек'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.mediaPlay);
      await position(tester, 1421);
      expect(video.sources.length, before + 1);
      await cleanup(tester);
    },
  );

  for (final withOpening in [true, false]) {
    testWidgets(
      'Bottom Up reaches timeline with ${withOpening ? "opening" : "next episode"} prompt visible',
      (tester) async {
        api.skipdata = {
          'opening': {'start': 30, 'stop': 110},
        };
        await launchPlayer(tester, index: 3);
        await position(tester, withOpening ? 35 : 1411);
        expect(find.byType(TvEpisodePrompt), findsOneWidget);
        for (var i = 0; i < 8; i++) {
          final state = tester.state<TvPlaybackControlsState>(
            find.byType(TvPlaybackControls),
          );
          state.nodes[i].requestFocus();
          await settle(tester);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
          await settle(tester);
          expect(FocusManager.instance.primaryFocus?.debugLabel, 'Timeline');
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
          await settle(tester);
          expect(FocusManager.instance.primaryFocus?.debugLabel, 'Timeline');
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
        }
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(
          tester.state<TvSeekBarState>(find.byType(TvSeekBar)).draft,
          isNotNull,
        );
        await press(tester, LogicalKeyboardKey.select);
        expect(
          video.positions.values.single,
          Duration(seconds: (withOpening ? 35 : 1411) + 10),
        );
        await cleanup(tester);
      },
    );
  }

  Future<void> rawBack(
    WidgetTester tester, [
    LogicalKeyboardKey key = LogicalKeyboardKey.goBack,
  ]) async {
    await tester.sendKeyEvent(key, physicalKey: PhysicalKeyboardKey.escape);
    await settle(tester);
  }

  Future<void> hidePlayback(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Timeline');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.byType(TvPlaybackControls), findsNothing);
  }

  testWidgets(
    'Every bottom action follows timeline, hidden, back, play navigation',
    (tester) async {
      await launchPlayer(tester, index: 3);
      for (var i = 0; i < 9; i++) {
        tester
            .state<TvPlaybackControlsState>(find.byType(TvPlaybackControls))
            .nodes[i]
            .requestFocus();
        await settle(tester);
        await hidePlayback(tester);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Playback surface',
        );
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player back');
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
        await hidePlayback(tester);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      }
      expect(find.textContaining('Шкала перемотки'), findsNothing);
      expect(find.textContaining('Стрелки —'), findsNothing);
      expect(find.textContaining('Перемотка · шаг'), findsNothing);
      await cleanup(tester);
    },
  );

  testWidgets('Upper exit remains directly actionable with a prompt', (
    tester,
  ) async {
    await launchPlayer(tester);
    await hidePlayback(tester);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player back');
    await position(tester, 1411);
    tester
        .state<TvPlaybackControlsState>(find.byType(TvPlaybackControls))
        .focusBack();
    await settle(tester);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.text('Root'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('Held Up crosses just one level per distinct press', (
    tester,
  ) async {
    await launchPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Timeline');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    expect(find.byType(TvPlaybackControls), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player back');
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(PlayerScreen), findsNothing);
    await cleanup(tester);
  });

  testWidgets(
    'Idle controls hide from play, back and timeline, also when paused',
    (tester) async {
      for (final paused in [false, true]) {
        for (var target = 0; target < 3; target++) {
          await launchPlayer(tester);
          if (paused) await press(tester, LogicalKeyboardKey.mediaPause);
          if (target == 1) {
            await hidePlayback(tester);
            await press(tester, LogicalKeyboardKey.arrowUp);
          }
          if (target == 2) await press(tester, LogicalKeyboardKey.arrowUp);
          await tester.pump(const Duration(seconds: 7));
          await settle(tester);
          expect(find.byType(TvPlaybackControls), findsNothing);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Playback surface',
          );
          await cleanup(tester);
        }
      }
    },
  );

  testWidgets(
    'Hidden arrows immediately seek with configured step, repeat and bounds without opening controls',
    (tester) async {
      await session.prefs.setInt('doubleTapSeekSeconds', 15);
      await launchPlayer(tester, index: 27);
      await position(tester, 300);
      await press(tester, LogicalKeyboardKey.mediaPause);
      await hidePlayback(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(video.positions.values.single, const Duration(seconds: 315));
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(video.positions.values.single, const Duration(seconds: 300));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(video.positions.values.single, const Duration(seconds: 330));
      expect(video.playing.values.single, false);
      expect(find.byType(TvPlaybackControls), findsNothing);
      final dynamic player = tester.state(find.byType(PlayerScreen));
      // A paused controller does not poll the fake platform's position.
      await player.controller.seekTo(const Duration(seconds: 3));
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(video.positions.values.single, Duration.zero);
      await player.controller.seekTo(const Duration(seconds: 1438));
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(video.positions.values.single, const Duration(seconds: 1440));
      expect(find.byType(TvPlaybackControls), findsNothing);
      await cleanup(tester);
    },
  );

  testWidgets('Hidden seek works even when an episode prompt owns focus', (
    tester,
  ) async {
    api.skipdata = {
      'opening': {'start': 30, 'stop': 110},
    };
    await launchPlayer(tester);
    await tester.pump(const Duration(seconds: 7));
    await settle(tester);
    await position(tester, 35);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Episode prompt action',
    );
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(video.positions.values.single, const Duration(seconds: 45));
    expect(find.byType(TvPlaybackControls), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(video.positions.values.single, const Duration(seconds: 35));
    await position(tester, 300);
    await position(tester, 1411);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Episode prompt action',
    );
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(video.positions.values.single, const Duration(seconds: 1401));
    expect(find.byType(TvPlaybackControls), findsNothing);
    await position(tester, 35);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Episode prompt action',
    );
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player back');
    await cleanup(tester);
  });

  testWidgets(
    'Upscale selector keeps episode, voice, quality, pause, progress and modal focus for every mode',
    (tester) async {
      await launchPlayer(tester, index: 3);
      video.initializeDelay = const Duration(milliseconds: 200);
      await position(tester, 754);
      await press(tester, LogicalKeyboardKey.mediaPause);
      tester
          .state<TvPlaybackControlsState>(find.byType(TvPlaybackControls))
          .focusPanel(2);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.select);
      final modes = ['light', 'cnn_s', 'cnn_m', 'off'];
      final labels = ['Лёгкий · контуры', 'Нейро S', 'Нейро M', 'Выключено'];
      for (var i = 0; i < modes.length; i++) {
        await focusText(tester, labels[i]);
        final focus = FocusManager.instance.primaryFocus;
        await press(tester, LogicalKeyboardKey.select);
        await settle(tester);
        expect(session.prefs.getString(upscalePreference), modes[i]);
        expect(upscaleCalls.last, modes[i]);
        expect(video.sources.last, contains('/1/4-hd.m3u8'));
        final id = video.streams.length - 1;
        expect(video.positions[id], const Duration(seconds: 754));
        expect(video.playing[id] ?? false, false);
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(ModalRoute.of(focus!.context!)!.isCurrent, true);
      }
      expect(video.sources.length, 5);
      await rawBack(tester);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Video panel');
      await rawBack(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(number(session.localHistory.first['timestamp']), 754);
      await cleanup(tester);
    },
  );

  testWidgets('Unsupported processing safely returns to off before playback', (
    tester,
  ) async {
    await session.prefs.setString(upscalePreference, 'cnn_m');
    rejectUpscale = true;
    await launchPlayer(tester);
    expect(session.prefs.getString(upscalePreference), 'off');
    expect(upscaleCalls, ['cnn_m', 'off']);
    expect(video.playing.values.single, true);
    await cleanup(tester);
  });

  Future<void> reportUpscaleFailure(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      VideoUpscale.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('failure', 'No processed video frame'),
      ),
      (_) {},
    );
    await settle(tester);
    await settle(tester);
  }

  testWidgets(
    'Direct lower-row upscaler popup selects a model with remote and restores its opener',
    (tester) async {
      await launchPlayer(tester, index: 3);
      await position(tester, 754);
      for (var i = 0; i < 6; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Upscale panel');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Апскейлер'), findsOneWidget);
      expect(find.text('Ваш просмотр'), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(session.prefs.getString(upscalePreference), 'cnn_s');
      final id = video.streams.length - 1;
      expect(video.positions[id], const Duration(seconds: 754));
      expect(video.playing[id], true);
      expect(
        ModalRoute.of(FocusManager.instance.primaryFocus!.context!)!.isCurrent,
        true,
      );
      await rawBack(tester);
      expect(find.text('Апскейлер'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Upscale panel');
      await cleanup(tester);
    },
  );

  testWidgets(
    'No-first-frame fallback switches off once and retains paused position',
    (tester) async {
      await session.prefs.setString(upscalePreference, 'cnn_s');
      await launchPlayer(tester, index: 3);
      await position(tester, 754);
      await press(tester, LogicalKeyboardKey.mediaPause);
      await reportUpscaleFailure(tester);
      expect(session.prefs.getString(upscalePreference), 'off');
      expect(upscaleCalls, ['cnn_s', 'off']);
      expect(video.sources.length, 2);
      final id = video.streams.length - 1;
      expect(video.positions[id], const Duration(seconds: 754));
      expect(video.playing[id], false);
      await reportUpscaleFailure(tester);
      expect(video.sources.length, 2);
      await cleanup(tester);
    },
  );

  testWidgets(
    'Effect initialization error retries the same video without processing',
    (tester) async {
      await session.prefs.setString(upscalePreference, 'cnn_m');
      video.failInitializations = 1;
      await launchPlayer(tester, index: 3, waitForRecovery: true);
      expect(video.sources.length, 2);
      expect(video.sources.last, video.sources.first);
      expect(upscaleCalls, ['cnn_m', 'off']);
      expect(session.prefs.getString(upscalePreference), 'off');
      expect(video.playing[1], true);
      await cleanup(tester);
    },
  );

  testWidgets(
    'Runtime processing error retains last good paused position despite erroneous video value',
    (tester) async {
      await session.prefs.setString(upscalePreference, 'light');
      await launchPlayer(tester, index: 3);
      await position(tester, 754);
      await press(tester, LogicalKeyboardKey.mediaPause);
      video.streams[0]!.addError(
        PlatformException(code: 'VideoError', message: 'GPU context lost'),
      );
      await settle(tester);
      await settle(tester);
      expect(session.prefs.getString(upscalePreference), 'off');
      expect(video.sources.length, 2);
      expect(video.positions[1], const Duration(seconds: 754));
      expect(video.playing[1], false);
      await cleanup(tester);
    },
  );

  testWidgets(
    'Back may close direct selector while a model is loading without losing actionable focus',
    (tester) async {
      await launchPlayer(tester);
      video.initializeDelay = const Duration(seconds: 1);
      tester
          .state<TvPlaybackControlsState>(find.byType(TvPlaybackControls))
          .focusUpscale();
      await settle(tester);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 100));
      await rawBack(tester);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('Апскейлер'), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      expect(
        ModalRoute.of(FocusManager.instance.primaryFocus!.context!)!.isCurrent,
        true,
      );
      expect(tester.takeException(), isNull);
      await cleanup(tester);
    },
  );

  testWidgets(
    'Zero-size initialization never reaches a zero-sized Flutter video rectangle',
    (tester) async {
      await session.prefs.setString(upscalePreference, 'light');
      video.zeroSizeInitializations = 1;
      await launchPlayer(tester, waitForRecovery: true);
      expect(session.prefs.getString(upscalePreference), 'off');
      expect(video.sources.length, 2);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      await cleanup(tester);
    },
  );

  testWidgets(
    'Installed-APK diagnostic route uses a local asset, no backend and no history',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(TvApp(session: session, videoCheckOnly: true));
      await settle(tester);
      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(video.sources.single, 'asset:assets/video_check.mp4');
      await tester.pump(const Duration(seconds: 20));
      await settle(tester);
      expect(api.calls, isEmpty);
      expect(session.localHistory, isEmpty);
      await cleanup(tester);
    },
  );

  Future<void> androidBack(WidgetTester tester) async {
    // Same framework entry point as MainActivity.navigationChannel.popRoute().
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        const MethodCall('popRoute'),
      ),
      (_) {},
    );
    await settle(tester);
  }

  testWidgets(
    'Android back channel exits visible, hidden, timeline and upper controls',
    (tester) async {
      for (var target = 0; target < 4; target++) {
        await launchPlayer(tester);
        if (target == 1 || target == 3) {
          await hidePlayback(tester);
        }
        if (target == 2) await press(tester, LogicalKeyboardKey.arrowUp);
        if (target == 3) await press(tester, LogicalKeyboardKey.arrowUp);
        await androidBack(tester);
        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.text('Root'), findsOneWidget);
        await cleanup(tester);
      }
    },
  );

  testWidgets('Android back closes panel or seek draft, next press exits', (
    tester,
  ) async {
    await launchPlayer(tester);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await androidBack(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(tester.state<TvSeekBarState>(find.byType(TvSeekBar)).draft, isNull);
    await androidBack(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    await cleanup(tester);
    await launchPlayer(tester);
    tester
        .state<TvPlaybackControlsState>(find.byType(TvPlaybackControls))
        .focusPanel(2);
    await settle(tester);
    await press(tester, LogicalKeyboardKey.select);
    await androidBack(tester);
    expect(find.text('Ваш просмотр'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Video panel');
    await androidBack(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    await cleanup(tester);
  });

  for (final key in [LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape]) {
    testWidgets(
      'Raw ${key.keyLabel} exits visible and hidden player in one press',
      (tester) async {
        await launchPlayer(tester);
        await rawBack(tester, key);
        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.text('Root'), findsOneWidget);
        await cleanup(tester);
        await launchPlayer(tester);
        await hidePlayback(tester);
        await rawBack(tester, key);
        expect(find.byType(PlayerScreen), findsNothing);
        await cleanup(tester);
      },
    );
  }

  testWidgets(
    'Opening and next prompts immediately focus their primary action and OK performs it',
    (tester) async {
      api.skipdata = {
        'opening': {'start': 30, 'stop': 110},
      };
      await launchPlayer(tester);
      await hidePlayback(tester);
      await position(tester, 35);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Episode prompt action',
      );
      final promptButton = find.widgetWithText(TvButton, 'Пропустить опенинг');
      final box = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: promptButton,
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        ((box.decoration! as BoxDecoration).border! as Border).top.color,
        accent,
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(video.positions[0], const Duration(seconds: 110));
      expect(video.playing[0], true);
      await position(tester, 300);
      await position(tester, 1411);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Episode prompt action',
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(video.sources.length, 2);
      expect(video.sources.last, contains('/1/2-'));
      await cleanup(tester);
    },
  );

  testWidgets(
    'Raw Back dismisses a prompt then exits; panel Back restores each exact opener',
    (tester) async {
      await launchPlayer(tester);
      await position(tester, 1411);
      await rawBack(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.byType(TvEpisodePrompt), findsNothing);
      for (var tab = 0; tab < 3; tab++) {
        final state = tester.state<TvPlaybackControlsState>(
          find.byType(TvPlaybackControls),
        );
        state.focusPanel(tab);
        await settle(tester);
        final opener = FocusManager.instance.primaryFocus;
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text('Ваш просмотр'), findsOneWidget);
        await rawBack(tester);
        expect(find.text('Ваш просмотр'), findsNothing);
        expect(FocusManager.instance.primaryFocus, same(opener));
      }
      await rawBack(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      await cleanup(tester);
    },
  );

  testWidgets(
    'Opening does not steal focus inside a panel; visible next prompt restores focus when it disappears',
    (tester) async {
      api.skipdata = {
        'opening': {'start': 30, 'stop': 110},
      };
      await launchPlayer(tester);
      final state = tester.state<TvPlaybackControlsState>(
        find.byType(TvPlaybackControls),
      );
      state.focusPanel(2);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.select);
      final panelFocus = FocusManager.instance.primaryFocus;
      await position(tester, 35);
      expect(FocusManager.instance.primaryFocus, same(panelFocus));
      expect(ModalRoute.of(panelFocus!.context!)!.isCurrent, true);
      await rawBack(tester);
      await position(tester, 300);
      await position(tester, 1411);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Episode prompt action',
      );
      await position(tester, 300);
      expect(find.byType(TvEpisodePrompt), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play pause');
      await cleanup(tester);
    },
  );

  testWidgets(
    'Search, keyboard, filters and settings have actionable remote focus and return to root',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(TvApp(session: session));
      await settle(tester);
      await focusText(tester, 'Поиск');
      await press(tester, LogicalKeyboardKey.select);
      await focusText(tester, 'Клавиатура');
      await press(tester, LogicalKeyboardKey.select);
      expect(tester.testTextInput.isVisible, true);
      await tester.enterText(find.byType(TextField), 'А');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        tester.widget<TvTextEntry>(find.byType(TvTextEntry).first).value,
        'А',
      );
      await focusText(tester, 'Фильтры');
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(FiltersDialog), findsOneWidget);
      for (var i = 0; i < 12; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await focusText(tester, 'Настройки');
      await press(tester, LogicalKeyboardKey.select);
      await focusText(tester, 'Продолжать с сохранённой позиции');
      await press(tester, LogicalKeyboardKey.select);
      expect(session.prefs.getBool('resume'), false);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(AnimeCard), findsWidgets);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Navigation 0');
      await cleanup(tester);
    },
  );
}
