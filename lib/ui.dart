import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'api.dart';

const accent = Color(0xffc7ff68),
    darkBg = Color(0xff0c0e15),
    surface = Color(0xff191e29),
    muted = Color(0xffabb5c5);

ThemeData mjTheme({bool light = false}) {
  final active = light ? const Color(0xff345a05) : accent;
  final background = light ? const Color(0xfffafaf7) : darkBg;
  final card = light ? const Color(0xffeaede6) : surface;
  final ink = light ? const Color(0xff20251f) : const Color(0xfff0f2ec);
  final secondary = light ? const Color(0xff4d584e) : muted;
  return ThemeData(
    useMaterial3: true,
    brightness: light ? Brightness.light : Brightness.dark,
    scaffoldBackgroundColor: background,
    fontFamily: 'MJSans',
    splashFactory: NoSplash.splashFactory,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: active,
          brightness: light ? Brightness.light : Brightness.dark,
        ).copyWith(
          primary: active,
          onPrimary: light ? Colors.white : darkBg,
          onSurface: ink,
          onSurfaceVariant: secondary,
          surface: background,
          surfaceContainerLow: card,
          surfaceContainerHigh: light
              ? const Color(0xffe1e5dc)
              : const Color(0xff242b39),
        ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 18, height: 1.35),
      bodyLarge: TextStyle(fontSize: 19),
      titleMedium: TextStyle(fontSize: 20),
    ),
    focusColor: active.withValues(alpha: .18),
    hoverColor: active.withValues(alpha: .08),
    sliderTheme: SliderThemeData(
      activeTrackColor: active,
      thumbColor: active,
      trackHeight: 4,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: active, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(ink),
        overlayColor: WidgetStatePropertyAll(active.withValues(alpha: .14)),
      ),
    ),
  );
}

Widget mjSettingsSection(
  BuildContext context,
  String title,
  IconData icon,
  List<Widget> children,
) {
  final colors = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 23, color: colors.primary),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: colors.copyWith(surfaceContainerLow: colors.surface),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

class TvButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool selected, autofocus;
  final EdgeInsets padding;
  final ValueChanged<bool>? onFocus;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;
  final bool subtle, primary, outlined;
  const TvButton({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.selected = false,
    this.autofocus = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    this.onFocus,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.subtle = false,
    this.primary = false,
    this.outlined = false,
  });
  @override
  State<TvButton> createState() => _TvButtonState();
}

class _TvButtonState extends State<TvButton> {
  bool focus = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = colors.primary;
    final isFocused = widget.focusNode?.hasFocus ?? focus;
    final enabled = widget.onPressed != null;
    final foreground = widget.primary && enabled
        ? colors.onPrimary
        : colors.onSurface;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) =>
          event is KeyRepeatEvent &&
              [
                LogicalKeyboardKey.select,
                LogicalKeyboardKey.enter,
                LogicalKeyboardKey.space,
              ].contains(event.logicalKey)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: widget.onPressed != null,
        onFocusChange: (v) {
          setState(() => focus = v);
          widget.onFocus?.call(v);
          if (v) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted ||
                  !context.mounted ||
                  !(widget.focusNode?.hasFocus ?? focus)) {
                return;
              }
              final duration = MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180);
              // Reveal either edge without moving a control that is already visible.
              await Scrollable.ensureVisible(
                context,
                alignmentPolicy:
                    ScrollPositionAlignmentPolicy.keepVisibleAtStart,
                duration: duration,
              );
              if (!mounted ||
                  !context.mounted ||
                  !(widget.focusNode?.hasFocus ?? focus)) {
                return;
              }
              await Scrollable.ensureVisible(
                context,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                duration: duration,
              );
            });
          }
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select, includeRepeats: false):
              ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
              ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: widget.onPressed,
            onLongPress: widget.onLongPress,
            borderRadius: widget.borderRadius,
            splashFactory: NoSplash.splashFactory,
            highlightColor: active.withValues(alpha: .1),
            hoverColor: active.withValues(alpha: .06),
            child: AnimatedScale(
              scale: 1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: !enabled
                      ? colors.surfaceContainerHigh
                      : widget.primary
                      ? active
                      : isFocused
                      ? active.withValues(alpha: .14)
                      : widget.selected
                      ? active.withValues(alpha: .10)
                      : widget.subtle
                      ? Colors.transparent
                      : widget.outlined
                      ? colors.surface
                      : colors.surfaceContainerLow,
                  borderRadius: widget.borderRadius,
                  border: Border.all(
                    color: isFocused
                        ? (widget.primary ? colors.onSurface : active)
                        : widget.outlined
                        ? colors.outlineVariant
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: widget.onPressed == null
                        ? colors.onSurfaceVariant
                        : foreground,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: !enabled
                          ? colors.onSurfaceVariant
                          : widget.primary
                          ? colors.onPrimary
                          : (isFocused || widget.selected)
                          ? active
                          : colors.onSurface,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget labelButton(
  String text,
  VoidCallback? action, {
  bool selected = false,
  bool autofocus = false,
  IconData? icon,
  FocusNode? focusNode,
}) => TvButton(
  focusNode: focusNode,
  onPressed: action,
  selected: selected,
  autofocus: autofocus,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[Icon(icon, size: 23), const SizedBox(width: 8)],
      Flexible(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
    ],
  ),
);
Widget tabButton(String text, VoidCallback? action, {bool selected = false}) =>
    Builder(
      builder: (context) => Semantics(
        selected: selected,
        child: TvButton(
          onPressed: action,
          subtle: true,
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(text, style: const TextStyle(fontSize: 17)),
            ),
          ),
        ),
      ),
    );
