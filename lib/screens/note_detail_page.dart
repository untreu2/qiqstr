import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
import 'profile_page.dart';
import '../widgets/reply_widget.dart';
import 'send_reply.dart';
import '../widgets/note_widget.dart';

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
  final Set<String> glowingReplies;
  final Set<String> swipedReplies;

  const RepliesSection({
    Key? key,
    required this.replies,
    required this.isLoading,
    required this.onSendReplyReaction,
    required this.onShowReplyDialog,
    required this.onNavigateToProfile,
    required this.glowingReplies,
    required this.swipedReplies,
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
                    border: glowingReplies.contains(reply.id)
                        ? Border.all(color: Colors.white, width: 4.0)
                        : swipedReplies.contains(reply.id)
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NoteDetailPage(
                              note: convertReplyToNote(reply)),
                        ),
                      );
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
}

NoteModel convertReplyToNote(ReplyModel reply) {
  return NoteModel(
    id: reply.id,
    content: reply.content,
    author: reply.author,
    authorName: reply.authorName,
    authorProfileImage: reply.authorProfileImage,
    timestamp: reply.timestamp,
    isRepost: false,
    repostedBy: null,
    repostedByName: '',
  );
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
  final Set<String> swipedReplies = {};

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reaction could not be sent: $e')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reaction could not be sent: $e')),
      );
    }
  }

  void _showReplyDialog(String noteId) {
    setState(() {
      swipedNotes.add(noteId);
    });

    Timer(const Duration(milliseconds: 300), () {
      setState(() {
        swipedNotes.remove(noteId);
      });
    });

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
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        left: true,
        right: true,
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
              setState(() {
                swipedNotes.add(widget.note.id);
              });
              Timer(const Duration(milliseconds: 300), () {
                setState(() {
                  swipedNotes.remove(widget.note.id);
                });
              });
              _showReplyDialog(widget.note.id);
            }
          },
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onDoubleTap: () {
                    _sendReaction(widget.note.id);
                  },
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
                      setState(() {
                        swipedNotes.add(widget.note.id);
                      });
                      Timer(const Duration(milliseconds: 300), () {
                        setState(() {
                          swipedNotes.remove(widget.note.id);
                        });
                      });
                      _showReplyDialog(widget.note.id);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      border: glowingNotes.contains(widget.note.id)
                          ? Border.all(color: Colors.white, width: 4.0)
                          : swipedNotes.contains(widget.note.id)
                              ? Border.all(color: Colors.white, width: 4.0)
                              : null,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: NoteWidget(
                      note: widget.note,
                      onAuthorTap: () => _navigateToProfile(widget.note.author),
                      onRepostedByTap: () => _navigateToProfile(widget.note.repostedBy ?? ''),
                      onNoteTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NoteDetailPage(note: widget.note),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                  glowingReplies: glowingReplies,
                  swipedReplies: swipedReplies,
                ),
              ],
            ),
          ),
        ),
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
