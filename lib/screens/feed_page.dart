import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
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
  late DataService _dataService;
  final Set<String> cachedNoteIds = {};
  bool isLoadingOlderNotes = false;

  @override
  void initState() {
    super.initState();
    _dataService = DataService(
      npub: widget.npub,
      dataType: DataType.Feed,
      onNewNote: _handleNewNote,
      onReactionsUpdated: _handleReactionsUpdated,
      onRepliesUpdated: _handleRepliesUpdated,
    );
    _loadFeedFromCache();
    _initializeRelayConnection();
  }

  @override
  void dispose() {
    _dataService.closeConnections();
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
      _dataService.fetchReactionsForNotes([newNote.id]);
      _dataService.fetchRepliesForNotes([newNote.id]);
      setState(() {});
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {
    reactionsMap[noteId] = reactions;
    _dataService.saveReactionsToCache();
    setState(() {});
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {
    repliesMap[noteId] = replies;
    _dataService.saveRepliesToCache();
    setState(() {});
  }

  Future<void> _initializeRelayConnection() async {
    await _dataService.initializeConnections();
  }

  Future<void> _loadFeedFromCache() async {
    await _dataService.loadNotesFromCache((cachedNote) {
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
    _dataService.loadReactionsFromCache().then((_) {
      reactionsMap.addAll(_dataService.reactionsMap);
      setState(() {});
    });
    _dataService.loadRepliesFromCache().then((_) {
      repliesMap.addAll(_dataService.repliesMap);
      setState(() {});
    });
  }

  Future<void> _loadOlderNotes() async {
    if (isLoadingOlderNotes) return;
    setState(() {
      isLoadingOlderNotes = true;
    });

    final followingList = await _dataService.getFollowingList(widget.npub);
    await _dataService.fetchOlderNotes(followingList, (olderNote) {
      if (!cachedNoteIds.contains(olderNote.id)) {
        cachedNoteIds.add(olderNote.id);
        feedItems.add(olderNote);
        _dataService.fetchReactionsForNotes([olderNote.id]);
        _dataService.fetchRepliesForNotes([olderNote.id]);
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
                  builder: (context) => ProfilePage(npub: widget.npub)),
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
                if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 200 &&
                    !isLoadingOlderNotes) {
                  _loadOlderNotes();
                }
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
                              builder: (context) =>
                                  ProfilePage(npub: item.author)),
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
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Reactions: ${reactions.length}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Replies: ${replies.length}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
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
                              builder: (context) =>
                                  ProfilePage(npub: item.author)),
                        );
                      },
                      child: item.authorProfileImage.isNotEmpty
                          ? CircleAvatar(
                              backgroundImage: CachedNetworkImageProvider(
                                  item.authorProfileImage),
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
                                )),
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
