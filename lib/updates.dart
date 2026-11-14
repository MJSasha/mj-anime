import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui.dart';

const updateChannel = MethodChannel('dev.mjanime/updates');
const updateBase = 'https://github.com/MJSasha/mj-anime/releases/download/';
const updateManifest =
    'https://github.com/MJSasha/mj-anime/releases/latest/download/update.json';

class AppRelease {
  final String version, sha256;
  final int code, size;
  final Uri url;
  const AppRelease(this.version, this.code, this.size, this.sha256, this.url);

  factory AppRelease.parse(Map<String, dynamic> json) {
    final version = json['version'];
    final code = json['versionCode'];
    final size = json['size'];
    final hash = json['sha256'];
    final url = json['url'];
    if (version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        code is! int ||
        code <= 0 ||
        size is! int ||
        size <= 0 ||
        size > 128 * 1024 * 1024 ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        url != '${updateBase}v$version/MJAnime-$version.apk') {
      throw const FormatException('Некорректные данные обновления');
    }
    return AppRelease(version, code, size, hash, Uri.parse(url as String));
  }
}

// No account headers, cookies or backend client are used for GitHub requests.
Future<AppRelease> fetchAppRelease() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    var uri = Uri.parse(updateManifest);
    HttpClientResponse? response;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          !const {
            'github.com',
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          }.contains(uri.host)) {
        throw const FormatException('Недоверенный адрес обновления');
      }
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'MJAnime-Updater');
      response = await request.close().timeout(const Duration(seconds: 20));
      if (!const {301, 302, 303, 307, 308}.contains(response.statusCode)) break;
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || redirects == 5) {
        throw const HttpException('Некорректное перенаправление GitHub');
      }
      uri = uri.resolve(location);
      await response.drain<void>().timeout(const Duration(seconds: 20));
    }
    if (response == null) throw const HttpException('Нет ответа GitHub');
    if (response.statusCode != 200) {
      throw const HttpException('Не удалось получить релиз GitHub');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 16384) {
        throw const FormatException('Слишком большой ответ обновления');
      }
    }
    return AppRelease.parse(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

class AppUpdates {
  final SharedPreferences prefs;
  final Future<AppRelease> Function() fetch;
  final MethodChannel channel;
  AppRelease? available;
  AppUpdates(
    this.prefs, {
    this.fetch = fetchAppRelease,
    this.channel = updateChannel,
  });

  bool get automatic => prefs.getBool('updates.auto') ?? true;
  Future<void> setAutomatic(bool value) => prefs.setBool('updates.auto', value);

  Future<void> automaticCheck() async {
    final last = prefs.getInt('updates.checked') ?? 0;
    if (!automatic || DateTime.now().millisecondsSinceEpoch - last < 86400000) {
      return;
    }
    // Failed requests are also throttled; manual retry is always available.
    await prefs.setInt(
      'updates.checked',
      DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await check();
    } catch (_) {
      // GitHub being unavailable must not interrupt browsing or playback.
    }
  }

  Future<void> check() async {
    final code = await channel.invokeMethod<int>('versionCode');
    if (code == null) throw StateError('Версия Android недоступна');
    final release = await fetch();
    available = release.code > code ? release : null;
  }

  Future<void> install() async {
    final release = available;
    if (release == null) return;
    await channel.invokeMethod<void>('downloadAndInstall', {
      'url': release.url.toString(),
      'size': release.size,
      'sha256': release.sha256,
    });
  }

  Future<void> cancel() => channel.invokeMethod<void>('cancel');
}

class UpdateDialog extends StatefulWidget {
  final AppUpdates updates;
  final String currentVersion;
  const UpdateDialog({
    super.key,
    required this.updates,
    required this.currentVersion,
  });
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool busy = false, downloading = false;
  String? message;
  final closeFocus = FocusNode(debugLabel: 'Close updates');

  @override
  void dispose() {
    closeFocus.dispose();
    super.dispose();
  }

  Future<void> perform(bool install) async {
    setState(() {
      busy = true;
      downloading = install;
      message = null;
    });
    try {
      if (install) {
        await widget.updates.install();
        message = 'Подтвердите установку в окне Android.';
      } else {
        await widget.updates.check();
        if (widget.updates.available == null) {
          message = 'Установлена последняя версия.';
        }
      }
    } on PlatformException catch (e) {
      message = e.code == 'cancelled' ? 'Загрузка отменена.' : e.message;
    } catch (_) {
      message = 'Не удалось проверить обновление. Проверьте доступ к GitHub и повторите.';
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          downloading = false;
        });
        closeFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.updates.available;
    return PopScope(
      canPop: !downloading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && downloading) widget.updates.cancel();
      },
      child: AlertDialog(
        title: const Text('Обновление MJAnime'),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Установлена версия ${widget.currentVersion}'),
              const SizedBox(height: 16),
              if (release != null)
                Text(
                  'Доступна ${release.version} · ${(release.size / 1048576).toStringAsFixed(1)} МБ',
                ),
              if (busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  downloading ? 'Загрузка и проверка APK…' : 'Проверка GitHub…',
                ),
              ],
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(message!),
                ),
              const SizedBox(height: 20),
              labelButton(
                'Автопроверка раз в сутки: ${widget.updates.automatic ? 'вкл' : 'выкл'}',
                busy
                    ? null
                    : () async {
                        await widget.updates.setAutomatic(
                          !widget.updates.automatic,
                        );
                        if (mounted) setState(() {});
                      },
                icon: widget.updates.automatic
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
              ),
            ],
          ),
        ),
        actions: [
          labelButton(
            downloading ? 'Отменить загрузку' : 'Закрыть',
            downloading ? widget.updates.cancel : () => Navigator.pop(context),
            focusNode: closeFocus,
            autofocus: true,
          ),
          labelButton('Проверить', busy ? null : () => perform(false)),
          if (release != null)
            labelButton(
              'Скачать и установить',
              busy ? null : () => perform(true),
              icon: Icons.system_update_outlined,
            ),
        ],
      ),
    );
  }
}
