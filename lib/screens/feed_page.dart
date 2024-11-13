import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note_model.dart';
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
  final FeedService _feedService = FeedService();
  final Set<String> cachedNoteIds = {};
  Timer? _refreshTimer;
  bool isLoadingOlderNotes = false;
  int currentLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadFeedFromCache(); 
    _loadFeed();
    _startBackgroundRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startBackgroundRefresh() {
    const refreshInterval = Duration(seconds: 10);
    _refreshTimer = Timer.periodic(refreshInterval, (timer) {
      _loadFeed();
    });
  }

  Future<void> _loadFeedFromCache() async {
    await _feedService.loadNotesFromCache((cachedNote) {
      setState(() {
        if (!cachedNoteIds.contains(cachedNote.noteId)) {
          cachedNoteIds.add(cachedNote.noteId);
          feedItems.add(cachedNote);
        }
      });
    });
    _sortFeedItems();
  }

  Future<void> _loadFeed({bool loadOlderNotes = false}) async {
    if (loadOlderNotes) {
      setState(() {
        isLoadingOlderNotes = true;
      });
      currentLimit += 10; 
    }

    try {
      final relayList = await _feedService.getRelayListFromNpub(widget.npub);
      final followingList = await _feedService.getFollowingList(widget.npub);
      for (var relayUrl in relayList) {
        await _feedService.fetchFeedForFollowingNpubs(
          relayUrl,
          followingList,
          (event) {
            if (!cachedNoteIds.contains(event.noteId)) {
              cachedNoteIds.add(event.noteId);
              setState(() {
                feedItems.add(event);
                _sortFeedItems();
              });
            }
          },
          limit: currentLimit,
        );
      }
      if (loadOlderNotes) {
        setState(() {
          isLoadingOlderNotes = false;
        });
      }
    } catch (e) {
      print('Error loading feed: $e');
      if (loadOlderNotes) {
        setState(() {
          isLoadingOlderNotes = false;
        });
      }
    }
  }

  void _sortFeedItems() {
    feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Latest notes'),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent &&
              !isLoadingOlderNotes) {
            _loadFeed(loadOlderNotes: true);
          }
          return false;
        },
        child: feedItems.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: feedItems.length,
                itemBuilder: (context, index) {
                  final item = feedItems[index];
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
                          builder: (context) => NoteDetailPage(note: item),
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
