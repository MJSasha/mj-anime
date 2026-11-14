import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:animetka_tv/api.dart';
import 'package:animetka_tv/auth.dart';
import 'package:animetka_tv/main.dart';
import 'package:animetka_tv/cinema.dart';
import 'package:animetka_tv/details.dart';
import 'package:animetka_tv/account.dart';
import 'package:animetka_tv/filters.dart';
import 'package:animetka_tv/ui.dart';

import 'remote_navigation_test.dart'
    show NavigationApi, OfflineHttp, OfflineVideo;

class FullFixApi extends NavigationApi {
  bool failPlaylist = false, emptyPlaylist = false, failSearch = false;
  String? searched;
  final mutations = <Json>[];
  final profile = <String, dynamic>{
    'nickname': 'Зритель',
    'bio': 'О себе',
    'city': 'Город',
    'stats': {},
  };
  @override
  Future<Json> detail(int id) async => {
    ...await super.detail(id),
    'anime_description': List.filled(
      50,
      'Длинный текст для проверки чтения пультом.',
    ).join('\n\n'),
  };
  @override
  Future<Json> playlist(int id, [int? translation]) async {
    if (failPlaylist) throw ApiFailure(503, 'Нет связи со списком серий');
    final data = await super.playlist(id, translation);
    if (emptyPlaylist) data['list'] = <Json>[];
    return data;
  }

  @override
  Future<List<Json>> search(
    String name, {
    int offset = 0,
    Json filters = const {},
  }) async {
    searched = name;
    if (failSearch) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      throw ApiFailure(503, 'Ошибка поиска');
    }
    return [anime];
  }

  List<Json> get folders => [
    {
      'id': 10,
      'title': 'Смотрю',
      'AnimeHistories': [
        {
          'animetka_id': 1,
          'material': anime,
          'episode': 3,
          'timestamp': 300,
          'duration': 1440,
        },
      ],
    },
  ];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? query,
    dynamic body,
    bool auth = false,
  }) async {
    if (method != 'GET') {
      mutations.add({'path': path, 'method': method, 'body': body});
    }
    if (path == '/api/auth/tv/start') {
      return {
        'token': 'pending',
        'url': 'https://example.invalid',
        'user_code': '123456',
      };
    }
    if (path.endsWith('/status')) return {'status': 'pending'};
    if (path == '/api/user/profile/me') {
      if (method == 'PATCH') profile.addAll(object(body));
      return profile;
    }
    if (path == '/api/user/folder') return folders;
    if (path.contains('/api/user/folder/')) return {};
    if (path.endsWith('/characters')) {
      return [
        {'id': 42, 'russian': 'Персонаж'},
      ];
    }
    if (path.endsWith('/characters/42')) {
      return {
        'description': List.filled(
          50,
          'Описание персонажа для проверки прокрутки.',
        ).join('\n\n'),
      };
    }
    return super.request(
      path,
      method: method,
      query: query,
      body: body,
      auth: auth,
    );
  }
}

