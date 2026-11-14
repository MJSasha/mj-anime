import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui.dart';

const upscalePreference = 'videoUpscaleMode';
const upscaleModes = ['off', 'light', 'cnn_s', 'cnn_m'];
String readUpscaleMode(SharedPreferences prefs) {
  final mode = prefs.getString(upscalePreference);
  return upscaleModes.contains(mode) ? mode! : 'off';
}

// One-time reset of the broken 1.6.0 pipeline, before opening any video.
Future<void> initializeVideoProcessing(SharedPreferences prefs) async {
  if ((prefs.getInt('upscaleSurfaceRevision') ?? 0) >= 1) return;
  await prefs.setString(upscalePreference, 'off');
  await prefs.setInt('upscaleSurfaceRevision', 1);
}

class VideoUpscale {
  static const channel = MethodChannel('dev.independent.animetka/upscale');
  static final status = ValueNotifier<String?>(null);
  static final failure = ValueNotifier<String?>(null);
  static Future<bool> configure(String mode) async {
    if (!upscaleModes.contains(mode)) throw ArgumentError.value(mode, 'mode');
    status.value = null;
    failure.value = null;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'status' && call.arguments is String) {
        status.value = call.arguments as String;
      }
      if (call.method == 'failure' && call.arguments is String) {
        failure.value = call.arguments as String;
      }
    });
    try {
      await channel.invokeMethod<void>('setMode', mode);
      return true;
    } on MissingPluginException {
      return mode == 'off';
    } on PlatformException {
      return false;
    }
  }
}

class AnimeUpscaleSelector extends StatelessWidget {
  final String mode;
  final ValueChanged<String>? onChanged;
  final bool showStatus, autofocus;
  const AnimeUpscaleSelector({
    super.key,
    required this.mode,
    required this.onChanged,
    this.showStatus = false,
    this.autofocus = false,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Улучшение изображения', style: TextStyle(fontSize: 21)),
      const SizedBox(height: 12),
      if (showStatus)
        SizedBox(
          height: 54,
          child: ValueListenableBuilder<String?>(
            valueListenable: VideoUpscale.status,
            builder: (_, message, _) => Text(
              message == null ? '' : 'Сейчас: $message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in const [
            ('off', 'Выключено'),
            ('light', 'Лёгкий · контуры'),
            ('cnn_s', 'Нейро S'),
            ('cnn_m', 'Нейро M'),
          ])
            labelButton(
              item.$2,
              onChanged == null ? null : () => onChanged!(item.$1),
              selected: mode == item.$1,
              autofocus: autofocus && mode == item.$1,
            ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        'S — быстрее, M — тяжелее. Нейро: видео 360–720p, вывод Full HD. Для 1080p — лёгкая обработка.',
        style: TextStyle(
          fontSize: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
