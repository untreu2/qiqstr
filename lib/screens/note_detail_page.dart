import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
import 'profile_page.dart';
import '../widgets/reply_widget.dart';
import '../widgets/video_preview.dart';
import 'send_reply.dart';

class ThreeDotsLoading extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;

  const ThreeDotsLoading({
    Key? key,
    this.size = 8.0,
    this.color = Colors.grey,
    this.duration = const Duration(milliseconds: 500),
  }) : super(key: key);

  @override
  _ThreeDotsLoadingState createState() => _ThreeDotsLoadingState();
}

class _ThreeDotsLoadingState extends State<ThreeDotsLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(int index) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.size,
        height: widget.size,
        margin: const EdgeInsets.symmetric(horizontal: 2.0),
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return DelayAnimation(
          delay: Duration(milliseconds: index * 200),
          child: _buildDot(index),
        );
      }),
    );
  }
}

class DelayAnimation extends StatelessWidget {
  final Widget child;
  final Duration delay;

  const DelayAnimation({Key? key, required this.child, required this.delay})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.delayed(delay),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return child;
        } else {
          return Opacity(opacity: 0.0, child: child);
        }
      },
    );
  }
}

class ReactionsSection extends StatelessWidget {
  final List<ReactionModel> reactions;
  final bool isLoading;

  const ReactionsSection({
    Key? key,
    required this.reactions,
    required this.isLoading,
  }) : super(key: key);

  Map<String, List<ReactionModel>> _groupReactions(
      List<ReactionModel> reactions) {
    Map<String, List<ReactionModel>> grouped = {};
    for (var reaction in reactions) {
      grouped.putIfAbsent(reaction.content, () => []).add(reaction);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'REACTIONS:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Padding(
            padding:
                EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: ThreeDotsLoading(),
          )
        else if (reactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'No reactions yet.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _groupReactions(reactions).entries.map((entry) {
                final reactionContent = entry.key;
                final reactionList = entry.value;
                final reactionCount = reactionList.length;
                return GestureDetector(
                  onTap: () => _showReactionDetails(
                      context, reactionContent, reactionList),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          reactionContent,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$reactionCount',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _showReactionDetails(
      BuildContext context, String reactionContent, List<ReactionModel> reactionList) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ReactionDetailsModal(
            reactionContent: reactionContent, reactions: reactionList);
      },
    );
  }
}

class RepliesSection extends StatelessWidget {
  final List<ReplyModel> replies;
  final bool isLoading;
  final Function(String) onSendReplyReaction;
  final Function(String) onShowReplyDialog;
  final Function(String) onNavigateToProfile;

