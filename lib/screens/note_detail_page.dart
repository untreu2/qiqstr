import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../screens/profile_page.dart';

class NoteDetailPage extends StatelessWidget {
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

  void _copyNoteId(BuildContext context) {
    final formattedNoteId = Nip19.encodeNote(note.id);
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

  Widget _buildReplyTree(String parentId, Map<String, List<ReplyModel>> replyTree, int depth, BuildContext context) {
    if (!replyTree.containsKey(parentId)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: replyTree[parentId]!.map((reply) {
        final reactionCount = reactionsMap[reply.id]?.length ?? 0;
        final replyCount = repliesMap[reply.id]?.length ?? 0;
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
                    ),
                    reactions: reactionsMap[reply.id] ?? [],
                    replies: repliesMap[reply.id] ?? [],
                    reactionsMap: reactionsMap,
                    repliesMap: repliesMap,
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
                const SizedBox(height: 4),
                Text(
                  'Reactions: $reactionCount Replies: $replyCount',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                _buildReplyTree(reply.id, replyTree, depth + 1, context),
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
        title: const Text('Not Details'),
      ),
      body: Padding(
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
                          builder: (context) => ProfilePage(npub: note.author),
                        ),
                      );
                    },
                    child: note.authorProfileImage.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(note.authorProfileImage),
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
                          builder: (context) => ProfilePage(npub: note.author),
                        ),
                      );
                    },
                    child: Text(
                      note.authorName,
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
                note.content,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    _formatTimestamp(note.timestamp),
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
                  : _buildReplyTree(note.id, replyTree, 0, context),
            ],
          ),
        ),
      ),
    );
  }
}
