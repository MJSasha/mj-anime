import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'auth.dart';
import 'cast.dart';
import 'ui.dart';
import 'tv_playback.dart';
import 'anime_upscale.dart';

class PlayerScreen extends StatefulWidget {
  final Session session;
  final Json anime, playlist;
  final int index;
  final bool isVideoCheck;
  final int? tid, startPosition;
  final Json? remote;
  final CastTransport? cast;
  const PlayerScreen({
    super.key,
    required this.session,
    required this.anime,
    required this.playlist,
    required this.index,
    this.isVideoCheck = false,
    this.tid,
    this.startPosition,
    this.remote,
    this.cast,
  });
  @override
  State<PlayerScreen> createState() => _PlayerState();
}

class _PlayerState extends State<PlayerScreen> with WidgetsBindingObserver {
  VideoPlayerController? controller;
  StreamSubscription<Json>? castSubscription;
  bool applyingRemote = false, closingRemote = false;
  bool initialRemoteApplied = false;
  late Json playlist;
  late int index;
  int? tid;
  String quality = '720';
  bool controls = true, loading = true, saving = false, advancing = false;
  String? error;
  bool sourceMissing = false;
  final recoveryFocus = FocusNode(debugLabel: 'Player recovery');
  bool get promptVisible {
    final c = controller;
    if (error != null ||
        panelOpen ||
        scrubbing ||
        c == null ||
        !c.value.isInitialized ||
        index >= episodes.length) {
      return false;
    }
    return (nextStarted != null && !nextDismissed && hasNext) ||
        (!openingDismissed &&
            openingSkipTarget(
                  episodes[index],
                  c.value.position,
                  c.value.duration,
                ) !=
                null);
  }

  void focusPrompt() {
    if (promptVisible) promptActionFocus.requestFocus();
  }

