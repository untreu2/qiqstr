// lib/widgets/reply_widget.dart

import 'package:flutter/material.dart';
import '../models/reply_model.dart';

class ReplyWidget extends StatelessWidget {
  final ReplyModel reply;
  final Map<String, List<ReplyModel>> replyTree;
  final int depth;

  const ReplyWidget({
    Key? key,
    required this.reply,
    required this.replyTree,
    required this.depth,
  }) : super(key: key);

  // Recursively build the reply tree
  Widget _buildReplies() {
    if (!replyTree.containsKey(reply.id)) {
      return Container();
    }

    return Column(
      children: replyTree[reply.id]!.map((childReply) {
        return ReplyWidget(
          reply: childReply,
          replyTree: replyTree,
          depth: depth + 1,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Side: Lines and Dots
        Container(
          width: 20,
          child: Column(
            children: [
              // Top line (except for the first level)
              if (depth > 0)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey,
                  ),
                )
              else
                Container(),
              // Dot or circle
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
        // Right Side: Reply Content
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author Info
                Row(
                  children: [
                    reply.authorProfileImage.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(reply.authorProfileImage),
                            radius: 16,
                          )
                        : const CircleAvatar(
                            child: Icon(Icons.person, size: 16),
                            radius: 16,
                          ),
                    const SizedBox(width: 8),
                    Text(
                      reply.authorName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(reply.timestamp),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Reply Content
                Text(reply.content),
                // Recursive Replies
                _buildReplies(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    // Format the timestamp as desired, e.g., "2 hours ago"
    final Duration diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
