import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
import 'profile_page.dart';

class NoteDetailPage extends StatefulWidget {
  final NoteModel note;

  const NoteDetailPage({
    Key? key,
    required this.note, required List<ReactionModel> reactions, required List<ReplyModel> replies, required Map<String, List<ReactionModel>> reactionsMap, required Map<String, List<ReplyModel>> repliesMap,
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
      const SnackBar(content: Text("Note ID copied to clipboard.")),
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

  Widget _buildReplyTree(String parentId, Map<String, List<ReplyModel>> replyTree, int depth) {
    if (!replyTree.containsKey(parentId)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: replyTree[parentId]!.map((reply) {
        return Padding(
          padding: EdgeInsets.only(left: depth * 16.0, top: 8.0, bottom: 8.0),
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
                    ), reactions: [], replies: [], reactionsMap: {}, repliesMap: {},
                  ),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(npub: reply.author),
                          ),
                        );
                      },
                      child: reply.authorProfileImage.isNotEmpty
                          ? CircleAvatar(
                              backgroundImage: NetworkImage(reply.authorProfileImage),
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
                            builder: (context) => ProfilePage(npub: reply.author),
                          ),
                        );
                      },
                      child: Text(
                        reply.authorName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(reply.timestamp),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(reply.content),
                const SizedBox(height: 8),
                _buildReplyTree(reply.id, replyTree, depth + 1),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
           "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final replyTree = _organizeReplies(replies);
    final reactionCount = reactions.length;
    final replyCount = replies.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Note Details'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                                  backgroundImage: NetworkImage(widget.note.authorProfileImage),
                                  radius: 24,
                                )
                              : const CircleAvatar(
                                  child: Icon(Icons.person, size: 24),
                                  radius: 24,
                                ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
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
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () => _copyNoteId(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.note.content,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          _formatTimestamp(widget.note.timestamp),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Reactions: $reactionCount',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Replies: $replyCount',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (reactions.isNotEmpty) ...[
                      const Text(
                        'Reactions:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
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
                                      builder: (context) => ProfilePage(npub: reaction.author),
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
                                      builder: (context) => ProfilePage(npub: reaction.author),
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
                      const SizedBox(height: 16),
                    ],
                    const Text(
                      'Replies:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    replies.isEmpty
                        ? const Text(
                            'No replies yet.',
                            style: TextStyle(color: Colors.grey),
                          )
                        : _buildReplyTree(widget.note.id, replyTree, 0),
                  ],
                ),
              ),
            ),
    );
  }
}
