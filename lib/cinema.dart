import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ui.dart';
import 'tv_playback.dart' show playbackTime;

/// Landscape artwork supplied by the catalog, with a real poster as fallback.
String scenery(Json anime) {
  for (final key in [
    'anime_screenshot_url',
    'screenshot_url',
    'backdrop_url',
    'banner_url',
    'image',
    'screenshot',
  ]) {
    final value = anime[key];
    if (value is String && value.isNotEmpty) return value;
  }
  final shots = anime['screenshots'];
  if (shots is List && shots.isNotEmpty) {
    final first = shots.first;
    if (first is String && first.isNotEmpty) return first;
    final url = object(first)['url'];
    if (url is String && url.isNotEmpty) return url;
  }
  return poster(anime);
}

class CinemaRail extends StatelessWidget {
  final int section;
  final List<FocusNode>? nodes;
  final ValueChanged<int> onSelect;
  const CinemaRail({
    super.key,
    required this.section,
    required this.onSelect,
    this.nodes,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 92,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          right: BorderSide(color: colors.outlineVariant.withValues(alpha: .3)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 26),
      child: Column(
        children: [
          Text(
            'MJ',
            style: TextStyle(
              color: colors.primary,
              fontSize: 26,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Text(
            '/ ANIME',
            style: TextStyle(fontSize: 11, letterSpacing: 1),
          ),
          const SizedBox(height: 32),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Tooltip(
                message: const [
                  'Главная',
                  'Поиск',
                  'Продолжить',
                  'Мои списки',
                  'Настройки',
                ][i],
                child: TvButton(
                  focusNode: nodes?[i],
                  selected: section == i,
                  subtle: section != i,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 2,
                  ),
                  onPressed: () => onSelect(i),
                  child: SizedBox(
                    width: 66,
                    child: Icon(
                      const [
                        Icons.home_outlined,
                        Icons.search_rounded,
                        Icons.history_rounded,
                        Icons.bookmarks_outlined,
                        Icons.settings_outlined,
                      ][i],
                      size: 27,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String historyRecency(DateTime? date) {
  if (date == null) return '';
  final elapsed = DateTime.now().toUtc().difference(date.toUtc());
  if (elapsed.inMinutes < 1) return 'Только что';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} мин назад';
  final now = DateTime.now();
  final day = DateTime(
    date.toLocal().year,
    date.toLocal().month,
    date.toLocal().day,
  );
  final days = DateTime(now.year, now.month, now.day).difference(day).inDays;
  if (days == 0) return 'Сегодня';
  if (days == 1) return 'Вчера';
  return '$days дн назад';
}

/// Lazy horizontal shelf with explicit D-pad movement, including unbuilt cards.
class AnimeCarousel extends StatefulWidget {
  final List<Json> items;
  final ValueChanged<Json> onOpen;
  final ValueChanged<Json>? onRemove, onFocused;
  final VoidCallback? onExitLeft;
  final String Function(Json)? recency;
  final bool history, autofocus;
  const AnimeCarousel({
    super.key,
    required this.items,
    required this.onOpen,
    this.onRemove,
    this.onFocused,
    this.onExitLeft,
    this.recency,
    this.history = false,
    this.autofocus = true,
  });
  @override
  State<AnimeCarousel> createState() => _AnimeCarouselState();
}

class _AnimeCarouselState extends State<AnimeCarousel> {
  final scroll = ScrollController();
  final nodes = <int, FocusNode>{};
  int selected = 0;
  FocusNode node(int i) =>
      nodes.putIfAbsent(i, () => FocusNode(debugLabel: 'Anime card'));
  double get extent => widget.history ? 342 : 280;
  void move(int from, int direction) {
    final to = from + direction;
    if (to < 0) {
      widget.onExitLeft?.call();
      return;
    }
    if (to >= widget.items.length) return;
    final target = node(to);
    if (target.context != null) {
      target.requestFocus();
      return;
    }
    scroll.jumpTo((to * extent).clamp(0, scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) target.requestFocus();
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final n in nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            itemExtent: extent,
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: widget.items.length,
            itemBuilder: (context, i) {
              final a = widget.items[i];
              final duration = number(a['duration']);
              final position = number(a['timestamp']);
              final stamp = widget.recency?.call(a) ?? '';
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                        event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      move(
                        i,
                        event.logicalKey == LogicalKeyboardKey.arrowLeft
                            ? -1
                            : 1,
                      );
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AnimeCard(
                    key: ValueKey(animeId(a)),
                    anime: a,
                    focusNode: node(i),
                    autofocus: widget.autofocus && i == 0,
                    onPressed: () => widget.onOpen(a),
                    removeOnLongPress: widget.onRemove != null,
                    onRemove: widget.onRemove == null
                        ? null
                        : () => widget.onRemove!(a),
                    onFocus: (focus) {
                      if (!focus) return;
                      setState(() => selected = i);
                      widget.onFocused?.call(a);
                    },
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: double.infinity,
                              child: photo(scenery(a)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title(a),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.history ? 21 : 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (widget.history && a['episode'] != null)
                          Text(
                            'Серия ${a['episode']}',
                            style: TextStyle(
                              fontSize: 16,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        if (widget.history && stamp.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              stamp,
                              style: TextStyle(
                                fontSize: 15,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          a['episode'] != null
                              ? '${widget.history ? '' : 'Серия ${a['episode']} · '}${playbackTime(Duration(seconds: position))}${duration > 0 ? ' / ${playbackTime(Duration(seconds: duration))}' : ''}'
                              : '${a['year'] ?? '—'} · ${a['episodes_total'] ?? '—'} серий',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.history ? 15 : 14,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (a['episode'] != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: duration > 0
                                  ? (position / duration).clamp(0, 1)
                                  : 0,
                              minHeight: 4,
                              color: colors.primary,
                              backgroundColor: colors.outlineVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: selected == 0
                      ? colors.outlineVariant
                      : colors.onSurfaceVariant,
                ),
                Text(
                  '${selected + 1} / ${widget.items.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: selected == widget.items.length - 1
                      ? colors.outlineVariant
                      : colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class NativeSearchDialog extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onChanged;
  const NativeSearchDialog({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  @override
  State<NativeSearchDialog> createState() => _NativeSearchDialogState();
}

class _NativeSearchDialogState extends State<NativeSearchDialog> {
  late final text = TextEditingController(text: widget.initial);
  final focus = FocusNode(debugLabel: 'Native search input');
  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  void submit() => Navigator.pop(context, text.text);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Поиск аниме'),
    content: SizedBox(
      width: 680,
      child: TextField(
        controller: text,
        focusNode: focus,
        autofocus: true,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        enableSuggestions: true,
        decoration: const InputDecoration(
          labelText: 'Название аниме',
          prefixIcon: Icon(Icons.search_rounded),
        ),
        onChanged: widget.onChanged,
        onSubmitted: (_) => submit(),
        onTap: () =>
            SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
      ),
    ),
    actions: [
      labelButton('Отмена', () => Navigator.pop(context)),
      labelButton('Найти', submit, icon: Icons.search_rounded),
    ],
  );
}
