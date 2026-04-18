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
// Inline video player (feed / note view)
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

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerUpdate);
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
    }
  }

  // ── controller ─────────────────────────────────────────────────────────────

  void _initController() {
    if (_isLoading || _isInitialized) return;
    setState(() => _isLoading = true);

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = ctrl;

    ctrl.initialize().then((_) {
      if (!mounted || _controller != ctrl) return;
      ctrl.addListener(_onControllerUpdate);
      ctrl.play();
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  // ── actions ────────────────────────────────────────────────────────────────

  void _togglePlayPause() {
    if (!_isInitialized) {
      _initController();
      return;
    }
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
  }

  void _openFullScreen() {
    final ctrl = _controller;
    final position = ctrl?.value.position ?? Duration.zero;
    ctrl?.pause();

    Navigator.of(context, rootNavigator: true)
        .push(
          _FullScreenRoute(
            child: FullScreenVideoPlayer(
              url: widget.url,
              existingController:
                  (_isInitialized && ctrl != null) ? ctrl : null,
              startPosition: position,
            ),
          ),
        )
        .then((_) {
      // Resume inline player if it was playing before fullscreen
      if (mounted && _isInitialized) {
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
    final isPlaying = ready && ctrl.value.isPlaying;
    final duration = ready ? ctrl.value.duration : Duration.zero;
    final position = ready ? ctrl.value.position : Duration.zero;
    final remaining = duration - position;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: ready
              ? Stack(
                  children: [
                    // Video
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _togglePlayPause,
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
                    ),

                    // Fullscreen button
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _openFullScreen,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CarbonIcons.maximize,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),

                    // Bottom bar
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
                              Colors.black.withValues(alpha: 0.65),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _togglePlayPause,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  isPlaying
                                      ? CarbonIcons.pause
                                      : CarbonIcons.play,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 8, right: 4),
                              child: Text(
                                _fmt(remaining),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Pause overlay — flash icon on tap
                    if (!isPlaying)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: AnimatedOpacity(
                              opacity: isPlaying ? 0 : 0.8,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CarbonIcons.play_filled,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              : GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    color: Colors.grey.shade900,
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              CarbonIcons.play_filled,
                              color: Colors.white,
                              size: 52,
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
// Custom route — hero-like expand / collapse transition
// ---------------------------------------------------------------------------

class _FullScreenRoute extends PageRouteBuilder {
  _FullScreenRoute({required Widget child})
      : super(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => child,
          transitionsBuilder: (_, animation, __, child) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            );
            final scale = Tween<double>(begin: 0.94, end: 1.0).animate(
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
// Full-screen video player
// ---------------------------------------------------------------------------

class FullScreenVideoPlayer extends StatefulWidget {
  final String url;
  final VideoPlayerController? existingController;
  final Duration startPosition;

  const FullScreenVideoPlayer({
    super.key,
    required this.url,
    this.existingController,
    this.startPosition = Duration.zero,
  });

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _ownsController = false;
  bool _showControls = true;
  bool _isDownloading = false;
  double _dragOffset = 0;

  late final AnimationController _controlsAnim;

  @override
  void initState() {
    super.initState();

    _controlsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
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
    final existing = widget.existingController;
    if (existing != null && existing.value.isInitialized) {
      _controller = existing;
      _ownsController = false;
      _isInitialized = true;
      _controller.setVolume(1);
      _controller.play();
      _controller.addListener(_onControllerUpdate);
      _scheduleHide();
    } else {
      _ownsController = true;
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _controller.initialize().then((_) {
        if (!mounted) return;
        if (widget.startPosition > Duration.zero) {
          _controller.seekTo(widget.startPosition);
        }
        _controller.setVolume(1);
        _controller.play();
        _controller.addListener(_onControllerUpdate);
        setState(() => _isInitialized = true);
        _scheduleHide();
      });
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  // ── controls visibility ────────────────────────────────────────────────────

  void _scheduleHide() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showControls && _controller.value.isPlaying) {
        _hideControls();
      }
    });
  }

  void _showControlsTemporarily() {
    if (!_showControls) {
      setState(() => _showControls = true);
      _controlsAnim.forward();
    }
    _scheduleHide();
  }

  void _hideControls() {
    if (!mounted) return;
    setState(() => _showControls = false);
    _controlsAnim.reverse();
  }

  // ── drag to dismiss ────────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) =>
      setState(() => _dragOffset += d.primaryDelta ?? 0);

  void _onDragEnd(DragEndDetails d) {
    if (_dragOffset.abs() > 90 ||
        (d.primaryVelocity != null && d.primaryVelocity!.abs() > 600)) {
      _dismiss();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  void _dismiss() => Navigator.of(context, rootNavigator: true).pop();

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

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _controlsAnim.dispose();
    _controller.removeListener(_onControllerUpdate);
    if (_ownsController) _controller.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── build ──────────────────────────────────────────────────────────────────

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
        onTap: _showControlsTemporarily,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            // ── video ────────────────────────────────────────────────────────
            Positioned.fill(child: Container(color: Colors.black)),

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

            // ── controls overlay ─────────────────────────────────────────────
            if (_isInitialized)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 24,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
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

                              // Play/pause
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
                                  _showControlsTemporarily();
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
                                        _showControlsTemporarily();
                                      },
                                    ),
                                  ),
                                ),
                              ),

                              // Remaining
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
