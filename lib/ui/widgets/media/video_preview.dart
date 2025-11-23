import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../common/snackbar_widget.dart';
import '../common/common_buttons.dart';

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
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isInitialized = true;
                _duration = _controller!.value.duration;
              });
              _controller!.addListener(_updatePosition);
            }
          });
        }
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_updatePosition);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isPlaying = false);
          }
        });
      }
    }
  }

  @override
  void deactivate() {
    if (_controller != null && _controller!.value.isInitialized && _controller!.value.isPlaying) {
      _controller!.pause();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isPlaying = false);
        }
      });
    }
    super.deactivate();
  }

  void _updatePosition() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;
    final newPosition = _controller!.value.position;
    final newDuration = _controller!.value.duration;
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _position = newPosition;
            _duration = newDuration;
            _isPlaying = _controller!.value.isPlaying;
          });
        }
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
    });
  }

  void _openFullScreen() {
    if (_controller != null && _controller!.value.isInitialized && _controller!.value.isPlaying) {
      _controller!.pause();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isPlaying = false);
        }
      });
    }
    
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => FullScreenVideoPlayer(url: widget.url),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _downloadVideo() async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      final saved = await GallerySaver.saveVideo(widget.url);

      if (mounted) {
        if (saved == true) {
          AppSnackbar.success(context, 'Video saved to gallery');
        } else {
          AppSnackbar.error(context, 'Failed to save video to gallery');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Download error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _isInitialized && _controller != null && _controller!.value.aspectRatio > 0
                ? AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: GestureDetector(
                          onTap: _isDownloading ? null : _downloadVideo,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _isDownloading ? CarbonIcons.download : CarbonIcons.download,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _openFullScreen,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              CarbonIcons.maximize,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () {},
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.7),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  _togglePlayPause();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    _isPlaying ? CarbonIcons.pause : CarbonIcons.play,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final colors = context.colors;
                                    return SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: colors.accent,
                                        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                                        thumbColor: Colors.white,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                                        trackHeight: 2,
                                      ),
                                      child: Slider(
                                        value: _position.inMilliseconds.toDouble().clamp(0.0, _duration.inMilliseconds.toDouble()),
                                        max: _duration.inMilliseconds.toDouble(),
                                        onChanged: (value) {
                                          final position = Duration(milliseconds: value.toInt());
                                          _controller?.seekTo(position);
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8, right: 4),
                                child: Text(
                                  _formatDuration(_duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                : AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      children: [
                        if (widget.authorProfileImageUrl != null && widget.authorProfileImageUrl!.isNotEmpty)
                          Positioned.fill(
                            child: CachedNetworkImage(
                              imageUrl: widget.authorProfileImageUrl!,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              maxHeightDiskCache: 400,
                              maxWidthDiskCache: 400,
                              memCacheWidth: 400,
                              errorWidget: (context, url, error) {
                                return Container(color: Colors.grey.shade800);
                              },
                              placeholder: (context, url) {
                                return Container(color: Colors.grey.shade800);
                              },
                            ),
                          )
                        else
                          Container(color: Colors.grey.shade800),
                        const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class FullScreenVideoPlayer extends StatefulWidget {
  final String url;

  const FullScreenVideoPlayer({super.key, required this.url});

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  Duration _position = Duration.zero;
  double _dragOffset = 0;
  bool _showControls = true;
  DateTime? _lastShowTime;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.setVolume(1);
        _controller.play();
        _controller.addListener(_updatePosition);
        _startHideTimer();
      });
  }

  DateTime? _lastPositionUpdate;
  
  void _updatePosition() {
    if (!_controller.value.isInitialized) return;
    
    final now = DateTime.now();
    if (_lastPositionUpdate != null && 
        now.difference(_lastPositionUpdate!).inMilliseconds < 500) {
      return;
    }
    
    _lastPositionUpdate = now;
    final newPosition = _controller.value.position;
    
    if ((_position - newPosition).inSeconds.abs() >= 1) {
      if (mounted) {
        setState(() {
          _position = newPosition;
        });
      }
    }
  }

  void _startHideTimer() {
    final showTime = DateTime.now();
    _lastShowTime = showTime;
    
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _lastShowTime == showTime && _showControls) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _showControlsAndResetTimer() {
    setState(() {
      _showControls = true;
    });
    _startHideTimer();
  }

  @override
  void dispose() {
    _controller.removeListener(_updatePosition);
    _controller.dispose();
    super.dispose();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 100) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _downloadVideo() async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      final saved = await GallerySaver.saveVideo(widget.url);

      if (mounted) {
        if (saved == true) {
          AppSnackbar.success(context, 'Video saved to gallery');
        } else {
          AppSnackbar.error(context, 'Failed to save video to gallery');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Download error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1.0 - (_dragOffset.abs() / 300).clamp(0.0, 1.0)),
      body: GestureDetector(
        onTap: _showControlsAndResetTimer,
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.black,
              ),
            ),
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
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_isInitialized)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Builder(
                    builder: (context) {
                      final colors = context.colors;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(40),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: colors.surface.withValues(alpha: 0.8),
                                border: Border.all(
                                  color: colors.border.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _controller.value.isPlaying ? CarbonIcons.pause : CarbonIcons.play,
                                      color: colors.textPrimary,
                                      size: 22,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (_controller.value.isPlaying) {
                                          _controller.pause();
                                        } else {
                                          _controller.play();
                                        }
                                      });
                                      _showControlsAndResetTimer();
                                    },
                                  ),
                                  Text(
                                    _formatDuration(_position),
                                    style: TextStyle(color: colors.textPrimary),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: colors.accent,
                                          inactiveTrackColor: colors.textSecondary.withValues(alpha: 0.3),
                                          thumbColor: colors.textPrimary,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                          trackHeight: 3,
                                        ),
                                        child: Slider(
                                          value: _controller.value.position.inMilliseconds.toDouble(),
                                          max: _controller.value.duration.inMilliseconds.toDouble(),
                                          onChanged: (value) {
                                            final position = Duration(milliseconds: value.toInt());
                                            _controller.seekTo(position);
                                            _showControlsAndResetTimer();
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(_controller.value.duration),
                                    style: TextStyle(color: colors.textPrimary),
                                  ),
                                  const SizedBox(width: 8),
                                  IconActionButton(
                                    icon: _isDownloading ? CarbonIcons.download : CarbonIcons.download,
                                    iconColor: colors.textPrimary,
                                    onPressed: _isDownloading ? null : _downloadVideo,
                                    size: ButtonSize.small,
                                  ),
                                  IconActionButton(
                                    icon: CarbonIcons.close,
                                    iconColor: colors.textPrimary,
                                    onPressed: () => Navigator.pop(context),
                                    size: ButtonSize.small,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