Widget primaryButton(
  String text,
  VoidCallback? action, {
  bool autofocus = false,
  IconData? icon,
}) => TvButton(
  onPressed: action,
  autofocus: autofocus,
  selected: true,
  primary: true,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[Icon(icon, size: 25), const SizedBox(width: 10)],
      Text(
        text,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500),
      ),
    ],
  ),
);
Widget photo(
  String url, {
  BoxFit fit = BoxFit.cover,
  Iterable<String> fallbacks = const [],
}) {
  final candidates = [
    url,
    ...fallbacks,
  ].where((s) => s.trim().isNotEmpty).toSet().toList();
  const empty = ColoredBox(
    color: surface,
    child: Center(child: Icon(Icons.movie_outlined, size: 40, color: muted)),
  );
  Widget load(int index) => index >= candidates.length
      ? empty
      : LayoutBuilder(
          builder: (context, bounds) => Image.network(
            absolute(candidates[index]),
            key: ValueKey(candidates[index]),
            cacheWidth: bounds.hasBoundedWidth
                ? (bounds.maxWidth * MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 1920)
                : null,
            filterQuality: FilterQuality.low,
            fit: fit,
            headers: const {'User-Agent': 'Dart/3.14 (dart:io)'},
            errorBuilder: (_, _, _) => load(index + 1),
          ),
        );
  return load(0);
}

String userError(Object error) {
  if (error is PlatformException) {
    return error.message?.isNotEmpty == true
        ? error.message!
        : 'Не удалось выполнить действие. Попробуйте ещё раз.';
  }
  if (error is MissingPluginException) {
    return 'Действие недоступно на этом устройстве';
  }
  return '$error';
}

void errorMessage(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(userError(e)),
        duration: const Duration(seconds: 6),
      ),
    );

class LoadView extends StatelessWidget {
  final Future<dynamic> future;
  final Widget Function(dynamic) builder;
  final VoidCallback? retry;
  const LoadView({
    super.key,
    required this.future,
    required this.builder,
    this.retry,
  });
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (c, s) {
      if (s.connectionState != ConnectionState.done && !s.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (s.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${s.error}', textAlign: TextAlign.center),
              if (retry != null)
                labelButton('Повторить', retry, autofocus: true),
            ],
          ),
        );
      }
      return builder(s.data);
    },
  );
}

