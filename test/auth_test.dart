import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animetka_tv/api.dart';
import 'package:animetka_tv/auth.dart';

class OfflineLoginApi extends Api {
  final calls = <Json>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? query,
    dynamic body,
    bool auth = false,
  }) async {
    calls.add({'path': path, 'body': body});
    switch (path) {
      case '/api/auth/tv/start':
        return {
          'token': 'test-pending',
          'url': 'https://example.invalid/login',
          'user_code': '123456',
        };
      case '/api/auth/tv/test-pending/status':
        return {'status': 'approved'};
      case '/api/auth/tv/finalize':
        return {
          'token': 'local-fake-session',
          'user': {'id': 1, 'nickname': 'Local test'},
        };
      case '/api/auth/device/register':
        return {};
      default:
        throw StateError('Unexpected offline request: $path');
    }
  }
}

class OfflineLogoutApi extends Api {
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? query,
    dynamic body,
    bool auth = false,
  }) async => throw ApiFailure(503, 'Simulated offline server');
}

void main() {
  testWidgets(
    'TV login polls, finalizes and persists session without network',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = OfflineLoginApi();
      final session = Session(prefs, api);
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(session: session, onDone: () => finished = true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('123456'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(prefs.getString('token'), 'local-fake-session');
      final registration = object(api.calls.last['body']);
      expect(
        registration.keys,
        containsAll(['device_id', 'os', 'device_model', 'client_version']),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('Offline logout still clears local credentials', () async {
    SharedPreferences.setMockInitialValues({
      'token': 'local-fake-session',
      'user': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final session = Session(prefs, OfflineLogoutApi());
    await expectLater(session.logout(), throwsA(isA<ApiFailure>()));
    expect(session.loggedIn, isFalse);
    expect(prefs.getString('token'), isNull);
  });
}
