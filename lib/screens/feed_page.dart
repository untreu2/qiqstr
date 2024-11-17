import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../services/feed_service.dart';
import '../screens/note_detail_page.dart';

class FeedPage extends StatefulWidget {
  final String npub;

  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final List<NoteModel> feedItems = [];
  final Map<String, List<ReactionModel>> reactionsMap = {};
  late FeedService _feedService;
  final Set<String> cachedNoteIds = {};
  bool isLoadingOlderNotes = false;

  @override
  void initState() {
    super.initState();
    _feedService = FeedService(
      onNewNote: (newNote) {
        if (!cachedNoteIds.contains(newNote.noteId)) {
          setState(() {
            cachedNoteIds.add(newNote.noteId);
            feedItems.insert(0, newNote);
            feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          });
        }
      },
      onReactionsUpdated: (noteId, reactions) {
        setState(() {
          reactionsMap[noteId] = reactions;
        });
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
    final relayList = await _feedService.getRelayListFromNpub(widget.npub);
    final followingList = await _feedService.getFollowingList(widget.npub);
    if (relayList.isNotEmpty) {
      await _feedService.connectToRelays(relayList, followingList);
    }
  }

  Future<void> _loadFeedFromCache() async {
    await _feedService.loadNotesFromCache((cachedNote) {
      if (!cachedNoteIds.contains(cachedNote.noteId)) {
        cachedNoteIds.add(cachedNote.noteId);
        feedItems.add(cachedNote);
      }
    });
    setState(() {
      feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  Future<void> _loadOlderNotes() async {
    setState(() {
      isLoadingOlderNotes = true;
    });

    final followingList = await _feedService.getFollowingList(widget.npub);
    await _feedService.fetchOlderNotes(followingList, (olderNote) {
      if (!cachedNoteIds.contains(olderNote.noteId)) {
        cachedNoteIds.add(olderNote.noteId);
        feedItems.add(olderNote);
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
        title: const Text('Latest notes'),
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
                itemCount: feedItems.length,
                itemBuilder: (context, index) {
                  final item = feedItems[index];
                  final reactions = reactionsMap[item.noteId] ?? [];
                  return ListTile(
                    title: Text(item.authorName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.content),
                        const SizedBox(height: 4),
                        Text(
                          item.timestamp.toString(),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Reactions: ${reactions.length}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: item.authorProfileImage.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(item.authorProfileImage),
                          )
                        : const CircleAvatar(child: Icon(Icons.person)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NoteDetailPage(
                            note: item,
                            reactions: reactions,
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
}
