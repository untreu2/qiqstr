import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qiqstr/publish.dart';
import 'package:qiqstr/profile.dart';
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
  Set<String> eventIds = {};

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

    for (String npub in followingNpubs) {
      if (!profileCache.containsKey(npub)) {
        await fetchProfileForNpub(npub);
      }
    }

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

    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? relayList = prefs.getStringList('relayList');

    if (relayList == null || relayList.isEmpty) {
      return;
    }

    Request requestEvent = Request(generate64RandomHexChars(), [
      Filter(
        authors: followingNpubs,
        kinds: [1],
        limit: 10,
      )
    ]);

    List<Future<void>> futures = relayList.map((relay) => _broadcastFeedRequest(requestEvent, relay)).toList();
    await Future.wait(futures); 
  }

  Future<void> _broadcastFeedRequest(Request requestEvent, String relay) async {
    try {
      WebSocket webSocket = await WebSocket.connect(relay);

      String requestJson = requestEvent.serialize();

      webSocket.add(requestJson);

      webSocket.listen((event) async {
        var decodedEvent = jsonDecode(event);

        if (decodedEvent[0] == "EVENT") {
          var eventData = decodedEvent[2];
          String eventId = eventData['id'];
          String author = eventData['pubkey'];
          String content = eventData['content'] ?? ''; 

          if (content.trim().isEmpty) {
            return; 
          }

          if (!eventIds.contains(eventId)) {
            eventIds.add(eventId);

            if (!profileCache.containsKey(author)) {
              await fetchProfileForNpub(author);
            }

            if (mounted) {
              setState(() {
                String authorName = profileCache[author]?['name'] ?? 'Anonymous';
                String profileImageUrl = profileCache[author]?['profileImage'] ?? '';
                String nip05 = profileCache[author]?['nip05'] ?? ''; 

                final imageUrls = extractImageUrls(content);
                final updatedContent = removeImageUrls(content, imageUrls);

                feedItems.add({
                  'author': author,
                  'name': authorName,
                  'nip05': nip05, 
                  'content': updatedContent,
                  'noteId': eventId,
                  'timestamp': DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000).toString(),
                  'reaction': '',
                  'profileImage': profileImageUrl,
                  'imageUrls': imageUrls,
                });

                feedItems.sort((a, b) {
                  DateTime dateA = DateTime.parse(a['timestamp']);
                  DateTime dateB = DateTime.parse(b['timestamp']);
                  return dateB.compareTo(dateA); 
                });
              });
            }
          }
        }
      });

      await Future.delayed(Duration(seconds: 10));
      await webSocket.close();
    } catch (e) {
      print('Error connecting to relay: $e');
    }
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
          String authorName = profileContent['name'] ?? 'Anonymous';
          String profileImage = profileContent['picture'] ?? '';
          String nip05 = profileContent['nip05'] ?? '';  

          profileCache[npub] = {
            'name': authorName,
            'profileImage': profileImage,
            'nip05': nip05,  
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
      eventIds.clear();
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

    List<Future<void>> futures = relayList.map((relay) => _broadcastReaction(reactionEvent, relay)).toList();
    await Future.wait(futures);

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

  bool isImageUrl(String url) {
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.gif') ||
        url.endsWith('.webp');
  }

  List<String> extractImageUrls(String content) {
    final RegExp urlPattern = RegExp(r'(https?:\/\/[^\s]+)');
    final Iterable<RegExpMatch> matches = urlPattern.allMatches(content);
    List<String> imageUrls = [];

    matches.forEach((match) {
      String url = match.group(0) ?? '';
      if (isImageUrl(url)) {
        imageUrls.add(url);
      }
    });

    return imageUrls;
  }

  String removeImageUrls(String content, List<String> imageUrls) {
    String updatedContent = content;

    for (String imageUrl in imageUrls) {
      updatedContent = updatedContent.replaceAll(imageUrl, '').trim();
    }

    return updatedContent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Latest notes'),
        centerTitle: true,
        leading: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePage(npub: widget.npub),
              ),
            );
          },
          child: Icon(Icons.account_circle, size: 30),
        ),
      ),
      body: feedItems.isEmpty
          ? Center(child: Text('Loading...'))
          : RefreshIndicator(
              onRefresh: _refreshFeed,
              child: ListView.builder(
                itemCount: feedItems.length,
                itemBuilder: (context, index) {
                  final item = feedItems[index];
                  final content = item['content'];
                  final imageUrls = (item['imageUrls'] ?? []) as List<String>;

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
                            content: content,
                            timestamp: item['timestamp'],
                            profileImageUrl: item['profileImage'],
                            nip05: item['nip05'],
                            imageUrls: imageUrls,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProfilePage(npub: item['author']),
                                    ),
                                  );
                                },
                                child: item['profileImage'] != '' && item['profileImage'] != null
                                    ? CircleAvatar(
                                        backgroundImage: NetworkImage(item['profileImage']),
                                        radius: 18,
                                      )
                                    : CircleAvatar(
                                        radius: 24,
                                        backgroundColor: Colors.grey,
                                      ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            '${item['name']}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.white,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        SizedBox(width: 4),
                                        if (item['nip05'] != null && item['nip05']!.isNotEmpty)
                                          Icon(Icons.verified, color: Colors.purple, size: 16),
                                      ],
                                    ),
                                    if (item['nip05'] != null && item['nip05'] != '')
                                      Flexible(
                                        child: Text(
                                          item['nip05'],
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.purpleAccent,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    SizedBox(height: 4),
                                    if (content.isNotEmpty)
                                      Flexible(
                                        child: Text(
                                          content,
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (imageUrls.isNotEmpty)
                            Column(
                              children: imageUrls.map((url) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(url),
                                  ),
                                );
                              }).toList(),
                            ),
                          SizedBox(height: 8),
                          Text(
                            item['timestamp'] ?? '',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
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
