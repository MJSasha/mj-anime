import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'ui.dart';
import 'api.dart';

String playbackTime(Duration d) {
  final s = d.inSeconds.clamp(0, 9999999);
  final minutes = ((s ~/ 60) % 60).toString().padLeft(2, '0');
  final seconds = (s % 60).toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:$minutes:$seconds' : '${s ~/ 60}:$seconds';
}

/// Remote arrows preview a position; OK commits and Back cancels.
class TvSeekBar extends StatefulWidget {
  final Duration position, duration;
  final int step;
  final VoidCallback? onUp, onDown, onToggle;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool> onScrub;
  const TvSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onScrub,
    this.step = 10,
    this.onUp,
    this.onDown,
    this.onToggle,
  });
  @override
  State<TvSeekBar> createState() => TvSeekBarState();
}

class TvSeekBarState extends State<TvSeekBar> {
  final focusNode = FocusNode(debugLabel: 'Timeline');
  double? draft;
  int repeats = 0;
  bool focused = false;
  double get maximum =>
      widget.duration.inMilliseconds.toDouble().clamp(1, double.infinity);
  void nudge(int direction) {
    focusNode.requestFocus();
    final factor = repeats >= 20
        ? 6
        : repeats >= 10
        ? 3
        : 1;
    repeats++;
    widget.onScrub(true);
    setState(
      () => draft =
          ((draft ?? widget.position.inMilliseconds.toDouble()) +
                  direction * widget.step * 1000 * factor)
              .clamp(0, maximum),
    );
  }

