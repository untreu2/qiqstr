import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../common/snackbar_widget.dart';
import '../common/common_buttons.dart';

// ---------------------------------------------------------------------------
// Global position cache — survives widget rebuilds and page transitions
// ---------------------------------------------------------------------------

class VideoPositionCache {
  VideoPositionCache._();
  static final VideoPositionCache instance = VideoPositionCache._();

  final Map<String, Duration> _positions = {};

  Duration get(String url) => _positions[url] ?? Duration.zero;

  void save(String url, Duration position) {
    if (position > Duration.zero) _positions[url] = position;
  }

  void clear() => _positions.clear();
}

// ---------------------------------------------------------------------------
// Inline video player — always muted, always auto-plays, tap → fullscreen
// ---------------------------------------------------------------------------

class VP extends StatefulWidget {
  final String url;
  final String? authorProfileImageUrl;

  const VP({
    super.key,
    required this.url,
    this.authorProfileImageUrl,
  });

  @override
  State<VP> createState() => _VPState();
}

class _VPState extends State<VP> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    _controller?.pause();
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller?.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_isInitialized) _controller?.play();
    }
  }

  // ── controller ─────────────────────────────────────────────────────────────

  void _initController() {
    if (_isLoading || _isInitialized) return;
    _isLoading = true;

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = ctrl;

    ctrl.initialize().then((_) {
      if (!mounted || _controller != ctrl) return;

      ctrl.setVolume(0);
      ctrl.setLooping(true);

      // Resume from saved position if any
      final saved = VideoPositionCache.instance.get(widget.url);
      if (saved > Duration.zero) ctrl.seekTo(saved);

      ctrl.play();
      ctrl.addListener(_onUpdate);

      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  // ── open fullscreen ─────────────────────────────────────────────────────────

  void _openFullScreen() {
    final ctrl = _controller;

    // Save current position before handing off
    if (ctrl != null && ctrl.value.isInitialized) {
      VideoPositionCache.instance.save(widget.url, ctrl.value.position);
      ctrl.pause();
    }

    Navigator.of(context, rootNavigator: true)
        .push(_FullScreenRoute(
          child: FullScreenVideoPlayer(url: widget.url),
        ))
        .then((_) {
      // When fullscreen closes, resume muted inline from wherever fullscreen left off
      if (!mounted) return;
      final position = VideoPositionCache.instance.get(widget.url);
      if (_isInitialized && ctrl != null) {
        if (position > Duration.zero) ctrl.seekTo(position);
        ctrl.play();
        setState(() {});
      }
    });
  }

  // ── build ──────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final ready = _isInitialized && ctrl != null && ctrl.value.isInitialized;
    final duration = ready ? ctrl.value.duration : Duration.zero;
    final position = ready ? ctrl.value.position : Duration.zero;
    final progress = (duration.inMilliseconds > 0)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = duration - position;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: GestureDetector(
            onTap: _openFullScreen,
            child: ready
                ? Stack(
                    children: [
                      // Video frame
                      Positioned.fill(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: ctrl.value.size.width,
                            height: ctrl.value.size.height,
                            child: VideoPlayer(ctrl),
                          ),
                        ),
                      ),

                      // Mute badge (top-left)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.volume_off_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),

                      // Fullscreen hint (top-right)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CarbonIcons.maximize,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),

                      // Bottom: thin progress bar + remaining time
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _fmt(remaining),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 2.5,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.25),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: Colors.grey.shade900,
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.play_circle_outline_rounded,
                              color: Colors.white54,
                              size: 48,
                            ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom route — fade + scale transition, transparent background
// ---------------------------------------------------------------------------

class _FullScreenRoute extends PageRouteBuilder {
  _FullScreenRoute({required Widget child})
      : super(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, __, ___) => child,
          transitionsBuilder: (_, animation, __, child) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            );
            final scale = Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            return FadeTransition(
              opacity: fade,
              child: ScaleTransition(scale: scale, child: child),
            );
          },
        );
}

// ---------------------------------------------------------------------------
// Full-screen video player — always with sound, resumes from cache position
// ---------------------------------------------------------------------------

class FullScreenVideoPlayer extends StatefulWidget {
  final String url;

  const FullScreenVideoPlayer({super.key, required this.url});

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isDownloading = false;
  double _dragOffset = 0;
  late final AnimationController _controlsAnim;

  @override
  void initState() {
    super.initState();

    _controlsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initVideo();
  }

