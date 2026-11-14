import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:animetka_tv/api.dart';
import 'package:animetka_tv/auth.dart' show platform;
import 'package:animetka_tv/main.dart';
import 'package:animetka_tv/player.dart';
import 'package:animetka_tv/ui.dart';

import 'remote_navigation_test.dart'
    show NavigationApi, OfflineHttp, OfflineVideo;

class SearchPagesApi extends NavigationApi {
  int count = 8;
  @override
  Future<List<Json>> search(
    String name, {
    int offset = 0,
    Json filters = const {},
  }) async => List.generate(
    count,
    (i) => {
      ...anime,
      'id': i + offset + 1,
      'title': 'Result ${i + offset + 1}',
    },
  );
}

void main() {
  late SearchPagesApi api;
  late Session session;
  setUp(() async {
    HttpOverrides.global = OfflineHttp();
    VideoPlayerPlatform.instance = OfflineVideo();
    SharedPreferences.setMockInitialValues({'guest': true});
    api = SearchPagesApi();
    session = Session(await SharedPreferences.getInstance(), api);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'appVersion') return '1.5.0';
          if (call.method != 'setKeepScreenOn') {
            throw StateError('Forbidden native action: ${call.method}');
          }
          return null;
        });
  });
  tearDown(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  TvButton button(WidgetTester tester, String label) => tester.widget<TvButton>(
    find
        .ancestor(of: find.text(label).first, matching: find.byType(TvButton))
        .first,
  );

  testWidgets(
    'History card preserves seconds instead of material duration in minutes',
    (tester) async {
      viewport(tester);
      await session.prefs.setString(
        'history',
        jsonEncode([
          {
            'animetka_id': 1,
            'material': {...api.anime, 'duration': 24},
            'episode': 3,
            'timestamp': 754,
            'duration': 1440,
          },
          {
            'animetka_id': 2,
            'material': {...api.anime, 'id': 2, 'duration': 24},
            'episode': 2,
            'timestamp': 430,
            'duration': 1440,
          },
        ]),
      );
      await tester.pumpWidget(TvApp(session: session));
      await settle(tester);
      await tester.tap(find.byTooltip('Продолжить'));
      await settle(tester);
      final progress = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((w) => w.value)
          .toList();
      expect(progress, [754 / 1440, 430 / 1440]);
      expect(
        historyAnime({
          'material': {'id': 1, 'duration': 24},
          'timestamp': 754,
        })['duration'],
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets(
    'Search footer uses actual page count and disables end of results',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(TvApp(session: session));
      await settle(tester);
      await tester.tap(find.byTooltip('Поиск'));
      await settle(tester);
      expect(find.text('1–8'), findsOneWidget);
      expect(button(tester, 'Далее').onPressed, isNull);
      api.count = 30;
      await tester.tap(find.text('Найти'));
      await settle(tester);
      expect(find.text('1–30'), findsOneWidget);
      expect(button(tester, 'Далее').onPressed, isNotNull);
      api.count = 2;
      await tester.tap(find.text('Далее'));
      await settle(tester);
      expect(find.text('31–32'), findsOneWidget);
      expect(button(tester, 'Далее').onPressed, isNull);
      api.count = 0;
      await tester.tap(find.text('Найти'));
      await settle(tester);
      expect(find.text('Нет результатов'), findsOneWidget);
      expect(button(tester, 'Далее').onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets(
    'TV keyboard switches alphabets, edits Unicode, moves cursor and submits draft',
    (tester) async {
      viewport(tester);
      var draft = '猫';
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: mjTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => TvSearchKeyboard(
                      initial: draft,
                      onChanged: (v) => draft = v,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      await tester.tap(find.text('ABC'));
      await settle(tester);
      await tester.tap(find.text('A'));
      await settle(tester);
      expect(draft, '猫A');
      await tester.tap(find.byIcon(Icons.chevron_left));
      await settle(tester);
      await tester.tap(find.text('B'));
      await settle(tester);
      expect(draft, '猫BA');
      await tester.tap(find.text('Стереть'));
      await settle(tester);
      expect(draft, '猫A');
      await tester.tap(find.text('Очистить'));
      await settle(tester);
      expect(draft, '');
      await tester.tap(find.text('АБВ'));
      await settle(tester);
      await tester.tap(find.text('Я'));
      await settle(tester);
      await tester.tap(find.text('Найти'));
      await settle(tester);
      expect(result, 'Я');
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  for (final voices in [1, 2]) {
    testWidgets(
      'Missing source focuses actionable recovery with $voices voice choices',
      (tester) async {
        viewport(tester);
        final playlist = await api.playlist(1);
        playlist['list'] = [
          {'title': 'Серия 1'},
        ];
        playlist['translations'] = objects(playlist['translations'])
            .take(voices)
            .toList();
        await tester.pumpWidget(
          MaterialApp(
            theme: mjTheme(),
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
                        index: 0,
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
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Player recovery',
        );
        expect(find.text('Повторить'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await settle(tester);
        if (voices == 1) {
          expect(find.byType(PlayerScreen), findsNothing);
        } else {
          expect(find.text('Ваш просмотр'), findsOneWidget);
          await tester.binding.handlePopRoute();
          await settle(tester);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Player recovery',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      },
    );
  }
}
