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
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  Function(NoteModel)? onNewNote;
  Function(String, List<ReactionModel>)? onReactionsUpdated;
  Function(String, List<ReplyModel>)? onRepliesUpdated;

  List<NoteModel> notes = [];
  final Set<String> eventIds = {};
  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};

  final Map<String, CachedProfile> profileCache = {};

  final Map<String, WebSocket> _webSockets = {};
  bool isConnecting = false;
  Timer? _checkNewNotesTimer;
  int currentLimit = 75;

  final List<String> relayUrls = [
    'wss://relay.damus.io',
    'wss://relay.snort.social',
    'wss://nos.lol',
    'wss://untreu.me',
    'wss://vitor.nostr1.com',
    'wss://nostr.mom',
    'wss://nostr.bitcoiner.social',
  ];

  final Map<String, Completer<Map<String, String>>> _pendingProfileRequests = {};
  final Map<String, String> _profileSubscriptionIds = {};

  late Box notesBox;
  late Box reactionsBox;
  late Box repliesBox;

  bool _isInitialized = false;
  bool _isClosed = false;

  ReceivePort? _receivePort;
  Isolate? _isolate;
  late SendPort _sendPort;

  Function(List<NoteModel>)? _onCacheLoad;

  final Completer<void> _sendPortReadyCompleter = Completer<void>();

  final Uuid _uuid = const Uuid();

  final Duration profileCacheTTL = const Duration(minutes: 10);
  final Duration cacheCleanupInterval = const Duration(hours: 1);
  Timer? _cacheCleanupTimer;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  DataService({
    required this.npub,
    required this.dataType,
    this.onNewNote,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
  });

  int get connectedRelaysCount => _webSockets.length;

  Future<void> initialize() async {
    try {
      final openedBoxes = await Future.wait([
        Hive.openBox('notes_${dataType.toString()}_$npub'),
        Hive.openBox('reactions_${dataType.toString()}_$npub'),
        Hive.openBox('replies_${dataType.toString()}_$npub'),
      ]);

      notesBox = openedBoxes[0];
      reactionsBox = openedBoxes[1];
      repliesBox = openedBoxes[2];

      _isInitialized = true;

      await _initializeIsolate();
      _startCacheCleanup();
    } catch (e) {
      print('Error initializing DataService: $e');
      rethrow;
    }
  }

  Future<void> _initializeIsolate() async {
    try {
      _receivePort = ReceivePort();
      _isolate = await Isolate.spawn(_dataProcessorEntryPoint, _receivePort!.sendPort);

      _receivePort!.listen((message) {
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
              print('Isolate Error: ${message.data}');
              break;
          }
        }
      });
    } catch (e) {
      print('Error initializing isolate: $e');
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
      final List<NoteModel> parsedNotes = jsonData.map((j) => NoteModel.fromJson(j)).toList();
      sendPort.send(IsolateMessage(MessageType.CacheLoad, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.Error, e.toString()));
    }
  }

  static void _processNewNotes(String data, SendPort sendPort) {
    try {
      final List<dynamic> jsonData = json.decode(data);
      final List<NoteModel> parsedNotes = jsonData.map((j) => NoteModel.fromJson(j)).toList();
      sendPort.send(IsolateMessage(MessageType.NewNotes, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.Error, e.toString()));
    }
  }

  Future<void> initializeConnections() async {
    if (!_isInitialized) {
      await initialize();
    }

    final targetNpubs = dataType == DataType.Feed ? await getFollowingList(npub) : [npub];

    if (_isClosed) return;

    await connectToRelays(relayUrls, targetNpubs);
    await fetchNotes(targetNpubs, initialLoad: true);
  }

  Future<void> connectToRelays(List<String> relayList, List<String> targetNpubs) async {
    if (isConnecting || _isClosed) return;
    isConnecting = true;

    await Future.wait(relayList.map((relayUrl) async {
      if (_isClosed) return;
      final existingSocket = _webSockets[relayUrl];
      final closedOrNull = existingSocket == null || existingSocket.readyState == WebSocket.closed;

      if (closedOrNull) {
        try {
          final webSocket = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
          if (_isClosed) {
            await webSocket.close();
            return;
          }
          _webSockets[relayUrl] = webSocket;
          webSocket.listen(
            (event) => _handleEvent(event, targetNpubs),
            onDone: () {
              _webSockets.remove(relayUrl);
              _reconnectRelay(relayUrl, targetNpubs);
            },
            onError: (_) {
              _webSockets.remove(relayUrl);
              _reconnectRelay(relayUrl, targetNpubs);
            },
          );

          await _fetchProfilesBatch(targetNpubs);
          await _fetchReplies(webSocket, targetNpubs);
        } catch (e) {
          print('Error connecting to relay $relayUrl: $e');
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

    const int maxAttempts = 5;
    if (attempt > maxAttempts) return;

    final delaySeconds = _calculateBackoffDelay(attempt);
    Timer(Duration(seconds: delaySeconds), () async {
      if (_isClosed) return;
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
        if (_isClosed) {
          await webSocket.close();
          return;
        }
        _webSockets[relayUrl] = webSocket;
        webSocket.listen(
          (event) => _handleEvent(event, targetNpubs),
          onDone: () {
            _webSockets.remove(relayUrl);
            _reconnectRelay(relayUrl, targetNpubs, attempt + 1);
          },
          onError: (_) {
            _webSockets.remove(relayUrl);
            _reconnectRelay(relayUrl, targetNpubs, attempt + 1);
          },
        );
        await _fetchProfilesBatch(targetNpubs);
        await _fetchReplies(webSocket, targetNpubs);
      } catch (e) {
        print('Error reconnecting to relay $relayUrl: $e');
        _reconnectRelay(relayUrl, targetNpubs, attempt + 1);
      }
    });
  }

  int _calculateBackoffDelay(int attempt) {
    const baseDelay = 2;
    const maxDelay = 32;
    final delay = (baseDelay * (1 << (attempt - 1))).clamp(1, maxDelay);
    final jitter = Random().nextInt(2);
    return delay + jitter;
  }

  Future<void> fetchNotes(List<String> targetNpubs, {bool initialLoad = false}) async {
    if (_isClosed) return;
    DateTime? sinceTimestamp;

    if (!initialLoad && notes.isNotEmpty) {
      sinceTimestamp = notes.first.timestamp;
    }

    final filter = Filter(
      authors: targetNpubs,
      kinds: [1, 6],
      limit: currentLimit,
      since: sinceTimestamp != null ? sinceTimestamp.millisecondsSinceEpoch ~/ 1000 : null,
    );

    final request = Request(generateUUID(), [filter]);

    await Future.wait(_webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
  }

  Future<void> saveNotesToCache() async {
    if (notesBox.isOpen) {
      try {
        final notesJson = notes.map((note) => note.toJson()).toList();
        await notesBox.put('notes_json', json.encode(notesJson));
      } catch (e) {
        print('Error saving notes to cache: $e');
      }
    }
  }

  Future<void> loadNotesFromCache(Function(List<NoteModel>) onLoad) async {
    if (!notesBox.isOpen) return;
    final cachedData = notesBox.get('notes_json', defaultValue: '');

    if (cachedData is! String) {
      try {
        final jsonString = json.encode(cachedData);
        _onCacheLoad = onLoad;
        await _sendPortReadyCompleter.future;
        _sendPort.send(IsolateMessage(MessageType.CacheLoad, jsonString));
      } catch (e) {
        print('Error loading notes from cache: $e');
      }
    } else {
      final jsonString = cachedData;
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
        final reactionsJson = reactionsMap.map((key, value) {
          return MapEntry(key, value.map((r) => r.toJson()).toList());
        });
        await reactionsBox.put('reactions', json.encode(reactionsJson));
      } catch (e) {
        print('Error saving reactions to cache: $e');
      }
    }
  }

  Future<void> loadReactionsFromCache() async {
    if (!reactionsBox.isOpen) return;
    try {
      final cachedReactionsString = reactionsBox.get('reactions');
      if (cachedReactionsString is String && cachedReactionsString.isNotEmpty) {
        final cachedReactionsJson = json.decode(cachedReactionsString) as Map<String, dynamic>;
        cachedReactionsJson.forEach((noteId, value) {
          final reactionsList = value as List<dynamic>;
          reactionsMap[noteId] = reactionsList.map((rJson) {
            return ReactionModel.fromJson(Map<String, dynamic>.from(rJson as Map));
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading reactions from cache: $e');
    }

    await _fetchProfilesForAllData();
  }

  Future<void> saveRepliesToCache() async {
    if (repliesBox.isOpen) {
      try {
        final repliesJson = repliesMap.map((key, value) {
          return MapEntry(key, value.map((r) => r.toJson()).toList());
        });
        await repliesBox.put('replies', json.encode(repliesJson));
      } catch (e) {
        print('Error saving replies to cache: $e');
      }
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (!repliesBox.isOpen) return;
    try {
      final cachedRepliesString = repliesBox.get('replies');
      if (cachedRepliesString is String && cachedRepliesString.isNotEmpty) {
        final cachedRepliesJson = json.decode(cachedRepliesString) as Map<String, dynamic>;
        cachedRepliesJson.forEach((noteId, value) {
          final repliesList = value as List<dynamic>;
          repliesMap[noteId] = repliesList.map((rJson) {
            return ReplyModel.fromJson(Map<String, dynamic>.from(rJson as Map));
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading replies from cache: $e');
    }

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
    final parentIds = notes.map((n) => n.id).toSet().union(repliesMap.keys.toSet()).toList();

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
        final eventData = decodedEvent[2] as Map<String, dynamic>;
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
    } catch (e) {
      print('Error handling event: $e');
    }
  }

  Future<void> _processNoteEvent(Map<String, dynamic> eventData, List<String> targetNpubs) async {
    final kind = eventData['kind'] as int;
    final author = eventData['pubkey'] as String;
    final isRepost = (kind == 6);

    Map<String, dynamic>? originalEventData;
    if (isRepost) {
      final contentRaw = eventData['content'];
      if (contentRaw is String && contentRaw.isNotEmpty) {
        try {
          originalEventData = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (_) {}
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
    final isReply = tags.any((tag) => tag.length >= 2 && tag[0] == 'e');

    if (eventIds.contains(noteId) || noteContent.trim().isEmpty) {
      return;
    }

    if (!isReply && dataType == DataType.Feed) {
      if (targetNpubs.isNotEmpty && !targetNpubs.contains(noteAuthor)) {
        if (!isRepost || !targetNpubs.contains(author)) {
          return;
        }
      }
    }

    if (isReply) {
      await _handleReplyEvent(eventData);
    } else {
      final authorProfile = await getCachedUserProfile(noteAuthor);
      final repostedByProfile = isRepost ? await getCachedUserProfile(author) : null;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        (eventData['created_at'] as int) * 1000,
      );

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
    } catch (e) {
      print('Error handling reaction event: $e');
    }
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final replyPubKey = eventData['pubkey'] as String;
      final replyProfile = await getCachedUserProfile(replyPubKey);

      String? parentId;
      final eTags = <String>[];
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
    } catch (e) {
      print('Error handling reply event: $e');
    }
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
        } catch (_) {
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
    } catch (e) {
      print('Error handling profile event: $e');
    }
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
      return _pendingProfileRequests[npub]!.future;
    }

    final completer = Completer<Map<String, String>>();
    _pendingProfileRequests[npub] = completer;
    final subscriptionId = generateUUID();

    _profileSubscriptionIds[subscriptionId] = npub;

    final request = Request(subscriptionId, [
      Filter(authors: [npub], kinds: [0], limit: 1),
    ]);

    await Future.wait(_webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));

    Future.delayed(const Duration(seconds: 5), () {
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
    final followingNpubs = <String>[];

    await Future.wait(relayUrls.map((relayUrl) async {
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
        if (_isClosed) {
          await webSocket.close();
          return;
        }
        final request = Request(generateUUID(), [
          Filter(authors: [npub], kinds: [3], limit: 1000),
        ]);
        final completer = Completer<void>();

        webSocket.listen(
          (event) {
            final decodedEvent = jsonDecode(event);
            if (decodedEvent[0] == 'EVENT') {
              for (var tag in decodedEvent[2]['tags']) {
                if (tag.isNotEmpty && tag[0] == 'p') {
                  followingNpubs.add(tag[1] as String);
                }
              }
              completer.complete();
            }
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete();
          },
        );

        webSocket.add(request.serialize());
        await completer.future.timeout(const Duration(seconds: 5), onTimeout: () async {
          await webSocket.close();
        });
        await webSocket.close();
      } catch (e) {
        print('Error fetching following list from $relayUrl: $e');
      }
    }));

    return followingNpubs.toSet().toList();
  }

  Future<void> fetchOlderNotes(List<String> targetNpubs, Function(NoteModel) onOlderNote) async {
    if (_isClosed || notes.isEmpty) return;

    final lastNote = notes.last;
    final request = Request(generateUUID(), [
      Filter(
        authors: targetNpubs,
        kinds: [1, 6],
        limit: currentLimit,
        until: lastNote.timestamp.millisecondsSinceEpoch ~/ 1000,
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
    _checkNewNotesTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      fetchNotes(targetNpubs);
      _fetchProfilesBatch(targetNpubs);
    });
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;

    _checkNewNotesTimer?.cancel();
    _cacheCleanupTimer?.cancel();

    try {
      if (_sendPortReadyCompleter.isCompleted) {
        _sendPort.send(IsolateMessage(MessageType.Error, 'close'));
      }
    } catch (e) {
      print('Error sending close message to isolate: $e');
    }

    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();

    await Future.wait(_webSockets.values.map((ws) async {
      try {
        await ws.close();
      } catch (e) {
        print('Error closing WebSocket: $e');
      }
    }));
    _webSockets.clear();

    try {
      if (notesBox.isOpen) await notesBox.close();
      if (reactionsBox.isOpen) await reactionsBox.close();
      if (repliesBox.isOpen) await repliesBox.close();
    } catch (e) {
      print('Error closing Hive boxes: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchEventById(String eventId) async {
    if (_isClosed) return null;

    final completer = Completer<Map<String, dynamic>?>();
    final subscriptionId = generateUUID();
    final request = Request(subscriptionId, [
      Filter(ids: [eventId], limit: 1),
    ]);

    StreamSubscription? subscription;
    await Future.wait(_webSockets.values.map((webSocket) async {
      if (webSocket.readyState == WebSocket.open) {
        subscription = webSocket.listen((event) {
          final decodedEvent = jsonDecode(event);
          if (decodedEvent[0] == 'EVENT' && decodedEvent[1] == subscriptionId) {
            final eventData = decodedEvent[2] as Map<String, dynamic>;
            completer.complete(eventData);
            subscription?.cancel();
          } else if (decodedEvent[0] == 'EOSE' && decodedEvent[1] == subscriptionId) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            subscription?.cancel();
          }
        }, onError: (_) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          subscription?.cancel();
        });

        webSocket.add(request.serialize());
      }
    }));

    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
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
      _onCacheLoad?.call(data);
      _onCacheLoad = null;
    }
  }

  Future<void> _fetchProfilesForAllData() async {
    if (_isClosed) return;

    final allAuthors = <String>{};
    allAuthors.addAll(notes.map((n) => n.author));
    for (var repList in repliesMap.values) {
      allAuthors.addAll(repList.map((r) => r.author));
    }
    for (var reactList in reactionsMap.values) {
      allAuthors.addAll(reactList.map((r) => r.author));
    }

    await _fetchProfilesBatch(allAuthors.toList());
  }

  void _startCacheCleanup() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(cacheCleanupInterval, (timer) async {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      final now = DateTime.now();
      profileCache.removeWhere(
        (key, cachedProfile) => now.difference(cachedProfile.fetchedAt) > profileCacheTTL,
      );
    });
  }

  Future<void> shareNote(String noteContent) async {
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found. Please log in again.');
      }

      final event = Event.from(
        kind: 1,
        tags: [],
        content: noteContent,
        privkey: privateKey,
      );

      final serializedEvent = event.serialize();

      for (var relayUrl in _webSockets.keys) {
        final webSocket = _webSockets[relayUrl];
        if (webSocket != null && webSocket.readyState == WebSocket.open) {
          webSocket.add(serializedEvent);
        }
      }
    } catch (e) {
      print('Error sharing note: $e');
      rethrow;
    }
  }
}