void main() {
  late FullFixApi api;
  late Session session;
  final native = <String>[];
  setUp(() async {
    HttpOverrides.global = OfflineHttp();
    VideoPlayerPlatform.instance = OfflineVideo();
    SharedPreferences.setMockInitialValues({'guest': true});
    api = FullFixApi();
    session = Session(await SharedPreferences.getInstance(), api);
    native.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          native.add(call.method);
          if (call.method == 'appVersion') return '1.5.0';
          if (call.method == 'setKeepScreenOn') return null;
          if (call.method == 'installUpdate') {
            throw PlatformException(
              code: 'unavailable',
              message: 'Не удалось открыть установщик',
            );
          }
          throw StateError('Forbidden native action: ${call.method}');
        });
  });
  tearDown(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
    expect(
      native.every(
        (v) => ['appVersion', 'setKeepScreenOn', 'installUpdate'].contains(v),
      ),
      true,
    );
  });
  void viewport(WidgetTester t) {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
  }

  Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyEvent(key);
    await settle(t);
  }

  Future<void> focus(WidgetTester t, String text) async {
    if (find.text(text).evaluate().isEmpty &&
        find.byTooltip(text).evaluate().isEmpty) {
      await press(t, LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 30 && find.text(text).evaluate().isEmpty; i++) {
        await press(t, LogicalKeyboardKey.arrowDown);
      }
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
    Focus.of(t.element(ink)).requestFocus();
    await settle(t);
  }

  Future<void> openText(WidgetTester t, String text) async {
    await focus(t, text);
    await press(t, LogicalKeyboardKey.select);
  }

  Future<void> back(WidgetTester t) async {
    await t.binding.handlePopRoute();
    await settle(t);
  }

  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t);
  }

  Future<void> mount(WidgetTester t, Widget page, {bool light = false}) async {
    viewport(t);
    await t.pumpWidget(
      MaterialApp(
        theme: mjTheme(light: light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TvButton(
              autofocus: true,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => page),
              ),
              child: const Text('Root'),
            ),
          ),
        ),
      ),
    );
    await settle(t);
    await press(t, LogicalKeyboardKey.select);
  }

  Future<void> app(WidgetTester t, {bool logged = false}) async {
    viewport(t);
    api.token = null;
    await t.pumpWidget(TvApp(session: session));
    await settle(t);
    if (logged) {
      api.token = 'synthetic-test-token';
      final dynamic state = t.state(find.byType(Shell));
      state.setState(() {});
      await settle(t);
    }
  }

  Future<void> type(WidgetTester t, String letters) async {
    for (final letter in letters.split('')) {
      await t.tap(find.text(letter).last);
      await settle(t);
    }
  }

  TvButton button(WidgetTester t, String label) => t.widget<TvButton>(
    find
        .ancestor(of: find.text(label).first, matching: find.byType(TvButton))
        .first,
  );

  testWidgets(
    'Search field navigates with arrows, opens keyboard with OK and returns without losing draft',
    (t) async {
      await app(t);
      await openText(t, 'Поиск');
      await focus(t, 'Название аниме');
      final input = FocusManager.instance.primaryFocus;
      await press(t, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus, isNot(same(input)));
      await focus(t, 'Название аниме');
      await press(t, LogicalKeyboardKey.select);
      expect(find.byType(NativeSearchDialog), findsOneWidget);
      expect(t.testTextInput.isVisible, true);
      await t.enterText(find.byType(TextField), 'А');
      await back(t);
      expect(FocusManager.instance.primaryFocus, same(input));
      expect(t.widget<TvTextEntry>(find.byType(TvTextEntry)).value, 'А');
      await press(t, LogicalKeyboardKey.arrowRight);
      await press(t, LogicalKeyboardKey.select);
      expect(api.searched, 'А');
      await clean(t);
    },
  );

  testWidgets(
    'Repeated prompt cancel and submit are safe throughout dialog exit animation',
    (t) async {
      viewport(t);
      String? result;
      await t.pumpWidget(
        MaterialApp(
          theme: mjTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TvButton(
                autofocus: true,
                onPressed: () async {
                  result = await textPrompt(context, 'Название списка');
                },
                child: const Text('Форма'),
              ),
            ),
          ),
        ),
      );
      await settle(t);
      for (var i = 0; i < 4; i++) {
        await press(t, LogicalKeyboardKey.select);
        await press(t, LogicalKeyboardKey.select);
        await back(t);
        expect(result, isNull);
        expect(find.text('Форма'), findsOneWidget);
      }
      await press(t, LogicalKeyboardKey.select);
      await press(t, LogicalKeyboardKey.select);
      await openText(t, 'Готово');
      expect(result, 'А');
      await clean(t);
    },
  );

  testWidgets(
    'Numeric filters use remote keyboard, reject inverted ranges and cancel safely',
    (t) async {
      await mount(t, FiltersDialog(api: api, initial: {}));
      await openText(t, 'Год от');
      expect(find.byType(TextField), findsNothing);
      await type(t, '2024');
      await openText(t, 'Готово');
      expect(find.text('2024'), findsOneWidget);
      await openText(t, 'Год до');
      await type(t, '2020');
      await openText(t, 'Готово');
      expect(find.text('2020'), findsOneWidget);
      await openText(t, 'Применить');
      expect(
        find.text('Нижняя граница не должна превышать верхнюю'),
        findsOneWidget,
        reason: t
            .widgetList<TvTextEntry>(find.byType(TvTextEntry))
            .map((v) => '${v.label}=${v.value}')
            .join(', '),
      );
      expect(find.byType(FiltersDialog), findsOneWidget);
      await back(t);
      expect(find.text('Root'), findsOneWidget);
      await clean(t);
    },
  );

  testWidgets(
    'Genre and order choices open with actionable focus and apply from remote',
    (t) async {
      await mount(t, FiltersDialog(api: api, initial: {}));
      await openText(t, 'Жанры: 0');
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      await press(t, LogicalKeyboardKey.select);
      await openText(t, 'Готово');
      expect(find.text('Жанры: 1'), findsOneWidget);
      await openText(t, 'Порядок: Не выбран');
      await press(t, LogicalKeyboardKey.arrowDown);
      await press(t, LogicalKeyboardKey.select);
      expect(find.text('Порядок: Популярность'), findsOneWidget);
      await clean(t);
    },
  );

  testWidgets(
    'Anime description has its own focus and scrolls downward and back to tabs',
    (t) async {
      await mount(t, DetailsScreen(session: session, id: 1));
      await openText(t, 'Информация');
      await press(t, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Описание аниме');
      for (var i = 0; i < 12; i++) {
        await press(t, LogicalKeyboardKey.arrowDown);
      }
      final scroll = t.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(TvScrollPane),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.pixels, greaterThan(0));
      for (var i = 0; i < 30; i++) {
        await press(t, LogicalKeyboardKey.arrowUp);
      }
      expect(scroll.position.pixels, 0);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('Описание аниме'),
      );
      await clean(t);
    },
  );

  testWidgets(
    'Character dialog focuses Close and has a reachable scrollable reading region',
    (t) async {
      await mount(t, DetailsScreen(session: session, id: 1));
      await openText(t, 'Персонажи');
      await openText(t, 'Персонаж');
      expect(button(t, 'Закрыть').autofocus, true);
      await press(t, LogicalKeyboardKey.arrowUp);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Описание персонажа',
      );
      for (var i = 0; i < 10; i++) {
        await press(t, LogicalKeyboardKey.arrowDown);
      }
      final scroll = t.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(TvScrollPane),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.pixels, greaterThan(0));
      await back(t);
      expect(find.byType(DetailsScreen), findsOneWidget);
      await clean(t);
    },
  );

  testWidgets(
    'Folder remove is a separate reachable action; Undo and focus survive removal',
    (t) async {
      api.token = 'synthetic-test-token';
      await mount(t, FolderScreen(session: session, folder: api.folders.first));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Anime card');
      await press(t, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Remove anime');
      await press(t, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Anime card');
      await press(t, LogicalKeyboardKey.arrowDown);
      await press(t, LogicalKeyboardKey.select);
      expect(find.text('В этом списке пока нет аниме'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Folder back');
      await press(t, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      await press(t, LogicalKeyboardKey.select);
      expect(find.byType(AnimeCard), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      await clean(t);
    },
  );

  testWidgets(
    'History short OK opens detail, held OK opens menu only, release and repeats cannot delete',
    (t) async {
      await session.prefs.setString(
        'history',
        jsonEncode([
          {
            'animetka_id': 1,
            'material': api.anime,
            'episode': 3,
            'timestamp': 300,
            'duration': 1440,
          },
        ]),
      );
      await app(t);
      await openText(t, 'Продолжить');
      await focus(t, 'Первый сезон');
      final opener = FocusManager.instance.primaryFocus;
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 750));
      await settle(t);
      expect(find.text('История просмотра'), findsOneWidget);
      expect(find.byType(DetailsScreen), findsNothing);
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await settle(t);
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await settle(t);
      expect(session.localHistory.length, 1);
      expect(find.text('История просмотра'), findsOneWidget);
      await back(t);
      expect(FocusManager.instance.primaryFocus, same(opener));
      await press(t, LogicalKeyboardKey.select);
      expect(find.byType(DetailsScreen), findsOneWidget);
      await back(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 750));
      await settle(t);
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await settle(t);
      await openText(t, 'Удалить из истории');
      expect(session.localHistory, isEmpty);
      expect(find.text('Пока нет просмотренных серий'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Navigation 2');
      await clean(t);
    },
  );

  for (final error in [false, true]) {
    testWidgets(
      'Initial episode ${error ? 'failure' : 'empty'} focuses a useful exit or recovery',
      (t) async {
        api.failPlaylist = error;
        api.emptyPlaylist = !error;
        await mount(t, DetailsScreen(session: session, id: 1));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          error ? 'Episode recovery' : 'Detail back',
        );
        if (error) {
          api.failPlaylist = false;
          await press(t, LogicalKeyboardKey.select);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Detail playback',
          );
        } else {
          await press(t, LogicalKeyboardKey.select);
          expect(find.byType(DetailsScreen), findsNothing);
        }
        await clean(t);
      },
    );
  }

  testWidgets(
    'Guest recommendations and collections offer login instead of retry or async failure',
    (t) async {
      await app(t);
      await openText(t, 'Рекомендации');
      expect(find.text('Здесь нужен аккаунт'), findsOneWidget);
      expect(find.text('Повторить'), findsNothing);
      await openText(t, 'Мои списки');
      expect(find.text('Здесь нужен аккаунт'), findsOneWidget);
      await openText(t, 'Войти в аккаунт');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      await clean(t);
    },
  );

  testWidgets('Search failure clears stale page range and disables paging', (
    t,
  ) async {
    await app(t);
    await openText(t, 'Поиск');
    expect(find.text('1–1'), findsOneWidget);
    api.failSearch = true;
    await openText(t, 'Найти');
    expect(find.text('1–1'), findsNothing);
    expect(find.text('Ошибка поиска'), findsWidgets);
    expect(button(t, 'Далее').onPressed, isNull);
    await clean(t);
  });

  testWidgets(
    'Profile fields use TV input, have spacing and save without controller lifetime errors',
    (t) async {
      api.token = 'synthetic-test-token';
      await mount(t, ProfileScreen(session: session));
      await press(t, LogicalKeyboardKey.select);
      expect(find.text('Редактировать профиль'), findsOneWidget);
      await press(t, LogicalKeyboardKey.select);
      expect(find.byType(TvSearchKeyboard), findsOneWidget);
      await openText(t, 'Очистить');
      await openText(t, 'ABC');
      await type(t, 'MJ');
      await openText(t, 'Готово');
      expect(find.byType(TextField), findsNothing);
      await openText(t, 'Сохранить');
      expect(api.profile['nickname'], 'MJ');
      await openText(t, 'Редактировать');
      await back(t);
      expect(find.text('Мой профиль'), findsOneWidget);
      await clean(t);
    },
  );

  testWidgets(
    'Update information uses installed package version and friendly platform errors',
    (t) async {
      await app(t);
      await openText(t, 'Настройки');
      await openText(t, 'Обновление MJAnime');
      expect(find.textContaining('Установлена версия 1.5.0'), findsOneWidget);
      expect(find.textContaining('Версия оригинала:'), findsNothing);
      expect(button(t, 'Закрыть').autofocus, true);
      await openText(t, 'Выбрать APK');
      expect(find.text('Не удалось открыть установщик'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(native, contains('installUpdate'));
      await clean(t);
    },
  );

  testWidgets('Light login and detail metadata use semantic secondary color', (
    t,
  ) async {
    await mount(t, LoginScreen(session: session, onDone: () {}), light: true);
    final instruction = t.widget<Text>(
      find.textContaining('Отсканируй QR в приложении'),
    );
    final context = t.element(
      find.textContaining('Отсканируй QR в приложении'),
    );
    expect(
      instruction.style!.color,
      Theme.of(context).colorScheme.onSurfaceVariant,
    );
    await clean(t);
  });
}
