import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'ui.dart';

class ProfileScreen extends StatefulWidget {
  final Session session;
  const ProfileScreen({super.key, required this.session});
  @override
  State<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileScreen> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    future = widget.session.api.request('/api/user/profile/me', auth: true);
  }

  Future<void> edit(Json profile) async {
    final draft = <String, String>{
      for (final key in ['nickname', 'bio', 'city'])
        key: '${profile[key] ?? ''}',
    };
    final saved = await showDialog<Json>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, update) => AlertDialog(
          title: const Text('Редактировать профиль'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in {
                    'nickname': 'Никнейм',
                    'bio': 'О себе',
                    'city': 'Город',
                  }.entries) ...[
                    TvTextEntry(
                      label: entry.value,
                      value: draft[entry.key]!,
                      autofocus: entry.key == 'nickname',
                      maxLines: entry.key == 'bio' ? 3 : 1,
                      onChanged: (value) =>
                          update(() => draft[entry.key] = value),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            labelButton('Отмена', () => Navigator.pop(d)),
            labelButton(
              'Сохранить',
              () => Navigator.pop(d, Map<String, dynamic>.from(draft)),
              icon: Icons.check_rounded,
            ),
          ],
        ),
      ),
    );
    if (saved != null) {
      try {
        await widget.session.api.request(
          '/api/user/profile/me',
          method: 'PATCH',
          auth: true,
          body: {
            'nickname': '${saved['nickname']}'.trim(),
            'bio': saved['bio'],
            'city': saved['city'],
          },
        );
        if (mounted) setState(reload);
      } catch (e) {
        if (mounted) errorMessage(context, e);
      }
    }
  }

  Future<void> removeCharacter(int id) async {
    try {
      await widget.session.api.request(
        '/api/user/profile/favorite-characters/$id',
        method: 'DELETE',
        auth: true,
      );
      if (mounted) setState(reload);
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мой профиль')),
    body: LoadView(
      future: future,
      retry: () => setState(reload),
      builder: (raw) {
        final p = object(raw);
        final stats = object(p['stats']);
        final chars = objects(p['favorite_characters']);
        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p['avatar_url'] != null)
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: ClipOval(child: photo('${p['avatar_url']}')),
                  ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['display_name'] ?? p['nickname'] ?? p['username'] ?? 'Мой профиль'}',
                        style: const TextStyle(fontSize: 30),
                      ),
                      if (p['telegram_username'] != null)
                        Text(
                          '@${p['telegram_username']}',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      if (p['bio'] != null) Text('${p['bio']}'),
                      if (p['city'] != null) Text('${p['city']}'),
                    ],
                  ),
                ),
                labelButton('Редактировать', () => edit(p), autofocus: true),
              ],
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 24,
              children: [
                for (final key in ['total', 'watching', 'completed', 'planned'])
                  Text(
                    '${{'total': 'Всего', 'watching': 'Смотрю', 'completed': 'Просмотрено', 'planned': 'Запланировано'}[key]}: ${stats[key] ?? 0}',
                  ),
              ],
            ),
            const SizedBox(height: 24),
            for (final key in ['favorite_genres', 'favorite_voices'])
              if (p[key] is List) ...[
                Text(
                  key == 'favorite_genres'
                      ? 'Любимые жанры'
                      : 'Любимые озвучки',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: (p[key] as List)
                      .map(
                        (v) => Chip(
                          label: Text(
                            v is Map
                                ? '${v['name'] ?? v['title'] ?? ''}'
                                : '$v',
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
              ],
            const Text('Любимые персонажи', style: TextStyle(fontSize: 22)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: chars
                  .map(
                    (c) => SizedBox(
                      width: 150,
                      child: Column(
                        children: [
                          SizedBox(
                            height: 180,
                            child: photo('${c['poster_url'] ?? ''}'),
                          ),
                          Text('${c['russian'] ?? c['name'] ?? ''}'),
                          labelButton(
                            'Убрать',
                            () => removeCharacter(
                              number(c['character_shikimori_id']),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
    ),
  );
}
