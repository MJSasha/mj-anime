import 'package:animetka_tv/anime_upscale.dart';
import 'package:animetka_tv/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Upgrade starts with normal video instead of a saved broken effect',
    () async {
      SharedPreferences.setMockInitialValues({upscalePreference: 'cnn_m'});
      final prefs = await SharedPreferences.getInstance();
      await initializeVideoProcessing(prefs);
      expect(readUpscaleMode(prefs), 'off');
    },
  );
  test(
    'Upgrade reset happens once and preserves subsequent user choices',
    () async {
      SharedPreferences.setMockInitialValues({upscalePreference: 'cnn_m'});
      final prefs = await SharedPreferences.getInstance();
      await initializeVideoProcessing(prefs);
      await prefs.setString(upscalePreference, 'cnn_s');
      await initializeVideoProcessing(prefs);
      expect(readUpscaleMode(prefs), 'cnn_s');
    },
  );

  test(
    'Off is the default and invalid saved modes never enable processing',
    () async {
      SharedPreferences.setMockInitialValues({upscalePreference: 'unknown'});
      final prefs = await SharedPreferences.getInstance();
      expect(readUpscaleMode(prefs), 'off');
      for (final mode in upscaleModes) {
        await prefs.setString(upscalePreference, mode);
        expect(readUpscaleMode(prefs), mode);
      }
    },
  );

  testWidgets(
    'All three levels and off can be selected using only remote arrows and OK',
    (tester) async {
      var mode = 'off';
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: mjTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, update) => AnimeUpscaleSelector(
                mode: mode,
                onChanged: (v) => update(() => mode = v),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final off = find.widgetWithText(TvButton, 'Выключено');
      Focus.of(
        tester.element(
          find.descendant(of: off, matching: find.byType(InkWell)),
        ),
      ).requestFocus();
      await tester.pumpAndSettle();
      for (final expected in ['light', 'cnn_s', 'cnn_m']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(mode, expected);
      }
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(mode, 'off');
    },
  );

  testWidgets(
    'Native status reports the actual fallback instead of implying CNN is active',
    (tester) async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        VideoUpscale.channel,
        (_) async => null,
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          VideoUpscale.channel,
          null,
        ),
      );
      await VideoUpscale.configure('cnn_s');
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        VideoUpscale.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('status', 'Лёгкий · CNN недоступна на GPU'),
        ),
        (_) {},
      );
      expect(VideoUpscale.status.value, contains('Лёгкий'));
      await tester.pumpWidget(
        MaterialApp(
          home: AnimeUpscaleSelector(
            mode: 'cnn_s',
            showStatus: true,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.textContaining('Сейчас: Лёгкий'), findsOneWidget);
    },
  );
}
