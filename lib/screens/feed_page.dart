import 'dart:async';
import 'package:flutter/material.dart';
import '../services/feed_service.dart';

class FeedPage extends StatefulWidget {
  final String npub;

  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final List<Map<String, dynamic>> feedItems = [];
  final FeedService _feedService = FeedService();
  final Set<String> cachedNoteIds = {};
  Timer? _refreshTimer;
  bool isLoadingOlderNotes = false;
  int currentLimit = 10;

  @override
  void initState() {
    super.initState();
    _feedService.clearProfileCache();
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
    const refreshInterval = Duration(seconds: 1);
    _refreshTimer = Timer.periodic(refreshInterval, (timer) {
      _loadFeed();
    });
  }

  Future<void> _loadFeedFromCache() async {
    await _feedService.loadNotesFromCache((cachedNote) {
      setState(() {
        feedItems.add(cachedNote);
      });
    });
  }

  Future<void> _loadFeed({bool loadOlderNotes = false}) async {
    if (loadOlderNotes) {
      setState(() {
        isLoadingOlderNotes = true;
      });
    }
    try {
      final relayList = await _feedService.getRelayListFromNpub(widget.npub);
      final followingList = await _feedService.getFollowingList(widget.npub);

      for (var relayUrl in relayList) {
        await _feedService.fetchFeedForFollowingNpubs(
          relayUrl,
          followingList,
          (event) {
            if (!cachedNoteIds.contains(event['noteId'])) {
              cachedNoteIds.add(event['noteId']);
              setState(() {
                feedItems.insert(0, event);
                if (feedItems.length > 100) {
                  feedItems.removeAt(feedItems.length - 1);
                }
                feedItems.sort((a, b) {
                  DateTime dateA = DateTime.parse(a['timestamp']);
                  DateTime dateB = DateTime.parse(b['timestamp']);
                  return dateB.compareTo(dateA);
                });
              });
            }
          },
          limit: loadOlderNotes ? currentLimit + 1 : 10,
        );
      }
      if (loadOlderNotes) {
        currentLimit += 1;
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
                    title: Text(item['name'] ?? 'Anonymous'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['content'] ?? ''),
                        const SizedBox(height: 4),
                        Text(
                          item['timestamp'] ?? '',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: item['profileImage'] != null
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(item['profileImage']),
                          )
                        : const CircleAvatar(child: Icon(Icons.person)),
                  );
                },
              ),
      ),
    );
  }
}
