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

enum DataType { Feed, Profile, Note }
enum MessageType { NewNotes, CacheLoad, Error, Close }

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
  final Function(String, int)? onReactionCountUpdated;
  final Function(String, int)? onReplyCountUpdated;
  List<NoteModel> notes = [];
  final Set<String> eventIds = {};
  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Map<String, CachedProfile> profileCache = {};
  final List<String> relayUrls = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.primal.net',
    'wss://vitor.nostr1.com',
    'wss://eu.purplerelay.com',
  ];
  final Map<String, WebSocket> _webSockets = {};
  bool isConnecting = false;
  Timer? _checkNewNotesTimer;
  int currentLimit = 75;
  final Map<String, Completer<Map<String, String>>> _pendingProfileRequests = {};
  final Map<String, String> _profileSubscriptionIds = {};
  Box<NoteModel>? notesBox;
  Box<ReactionModel>? reactionsBox;
  Box<ReplyModel>? repliesBox;
  bool _isInitialized = false;
  bool _isClosed = false;
  late ReceivePort _receivePort;
  late Isolate _isolate;
  late SendPort _sendPort;
  Function(List<NoteModel>)? _onCacheLoad;
  final Completer<void> _sendPortReadyCompleter = Completer<void>();
  final Uuid _uuid = Uuid();
  final Duration profileCacheTTL = Duration(hours: 24);
  final Duration cacheCleanupInterval = Duration(hours: 12);
  Timer? _cacheCleanupTimer;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  DataService({
    required this.npub,
    required this.dataType,
    this.onNewNote,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
    this.onReactionCountUpdated,
    this.onReplyCountUpdated,
  });

  int get connectedRelaysCount => _webSockets.length;

  Future<void> initialize() async {
    try {
      await Future.wait([
        _openHiveBox<NoteModel>('notes_${dataType.toString()}_$npub').then((box) {
          notesBox = box;
          print('Hive notes box opened successfully.');
        }),
        _openHiveBox<ReactionModel>('reactions_${dataType.toString()}_$npub').then((box) {
          reactionsBox = box;
          print('Hive reactions box opened successfully.');
        }),
        _openHiveBox<ReplyModel>('replies_${dataType.toString()}_$npub').then((box) {
          repliesBox = box;
          print('Hive replies box opened successfully.');
        }),
      ]);
      _isInitialized = true;
      await _initializeIsolate();
      _startCacheCleanup();
    } catch (e) {
      print('Error during DataService initialization: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<Box<T>> _openHiveBox<T>(String boxName) async {
    return await Hive.openBox<T>(boxName);
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
              print('Isolate error: ${message.data}');
              break;
            case MessageType.Close:
              print('Isolate received close message.');
              break;
          }
        }
      });
      print('Isolate initialized successfully.');
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
          case MessageType.Close:
            isolateReceivePort.close();
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
      print('DataService is not initialized. Call initialize() first.');
      return;
    }
    List<String> targetNpubs = dataType == DataType.Feed
        ? await getFollowingList(npub)
        : [npub];
    if (_isClosed) return;
    await _connectToRelays(relayUrls, targetNpubs);
    await fetchNotes(targetNpubs, initialLoad: true);
    await Future.wait([
      loadReactionsFromCache(),
      loadRepliesFromCache(),
    ]);
    await _subscribeToAllReactions();
  }

  Future<void> _connectToRelays(List<String> relayList, List<String> targetNpubs) async {
    if (isConnecting || _isClosed) return;
    isConnecting = true;
    await Future.wait(relayList.map<Future<void>>((relayUrl) async {
      if (_isClosed) {
        return;
      }
      if (!_webSockets.containsKey(relayUrl) ||
          _webSockets[relayUrl]?.readyState == WebSocket.closed) {
        try {
          final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 1));
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
            onError: (error) {
              _webSockets.remove(relayUrl);
              _reconnectRelay(relayUrl, targetNpubs);
            },
          );
          await Future.wait([
            _fetchProfilesBatch(targetNpubs),
            _fetchReplies(webSocket, targetNpubs),
            _fetchReactions(webSocket, targetNpubs),
          ]);
          print('Connected to relay: $relayUrl');
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
    final int delaySeconds = _calculateBackoffDelay(attempt);
    Timer(Duration(seconds: delaySeconds), () async {
      if (_isClosed) return;
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 1));
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
          onError: (error) {
            _webSockets.remove(relayUrl);
            _reconnectRelay(relayUrl, targetNpubs, attempt + 1);
          },
        );
        await Future.wait([
          _fetchProfilesBatch(targetNpubs),
          _fetchReplies(webSocket, targetNpubs),
          _fetchReactions(webSocket, targetNpubs),
        ]);
        print('Reconnected to relay: $relayUrl');
      } catch (e) {
        print('Error reconnecting to relay $relayUrl (Attempt $attempt): $e');
        _reconnectRelay(relayUrl, targetNpubs, attempt + 1);
      }
    });
  }

  int _calculateBackoffDelay(int attempt) {
    final int baseDelay = 2;
    final int maxDelay = 32;
    final int delay = (baseDelay * pow(2, attempt - 1)).toInt().clamp(1, maxDelay);
    final int jitter = Random().nextInt(2);
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
    await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
    print('Fetched notes with filter: $filter');
  }

  Future<void> saveNotesToCache() async {
    if (notesBox != null && notesBox!.isOpen) {
      try {
        final Map<String, NoteModel> notesMap = {for (var note in notes) note.id: note};
        await notesBox!.putAll(notesMap);
        print('Notes saved to cache successfully.');
      } catch (e) {
        print('Error saving notes to cache: $e');
      }
    } else {
      print('Error saving notes to cache: notesBox is not initialized or not open.');
    }
  }

  Future<void> loadNotesFromCache(Function(List<NoteModel>) onLoad) async {
    if (notesBox == null || !notesBox!.isOpen) {
      print('Notes box is not initialized or not open.');
      return;
    }
    try {
      final allNotes = notesBox!.values.cast<NoteModel>().toList();
      if (allNotes.isEmpty) {
        print('No notes found in cache.');
        return;
      }
      for (var note in allNotes) {
        if (!eventIds.contains(note.id)) {
          notes.add(note);
          eventIds.add(note.id);
        }
      }
      onLoad(allNotes);
      print('Cache loaded with ${allNotes.length} notes.');
      List<String> cachedEventIds = allNotes.map((note) => note.id).toList();
      await Future.wait([
        fetchReactionsForEvents(cachedEventIds),
        fetchRepliesForEvents(cachedEventIds),
      ]);
    } catch (e) {
      print('Error loading notes from cache: $e');
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
    await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
    print('Sent profile fetch request for ${uniqueNpubs.length} authors.');
  }

  Future<void> _fetchReactions(WebSocket webSocket, List<String> targetNpubs) async {
    if (_isClosed) return;
    final eventIdsForReactions = notes.map((note) => note.id).toSet().toList();
    if (eventIdsForReactions.isEmpty) return;
    final request = Request(generateUUID(), [
      Filter(
        kinds: [7],
        e: eventIdsForReactions,
        limit: 1000,
      ),
    ]);
    webSocket.add(request.serialize());
    print('Sent reaction fetch request for ${eventIdsForReactions.length} event IDs.');
  }

  Future<void> _fetchReplies(WebSocket webSocket, List<String> targetNpubs) async {
    if (_isClosed) return;
    final parentEventIds = notes.map((note) => note.id).toSet().toList();
    if (parentEventIds.isEmpty) return;
    final request = Request(generateUUID(), [
      Filter(
        kinds: [1],
        e: parentEventIds,
        limit: 1000,
      ),
    ]);
    webSocket.add(request.serialize());
    print('Sent reply fetch request for ${parentEventIds.length} parent event IDs.');
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {
    if (_isClosed) return;
    try {
      final decodedEvent = jsonDecode(event);
      if (decodedEvent[0] == 'EVENT') {
        Map<String, dynamic> eventData = decodedEvent[2] as Map<String, dynamic>;
        final kind = eventData['kind'] as int;
        if (kind == 0) {
          await _handleProfileEvent(eventData);
        } else if (kind == 1 || kind == 6) {
          await _processNoteEvent(eventData, targetNpubs);
        } else if (kind == 7) {
          await _handleReactionEvent(eventData);
        }
      }
    } catch (e) {
      print('Error handling event: $e');
    }
  }

  Future<void> _processNoteEvent(Map<String, dynamic> eventData, List<String> targetNpubs) async {
    final kind = eventData['kind'] as int;
    final author = eventData['pubkey'] as String;
    bool isRepost = kind == 6;
    Map<String, dynamic>? originalEventData;
    DateTime? repostTimestamp;
    if (isRepost) {
      repostTimestamp = DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000);
      final contentRaw = eventData['content'];
      if (contentRaw is String && contentRaw.isNotEmpty) {
        try {
          originalEventData = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (e) {
          originalEventData = null;
        }
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
    final eventId = eventData['id'] as String?;
    if (eventId == null) {
      print('Event ID is null.');
      return;
    }
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
    if (eventIds.contains(eventId) || noteContent.trim().isEmpty) {
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
          (eventData['created_at'] as int) * 1000);
      final newEvent = NoteModel(
        id: eventId,
        content: noteContent,
        author: noteAuthor,
        authorName: authorProfile['name'] ?? 'Anonymous',
        authorProfileImage: authorProfile['profileImage'] ?? '',
        timestamp: timestamp,
        isRepost: isRepost,
        repostedBy: isRepost ? author : null,
        repostedByName: isRepost ? (repostedByProfile?['name'] ?? 'Anonymous') : null,
        repostedByProfileImage: isRepost ? (repostedByProfile?['profileImage'] ?? '') : null,
        repostTimestamp: repostTimestamp,
      );
      if (!eventIds.contains(newEvent.id)) {
        notes.add(newEvent);
        eventIds.add(newEvent.id);
        await notesBox!.put(newEvent.id, newEvent);
        _sortNotes();
        onNewNote?.call(newEvent);
        print('New note added (unique by eventId) and saved to cache: ${newEvent.id}');
        await Future.wait([
          fetchReactionsForEvents([newEvent.id]),
          fetchRepliesForEvents([newEvent.id]),
        ]);
        await _subscribeToAllReactions();
      }
    }
  }

  void _sortNotes() {
    notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> _handleReactionEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final reactionPubKey = eventData['pubkey'] as String;
      final reactionProfile = await getCachedUserProfile(reactionPubKey);
      String? targetEventId;
      for (var tag in eventData['tags']) {
        if (tag.length >= 2 && tag[0] == 'e') {
          targetEventId = tag[1] as String;
          break;
        }
      }
      if (targetEventId == null) return;
      final reaction = ReactionModel.fromEvent(eventData, reactionProfile);
      reactionsMap.putIfAbsent(targetEventId, () => []);
      if (!reactionsMap[targetEventId]!.any((r) => r.id == reaction.id)) {
        reactionsMap[targetEventId]!.add(reaction);
        onReactionsUpdated?.call(targetEventId, reactionsMap[targetEventId]!);
        print('Reaction updated for event $targetEventId: ${reaction.content}');
        var reactionCount = reactionsMap[targetEventId]!.length;
        onReactionCountUpdated?.call(targetEventId, reactionCount);
        await reactionsBox?.put(reaction.id, reaction);
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
      String? parentEventId;
      List<String> eTags = [];
      for (var tag in eventData['tags']) {
        if (tag.length >= 2 && tag[0] == 'e') {
          eTags.add(tag[1]);
        }
      }
      if (eTags.isNotEmpty) {
        parentEventId = eTags.last;
      }
      if (parentEventId == null || parentEventId.isEmpty) return;
      final reply = ReplyModel.fromEvent(eventData, replyProfile);
      repliesMap.putIfAbsent(parentEventId, () => []);
      if (!repliesMap[parentEventId]!.any((r) => r.id == reply.id)) {
        repliesMap[parentEventId]!.add(reply);
        onRepliesUpdated?.call(parentEventId, repliesMap[parentEventId]!);
        print('Reply updated for event $parentEventId: ${reply.content}');
        var replyCount = repliesMap[parentEventId]!.length;
        onReplyCountUpdated?.call(parentEventId, replyCount);
        await repliesBox?.put(reply.id, reply);
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
      if (contentRaw is String && contentRaw.isNotEmpty) {
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
    } catch (e) {
      print('Error handling profile event: $e');
    }
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (_isClosed) {
      return _defaultProfile();
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
    await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
    print('Sent profile fetch request for npub: $npub');
    try {
      return await completer.future.timeout(Duration(seconds: 1), onTimeout: () => _defaultProfile());
    } catch (e) {
      return _defaultProfile();
    }
  }

  Map<String, String> _defaultProfile() {
    return {
      'name': 'Anonymous',
      'profileImage': '',
      'about': '',
      'nip05': '',
      'banner': '',
    };
  }

  Future<List<String>> getFollowingList(String npub) async {
    List<String> followingNpubs = [];
    final limitedRelayUrls = relayUrls.take(3).toList();
    await Future.wait(limitedRelayUrls.map<Future<void>>((relayUrl) async {
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 1));
        if (_isClosed) {
          await webSocket.close();
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
        await completer.future.timeout(Duration(seconds: 1), onTimeout: () async {
          await webSocket.close();
        });
        await webSocket.close();
      } catch (e) {
        print('Error fetching following list from $relayUrl: $e');
      }
    }));
    followingNpubs = followingNpubs.toSet().toList();
    print('Fetched ${followingNpubs.length} following npubs.');
    return followingNpubs;
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
    await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
    print('Sent older notes fetch request.');
  }

  void _startCheckingForNewData(List<String> targetNpubs) {
    _checkNewNotesTimer?.cancel();
    _checkNewNotesTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      fetchNotes(targetNpubs);
      _fetchProfilesBatch(targetNpubs);
    });
    print('Started periodic data fetching every 30 seconds.');
  }

  Future<void> _subscribeToAllReactions() async {
    if (_isClosed) return;
    String subscriptionId = generateUUID();
    List<String> allEventIds = notes.map((note) => note.id).toList();
    if (allEventIds.isEmpty) return;
    final filter = Filter(
      kinds: [7],
      e: allEventIds,
      limit: 1000,
    );
    final request = Request(subscriptionId, [filter]);
    await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
    print(
        'Subscribed to reactions for ${allEventIds.length} events with subscription ID: $subscriptionId');
  }

  Future<void> _updateReactionSubscription() async {
    await _subscribeToAllReactions();
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;
    _checkNewNotesTimer?.cancel();
    _cacheCleanupTimer?.cancel();
    try {
      if (_sendPortReadyCompleter.isCompleted) {
        _sendPort.send(IsolateMessage(MessageType.Close, 'close'));
      }
    } catch (e) {
      print('Error sending close message to isolate: $e');
    }
    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
    await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
      await ws.close();
    }));
    _webSockets.clear();
    await Future.wait([
      if (notesBox != null && notesBox!.isOpen) notesBox!.close(),
      if (reactionsBox != null && reactionsBox!.isOpen) reactionsBox!.close(),
      if (repliesBox != null && repliesBox!.isOpen) repliesBox!.close(),
    ]);
    print('All connections closed and boxes are closed.');
  }

  Future<Map<String, dynamic>?> _fetchEventById(String eventId) async {
    if (_isClosed) return null;
    Completer<Map<String, dynamic>?> completer = Completer<Map<String, dynamic>?>();
    String subscriptionId = generateUUID();
    final request = Request(subscriptionId, [
      Filter(ids: [eventId], limit: 1),
    ]);
    StreamSubscription? subscription;
    await Future.wait(_webSockets.values.map<Future<void>>((webSocket) async {
      if (webSocket.readyState == WebSocket.open) {
        subscription = webSocket.listen((event) {
          final decodedEvent = jsonDecode(event);
          if (decodedEvent[0] == 'EVENT' && decodedEvent[1] == subscriptionId) {
            Map<String, dynamic> eventData = decodedEvent[2] as Map<String, dynamic>;
            completer.complete(eventData);
            subscription?.cancel();
          } else if (decodedEvent[0] == 'EOSE' && decodedEvent[1] == subscriptionId) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            subscription?.cancel();
          }
        }, onError: (error) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          subscription?.cancel();
        });
        webSocket.add(request.serialize());
      }
    }));
    return completer.future.timeout(Duration(seconds: 1), onTimeout: () {
      print('Timeout while fetching event by ID: $eventId');
      return null;
    });
  }

  Future<void> _handleNewNotes(dynamic data) async {
    if (data is List<NoteModel>) {
      if (data.isNotEmpty) {
        for (var note in data) {
          if (!eventIds.contains(note.id)) {
            notes.add(note);
            eventIds.add(note.id);
            await notesBox!.put(note.id, note);
          }
        }
        _sortNotes();
        onNewNote?.call(data.last);
        print('Handled new notes: ${data.length} notes added.');
        List<String> newEventIds = data.map((note) => note.id).toList();
        await Future.wait([
          fetchReactionsForEvents(newEventIds),
          fetchRepliesForEvents(newEventIds),
        ]);
        await _updateReactionSubscription();
      }
    }
  }

  void _handleCacheLoad(dynamic data) {
    if (data is List<NoteModel>) {
      if (_onCacheLoad != null) {
        _onCacheLoad!(data);
        _onCacheLoad = null;
        print('Cache loaded with ${data.length} notes.');
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
    print('Fetched profiles for all authors.');
  }

  void _startCacheCleanup() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(cacheCleanupInterval, (timer) async {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      final now = DateTime.now();
      profileCache.removeWhere((key, cachedProfile) =>
          now.difference(cachedProfile.fetchedAt) > profileCacheTTL);
      reactionsMap.forEach((eventId, reactions) {
        reactions.removeWhere((reaction) =>
            now.difference(reaction.fetchedAt) > profileCacheTTL);
      });
      repliesMap.forEach((eventId, replies) {
        replies.removeWhere((reply) =>
            now.difference(reply.fetchedAt) > profileCacheTTL);
      });
      await Future.wait([
        if (reactionsBox != null && reactionsBox!.isOpen)
          reactionsBox!.deleteAll(reactionsBox!.keys.where((key) {
            final reaction = reactionsBox!.get(key);
            return reaction != null && now.difference(reaction.fetchedAt) > profileCacheTTL;
          })),
        if (repliesBox != null && repliesBox!.isOpen)
          repliesBox!.deleteAll(repliesBox!.keys.where((key) {
            final reply = repliesBox!.get(key);
            return reply != null && now.difference(reply.fetchedAt) > profileCacheTTL;
          })),
      ]);
      print('Performed cache cleanup.');
    });
    print('Started cache cleanup timer.');
  }

  Future<void> shareNote(String noteContent) async {
    if (_isClosed) {
      print('Cannot share note: DataService is closed.');
      return;
    }
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
      await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
        if (ws.readyState == WebSocket.open) {
          ws.add(serializedEvent);
        }
      }));
      print('Note shared successfully.');
    } catch (e) {
      print('Error sharing note: $e');
      throw e;
    }
  }

  Future<void> fetchReactionsForEvents(List<String> eventIdsToFetch) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(
        kinds: [7],
        e: eventIdsToFetch,
        limit: 1000,
      ),
    ]);
    await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
    print('Fetched reactions for events: ${eventIdsToFetch.length}');
  }

  Future<void> fetchRepliesForEvents(List<String> parentEventIds) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(
        kinds: [1],
        e: parentEventIds,
        limit: 1000,
      ),
    ]);
    await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
      if (ws.readyState == WebSocket.open) {
        ws.add(request.serialize());
      }
    }));
    print('Fetched replies for events: ${parentEventIds.length}');
  }

  Future<void> sendReaction(String targetEventId, String reactionContent) async {
    if (_isClosed) {
      print('Cannot send reaction: DataService is closed.');
      return;
    }
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found. Please log in again.');
      }
      final event = Event.from(
        kind: 7,
        tags: [
          ['e', targetEventId],
        ],
        content: reactionContent,
        privkey: privateKey,
      );
      final serializedEvent = event.serialize();
      await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
        if (ws.readyState == WebSocket.open) {
          ws.add(serializedEvent);
        }
      }));
      print('Reaction event sent to WebSocket successfully.');
    } catch (e) {
      print('Error sending reaction: $e');
      throw e;
    }
  }

  Future<void> sendReply(String parentEventId, String replyContent) async {
    if (_isClosed) {
      print('Cannot send reply: DataService is closed.');
      return;
    }
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found. Please log in again.');
      }
      String? noteAuthor = notes.firstWhere(
        (note) => note.id == parentEventId,
        orElse: () => throw Exception('Event not found for reply.'),
      ).author;
      final event = Event.from(
        kind: 1,
        tags: [
          ['e', parentEventId, '', 'root'],
          ['p', noteAuthor]
        ],
        content: replyContent,
        privkey: privateKey,
      );
      final serializedEvent = event.serialize();
      await Future.wait(_webSockets.values.map<Future<void>>((ws) async {
        if (ws.readyState == WebSocket.open) {
          ws.add(serializedEvent);
        }
      }));
      print('Reply event sent to WebSocket successfully.');
    } catch (e) {
      print('Error sending reply: $e');
      throw e;
    }
  }

  Future<void> loadReactionsFromCache() async {
    if (reactionsBox == null || !reactionsBox!.isOpen) {
      print('Reactions box is not initialized or not open.');
      return;
    }
    try {
      final allReactions = reactionsBox!.values.cast<ReactionModel>().toList();
      if (allReactions.isEmpty) {
        print('No reactions found in cache.');
        return;
      }
      for (var reaction in allReactions) {
        reactionsMap.putIfAbsent(reaction.targetEventId, () => []);
        if (!reactionsMap[reaction.targetEventId]!
            .any((r) => r.id == reaction.id)) {
          reactionsMap[reaction.targetEventId]!.add(reaction);
          onReactionsUpdated?.call(
              reaction.targetEventId, reactionsMap[reaction.targetEventId]!);
        }
      }
      print('Reactions cache loaded with ${allReactions.length} reactions.');
    } catch (e) {
      print('Error loading reactions from cache: $e');
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (repliesBox == null || !repliesBox!.isOpen) {
      print('Replies box is not initialized or not open.');
      return;
    }
    try {
      final allReplies = repliesBox!.values.cast<ReplyModel>().toList();
      if (allReplies.isEmpty) {
        print('No replies found in cache.');
        return;
      }
      for (var reply in allReplies) {
        repliesMap.putIfAbsent(reply.parentEventId, () => []);
        if (!repliesMap[reply.parentEventId]!
            .any((r) => r.id == reply.id)) {
          repliesMap[reply.parentEventId]!.add(reply);
        }
      }
      print('Replies cache loaded with ${allReplies.length} replies.');
    } catch (e) {
      print('Error loading replies from cache: $e');
    }
  }
}
