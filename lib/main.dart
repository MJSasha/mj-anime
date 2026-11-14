import 'dart:convert';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'auth.dart';
import 'details.dart';
import 'player.dart';
import 'cast.dart';
import 'account.dart';
import 'filters.dart';
import 'ui.dart';
import 'anime_upscale.dart';
import 'local_video_check.dart';
import 'cinema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final prefs = await SharedPreferences.getInstance();
  await initializeVideoProcessing(prefs);
  final checkMode = await platform.invokeMethod<String>('videoCheckMode');
  if (checkMode != null) await prefs.setString(upscalePreference, checkMode);
  runApp(
    TvApp(session: Session(prefs, Api()), videoCheckOnly: checkMode != null),
  );
}

class TvApp extends StatefulWidget {
  final Session session;
  final bool videoCheckOnly;
  const TvApp({super.key, required this.session, this.videoCheckOnly = false});
  @override
  State<TvApp> createState() => _TvAppState();
}

class _TvAppState extends State<TvApp> {
  late bool login, light;
  @override
  void initState() {
    super.initState();
    login = !widget.session.guest && !widget.session.loggedIn;
    light = widget.session.prefs.getBool('light') ?? false;
    widget.session.addListener(sessionChanged);
  }

  void sessionChanged() {
    if (mounted) {
      setState(() => login = !widget.session.guest && !widget.session.loggedIn);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(sessionChanged);
    super.dispose();
  }

  void toggleTheme() {
    setState(() => light = !light);
    widget.session.prefs.setBool('light', light);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MJAnime',
    theme: mjTheme(light: light),
    builder: (context, child) => LayoutBuilder(
      builder: (context, box) {
        final size = Size(1280, box.maxHeight * 1280 / box.maxWidth);
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: size,
                devicePixelRatio:
                    MediaQuery.devicePixelRatioOf(context) *
                    box.maxWidth /
                    1280,
              ),
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(
                    LogicalKeyboardKey.select,
                    includeRepeats: false,
                  ): ActivateIntent(),
                },
                child: child!,
              ),
            ),
          ),
        );
      },
    ),
    home: widget.videoCheckOnly
        ? LocalVideoCheckHome(session: widget.session)
        : login
        ? LoginScreen(
            session: widget.session,
            onTheme: toggleTheme,
            onDone: () => setState(() => login = false),
          )
        : Shell(
            session: widget.session,
            onLogin: () => setState(() => login = true),
            onTheme: toggleTheme,
          ),
  );
}

class Shell extends StatefulWidget {
  final Session session;
  final VoidCallback onLogin, onTheme;
  const Shell({
    super.key,
    required this.session,
    required this.onLogin,
    required this.onTheme,
  });
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late CastTransport cast;
  StreamSubscription<Json>? castSubscription;
  bool openingCast = false;
  int remoteGeneration = 0;
  int section = 0, tab = 0;
  late Future<dynamic> data;
  String query = '';
  int offset = 0;
  Json filters = {};
  final text = TextEditingController();
  final settingsScroll = ScrollController();
  int searchCount = 0, searchGeneration = 0;
  bool searchPending = false, searchFailed = false;
  String appVersion = '—';
  Json? focusedTitle;
  bool get requiresLogin =>
      !widget.session.loggedIn && (section == 3 || (section == 0 && tab == 1));

  final navFocus = List.generate(
    5,
    (i) => FocusNode(debugLabel: 'Navigation $i'),
  );
  final names = ['Подборка', 'Рекомендации', 'Топ', 'Фильмы', 'Онгоинги'];
  @override
  void initState() {
    super.initState();
    data = load();
    readAppVersion();
    cast = CastTransport(widget.session);
    castSubscription = cast.events.stream.listen(remoteEvent);
    cast.connect();
  }

