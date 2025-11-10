import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/colors.dart';

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

class _VPState extends State<VP> {
  void _openFullScreen() {
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openFullScreen,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
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
                Center(
                  child: Icon(
                    Icons.play_circle_filled,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
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
              Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
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
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
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
                                style: const TextStyle(color: Colors.white),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: AppColors.accent,
                                      inactiveTrackColor: Colors.white.withValues(alpha: 0.24),
                                      thumbColor: Colors.white,
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
                                style: const TextStyle(color: Colors.white),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 22),
                                onPressed: () {
                                  Navigator.pop(context);
                                },
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
