import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VP extends StatefulWidget {
  final String url;

  const VP({super.key, required this.url});

  @override
  _VPState createState() => _VPState();
}

class _VPState extends State<VP> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  bool _isControlsVisible = true;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  static const double borderRadius = 0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.network(widget.url);
    try {
      await _controller.initialize();
      setState(() {
        _totalDuration = _controller.value.duration;
      });
      _controller.addListener(() {
        setState(() {
          _currentPosition = _controller.value.position;
          _isPlaying = _controller.value.isPlaying;
          if (_isPlaying) {
            _isControlsVisible = false;
          }
        });
      });
    } catch (e) {
      print("Error initializing video: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isControlsVisible = true;
      } else {
        _controller.play();
        _isControlsVisible = false;
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() {
      _isControlsVisible = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (_controller.value.isPlaying) {
        setState(() {
          _isControlsVisible = false;
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: GestureDetector(
                onTap: () {
                  _togglePlayPause();
                  _toggleControlsVisibility();
                },
                child: Stack(
                  children: [
                    VideoPlayer(_controller),
                    AnimatedOpacity(
                      opacity: _isControlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: _buildControlsOverlay(),
                    ),
                  ],
                ),
              ),
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }

  Widget _buildControlsOverlay() {
    return Container(
      color: Colors.black38,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: _togglePlayPause,
              ),
              Expanded(
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.black26,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_currentPosition),
                style: const TextStyle(color: Colors.white),
              ),
              const Text(
                ' / ',
                style: TextStyle(color: Colors.white),
              ),
              Text(
                _formatDuration(_totalDuration),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
