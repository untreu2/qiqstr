import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/feed_service.dart';
import '../screens/note_detail_page.dart';
import '../screens/profile_page.dart';

class FeedPage extends StatefulWidget {
  final String npub;

  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final List<NoteModel> feedItems = [];
  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  late FeedService _feedService;
  final Set<String> cachedNoteIds = {};
  bool isLoadingOlderNotes = false;
  final Debouncer _debouncer = Debouncer(milliseconds: 300);
  Timer? _updateTimer;
  bool _needsUpdate = false;

  @override
  void initState() {
    super.initState();
    _feedService = FeedService(
      onNewNote: _handleNewNote,
      onReactionsUpdated: _handleReactionsUpdated,
      onRepliesUpdated: _handleRepliesUpdated,
    );
    _loadFeedFromCache();
    _initializeRelayConnection();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _debouncer.dispose();
    _feedService.closeConnections();
    super.dispose();
  }

  void _handleNewNote(NoteModel newNote) {
    if (!cachedNoteIds.contains(newNote.id)) {
      cachedNoteIds.add(newNote.id);
      int insertIndex = feedItems.indexWhere((note) => note.timestamp.isBefore(newNote.timestamp));
      if (insertIndex == -1) {
        feedItems.add(newNote);
      } else {
        feedItems.insert(insertIndex, newNote);
      }
      _feedService.fetchReactionsForNotes([newNote.id]);
      _feedService.fetchRepliesForNotes([newNote.id]);
      _needsUpdate = true;
      _scheduleUpdate();
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {
    reactionsMap[noteId] = reactions;
    _feedService.saveReactionsToCache();
    _needsUpdate = true;
    _scheduleUpdate();
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {
    repliesMap[noteId] = replies;
    _feedService.saveRepliesToCache();
    _needsUpdate = true;
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (_updateTimer?.isActive ?? false) return;
    _updateTimer = Timer(Duration(milliseconds: 100), () {
      if (_needsUpdate) {
        setState(() {
          _needsUpdate = false;
        });
      }
    });
  }

  Future<void> _initializeRelayConnection() async {
    await _feedService.initializeConnections(widget.npub);
  }

  Future<void> _loadFeedFromCache() async {
    await _feedService.loadNotesFromCache((cachedNote) {
      if (!cachedNoteIds.contains(cachedNote.id)) {
        cachedNoteIds.add(cachedNote.id);
        feedItems.add(cachedNote);
      }
    });
    feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {});
    _loadReactionsAndReplies();
  }

  void _loadReactionsAndReplies() {
    _feedService.loadReactionsFromCache().then((_) {
      reactionsMap.addAll(_feedService.reactionsMap);
      setState(() {});
    });
    _feedService.loadRepliesFromCache().then((_) {
      repliesMap.addAll(_feedService.repliesMap);
      setState(() {});
    });
  }

  Future<void> _loadOlderNotes() async {
    if (isLoadingOlderNotes) return;
    setState(() {
      isLoadingOlderNotes = true;
    });

    final followingList = await _feedService.getFollowingList(widget.npub);
    await _feedService.fetchOlderNotes(followingList, (olderNote) {
      if (!cachedNoteIds.contains(olderNote.id)) {
        cachedNoteIds.add(olderNote.id);
        feedItems.add(olderNote);
        _feedService.fetchReactionsForNotes([olderNote.id]);
        _feedService.fetchRepliesForNotes([olderNote.id]);
      }
    });

    setState(() {
      isLoadingOlderNotes = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePage(npub: widget.npub),
              ),
            );
          },
          child: Row(
            children: const [
              SizedBox(width: 16),
              Text(
                'Profile',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        leadingWidth: 120,
        title: const Text('Latest Notes'),
      ),
      body: feedItems.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                _debouncer.run(() {
                  if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200 &&
                      !isLoadingOlderNotes) {
                    _loadOlderNotes();
                  }
                });
                return false;
              },
              child: ListView.builder(
                itemCount: feedItems.length + (isLoadingOlderNotes ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == feedItems.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final item = feedItems[index];
                  final reactions = reactionsMap[item.id] ?? [];
                  final replies = repliesMap[item.id] ?? [];
                  return ListTile(
                    title: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(npub: item.author),
                          ),
                        );
                      },
                      child: Text(item.authorName),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.content),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(item.timestamp),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Reactions: ${reactions.length}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Replies: ${replies.length}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(npub: item.author),
                          ),
                        );
                      },
                      child: item.authorProfileImage.isNotEmpty
                          ? CircleAvatar(
                              backgroundImage: CachedNetworkImageProvider(item.authorProfileImage),
                            )
                          : const CircleAvatar(child: Icon(Icons.person)),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NoteDetailPage(
                            note: item,
                            reactions: reactions,
                            replies: replies,
                            reactionsMap: reactionsMap,
                            repliesMap: repliesMap,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
  }
}

class Debouncer {
  final int milliseconds;
  VoidCallback? action;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
