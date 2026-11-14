import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'player.dart';
import 'ui.dart';

Future<void> openLocalVideoCheck(BuildContext context, Session session) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          session: session,
          anime: const {'id': -1, 'anime_title': 'Локальная проверка видео'},
          playlist: const {
            'list': [
              {'title': 'Локальный ролик', 'file': '[720]local-check.mp4'},
            ],
            'translations': [],
          },
          index: 0,
          isVideoCheck: true,
        ),
      ),
    );

/// Uses the real PlayerScreen, decoder, GPU effects and Flutter texture. No backend or account.
class LocalVideoCheckHome extends StatelessWidget {
  final Session session;
  const LocalVideoCheckHome({super.key, required this.session});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Проверка воспроизведения',
              style: TextStyle(fontSize: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Локальный H.264-ролик: движущаяся метка и номер кадра. Сервер и аккаунт не используются.',
            ),
            const SizedBox(height: 24),
            primaryButton(
              'Начать проверку',
              () => openLocalVideoCheck(context, session),
              autofocus: true,
              icon: Icons.play_arrow_rounded,
            ),
          ],
        ),
      ),
    ),
  );
}