  void syncPromptFocus() {
    final visible =
        promptVisible &&
        (nextStarted != null ||
            !(widget.session.prefs.getBool('autoSkipOpeningEnding') ?? false));
    if (visible && !promptWasVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            promptVisible &&
            ModalRoute.of(context)?.isCurrent == true) {
          focusPrompt();
        }
      });
    }
    promptWasVisible = visible;
  }

  void remoteBack() {
    if (scrubbing) {
      seekKey.currentState?.finish(commit: false);
    } else if (promptVisible) {
      dismissPrompt();
    } else {
      Navigator.pop(context);
    }
  }

  void showFailure(String message) {
    if (!mounted) return;
    hide?.cancel();
    setState(() {
      error = message;
      loading = false;
      controls = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && error != null) recoveryFocus.requestFocus();
    });
  }

  BoxFit fit = BoxFit.contain;
  String upscaleMode = 'off';
  bool upscaleChanging = false, recoveringUpscale = false;
  Duration goodVideoPosition = Duration.zero;
  bool goodVideoPlaying = true;
  double speed = 1;
  Timer? heartbeat, hide;
  int epoch = 0, lastSaved = 0, played = 0;
  List<Json> episodes = [];
  int? nextStarted;
  bool nextDismissed = false, openingDismissed = false, hadOpening = false;
  bool promptWasVisible = false, savedOnExit = false;
  final promptActionFocus = FocusNode(debugLabel: 'Episode prompt action');
  final promptDismissFocus = FocusNode(debugLabel: 'Episode prompt dismiss');
  void promptFocusChanged() {
    if (mounted) setState(() {});
  }

  bool get promptFocused =>
      promptActionFocus.hasFocus || promptDismissFocus.hasFocus;
  bool get hasNext => index + 1 < episodes.length;
  bool get autoNext => widget.session.prefs.getBool('autoNextEpisode') ?? true;
  void restorePlaybackFocus() {
    if (!mounted) return;
    if (controls) {
      controlsKey.currentState?.focusPlay();
    } else {
      playbackFocus.requestFocus();
    }
  }

  void dismissPrompt() {
    setState(() {
      if (nextStarted != null) {
        nextDismissed = true;
        nextStarted = null;
      } else {
        openingDismissed = true;
      }
    });
    restorePlaybackFocus();
  }

  Future<void> advanceEpisode() async {
    if (advancing || !hasNext) return;
    advancing = true;
    try {
      await changeEpisode(index + 1);
    } finally {
      advancing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    promptActionFocus.addListener(promptFocusChanged);
    promptDismissFocus.addListener(promptFocusChanged);
    keepAwake(true);
    playlist = widget.playlist;
    episodes = objects(playlist['list']);
    index = widget.index;
    final voices = objects(playlist['translations']);
    final initialVoice =
        voices.where((v) => v['selected'] == true).firstOrNull ??
        voices.firstOrNull;
    tid =
        widget.tid ??
        (initialVoice == null ? null : number(initialVoice['value']));
    upscaleMode = readUpscaleMode(widget.session.prefs);
    quality = widget.session.prefs.getString('preferredQuality') ?? 'auto';
    widget.cast?.activeAnimeId = animeId(widget.anime);
    castSubscription = widget.cast?.events.stream.listen(applyRemote);
    VideoUpscale.failure.addListener(upscaleFailure);
    open(resume: true);
    heartbeat = Timer.periodic(const Duration(seconds: 15), (_) => save());
  }

  @override
  void dispose() {
    epoch++;
    VideoUpscale.failure.removeListener(upscaleFailure);
    playbackFocus.dispose();
    recoveryFocus.dispose();
    promptActionFocus.removeListener(promptFocusChanged);
    promptDismissFocus.removeListener(promptFocusChanged);
    promptActionFocus.dispose();
    promptDismissFocus.dispose();
    castSubscription?.cancel();
    widget.cast?.activeAnimeId = null;
    WidgetsBinding.instance.removeObserver(this);
    keepAwake(false);
    heartbeat?.cancel();
    hide?.cancel();
    final c = controller;
    controller = null;
    if (!savedOnExit) saveFrom(c);
    c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      controller?.pause();
      save();
    }
  }

  Future<void> keepAwake(bool enabled) async {
    try {
      await platform.invokeMethod('setKeepScreenOn', enabled);
    } catch (_) {
      /* No platform channel in offline widget tests. */
    }
  }

  Future<void> saveFrom(VideoPlayerController? c) async {
    if (widget.isVideoCheck) return;
    if (c == null || !c.value.isInitialized) return;
    try {
      await widget.session.progress(
        widget.anime,
        index + 1,
        c.value.position.inSeconds,
        c.value.duration.inSeconds,
        tid,
        played: played,
      );
      played = 0;
    } catch (_) {
      /* Local progress remains saved if account sync is unavailable. */
    }
  }

  Future<void> save() async {
    if (saving) return;
    saving = true;
    try {
      await saveFrom(controller);
    } finally {
      saving = false;
    }
  }

  Future<void> open({bool resume = false, int? position, bool? paused}) async {
    final seq = ++epoch;
    final old = controller;
    controller = null;
    await old?.dispose();
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
      sourceMissing = false;
      promptWasVisible = false;
    });
    VideoPlayerController? pending;
    bool processingAttempt = false;
    try {
      if (episodes.isEmpty) {
        sourceMissing = true;
        throw ApiFailure(404, 'Нет доступных серий');
      }
      final ep = episodes[index];
      var variants = qualityVariants('${ep['file'] ?? ''}');
      if (variants.isEmpty &&
          ep['file'] is String &&
          (ep['file'] as String).trim().isNotEmpty) {
        variants = [
          {'quality': 'auto', 'url': absolute(ep['file'])},
        ];
      }
      if (variants.isEmpty) {
        sourceMissing = true;
        throw ApiFailure(404, 'Серия не содержит ссылки на видео');
      }
      final selected =
          variants.where((v) => v['quality'] == quality).firstOrNull ??
          variants.last;
      quality = '${selected['quality']}';
      final source = '${selected['url']}';
      final url = widget.isVideoCheck
          ? ''
          : await resolveVideo(source, token: widget.session.api.token);
      final configured = await VideoUpscale.configure(upscaleMode);
      if (!mounted || seq != epoch) return;
      if (!configured && upscaleMode != 'off') {
        setState(() => upscaleMode = 'off');
        await widget.session.prefs.setString(upscalePreference, 'off');
        await VideoUpscale.configure('off');
        if (!mounted || seq != epoch) return;
        errorMessage(
          context,
          'Улучшение изображения недоступно. Воспроизводим без обработки.',
        );
      }
      processingAttempt = upscaleMode != 'off';
      final c = widget.isVideoCheck
          ? VideoPlayerController.asset('assets/video_check.mp4')
          : VideoPlayerController.networkUrl(
              Uri.parse(url),
              formatHint: url.contains('.m3u8') ? VideoFormat.hls : null,
              httpHeaders: videoHeaders(url, token: widget.session.api.token),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
            );
      pending = c;
      await c.initialize().timeout(
        Duration(seconds: processingAttempt ? 15 : 45),
      );
      if (!mounted || seq != epoch) {
        await c.dispose();
        return;
      }
      if (c.value.size.isEmpty) {
        throw StateError('Не получен размер видеокадра');
      }
      if (widget.isVideoCheck) await c.setLooping(true);
      pending = null;
      controller = c;
      c.addListener(tick);
      int start = position ?? (resume ? widget.startPosition : null) ?? 0;
      if (resume && (widget.session.prefs.getBool('resume') ?? true)) {
        final h = widget.session.localHistory
            .where(
              (h) =>
                  number(h['animetka_id']) == animeId(widget.anime) &&
                  number(h['episode']) == index + 1,
            )
            .firstOrNull;
        if (h != null && widget.startPosition == null) {
          start = number(h['timestamp']);
        }
      }
      if (start > 0 && start < c.value.duration.inSeconds - 10) {
        await c.seekTo(Duration(seconds: start));
      }
      await c.setPlaybackSpeed(speed);
      if (paused != null) {
        if (!paused) await c.play();
      } else if (widget.remote != null && !initialRemoteApplied) {
        initialRemoteApplied = true;
        await c.seekTo(
          Duration(
            milliseconds:
                ((double.tryParse('${widget.remote!['position_seconds']}') ??
                            0) *
                        1000)
                    .round(),
          ),
        );
        if (widget.remote!['paused'] == false) await c.play();
      } else {
        await c.play();
      }
      widget.cast?.ready();
      if (mounted) setState(() => loading = false);
      showControls();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && seq == epoch && !panelOpen) {
          controlsKey.currentState?.focusPlay();
        }
      });
    } catch (e) {
      await pending?.dispose();
      if (mounted && seq == epoch) {
        if (processingAttempt && upscaleMode != 'off' && !recoveringUpscale) {
          await recoverUpscale(
            position: position,
            paused: paused,
            resume: resume,
          );
        } else {
          showFailure('$e');
        }
      }
    }
  }

  void upscaleFailure() {
    if (VideoUpscale.failure.value != null &&
        controller?.value.isInitialized == true) {
      recoverUpscale();
    }
  }

  Future<void> recoverUpscale({
    int? position,
    bool? paused,
    bool resume = false,
  }) async {
    if (!mounted || recoveringUpscale || upscaleMode == 'off') return;
    recoveringUpscale = true;
    final failed = controller?.value.hasError ?? false;
    final start =
        position ??
        (failed
            ? goodVideoPosition.inSeconds
            : controller?.value.position.inSeconds);
    final wasPaused = failed
        ? !goodVideoPlaying
        : paused ?? (controller == null ? null : !controller!.value.isPlaying);
    try {
      await save();
      if (!mounted) return;
      setState(() => upscaleMode = 'off');
      await widget.session.prefs.setString(upscalePreference, 'off');
      if (!mounted) return;
      await open(position: start, paused: wasPaused, resume: resume);
      if (!mounted) return;
      VideoUpscale.status.value =
          'Без обработки: не удалось вывести видео с апскейлером';
      errorMessage(context, 'Апскейлер отключён: возвращено обычное видео.');
    } finally {
      recoveringUpscale = false;
    }
  }

  void tick() {
    final c = controller;
    if (c == null || !mounted) return;
    if (c.value.hasError && error != c.value.errorDescription) {
      if (recoveringUpscale) return;
      if (upscaleMode != 'off') {
        recoverUpscale();
        return;
      }
      showFailure(c.value.errorDescription ?? 'Ошибка воспроизведения');
      return;
    }
    if (c.value.isInitialized) {
      goodVideoPosition = c.value.position;
      goodVideoPlaying = c.value.isPlaying;
    }
    if (c.value.isPlaying && c.value.position.inSeconds != lastSaved) {
      lastSaved = c.value.position.inSeconds;
      played++;
    }
    if (c.value.isInitialized && c.value.duration > Duration.zero) {
      final value = c.value;
      final seconds = value.position.inSeconds;
      final inTail =
          seconds >= nextEpisodeThreshold(episodes[index], value.duration);
      final opening =
          openingSkipTarget(episodes[index], value.position, value.duration) !=
          null;
      if (!opening && hadOpening) {
        openingDismissed = false;
        if (promptFocused && nextStarted == null) restorePlaybackFocus();
      }
      hadOpening = opening;
      if (!inTail || panelOpen || scrubbing) {
        if (!inTail) nextDismissed = false;
        if (nextStarted != null) {
          if (promptFocused) restorePlaybackFocus();
          setState(() => nextStarted = null);
        }
      } else if (hasNext && !nextDismissed && !advancing) {
        if (nextStarted == null && value.isPlaying) {
          setState(() => nextStarted = value.position.inMilliseconds);
        }
        if (autoNext &&
            ((nextStarted != null &&
                    value.isPlaying &&
                    value.position.inMilliseconds - nextStarted! >= 10000) ||
                value.position >= value.duration)) {
          advanceEpisode();
          return;
        }
      }
    }
    widget.cast?.position(
      c.value.position.inMilliseconds / 1000,
      !c.value.isPlaying,
      c.value.playbackSpeed,
    );
    if (widget.session.prefs.getBool('autoSkipOpeningEnding') ?? false) {
      final skip = object(episodes[index]['skipdata']);
      for (final part in ['opening', 'ending']) {
        if (part == 'ending' && hasNext) continue;
        final span = object(skip[part]);
        final start = number(span['start'], -1),
            stop = number(span['stop'], -1);
        if (start >= 0 &&
            stop > start &&
            c.value.position.inSeconds >= start &&
            c.value.position.inSeconds < stop) {
          c.seekTo(Duration(seconds: stop));
          break;
        }
      }
    }
    syncPromptFocus();
    // Position changes rebuild only the controls via ValueListenableBuilder.
  }

  Future<void> applyRemote(Json event) async {
    final cast = widget.cast;
    if (cast == null || closingRemote || !mounted) return;
    if (event['chat_id'] != null &&
        event['chat_id'].toString() != cast.chatId) {
      return;
    }
    if (event['type'] == 'watch:end') {
      closingRemote = true;
      if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
      return;
    }
    if (applyingRemote) return;
    if (event['type'] == 'watch:volume') {
      final v = double.tryParse('${event['level'] ?? event['volume']}');
      if (v != null) await platform.invokeMethod('setVolume', v.clamp(0, 1));
      return;
    }
    if (!['watch:sync', 'watch:state', 'watch:start'].contains(event['type'])) {
      return;
    }
    final state = {...object(event['state']), ...event};
    if (state['chat_id'] != null &&
        state['chat_id'].toString() != cast.chatId) {
      return;
    }
    applyingRemote = true;
    try {
      final nextTid = state['translation_id'] == null
          ? tid
          : number(state['translation_id']);
      final nextEpisode = state['episode'] == null
          ? index
          : number(state['episode'], 1) - 1;
      if (nextTid != tid && nextTid != null) await changeTranslation(nextTid);
      if (nextEpisode != index &&
          nextEpisode >= 0 &&
          nextEpisode < episodes.length) {
        await changeEpisode(nextEpisode);
      }
      final q = state['quality']?.toString();
      if (q != null && q.isNotEmpty && q != quality) {
        quality = q;
        await open(position: controller?.value.position.inSeconds);
      }
      final c = controller;
      if (c == null || !c.value.isInitialized) return;
      final seconds = double.tryParse('${state['position_seconds']}');
      if (seconds != null &&
          (seconds * 1000 - c.value.position.inMilliseconds).abs() > 800) {
        await c.seekTo(Duration(milliseconds: (seconds * 1000).round()));
      }
      final rate = double.tryParse('${state['playback_rate']}');
      if (rate != null && rate >= .25 && rate <= 2) {
        speed = rate;
        await c.setPlaybackSpeed(rate);
      }
      if (state.containsKey('paused')) {
        if (state['paused'] == false) {
          await c.play();
        } else {
          await c.pause();
        }
      }
    } catch (e) {
      if (mounted) errorMessage(context, e);
    } finally {
      applyingRemote = false;
    }
  }

  final seekKey = GlobalKey<TvSeekBarState>();
  final controlsKey = GlobalKey<TvPlaybackControlsState>();
  final playbackFocus = FocusNode(debugLabel: 'Playback surface');
  bool panelOpen = false, focusTopOnShow = false;
  void hideControls() {
    hide?.cancel();
    if (!mounted) return;
    setState(() => controls = false);
    if (!promptFocused) playbackFocus.requestFocus();
  }

  bool scrubbing = false;
  void showControls({bool top = false}) {
    hide?.cancel();
    if (!mounted || error != null) return;
    final wasHidden = !controls;
    if (wasHidden) {
      setState(() {
        focusTopOnShow = top;
        controls = true;
      });
    }
    hide = Timer(const Duration(seconds: 6), () {
      if (mounted && controls && !scrubbing && !panelOpen) {
        hideControls();
      }
    });
  }

  Future<void> changeUpscale(String mode) async {
    if (mode == upscaleMode) return;
    final c = controller;
    final position = c?.value.position.inSeconds ?? 0;
    final paused = c?.value.isPlaying == false;
    await save();
    if (!mounted) return;
    setState(() => upscaleMode = mode);
    await widget.session.prefs.setString(upscalePreference, mode);
    if (mounted) await open(position: position, paused: paused);
  }

  Future<void> changeEpisode(int i) async {
    if (i < 0 || i >= episodes.length) return;
    await save();
    if (!mounted) return;
    index = i;
    nextStarted = null;
    nextDismissed = false;
    openingDismissed = false;
    hadOpening = false;
    await open();
  }

  Future<void> changeTranslation(int id) async {
    await save();
    final position = controller?.value.position.inSeconds ?? 0;
    try {
      final p = await widget.session.api.playlist(animeId(widget.anime), id);
      if (!mounted) return;
      playlist = p;
      episodes = objects(playlist['list']);
      tid = id;
      index = index.clamp(0, (episodes.length - 1).clamp(0, 99999));
      await open(position: position);
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }

  int get seekStep => widget.session.prefs.getInt('doubleTapSeekSeconds') ?? 10;
  void seek(int seconds, {bool reveal = true}) {
    final c = controller;
    if (c == null) return;
    c.seekTo(
      Duration(
        seconds: (c.value.position.inSeconds + seconds).clamp(
          0,
          c.value.duration.inSeconds,
        ),
      ),
    );
    if (reveal) showControls();
  }

  void toggle() {
    final c = controller;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
    showControls();
  }

  KeyEventResult key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.escape) {
      if (e is KeyDownEvent) remoteBack();
      return KeyEventResult.handled;
    }
    if (error != null) return KeyEventResult.ignored;
    if (e is KeyRepeatEvent &&
        [
          LogicalKeyboardKey.mediaPlayPause,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.enter,
        ].contains(k)) {
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause ||
        k == LogicalKeyboardKey.mediaStop) {
      if (k == LogicalKeyboardKey.mediaPlay) {
        controller?.play();
      } else {
        controller?.pause();
      }
      showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      seek(-seekStep);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      seek(seekStep);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext) {
      changeEpisode(index + 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious) {
      changeEpisode(index - 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.space) {
      toggle();
      return KeyEventResult.handled;
    }
    if (!controls) {
      if (k == LogicalKeyboardKey.arrowUp) {
        if (e is KeyDownEvent) showControls(top: true);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        seek(
          k == LogicalKeyboardKey.arrowRight ? seekStep : -seekStep,
          reveal: false,
        );
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
        toggle();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        if (e is KeyDownEvent) showControls();
        return KeyEventResult.handled;
      }
    }
    if (controls) showControls();
    return KeyEventResult.ignored;
  }

  String time(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Theme(
      data: mjTheme(),
      child: PopScope(
        canPop: !scrubbing && !promptVisible,
        onPopInvokedWithResult: (did, result) {
          if (did) {
            savedOnExit = true;
            saveFrom(controller);
          } else {
            remoteBack();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            autofocus: true,
            focusNode: playbackFocus,
            onKeyEvent: key,
            child: GestureDetector(
              onTap: showControls,
              onDoubleTapDown: (details) => seek(
                details.localPosition.dx < MediaQuery.sizeOf(context).width / 2
                    ? -seekStep
                    : seekStep,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (c != null && c.value.isInitialized)
                    FittedBox(
                      fit: fit,
                      child: SizedBox(
                        width: c.value.size.width,
                        height: c.value.size.height,
                        child: VideoPlayer(c),
                      ),
                    ),
                  if (loading) const Center(child: CircularProgressIndicator()),
                  if (error != null)
                    Center(
                      child: Container(
                        width: 620,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: accent,
                              size: 36,
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Не удалось воспроизвести серию',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              error!,
                              style: const TextStyle(
                                fontSize: 18,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (!sourceMissing)
                              SizedBox(
                                width: double.infinity,
                                child: TvButton(
                                  focusNode: recoveryFocus,
                                  primary: true,
                                  onPressed: () => open(
                                    position: c?.value.position.inSeconds,
                                  ),
                                  child: const Text(
                                    'Повторить',
                                    style: TextStyle(fontSize: 20),
                                  ),
                                ),
                              ),
                            if (objects(playlist['translations']).length >
                                1) ...[
                              if (!sourceMissing) const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: TvButton(
                                  outlined: !sourceMissing,
                                  primary: sourceMissing,
                                  focusNode: sourceMissing
                                      ? recoveryFocus
                                      : null,
                                  onPressed: () => panel(1),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.graphic_eq_rounded),
                                      SizedBox(width: 12),
                                      Text('Выбрать другую озвучку'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TvButton(
                                outlined: true,
                                focusNode:
                                    sourceMissing &&
                                        objects(playlist['translations'])
                                                .length <=
                                            1
                                    ? recoveryFocus
                                    : null,
                                onPressed: () => Navigator.pop(context),
                                child: const Row(
                                  children: [
                                    Icon(Icons.arrow_back_rounded),
                                    SizedBox(width: 12),
                                    Text('К сериям'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (c != null)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (_, value, _) =>
                          value.isBuffering && error == null
                          ? const Center(
                              child: CircularProgressIndicator(color: accent),
                            )
                          : const SizedBox.shrink(),
                    ),
                  if (controls && error == null)
                    if (c != null)
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: c,
                        builder: (_, value, _) => playbackControls(c, value),
                      )
                    else
                      playbackControls(null, null),
                  if (c != null && c.value.isInitialized)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (_, value, _) => episodePrompt(c, value),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget episodePrompt(VideoPlayerController c, VideoPlayerValue value) {
    final skip = index < episodes.length && !openingDismissed
        ? openingSkipTarget(episodes[index], value.position, value.duration)
        : null;
    final next = nextStarted != null && !nextDismissed && hasNext;
    if (panelOpen || scrubbing || error != null || (skip == null && !next)) {
      return const SizedBox.shrink();
    }
    final remaining = next && autoNext
        ? ((10000 - (value.position.inMilliseconds - nextStarted!)).clamp(
                    0,
                    10000,
                  ) /
                  1000)
              .ceil()
        : null;
    return Positioned(
      right: 42,
      bottom: controls ? 285 : 42,
      child: TvEpisodePrompt(
        nextEpisode: next ? index + 2 : null,
        seconds: remaining,
        actionFocus: promptActionFocus,
        dismissFocus: promptDismissFocus,
        onAction: next
            ? advanceEpisode
            : () {
                if (skip != null) c.seekTo(skip);
              },
        onDismiss: dismissPrompt,
        onHiddenUp: controls ? null : () => showControls(top: true),
        onHiddenSeek: controls
            ? null
            : (direction) => seek(direction * seekStep, reveal: false),
        onControls: () {
          showControls();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) controlsKey.currentState?.focusPlay();
          });
        },
      ),
    );
  }

  Widget playbackControls(VideoPlayerController? c, VideoPlayerValue? value) =>
      TvPlaybackControls(
        key: controlsKey,
        title: title(widget.anime),
        episode: index + 1,
        count: episodes.length,
        quality: quality,
        speed: speed,
        step: seekStep,
        position: value?.position ?? Duration.zero,
        duration: value?.duration ?? Duration.zero,
        playing: value?.isPlaying ?? false,
        ready: value?.isInitialized == true,
        seekKey: seekKey,
        initialFocusBack: focusTopOnShow,
        onBack: () => Navigator.pop(context),
        onHide: hideControls,
        onToggle: toggle,
        onInteraction: showControls,
        onPrevious: index > 0 ? () => changeEpisode(index - 1) : null,
        onNext: index + 1 < episodes.length
            ? () => changeEpisode(index + 1)
            : null,
        onPanel: (tab) => panel(tab),
        onUpscale: upscalePanel,
        onSeek: (position) {
          c?.seekTo(position);
          showControls();
        },
        onScrub: (active) {
          if (mounted) setState(() => scrubbing = active);
          if (active) {
            hide?.cancel();
          } else {
            showControls();
          }
        },
      );

  Widget upscaleSelector(
    BuildContext dialog,
    StateSetter update, {
    bool autofocus = false,
  }) => ValueListenableBuilder<String?>(
    valueListenable: VideoUpscale.status,
    builder: (_, status, _) => AnimeUpscaleSelector(
      mode: upscaleMode,
      showStatus: true,
      autofocus: autofocus,
      onChanged: (value) async {
        if (upscaleChanging) return;
        update(() => upscaleChanging = true);
        try {
          await changeUpscale(value);
        } finally {
          if (mounted && dialog.mounted) update(() => upscaleChanging = false);
        }
      },
    ),
  );

  Future<void> upscalePanel() async {
    if (panelOpen) return;
    panelOpen = true;
    showControls();
    hide?.cancel();
    await showDialog<void>(
      context: context,
      builder: (dialog) => Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if ([
            LogicalKeyboardKey.goBack,
            LogicalKeyboardKey.browserBack,
            LogicalKeyboardKey.escape,
          ].contains(event.logicalKey)) {
            if (event is KeyDownEvent) Navigator.pop(dialog);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: StatefulBuilder(
          builder: (dialog, update) => Dialog(
            alignment: Alignment.bottomRight,
            insetPadding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 520,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Апскейлер', style: TextStyle(fontSize: 24)),
                        const Spacer(),
                        labelButton(
                          'Закрыть',
                          () => Navigator.pop(dialog),
                          icon: Icons.close,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    upscaleSelector(dialog, update, autofocus: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    panelOpen = false;
    if (!mounted) return;
    showControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controlsKey.currentState?.focusUpscale();
    });
  }

  Future<void> panel([int selectedTab = 2]) async {
    if (panelOpen) return;
    panelOpen = true;
    final opener = selectedTab;
    final panelScroll = ScrollController(
      initialScrollOffset: selectedTab == 0
          ? (index - 2).clamp(0, episodes.length) * 66.0
          : 0,
    );
    showControls();
    hide?.cancel();
    await showDialog(
      context: context,
      builder: (d) => Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack) {
            if (event is KeyDownEvent) Navigator.pop(d);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: StatefulBuilder(
          builder: (d, update) => Dialog(
            alignment: Alignment.centerRight,
            insetPadding: const EdgeInsets.all(20),
            backgroundColor: surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: SizedBox(
              width: 470,
              height: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Ваш просмотр',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        labelButton(
                          'Закрыть',
                          () => Navigator.pop(d),
                          autofocus: false,
                          icon: Icons.close,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title(widget.anime),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: List.generate(
                        3,
                        (i) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: tabButton(
                              ['Серии', 'Озвучка', 'Видео'][i],
                              () {
                                update(() => selectedTab = i);
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (panelScroll.hasClients) {
                                    panelScroll.jumpTo(
                                      i == 0
                                          ? ((index - 2).clamp(
                                                      0,
                                                      episodes.length,
                                                    ) *
                                                    66.0)
                                                .clamp(
                                                  0,
                                                  panelScroll
                                                      .position
                                                      .maxScrollExtent,
                                                )
                                          : 0,
                                    );
                                  }
                                });
                              },
                              selected: selectedTab == i,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: Scrollbar(
                        controller: panelScroll,
                        thumbVisibility: true,
                        child: ListView(
                          controller: panelScroll,
                          key: ValueKey(selectedTab),
                          padding: const EdgeInsets.all(4),
                          children: [
                            if (selectedTab == 0)
                              ...List.generate(
                                episodes.length,
                                (i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: TvButton(
                                    autofocus: i == index,
                                    selected: i == index,
                                    onPressed: () {
                                      Navigator.pop(d);
                                      changeEpisode(i);
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          i == index
                                              ? Icons.play_circle
                                              : Icons.play_circle_outline,
                                        ),
                                        const SizedBox(width: 14),
                                        Text('Серия ${i + 1}'),
                                        const Spacer(),
                                        if (i == index)
                                          const Text(
                                            'Сейчас',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (selectedTab == 1)
                              ...objects(playlist['translations']).map(
                                (t) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: TvButton(
                                    selected: tid == number(t['value']),
                                    autofocus: tid == number(t['value']),
                                    onPressed: () {
                                      Navigator.pop(d);
                                      changeTranslation(number(t['value']));
                                    },
                                    child: Row(
                                      children: [
                                        Expanded(child: Text('${t['name']}')),
                                        if (tid == number(t['value']))
                                          const Icon(
                                            Icons.check_circle_outline,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (selectedTab == 2) ...[
                              const Text(
                                'Качество видео',
                                style: TextStyle(fontSize: 21),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children:
                                    qualityVariants(
                                          episodes.isEmpty
                                              ? ''
                                              : '${episodes[index]['file'] ?? ''}',
                                        )
                                        .map(
                                          (v) => labelButton(
                                            '${v['quality']}p',
                                            () {
                                              quality = '${v['quality']}';
                                              Navigator.pop(d);
                                              open(
                                                position: controller
                                                    ?.value
                                                    .position
                                                    .inSeconds,
                                              );
                                            },
                                            selected: quality == v['quality'],
                                            autofocus: quality == v['quality'],
                                          ),
                                        )
                                        .toList(),
                              ),
                              const SizedBox(height: 28),
                              const Text(
                                'Скорость просмотра',
                                style: TextStyle(fontSize: 21),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [.5, .75, 1.0, 1.25, 1.5, 2.0]
                                    .map(
                                      (v) => SizedBox(
                                        width: 120,
                                        child: labelButton('$v×', () {
                                          speed = v;
                                          controller?.setPlaybackSpeed(v);
                                          update(() {});
                                        }, selected: speed == v),
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 28),
                              upscaleSelector(d, update),
                              const SizedBox(height: 28),
                              const Text(
                                'Изображение',
                                style: TextStyle(fontSize: 21),
                              ),
                              const SizedBox(height: 12),
                              ...[
                                BoxFit.contain,
                                BoxFit.cover,
                                BoxFit.fill,
                              ].indexed.map(
                                (v) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: labelButton(
                                    [
                                      'Вписать в экран',
                                      'Заполнить экран',
                                      'Растянуть',
                                    ][v.$1],
                                    () {
                                      setState(() => fit = v.$2);
                                      update(() {});
                                    },
                                    selected: fit == v.$2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    panelScroll.dispose();
    panelOpen = false;
    if (mounted) {
      showControls();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (error != null) {
          recoveryFocus.requestFocus();
        } else {
          controlsKey.currentState?.focusPanel(opener);
        }
      });
    }
  }

  Future<void> volume(double delta) async {
    try {
      final v = await platform.invokeMethod<double>('getVolume') ?? .5;
      await platform.invokeMethod('setVolume', (v + delta).clamp(0, 1));
    } catch (e) {
      if (mounted) errorMessage(context, e);
    }
  }
}
