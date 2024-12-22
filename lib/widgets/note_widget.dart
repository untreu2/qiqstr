import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../models/note_model.dart';
import '../screens/note_detail_page.dart';
import '../screens/profile_page.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final VoidCallback? onTapAuthor;
  final VoidCallback? onTapRepost;

  const NoteWidget({
    Key? key,
    required this.note,
    this.onTapAuthor,
    this.onTapRepost,
  }) : super(key: key);

  @override
  _NoteWidgetState createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget> {
  Map<String, dynamic> _parsedContent = {};

  @override
  void initState() {
    super.initState();
    _parsedContent = _parseContent(widget.note.content);
  }

  Map<String, dynamic> _parseContent(String content) {
    final RegExp mediaRegExp = RegExp(
      r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))',
      caseSensitive: false,
    );
    final Iterable<RegExpMatch> matches = mediaRegExp.allMatches(content);

    final List<String> mediaUrls = matches.map((m) => m.group(0)!).toList();
    final String text = content.replaceAll(mediaRegExp, '').trim();

    return {
      'text': text,
      'mediaUrls': mediaUrls,
    };
  }

  Widget _buildMediaPreviews(List<String> mediaUrls) {
    return Column(
      children: mediaUrls.map((url) {
        if (url.toLowerCase().endsWith('.mp4')) {
          return _VideoPreview(url: url);
        } else {
          return CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error),
            fit: BoxFit.cover,
            width: double.infinity,
          );
        }
      }).toList(),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}"
        "-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:"
        "${timestamp.minute.toString().padLeft(2, '0')}:"
        "${timestamp.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.note;
    final parsedContent = _parsedContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.isRepost)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 8.0),
            child: GestureDetector(
              onTap: widget.onTapRepost ??
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ProfilePage(npub: item.repostedBy!),
                      ),
                    );
                  },
              child: Row(
                children: [
                  const Icon(
                    Icons.repeat,
                    size: 16.0,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4.0),
                  Text(
                    'Reposted by ${item.repostedByName}',
                    style: const TextStyle(
                      fontSize: 12.0,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        GestureDetector(
          onTap: widget.onTapAuthor ??
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfilePage(npub: item.author),
                  ),
                );
              },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              children: [
                item.authorProfileImage.isNotEmpty
                    ? CircleAvatar(
                        radius: 18,
                        backgroundImage:
                            CachedNetworkImageProvider(item.authorProfileImage),
                      )
                    : const CircleAvatar(
                        radius: 12,
                        child: Icon(Icons.person, size: 16),
                      ),
                const SizedBox(width: 12),
                Text(
                  item.authorName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoteDetailPage(
                  note: item,
                  reactions: [],
                  replies: [],
                  reactionsMap: {},
                  repliesMap: {},
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parsedContent['text'] != null &&
                  parsedContent['text'] != '')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(parsedContent['text']),
                ),
              if (parsedContent['text'] != null &&
                      parsedContent['text'] != '' &&
                      parsedContent['mediaUrls'] != null &&
                      parsedContent['mediaUrls'].isNotEmpty
                  ? true
                  : false)
                const SizedBox(height: 16.0),
              if (parsedContent['mediaUrls'] != null &&
                  parsedContent['mediaUrls'].isNotEmpty)
                _buildMediaPreviews(parsedContent['mediaUrls']),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  _formatTimestamp(item.timestamp),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final String url;
  const _VideoPreview({Key? key, required this.url}) : super(key: key);

  @override
  __VideoPreviewState createState() => __VideoPreviewState();
}

class __VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          if (!_controller.value.isPlaying)
            const Icon(
              Icons.play_circle_outline,
              size: 64.0,
              color: Colors.white70,
            ),
        ],
      ),
    );
  }
}
