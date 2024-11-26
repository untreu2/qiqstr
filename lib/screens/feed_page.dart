import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
import 'note_detail_page.dart';
import 'profile_page.dart';
import 'login_page.dart';

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
  bool isInitializing = true;

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
    _initializeFeed();
  }

  Future<void> _initializeFeed() async {
    await _dataService.initialize();

    await _loadFeedFromCache();

    await _dataService.initializeConnections();

    if (mounted) {
      setState(() {
        isInitializing = false;
      });
    }
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
      _dataService.saveNotesToCache();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {
    reactionsMap[noteId] = reactions;
    _dataService.saveReactionsToCache();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {
    repliesMap[noteId] = replies;
    _dataService.saveRepliesToCache();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadFeedFromCache() async {
    await _dataService.loadNotesFromCache((cachedNote) {
      if (!cachedNoteIds.contains(cachedNote.id)) {
        cachedNoteIds.add(cachedNote.id);
        feedItems.add(cachedNote);
      }
    });
    feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    await _dataService.loadReactionsFromCache();
    await _dataService.loadRepliesFromCache();
    reactionsMap.addAll(_dataService.reactionsMap);
    repliesMap.addAll(_dataService.repliesMap);

    if (mounted) {
      setState(() {});
    }
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
        if (mounted) {
          setState(() {});
        }
      }
    });

    if (mounted) {
      setState(() {
        isLoadingOlderNotes = false;
      });
    }
  }

  Future<void> _logoutAndClearData() async {
    await Hive.deleteFromDisk();

    await _dataService.closeConnections();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isInitializing && feedItems.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logoutAndClearData,
          ),
          title: const Text('Latest Notes'),
          actions: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfilePage(npub: widget.npub)),
                );
              },
              child: Row(
                children: const [
                  Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(width: 16),
                ],
              ),
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout),
          onPressed: _logoutAndClearData,
        ),
        title: const Text('Latest Notes'),
        actions: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfilePage(npub: widget.npub)),
              );
            },
            child: Row(
              children: const [
                Text(
                  'Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                SizedBox(width: 16),
              ],
            ),
          ),
        ],
      ),
      body: feedItems.isEmpty
          ? const Center(child: Text('No feed items available.'))
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
                          MaterialPageRoute(builder: (context) => ProfilePage(npub: item.author)),
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
                          MaterialPageRoute(builder: (context) => ProfilePage(npub: item.author)),
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
