import 'dart:async';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _feedService = FeedService(
      onNewNote: (newNote) {
        if (!cachedNoteIds.contains(newNote.id)) {
          setState(() {
            cachedNoteIds.add(newNote.id);
            feedItems.insert(0, newNote);
            feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            _feedService.fetchReactionsForNotes([newNote.id]);
            _feedService.fetchRepliesForNotes([newNote.id]);
          });
        }
      },
      onReactionsUpdated: (noteId, reactions) {
        setState(() {
          reactionsMap[noteId] = reactions;
        });
        _feedService.saveReactionsToCache();
      },
      onRepliesUpdated: (noteId, replies) {
        setState(() {
          repliesMap[noteId] = replies;
        });
        _feedService.saveRepliesToCache();
      },
    );
    _loadFeedFromCache();
    _initializeRelayConnection();
  }

  @override
  void dispose() {
    _feedService.closeConnections();
    super.dispose();
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
    await _feedService.loadReactionsFromCache();
    await _feedService.loadRepliesFromCache();
    setState(() {
      feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      reactionsMap.addAll(_feedService.reactionsMap);
      repliesMap.addAll(_feedService.repliesMap);
    });
  }

  Future<void> _loadOlderNotes() async {
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
      feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
            children: [
              const SizedBox(width: 16),
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
                if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent &&
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
                              backgroundImage: NetworkImage(item.authorProfileImage),
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
