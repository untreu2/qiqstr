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
      await _fetchReactionsAndReplies();
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
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
    }
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

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";
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

  @override
  Widget build(BuildContext context) {
    _organizeReplies(replies);
    final replyCount = replies.length;
    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity! > 0) {
                    setState(() {
                      swipedNotes.add(widget.note.id);
                    });
                    _showReplyDialog(widget.note.id);
                    Timer(const Duration(milliseconds: 500), () {
                      setState(() {
                        swipedNotes.remove(widget.note.id);
                      });
                    });
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
                          if (details.primaryVelocity! > 0) {
                            setState(() {
                              swipedNotes.add(widget.note.id);
                            });
                            _showReplyDialog(widget.note.id);
                            Timer(const Duration(milliseconds: 500), () {
                              setState(() {
                                swipedNotes.remove(widget.note.id);
                              });
                            });
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(),
                              ..._buildParsedContent(widget.note.content),
                              _buildTimestampAndCounts(replyCount),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                      ReactionsSection(reactions: reactions),
                      _buildRepliesSection(),
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

  void _navigateToProfile(String authorNpub) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(npub: authorNpub),
      ),
    );
  }

  Widget _buildTimestampAndCounts(int replyCount) {
    final reactionCount = reactions.length;
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

  Widget _buildRepliesSection() {
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
                  return GestureDetector(
                    onDoubleTap: () {
                      _sendReplyReaction(reply.id);
                    },
                    onHorizontalDragEnd: (details) {
                      if (details.primaryVelocity! > 0) {
                        setState(() {
                          swipedNotes.add(reply.id);
                        });
                        _showReplyDialog(reply.id);
                        Timer(const Duration(milliseconds: 500), () {
                          setState(() {
                            swipedNotes.remove(reply.id);
                          });
                        });
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        border: glowingReplies.contains(reply.id)
                            ? Border.all(color: Colors.white, width: 4.0)
                            : swipedNotes.contains(reply.id)
                                ? Border.all(color: Colors.white, width: 4.0)
                                : null,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: ReplyWidget(
                        reply: reply,
                        onAuthorTap: () {
                          _navigateToProfile(reply.author);
                        },
                        onReplyTap: () {
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
                                  isRepost: false,
                                  repostedBy: null,
                                  repostedByName: '',
                                ),
                                reactions: [],
                                replies: [],
                                reactionsMap: {},
                                repliesMap: {},
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }
}

class ReactionsSection extends StatelessWidget {
  final List<ReactionModel> reactions;

  const ReactionsSection({Key? key, required this.reactions}) : super(key: key);

  Map<String, List<ReactionModel>> _groupReactions(List<ReactionModel> reactions) {
    Map<String, List<ReactionModel>> grouped = {};
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
            runSpacing: 10,
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
                        style: const TextStyle(fontSize: 16),
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
        const SizedBox(height: 16),
      ],
    );
  }

  void _showReactionDetails(BuildContext context, String reactionContent, List<ReactionModel> reactionList) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ReactionDetailsModal(reactionContent: reactionContent, reactions: reactionList);
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
                  trailing: Text(reaction.content.isNotEmpty ? reaction.content : '+'),
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