  RepliesSection({
    Key? key,
    required this.replies,
    required this.isLoading,
    required this.onSendReplyReaction,
    required this.onShowReplyDialog,
    required this.onNavigateToProfile,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'REPLIES:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Padding(
            padding:
                EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: ThreeDotsLoading(),
          )
        else if (replies.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'No replies yet.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: replies.length,
            itemBuilder: (context, index) {
              final reply = replies[index];
              return GestureDetector(
                onDoubleTap: () {
                  onSendReplyReaction(reply.id);
                },
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity! > 0) {
                    onShowReplyDialog(reply.id);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    border: _glowingReplies.contains(reply.id)
                        ? Border.all(color: Colors.white, width: 4.0)
                        : null,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: ReplyWidget(
                    reply: reply,
                    onAuthorTap: () {
                      onNavigateToProfile(reply.author);
                    },
                    onReplyTap: () {
                    },
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  final Set<String> _glowingReplies = {};
}

class NoteDetailPage extends StatefulWidget {
  final NoteModel note;

  const NoteDetailPage({
    Key? key,
    required this.note,
  }) : super(key: key);

  @override
  _NoteDetailPageState createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  List<ReactionModel> reactions = [];
  List<ReplyModel> replies = [];
  bool isReactionsLoading = true;
  bool isRepliesLoading = true; 
  late DataService _dataService;

  final Set<String> glowingNotes = {};
  final Set<String> glowingReplies = {};
  final Set<String> swipedNotes = {};

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
      _fetchReactionsAndReplies();
    } catch (e) {
      print('Error initializing NoteDetailPage: $e');
      setState(() {
        isReactionsLoading = false;
        isRepliesLoading = false;
      });
    }
  }

  Future<void> _fetchReactionsAndReplies() async {
    try {
      await _dataService.fetchReactionsForNotes([widget.note.id]);
      setState(() {
        isReactionsLoading = false;
      });
      await _dataService.fetchRepliesForNotes([widget.note.id]);
      setState(() {
        isRepliesLoading = false;
      });
    } catch (e) {
      print('Error fetching reactions and replies: $e');
      setState(() {
        isReactionsLoading = false;
        isRepliesLoading = false;
      });
    }
  }

void _handleReactionsUpdated(String noteId, List<ReactionModel> updatedReactions) {
  if (noteId == widget.note.id) {
    final newReactions = updatedReactions.where((reaction) => !reactions.contains(reaction)).toList();
    if (newReactions.isNotEmpty) {
      setState(() {
        reactions.addAll(newReactions);
      });
    }
  }
}


  void _handleRepliesUpdated(String noteId, List<ReplyModel> updatedReplies) {
    if (noteId == widget.note.id) {
      setState(() {
        replies = updatedReplies;
      });
    }
  }

  Future<void> _sendReaction(String noteId) async {
    try {
      await _dataService.sendReaction(noteId, '💜');
      setState(() {
        glowingNotes.add(noteId);
      });

      Timer(const Duration(seconds: 1), () {
        setState(() {
          glowingNotes.remove(noteId);
        });
      });
    } catch (e) {
      print('Error sending reaction: $e');
    }
  }

  Future<void> _sendReplyReaction(String replyId) async {
    try {
      await _dataService.sendReaction(replyId, '💜');
      setState(() {
        glowingReplies.add(replyId);
      });

      Timer(const Duration(seconds: 1), () {
        setState(() {
          glowingReplies.remove(replyId);
        });
      });
    } catch (e) {
      print('Error sending reply reaction: $e');
    }
  }

  Map<String, dynamic> _parseContent(String content) {
    final RegExp mediaRegExp = RegExp(
        r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))',
        caseSensitive: false);
    final Iterable<RegExpMatch> matches = mediaRegExp.allMatches(content);
    final List<String> mediaUrls = matches.map((m) => m.group(0)!).toList();
    final String text = content.replaceAll(mediaRegExp, '').trim();
    return {'text': text, 'mediaUrls': mediaUrls};
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
      widgets.addAll(_buildMediaPreviews(parsedContent['mediaUrls'] as List<String>));
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }

  List<Widget> _buildMediaPreviews(List<String> mediaUrls) {
    return mediaUrls.map((url) {
      if (url.toLowerCase().endsWith('.mp4')) {
        return VideoPreview(url: url);
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

  void _showReplyDialog(String noteId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) => SendReplyDialog(
        dataService: _dataService,
        noteId: noteId,
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";
  }

  void _navigateToProfile(String authorNpub) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(npub: authorNpub),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int reactionCount = reactions.length;
    final int replyCount = replies.length;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity! > 0) {
              _showReplyDialog(widget.note.id);
            }
          },
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                GestureDetector(
                  onDoubleTap: () {
                    _sendReaction(widget.note.id);
                  },
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity! > 0) {
                      _showReplyDialog(widget.note.id);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      border: glowingNotes.contains(widget.note.id)
                          ? Border.all(color: Colors.white, width: 4.0)
                          : null,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._buildParsedContent(widget.note.content),
                        _buildTimestampAndCounts(reactionCount, replyCount),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                ReactionsSection(
                  reactions: reactions,
                  isLoading: isReactionsLoading,
                ),
                RepliesSection(
                  replies: replies,
                  isLoading: isRepliesLoading,
                  onSendReplyReaction: _sendReplyReaction,
                  onShowReplyDialog: _showReplyDialog,
                  onNavigateToProfile: _navigateToProfile,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _navigateToProfile(widget.note.author),
            child: widget.note.authorProfileImage.isNotEmpty
                ? CircleAvatar(
                    backgroundImage:
                        CachedNetworkImageProvider(widget.note.authorProfileImage),
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
              onTap: () => _navigateToProfile(widget.note.author),
              child: Text(
                widget.note.authorName,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => _copyNoteId(context),
          ),
        ],
      ),
    );
  }

  void _copyNoteId(BuildContext context) {
    final formattedNoteId = Nip19.encodeNote(widget.note.id);
    Clipboard.setData(ClipboardData(text: formattedNoteId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Note ID copied.")),
    );
  }

  Widget _buildTimestampAndCounts(int reactionCount, int replyCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Flexible(
            child: Text(
              _formatTimestamp(widget.note.timestamp),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 16),
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
}

class ReactionDetailsModal extends StatelessWidget {
  final String reactionContent;
  final List<ReactionModel> reactions;

  const ReactionDetailsModal({
    Key? key,
    required this.reactionContent,
    required this.reactions,
  }) : super(key: key);

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
                          backgroundImage:
                              CachedNetworkImageProvider(reaction.authorProfileImage),
                        )
                      : const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                  title: Text(reaction.authorName),
                  trailing: Text(
                      reaction.content.isNotEmpty ? reaction.content : '+'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(npub: reaction.author),
                      ),
                    );
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
