import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'ui.dart';

const platform = MethodChannel('dev.independent.animetka/native');

class LoginScreen extends StatefulWidget {
  final Session session;
  final VoidCallback onDone;
  final VoidCallback? onTheme;
  const LoginScreen({
    super.key,
    required this.session,
    required this.onDone,
    this.onTheme,
  });
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  int tab = 0, epoch = 0;
  Json session = {};
  String? error;
  bool busy = false, polling = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    start();
  }

  @override
  void dispose() {
    epoch++;
    timer?.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final e = ++epoch;
    timer?.cancel();
    if (!mounted) return;
    setState(() {
      session = {};
      error = null;
      busy = true;
    });
    if (tab == 2) {
      setState(() => busy = false);
      return;
    }
    try {
      final data = object(
        await widget.session.api.request(
          tab == 0 ? '/api/auth/tv/start' : '/api/auth/telegram/start',
          method: 'POST',
          body: {
            'device_id': widget.session.deviceId,
            'platform': 'android',
            'device_label': 'MJAnime · Android TV',
          },
        ),
      );
      if (!mounted || e != epoch) return;
      setState(() => session = data);
      timer = Timer.periodic(const Duration(seconds: 3), (_) => poll(e));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> poll(int e) async {
    if (polling || !mounted || epoch != e) return;
    polling = true;
    try {
      final type = tab == 0 ? 'tv' : 'telegram/start';
      final token = session['token'];
      if (token == null) return;
      final r = object(
        await widget.session.api.request('/api/auth/$type/$token/status'),
      );
      if (epoch != e || !mounted) return;
      if (r['status'] == 'expired') {
        timer?.cancel();
        setState(() => error = 'Код истёк. Обновите QR.');
      } else if ([
        'authorized',
        'approved',
        'confirmed',
        'completed',
        'ready',
      ].contains(r['status'])) {
        timer?.cancel();
        final data = object(
          await widget.session.api.request(
            '/api/auth/$type/finalize',
            method: 'POST',
            body: {'token': token},
          ),
        );
        await finish(data);
      }
    } catch (err) {
      if (mounted && epoch == e) setState(() => error = '$err');
    } finally {
      polling = false;
    }
  }

  Future<void> finish(Json data) async {
    if (data['requires_password'] == true || data['pending_token'] != null) {
      if (!mounted) return;
      final password = await textPrompt(
        context,
        'Пароль аккаунта',
        password: true,
      );
      if (password == null) return;
      data = object(
        await widget.session.api.request(
          '/api/auth/password/confirm-login',
          method: 'POST',
          body: {'pending_token': data['pending_token'], 'password': password},
        ),
      );
    }
    await widget.session.save(data);
    if (mounted) widget.onDone();
  }

  Future<void> phrase() async {
    final words = await textPrompt(
      context,
      'Введите фразу через пробел',
      password: true,
    );
    if (words == null || words.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await finish(
        object(
          await widget.session.api.request(
            '/api/auth/mnemonic/login',
            method: 'POST',
            body: {'words': words.trim().split(RegExp(r'\s+'))},
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
    floatingActionButton: widget.onTheme == null
        ? null
        : IconButton(
            tooltip: 'Сменить тему',
            onPressed: widget.onTheme,
            icon: const Icon(Icons.light_mode),
          ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: SizedBox(
          width: 840,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MJ / ANIME',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Регистрация без Telegram доступна на сайте animetka.com',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: const EdgeInsets.all(5),
                    child: tabButton(
                      ['Приложение', 'Telegram', 'Фраза'][i],
                      () {
                        setState(() => tab = i);
                        start();
                      },
                      selected: tab == i,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xff303744)),
                ),
                child: busy
                    ? const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : tab == 2
                    ? Column(
                        children: [
                          const Text(
                            'Войдите по фразе, сохранённой при регистрации',
                          ),
                          const SizedBox(height: 20),
                          labelButton('Ввести фразу', phrase, autofocus: true),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tab == 0
                                      ? 'Отсканируй QR в приложении AniMetka или введи код под QR'
                                      : 'Отсканируй QR телефоном и подтверди вход в Telegram',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                labelButton(
                                  'Обновить QR',
                                  start,
                                  autofocus: true,
                                ),
                                const SizedBox(height: 16),
                                if (session.isNotEmpty)
                                  Text(
                                    'Ждём подтверждение…',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                if (tab == 1 && session['url'] != null)
                                  labelButton(
                                    'Открыть Telegram на этом устройстве',
                                    () => platform.invokeMethod(
                                      'openUrl',
                                      session['url'],
                                    ),
                                    icon: Icons.open_in_new_rounded,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 35),
                          if (session['url'] != null)
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: QrImageView(
                                    data: '${session['url']}',
                                    size: 180,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                                if (tab == 0)
                                  Text(
                                    '${session['user_code'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      letterSpacing: 5,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              const SizedBox(height: 18),
              labelButton('Продолжить без аккаунта', () async {
                await widget.session.prefs.setBool('guest', true);
                if (mounted) widget.onDone();
              }),
            ],
          ),
        ),
      ),
    ),
  );
}
