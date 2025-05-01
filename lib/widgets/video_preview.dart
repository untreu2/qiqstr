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
  late VideoPlayerController _controller;
  bool _isVisible = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        if (_isVisible) _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleVisibilityChanged(VisibilityInfo info) {
    final isVisibleNow = info.visibleFraction > 0.5;
    if (isVisibleNow != _isVisible) {
      setState(() => _isVisible = isVisibleNow);
      if (_isVisible && _controller.value.isInitialized) {
        _controller.play();
      } else {
        _controller.pause();
      }
    }
  }

  void _openFullScreen() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(8),
        child: VideoDialogPlayer(url: widget.url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.url),
      onVisibilityChanged: _handleVisibilityChanged,
      child: GestureDetector(
        onTap: _openFullScreen,
        child: _isInitialized
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: _controller.value.size.width,
                      height: _controller.value.size.height,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                ),
              )
            : const AspectRatio(
                aspectRatio: 1,
                child: Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

class VideoDialogPlayer extends StatefulWidget {
  final String url;

  const VideoDialogPlayer({super.key, required this.url});

  @override
  State<VideoDialogPlayer> createState() => _VideoDialogPlayerState();
}

class _VideoDialogPlayerState extends State<VideoDialogPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  Duration _position = Duration.zero;

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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return _isInitialized
        ? Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.black54,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
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
                        child: VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          colors: VideoProgressColors(
                            playedColor: Colors.amber,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(_controller.value.duration),
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_exit,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        : const Center(child: CircularProgressIndicator());
  }
}
