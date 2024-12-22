import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../providers/note_detail_service_provider.dart';
import '../models/note_model.dart'; 
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
import '../screens/profile_page.dart';
import '../widgets/reply_widget.dart';

class NoteDetailPage extends ConsumerStatefulWidget {
  final NoteModel note;
  final List<ReactionModel> reactions;
  final List<ReplyModel> replies;
  final Map<String, List<ReactionModel>> reactionsMap;
  final Map<String, List<ReplyModel>> repliesMap;

  const NoteDetailPage({
    Key? key,
    required this.note,
    required this.reactions,
    required this.replies,
    required this.reactionsMap,
    required this.repliesMap,
  }) : super(key: key);

  @override
  _NoteDetailPageState createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends ConsumerState<NoteDetailPage> {
  List<ReactionModel> reactions = [];
  List<ReplyModel> replies = [];
  Map<String, List<ReplyModel>> repliesMap = {};

  bool _hasFetched = false;

  @override
  Widget build(BuildContext context) {
    final dataServiceAsync = ref.watch(noteDetailServiceProvider(widget.note.author));

    return dataServiceAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
      data: (dataService) {
        if (!_hasFetched) {
          _setupCallbacks(dataService);
          _fetchReactionsAndReplies(dataService);
          _hasFetched = true;
        }

        final replyCount = replies.length;

        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NoteWidget(
                    key: ValueKey(widget.note.id),
                    note: widget.note,
                    onTapAuthor: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfilePage(npub: widget.note.author),
                        ),
                      );
                    },
                    onTapRepost: () {
                      if (widget.note.repostedBy != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(npub: widget.note.repostedBy!),
                          ),
                        );
                      }
                    },
                    isDetailPage: true, 
                    showTimestamp: true,
                  ),

                  _buildCounts(replyCount),

                  const SizedBox(height: 16),

                  ReactionsSection(reactions: reactions),

                  _buildRepliesSection(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _setupCallbacks(DataService dataService) {
    dataService.onReactionsUpdated = _handleReactionsUpdated;
    dataService.onRepliesUpdated = _handleRepliesUpdated;
  }

  Future<void> _fetchReactionsAndReplies(DataService dataService) async {
    await dataService.fetchReactionsForNotes([widget.note.id]);

    await dataService.fetchRepliesForNotes([widget.note.id]);
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> updatedReactions) {
    if (noteId == widget.note.id) {
      setState(() {
        reactions = updatedReactions;
      });
    }
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> updatedReplies) {
    if (noteId == widget.note.id) {
      setState(() {
        replies = updatedReplies;
        repliesMap = _organizeReplies(replies);
      });
    }
  }

  Map<String, List<ReplyModel>> _organizeReplies(List<ReplyModel> replies) {
    final replyTree = <String, List<ReplyModel>>{};
    for (var reply in replies) {
      if (reply.parentId.isNotEmpty) {
        replyTree.putIfAbsent(reply.parentId, () => []).add(reply);
      }
    }
    return replyTree;
  }

Widget _buildCounts(int replyCount) {
  final reactionCount = reactions.length;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16.0),
    child: Row(
      children: [
        Flexible(
          child: Text(
            'REACTIONS: $reactionCount',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            'REPLIES: $replyCount',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    ),
  );
}


Widget _buildRepliesSection() {
  return ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    itemCount: replies.length,
    itemBuilder: (context, index) {
      final reply = replies[index];
      return ReplyWidget(
        key: ValueKey(reply.id),
        reply: reply,
        reactions: [],
      );
    },
  );
}

}

class NoteWidget extends StatelessWidget {
  final NoteModel note;
  final VoidCallback? onTapAuthor;
  final VoidCallback? onTapRepost;
  final bool isDetailPage;
  final bool showTimestamp;

  const NoteWidget({
    Key? key,
    required this.note,
    this.onTapAuthor,
    this.onTapRepost,
    this.isDetailPage = false,
    this.showTimestamp = true, 
  }) : super(key: key);

  Map<String, dynamic> _parseContent(String content) {
    final mediaRegExp = RegExp(
      r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))',
      caseSensitive: false,
    );
    final matches = mediaRegExp.allMatches(content);
    final mediaUrls = matches.map((m) => m.group(0)!).toList();
    final text = content.replaceAll(mediaRegExp, '').trim();

    return {'text': text, 'mediaUrls': mediaUrls};
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
    final parsedContent = _parseContent(note.content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.repostedBy != null)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 8.0),
            child: GestureDetector(
              onTap: onTapRepost ??
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(npub: note.repostedBy!),
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
                    'Reposted by ${note.repostedByName}',
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
          onTap: onTapAuthor ??
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfilePage(npub: note.author),
                  ),
                );
              },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              children: [
                note.authorProfileImage.isNotEmpty
                    ? CircleAvatar(
                        radius: 18,
                        backgroundImage:
                            CachedNetworkImageProvider(note.authorProfileImage),
                      )
                    : const CircleAvatar(
                        radius: 12,
                        child: Icon(Icons.person, size: 16),
                      ),
                const SizedBox(width: 12),
                Text(
                  note.authorName,
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
            if (isDetailPage) {
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoteDetailPage(
                  note: note,
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
              if (showTimestamp)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    _formatTimestamp(note.timestamp),
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
