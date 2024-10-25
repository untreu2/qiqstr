import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr/nostr.dart';

class FeedService {
  List<Map<String, dynamic>> feedItems = [];
  Map<String, Map<String, String>> profileCache = {};
  Set<String> eventIds = {};

  Future<void> saveNotesToCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedNotes = feedItems.map((note) => jsonEncode(note)).toList();
    await prefs.setStringList('cachedNotes', cachedNotes);
  }

  Future<void> loadNotesFromCache(Function(Map<String, dynamic>) onLoad) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedNotes = prefs.getStringList('cachedNotes') ?? [];

    for (var noteJson in cachedNotes) {
      final note = jsonDecode(noteJson) as Map<String, dynamic>;
      eventIds.add(note['noteId']);
      onLoad(note);
    }
  }

  Future<void> fetchFeed(String npub, Function(Map<String, dynamic>) onNewEvent) async {
    final relayList = await getRelayListFromNpub(npub);
    final followingNpubs = await getFollowingList(npub);

    if (relayList.isEmpty || followingNpubs.isEmpty) return;

    final allRelays = <String>{};
    allRelays.addAll(relayList);

    for (var npub in followingNpubs) {
      final followedRelayList = await getRelayListFromNpub(npub);
      allRelays.addAll(followedRelayList);
    }

    await Future.forEach<String>(allRelays, (relayUrl) async {
      await fetchFeedForFollowingNpubs(
        relayUrl,
        followingNpubs,
        onNewEvent,
        limit: 10,
      );
    });
  }

  Future<List<String>> getRelayListFromNpub(String npub) async {
    final mainRelayUrl = 'wss://relay.damus.io';
    List<String> relayList = [];

    try {
      final webSocket = await WebSocket.connect(mainRelayUrl);
      final request = Request(generate64RandomHexChars(), [
        Filter(authors: [npub], kinds: [10002], limit: 1),
      ]);

      webSocket.listen((event) {
        final decodedEvent = jsonDecode(event);
        if (decodedEvent[0] == 'EVENT') {
          final tags = decodedEvent[2]['tags'] as List;
          for (var tag in tags) {
            if (tag.isNotEmpty && tag[0] == 'r') relayList.add(tag[1]);
          }
        }
      });

      webSocket.add(request.serialize());
      await Future.delayed(Duration(seconds: 10));
      await webSocket.close();
    } catch (e) {
      print('Error fetching relay list: $e');
    }

    return relayList;
  }

  Future<List<String>> getFollowingList(String npub) async {
    List<String> followingNpubs = [];
    final mainRelayUrl = 'wss://relay.damus.io';

    try {
      final webSocket = await WebSocket.connect(mainRelayUrl);
      final request = Request(generate64RandomHexChars(), [
        Filter(authors: [npub], kinds: [3], limit: 1),
      ]);

      webSocket.listen((event) {
        final decodedEvent = jsonDecode(event);
        if (decodedEvent[0] == 'EVENT') {
          for (var tag in decodedEvent[2]['tags']) {
            if (tag.isNotEmpty && tag[0] == 'p') followingNpubs.add(tag[1]);
          }
        }
      });

      webSocket.add(request.serialize());
      await Future.delayed(Duration(seconds: 5));
      await webSocket.close();
    } catch (e) {
      print('Error fetching following list: $e');
    }

    return followingNpubs;
  }

  Future<void> fetchFeedForFollowingNpubs(
    String relayUrl,
    List<String> followingNpubs,
    Function(Map<String, dynamic>) onNewEvent, {required int limit}
  ) async {
    try {
      final webSocket = await WebSocket.connect(relayUrl);
      final request = Request(generate64RandomHexChars(), [
        Filter(authors: followingNpubs, kinds: [1], limit: limit),
      ]);

      webSocket.listen((event) async {
        final decodedEvent = jsonDecode(event);

        if (decodedEvent[0] == 'EVENT') {
          final eventData = decodedEvent[2];
          final eventId = eventData['id'];
          final author = eventData['pubkey'];
          final content = eventData['content'] ?? '';

          if (eventIds.contains(eventId) || content.trim().isEmpty) {
            return;
          }

          if (!profileCache.containsKey(author)) {
            await _fetchProfileForNpub(author);
          }

          final authorProfile = profileCache[author] ?? {};

          eventIds.add(eventId);
          final newEvent = {
            'author': author,
            'name': authorProfile['name'] ?? 'Anonymous',
            'content': content,
            'noteId': eventId,
            'timestamp': DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000).toString(),
            'profileImage': authorProfile['profileImage'] ?? '',
          };
          onNewEvent(newEvent);

          feedItems.add(newEvent);
          await saveNotesToCache();

          if (feedItems.length > 100) {
            feedItems.removeAt(0);
            eventIds.remove(feedItems[0]['noteId']);
          }
        }
      });

      webSocket.add(request.serialize());
      await Future.delayed(Duration(seconds: 10));
      await webSocket.close();
    } catch (e) {
      print('Error fetching events from $relayUrl: $e');
    }
  }

  Future<void> _fetchProfileForNpub(String npub) async {
    final prefs = await SharedPreferences.getInstance();

    if (profileCache.containsKey(npub)) return;

    String? cachedProfile = prefs.getString('profile_$npub');

    if (cachedProfile != null) {
      profileCache[npub] = Map<String, String>.from(jsonDecode(cachedProfile));
      return;
    }

    final mainRelayUrl = 'wss://relay.damus.io';
    final webSocket = await WebSocket.connect(mainRelayUrl);
    final request = Request(generate64RandomHexChars(), [
      Filter(authors: [npub], kinds: [0], limit: 1),
    ]);

    webSocket.listen((event) {
      final decodedEvent = jsonDecode(event);

      if (decodedEvent[0] == 'EVENT') {
        final profileContent = jsonDecode(decodedEvent[2]['content']);
        final profileData = {
          'name': profileContent['name'] ?? 'Anonymous',
          'profileImage': profileContent['picture'] ?? '',
        };
        profileCache[npub] = Map<String, String>.from(profileData);

        prefs.setString('profile_$npub', jsonEncode(profileData));
      }
    });

    webSocket.add(request.serialize());
    await Future.delayed(Duration(seconds: 10));
    await webSocket.close();
  }

  Future<void> clearProfileCache() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.clear();
  }
}
