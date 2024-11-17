import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr/nostr.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import 'package:uuid/uuid.dart';

class FeedService {
  List<NoteModel> feedItems = [];
  Set<String> eventIds = {};
  Map<String, List<ReactionModel>> reactionsMap = {};
  Map<String, Map<String, String>> profileCache = {};
  Map<String, WebSocket> _webSockets = {};
  bool isConnecting = false;
  Timer? _checkNewNotesTimer;
  Function(NoteModel)? onNewNote;
  Function(String, List<ReactionModel>)? onReactionsUpdated;
  int currentLimit = 100;

  FeedService({this.onNewNote, this.onReactionsUpdated});

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

  String generate64RandomHexChars() {
    var uuid = Uuid();
    return uuid.v4().replaceAll('-', '');
  }

  Future<void> connectToRelays(List<String> relayList, List<String> followingNpubs) async {
    if (isConnecting) return;
    isConnecting = true;

    for (var relayUrl in relayList) {
      if (!_webSockets.containsKey(relayUrl) || _webSockets[relayUrl]?.readyState == WebSocket.closed) {
        try {
          final webSocket = await WebSocket.connect(relayUrl);
          _webSockets[relayUrl] = webSocket;
          webSocket.listen((event) => _handleEvent(event, followingNpubs), onDone: () {
            _reconnect(relayUrl, followingNpubs);
          }, onError: (error) {
            _reconnect(relayUrl, followingNpubs);
          });

          _fetchNotesForFollowing(webSocket, followingNpubs);
          fetchReactionsForNotes(feedItems.map((note) => note.noteId).toList());
        } catch (e) {
          _reconnect(relayUrl, followingNpubs);
        }
      }
    }
    isConnecting = false;
    _startCheckingForNewNotes(followingNpubs);
  }

  void _reconnect(String relayUrl, List<String> followingNpubs) {
    Future.delayed(Duration(seconds: 5), () {
      connectToRelays([relayUrl], followingNpubs);
    });
  }

  void _fetchNotesForFollowing(WebSocket webSocket, List<String> followingNpubs) {
    final request = Request(generate64RandomHexChars(), [
      Filter(authors: followingNpubs, kinds: [1], limit: currentLimit)
    ]);
    webSocket.add(request.serialize());
  }

  Future<void> fetchReactionsForNotes(List<String> noteIds) async {
    for (var relayUrl in _webSockets.keys) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          kinds: [7],
          e: noteIds,
        ),
      ]);
      _webSockets[relayUrl]?.add(request.serialize());
    }
  }

  void _handleEvent(dynamic event, List<String> followingNpubs) async {
    final decodedEvent = jsonDecode(event);
    if (decodedEvent[0] == 'EVENT') {
      final eventData = decodedEvent[2];
      final kind = eventData['kind'];
      if (kind == 1) {
        final eventId = eventData['id'];
        final author = eventData['pubkey'];
        final content = eventData['content'] ?? '';

        if (eventIds.contains(eventId) || content.trim().isEmpty || !followingNpubs.contains(author)) {
          return;
        }

        final authorProfile = await getCachedUserProfile(author);
        eventIds.add(eventId);

        final newEvent = NoteModel(
          noteId: eventId,
          content: content,
          author: author,
          authorName: authorProfile['name'] ?? 'Anonymous',
          authorProfileImage: authorProfile['profileImage'] ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000),
        );

        feedItems.add(newEvent);
        feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await saveNotesToCache();
        if (onNewNote != null) onNewNote!(newEvent);

        fetchReactionsForNotes([eventId]);
      } else if (kind == 7) {
        _handleReactionEvent(eventData);
      }
    }
  }

  void _handleReactionEvent(Map<String, dynamic> eventData) {
    final reaction = ReactionModel.fromEvent(eventData);

    String? noteId;
    for (var tag in eventData['tags']) {
      if (tag.length >= 2 && tag[0] == 'e') {
        noteId = tag[1];
        break;
      }
    }
    if (noteId == null) return;

    reactionsMap.putIfAbsent(noteId, () => []);
    if (!reactionsMap[noteId]!.any((r) => r.reactionId == reaction.reactionId)) {
      reactionsMap[noteId]!.add(reaction);
      if (onReactionsUpdated != null) {
        onReactionsUpdated!(noteId, reactionsMap[noteId]!);
      }
    }
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (profileCache.containsKey(npub)) {
      return profileCache[npub]!;
    }

    final profileData = await getUserProfileFromNpub(npub);
    profileCache[npub] = profileData;
    return profileData;
  }

  Future<Map<String, String>> getUserProfileFromNpub(String npub) async {
    if (profileCache.containsKey(npub)) {
      return profileCache[npub]!;
    }

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
    profileCache[npub] = {'name': userName, 'profileImage': profileImage};
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
      await Future.delayed(Duration(seconds: 5));
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

  Future<void> fetchOlderNotes(List<String> followingNpubs, Function(NoteModel) onOlderNote) async {
    for (var relayUrl in _webSockets.keys) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          authors: followingNpubs,
          kinds: [1],
          limit: currentLimit,
          until: feedItems.last.timestamp.millisecondsSinceEpoch ~/ 1000,
        ),
      ]);
      _webSockets[relayUrl]?.add(request.serialize());
    }
  }

  void _startCheckingForNewNotes(List<String> followingNpubs) {
    _checkNewNotesTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      for (var relayUrl in _webSockets.keys) {
        _fetchNotesForFollowing(_webSockets[relayUrl]!, followingNpubs);
        fetchReactionsForNotes(feedItems.map((note) => note.noteId).toList());
      }
    });
  }

  void closeConnections() {
    _checkNewNotesTimer?.cancel();
    for (var ws in _webSockets.values) {
      ws.close();
    }
    _webSockets.clear();
  }
}
