import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
import 'profile_page.dart';
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

class RepliesSection extends StatelessWidget {
  final List<ReplyModel> replies;
  final bool isLoading;
  final Function(String) onSendReplyReaction;
  final Function(String) onShowReplyDialog;
  final Function(String) onNavigateToProfile;
  final Set<String> glowingReplies;
  final Set<String> swipedReplies;
  final Map<String, int> reactionCounts;
  final Map<String, int> replyCounts;

  const RepliesSection({
    Key? key,
    required this.replies,
    required this.isLoading,
    required this.onSendReplyReaction,
    required this.onShowReplyDialog,
    required this.onNavigateToProfile,
    required this.glowingReplies,
    required this.swipedReplies,
    required this.reactionCounts,
    required this.replyCounts,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: replies.length,
              itemBuilder: (context, index) {
                final reply = replies[index];
                return NoteWidget(
                  key: ValueKey(reply.id),
                  note: convertReplyToNote(reply),
                  reactionCount: reactionCounts[reply.id] ?? 0,
                  replyCount: replyCounts[reply.id] ?? 0,
                  onSendReaction: onSendReplyReaction,
                  onShowReplyDialog: onShowReplyDialog,
                  onAuthorTap: () {
                    onNavigateToProfile(reply.author);
                  },
                  onRepostedByTap: null,
                  onNoteTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NoteDetailPage(note: convertReplyToNote(reply)),
                      ),
                    );
                  },
                );
              },
            ),
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
  final Set<String> swipedNotes = {};

  final Map<String, int> _reactionCounts = {};
  final Map<String, int> _replyCounts = {};

  @override
  void initState() {
    super.initState();
    _initializeDetail();
  }

  @override
  void dispose() {
    dispose();
    super.dispose();
  }

  Future<void> _initializeDetail() async {
    try {
      _dataService = DataService(
        npub: widget.note.author,
        dataType: DataType.Note,
        onReactionsUpdated: _handleReactionsUpdated,
        onRepliesUpdated: _handleRepliesUpdated,
        onReactionCountUpdated: _updateReactionCount,
        onReplyCountUpdated: _updateReplyCount,
      );
      await _dataService.initialize();
      await _dataService.initializeConnections();
      await _fetchReactionsAndReplies();

      if (mounted) {
        setState(() {
          isReactionsLoading = false;
          isRepliesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isReactionsLoading = false;
          isRepliesLoading = false;
        });
      }
      print('Error initializing NoteDetailPage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing detail: $e')),
        );
      }
    }
  }

  Future<void> _fetchReactionsAndReplies() async {
    try {
      print('Fetching reactions for note ID: ${widget.note.id}');
      await _dataService.fetchReactionsForEvents([widget.note.id]);
      print('Reactions fetched: ${_dataService.reactionsMap[widget.note.id]?.length ?? 0}');

      print('Fetching replies for note ID: ${widget.note.id}');
      await _dataService.fetchRepliesForEvents([widget.note.id]);
      print('Replies fetched: ${_dataService.repliesMap[widget.note.id]?.length ?? 0}');

      if (!mounted) return;

      setState(() {
        reactions = _dataService.reactionsMap[widget.note.id] ?? [];
        _reactionCounts[widget.note.id] = reactions.length;

        replies = _dataService.repliesMap[widget.note.id] ?? [];
        _replyCounts[widget.note.id] = replies.length;
      });

      List<String> replyIds = replies.map((reply) => reply.id).toList();
      if (replyIds.isNotEmpty) {
        print('Fetching reactions for reply IDs: $replyIds');
        await _dataService.fetchReactionsForEvents(replyIds);
        if (!mounted) return;
        setState(() {
          for (var reply in replies) {
            _reactionCounts[reply.id] = _dataService.reactionsMap[reply.id]?.length ?? 0;
            print('Reactions for reply ID ${reply.id}: ${_reactionCounts[reply.id]}');
          }
        });
      }
    } catch (e) {
      print('Error fetching reactions and replies: $e');
      if (mounted) {
        setState(() {
          isReactionsLoading = false;
          isRepliesLoading = false;
        });
      }
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> updatedReactions) {
    if (!mounted) return;
    setState(() {
      if (noteId == widget.note.id) {
        reactions = updatedReactions;
      }
      _reactionCounts[noteId] = updatedReactions.length;
      print('Reactions updated for note ID $noteId: ${updatedReactions.length}');
    });
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> updatedReplies) {
    if (noteId == widget.note.id) {
      if (!mounted) return;
      setState(() {
        replies = updatedReplies;
        _replyCounts[noteId] = updatedReplies.length;
        print('Replies updated for note ID $noteId: ${updatedReplies.length}');
      });

      List<String> newReplyIds = updatedReplies.map((reply) => reply.id).toList();
      if (newReplyIds.isNotEmpty) {
        print('Fetching reactions for new reply IDs: $newReplyIds');
        _dataService.fetchReactionsForEvents(newReplyIds).then((_) {
          if (!mounted) return;
          setState(() {
            for (var reply in updatedReplies) {
              _reactionCounts[reply.id] = _dataService.reactionsMap[reply.id]?.length ?? 0;
              print('Reactions for new reply ID ${reply.id}: ${_reactionCounts[reply.id]}');
            }
          });
        }).catchError((e) {
          print('Error fetching reactions for new replies: $e');
        });
      }
    }
  }

  void _updateReactionCount(String noteId, int count) {
    if (!mounted) return;
    setState(() {
      _reactionCounts[noteId] = count;
      print('Reaction count updated for note ID $noteId: $count');
    });
  }

  void _updateReplyCount(String noteId, int count) {
    if (!mounted) return;
    setState(() {
      _replyCounts[noteId] = count;
      print('Reply count updated for note ID $noteId: $count');
    });
  }

  Future<void> _sendReaction(String noteId) async {
    try {
      await _dataService.sendReaction(noteId, '💜');
      if (!mounted) return;
      setState(() {
        glowingNotes.add(noteId);
        _reactionCounts[noteId] = (_reactionCounts[noteId] ?? 0) + 1;
        print('Sent reaction to note ID $noteId. New reaction count: ${_reactionCounts[noteId]}');
      });

      Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() {
          glowingNotes.remove(noteId);
        });
      });
    } catch (e) {
      print('Error sending reaction: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reaction: $e')),
      );
    }
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

  void _navigateToProfile(String authorNpub) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(npub: authorNpub),
      ),
    );
  }

  Widget _buildReactionsSection() {
    return ReactionsSection(
      reactions: reactions,
      isLoading: isReactionsLoading,
    );
  }

  Widget _buildRepliesSection() {
    return RepliesSection(
      replies: replies,
      isLoading: isRepliesLoading,
      onSendReplyReaction: _sendReaction,
      onShowReplyDialog: _showReplyDialog,
      onNavigateToProfile: _navigateToProfile,
      glowingReplies: glowingNotes,
      swipedReplies: swipedNotes,
      reactionCounts: _reactionCounts,
      replyCounts: _replyCounts,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NoteWidget(
                note: widget.note,
                reactionCount: _reactionCounts[widget.note.id] ?? 0,
                replyCount: _replyCounts[widget.note.id] ?? 0,
                onSendReaction: _sendReaction,
                onShowReplyDialog: _showReplyDialog,
                onAuthorTap: () {
                  _navigateToProfile(widget.note.author);
                },
                onRepostedByTap: widget.note.isRepost
                    ? () {
                        if (widget.note.repostedBy != null) {
                          _navigateToProfile(widget.note.repostedBy!);
                        }
                      }
                    : null,
                onNoteTap: () {
                },
              ),
              const SizedBox(height: 12),
              _buildReactionsSection(),
              _buildRepliesSection(),
            ],
          ),
        ),
      ),
    );
  }
}
