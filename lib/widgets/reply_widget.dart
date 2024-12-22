import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:video_player/video_player.dart';
import '../models/reply_model.dart';
import '../models/reaction_model.dart'; 
import '../screens/profile_page.dart';
import '../screens/note_detail_page.dart';

class ReplyWidget extends StatelessWidget {
  final ReplyModel reply;
  final List<ReactionModel> reactions;

  const ReplyWidget({
    Key? key,
    required this.reply,
    required this.reactions,
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

  void _navigateToProfile(BuildContext context, String authorNpub) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(npub: authorNpub),
      ),
    );
  }

  void _navigateToReplyDetail(BuildContext context, ReplyModel reply) {
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
  }

  @override
  Widget build(BuildContext context) {
    final parsedContent = _parseContent(reply.content);

    return Padding(
      padding: const EdgeInsets.only(
        left: 16.0,
        top: 8.0,
        bottom: 8.0,
      ),
      child: InkWell(
        onTap: () => _navigateToReplyDetail(context, reply),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReplyHeader(context),
            const SizedBox(height: 4),
            if (parsedContent['text'] != null && parsedContent['text'] != '')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  parsedContent['text'],
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            if (parsedContent['mediaUrls'] != null &&
                parsedContent['mediaUrls'].isNotEmpty)
              _buildMediaPreviews(parsedContent['mediaUrls']),
            ReactionsSection(reactions: reactions),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _navigateToProfile(context, reply.author),
            child: reply.authorProfileImage.isNotEmpty
                ? CircleAvatar(
                    backgroundImage:
                        CachedNetworkImageProvider(reply.authorProfileImage),
                    radius: 16,
                  )
                : const CircleAvatar(
                    child: Icon(Icons.person, size: 16),
                    radius: 16,
                  ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: () => _navigateToProfile(context, reply.author),
              child: Text(
                reply.authorName,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _formatTimestamp(reply.timestamp),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class ReactionsSection extends StatelessWidget {
  final List<ReactionModel> reactions;

  const ReactionsSection({Key? key, required this.reactions}) : super(key: key);

  Map<String, List<ReactionModel>> _groupReactions(List<ReactionModel> reactions) {
    final grouped = <String, List<ReactionModel>>{};
    for (var reaction in reactions) {
      grouped.putIfAbsent(reaction.content, () => []).add(reaction);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final groupedReactions = _groupReactions(reactions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),

        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: groupedReactions.entries.map((entry) {
              final reactionContent = entry.key;
              final reactionList = entry.value;
              final reactionCount = reactionList.length;

              return GestureDetector(
                onTap: () => _showReactionDetails(context, reactionContent, reactionList),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        reactionContent,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$reactionCount',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _showReactionDetails(BuildContext context, String reactionContent, List<ReactionModel> reactionList) {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return ReactionDetailsModal(
          reactionContent: reactionContent,
          reactions: reactionList,
        );
      },
    );
  }
}

class ReactionDetailsModal extends StatelessWidget {
  final String reactionContent;
  final List<ReactionModel> reactions;

  const ReactionDetailsModal({
    Key? key,
    required this.reactionContent,
    required this.reactions,
  }) : super(key: key);


  void _navigateToProfile(BuildContext context, String authorNpub) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(npub: authorNpub),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Reactions: $reactionContent',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: reactions.length,
              itemBuilder: (context, index) {
                final reaction = reactions[index];
                return ListTile(
                  leading: reaction.authorProfileImage.isNotEmpty
                      ? CircleAvatar(
                          backgroundImage: CachedNetworkImageProvider(
                            reaction.authorProfileImage,
                          ),
                        )
                      : const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                  title: Text(reaction.authorName),
                  trailing: Text(
                    reaction.content.isNotEmpty ? reaction.content : '+',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToProfile(context, reaction.author);
                  },
                );
              },
            ),
          ),
        ],
      ),
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
