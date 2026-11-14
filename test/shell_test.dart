import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:animetka_tv/auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animetka_tv/api.dart';
import 'package:animetka_tv/main.dart';

class OfflineApi extends Api {
  String? searched;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? query,
    dynamic body,
    bool auth = false,
  }) async => [
    {
      'id': 2778,
      'title': 'Тестовая история',
      'year': 2023,
      'shikimori_rating': 9.2,
      'episodes_total': 28,
    },
  ];
  @override
  Future<List<Json>> search(
    String name, {
    int offset = 0,
    Json filters = const {},
  }) async {
    searched = name;
    return [
      {'animetka_id': 228, 'title': 'Результат поиска', 'year': 1995},
    ];
  }
}

void main() {
  testWidgets('Guest can search and open settings entirely offline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'guest': true});
    final api = OfflineApi();
    final session = Session(await SharedPreferences.getInstance(), api);
    await tester.pumpWidget(TvApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('Тестовая история'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Поиск'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Клавиатура'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'NARUTO');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(api.searched, 'NARUTO');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (MethodCall call) async {
          if (call.method == 'speech') return 'Наруто';
          throw StateError('Unexpected native command: ${call.method}');
        });
    await tester.tap(find.text('Голос'));
    await tester.pumpAndSettle();
    expect(api.searched, 'Наруто');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);

    expect(find.text('Результат поиска'), findsOneWidget);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Автоматически'), 250);
    expect(find.text('Автоматически'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Сменить тему'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сменить тему'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
