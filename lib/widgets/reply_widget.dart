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
        Container(
          width: 20,
          child: Column(
            children: [
              if (depth > 0)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey,
                  ),
                )
              else
                Container(),
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
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  ],
                ),
                const SizedBox(height: 4),
                Text(reply.content),
                _buildReplies(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