  void finish({bool commit = true}) {
    if (draft == null) return;
    if (commit) widget.onSeek(Duration(milliseconds: draft!.round()));
    setState(() {
      draft = null;
      repeats = 0;
    });
    widget.onScrub(false);
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = (draft ?? widget.position.inMilliseconds.toDouble())
        .clamp(0, maximum)
        .toDouble();
    return Focus(
      focusNode: focusNode,
      onFocusChange: (v) {
        setState(() => focused = v);
        if (!v) finish(commit: false);
      },
      onKeyEvent: (_, event) {
        final key = event.logicalKey;
        if (event is KeyUpEvent) {
          repeats = 0;
          return KeyEventResult.ignored;
        }
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          nudge(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          if (draft != null) {
            finish();
          } else {
            widget.onToggle?.call();
          }
          return KeyEventResult.handled;
        }
        if (draft != null &&
            (key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.goBack)) {
          finish(commit: false);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) {
          if (event is KeyRepeatEvent) return KeyEventResult.handled;
          finish(commit: false);
          (key == LogicalKeyboardKey.arrowUp ? widget.onUp : widget.onDown)
              ?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        label: 'Перемотка',
        value: playbackTime(Duration(milliseconds: value.round())),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  playbackTime(Duration(milliseconds: value.round())),
                  style: TextStyle(
                    fontSize: 20,
                    color: draft == null ? Colors.white : accent,
                  ),
                ),
                const Spacer(),
                Text(
                  playbackTime(widget.duration),
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: focused
                    ? accent.withValues(alpha: .1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused ? accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ExcludeFocus(
                child: Slider(
                  value: value,
                  max: maximum,
                  activeColor: accent,
                  inactiveColor: Colors.white24,
                  onChangeStart: (_) => widget.onScrub(true),
                  onChanged: (v) => setState(() => draft = v),
                  onChangeEnd: (_) => finish(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Playback controls own stable focus nodes; updates never replace focused actions.
class TvPlaybackControls extends StatefulWidget {
  final String title, quality;
  final int episode, count, step;
  final double speed;
  final Duration position, duration;
  final bool playing, ready, initialFocusBack;
  final VoidCallback onBack, onToggle, onInteraction;
  final VoidCallback? onPrevious, onNext, onHide, onUpscale;
  final ValueChanged<int> onPanel;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool> onScrub;
  final GlobalKey<TvSeekBarState>? seekKey;
  const TvPlaybackControls({
    super.key,
    required this.title,
    required this.episode,
    required this.count,
    required this.quality,
    required this.speed,
    required this.position,
    required this.duration,
    required this.playing,
    required this.onBack,
    required this.onToggle,
    required this.onInteraction,
    required this.onPanel,
    required this.onSeek,
    required this.onScrub,
    this.onPrevious,
    this.onNext,
    this.onHide,
    this.onUpscale,
    this.step = 10,
    this.ready = true,
    this.initialFocusBack = false,
    this.seekKey,
  });
  @override
  State<TvPlaybackControls> createState() => TvPlaybackControlsState();
}

class TvPlaybackControlsState extends State<TvPlaybackControls> {
  final back = FocusNode(debugLabel: 'Player back');
  final nodes = List.generate(
    9,
    (i) => FocusNode(
      debugLabel: [
        'Previous episode',
        'Rewind',
        'Play pause',
        'Forward',
        'Next episode',
        'Episodes panel',
        'Audio panel',
        'Video panel',
        'Upscale panel',
      ][i],
    ),
  );
  final fallbackSeek = GlobalKey<TvSeekBarState>();
  GlobalKey<TvSeekBarState> get seek => widget.seekKey ?? fallbackSeek;
  void focusPlay() {
    if (mounted && widget.ready && ModalRoute.of(context)?.isCurrent == true) {
      nodes[2].requestFocus();
    }
  }

  void focusBack() {
    if (!mounted) return;
    back.requestFocus();
    widget.onInteraction();
  }

  void playFocusChanged() {
    if (mounted) setState(() {});
  }

  void focusUpscale() {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      (widget.ready ? nodes[8] : back).requestFocus();
    }
  }

  void focusPanel(int tab) {
    if (mounted) nodes[5 + tab].requestFocus();
  }

  @override
  void initState() {
    super.initState();
    for (final node in nodes) {
      node.addListener(playFocusChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.initialFocusBack ? focusBack() : focusPlay();
    });
  }

  @override
  void didUpdateWidget(TvPlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.ready && widget.ready && !back.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => focusPlay());
    }
  }

  @override
  void dispose() {
    for (final node in nodes) {
      node.removeListener(playFocusChanged);
    }
    back.dispose();
    for (final n in nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void move(int from, int direction) {
    var to = from + direction;
    while (to >= 0 && to < nodes.length) {
      if ((to != 0 || widget.onPrevious != null) &&
          (to != 4 || widget.onNext != null) &&
          (to != 8 || widget.onUpscale != null)) {
        nodes[to].requestFocus();
        return;
      }
      to += direction;
    }
  }

  Widget action(
    int index,
    IconData icon,
    String label,
    VoidCallback? callback, {
    bool primary = false,
  }) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        move(index, key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
        widget.onInteraction();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        if (event is KeyDownEvent) {
          seek.currentState?.focusNode.requestFocus();
          widget.onInteraction();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (event is KeyDownEvent) {
          focusPlay();
          widget.onInteraction();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: TvButton(
          focusNode: nodes[index],
          onPressed: callback,
          primary: primary && nodes[index].hasFocus,
          subtle: true,
          borderRadius: BorderRadius.circular(28),
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 26),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xb3000000),
            Color(0x00000000),
            Color(0xa6000000),
            Color(0xfa000000),
          ],
          stops: [0, .35, .6, 1],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(42, 28, 42, 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        focusPlay();
                        widget.onInteraction();
                        return KeyEventResult.handled;
                      }
                      if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                          event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        widget.onInteraction();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: labelButton(
                      'Назад',
                      widget.onBack,
                      icon: Icons.arrow_back_rounded,
                      focusNode: back,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'MJAnime',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xffabb5c5),
                      letterSpacing: -.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (widget.ready) ...[
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Text(
                      'Серия ${widget.episode} из ${widget.count}',
                      style: const TextStyle(
                        fontSize: 17,
                        color: Color(0xffd0dae6),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text('•', style: TextStyle(color: muted)),
                    const SizedBox(width: 14),
                    Text(
                      '${widget.quality == 'auto' ? 'Авто' : '${widget.quality}p'}${widget.speed == 1 ? '' : '  ·  ${widget.speed}×'}',
                      style: const TextStyle(fontSize: 17, color: muted),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 18),
                TvSeekBar(
                  key: seek,
                  position: widget.position,
                  duration: widget.duration,
                  step: widget.step,
                  onSeek: widget.onSeek,
                  onScrub: widget.onScrub,
                  onToggle: widget.onToggle,
                  onUp: widget.onHide,
                  onDown: focusPlay,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    action(
                      0,
                      Icons.skip_previous_rounded,
                      'Предыдущая серия',
                      widget.onPrevious,
                    ),
                    const SizedBox(width: 10),
                    action(
                      1,
                      Icons.replay_10_rounded,
                      'Назад на ${widget.step} сек',
                      () => widget.onSeek(
                        Duration(
                          milliseconds:
                              (widget.position.inMilliseconds -
                                      widget.step * 1000)
                                  .clamp(0, widget.duration.inMilliseconds),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    action(
                      2,
                      widget.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      widget.playing ? 'Пауза' : 'Продолжить',
                      widget.onToggle,
                      primary: true,
                    ),
                    const SizedBox(width: 10),
                    action(
                      3,
                      Icons.forward_10_rounded,
                      'Вперёд на ${widget.step} сек',
                      () => widget.onSeek(
                        Duration(
                          milliseconds:
                              (widget.position.inMilliseconds +
                                      widget.step * 1000)
                                  .clamp(0, widget.duration.inMilliseconds),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    action(
                      4,
                      Icons.skip_next_rounded,
                      'Следующая серия',
                      widget.onNext,
                    ),
                    const Spacer(),
                    action(
                      5,
                      Icons.video_library_outlined,
                      'Серии',
                      () => widget.onPanel(0),
                    ),
                    const SizedBox(width: 12),
                    action(
                      6,
                      Icons.graphic_eq_rounded,
                      'Озвучка',
                      () => widget.onPanel(1),
                    ),
                    const SizedBox(width: 12),
                    action(
                      7,
                      Icons.tune_rounded,
                      'Видео',
                      () => widget.onPanel(2),
                    ),
                    if (widget.onUpscale != null) ...[
                      const SizedBox(width: 12),
                      action(
                        8,
                        Icons.auto_fix_high_rounded,
                        'Апскейлер',
                        widget.onUpscale,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Markers are seconds; absent or invalid markers never invent a skip range.
Duration? openingSkipTarget(
  Json episode,
  Duration position,
  Duration duration,
) {
  final span = object(object(episode['skipdata'])['opening']);
  final start = number(span['start'], -1), stop = number(span['stop'], -1);
  if (start < 0 ||
      stop <= start ||
      stop > duration.inSeconds ||
      position.inMilliseconds < start * 1000 ||
      position.inMilliseconds >= stop * 1000) {
    return null;
  }
  return Duration(seconds: stop);
}

int nextEpisodeThreshold(Json episode, Duration duration) {
  final ending = object(object(episode['skipdata'])['ending']);
  final start = number(ending['start'], -1);
  final total = duration.inSeconds;
  return start >= total * .7 && start < total && total - start <= 180
      ? start
      : (total - 30).clamp(0, total);
}

class TvEpisodePrompt extends StatelessWidget {
  final int? nextEpisode, seconds;
  final ValueChanged<int>? onHiddenSeek;
  final VoidCallback? onHiddenUp;
  final VoidCallback onAction, onDismiss, onControls;
  final FocusNode actionFocus, dismissFocus;
  const TvEpisodePrompt({
    super.key,
    this.nextEpisode,
    this.seconds,
    this.onHiddenSeek,
    this.onHiddenUp,
    required this.onAction,
    required this.onDismiss,
    required this.onControls,
    required this.actionFocus,
    required this.dismissFocus,
  });
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        if (onHiddenSeek != null) {
          onHiddenSeek!(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
        } else {
          (key == LogicalKeyboardKey.arrowLeft ? actionFocus : dismissFocus)
              .requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        if (event is KeyDownEvent) {
          if (key == LogicalKeyboardKey.arrowUp && onHiddenUp != null) {
            onHiddenUp!();
          } else {
            onControls();
          }
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Container(
      width: nextEpisode == null ? 355 : 420,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xf20c0e15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xff303744)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nextEpisode != null) ...[
            const Text(
              'Следующая серия',
              style: TextStyle(color: accent, fontSize: 13, letterSpacing: 1),
            ),
            const SizedBox(height: 7),
            Text(
              'Серия $nextEpisode',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              seconds == null
                  ? 'Продолжить просмотр?'
                  : 'Начнётся через $seconds сек',
              style: const TextStyle(color: muted, fontSize: 15),
            ),
            const SizedBox(height: 16),
          ],
          if (!actionFocus.hasFocus && !dismissFocus.hasFocus) ...[
            const Row(
              children: [
                Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: muted),
                SizedBox(width: 6),
                Text(
                  'Выбрать действие',
                  style: TextStyle(fontSize: 16, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TvButton(
                  focusNode: actionFocus,
                  onPressed: onAction,
                  selected: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Text(
                    nextEpisode == null
                        ? 'Пропустить опенинг'
                        : 'Смотреть сейчас',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TvButton(
                focusNode: dismissFocus,
                onPressed: onDismiss,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                child: Text(
                  nextEpisode == null ? 'Скрыть' : 'Остаться',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
