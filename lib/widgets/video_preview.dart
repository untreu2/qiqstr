import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class VP extends StatefulWidget {
  final String url;

  const VP({super.key, required this.url});

  @override
  State<VP> createState() => _VPState();
}

class _VPState extends State<VP> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasStartedInit = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _handleVisibilityChanged(VisibilityInfo info) async {
    final isNowVisible = info.visibleFraction > 0.5;

    if (isNowVisible && !_hasStartedInit) {
      _hasStartedInit = true;

      _controller = VideoPlayerController.network(widget.url)
        ..setLooping(true)
        ..setVolume(0)
        ..initialize().then((_) {
          setState(() => _isInitialized = true);
          _controller!.play();
        });
    }

    if (_controller?.value.isInitialized ?? false) {
      if (isNowVisible) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  void _openFullScreen() {
    if (_isInitialized) {
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
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.url),
      onVisibilityChanged: _handleVisibilityChanged,
      child: GestureDetector(
        onTap: _openFullScreen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: _isInitialized && _controller != null
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                : Container(
                    color: Colors.grey.shade800,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
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

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.setVolume(1);
        _controller.play();
        _controller.addListener(_updatePosition);
      });
  }

  void _updatePosition() {
    if (!_controller.value.isInitialized) return;
    setState(() {
      _position = _controller.value.position;
    });
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
      backgroundColor: Colors.black.withOpacity(1.0 - (_dragOffset.abs() / 300).clamp(0.0, 1.0)),
      body: GestureDetector(
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: Stack(
          children: [
            if (_isInitialized)
              Positioned.fill(
                child: Transform.scale(
                  scale: 1.2,
                  child: ClipRect(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                        child: Container(
                          color: Colors.black.withOpacity(0.3),
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    ),
                  ),
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
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(25.0),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(25.0),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_controller.value.isPlaying) {
                                    _controller.pause();
                                  } else {
                                    _controller.play();
                                  }
                                });
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
                                    activeTrackColor: Colors.amber,
                                    inactiveTrackColor: Colors.white24,
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
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
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
