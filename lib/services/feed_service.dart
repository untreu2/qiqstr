import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr/nostr.dart';
import '../models/note_model.dart';

class FeedService {
  List<NoteModel> feedItems = [];
  Set<String> eventIds = {};

  Future<void> saveNotesToCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedNotes = feedItems.map((note) => jsonEncode(note.toJson())).toList();
    await prefs.setStringList('cachedNotes', cachedNotes);
  }

  Future<void> loadNotesFromCache(Function(NoteModel) onLoad) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedNotes = prefs.getStringList('cachedNotes') ?? [];
    for (var noteJson in cachedNotes) {
      final note = NoteModel.fromJson(jsonDecode(noteJson));
      eventIds.add(note.noteId);
      onLoad(note);
    }
  }

  Future<Map<String, String>> getUserProfileFromNpub(String npub) async {
    final mainRelayUrl = 'wss://relay.damus.io';
    String userName = 'Anonymous';
    String profileImage = '';
    try {
      final webSocket = await WebSocket.connect(mainRelayUrl);
      final request = Request(generate64RandomHexChars(), [
        Filter(authors: [npub], kinds: [0], limit: 1),
      ]);
      webSocket.listen((event) {
        final decodedEvent = jsonDecode(event);
        if (decodedEvent[0] == 'EVENT') {
          final profileContent = jsonDecode(decodedEvent[2]['content']);
          userName = profileContent['name'] ?? 'Anonymous';
          profileImage = profileContent['picture'] ?? '';
        }
      });
      webSocket.add(request.serialize());
      await Future.delayed(Duration(seconds: 5));
      await webSocket.close();
    } catch (e) {
      print('Error fetching user profile: $e');
    }
    return {'name': userName, 'profileImage': profileImage};
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
    Function(NoteModel) onNewEvent, {required int limit}
  ) async {
    if (followingNpubs.isEmpty) return;
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
          final authorProfile = await getUserProfileFromNpub(author);
          eventIds.add(eventId);
          final newEvent = NoteModel(
            noteId: eventId,
            content: content,
            author: author,
            authorName: authorProfile['name'] ?? 'Anonymous',
            authorProfileImage: authorProfile['profileImage'] ?? '',
            timestamp: DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000),
          );
          onNewEvent(newEvent);
          feedItems.insert(0, newEvent);
          await saveNotesToCache();
          if (feedItems.length > 100) {
            feedItems.removeLast();
            eventIds.remove(feedItems.last.noteId);
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
}
