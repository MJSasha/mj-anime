import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'player.dart';
import 'tv_playback.dart';
import 'cast.dart';
import 'ui.dart';
import 'cinema.dart';

class DetailsScreen extends StatefulWidget {
  final Session session;
  final int id;
  final CastTransport? cast;
  final Json? history;
  final ValueChanged<int>? onNavigate;
  const DetailsScreen({
    super.key,
    required this.session,
    required this.id,
    this.cast,
    this.history,
    this.onNavigate,
  });
  @override
  State<DetailsScreen> createState() => _DetailsState();
}

class _DetailsState extends State<DetailsScreen> {
  late Future<Json> future;
  Json anime = {}, playlist = {};
  int tab = 0, request = 0;
  final episodeShots = <int, String>{};
  final requestedShots = <int>{};
  int? tid;
  Json? resumeEntry;
  final playbackActionFocus = FocusNode(debugLabel: 'Detail playback');
  final backFocus = FocusNode(debugLabel: 'Detail back');
  final recoveryFocus = FocusNode(debugLabel: 'Episode recovery');
  bool descending = false, loadingPlaylist = false;
  String? playlistError;
  @override
  void initState() {
    super.initState();
    widget.session.markOpened(widget.id);
    future = widget.session.api.detail(widget.id);
    resumeEntry =
        widget.history ??
        widget.session.localHistory
            .where((h) => animeId(h) == widget.id)
            .firstOrNull;
    tid = resumeEntry?['tid'] == null ? null : number(resumeEntry!['tid']);
    loadPlaylist(tid);
    loadFavorites();
  }

  @override
  void dispose() {
    playbackActionFocus.dispose();
    backFocus.dispose();
    recoveryFocus.dispose();
    super.dispose();
  }

  Future<void> loadFavorites() async {
    if (!widget.session.loggedIn) return;
    try {
      final p = object(
        await widget.session.api.request('/api/user/profile/me', auth: true),
      );
      final list = p['favorite_voices'] is List
          ? (p['favorite_voices'] as List)
                .map((v) => v is Map ? '${v['name'] ?? v['title']}' : '$v')
                .toList()
          : <String>[];
      await widget.session.prefs.setStringList('favoriteVoices', list);
      if (mounted) setState(() {});
    } catch (_) {
      /* Keep the last known local preferences while offline. */
    }
  }