  void _initVideo() {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (!mounted) return;

      // Always resume from saved position
      final saved = VideoPositionCache.instance.get(widget.url);
      if (saved > Duration.zero) _controller.seekTo(saved);

      _controller.setVolume(1);
      _controller.setLooping(true);
      _controller.play();
      _controller.addListener(_onUpdate);

      setState(() => _isInitialized = true);
      _scheduleHide();
    });
  }

  void _onUpdate() {
    if (!mounted) return;
    // Continuously persist position so any dismiss path saves it
    if (_controller.value.isInitialized) {
      VideoPositionCache.instance.save(
        widget.url,
        _controller.value.position,
      );
    }
    setState(() {});
  }

  // ── controls ───────────────────────────────────────────────────────────────

  void _scheduleHide() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showControls && _controller.value.isPlaying) {
        setState(() => _showControls = false);
        _controlsAnim.reverse();
      }
    });
  }

  void _bringUpControls() {
    if (!_showControls) {
      setState(() => _showControls = true);
      _controlsAnim.forward();
    }
    _scheduleHide();
  }

  // ── drag to dismiss ─────────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) =>
      setState(() => _dragOffset += d.primaryDelta ?? 0);

  void _onDragEnd(DragEndDetails d) {
    final fast = d.primaryVelocity != null && d.primaryVelocity!.abs() > 500;
    if (_dragOffset.abs() > 90 || fast) {
      _dismiss();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  void _dismiss() {
    // Final position save before pop
    if (_controller.value.isInitialized) {
      VideoPositionCache.instance.save(
        widget.url,
        _controller.value.position,
      );
    }
    Navigator.of(context, rootNavigator: true).pop();
  }

  // ── download ───────────────────────────────────────────────────────────────

  Future<void> _downloadVideo() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final saved = await GallerySaver.saveVideo(widget.url);
      if (mounted) {
        saved == true
            ? AppSnackbar.success(context, 'Video saved to gallery')
            : AppSnackbar.error(context, 'Failed to save video');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Download error: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // ── lifecycle ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _controlsAnim.dispose();
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bgAlpha = 1.0 - (_dragOffset.abs() / 350).clamp(0.0, 1.0);
    final isPlaying = _isInitialized && _controller.value.isPlaying;
    final position =
        _isInitialized ? _controller.value.position : Duration.zero;
    final duration =
        _isInitialized ? _controller.value.duration : Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds
        .toDouble()
        .clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgAlpha),
      body: GestureDetector(
        onTap: _bringUpControls,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            // ── video ─────────────────────────────────────────────────────────
            Positioned.fill(child: const ColoredBox(color: Colors.black)),

            if (_isInitialized)
              Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // ── controls ──────────────────────────────────────────────────────
            if (_isInitialized)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 24,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: 0.75),
                            border: Border.all(
                              color: colors.border.withValues(alpha: 0.15),
                            ),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Row(
                            children: [
                              // Close
                              IconActionButton(
                                icon: CarbonIcons.close,
                                onPressed: _dismiss,
                                size: ButtonSize.small,
                                isCircular: true,
                              ),
                              const SizedBox(width: 4),

                              // Play / pause
                              IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  isPlaying
                                      ? CarbonIcons.pause
                                      : CarbonIcons.play,
                                  color: colors.textPrimary,
                                  size: 22,
                                ),
                                onPressed: () {
                                  isPlaying
                                      ? _controller.pause()
                                      : _controller.play();
                                  _bringUpControls();
                                },
                              ),

                              // Elapsed
                              Text(
                                _fmt(position),
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 12,
                                ),
                              ),

                              // Scrubber
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: colors.accent,
                                      inactiveTrackColor: colors.textSecondary
                                          .withValues(alpha: 0.3),
                                      thumbColor: colors.textPrimary,
                                      thumbShape:
                                          const RoundSliderThumbShape(
                                              enabledThumbRadius: 6),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 12),
                                      trackHeight: 3,
                                    ),
                                    child: Slider(
                                      value: posMs,
                                      max: maxMs > 0 ? maxMs : 1.0,
                                      onChanged: (v) {
                                        _controller.seekTo(
                                          Duration(milliseconds: v.toInt()),
                                        );
                                        _bringUpControls();
                                      },
                                    ),
                                  ),
                                ),
                              ),

                              // Duration
                              Text(
                                _fmt(duration),
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),

                              // Download
                              _isDownloading
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.textPrimary,
                                      ),
                                    )
                                  : IconActionButton(
                                      icon: CarbonIcons.download,
                                      onPressed: _downloadVideo,
                                      size: ButtonSize.small,
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
