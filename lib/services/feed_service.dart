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

  List<String> relayUrls = [];

  Map<String, Completer<Map<String, String>>> _pendingProfileRequests = {};
  Map<String, String> _profileSubscriptionIds = {};

  FeedService({this.onNewNote, this.onReactionsUpdated});

  Future<void> initializeConnections(String npub) async {
    List<String> popularRelays = [
      'wss://relay.damus.io',
      'wss://relay.snort.social',
      'wss://nos.lol',
    ];

    relayUrls = popularRelays;
    List<String> followingNpubs = await getFollowingList(npub);
    await connectToRelays(relayUrls, followingNpubs);
  }

  Future<void> connectToRelays(List<String> relayList, List<String> followingNpubs) async {
    if (isConnecting) return;
    isConnecting = true;

    await Future.wait(relayList.map((relayUrl) async {
      if (!_webSockets.containsKey(relayUrl) || _webSockets[relayUrl]?.readyState == WebSocket.closed) {
        try {
          final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 5));
          _webSockets[relayUrl] = webSocket;

          webSocket.listen(
            (event) => _handleEvent(event, followingNpubs),
            onDone: () {
              _webSockets.remove(relayUrl);
              print('Disconnected from $relayUrl');
            },
            onError: (error) {
              print('Relay error ($relayUrl): $error');
              _webSockets.remove(relayUrl);
            },
          );

          _fetchNotesForFollowing(webSocket, followingNpubs);
          _fetchProfilesForFollowing(webSocket, followingNpubs);
        } catch (e) {
          print('Failed to connect to $relayUrl: $e');
          _webSockets.remove(relayUrl);
        }
      }
    }));

    isConnecting = false;

    if (_webSockets.isNotEmpty) {
      _startCheckingForNewNotesAndProfiles(followingNpubs);
    }
  }

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

  void _fetchNotesForFollowing(WebSocket webSocket, List<String> followingNpubs) {
    final request = Request(generate64RandomHexChars(), [
      Filter(authors: followingNpubs, kinds: [1], limit: currentLimit),
    ]);
    webSocket.add(request.serialize());
  }

  void _fetchProfilesForFollowing(WebSocket webSocket, List<String> followingNpubs) {
    final request = Request(generate64RandomHexChars(), [
      Filter(authors: followingNpubs, kinds: [0]),
    ]);
    webSocket.add(request.serialize());
  }

  Future<void> fetchReactionsForNotes(List<String> noteIds) async {
    for (var relayUrl in _webSockets.keys) {
      final request = Request(generate64RandomHexChars(), [
        Filter(kinds: [7], e: noteIds),
      ]);
      _webSockets[relayUrl]?.add(request.serialize());
    }
  }

  void _handleEvent(dynamic event, List<String> followingNpubs) async {
    try {
      final decodedEvent = jsonDecode(event);

      if (decodedEvent[0] == 'EVENT') {
        final eventData = decodedEvent[2];
        final kind = eventData['kind'];

        if (kind == 1) {
          final eventId = eventData['id'];
          final author = eventData['pubkey'];
          final content = eventData['content'] ?? '';

          if (eventIds.contains(eventId) || content.trim().isEmpty || (followingNpubs.isNotEmpty && !followingNpubs.contains(author))) {
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

          if (onNewNote != null) {
            onNewNote!(newEvent);
          }

          fetchReactionsForNotes([eventId]);
        } else if (kind == 7) {
          _handleReactionEvent(eventData);
        } else if (kind == 0) {
          final author = eventData['pubkey'];
          final profileContent = jsonDecode(eventData['content']);
          final userName = profileContent['name'] ?? 'Anonymous';
          final profileImage = profileContent['picture'] ?? '';

          profileCache[author] = {'name': userName, 'profileImage': profileImage};

          if (_pendingProfileRequests.containsKey(author)) {
            _pendingProfileRequests[author]!.complete(profileCache[author]!);
            _pendingProfileRequests.remove(author);
          }
        }
      } else if (decodedEvent[0] == 'EOSE') {
        final subscriptionId = decodedEvent[1];
        final npub = _profileSubscriptionIds[subscriptionId];
        if (npub != null && _pendingProfileRequests.containsKey(npub)) {
          profileCache[npub] = {'name': 'Anonymous', 'profileImage': ''};
          _pendingProfileRequests[npub]!.complete(profileCache[npub]!);
          _pendingProfileRequests.remove(npub);
          _profileSubscriptionIds.remove(subscriptionId);
        }
      }
    } catch (e) {
      print('Error handling event: $e');
    }
  }

  void _handleReactionEvent(Map<String, dynamic> eventData) async {
    final reactionPubKey = eventData['pubkey'];
    final reactionProfile = await getCachedUserProfile(reactionPubKey);

    String? noteId;
    for (var tag in eventData['tags']) {
      if (tag.length >= 2 && tag[0] == 'e') {
        noteId = tag[1];
        break;
      }
    }
    if (noteId == null) return;

    final reaction = ReactionModel.fromEvent(eventData, reactionProfile);

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

    if (_pendingProfileRequests.containsKey(npub)) {
      return _pendingProfileRequests[npub]!.future;
    }

    Completer<Map<String, String>> completer = Completer<Map<String, String>>();
    _pendingProfileRequests[npub] = completer;

    String subscriptionId = generate64RandomHexChars();
    _profileSubscriptionIds[subscriptionId] = npub;

    final request = Request(subscriptionId, [
      Filter(authors: [npub], kinds: [0], limit: 1),
    ]);

    for (var webSocket in _webSockets.values) {
      webSocket.add(request.serialize());
    }

    Future.delayed(Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        profileCache[npub] = {'name': 'Anonymous', 'profileImage': ''};
        completer.complete(profileCache[npub]!);
        _pendingProfileRequests.remove(npub);
        _profileSubscriptionIds.remove(subscriptionId);
      }
    });

    return completer.future;
  }

  Future<List<String>> getFollowingList(String npub) async {
    List<String> followingNpubs = [];

    for (var relayUrl in relayUrls) {
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 5));
        final request = Request(generate64RandomHexChars(), [
          Filter(authors: [npub], kinds: [3], limit: 1),
        ]);

        Completer<void> completer = Completer<void>();

        webSocket.listen((event) {
          final decodedEvent = jsonDecode(event);
          if (decodedEvent[0] == 'EVENT') {
            for (var tag in decodedEvent[2]['tags']) {
              if (tag.isNotEmpty && tag[0] == 'p') {
                followingNpubs.add(tag[1]);
              }
            }
            completer.complete();
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete();
        });

        webSocket.add(request.serialize());

        await completer.future.timeout(Duration(seconds: 5), onTimeout: () {
          webSocket.close();
        });

        await webSocket.close();
      } catch (e) {
        print("Error fetching following list from $relayUrl: $e");
      }
    }

    followingNpubs = followingNpubs.toSet().toList();
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

  void _startCheckingForNewNotesAndProfiles(List<String> followingNpubs) {
    _checkNewNotesTimer?.cancel();
    _checkNewNotesTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      for (var relayUrl in _webSockets.keys) {
        final webSocket = _webSockets[relayUrl]!;
        _fetchNotesForFollowing(webSocket, followingNpubs);
        _fetchProfilesForFollowing(webSocket, followingNpubs);
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
