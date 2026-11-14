import 'package:animetka_tv/updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = <String, dynamic>{
    'version': '1.8.0',
    'versionCode': 17,
    'size': 1234,
    'sha256': 'a' * 64,
    'url': '${updateBase}v1.8.0/MJAnime-1.8.0.apk',
  };
  test('accepts stable release, rejects malformed/untrusted metadata', () {
    expect(AppRelease.parse(manifest).code, 17);
    for (final invalid in [
      {'url': 'https://evil.example/update.apk'},
      {'url': '${updateBase}v1.8.0/MJAnime-1.7.0.apk'},
      {'version': '1.8.0-beta'},
      {'versionCode': 0},
      {'size': 134217729},
      {'size': -1},
      {'sha256': 'oops'},
      {'versionCode': '17'},
    ]) {
      expect(
        () => AppRelease.parse({...manifest, ...invalid}),
        throwsFormatException,
      );
    }
  });
  test(
    'auto check throttles, respects opt-out, never installs automatically',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var fetches = 0;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(updateChannel, (call) async {
            calls.add(call.method);
            if (call.method == 'versionCode') return 16;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(updateChannel, null),
      );
      final updates = AppUpdates(
        prefs,
        fetch: () async {
          fetches++;
          return AppRelease.parse(manifest);
        },
      );
      await updates.automaticCheck();
      await updates.automaticCheck();
      expect(fetches, 1);
      expect(updates.available?.code, 17);
      expect(calls, ['versionCode']);
      await updates.check();
      expect(fetches, 2);
      await updates.install();
      expect(calls.last, 'downloadAndInstall');
      await updates.setAutomatic(false);
      await prefs.remove('updates.checked');
      await updates.automaticCheck();
      expect(fetches, 2);
    },
  );
  test(
    'same/older version is ignored; failed auto check is silent and throttled',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(updateChannel, (_) async => 17);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(updateChannel, null),
      );
      final updates = AppUpdates(
        prefs,
        fetch: () async => AppRelease.parse(manifest),
      );
      await updates.check();
      expect(updates.available, isNull);
      var tries = 0;
      final failing = AppUpdates(
        prefs,
        fetch: () async {
          tries++;
          throw Exception('offline');
        },
      );
      await failing.automaticCheck();
      await failing.automaticCheck();
      expect(tries, 1);
    },
  );
}
