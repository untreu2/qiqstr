import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qiqstr/publish.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr/nostr.dart';
import 'note.dart';

class FeedPage extends StatefulWidget {
  final String npub;

  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  List<Map<String, dynamic>> feedItems = [];
  Map<String, Map<String, String>> profileCache = {};

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _fetchAndSaveRelayList();
  }

  Future<void> _fetchAndSaveRelayList() async {
    List<String> relayList = [];
    WebSocket webSocket = await WebSocket.connect('wss://relay.damus.io');
    var requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [widget.npub],
        kinds: [10002],
        limit: 1,
      )
    ]);

    webSocket.listen((event) {
      var decodedEvent = jsonDecode(event);
      if (decodedEvent[0] == "EVENT") {
        var eventData = decodedEvent[2];
        var tags = eventData['tags'] as List;
        for (var tag in tags) {
          if (tag.isNotEmpty && tag[0] == 'r') {
            relayList.add(tag[1]);
          }
        }
      }
    });

    webSocket.add(requestWithFilter.serialize());
    await Future.delayed(Duration(seconds: 10));
    await webSocket.close();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('relayList', relayList);
  }

  Future<void> _loadFeed() async {
    List<String> followingNpubs = await getFollowingList(widget.npub);
    await fetchFeedForFollowingNpubs(followingNpubs);
  }

  Future<List<String>> getFollowingList(String npub) async {
    var requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [npub],
        kinds: [3],
        limit: 1,
      )
    ]);

    WebSocket webSocket = await WebSocket.connect('wss://relay.damus.io');
    List<String> followingNpubs = [];

    webSocket.listen((event) {
      var message = Message.deserialize(event);
      if (message.type == 'EVENT' && message.message.kind == 3) {
        for (var tag in message.message.tags) {
          if (tag.isNotEmpty && tag[0] == 'p') {
            followingNpubs.add(tag[1]);
          }
        }
      }
    });

    webSocket.add(requestWithFilter.serialize());
    await Future.delayed(Duration(seconds: 3));
    await webSocket.close();
    return followingNpubs;
  }

  Future<void> fetchFeedForFollowingNpubs(List<String> followingNpubs) async {
    if (followingNpubs.isEmpty) {
      return;
    }

    WebSocket webSocket = await WebSocket.connect('wss://relay.damus.io');
    var requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: followingNpubs,
        kinds: [1],
        limit: 10,
      )
    ]);

    webSocket.listen((event) async {
      var decodedEvent = jsonDecode(event);

      if (decodedEvent[0] == "EVENT") {
        var eventData = decodedEvent[2];
        String author = eventData['pubkey'];

        if (!profileCache.containsKey(author)) {
          await fetchProfileForNpub(author);
        }

        if (mounted) {
          setState(() {
            feedItems.add({
              'author': author,
              'name': profileCache[author]?['name'] ?? 'Anonymous',
              'content': eventData['content'],
              'noteId': eventData['id'],
              'timestamp': DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000).toString(),
              'reaction': ''
            });
          });
        }
      }
    });

    webSocket.add(requestWithFilter.serialize());
    await Future.delayed(Duration(seconds: 10));
    await webSocket.close();

    setState(() {
      feedItems.sort((a, b) {
        var dateA = DateTime.parse(a['timestamp']!);
        var dateB = DateTime.parse(b['timestamp']!);
        return dateB.compareTo(dateA);
      });
    });
  }

  Future<void> fetchProfileForNpub(String npub) async {
    WebSocket webSocket = await WebSocket.connect('wss://relay.damus.io');
    var requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [npub],
        kinds: [0],
        limit: 1
      )
    ]);

    webSocket.listen((event) {
      var decodedEvent = jsonDecode(event);

      if (decodedEvent[0] == "EVENT") {
        var eventData = decodedEvent[2];
        var kind = eventData['kind'];

        if (kind == 0) {
          var profileContent = jsonDecode(eventData['content']);
          profileCache[npub] = {
            'name': profileContent['name'] ?? 'Anonymous',
            'profileImage': profileContent['picture'] ?? '',
          };
        }
      }
    });

    webSocket.add(requestWithFilter.serialize());
    await Future.delayed(Duration(seconds: 10));
    await webSocket.close();
  }

  Future<void> _refreshFeed() async {
    setState(() {
      feedItems.clear();
    });
    await _loadFeed();
  }

  Future<void> _leaveReaction(String nsec, String hexNoteId, String emoji, int index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? relayList = prefs.getStringList('relayList');

    if (relayList == null || relayList.isEmpty) {
      print("Relay list not found.");
      return;
    }

    Event reactionEvent = Event.from(
      kind: 7,
      tags: [['e', hexNoteId]],
      content: emoji,
      privkey: nsec,
    );

    for (String relay in relayList) {
      await _broadcastReaction(reactionEvent, relay);
    }

    setState(() {
      feedItems[index]['reaction'] = emoji;
    });
  }

  Future<void> _broadcastReaction(Event reactionEvent, String relay) async {
    try {
      WebSocket webSocket = await WebSocket.connect(relay);

      String signedReactionJson = jsonEncode(["EVENT", reactionEvent.toJson()]);

      webSocket.add(signedReactionJson);

      webSocket.listen((event) {
        print('Response from relay: $event');
      });

      await Future.delayed(Duration(seconds: 5));
      await webSocket.close();
    } catch (e) {
      print('Error connecting to relay: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Latest notes'),
      ),
      body: feedItems.isEmpty
          ? Center(child: Text('Loading...'))
          : RefreshIndicator(
              onRefresh: _refreshFeed,
              child: ListView.builder(
                itemCount: feedItems.length,
                itemBuilder: (context, index) {
                  final item = feedItems[index];

                  return GestureDetector(
                    onDoubleTap: () {
                      SharedPreferences.getInstance().then((prefs) {
                        String? nsec = prefs.getString('privateKey');
                        if (nsec != null) {
                          String hexNoteId = item['noteId'];
                          _leaveReaction(nsec, hexNoteId, '🔔', index);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🔔 reaction sent')));
                        } else {
                          print("Private key not found.");
                        }
                      });
                    },
                    onLongPress: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NotePage(
                            authorName: item['name'],
                            content: item['content'],
                            timestamp: item['timestamp'],
                          ),
                        ),
                      );
                    },
                    child: ListTile(
                      title: Text('${item['name']}'),
                      subtitle: Text(item['content'] ?? ''),
                      trailing: Text(item['timestamp'] ?? ''),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PublishPage(),
            ),
          );
        },
        child: Icon(Icons.edit),
        tooltip: 'Share',
      ),
    );
  }
}
