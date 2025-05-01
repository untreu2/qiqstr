import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VP extends StatelessWidget {
  final String url;

  const VP({super.key, required this.url});

  void _openVideoDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: VideoDialogPlayer(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openVideoDialog(context),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(12),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
          ),
        ],
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

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _isInitialized ? _controller.value.aspectRatio : 16 / 9,
      child: Stack(
        children: [
          _isInitialized
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: VideoPlayer(_controller),
                )
              : const Center(child: CircularProgressIndicator()),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
