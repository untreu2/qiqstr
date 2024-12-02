import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
import 'profile_page.dart';

class NoteDetailPage extends StatefulWidget {
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

class _NoteDetailPageState extends State<NoteDetailPage> {
  List<ReactionModel> reactions = [];
  List<ReplyModel> replies = [];
  Map<String, List<ReplyModel>> repliesMap = {};
  bool isLoading = true;
  late DataService _dataService;

  @override
  void initState() {
    super.initState();
    _initializeDetail();
  }

  Future<void> _initializeDetail() async {
    try {
      _dataService = DataService(
        npub: widget.note.author,
        dataType: DataType.Profile,
        onReactionsUpdated: _handleReactionsUpdated,
        onRepliesUpdated: _handleRepliesUpdated,
      );
      await _dataService.initialize();
      await _dataService.initializeConnections();
      await _fetchReactionsAndReplies();
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error initializing note detail: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchReactionsAndReplies() async {
    await _dataService.fetchReactionsForNotes([widget.note.id]);
    await _dataService.fetchRepliesForNotes([widget.note.id]);
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

  void _copyNoteId(BuildContext context) {
    final formattedNoteId = Nip19.encodeNote(widget.note.id);
    Clipboard.setData(ClipboardData(text: formattedNoteId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Note ID copied.")),
    );
  }

  Map<String, List<ReplyModel>> _organizeReplies(List<ReplyModel> replies) {
    Map<String, List<ReplyModel>> replyTree = {};
    for (var reply in replies) {
      if (reply.parentId.isNotEmpty) {
        replyTree.putIfAbsent(reply.parentId, () => []).add(reply);
      }
    }
    return replyTree;
  }

  Map<String, dynamic> _parseContent(String content) {
    final RegExp mediaRegExp = RegExp(
        r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))',
        caseSensitive: false);
    final Iterable<RegExpMatch> matches = mediaRegExp.allMatches(content);

    final List<String> mediaUrls = matches.map((m) => m.group(0)!).toList();

    final String text = content.replaceAll(mediaRegExp, '').trim();

    return {
      'text': text,
      'mediaUrls': mediaUrls,
    };
  }

  List<Widget> _buildParsedContent(String content) {
    final parsedContent = _parseContent(content);
    List<Widget> widgets = [];

    if (parsedContent['text'] != null && (parsedContent['text'] as String).isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Text(
          parsedContent['text'],
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ));
      widgets.add(const SizedBox(height: 8));
    }

    if (parsedContent['mediaUrls'] != null && (parsedContent['mediaUrls'] as List).isNotEmpty) {
      if (parsedContent['text'] != null && (parsedContent['text'] as String).isNotEmpty) {
        widgets.add(const SizedBox(height: 16.0));
      }
      widgets.addAll(_buildMediaPreviews(parsedContent['mediaUrls'] as List<String>));
      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }

  List<Widget> _buildMediaPreviews(List<String> mediaUrls) {
    return mediaUrls.map((url) {
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
    }).toList();
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    _organizeReplies(replies);
    final reactionCount = reactions.length;
    final replyCount = replies.length;

    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProfilePage(npub: widget.note.author),
                                ),
                              );
                            },
                            child: widget.note.authorProfileImage.isNotEmpty
                                ? CircleAvatar(
                                    backgroundImage:
                                        NetworkImage(widget.note.authorProfileImage),
                                    radius: 24,
                                  )
                                : const CircleAvatar(
                                    child: Icon(Icons.person, size: 24),
                                    radius: 24,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProfilePage(npub: widget.note.author),
                                  ),
                                );
                              },
                              child: Text(
                                widget.note.authorName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () => _copyNoteId(context),
                          ),
                        ],
                      ),
                    ),
                    ..._buildParsedContent(widget.note.content),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          Text(
                            _formatTimestamp(widget.note.timestamp),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'REACTIONS: $reactionCount',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'REPLIES: $replyCount',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (reactions.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'REACTIONS:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Wrap(
                          spacing: 10,
                          children: reactions.map((reaction) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            ProfilePage(npub: reaction.author),
                                      ),
                                    );
                                  },
                                  child: CircleAvatar(
                                    backgroundImage: reaction.authorProfileImage.isNotEmpty
                                        ? NetworkImage(reaction.authorProfileImage)
                                        : null,
                                    child: reaction.authorProfileImage.isEmpty
                                        ? const Icon(Icons.person, size: 16)
                                        : null,
                                    radius: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            ProfilePage(npub: reaction.author),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    reaction.authorName,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  reaction.content.isNotEmpty ? reaction.content : '+',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'REPLIES:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    replies.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text(
                              'No replies yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: replies.length,
                            itemBuilder: (context, index) {
                              final reply = replies[index];
                              return Padding(
                                padding: EdgeInsets.only(
                                  left: 16.0 * _getReplyDepth(reply),
                                  top: 8.0,
                                  bottom: 8.0,
                                ),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => NoteDetailPage(
                                          note: NoteModel(
                                            id: reply.id,
                                            content: reply.content,
                                            author: reply.author,
                                            authorName: reply.authorName,
                                            authorProfileImage: reply.authorProfileImage,
                                            timestamp: reply.timestamp,
                                          ),
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
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                        child: Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        ProfilePage(npub: reply.author),
                                                  ),
                                                );
                                              },
                                              child: reply.authorProfileImage.isNotEmpty
                                                  ? CircleAvatar(
                                                      backgroundImage:
                                                          NetworkImage(reply.authorProfileImage),
                                                      radius: 16,
                                                    )
                                                  : const CircleAvatar(
                                                      child: Icon(Icons.person, size: 16),
                                                      radius: 16,
                                                    ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        ProfilePage(npub: reply.author),
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                reply.authorName,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatTimestamp(reply.timestamp),
                                              style: const TextStyle(
                                                  fontSize: 12, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      ..._buildReplyContent(reply.content),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
      ),
    );
  }

  int _getReplyDepth(ReplyModel reply) {
    return 0;
  }

  List<Widget> _buildReplyContent(String content) {
    final parsedContent = _parseContent(content);
    List<Widget> widgets = [];

    if (parsedContent['text'] != null &&
        (parsedContent['text'] as String).isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Text(
          parsedContent['text'],
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ));
      widgets.add(const SizedBox(height: 8));
    }

    if (parsedContent['mediaUrls'] != null &&
        (parsedContent['mediaUrls'] as List).isNotEmpty) {
      if (parsedContent['text'] != null &&
          (parsedContent['text'] as String).isNotEmpty) {
        widgets.add(const SizedBox(height: 16.0));
      }
      widgets.addAll(_buildMediaPreviews(parsedContent['mediaUrls'] as List<String>));
      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
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
