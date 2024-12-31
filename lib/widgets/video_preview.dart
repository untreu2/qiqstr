import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VP extends StatefulWidget {
  final String url;

  const VP({Key? key, required this.url}) : super(key: key);

  @override
  _VPState createState() => _VPState();
}

class _VPState extends State<VP> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  bool _isControlsVisible = true;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

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
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() {
      _isControlsVisible = !_isControlsVisible;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: GestureDetector(
              onTap: _toggleControlsVisibility,
              child: Stack(
                children: [
                  VideoPlayer(_controller),
                  if (_isControlsVisible) _buildControlsOverlay(),
                ],
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
          VideoProgressIndicator(
            _controller,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            colors: VideoProgressColors(
              playedColor: Colors.red,
              bufferedColor: Colors.grey,
              backgroundColor: Colors.black26,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: _togglePlayPause,
              ),
              Text(
                _formatDuration(_currentPosition),
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                _formatDuration(_totalDuration),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
