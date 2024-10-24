import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr/nostr.dart';
import 'note.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, String> userProfile = {};
  List<Map<String, dynamic>> userNotes = [];
  Set<String> eventIds = {};

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadUserNotes();
  }

  Future<void> _loadUserProfile() async {
    WebSocket webSocket = await WebSocket.connect('wss://relay.damus.io');
    var requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [widget.npub],
        kinds: [0],
        limit: 1,
      )
    ]);

    webSocket.listen((event) {
      var decodedEvent = jsonDecode(event);

      if (decodedEvent[0] == "EVENT") {
        var eventData = decodedEvent[2];
        var kind = eventData['kind'];

        if (kind == 0) {
          var profileContent = jsonDecode(eventData['content']);
          setState(() {
            userProfile = {
              'name': profileContent['name'] ?? 'Anonymous',
              'profileImage': profileContent['picture'] ?? '',
              'nip05': profileContent['nip05'] ?? '',
              'about': profileContent['about'] ?? 'No information provided',
            };
          });
        }
      }
    });

    webSocket.add(requestWithFilter.serialize());
    await Future.delayed(Duration(seconds: 10));
    await webSocket.close();
  }

  Future<void> _loadUserNotes() async {
    WebSocket webSocket = await WebSocket.connect('wss://relay.damus.io');
    var requestWithFilter = Request(generate64RandomHexChars(), [
      Filter(
        authors: [widget.npub],
        kinds: [1],
        limit: 10,
      )
    ]);

    webSocket.listen((event) {
      var decodedEvent = jsonDecode(event);

      if (decodedEvent[0] == "EVENT") {
        var eventData = decodedEvent[2];
        String eventId = eventData['id'];
        String content = eventData['content'] ?? '';

        if (!eventIds.contains(eventId)) {
          setState(() {
            eventIds.add(eventId);
            final imageUrls = extractImageUrls(content);
            final updatedContent = removeImageUrls(content, imageUrls);

            userNotes.add({
              'content': updatedContent,
              'timestamp': DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000).toString(),
              'imageUrls': imageUrls,
              'noteId': eventId,
            });

            userNotes.sort((a, b) {
              DateTime dateA = DateTime.parse(a['timestamp']);
              DateTime dateB = DateTime.parse(b['timestamp']);
              return dateB.compareTo(dateA);
            });
          });
        }
      }
    });

    webSocket.add(requestWithFilter.serialize());
    await Future.delayed(Duration(seconds: 10));
    await webSocket.close();
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

  bool isImageUrl(String url) {
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.gif') ||
        url.endsWith('.webp');
  }

  Future<void> _leaveReaction(String hexNoteId, String emoji, int index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? nsec = prefs.getString('privateKey');

    if (nsec == null) {
      print("Private key not found.");
      return;
    }

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
      userNotes[index]['reaction'] = emoji;
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
        title: Text('${userProfile['name'] ?? 'Profile'}'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 20),
            CircleAvatar(
              backgroundImage: userProfile['profileImage'] != null && userProfile['profileImage']!.isNotEmpty
                  ? NetworkImage(userProfile['profileImage']!)
                  : AssetImage('assets/default_profile.png') as ImageProvider,
              radius: 60,
            ),
            SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Center(
                child: Text(
                  userProfile['name'] ?? 'Anonymous',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            SizedBox(height: 10),
            if (userProfile['nip05'] != null && userProfile['nip05']!.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    userProfile['nip05']!,
                    style: TextStyle(fontSize: 16, color: Colors.purple),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.verified, color: Colors.purple, size: 18),
                ],
              ),
            SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                userProfile['about'] ?? 'No information provided.',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 20),
            Divider(),
            Padding(
              padding: const EdgeInsets.all(8.0),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: userNotes.length,
              itemBuilder: (context, index) {
                final note = userNotes[index];
                final content = note['content'];
                final imageUrls = (note['imageUrls'] ?? []) as List<String>;

                return GestureDetector(
                  onDoubleTap: () {
                    String hexNoteId = note['noteId'];
                    _leaveReaction(hexNoteId, '👍', index);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('👍 reaction sent')));
                  },
                  onLongPress: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NotePage(
                          authorName: userProfile['name'] ?? 'Anonymous',
                          content: content,
                          timestamp: note['timestamp'],
                          profileImageUrl: userProfile['profileImage'] ?? '',
                          nip05: userProfile['nip05'] ?? '',
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
                            userProfile['profileImage'] != null && userProfile['profileImage']!.isNotEmpty
                                ? CircleAvatar(
                                    backgroundImage: NetworkImage(userProfile['profileImage']!),
                                    radius: 24,
                                  )
                                : CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.grey,
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
                                          '${userProfile['name'] ?? 'Anonymous'}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
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
                          note['timestamp'] ?? '',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