class AnimeGrid extends StatelessWidget {
  final List<Json> items;
  final ValueChanged<Json> onOpen;
  final ValueChanged<Json>? onRemove;
  final bool removeOnLongPress;
  final String emptyMessage;
  final String? emptyHint;
  const AnimeGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.onRemove,
    this.removeOnLongPress = false,
    this.emptyMessage = 'Здесь пока ничего нет',
    this.emptyHint,
  });
  @override
  Widget build(BuildContext context) => items.isEmpty
      ? TvEmptyState(title: emptyMessage, hint: emptyHint)
      : LayoutBuilder(
          builder: (c, b) => GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: (b.maxWidth / 190).floor().clamp(2, 6),
              childAspectRatio: .56,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
            ),
            itemCount: items.length,
            itemBuilder: (c, i) {
              final a = items[i];
              return AnimeCard(
                key: ValueKey(animeId(a)),
                anime: a,
                onPressed: () => onOpen(a),
                autofocus: i == 0,
                removeOnLongPress: removeOnLongPress,
                onRemove: onRemove == null ? null : () => onRemove!(a),
              );
            },
          ),
        );
}

class AnimeCard extends StatefulWidget {
  final Json anime;
  final VoidCallback onPressed;
  final VoidCallback? onRemove;
  final bool autofocus, removeOnLongPress;
  final FocusNode? focusNode;
  final Widget? content;
  final ValueChanged<bool>? onFocus;
  const AnimeCard({
    super.key,
    required this.anime,
    required this.onPressed,
    this.onRemove,
    this.autofocus = false,
    this.removeOnLongPress = false,
    this.focusNode,
    this.content,
    this.onFocus,
  });
  @override
  State<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<AnimeCard> {
  final internalFocus = FocusNode(debugLabel: 'Anime card');
  FocusNode get openFocus => widget.focusNode ?? internalFocus;
  final removeFocus = FocusNode(debugLabel: 'Remove anime');
  Timer? holdTimer;
  bool held = false, longPressFired = false, menuOpen = false;
  @override
  void initState() {
    super.initState();
    openFocus.onKeyEvent = handleHold;
    openFocus.addListener(cancelHoldOnBlur);
  }

  void cancelHoldOnBlur() {
    if (!openFocus.hasFocus) {
      holdTimer?.cancel();
      held = false;
    }
  }

  KeyEventResult handleHold(FocusNode node, KeyEvent event) {
    if (!widget.removeOnLongPress ||
        widget.onRemove == null ||
        ![
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.enter,
        ].contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      held = true;
      longPressFired = false;
      holdTimer?.cancel();
      holdTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted && held && openFocus.hasFocus) {
          longPressFired = true;
          showHistoryMenu();
        }
      });
    } else if (event is KeyUpEvent) {
      holdTimer?.cancel();
      if (held && !longPressFired) widget.onPressed();
      held = false;
    }
    return KeyEventResult.handled;
  }

  Future<void> showHistoryMenu() async {
    if (menuOpen || widget.onRemove == null) return;
    menuOpen = true;
    final remove = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('История просмотра'),
        content: Text(title(widget.anime)),
        actions: [
          labelButton('Отмена', () => Navigator.pop(d, false), autofocus: true),
          labelButton(
            'Удалить из истории',
            () => Navigator.pop(d, true),
            icon: Icons.delete_outline,
          ),
        ],
      ),
    );
    menuOpen = false;
    if (!mounted) return;
    if (remove == true) {
      widget.onRemove?.call();
    } else {
      openFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    holdTimer?.cancel();
    openFocus.removeListener(cancelHoldOnBlur);
    internalFocus.dispose();
    removeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    final onPressed = widget.onPressed;
    final onRemove = widget.onRemove;
    final hasContextMenu = widget.removeOnLongPress && onRemove != null;
    final autofocus = widget.autofocus;
    final colors = Theme.of(context).colorScheme;
    final progress =
        anime.containsKey('timestamp') && number(anime['duration']) > 0
        ? (number(anime['timestamp']) / number(anime['duration'])).clamp(
            0.0,
            1.0,
          )
        : null;
    return RepaintBoundary(
      child: Column(
        children: [
          Expanded(
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) {
                if (onRemove != null &&
                    !hasContextMenu &&
                    event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  removeFocus.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TvButton(
                focusNode: openFocus,
                onPressed: onPressed,
                onLongPress: hasContextMenu ? showHistoryMenu : null,
                autofocus: autofocus,
                onFocus: widget.onFocus,
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.all(12),
                child:
                    widget.content ??
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: double.infinity,
                              child: photo(poster(anime), fit: BoxFit.contain),
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        SizedBox(
                          height: 42,
                          child: Text(
                            title(anime),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${anime['year'] ?? '—'} · ${anime['episodes_total'] ?? '—'} эп.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.star_outline_rounded,
                              size: 17,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${anime['shikimori_rating'] ?? '—'}',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        if (anime['episode'] != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Серия ${anime['episode']}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 16,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (hasContextMenu) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Удерживайте OK',
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (progress != null) ...[
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            color: colors.primary,
                            backgroundColor: colors.surface,
                          ),
                        ],
                      ],
                    ),
              ),
            ),
          ),
          if (onRemove != null && !hasContextMenu) ...[
            const SizedBox(height: 6),
            Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  openFocus.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: SizedBox(
                width: double.infinity,
                child: TvButton(
                  focusNode: removeFocus,
                  onPressed: onRemove,
                  outlined: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bookmark_remove_outlined, size: 21),
                      SizedBox(width: 8),
                      Text('Убрать', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<String?> textPrompt(
  BuildContext context,
  String title, {
  String initial = '',
  bool password = false,
  bool numeric = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => TvSearchKeyboard(
    initial: initial,
    title: title,
    submitLabel: 'Готово',
    password: password,
    numeric: numeric,
    onChanged: (_) {},
  ),
);

/// A remote selects a field; editing happens inside the TV keyboard route.
class TvTextEntry extends StatelessWidget {
  final String label, value, submitLabel;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted, onEdit;
  final bool numeric, password, autofocus;
  final int maxLines;
  const TvTextEntry({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.onEdit,
    this.numeric = false,
    this.password = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.submitLabel = 'Готово',
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TvButton(
      autofocus: autofocus,
      outlined: true,
      onPressed: () async {
        if (onEdit != null) {
          onEdit!();
          return;
        }
        final result = await showDialog<String>(
          context: context,
          builder: (_) => TvSearchKeyboard(
            initial: value,
            title: label,
            submitLabel: submitLabel,
            numeric: numeric,
            password: password,
            onChanged: (_) {},
          ),
        );
        if (result != null && context.mounted) {
          onChanged(result);
          onSubmitted?.call();
        }
      },
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant),
            ),
            if (value.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                password ? List.filled(value.runes.length, '•').join() : value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TvEmptyState extends StatelessWidget {
  final String title;
  final String? hint, actionLabel;
  final VoidCallback? onAction;
  final bool autofocus;
  const TvEmptyState({
    super.key,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.autofocus = false,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 23),
          ),
          if (hint != null) ...[
            const SizedBox(height: 12),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 24),
            labelButton(actionLabel!, onAction, autofocus: autofocus),
          ],
        ],
      ),
    ),
  );
}

class TvScrollPane extends StatefulWidget {
  final Widget child;
  final String label;
  const TvScrollPane({super.key, required this.child, required this.label});
  @override
  State<TvScrollPane> createState() => _TvScrollPaneState();
}

class _TvScrollPaneState extends State<TvScrollPane> {
  final scroll = ScrollController();
  late final focus = FocusNode(debugLabel: widget.label);
  bool focused = false;
  @override
  void dispose() {
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      focusNode: focus,
      debugLabel: widget.label,
      onFocusChange: (v) => setState(() => focused = v),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown) {
          if (!scroll.hasClients) return KeyEventResult.handled;
          if (k == LogicalKeyboardKey.arrowUp && scroll.offset <= 0) {
            focus.focusInDirection(TraversalDirection.up);
            return KeyEventResult.handled;
          }
          final next =
              (scroll.offset + (k == LogicalKeyboardKey.arrowDown ? 100 : -100))
                  .clamp(0.0, scroll.position.maxScrollExtent);
          scroll.jumpTo(next);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        label: widget.label,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(
              color: focused ? colors.primary : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.swap_vert_rounded,
                    size: 22,
                    color: focused ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Прокрутка',
                    style: TextStyle(
                      fontSize: 16,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Scrollbar(
                  controller: scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.only(right: 12),
                    child: widget.child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TvSettingToggle extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const TvSettingToggle({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TvButton(
      onPressed: () => onChanged(!value),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 14),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 20),
          Text(
            value ? 'Включено' : 'Выключено',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

class TvSearchKeyboard extends StatefulWidget {
  final String initial, title, submitLabel;
  final bool numeric, password;
  final ValueChanged<String> onChanged;
  const TvSearchKeyboard({
    super.key,
    required this.initial,
    required this.onChanged,
    this.title = 'Поиск аниме',
    this.submitLabel = 'Найти',
    this.numeric = false,
    this.password = false,
  });
  @override
  State<TvSearchKeyboard> createState() => _TvSearchKeyboardState();
}

class _TvSearchKeyboardState extends State<TvSearchKeyboard> {
  late String query;
  late int cursor;
  bool latin = false;
  final previewScroll = ScrollController();
  @override
  void initState() {
    super.initState();
    query = widget.initial;
    cursor = query.runes.length;
  }

  @override
  void dispose() {
    previewScroll.dispose();
    super.dispose();
  }

  void edit(String value, {bool erase = false, bool clear = false}) {
    final units = query.runes.toList();
    if (clear) {
      units.clear();
      cursor = 0;
    } else if (erase) {
      if (cursor > 0) {
        units.removeAt(--cursor);
      }
    } else {
      final insert = value.runes.toList();
      units.insertAll(cursor, insert);
      cursor += insert.length;
    }
    setState(() => query = String.fromCharCodes(units));
    widget.onChanged(query);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (previewScroll.hasClients) {
        previewScroll.jumpTo(
          cursor == 0 ? 0 : previewScroll.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final units = query.runes.toList();
    final alphabet = widget.numeric
        ? '1234567890.,-'
        : '${latin ? 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' : 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'}0123456789-';
    return Dialog(
      child: SizedBox(
        width: 850,
        height: (MediaQuery.sizeOf(context).height - 48).clamp(340, 650),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  labelButton(
                    'Отмена',
                    () => Navigator.pop(context),
                    icon: Icons.close,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Semantics(
                label: widget.title,
                value: widget.password ? 'Скрытый текст' : query,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: SingleChildScrollView(
                    controller: previewScroll,
                    scrollDirection: Axis.horizontal,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: String.fromCharCodes(
                              units
                                  .take(cursor)
                                  .map((v) => widget.password ? 0x2022 : v),
                            ),
                          ),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              width: 2,
                              height: 24,
                              color: colors.primary,
                            ),
                          ),
                          TextSpan(
                            text: String.fromCharCodes(
                              units
                                  .skip(cursor)
                                  .map((v) => widget.password ? 0x2022 : v),
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 21),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!widget.numeric)
                    labelButton(
                      'АБВ',
                      () => setState(() => latin = false),
                      selected: !latin,
                    ),
                  const SizedBox(width: 10),
                  if (!widget.numeric)
                    labelButton(
                      'ABC',
                      () => setState(() => latin = true),
                      selected: latin,
                    ),
                  const Spacer(),
                  Semantics(
                    label: 'Курсор влево',
                    button: true,
                    child: TvButton(
                      onPressed: cursor > 0
                          ? () => setState(() => cursor--)
                          : null,
                      child: const Icon(Icons.chevron_left),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Курсор вправо',
                    button: true,
                    child: TvButton(
                      onPressed: cursor < units.length
                          ? () => setState(() => cursor++)
                          : null,
                      child: const Icon(Icons.chevron_right),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: widget.numeric ? 6 : 12,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: alphabet.length,
                  itemBuilder: (_, i) => TvButton(
                    key: ValueKey('${latin ? 1 : 0}:$i'),
                    autofocus: i == 0,
                    onPressed: () => edit(alphabet[i]),
                    padding: const EdgeInsets.all(10),
                    child: Center(
                      child: Text(
                        alphabet[i],
                        style: const TextStyle(fontSize: 21),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!widget.numeric) labelButton('Пробел', () => edit(' ')),
                  const SizedBox(width: 10),
                  labelButton(
                    'Стереть',
                    query.isEmpty ? null : () => edit('', erase: true),
                    icon: Icons.backspace_outlined,
                  ),
                  const SizedBox(width: 10),
                  labelButton(
                    'Очистить',
                    query.isEmpty ? null : () => edit('', clear: true),
                    icon: Icons.clear_all_rounded,
                  ),
                  const Spacer(),
                  primaryButton(
                    widget.submitLabel,
                    () => Navigator.pop(context, query),
                    icon: Icons.search_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
