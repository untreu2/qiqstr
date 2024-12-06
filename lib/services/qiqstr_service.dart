import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:nostr/nostr.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import 'package:uuid/uuid.dart';

enum DataType { Feed, Profile }

enum MessageType { NewNotes, CacheLoad, Error }

class IsolateMessage {
  final MessageType type;
  final dynamic data;

  IsolateMessage(this.type, this.data);
}

class CachedProfile {
  final Map<String, String> data;
  final DateTime fetchedAt;

  CachedProfile(this.data, this.fetchedAt);
}

class DataService {
  final String npub;
  final DataType dataType;
  final Function(NoteModel)? onNewNote;
  final Function(String, List<ReactionModel>)? onReactionsUpdated;
  final Function(String, List<ReplyModel>)? onRepliesUpdated;

  List<NoteModel> notes = [];
  final Set<String> eventIds = {};
  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};

  final Map<String, CachedProfile> profileCache = {};

  final Map<String, WebSocket> _webSockets = {};
  bool isConnecting = false;
  Timer? _checkNewNotesTimer;
  int currentLimit = 75;
  int currentOffset = 0;

  final List<String> relayUrls = [
    'wss://relay.damus.io',
    'wss://relay.snort.social',
    'wss://nos.lol',
    'wss://untreu.me',
    'wss://vitor.nostr1.com',
    'wss://nostr.mom'
  ];

  final Map<String, Completer<Map<String, String>>> _pendingProfileRequests = {};
  final Map<String, String> _profileSubscriptionIds = {};

  late Box notesBox;
  late Box reactionsBox;
  late Box repliesBox;

  bool _isInitialized = false;
  bool _isClosed = false;

  late ReceivePort _receivePort;
  late Isolate _isolate;
  late SendPort _sendPort;

  Function(List<NoteModel>)? _onCacheLoad;

  final Completer<void> _sendPortReadyCompleter = Completer<void>();

  final Uuid _uuid = Uuid();

  final Duration profileCacheTTL = Duration(minutes: 10);

  DataService({
    required this.npub,
    required this.dataType,
    this.onNewNote,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
  });

  Future<void> initialize() async {
    try {
      await Future.wait([
        Hive.openBox('notes_${dataType.toString()}_$npub'),
        Hive.openBox('reactions_${dataType.toString()}_$npub'),
        Hive.openBox('replies_${dataType.toString()}_$npub'),
      ]).then((boxes) {
        notesBox = boxes[0];
        reactionsBox = boxes[1];
        repliesBox = boxes[2];
      });
      _isInitialized = true;

      await _initializeIsolate();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _initializeIsolate() async {
    try {
      _receivePort = ReceivePort();
      _isolate = await Isolate.spawn(_dataProcessorEntryPoint, _receivePort.sendPort);

      _receivePort.listen((message) {
        if (message is SendPort) {
          _sendPort = message;
          if (!_sendPortReadyCompleter.isCompleted) {
            _sendPortReadyCompleter.complete();
          }
        } else if (message is IsolateMessage) {
          switch (message.type) {
            case MessageType.NewNotes:
              _handleNewNotes(message.data);
              break;
            case MessageType.CacheLoad:
              _handleCacheLoad(message.data);
              break;
            case MessageType.Error:
              break;
          }
        }
      });
    } catch (e) {
      rethrow;
    }
  }

  static void _dataProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort isolateReceivePort = ReceivePort();
    sendPort.send(isolateReceivePort.sendPort);

    isolateReceivePort.listen((message) {
      if (message is IsolateMessage) {
        switch (message.type) {
          case MessageType.CacheLoad:
            _processCacheLoad(message.data, sendPort);
            break;
          case MessageType.NewNotes:
            _processNewNotes(message.data, sendPort);
            break;
          case MessageType.Error:
            sendPort.send(IsolateMessage(MessageType.Error, message.data));
            break;
        }
      } else if (message is String && message == 'close') {
        isolateReceivePort.close();
      }
    });
  }

  static void _processCacheLoad(String data, SendPort sendPort) {
    try {
      final List<dynamic> jsonData = json.decode(data);
      final List<NoteModel> parsedNotes =
          jsonData.map((json) => NoteModel.fromJson(json)).toList();
      sendPort.send(IsolateMessage(MessageType.CacheLoad, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.Error, e.toString()));
    }
  }

  static void _processNewNotes(String data, SendPort sendPort) {
    try {
      final List<dynamic> jsonData = json.decode(data);
      final List<NoteModel> parsedNotes =
          jsonData.map((json) => NoteModel.fromJson(json)).toList();
      sendPort.send(IsolateMessage(MessageType.NewNotes, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.Error, e.toString()));
    }
  }

  Future<void> initializeConnections() async {
    if (!_isInitialized) {
      await initialize();
    }

    List<String> targetNpubs = dataType == DataType.Feed
        ? await getFollowingList(npub)
        : [npub];

    if (_isClosed) return;

    await connectToRelays(relayUrls, targetNpubs);
    await fetchNotes(targetNpubs, initialLoad: true);
  }

  Future<void> connectToRelays(List<String> relayList, List<String> targetNpubs) async {
    if (isConnecting || _isClosed) return;
    isConnecting = true;

    await Future.wait(relayList.map((relayUrl) async {
      if (_isClosed) return;
      if (!_webSockets.containsKey(relayUrl) || _webSockets[relayUrl]?.readyState == WebSocket.closed) {
        try {
          final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 5));
          if (_isClosed) {
            webSocket.close();
            return;
          }
          _webSockets[relayUrl] = webSocket;
          webSocket.listen(
            (event) => _handleEvent(event, targetNpubs),
            onDone: () {
              _webSockets.remove(relayUrl);
              _reconnectRelay(relayUrl, targetNpubs);
            },
            onError: (error) {
              _webSockets.remove(relayUrl);
              _reconnectRelay(relayUrl, targetNpubs);
            },
          );
          await _fetchProfilesBatch(targetNpubs);
          await _fetchReplies(webSocket, targetNpubs);
        } catch (e) {
          _webSockets.remove(relayUrl);
        }
      }
    }));

    isConnecting = false;

    if (_webSockets.isNotEmpty) {
      _startCheckingForNewData(targetNpubs);
    }
  }

  void _reconnectRelay(String relayUrl, List<String> targetNpubs, [int attempt = 1]) {
    if (_isClosed) return;
    final int delaySeconds = attempt > 5 ? 32 : (1 << attempt);
    Timer(Duration(seconds: delaySeconds), () async {
      if (_isClosed) return;
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 5));
        if (_isClosed) {
          webSocket.close();
          return;
        }
        _webSockets[relayUrl] = webSocket;
        webSocket.listen(
          (event) => _handleEvent(event, targetNpubs),
          onDone: () {
            _webSockets.remove(relayUrl);
            _reconnectRelay(relayUrl, targetNpubs, attempt + 1);
          },
          onError: (error) {
            _webSockets.remove(relayUrl);
            _reconnectRelay(relayUrl, targetNpubs, attempt + 1);
          },
        );
        await _fetchProfilesBatch(targetNpubs);
        await _fetchReplies(webSocket, targetNpubs);
      } catch (e) {
        _reconnectRelay(relayUrl, targetNpubs, attempt + 1);
      }
    });
  }

  Future<void> fetchNotes(List<String> targetNpubs, {bool initialLoad = false}) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(
        authors: targetNpubs,
        kinds: [1, 6],
        limit: currentLimit,
        since: currentOffset,
      ),
    ]);

    await Future.wait(_webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));

    if (initialLoad) {
      currentOffset += currentLimit;
    }
  }

  Future<void> saveNotesToCache() async {
    if (notesBox.isOpen) {
      try {
        final notesJson = notes.map((note) => note.toJson()).toList();
        await notesBox.put('notes_json', json.encode(notesJson));
      } catch (e) {}
    }
  }

  Future<void> loadNotesFromCache(Function(List<NoteModel>) onLoad) async {
    if (!notesBox.isOpen) return;
    var cachedData = notesBox.get('notes_json', defaultValue: '');
    if (cachedData is! String) {
      try {
        String jsonString = json.encode(cachedData);
        _onCacheLoad = onLoad;
        await _sendPortReadyCompleter.future;
        _sendPort.send(IsolateMessage(MessageType.CacheLoad, jsonString));
      } catch (e) {}
    } else {
      String jsonString = cachedData;
      if (jsonString.isEmpty) return;
      _onCacheLoad = onLoad;

      await _sendPortReadyCompleter.future;

      _sendPort.send(IsolateMessage(MessageType.CacheLoad, jsonString));
    }

    await _fetchProfilesForAllData();
  }

  Future<void> saveReactionsToCache() async {
    if (reactionsBox.isOpen) {
      try {
        Map<String, dynamic> reactionsJson = reactionsMap.map((key, value) {
          return MapEntry(key, value.map((reaction) => reaction.toJson()).toList());
        });
        await reactionsBox.put('reactions', json.encode(reactionsJson));
      } catch (e) {}
    }
  }

  Future<void> loadReactionsFromCache() async {
    if (!reactionsBox.isOpen) return;
    try {
      String? cachedReactionsString = reactionsBox.get('reactions');
      if (cachedReactionsString != null && cachedReactionsString.isNotEmpty) {
        Map<String, dynamic> cachedReactionsJson = json.decode(cachedReactionsString);
        cachedReactionsJson.forEach((key, value) {
          String noteId = key;
          List<dynamic> reactionsList = value as List<dynamic>;
          reactionsMap[noteId] = reactionsList
              .map((reactionJson) => ReactionModel.fromJson(Map<String, dynamic>.from(reactionJson as Map)))
              .toList();
        });
      }
    } catch (e) {}

    await _fetchProfilesForAllData();
  }

  Future<void> saveRepliesToCache() async {
    if (repliesBox.isOpen) {
      try {
        Map<String, dynamic> repliesJson = repliesMap.map((key, value) {
          return MapEntry(key, value.map((reply) => reply.toJson()).toList());
        });
        await repliesBox.put('replies', json.encode(repliesJson));
      } catch (e) {}
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (!repliesBox.isOpen) return;
    try {
      String? cachedRepliesString = repliesBox.get('replies');
      if (cachedRepliesString != null && cachedRepliesString.isNotEmpty) {
        Map<String, dynamic> cachedRepliesJson = json.decode(cachedRepliesString);
        cachedRepliesJson.forEach((key, value) {
          String noteId = key;
          List<dynamic> repliesList = value as List<dynamic>;
          repliesMap[noteId] = repliesList
              .map((replyJson) => ReplyModel.fromJson(Map<String, dynamic>.from(replyJson as Map)))
              .toList();
        });
      }
    } catch (e) {}

    await _fetchProfilesForAllData();
  }

  String generateUUID() {
    return _uuid.v4().replaceAll('-', '');
  }

  Future<void> _fetchProfilesBatch(List<String> npubs) async {
    if (_isClosed) return;

    final uniqueNpubs = npubs.toSet().difference(profileCache.keys.toSet()).toList();
    if (uniqueNpubs.isEmpty) return;

    final request = Request(generateUUID(), [
      Filter(authors: uniqueNpubs, kinds: [0], limit: uniqueNpubs.length),
    ]);

    await Future.wait(_webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
  }

  Future<void> _fetchReplies(WebSocket webSocket, List<String> targetNpubs) async {
    if (_isClosed) return;
    final parentIds = notes.map((note) => note.id).toSet().union(repliesMap.keys.toSet()).toList();
    final request = Request(generateUUID(), [
      Filter(
        kinds: [1],
        e: parentIds,
        limit: 1000,
      ),
    ]);
    webSocket.add(request.serialize());
  }

  Future<void> fetchReactionsForNotes(List<String> noteIds) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(
        kinds: [7],
        e: noteIds,
        limit: 1000,
      ),
    ]);

    await Future.wait(_webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
  }

  Future<void> fetchRepliesForNotes(List<String> parentIds) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(
        kinds: [1],
        e: parentIds,
        limit: 1000,
      ),
    ]);

    await Future.wait(_webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {
    if (_isClosed) return;
    try {
      final decodedEvent = jsonDecode(event);
      if (decodedEvent[0] == 'EVENT') {
        Map<String, dynamic> eventData = decodedEvent[2] as Map<String, dynamic>;
        final kind = eventData['kind'] as int;
        if (kind == 1 || kind == 6) {
          await _processNoteEvent(eventData, targetNpubs);
        } else if (kind == 7) {
          await _handleReactionEvent(eventData);
        } else if (kind == 0) {
          await _handleProfileEvent(eventData);
        }
      } else if (decodedEvent[0] == 'EOSE') {
        final subscriptionId = decodedEvent[1] as String;
        final npub = _profileSubscriptionIds[subscriptionId];
        if (npub != null && _pendingProfileRequests.containsKey(npub)) {
          profileCache[npub] = CachedProfile({
            'name': 'Anonymous',
            'profileImage': '',
            'about': '',
            'nip05': '',
            'banner': '',
          }, DateTime.now());
          _pendingProfileRequests[npub]?.complete(profileCache[npub]!.data);
          _pendingProfileRequests.remove(npub);
          _profileSubscriptionIds.remove(subscriptionId);
        }
      }
    } catch (e) {}
  }

  Future<void> _processNoteEvent(Map<String, dynamic> eventData, List<String> targetNpubs) async {
    final kind = eventData['kind'] as int;
    final author = eventData['pubkey'] as String;
    bool isRepost = kind == 6;

    Map<String, dynamic>? originalEventData;
    if (isRepost) {
      final contentRaw = eventData['content'];
      if (contentRaw is String && contentRaw.isNotEmpty) {
        try {
          originalEventData = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (e) {}
      }

      if (originalEventData == null) {
        String? originalEventId;
        for (var tag in eventData['tags']) {
          if (tag.length >= 2 && tag[0] == 'e') {
            originalEventId = tag[1] as String;
            break;
          }
        }
        if (originalEventId != null) {
          originalEventData = await _fetchEventById(originalEventId);
        }
      }

      if (originalEventData == null) {
        return;
      }

      eventData = originalEventData;
    }

    final noteId = eventData['id'] as String;
    final noteAuthor = eventData['pubkey'] as String;
    final noteContentRaw = eventData['content'];
    String noteContent = '';

    if (noteContentRaw is String) {
      noteContent = noteContentRaw;
    } else if (noteContentRaw is Map<String, dynamic>) {
      noteContent = jsonEncode(noteContentRaw);
    }

    final tags = eventData['tags'] as List<dynamic>;
    bool isReply = tags.any((tag) => tag.length >= 2 && tag[0] == 'e');

    if (eventIds.contains(noteId) || noteContent.trim().isEmpty) {
      return;
    }

    if (!isReply) {
      if (dataType == DataType.Feed &&
          targetNpubs.isNotEmpty &&
          !targetNpubs.contains(noteAuthor) &&
          (!isRepost || !targetNpubs.contains(author))) {
        return;
      }
    }

    if (isReply) {
      await _handleReplyEvent(eventData);
    } else {
      final authorProfile = await getCachedUserProfile(noteAuthor);
      Map<String, String>? repostedByProfile = isRepost ? await getCachedUserProfile(author) : null;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
          ((isRepost ? originalEventData!['created_at'] : eventData['created_at']) as int) * 1000);

      final newEvent = NoteModel(
        id: noteId,
        content: noteContent,
        author: noteAuthor,
        authorName: authorProfile['name'] ?? 'Anonymous',
        authorProfileImage: authorProfile['profileImage'] ?? '',
        timestamp: timestamp,
        isRepost: isRepost,
        repostedBy: isRepost ? author : null,
        repostedByName: isRepost ? (repostedByProfile?['name'] ?? 'Anonymous') : null,
        repostedByProfileImage: isRepost ? (repostedByProfile?['profileImage'] ?? '') : null,
      );

      notes.add(newEvent);
      notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      eventIds.add(noteId);
      await saveNotesToCache();
      onNewNote?.call(newEvent);
    }
  }

  Future<void> _handleReactionEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final reactionPubKey = eventData['pubkey'] as String;
      final reactionProfile = await getCachedUserProfile(reactionPubKey);
      String? noteId;
      for (var tag in eventData['tags']) {
        if (tag.length >= 2 && tag[0] == 'e') {
          noteId = tag[1] as String;
          break;
        }
      }
      if (noteId == null) return;
      final reaction = ReactionModel.fromEvent(eventData, reactionProfile);
      reactionsMap.putIfAbsent(noteId, () => []);
      if (!reactionsMap[noteId]!.any((r) => r.id == reaction.id)) {
        reactionsMap[noteId]!.add(reaction);
        await saveReactionsToCache();
        onReactionsUpdated?.call(noteId, reactionsMap[noteId]!);
        if (repliesMap.containsKey(noteId)) {
          fetchReactionsForNotes([noteId]);
        }
      }
    } catch (e) {}
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final replyPubKey = eventData['pubkey'] as String;
      final replyProfile = await getCachedUserProfile(replyPubKey);
      String? parentId;
      List<String> eTags = [];
      for (var tag in eventData['tags']) {
        if (tag.length >= 2 && tag[0] == 'e') {
          eTags.add(tag[1]);
        }
      }
      if (eTags.isNotEmpty) {
        parentId = eTags.last;
      }
      if (parentId == null || parentId.isEmpty) return;
      final reply = ReplyModel.fromEvent(eventData, replyProfile);
      repliesMap.putIfAbsent(parentId, () => []);
      if (!repliesMap[parentId]!.any((r) => r.id == reply.id)) {
        repliesMap[parentId]!.add(reply);
        await saveRepliesToCache();
        onRepliesUpdated?.call(parentId, repliesMap[parentId]!);
        fetchRepliesForNotes([reply.id]);
        fetchReactionsForNotes([reply.id]);
      }
    } catch (e) {}
  }

  Future<void> _handleProfileEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final author = eventData['pubkey'] as String;
      final contentRaw = eventData['content'];
      Map<String, dynamic> profileContent;
      if (contentRaw is String) {
        try {
          profileContent = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (e) {
          profileContent = {};
        }
      } else {
        profileContent = {};
      }

      final userName = profileContent['name'] as String? ?? 'Anonymous';
      final profileImage = profileContent['picture'] as String? ?? '';
      final about = profileContent['about'] as String? ?? '';
      final nip05 = profileContent['nip05'] as String? ?? '';
      final banner = profileContent['banner'] as String? ?? '';

      profileCache[author] = CachedProfile({
        'name': userName,
        'profileImage': profileImage,
        'about': about,
        'nip05': nip05,
        'banner': banner,
      }, DateTime.now());

      if (_pendingProfileRequests.containsKey(author)) {
        _pendingProfileRequests[author]?.complete(profileCache[author]!.data);
        _pendingProfileRequests.remove(author);
      }
    } catch (e) {}
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (_isClosed) {
      return {
        'name': 'Anonymous',
        'profileImage': '',
        'about': '',
        'nip05': '',
        'banner': '',
      };
    }

    final now = DateTime.now();

    if (profileCache.containsKey(npub)) {
      final cachedProfile = profileCache[npub]!;
      if (now.difference(cachedProfile.fetchedAt) < profileCacheTTL) {
        return cachedProfile.data;
      } else {
        profileCache.remove(npub);
      }
    }

    if (_pendingProfileRequests.containsKey(npub)) {
      return await _pendingProfileRequests[npub]!.future;
    }

    Completer<Map<String, String>> completer = Completer<Map<String, String>>();
    _pendingProfileRequests[npub] = completer;
    String subscriptionId = generateUUID();

    _profileSubscriptionIds[subscriptionId] = npub;

    final request = Request(subscriptionId, [
      Filter(authors: [npub], kinds: [0], limit: 1),
    ]);

    await Future.wait(_webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));

    Future.delayed(Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        profileCache[npub] = CachedProfile({
          'name': 'Anonymous',
          'profileImage': '',
          'about': '',
          'nip05': '',
          'banner': '',
        }, DateTime.now());
        completer.complete(profileCache[npub]!.data);
        _pendingProfileRequests.remove(npub);
        _profileSubscriptionIds.remove(subscriptionId);
      }
    });

    return completer.future;
  }

  Future<List<String>> getFollowingList(String npub) async {
    List<String> followingNpubs = [];
    await Future.wait(relayUrls.map((relayUrl) async {
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 5));
        if (_isClosed) {
          webSocket.close();
          return;
        }
        final request = Request(generateUUID(), [
          Filter(authors: [npub], kinds: [3], limit: 1000),
        ]);
        Completer<void> completer = Completer<void>();
        webSocket.listen((event) {
          final decodedEvent = jsonDecode(event);
          if (decodedEvent[0] == 'EVENT') {
            for (var tag in decodedEvent[2]['tags']) {
              if (tag.isNotEmpty && tag[0] == 'p') {
                followingNpubs.add(tag[1] as String);
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
      } catch (e) {}
    }));
    followingNpubs = followingNpubs.toSet().toList();
    return followingNpubs;
  }

  Future<void> fetchOlderNotes(List<String> targetNpubs, Function(NoteModel) onOlderNote) async {
    if (_isClosed || notes.isEmpty) return;
    final request = Request(generateUUID(), [
      Filter(
        authors: targetNpubs,
        kinds: [1, 6],
        limit: currentLimit,
        until: notes.last.timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
    ]);

    await Future.wait(_webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
  }

  void _startCheckingForNewData(List<String> targetNpubs) {
    _checkNewNotesTimer?.cancel();
    _checkNewNotesTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      Set<String> allParentIds = Set<String>.from(notes.map((note) => note.id));
      allParentIds.addAll(repliesMap.keys);
      fetchNotes(targetNpubs);
      _fetchProfilesBatch(targetNpubs);
    });
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;
    _checkNewNotesTimer?.cancel();

    try {
      if (_sendPortReadyCompleter.isCompleted) {
        _sendPort.send(IsolateMessage(MessageType.Error, 'close'));
      }
    } catch (e) {}

    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();

    await Future.wait(_webSockets.values.map((ws) async {
      await ws.close();
    }));
    _webSockets.clear();

    if (notesBox.isOpen) await notesBox.close();
    if (reactionsBox.isOpen) await reactionsBox.close();
    if (repliesBox.isOpen) await repliesBox.close();
  }

  Future<Map<String, dynamic>?> _fetchEventById(String eventId) async {
    if (_isClosed) return null;
    Completer<Map<String, dynamic>?> completer = Completer<Map<String, dynamic>?>();
    String subscriptionId = generateUUID();

    final request = Request(subscriptionId, [
      Filter(ids: [eventId], limit: 1),
    ]);

    StreamSubscription? sub;
    await Future.wait(_webSockets.values.map((webSocket) async {
      if (webSocket.readyState == WebSocket.open) {
        sub = webSocket.listen((event) {
          final decodedEvent = jsonDecode(event);
          if (decodedEvent[0] == 'EVENT' && decodedEvent[1] == subscriptionId) {
            Map<String, dynamic> eventData = decodedEvent[2] as Map<String, dynamic>;
            completer.complete(eventData);
            sub?.cancel();
          } else if (decodedEvent[0] == 'EOSE' && decodedEvent[1] == subscriptionId) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            sub?.cancel();
          }
        }, onError: (error) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          sub?.cancel();
        });

        webSocket.add(request.serialize());
      }
    }));

    return completer.future.timeout(Duration(seconds: 5), onTimeout: () {
      return null;
    });
  }

  void _handleNewNotes(dynamic data) {
    if (data is List<NoteModel>) {
      if (data.isNotEmpty) {
        notes.addAll(data);
        notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        onNewNote?.call(data.last);
        saveNotesToCache();
      }
    }
  }

  void _handleCacheLoad(dynamic data) {
    if (data is List<NoteModel>) {
      if (_onCacheLoad != null) {
        _onCacheLoad!(data);
        _onCacheLoad = null;
      }
    }
  }

  Future<void> _fetchProfilesForAllData() async {
    if (_isClosed) return;

    Set<String> allAuthors = notes.map((note) => note.author).toSet();

    for (var replies in repliesMap.values) {
      allAuthors.addAll(replies.map((reply) => reply.author));
    }

    for (var reactions in reactionsMap.values) {
      allAuthors.addAll(reactions.map((reaction) => reaction.author));
    }

    await _fetchProfilesBatch(allAuthors.toList());
  }
}