  @override
  void dispose() {
    castSubscription?.cancel();
    cast.dispose();
    for (final node in navFocus) {
      node.dispose();
    }
    settingsScroll.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> readAppVersion() async {
    try {
      final value = await platform.invokeMethod<String>('appVersion');
      if (mounted && value != null) setState(() => appVersion = value);
    } catch (_) {
      /* Version remains unavailable outside Android. */
    }
  }

  Future<dynamic> load() async {
    final api = widget.session.api;
    if (section == 1) {
      final generation = ++searchGeneration;
      searchPending = true;
      searchFailed = false;
      try {
        final found = await api.search(query, offset: offset, filters: filters);
        if (mounted && generation == searchGeneration) {
          setState(() => searchCount = found.length);
        }
        return found;
      } catch (_) {
        if (mounted && generation == searchGeneration) {
          setState(() {
            searchCount = 0;
            searchFailed = true;
          });
        }
        rethrow;
      } finally {
        if (mounted && generation == searchGeneration) {
          setState(() => searchPending = false);
        }
      }
    }
    if (section == 2) {
      return widget.session.loggedIn
          ? await api.request(
              '/api/user/history',
              auth: true,
              query: {'limit': 100, 'offset': 0},
            )
          : widget.session.localHistory;
    }
    if (section == 3) {
      if (!widget.session.loggedIn) {
        return <Json>[];
      }
      return api.request('/api/user/folder', auth: true);
    }
    if (section == 4) return <Json>[];
    final paths = [
      '/api/anime/main',
      '/api/anime/recommendations',
      '/api/anime/top',
      '/api/anime/top/films',
      '/api/anime/top/season',
    ];
    if (tab == 1 && !widget.session.loggedIn) {
      return <Json>[];
    }
    if (tab == 1 && widget.session.loggedIn) {
      return api.request(
        '/api/anime/for-you',
        auth: true,
        query: {'limit': 30, 'offset': 0},
      );
    }
    return api.request(paths[tab]);
  }

  Future<void> remoteEvent(Json event) async {
    if (!mounted) return;
    if (event['type'] == 'watch:end' || event['type'] == 'room:closed') {
      remoteGeneration++;
      return;
    }
    if (event['type'] == 'cast:invite') {
      if (!cast.invited) return;
      final room = number(event['room_id']);
      if (room > 0) cast.join(room, chat: event['chat_id']?.toString());
    }
    if (![
      'watch:start',
      'watch:state',
      'watch:snapshot',
    ].contains(event['type'])) {
      return;
    }
    if (!cast.invited || cast.roomId == null) return;
    final state = cast.lastState;
    final id = number(state['anime_id']);
    if (id == 0 || openingCast || cast.activeAnimeId == id) return;
    if (event['room_id'] != null) {
      cast.join(number(event['room_id']), chat: state['chat_id']?.toString());
    }
    openingCast = true;
    final generation = ++remoteGeneration;
    try {
      final anime = await widget.session.api.detail(id);
      final tid = state['translation_id'] == null
          ? null
          : number(state['translation_id']);
      final playlist = await widget.session.api.playlist(id, tid);
      if (!mounted || generation != remoteGeneration) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            session: widget.session,
            anime: anime,
            playlist: playlist,
            index: (number(state['episode'], 1) - 1).clamp(
              0,
              (objects(playlist['list']).length - 1).clamp(0, 9999),
            ),
            tid: tid,
            remote: state,
            cast: cast,
          ),
        ),
      );
    } catch (e) {
      if (mounted) errorMessage(context, e);
    } finally {
      openingCast = false;
    }
  }

  void refresh() {
    setState(() {
      data = load();
    });
  }

  void navigate(int s) {
    searchGeneration++;
    setState(() {
      section = s;
      focusedTitle = null;
      offset = 0;
      data = load();
    });
  }

  void open(Json a) async {
    if (animeId(a) == 0) {
      query = '${a['russian'] ?? a['title'] ?? a['name'] ?? ''}';
      text.text = query;
      navigate(1);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          session: widget.session,
          id: animeId(a),
          cast: cast,
          history: section == 2 ? a : null,
          onNavigate: navigate,
        ),
      ),
    ).then((_) {
      if (section == 0 || section == 2 || section == 3) refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rail = CinemaRail(
      section: section,
      nodes: navFocus,
      onSelect: navigate,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section != 0) ...[
          Row(
            children: [
              Text(
                [
                  'Главная',
                  'Поиск аниме',
                  'История',
                  'Моя коллекция',
                  'Настройки',
                ][section],
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.hd_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 25,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            [
              'Истории, которые хочется смотреть',
              'Найдите следующую историю',
              'Сначала недавно открытые',
              'Всё, что вы сохранили',
              'Настройте просмотр под себя',
            ][section],
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (section == 1) searchBar(),
        if (section == 3)
          Row(
            children: [
              const Text('Мои списки', style: TextStyle(fontSize: 24)),
              const Spacer(),
              labelButton('Создать список', createFolder),
            ],
          ),
        if (section != 0) const SizedBox(height: 12),
        Expanded(
          child: section == 4
              ? settings()
              : requiresLogin
              ? TvEmptyState(
                  title: 'Здесь нужен аккаунт',
                  hint: section == 3
                      ? 'Войдите, чтобы сохранять аниме в списки'
                      : 'Войдите, чтобы получить персональные рекомендации',
                  actionLabel: 'Войти в аккаунт',
                  onAction: widget.onLogin,
                )
              : LoadView(future: data, retry: refresh, builder: content),
        ),
        if (section == 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              labelButton(
                'Назад',
                offset == 0 || searchPending || searchFailed
                    ? null
                    : () {
                        offset = (offset - 30).clamp(0, 99999);
                        refresh();
                      },
              ),
              const SizedBox(width: 10),
              Text(
                searchPending
                    ? 'Поиск…'
                    : searchFailed
                    ? 'Ошибка поиска'
                    : searchCount == 0
                    ? 'Нет результатов'
                    : '${offset + 1}–${offset + searchCount}',
              ),
              const SizedBox(width: 10),
              labelButton(
                'Далее',
                searchPending || searchFailed || searchCount < 30
                    ? null
                    : () {
                        offset += 30;
                        refresh();
                      },
              ),
            ],
          ),
      ],
    );
    return PopScope(
      canPop: section == 0 && tab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (section != 0) {
            navigate(0);
            navFocus[0].requestFocus();
          } else {
            setState(() {
              tab = 0;
              data = load();
            });
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              rail,
              Expanded(
                child: Padding(
                  padding: section == 0
                      ? EdgeInsets.zero
                      : const EdgeInsets.fromLTRB(28, 26, 28, 20),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget content(dynamic raw) {
    if (section == 3) return folders(objects(raw));
    List<Json> items = objects(raw);
    if (raw is Map) {
      for (final key in ['items', 'list', 'animes', 'data', 'results']) {
        if (raw[key] is List) {
          items = objects(raw[key]);
          break;
        }
      }
    }
    if (section == 2) {
      items = widget.session.recentHistory(items);
    }
    if (section == 2 && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            const Text(
              'Пока нет просмотренных серий',
              style: TextStyle(fontSize: 25),
            ),
            const SizedBox(height: 10),
            Text(
              'Начните смотреть — прогресс появится здесь',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            primaryButton('Открыть каталог', () {
              navigate(0);
              navFocus[0].requestFocus();
            }, icon: Icons.video_library_outlined),
          ],
        ),
      );
    }
    if (section == 2 && items.isNotEmpty) return history(items);
    if (section == 1 && items.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final a = items[i];
          return SizedBox(
            height: 112,
            child: TvButton(
              autofocus: i == 0,
              onPressed: () => open(a),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 90,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: photo(poster(a)),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title(a),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        titleMetadata(a),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    if (section == 0 && items.isNotEmpty) return home(items);
    return AnimeGrid(
      items: items,
      onOpen: open,
      onRemove: section == 2 ? removeHistory : null,
      removeOnLongPress: section == 2,
    );
  }

  Future<void> removeHistory(Json anime) async {
    try {
      final id = animeId(anime);
      if (widget.session.loggedIn) {
        await widget.session.api.request(
          '/api/user/history/$id',
          method: 'DELETE',
          auth: true,
        );
      }
      final local = widget.session.localHistory
        ..removeWhere((h) => number(h['animetka_id']) == id);
      await widget.session.prefs.setString('history', jsonEncode(local));
      if (mounted) {
        refresh();
        navFocus[2].requestFocus();
      }
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Widget titleMetadata(Json anime) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '${anime['year'] ?? '—'} · ${anime['episodes_total'] ?? '—'} серий · ',
        style: TextStyle(
          fontSize: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      Icon(
        Icons.star_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      Text(
        ' ${anime['shikimori_rating'] ?? '—'}',
        style: TextStyle(
          fontSize: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget home(List<Json> items) {
    final featured =
        items
            .where((a) => animeId(a) == animeId(focusedTitle ?? {}))
            .firstOrNull ??
        items.first;
    final recent = widget.session.recentHistory(widget.session.localHistory);
    final hasRecent = recent.isNotEmpty && tab == 0;
    final shelf = hasRecent ? recent : items;
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          height: 420,
          child: Stack(
            fit: StackFit.expand,
            children: [
              photo(scenery(featured)),
              ClipRect(
                child: Transform.scale(
                  scaleX: 1.7,
                  alignment: Alignment.bottomLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-.85, 1.3),
                        radius: 1.15,
                        colors: [
                          colors.surface.withValues(alpha: .98),
                          colors.surface.withValues(alpha: .85),
                          Colors.transparent,
                          Colors.transparent,
                        ],
                        stops: const [0, .6, .9, 1],
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                top: 26,
                left: 28,
                child: Text(
                  'Главная',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w500),
                ),
              ),
              Positioned(
                left: 28,
                right: 28,
                bottom: 35,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 640,
                      child: Text(
                        title(featured),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 48,
                          height: 1.08,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    titleMetadata(featured),
                    const SizedBox(height: 20),
                    labelButton(
                      'Открыть тайтл',
                      () => open(featured),
                      icon: Icons.play_arrow_rounded,
                      autofocus: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasRecent ? 'Продолжить просмотр' : names[tab],
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 230,
                child: AnimeCarousel(
                  key: ValueKey('home-$tab'),
                  items: shelf,
                  onOpen: open,
                  autofocus: false,
                  onExitLeft: () => navFocus[0].requestFocus(),
                  onFocused: (a) {
                    if (animeId(focusedTitle ?? {}) != animeId(a)) {
                      setState(() => focusedTitle = a);
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: names.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => tabButton(names[i], () {
                    setState(() {
                      tab = i;
                      data = load();
                    });
                  }, selected: tab == i),
                ),
              ),
              if (hasRecent) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 240,
                  child: AnimeCarousel(
                    key: const ValueKey('home-catalog'),
                    items: items,
                    onOpen: open,
                    autofocus: false,
                    onExitLeft: () => navFocus[0].requestFocus(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget history(List<Json> items) {
    final selected =
        items
            .where((a) => animeId(a) == animeId(focusedTitle ?? {}))
            .firstOrNull ??
        items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 108,
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 100,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: photo(poster(selected)),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title(selected),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    titleMetadata(selected),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 350,
          child: AnimeCarousel(
            key: const ValueKey('history-carousel'),
            items: items,
            onOpen: open,
            history: true,
            onRemove: removeHistory,
            onExitLeft: () => navFocus[2].requestFocus(),
            recency: (a) => historyRecency(widget.session.historyDate(a)),
            onFocused: (a) {
              if (animeId(focusedTitle ?? {}) != animeId(a)) {
                setState(() => focusedTitle = a);
              }
            },
          ),
        ),
      ],
    );
  }

  Future<void> performSearch([String? name]) async {
    query = (name ?? text.text).trim();
    text.text = query;
    offset = 0;
    if (query.isNotEmpty &&
        (widget.session.prefs.getBool('searchHistoryEnabled') ?? true)) {
      final history = widget.session.prefs.getStringList('searchHistory') ?? [];
      history.remove(query);
      history.insert(0, query);
      await widget.session.prefs.setStringList(
        'searchHistory',
        history.take(30).toList(),
      );
    }
    if (mounted) refresh();
  }

  Widget searchBar() {
    final recent =
        (widget.session.prefs.getBool('searchHistoryEnabled') ?? true)
        ? widget.session.prefs.getStringList('searchHistory') ?? []
        : <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TvTextEntry(
                label: 'Название аниме',
                value: text.text,
                onChanged: (value) => setState(() => text.text = value),
                onEdit: keyboard,
                submitLabel: 'Найти',
              ),
            ),
            const SizedBox(width: 10),
            labelButton('Найти', () => performSearch()),
            const SizedBox(width: 8),
            labelButton('Клавиатура', keyboard),
            const SizedBox(width: 8),
            labelButton('Голос', speech, icon: Icons.mic),
            const SizedBox(width: 8),
            labelButton('Фильтры', filterDialog, selected: filters.isNotEmpty),
          ],
        ),
        if (recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final item in recent.take(8))
                  labelButton(item, () => performSearch(item)),
                labelButton('Очистить историю', () async {
                  await widget.session.prefs.remove('searchHistory');
                  if (mounted) setState(() {});
                }),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> speech() async {
    try {
      final result = await platform.invokeMethod<String>('speech');
      if (result != null && mounted) {
        text.text = result;
        performSearch(result);
      }
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Future<void> keyboard() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NativeSearchDialog(
        initial: text.text,
        onChanged: (value) => setState(() => text.text = value),
      ),
    );
    if (result != null && mounted) await performSearch(result);
  }

  Future<void> filterDialog() async {
    final result = await showDialog<Json>(
      context: context,
      builder: (_) => FiltersDialog(api: widget.session.api, initial: filters),
    );
    if (result != null && mounted) {
      filters = result;
      offset = 0;
      refresh();
    }
  }

  Widget folders(List<Json> items) => items.isEmpty
      ? TvEmptyState(
          title: 'У вас пока нет списков',
          hint: 'Создайте список и добавляйте в него аниме',
          actionLabel: 'Создать список',
          onAction: createFolder,
        )
      : ListView(
          children: items
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: labelButton(
                          '${f['title'] ?? 'Список'}',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FolderScreen(
                                session: widget.session,
                                folder: f,
                                cast: cast,
                                onNavigate: navigate,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Переименовать список',
                        onPressed: () => editFolder(f),
                        icon: const Icon(Icons.edit),
                      ),
                      IconButton(
                        tooltip: 'Удалить список',
                        onPressed: () => deleteFolder(f),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
  Future<void> createFolder() async {
    if (!widget.session.loggedIn) {
      widget.onLogin();
      return;
    }
    final t = await textPrompt(context, 'Название списка');
    if (t == null || t.trim().isEmpty) return;
    try {
      await widget.session.api.request(
        '/api/user/folder',
        method: 'PUT',
        auth: true,
        body: {'title': t, 'color': '#c7ff68'},
      );
      refresh();
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Future<void> editFolder(Json f) async {
    final t = await textPrompt(
      context,
      'Название списка',
      initial: '${f['title'] ?? ''}',
    );
    if (t == null || t.trim().isEmpty) return;
    try {
      await widget.session.api.request(
        '/api/user/folder',
        method: 'PATCH',
        auth: true,
        body: {'folder_id': f['id'], 'title': t},
      );
      refresh();
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Future<void> deleteFolder(Json f) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Удалить список «${f['title']}»?'),
        actions: [
          labelButton('Отмена', () => Navigator.pop(d, false), autofocus: true),
          labelButton(
            'Удалить',
            () => Navigator.pop(d, true),
            icon: Icons.delete_outline,
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.session.api.request(
        '/api/user/folder',
        method: 'DELETE',
        auth: true,
        body: {'folder_id': f['id']},
      );
      refresh();
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Widget settings() => Scrollbar(
    controller: settingsScroll,
    thumbVisibility: true,
    child: ListView(
      controller: settingsScroll,
      padding: const EdgeInsets.only(right: 8),
      children: [
        mjSettingsSection(context, 'Просмотр', Icons.play_circle_outline, [
          TvSettingToggle(
            title: const Text('Продолжать с сохранённой позиции'),
            value: widget.session.prefs.getBool('resume') ?? true,
            onChanged: (v) async {
              await widget.session.prefs.setBool('resume', v);
              setState(() {});
            },
          ),
          TvSettingToggle(
            title: const Text('Автоматически включать следующую серию'),
            value: widget.session.prefs.getBool('autoNextEpisode') ?? true,
            onChanged: (v) async {
              await widget.session.prefs.setBool('autoNextEpisode', v);
              setState(() {});
            },
          ),
          TvSettingToggle(
            title: const Text('Пропускать опенинги и эндинги'),
            subtitle: const Text('По меткам, доступным для конкретной серии'),
            value:
                widget.session.prefs.getBool('autoSkipOpeningEnding') ?? false,
            onChanged: (v) async {
              await widget.session.prefs.setBool('autoSkipOpeningEnding', v);
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          const Text('Шаг перемотки', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final n in [5, 10, 15, 20])
                labelButton(
                  '$n сек',
                  () async {
                    await widget.session.prefs.setInt(
                      'doubleTapSeekSeconds',
                      n,
                    );
                    setState(() {});
                  },
                  selected:
                      (widget.session.prefs.getInt('doubleTapSeekSeconds') ??
                          10) ==
                      n,
                ),
            ],
          ),
          const SizedBox(height: 22),
          AnimeUpscaleSelector(
            mode: readUpscaleMode(widget.session.prefs),
            onChanged: (v) async {
              await widget.session.prefs.setString(upscalePreference, v);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 22),
          const Text('Качество по умолчанию', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final v in ['auto', '1080', '720', '480', '360'])
                labelButton(
                  v == 'auto' ? 'Автоматически' : '${v}p',
                  () async {
                    await widget.session.prefs.setString('preferredQuality', v);
                    setState(() {});
                  },
                  selected:
                      (widget.session.prefs.getString('preferredQuality') ??
                          'auto') ==
                      v,
                ),
            ],
          ),
        ]),
        mjSettingsSection(context, 'Оформление', Icons.palette_outlined, [
          Text(
            'MJ / ANIME',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 2,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Время для новой истории',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 8),
          Text(
            'Настройки сохраняются автоматически.',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          labelButton(
            'Сменить тему',
            widget.onTheme,
            icon: Icons.contrast_rounded,
          ),
        ]),
        mjSettingsSection(context, 'Поиск', Icons.search_rounded, [
          TvSettingToggle(
            title: const Text('Сохранять историю поиска'),
            value: widget.session.prefs.getBool('searchHistoryEnabled') ?? true,
            onChanged: (v) async {
              await widget.session.prefs.setBool('searchHistoryEnabled', v);
              setState(() {});
            },
          ),
        ]),
        mjSettingsSection(context, 'Аккаунт', Icons.person_outline, [
          Text(
            widget.session.loggedIn
                ? '${widget.session.user['nickname'] ?? 'Мой профиль'}'
                : 'Гостевой режим',
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              labelButton(
                widget.session.loggedIn
                    ? 'Выйти из аккаунта'
                    : 'Войти в аккаунт',
                () async {
                  try {
                    if (widget.session.loggedIn) await widget.session.logout();
                    widget.onLogin();
                  } catch (e) {
                    if (mounted) {
                      errorMessage(context, e);
                      widget.onLogin();
                    }
                  }
                },
                icon: Icons.login_rounded,
              ),
              labelButton(
                'Профиль',
                () => profile(),
                icon: Icons.person_outline,
              ),
            ],
          ),
        ]),
        mjSettingsSection(context, 'Приложение', Icons.info_outline, [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              labelButton(
                'Обновление MJAnime',
                updates,
                icon: Icons.system_update_outlined,
              ),
              labelButton(
                'Проверить воспроизведение',
                () => openLocalVideoCheck(context, widget.session),
                icon: Icons.movie_outlined,
              ),
              labelButton(
                'Установить обновление APK',
                installUpdate,
                icon: Icons.download_outlined,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'MJAnime · версия $appVersion\nAndroid TV',
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ]),
      ],
    ),
  );
  Future<void> profile() async {
    if (!widget.session.loggedIn) {
      widget.onLogin();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(session: widget.session)),
    );
  }

  Future<void> installUpdate() async {
    try {
      await platform.invokeMethod('installUpdate');
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Future<void> updates() async {
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Обновление MJAnime'),
        content: Text(
          'Установлена версия $appVersion.\n\nДля обновления выберите скачанный APK MJAnime. Устанавливайте его поверх текущей версии — настройки и история сохранятся.',
        ),
        actions: [
          labelButton('Закрыть', () => Navigator.pop(d), autofocus: true),
          labelButton('Выбрать APK', () {
            Navigator.pop(d);
            installUpdate();
          }, icon: Icons.download_outlined),
        ],
      ),
    );
  }
}

class FolderScreen extends StatefulWidget {
  final Session session;
  final Json folder;
  final CastTransport? cast;
  final ValueChanged<int>? onNavigate;
  const FolderScreen({
    super.key,
    required this.session,
    required this.folder,
    this.cast,
    this.onNavigate,
  });
  @override
  State<FolderScreen> createState() => _FolderState();
}

class _FolderState extends State<FolderScreen> {
  late List<Json> items;
  final refreshFocus = FocusNode(debugLabel: 'Folder refresh');
  final emptyFocus = FocusNode(debugLabel: 'Folder back');
  @override
  void initState() {
    super.initState();
    items = objects(widget.folder['AnimeHistories']).map(historyAnime).toList();
  }

  @override
  void dispose() {
    refreshFocus.dispose();
    emptyFocus.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final folders = objects(
        await widget.session.api.request('/api/user/folder', auth: true),
      );
      final folder = folders
          .where((f) => f['id'] == widget.folder['id'])
          .firstOrNull;
      if (mounted) {
        setState(
          () =>
              items = objects(folder?['AnimeHistories'])
                  .map(historyAnime)
                  .toList(),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            (items.isEmpty ? emptyFocus : refreshFocus).requestFocus();
          }
        });
      }
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  Future<void> remove(Json anime) async {
    try {
      await widget.session.api.request(
        '/api/user/folder/delete',
        method: 'POST',
        auth: true,
        body: {'folder_id': widget.folder['id'], 'animetka_id': animeId(anime)},
      );
      if (!mounted) return;
      setState(() => items.removeWhere((a) => animeId(a) == animeId(anime)));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) (items.isEmpty ? emptyFocus : refreshFocus).requestFocus();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Аниме убрано из списка'),
          action: SnackBarAction(
            label: 'Вернуть',
            onPressed: () async {
              try {
                await widget.session.api.request(
                  '/api/user/folder/add',
                  method: 'POST',
                  auth: true,
                  body: {
                    'folder_id': widget.folder['id'],
                    'animetka_id': animeId(anime),
                  },
                );
                await reload();
              } catch (e) {
                if (mounted) errorMessage(context, e);
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.folder['title']}'),
      actions: [
        IconButton(
          tooltip: 'Обновить',
          focusNode: refreshFocus,
          onPressed: reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: items.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'В этом списке пока нет аниме',
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Добавляйте аниме кнопкой «В список» на его странице',
                ),
                const SizedBox(height: 24),
                TvButton(
                  focusNode: emptyFocus,
                  autofocus: true,
                  onPressed: () => Navigator.pop(context),
                  child: const Text('К спискам'),
                ),
              ],
            ),
          )
        : AnimeGrid(
            items: items,
            onRemove: remove,
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
          ),
  );
}