  Future<void> loadPlaylist([int? id]) async {
    final seq = ++request;
    setState(() {
      loadingPlaylist = true;
      playlistError = null;
    });
    try {
      var p = await widget.session.api.playlist(widget.id, id);
      if (id == null) {
        final name = widget.session.prefs.getString('lastTranslationName');
        final match = objects(p['translations'])
            .where((t) => t['name'] == name)
            .firstOrNull;
        if (match != null && match['selected'] != true) {
          id = number(match['value']);
          p = await widget.session.api.playlist(widget.id, id);
        }
      }
      if (!mounted || seq != request) return;
      setState(() {
        playlist = p;
        tid =
            id ??
            objects(p['translations'])
                .where((e) => e['selected'] == true)
                .map((e) => number(e['value']))
                .firstOrNull;
      });
    } catch (e) {
      if (mounted && seq == request) setState(() => playlistError = '$e');
    } finally {
      if (mounted && seq == request) {
        setState(() => loadingPlaylist = false);
        if (seq == 1 || recoveryFocus.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
            (playlistError != null
                    ? recoveryFocus
                    : objects(playlist['list']).isEmpty
                    ? backFocus
                    : playbackActionFocus)
                .requestFocus();
          });
        }
      }
    }
  }

  Future<void> selectVoice(Json translation) async {
    await widget.session.prefs.setString(
      'lastTranslationName',
      '${translation['name']}',
    );
    await loadPlaylist(number(translation['value']));
  }

  List<String> get favoriteVoices =>
      widget.session.prefs.getStringList('favoriteVoices') ?? [];
  Future<void> toggleVoice(String name) async {
    try {
      var favorites = favoriteVoices.toSet();
      if (widget.session.loggedIn) {
        final profile = object(
          await widget.session.api.request('/api/user/profile/me', auth: true),
        );
        favorites =
            (profile['favorite_voices'] is List
                    ? (profile['favorite_voices'] as List).map(
                        (v) => v is Map ? '${v['name'] ?? v['title']}' : '$v',
                      )
                    : <String>[])
                .toSet();
      }
      favorites.contains(name) ? favorites.remove(name) : favorites.add(name);
      if (widget.session.loggedIn) {
        await widget.session.api.request(
          '/api/user/profile/me',
          method: 'PATCH',
          auth: true,
          body: {'favorite_voices': favorites.toList()},
        );
      }
      await widget.session.prefs.setStringList(
        'favoriteVoices',
        favorites.toList(),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Future<void> loadShots(int offset) async {
    if (!requestedShots.add(offset)) return;
    try {
      final raw = object(
        await widget.session.api.request(
          '/api/anime/screenshots',
          query: {'material': widget.id, 'offset': offset, 'limit': 20},
        ),
      );
      if (!mounted) return;
      setState(() {
        for (final item in objects(raw['items'])) {
          if (item['url'] is String && item['ready'] == true) {
            episodeShots[number(item['serie_num'])] = item['url'];
          }
        }
      });
    } catch (_) {
      requestedShots.remove(offset);
    }
  }

  void play(int index, {bool resume = false}) {
    final eps = objects(playlist['list']);
    if (eps.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          session: widget.session,
          anime: anime,
          playlist: playlist,
          index: index,
          tid: tid,
          startPosition: resume ? number(resumeEntry?['timestamp']) : 0,
          cast: widget.cast,
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        resumeEntry =
            widget.session.localHistory
                .where((h) => animeId(h) == widget.id)
                .firstOrNull ??
            resumeEntry;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          playbackActionFocus.requestFocus();
        }
      });
    });
  }

  Future<void> favorite() async {
    if (!widget.session.loggedIn) {
      errorMessage(
        context,
        'Войдите в аккаунт, чтобы добавлять аниме в списки',
      );
      return;
    }
    try {
      final folders = objects(
        await widget.session.api.request('/api/user/folder', auth: true),
      );
      if (!mounted) return;
      final id = await showDialog<int>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Добавить в список'),
          content: SizedBox(
            width: 550,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (folders.isEmpty)
                  const Text('Сначала создайте список в разделе «Мои списки»'),
                for (var i = 0; i < folders.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: labelButton(
                        '${folders[i]['title']}',
                        () => Navigator.pop(d, number(folders[i]['id'])),
                        autofocus: i == 0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            labelButton(
              'Отмена',
              () => Navigator.pop(d),
              autofocus: folders.isEmpty,
            ),
          ],
        ),
      );
      if (id == null) return;
      await widget.session.api.request(
        '/api/user/folder/add',
        method: 'POST',
        auth: true,
        body: {'folder_id': id, 'animetka_id': widget.id},
      );
      if (mounted) errorMessage(context, 'Добавлено в список');
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Widget detailAction(
    String text,
    IconData icon,
    VoidCallback? action, {
    FocusNode? focusNode,
  }) => SizedBox(
    width: double.infinity,
    child: TvButton(
      focusNode: focusNode,
      outlined: true,
      onPressed: action,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 23),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Row(
        children: [
          CinemaRail(
            section: -1,
            onSelect: (index) {
              if (widget.onNavigate != null) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                widget.onNavigate!(index);
              } else {
                Navigator.maybePop(context);
              }
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              child: LoadView(
                future: future,
                retry: () => setState(() {
                  future = widget.session.api.detail(widget.id);
                }),
                builder: (data) {
                  anime = object(data);
                  final eps = objects(playlist['list']);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 164,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 82,
                              height: 124,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: photo(
                                  poster(anime),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 22),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title(anime),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        '${anime['year'] ?? '—'} · ${anime['episodes_total'] ?? '—'} серий · ',
                                        style: TextStyle(
                                          fontSize: 17,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      Icon(
                                        Icons.star_rounded,
                                        size: 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      Text(
                                        ' ${anime['shikimori_rating'] ?? '—'}',
                                        style: TextStyle(
                                          fontSize: 17,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      TvButton(
                                        primary: true,
                                        autofocus: true,
                                        focusNode: playbackActionFocus,
                                        onPressed: eps.isEmpty
                                            ? null
                                            : () => play(
                                                resumeEntry == null
                                                    ? 0
                                                    : (number(
                                                                resumeEntry!['episode'],
                                                                1,
                                                              ) -
                                                              1)
                                                          .clamp(
                                                            0,
                                                            eps.length - 1,
                                                          ),
                                                resume: resumeEntry != null,
                                              ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.play_arrow_rounded,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              resumeEntry == null
                                                  ? 'Смотреть'
                                                  : 'Продолжить',
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (resumeEntry != null) ...[
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message: 'С первой серии',
                                          child: Semantics(
                                            label: 'С первой серии',
                                            child: TvButton(
                                              subtle: true,
                                              onPressed: eps.isEmpty
                                                  ? null
                                                  : () => play(0),
                                              padding: const EdgeInsets.all(12),
                                              child: const Icon(
                                                Icons.restart_alt_rounded,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 12),
                                      labelButton(
                                        'В список',
                                        favorite,
                                        icon: Icons.bookmark_add_outlined,
                                      ),
                                      if (resumeEntry != null) ...[
                                        const SizedBox(width: 18),
                                        Expanded(
                                          child: Text(
                                            'Серия ${resumeEntry!['episode'] ?? 1} · ${playbackTime(Duration(seconds: number(resumeEntry!['timestamp'])))}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            labelButton(
                              'Назад',
                              () => Navigator.pop(context),
                              icon: Icons.arrow_back_rounded,
                              focusNode: backFocus,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        children: List.generate(
                          5,
                          (i) => tabButton(
                            const [
                              'Серии',
                              'Информация',
                              'Кадры',
                              'Персонажи',
                              'Сезоны',
                            ][i],
                            () => setState(() => tab = i),
                            selected: tab == i,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: [
                          episodes(),
                          information(),
                          gallery(),
                          characters(),
                          franchise(),
                        ][tab],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> voices() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Озвучка'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: ListView(
            children: [
              for (final t in objects(playlist['translations']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: labelButton(
                          '${t['name']}${t['subs'] == true ? ' · SUB' : ''}',
                          () {
                            Navigator.pop(dialog);
                            selectVoice(t);
                          },
                          selected: tid == number(t['value']),
                          autofocus: tid == number(t['value']),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Любимая озвучка',
                        onPressed: () async {
                          await toggleVoice('${t['name']}');
                          if (dialog.mounted) {
                            (dialog as Element).markNeedsBuild();
                          }
                        },
                        icon: Icon(
                          favoriteVoices.contains(t['name'])
                              ? Icons.star
                              : Icons.star_border,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [labelButton('Закрыть', () => Navigator.pop(dialog))],
      ),
    );
  }

  Widget episodes() {
    if (loadingPlaylist) {
      return const Center(child: CircularProgressIndicator());
    }
    if (playlistError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(playlistError!),
            labelButton(
              'Повторить',
              () => loadPlaylist(tid),
              autofocus: true,
              focusNode: recoveryFocus,
            ),
          ],
        ),
      );
    }
    final eps = objects(playlist['list']);
    final translations = objects(playlist['translations']);
    final voice = translations
        .where((t) => tid == number(t['value']))
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Text(
                'Серии · ${eps.length}',
                style: TextStyle(
                  fontSize: 17,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Tooltip(
                  message: 'Озвучка',
                  child: TvButton(
                    subtle: true,
                    onPressed: translations.isEmpty ? null : voices,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.graphic_eq_rounded, size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            '${voice?['name'] ?? 'Выбрать озвучку'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.expand_more_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TvButton(
                subtle: true,
                onPressed: () => setState(() => descending = !descending),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort_rounded, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      descending ? 'Сначала новые' : 'Сначала старые',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: eps.isEmpty
              ? const Center(child: Text('Серии пока недоступны'))
              : GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.12,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: eps.length,
                  itemBuilder: (c, i) {
                    final index = descending ? eps.length - 1 - i : i;
                    final ep = eps[index];
                    loadShots((index ~/ 20) * 20);
                    final shot =
                        episodeShots[index + 1] ??
                        ep['screenshot'] ??
                        ep['image'] ??
                        scenery(anime);
                    final resumeEpisode =
                        resumeEntry != null &&
                        number(resumeEntry!['episode'], 1) == index + 1;
                    final name = '${ep['title'] ?? ''}'.trim();
                    final generic = RegExp(
                      r'^(?:серия\s*\d+|\d+\s*серия|episode\s*\d+)$',
                      caseSensitive: false,
                    ).hasMatch(name);
                    final caption = name.isEmpty || generic
                        ? 'Серия ${index + 1}'
                        : 'Серия ${index + 1} · $name';
                    return Semantics(
                      label: caption,
                      child: TvButton(
                        key: ValueKey('episode-${index + 1}'),
                        selected: resumeEpisode,
                        outlined: resumeEpisode,
                        onPressed: () => play(index, resume: resumeEpisode),
                        padding: const EdgeInsets.all(3),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              photo('$shot'),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.center,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black87,
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 9,
                                left: 9,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: darkBg.withValues(alpha: .92),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${index + 1}'.padLeft(2, '0'),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              if (resumeEpisode)
                                const Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: accent,
                                    size: 28,
                                  ),
                                ),
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 10,
                                child: Text(
                                  caption,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.15,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget information() => TvScrollPane(
    label: 'Описание аниме',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${anime['year'] ?? ''} · ${anime['anime_kind'] ?? ''} · ${anime['episodes_total'] ?? '—'} эп.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${anime['anime_description'] ?? anime['description'] ?? 'Описание отсутствует'}',
          style: const TextStyle(fontSize: 17, height: 1.6),
        ),
        const SizedBox(height: 20),
        for (final key in [
          'anime_genres',
          'anime_studios',
          'directors',
          'actors',
          'countries',
        ])
          if (anime[key] is List)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${{'anime_genres': 'Жанры', 'anime_studios': 'Студии', 'directors': 'Режиссёры', 'actors': 'Актёры', 'countries': 'Страны'}[key]}: ${(anime[key] as List).join(', ')}',
              ),
            ),
        if (anime['minimal_age'] != null)
          Text('Возраст: ${anime['minimal_age']}+'),
      ],
    ),
  );
  Widget gallery() {
    final shots = anime['screenshots'] is List
        ? List.of(anime['screenshots'])
        : [];
    return shots.isEmpty
        ? const Center(child: Text('Кадров пока нет'))
        : GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.78,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: shots.length,
            itemBuilder: (c, i) => TvButton(
              onPressed: () => showDialog(
                context: context,
                builder: (d) => Dialog(
                  child: Stack(
                    children: [
                      photo('${shots[i]}', fit: BoxFit.contain),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: labelButton(
                          'Закрыть',
                          () => Navigator.pop(d),
                          autofocus: true,
                          icon: Icons.close_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              padding: EdgeInsets.zero,
              child: photo('${shots[i]}'),
            ),
          );
  }

  Widget characters() => CharacterPanel(session: widget.session, anime: anime);
  Widget franchise() {
    final raw = anime['franchise'];
    final items = objects(
      raw is Map ? (raw['nodes'] ?? raw['items'] ?? raw['animes']) : raw,
    );
    return AnimeGrid(
      items: items,
      emptyMessage: 'Связанных сезонов пока нет',
      emptyHint: 'Серии и информация доступны в соседних вкладках',
      onOpen: (a) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DetailsScreen(
            session: widget.session,
            id: animeId(a),
            cast: widget.cast,
            onNavigate: widget.onNavigate,
          ),
        ),
      ),
    );
  }
}

class CharacterPanel extends StatefulWidget {
  final Session session;
  final Json anime;
  const CharacterPanel({super.key, required this.session, required this.anime});
  @override
  State<CharacterPanel> createState() => _CharacterState();
}

class _CharacterState extends State<CharacterPanel> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<dynamic> load() => widget.session.api.request(
    '/api/anime/${animeId(widget.anime)}/characters',
  );
  @override
  Widget build(BuildContext context) => LoadView(
    future: future,
    retry: () => setState(() {
      future = load();
    }),
    builder: (raw) {
      final items = objects(
        raw is Map ? raw['items'] ?? raw['characters'] ?? raw['data'] : raw,
      );
      if (items.isEmpty) {
        return const TvEmptyState(
          title: 'Персонажи пока не добавлены',
          hint: 'Выберите серии, информацию или другую вкладку сверху',
        );
      }
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          childAspectRatio: .7,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final a = object(items[i]['character'] ?? items[i]);
          final image = a['image'];
          final url =
              a['image_url'] ??
              a['poster_url'] ??
              (image is Map ? image['original'] ?? image['preview'] : image) ??
              '';
          return TvButton(
            onPressed: () => showCharacter(a),
            child: Column(
              children: [
                Expanded(child: photo('$url')),
                Text('${a['russian'] ?? a['name'] ?? ''}', maxLines: 2),
              ],
            ),
          );
        },
      );
    },
  );
  Future<void> showCharacter(Json item) async {
    final id = number(item['character_shikimori_id'] ?? item['id']);
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${item['russian'] ?? item['name'] ?? 'Персонаж'}'),
        content: SizedBox(
          width: 850,
          height: 440,
          child: LoadView(
            future: widget.session.api.request('/api/anime/characters/$id'),
            builder: (raw) {
              final character = {...item, ...object(raw)};
              final description = '${character['description'] ?? ''}'
                  .replaceAll(RegExp(r'\[[^\]]+\]'), '');
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 200,
                    child: photo(
                      '${character['poster_url'] ?? item['poster_url'] ?? ''}',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: TvScrollPane(
                      label: 'Описание персонажа',
                      child: Text(
                        description.isEmpty
                            ? 'Описание пока отсутствует'
                            : description,
                        style: const TextStyle(fontSize: 16, height: 1.6),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          labelButton(
            'В избранное',
            () => favorite(item),
            icon: Icons.bookmark_add_outlined,
          ),
          labelButton('Закрыть', () => Navigator.pop(d), autofocus: true),
        ],
      ),
    );
  }

  Future<void> favorite(Json a) async {
    if (!widget.session.loggedIn) {
      errorMessage(context, 'Войдите в аккаунт');
      return;
    }
    try {
      await widget.session.api.request(
        '/api/user/profile/favorite-characters',
        method: 'POST',
        auth: true,
        body: {
          'character_shikimori_id': a['character_shikimori_id'] ?? a['id'],
        },
      );
      if (mounted) errorMessage(context, 'Персонаж добавлен в избранное');
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }
}
