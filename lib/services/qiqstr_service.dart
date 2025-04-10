import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'package:hive/hive.dart';
import 'package:nostr/nostr.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:typed_data';
import '../models/user_model.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/following_model.dart';
import '../models/zap_model.dart';
import '../services/bolt11_decoder.dart';

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

class WebSocketManager {
  final List<String> relayUrls;
  final Map<String, WebSocket> _webSockets = {};
  final Duration connectionTimeout;
  bool _isClosed = false;

  WebSocketManager(
      {required this.relayUrls,
      this.connectionTimeout = const Duration(seconds: 1)});

  List<WebSocket> get activeSockets => _webSockets.values.toList();
  bool get isConnected => _webSockets.isNotEmpty;

  Future<void> connectRelays(List<String> targetNpubs,
      {Function(dynamic event, String relayUrl)? onEvent,
      Function(String relayUrl)? onDisconnected}) async {
    await Future.wait(relayUrls.map((relayUrl) async {
      if (_isClosed) return;
      if (!_webSockets.containsKey(relayUrl) ||
          _webSockets[relayUrl]?.readyState == WebSocket.closed) {
        try {
          final rawWs =
              await WebSocket.connect(relayUrl).timeout(connectionTimeout);
          final wsBroadcast = rawWs.asBroadcastStream();
          _webSockets[relayUrl] = rawWs;
          wsBroadcast.listen((event) => onEvent?.call(event, relayUrl),
              onDone: () {
            _webSockets.remove(relayUrl);
            onDisconnected?.call(relayUrl);
          }, onError: (error) {
            _webSockets.remove(relayUrl);
            onDisconnected?.call(relayUrl);
          });
        } catch (e) {
          print('Error connecting to relay $relayUrl: $e');
          _webSockets.remove(relayUrl);
        }
      }
    }));
  }

  Future<void> executeOnActiveSockets(
      FutureOr<void> Function(WebSocket ws) action) async {
    final futures = _webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) await action(ws);
    });
    await Future.wait(futures);
  }

  Future<void> broadcast(String message) async {
    await executeOnActiveSockets((ws) async => ws.add(message));
  }

  void reconnectRelay(String relayUrl, List<String> targetNpubs,
      {int attempt = 1, Function(String relayUrl)? onReconnected}) {
    if (_isClosed) return;
    const int maxAttempts = 5;
    if (attempt > maxAttempts) return;

    int delaySeconds = _calculateBackoffDelay(attempt);
    Timer(Duration(seconds: delaySeconds), () async {
      if (_isClosed) return;
      try {
        final rawWs =
            await WebSocket.connect(relayUrl).timeout(connectionTimeout);
        final wsBroadcast = rawWs.asBroadcastStream();
        if (_isClosed) {
          await rawWs.close();
          return;
        }
        _webSockets[relayUrl] = rawWs;
        wsBroadcast.listen((event) {}, onDone: () {
          _webSockets.remove(relayUrl);
          reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
        }, onError: (error) {
          _webSockets.remove(relayUrl);
          reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
        });
        onReconnected?.call(relayUrl);
        print('Reconnected to relay: $relayUrl');
      } catch (e) {
        print('Error reconnecting to relay $relayUrl (Attempt $attempt): $e');
        reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
      }
    });
  }

  int _calculateBackoffDelay(int attempt) {
    const int baseDelay = 2;
    const int maxDelay = 32;
    int delay = (baseDelay * pow(2, attempt - 1)).toInt().clamp(1, maxDelay);
    int jitter = Random().nextInt(2);
    return delay + jitter;
  }

  Future<void> closeConnections() async {
    _isClosed = true;
    await Future.wait(_webSockets.values.map((ws) async => await ws.close()));
    _webSockets.clear();
  }
}

class DataService {
  final String npub;
  final DataType dataType;
  final Function(NoteModel)? onNewNote;
  final Function(String, List<ReactionModel>)? onReactionsUpdated;
  final Function(String, List<ReplyModel>)? onRepliesUpdated;
  final Function(String, int)? onReactionCountUpdated;
  final Function(String, int)? onReplyCountUpdated;
  final Function(String, List<RepostModel>)? onRepostsUpdated;
  final Function(String, int)? onRepostCountUpdated;
  final Function(String, List<ZapModel>)? onZapsUpdated;

  List<NoteModel> notes = [];
  final Set<String> eventIds = {};

  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Map<String, List<RepostModel>> repostsMap = {};
  final Map<String, List<ZapModel>> zapMap = {};

  final Map<String, CachedProfile> profileCache = {};

  Box<UserModel>? usersBox;
  Box<NoteModel>? notesBox;
  Box<ReactionModel>? reactionsBox;
  Box<ReplyModel>? repliesBox;
  Box<RepostModel>? repostsBox;
  Box<FollowingModel>? followingBox;
  Box<ZapModel>? zapBox;

  late WebSocketManager _socketManager;
  bool _isInitialized = false;
  bool _isClosed = false;

  Timer? _cacheCleanupTimer;
  final int currentLimit = 75;

  final Map<String, Completer<Map<String, String>>> _pendingProfileRequests =
      {};
  final Map<String, String> _profileSubscriptionIds = {};

  late ReceivePort _receivePort;
  late Isolate _isolate;
  late SendPort _sendPort;
  final Completer<void> _sendPortReadyCompleter = Completer<void>();

  Function(List<NoteModel>)? _onCacheLoad;

  final Uuid _uuid = Uuid();

  final Duration profileCacheTTL = const Duration(hours: 24);
  final Duration cacheCleanupInterval = const Duration(hours: 12);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  DataService(
      {required this.npub,
      required this.dataType,
      this.onNewNote,
      this.onReactionsUpdated,
      this.onRepliesUpdated,
      this.onReactionCountUpdated,
      this.onReplyCountUpdated,
      this.onRepostsUpdated,
      this.onRepostCountUpdated,
      this.onZapsUpdated});

  int get connectedRelaysCount => _socketManager.activeSockets.length;

  Future<void> initialize() async {
    notesBox =
        await _openHiveBox<NoteModel>('notes_${dataType.toString()}_$npub');
    print('[DataService] Hive notes box opened successfully.');

    await Future.wait([
      _openHiveBox<ReactionModel>('reactions_${dataType.toString()}_$npub')
          .then((box) {
        reactionsBox = box;
        print('[DataService] Hive reactions box opened successfully.');
      }),
      _openHiveBox<ReplyModel>('replies_${dataType.toString()}_$npub')
          .then((box) {
        repliesBox = box;
        print('[DataService] Hive replies box opened successfully.');
      }),
      _openHiveBox<RepostModel>('reposts_${dataType.toString()}_$npub')
          .then((box) {
        repostsBox = box;
        print('[DataService] Hive reposts box opened successfully.');
      }),
      _openHiveBox<UserModel>('users').then((box) {
        usersBox = box;
        print('[DataService] Hive users box opened successfully.');
      }),
      _openHiveBox<FollowingModel>('followingBox').then((box) {
        followingBox = box;
        print('[DataService] Hive following box opened successfully.');
      }),
      _openHiveBox<ZapModel>('zaps_${dataType.toString()}_$npub').then((box) {
        zapBox = box;
        print('[DataService] Hive zap box opened successfully.');
      }),
    ]);

    _socketManager = WebSocketManager(relayUrls: [
      'wss://relay.damus.io',
      'wss://nos.lol',
      'wss://relay.primal.net',
      'wss://vitor.nostr1.com',
      'wss://eu.purplerelay.com',
    ]);

    await Future.wait([
      _initializeIsolate(),
      _socketManager.connectRelays([],
          onEvent: (event, relayUrl) => _handleEvent(event, []),
          onDisconnected: (relayUrl) =>
              _socketManager.reconnectRelay(relayUrl, [])),
    ]);

    await loadNotesFromCache((loadedNotes) {
      print('[DataService] Cache loaded with ${loadedNotes.length} notes.');
    });

    if (notes.isNotEmpty) {
      List<String> noteIds = notes.map((note) => note.id).toList();
      await Future.wait([
        fetchReactionsForEvents(noteIds),
        fetchRepliesForEvents(noteIds),
        fetchRepostsForEvents(noteIds),
        fetchZapsForEvents(noteIds),
      ]);
      print(
          '[DataService] Fetched reactions, replies, reposts, and zaps for cached notes.');
    }

    await _fetchUserData();

    _isInitialized = true;
  }

  Future<Box<T>> _openHiveBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    } else {
      return await Hive.openBox<T>(boxName);
    }
  }

  Future<void> _initializeIsolate() async {
    _receivePort = ReceivePort();
    _isolate =
        await Isolate.spawn(_dataProcessorEntryPoint, _receivePort.sendPort);

    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!_sendPortReadyCompleter.isCompleted) {
          _sendPortReadyCompleter.complete();
          print('[DataService] Isolate initialized successfully.');
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
            print('[DataService ERROR] Isolate error: ${message.data}');
            break;
          case MessageType.Close:
            print('[DataService] Isolate received close message.');
            break;
        }
      }
    });
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

  Request _createRequest(Filter filter) => Request(generateUUID(), [filter]);

  void _startRealTimeSubscription(List<String> targetNpubs) {
    final filter = Filter(
      authors: targetNpubs,
      kinds: [1, 6, 7],
      since: (notes.isNotEmpty)
          ? (notes.first.timestamp.millisecondsSinceEpoch ~/ 1000)
          : null,
    );
    final request = Request(generateUUID(), [filter]);
    _safeBroadcast(request.serialize());
    print('[DataService] Started real-time subscription for new events.');
  }

  Future<void> _subscribeToFollowing() async {
    final filter = Filter(
      authors: [npub],
      kinds: [3],
    );
    final request = Request(generateUUID(), [filter]);
    await _broadcastRequest(request);
    print('[DataService] Subscribed to following events (kind 3).');
  }

  Future<void> _fetchUserData() async {
    List<String> targetNpubs;
    if (dataType == DataType.Feed) {
      final following = await getFollowingList(npub);
      following.add(npub);
      targetNpubs = following.toSet().toList();
    } else {
      targetNpubs = [npub];
    }

    if (_isClosed) return;

    await _socketManager.connectRelays(targetNpubs,
        onEvent: (event, relayUrl) => _handleEvent(event, targetNpubs),
        onDisconnected: (relayUrl) =>
            _socketManager.reconnectRelay(relayUrl, targetNpubs));

    await fetchNotes(targetNpubs, initialLoad: true);

    await Future.wait([
      loadReactionsFromCache(),
      loadRepliesFromCache(),
      loadRepostsFromCache(),
      loadZapsFromCache(),
    ]);

    await _subscribeToAllReactions();

    _startRealTimeSubscription(targetNpubs);
    await _subscribeToFollowing();

    await getCachedUserProfile(npub);
  }

  Future<void> initializeConnections() async {
    if (!_isInitialized) return;
    List<String> targetNpubs;
    if (dataType == DataType.Feed) {
      final following = await getFollowingList(npub);
      following.add(npub);
      targetNpubs = following.toSet().toList();
    } else {
      targetNpubs = [npub];
    }

    if (_isClosed) return;

    await _socketManager.connectRelays(targetNpubs,
        onEvent: (event, relayUrl) => _handleEvent(event, targetNpubs),
        onDisconnected: (relayUrl) =>
            _socketManager.reconnectRelay(relayUrl, targetNpubs));

    await fetchNotes(targetNpubs, initialLoad: true);

    await Future.wait([
      loadReactionsFromCache(),
      loadRepliesFromCache(),
      loadRepostsFromCache(),
      loadZapsFromCache(),
    ]);

    await _subscribeToAllReactions();
    _startRealTimeSubscription(targetNpubs);
  }

  Future<void> _broadcastRequest(Request request) async =>
      await _safeBroadcast(request.serialize());

  Future<void> _safeBroadcast(String message) async {
    try {
      await _socketManager.broadcast(message);
    } catch (e) {}
  }

  Future<void> fetchNotes(List<String> targetNpubs,
      {bool initialLoad = false}) async {
    if (_isClosed) return;

    DateTime? sinceTimestamp;
    if (!initialLoad && notes.isNotEmpty) {
      sinceTimestamp = notes.first.timestamp;
    }

    final filter = Filter(
      authors: targetNpubs,
      kinds: [1, 6],
      limit: currentLimit,
      since: sinceTimestamp != null
          ? sinceTimestamp.millisecondsSinceEpoch ~/ 1000
          : null,
    );

    await _broadcastRequest(_createRequest(filter));
    print('[DataService] Fetched notes with filter: $filter');
  }

  Future<void> _fetchProfilesBatch(List<String> npubs) async {
    if (_isClosed) return;

    final uniqueNpubs =
        npubs.toSet().difference(profileCache.keys.toSet()).toList();
    if (uniqueNpubs.isEmpty) return;

    final filter =
        Filter(authors: uniqueNpubs, kinds: [0], limit: uniqueNpubs.length);
    await _broadcastRequest(_createRequest(filter));
    print(
        '[DataService] Sent profile fetch request for ${uniqueNpubs.length} authors.');
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {
    if (_isClosed) return;
    try {
      final decodedEvent = jsonDecode(event);
      if (decodedEvent[0] == 'EVENT') {
        final Map<String, dynamic> eventData =
            decodedEvent[2] as Map<String, dynamic>;
        final kind = eventData['kind'] as int;
        if (kind == 0) {
          await _handleProfileEvent(eventData);
        } else if (kind == 3) {
          await _handleFollowingEvent(eventData);
        } else if (kind == 7) {
          await _handleReactionEvent(eventData);
        } else if (kind == 1) {
          await _processNoteEvent(eventData, targetNpubs,
              rawWs: jsonEncode(eventData));
        } else if (kind == 6) {
          await _handleRepostEvent(eventData);
          await _processNoteEvent(eventData, targetNpubs,
              rawWs: jsonEncode(eventData));
        } else if (kind == 9735) {
          await _handleZapEvent(eventData);
        }
      }
    } catch (e) {
      print('[DataService ERROR] Error handling event: $e');
    }
  }

  Future<void> _handleFollowingEvent(Map<String, dynamic> eventData) async {
    try {
      List<String> newFollowing = [];
      final tags = eventData['tags'] as List<dynamic>;
      for (var tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'p') {
          if (tag.length > 1) {
            newFollowing.add(tag[1] as String);
          }
        }
      }
      if (followingBox != null && followingBox!.isOpen) {
        final model =
            FollowingModel(pubkeys: newFollowing, updatedAt: DateTime.now());
        await followingBox!.put('following', model);
        print('[DataService] Following model updated with new event.');
      }
    } catch (e) {
      print('[DataService ERROR] Error handling following event: $e');
    }
  }

  Future<void> _processNoteEvent(
      Map<String, dynamic> eventData, List<String> targetNpubs,
      {String? rawWs}) async {
    int kind = eventData['kind'] as int;
    final author = eventData['pubkey'] as String;
    bool isRepost = kind == 6;
    Map<String, dynamic>? originalEventData;
    DateTime? repostTimestamp;
    String? repostRawWs;

    if (isRepost) {
      repostTimestamp =
          DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000);
      repostRawWs = eventData['content'];
      if (repostRawWs is String && repostRawWs.isNotEmpty) {
        try {
          originalEventData = jsonDecode(repostRawWs) as Map<String, dynamic>;
        } catch (e) {
          originalEventData = null;
        }
      }
      if (originalEventData == null) {
        String? originalEventId;
        for (var tag in eventData['tags']) {
          if (tag is List && tag.length >= 2 && tag[0] == 'e') {
            originalEventId = tag[1] as String;
            break;
          }
        }
        if (originalEventId != null) {
          originalEventData = await _fetchEventById(originalEventId);
        }
      }
      if (originalEventData == null) return;
      eventData = originalEventData;
    }

    final eventId = eventData['id'] as String?;
    if (eventId == null) {
      print('[DataService] Event ID is null.');
      return;
    }

    final noteAuthor = eventData['pubkey'] as String;
    final noteContentRaw = eventData['content'];
    String noteContent =
        noteContentRaw is String ? noteContentRaw : jsonEncode(noteContentRaw);
    final tags = eventData['tags'] as List<dynamic>;
    final parentEventId = _extractParentEventId(tags);

    if (eventIds.contains(eventId) || noteContent.trim().isEmpty) return;

    if (parentEventId == null &&
        dataType == DataType.Feed &&
        targetNpubs.isNotEmpty &&
        !targetNpubs.contains(noteAuthor) &&
        (!isRepost || !targetNpubs.contains(author))) return;

    if (parentEventId != null) {
      await _handleReplyEvent(eventData, parentEventId);
    } else {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
          (eventData['created_at'] as int) * 1000);
      final newNote = NoteModel(
        id: eventId,
        content: noteContent,
        author: noteAuthor,
        timestamp: timestamp,
        isRepost: isRepost,
        repostedBy: isRepost ? author : null,
        repostTimestamp: repostTimestamp,
        rawWs: isRepost ? repostRawWs : rawWs,
      );

      if (!eventIds.contains(newNote.id)) {
        notes.add(newNote);
        eventIds.add(newNote.id);

        if (notesBox != null && notesBox!.isOpen) {
          await notesBox!.put(newNote.id, newNote);
        }

        onNewNote?.call(newNote);
        print('[DataService] New note added and saved to cache: ${newNote.id}');

        List<String> newEventIds = [newNote.id];
        await Future.wait([
          fetchReactionsForEvents(newEventIds),
          fetchRepliesForEvents(newEventIds),
          fetchRepostsForEvents(newEventIds),
          fetchZapsForEvents(newEventIds),
        ]);
        await _updateReactionSubscription();
      }
    }
  }

  String? _extractParentEventId(List<dynamic> tags) {
    for (var tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
        return tag[1] as String?;
      }
    }
    return null;
  }

  Future<void> _handleReactionEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      String? targetEventId;
      for (var tag in eventData['tags']) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          targetEventId = tag[1] as String;
          break;
        }
      }
      if (targetEventId == null) return;

      final reaction = ReactionModel.fromEvent(eventData);
      reactionsMap.putIfAbsent(targetEventId, () => []);

      if (!reactionsMap[targetEventId]!.any((r) => r.id == reaction.id)) {
        reactionsMap[targetEventId]!.add(reaction);
        onReactionsUpdated?.call(targetEventId, reactionsMap[targetEventId]!);

        print(
            '[DataService] Reaction updated for event $targetEventId: ${reaction.content}');
        onReactionCountUpdated?.call(
            targetEventId, reactionsMap[targetEventId]!.length);

        await reactionsBox?.put(reaction.id, reaction);
      }
    } catch (e) {
      print('[DataService ERROR] Error handling reaction event: $e');
    }
  }

  Future<void> _handleZapEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final bolt11Tag = eventData['tags']?.firstWhere(
          (tag) => tag is List && tag.length >= 2 && tag[0] == 'bolt11',
          orElse: () => null);
      if (bolt11Tag == null) return;
      final bolt11 = bolt11Tag[1] as String;

      final targetEventIdTag = eventData['tags']?.firstWhere(
          (tag) => tag is List && tag.length >= 2 && tag[0] == 'e',
          orElse: () => null);
      if (targetEventIdTag == null) return;
      final targetEventId = targetEventIdTag[1] as String;

      final amount = LightningInvoiceParser.getSatoshiAmount(bolt11) ?? 0;
      final rawMemo = LightningInvoiceParser.getMemo(bolt11);
      String memo = '';
      try {
        if (rawMemo != null && rawMemo.isNotEmpty) {
          final parsedMemo = jsonDecode(rawMemo);
          memo = parsedMemo['content'] ?? '';
        }
      } catch (e) {
        memo = rawMemo ?? '';
      }

      final zap = ZapModel.fromEvent(eventData, amount: amount, memo: memo);
      zapMap.putIfAbsent(targetEventId, () => []);
      if (!zapMap[targetEventId]!.any((z) => z.id == zap.id)) {
        zapMap[targetEventId]!.add(zap);
        await zapBox?.put(zap.id, zap);
        onZapsUpdated?.call(targetEventId, zapMap[targetEventId]!);
        print(
            '[DataService] Zap added for $targetEventId: amount ${amount} sats');
      }
    } catch (e) {
      print('[DataService ERROR] Error handling zap event: $e');
    }
  }

  Future<void> _handleReplyEvent(
      Map<String, dynamic> eventData, String parentEventId) async {
    if (_isClosed) return;
    try {
      final reply = ReplyModel.fromEvent(eventData);
      repliesMap.putIfAbsent(parentEventId, () => []);

      if (!repliesMap[parentEventId]!.any((r) => r.id == reply.id)) {
        repliesMap[parentEventId]!.add(reply);
        onRepliesUpdated?.call(parentEventId, repliesMap[parentEventId]!);

        print(
            '[DataService] Reply updated for event $parentEventId: ${reply.content}');
        onReplyCountUpdated?.call(
            parentEventId, repliesMap[parentEventId]!.length);

        await repliesBox?.put(reply.id, reply);
      }

      await fetchRepliesForEvents([reply.id]);
    } catch (e) {
      print('[DataService ERROR] Error handling reply event: $e');
    }
  }

  Future<void> _handleRepostEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      String? originalNoteId;
      for (var tag in eventData['tags']) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
          originalNoteId = tag[1] as String?;
          break;
        }
      }
      if (originalNoteId == null) return;

      final repost = RepostModel.fromEvent(eventData, originalNoteId);
      repostsMap.putIfAbsent(originalNoteId, () => []);

      if (!repostsMap[originalNoteId]!.any((r) => r.id == repost.id)) {
        repostsMap[originalNoteId]!.add(repost);
        onRepostsUpdated?.call(originalNoteId, repostsMap[originalNoteId]!);

        print(
            '[DataService] Repost updated for event $originalNoteId: ${repost.repostedBy}');
        onRepostCountUpdated?.call(
            originalNoteId, repostsMap[originalNoteId]!.length);

        await repostsBox?.put(repost.id, repost);
      }
    } catch (e) {
      print('[DataService ERROR] Error handling repost event: $e');
    }
  }

  Future<void> _handleProfileEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final author = eventData['pubkey'] as String;
      final createdAt =
          DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000);
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
      final lud16 = profileContent['lud16'] as String? ?? '';
      final website = profileContent['website'] as String? ?? '';

      if (profileCache.containsKey(author)) {
        final cachedProfile = profileCache[author]!;
        if (createdAt.isBefore(cachedProfile.fetchedAt)) {
          print(
              '[DataService] Profile event ignored for $author: older data received.');
          return;
        }
      }

      profileCache[author] = CachedProfile({
        'name': userName,
        'profileImage': profileImage,
        'about': about,
        'nip05': nip05,
        'banner': banner,
        'lud16': lud16,
        'website': website
      }, createdAt);

      if (usersBox != null && usersBox!.isOpen) {
        final userModel = UserModel(
          npub: author,
          name: userName,
          about: about,
          nip05: nip05,
          banner: banner,
          profileImage: profileImage,
          lud16: lud16,
          website: website,
          updatedAt: createdAt,
        );
        await usersBox!.put(author, userModel);
      }

      if (_pendingProfileRequests.containsKey(author)) {
        _pendingProfileRequests[author]?.complete(profileCache[author]!.data);
        _pendingProfileRequests.remove(author);
      }
    } catch (e) {
      print('[DataService ERROR] Error handling profile event: $e');
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
        'lud16': '',
        'website': ''
      };
    }

    final now = DateTime.now();
    if (profileCache.containsKey(npub)) {
      final cached = profileCache[npub]!;
      if (now.difference(cached.fetchedAt) < profileCacheTTL) {
        return cached.data;
      } else {
        profileCache.remove(npub);
      }
    }

    if (usersBox != null && usersBox!.isOpen) {
      final user = usersBox!.get(npub);
      if (user != null) {
        final data = {
          'name': user.name,
          'profileImage': user.profileImage,
          'about': user.about,
          'nip05': user.nip05,
          'banner': user.banner,
          'lud16': user.lud16,
          'website': user.website,
        };
        profileCache[npub] = CachedProfile(data, user.updatedAt);
        return data;
      }
    }

    if (_pendingProfileRequests.containsKey(npub)) {
      return await _pendingProfileRequests[npub]!.future;
    }

    final completer = Completer<Map<String, String>>();
    _pendingProfileRequests[npub] = completer;

    String subscriptionId = generateUUID();
    _profileSubscriptionIds[subscriptionId] = npub;

    final request =
        _createRequest(Filter(authors: [npub], kinds: [0], limit: 1));
    await _broadcastRequest(request);

    try {
      return await completer.future.timeout(const Duration(seconds: 1),
          onTimeout: () => {
                'name': 'Anonymous',
                'profileImage': '',
                'about': '',
                'nip05': '',
                'banner': '',
                'lud16': '',
                'website': ''
              });
    } catch (e) {
      return {
        'name': 'Anonymous',
        'profileImage': '',
        'about': '',
        'nip05': '',
        'banner': '',
        'lud16': '',
        'website': ''
      };
    }
  }

  Future<List<String>> getFollowingList(String npub) async {
    if (followingBox != null && followingBox!.isOpen) {
      final cachedFollowing = followingBox!.get('following');
      if (cachedFollowing != null) {
        print('[DataService] Using cached following list from Hive.');
        return cachedFollowing.pubkeys;
      }
    }
    List<String> following = [];
    final limitedRelays = _socketManager.relayUrls.take(3).toList();

    await Future.wait(limitedRelays.map((relayUrl) async {
      try {
        final ws = await WebSocket.connect(relayUrl)
            .timeout(const Duration(seconds: 1));
        if (_isClosed) {
          await ws.close();
          return;
        }
        final request =
            _createRequest(Filter(authors: [npub], kinds: [3], limit: 1000));
        final completer = Completer<void>();

        ws.listen((event) {
          final decoded = jsonDecode(event);
          if (decoded[0] == 'EVENT') {
            for (var tag in decoded[2]['tags']) {
              if (tag is List && tag.isNotEmpty && tag[0] == 'p') {
                following.add(tag[1] as String);
              }
            }
            completer.complete();
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete();
        });

        ws.add(request.serialize());
        await completer.future.timeout(const Duration(seconds: 1),
            onTimeout: () async {
          await ws.close();
        });
        await ws.close();
      } catch (e) {}
    }));

    following = following.toSet().toList();

    if (followingBox != null && followingBox!.isOpen) {
      final newFollowingModel =
          FollowingModel(pubkeys: following, updatedAt: DateTime.now());
      await followingBox!.put('following', newFollowingModel);
      print('[DataService] Updated Hive following model.');
    }
    return following;
  }

  Future<void> fetchOlderNotes(
      List<String> targetNpubs, Function(NoteModel) onOlderNote) async {
    if (_isClosed || notes.isEmpty) return;
    final lastNote = notes.last;
    final filter = Filter(
      authors: targetNpubs,
      kinds: [1, 6],
      limit: currentLimit,
      until: lastNote.timestamp.millisecondsSinceEpoch ~/ 1000,
    );
    final request = _createRequest(filter);
    await _broadcastRequest(request);
  }

  Future<void> _subscribeToAllReactions() async {
    if (_isClosed) return;
    String subscriptionId = generateUUID();
    List<String> allEventIds = notes.map((note) => note.id).toList();
    if (allEventIds.isEmpty) return;

    final filter = Filter(kinds: [7], e: allEventIds, limit: 1000);
    final request = Request(subscriptionId, [filter]);
    await _broadcastRequest(request);
  }

  Future<void> _updateReactionSubscription() async =>
      await _subscribeToAllReactions();

  Future<void> fetchZapsForEvents(List<String> eventIdsToFetch) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(kinds: [9735], e: eventIdsToFetch, limit: 1000)
    ]);
    await _broadcastRequest(request);
  }

  Future<void> loadZapsFromCache() async {
    if (zapBox == null || !zapBox!.isOpen) return;
    try {
      final allZaps = zapBox!.values.cast<ZapModel>().toList();
      if (allZaps.isEmpty) return;

      for (var zap in allZaps) {
        zapMap.putIfAbsent(zap.targetEventId, () => []);
        if (!zapMap[zap.targetEventId]!.any((z) => z.id == zap.id)) {
          zapMap[zap.targetEventId]!.add(zap);
        }
      }
      print(
          '[DataService] Zaps cache loaded with ${allZaps.length} zap receipts.');
    } catch (e) {
      print('[DataService ERROR] Error loading zaps from cache: $e');
    }
  }

  Future<void> shareNote(String noteContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = Event.from(
        kind: 1,
        tags: [],
        content: noteContent,
        privkey: privateKey,
      );
      final serializedEvent = event.serialize();

      await _socketManager.broadcast(serializedEvent);

      final timestamp = DateTime.now();
      final newNote = NoteModel(
        id: event.id,
        content: noteContent,
        author: npub,
        timestamp: timestamp,
        isRepost: false,
      );
      notes.add(newNote);
      eventIds.add(newNote.id);
      if (notesBox != null && notesBox!.isOpen) {
        await notesBox!.put(newNote.id, newNote);
      }
      onNewNote?.call(newNote);
      print('[DataService] Note shared successfully and added to cache.');
    } catch (e) {
      print('[DataService ERROR] Error sharing note: $e');
      throw e;
    }
  }

  Future<String> sendMedia(String filePath, String serverUrl) async {
    final privateKey = await _secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    final configUrl = serverUrl.endsWith('/')
        ? '$serverUrl.well-known/nostr/nip96.json'
        : '$serverUrl/.well-known/nostr/nip96.json';
    final httpClient = HttpClient();
    final configRequest = await httpClient.getUrl(Uri.parse(configUrl));
    final configResponse = await configRequest.close();
    if (configResponse.statusCode != 200) {
      throw Exception(
          'Failed to fetch server configuration: ${configResponse.statusCode}');
    }
    final configBody = await configResponse.transform(utf8.decoder).join();
    final configJson = json.decode(configBody);
    final apiUrl = configJson['api_url'];
    if (apiUrl == null || apiUrl.isEmpty) {
      throw Exception('API URL not found in server configuration.');
    }

    final event = Event.from(
      kind: 27235,
      tags: [
        ['u', apiUrl],
        ['method', 'POST'],
      ],
      content: '',
      privkey: privateKey,
    );
    final eventJsonStr = json.encode(event.toJson());
    final token = base64.encode(utf8.encode(eventJsonStr));
    final authHeader = 'Nostr $token';

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }
    final fileSize = await file.length();
    final fileBytes = await file.readAsBytes();

    String mimeType;
    String? extension;
    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      mimeType = 'image/jpeg';
      extension = 'jpg';
    } else if (lowerPath.endsWith('.png')) {
      mimeType = 'image/png';
      extension = 'png';
    } else if (lowerPath.endsWith('.mp4')) {
      mimeType = 'video/mp4';
      extension = 'mp4';
    } else {
      mimeType = 'application/octet-stream';
    }

    final randomName = Uuid().v4();
    final fileName = extension != null ? '$randomName.$extension' : randomName;

    final boundary = '----dart_form_boundary_${Uuid().v4()}';
    final contentTypeHeader = 'multipart/form-data; boundary=$boundary';
    final bodyBuffer = BytesBuilder();

    void addField(String name, String value) {
      bodyBuffer.add(utf8.encode('--$boundary\r\n'));
      bodyBuffer.add(
          utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
      bodyBuffer.add(utf8.encode(value));
      bodyBuffer.add(utf8.encode('\r\n'));
    }

    addField('expiration', '');
    addField('size', fileSize.toString());
    addField('content_type', mimeType);

    bodyBuffer.add(utf8.encode('--$boundary\r\n'));
    bodyBuffer.add(utf8.encode(
        'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'));
    bodyBuffer.add(utf8.encode('Content-Type: $mimeType\r\n\r\n'));
    bodyBuffer.add(fileBytes);
    bodyBuffer.add(utf8.encode('\r\n'));
    bodyBuffer.add(utf8.encode('--$boundary--\r\n'));

    final multipartBody = bodyBuffer.takeBytes();

    final apiUri = Uri.parse(
        apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl);
    final uploadRequest = await httpClient.postUrl(apiUri);
    uploadRequest.headers.set(HttpHeaders.contentTypeHeader, contentTypeHeader);
    uploadRequest.headers.set(HttpHeaders.authorizationHeader, authHeader);
    uploadRequest.contentLength = multipartBody.length;
    uploadRequest.add(multipartBody);

    final uploadResponse = await uploadRequest.close();
    final uploadResponseBody =
        await uploadResponse.transform(utf8.decoder).join();
    Map<String, dynamic> uploadResp = json.decode(uploadResponseBody);

    if (uploadResp['status'] == 'processing' &&
        uploadResp['processing_url'] != null) {
      final processingUrl = uploadResp['processing_url'];
      int retries = 5;
      while (retries > 0) {
        await Future.delayed(const Duration(seconds: 1));
        final pollRequest = await httpClient.getUrl(Uri.parse(processingUrl));
        final pollResponse = await pollRequest.close();
        if (pollResponse.statusCode == 201) {
          final pollBody = await pollResponse.transform(utf8.decoder).join();
          uploadResp = json.decode(pollBody);
          break;
        } else {
          final pollBody = await pollResponse.transform(utf8.decoder).join();
          final delayedResponse = json.decode(pollBody);
          if (delayedResponse['status'] == 'error') {
            throw Exception('Processing error: ${delayedResponse['message']}');
          }
          retries--;
        }
      }
      if (retries <= 0) {
        throw Exception('Processing timeout (5 attempts reached)');
      }
    }

    if (uploadResp['status'] == 'error') {
      throw Exception('Server returned error: ${uploadResp['message']}');
    }

    String? fileURL;
    if (uploadResp['nip94_event'] != null &&
        uploadResp['nip94_event']['tags'] != null) {
      for (final tag in uploadResp['nip94_event']['tags']) {
        if (tag is List && tag.length >= 2 && tag[0] == 'url') {
          fileURL = tag[1];
          break;
        }
      }
    }

    if (fileURL == null) {
      throw Exception('File URL not found in server response.');
    }

    return fileURL;
  }

  Future<void> sendReaction(
      String targetEventId, String reactionContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = Event.from(
        kind: 7,
        tags: [
          ['e', targetEventId]
        ],
        content: reactionContent,
        privkey: privateKey,
      );
      final serializedEvent = event.serialize();
      await _socketManager.broadcast(serializedEvent);

      final reaction = ReactionModel.fromEvent(event.toJson());
      reactionsMap.putIfAbsent(targetEventId, () => []);
      if (!reactionsMap[targetEventId]!.any((r) => r.id == reaction.id)) {
        reactionsMap[targetEventId]!.add(reaction);
        onReactionsUpdated?.call(targetEventId, reactionsMap[targetEventId]!);
        onReactionCountUpdated?.call(
            targetEventId, reactionsMap[targetEventId]!.length);
        if (reactionsBox != null && reactionsBox!.isOpen) {
          await reactionsBox!.put(reaction.id, reaction);
        }
      }
      print('[DataService] Reaction sent and added to cache.');
    } catch (e) {
      print('[DataService ERROR] Error sending reaction: $e');
      throw e;
    }
  }

  Future<void> sendReply(String parentEventId, String replyContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }
      String noteAuthor = notes
          .firstWhere((note) => note.id == parentEventId,
              orElse: () => throw Exception('Event not found for reply.'))
          .author;

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
      await _socketManager.broadcast(serializedEvent);

      final reply = ReplyModel.fromEvent(event.toJson());
      repliesMap.putIfAbsent(parentEventId, () => []);
      if (!repliesMap[parentEventId]!.any((r) => r.id == reply.id)) {
        repliesMap[parentEventId]!.add(reply);
        onRepliesUpdated?.call(parentEventId, repliesMap[parentEventId]!);
        onReplyCountUpdated?.call(
            parentEventId, repliesMap[parentEventId]!.length);
        if (repliesBox != null && repliesBox!.isOpen) {
          await repliesBox!.put(reply.id, reply);
        }
      }
      print('[DataService] Reply sent and added to cache.');
    } catch (e) {
      print('[DataService ERROR] Error sending reply: $e');
      throw e;
    }
  }

  Future<void> sendRepost(NoteModel note) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }
      final content = note.rawWs;
      if (content == null || content.isEmpty) {
        throw Exception('Raw event data is missing for this note.');
      }
      final tags = [
        ['e', note.id],
        ['p', note.author]
      ];
      final event = Event.from(
        kind: 6,
        tags: tags,
        content: content,
        privkey: privateKey,
      );
      final serializedEvent = event.serialize();
      await _socketManager.broadcast(serializedEvent);

      final repost = RepostModel.fromEvent(event.toJson(), note.id);
      repostsMap.putIfAbsent(note.id, () => []);
      if (!repostsMap[note.id]!.any((r) => r.id == repost.id)) {
        repostsMap[note.id]!.add(repost);
        onRepostsUpdated?.call(note.id, repostsMap[note.id]!);
        onRepostCountUpdated?.call(note.id, repostsMap[note.id]!.length);
        if (repostsBox != null && repostsBox!.isOpen) {
          await repostsBox!.put(repost.id, repost);
        }
      }
      print('[DataService] Repost sent and added to cache.');
    } catch (e) {
      print('[DataService ERROR] Error sending repost: $e');
      throw e;
    }
  }

  Future<void> saveNotesToCache() async {
    if (notesBox != null && notesBox!.isOpen) {
      try {
        final Map<String, NoteModel> notesMap = {
          for (var note in notes) note.id: note
        };
        await notesBox!.putAll(notesMap);
        print('[DataService] Notes saved to cache successfully.');
      } catch (e) {
        print('[DataService ERROR] Error saving notes to cache: $e');
      }
    }
  }

  Future<void> loadNotesFromCache(Function(List<NoteModel>) onLoad) async {
    if (notesBox == null || !notesBox!.isOpen) return;
    try {
      final allNotes = notesBox!.values.cast<NoteModel>().toList();
      if (allNotes.isEmpty) return;

      for (var note in allNotes) {
        if (!eventIds.contains(note.id)) {
          notes.add(note);
          eventIds.add(note.id);
        }
      }

      onLoad(allNotes);
      print('[DataService] Cache loaded with ${allNotes.length} notes.');

      List<String> cachedEventIds = allNotes.map((note) => note.id).toList();

      await Future.wait([
        fetchReactionsForEvents(cachedEventIds),
        fetchRepliesForEvents(cachedEventIds),
        fetchRepostsForEvents(cachedEventIds),
        fetchZapsForEvents(cachedEventIds),
      ]);
    } catch (e) {
      print('[DataService ERROR] Error loading notes from cache: $e');
    }
    await _fetchProfilesForAllData();
  }

  Future<void> loadReactionsFromCache() async {
    if (reactionsBox == null || !reactionsBox!.isOpen) return;
    try {
      final allReactions = reactionsBox!.values.cast<ReactionModel>().toList();
      if (allReactions.isEmpty) return;

      for (var reaction in allReactions) {
        reactionsMap.putIfAbsent(reaction.targetEventId, () => []);
        if (!reactionsMap[reaction.targetEventId]!
            .any((r) => r.id == reaction.id)) {
          reactionsMap[reaction.targetEventId]!.add(reaction);
          onReactionsUpdated?.call(
              reaction.targetEventId, reactionsMap[reaction.targetEventId]!);
        }
      }
      print(
          '[DataService] Reactions cache loaded with ${allReactions.length} reactions.');
    } catch (e) {
      print('[DataService ERROR] Error loading reactions from cache: $e');
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (repliesBox == null || !repliesBox!.isOpen) return;
    try {
      final allReplies = repliesBox!.values.cast<ReplyModel>().toList();
      if (allReplies.isEmpty) return;

      for (var reply in allReplies) {
        repliesMap.putIfAbsent(reply.parentEventId, () => []);
        if (!repliesMap[reply.parentEventId]!.any((r) => r.id == reply.id)) {
          repliesMap[reply.parentEventId]!.add(reply);
        }
      }
      print(
          '[DataService] Replies cache loaded with ${allReplies.length} replies.');
    } catch (e) {
      print('[DataService ERROR] Error loading replies from cache: $e');
    }
  }

  Future<void> loadRepostsFromCache() async {
    if (repostsBox == null || !repostsBox!.isOpen) return;
    try {
      final allReposts = repostsBox!.values.cast<RepostModel>().toList();
      if (allReposts.isEmpty) return;

      for (var repost in allReposts) {
        repostsMap.putIfAbsent(repost.originalNoteId, () => []);
        if (!repostsMap[repost.originalNoteId]!.any((r) => r.id == repost.id)) {
          repostsMap[repost.originalNoteId]!.add(repost);
          onRepostsUpdated?.call(
              repost.originalNoteId, repostsMap[repost.originalNoteId]!);
        }
      }
      print(
          '[DataService] Reposts cache loaded with ${allReposts.length} reposts.');
    } catch (e) {
      print('[DataService ERROR] Error loading reposts from cache: $e');
    }
  }

  Future<void> _handleNewNotes(dynamic data) async {
    if (data is List<NoteModel> && data.isNotEmpty) {
      for (var note in data) {
        if (!eventIds.contains(note.id)) {
          notes.add(note);
          eventIds.add(note.id);
          await notesBox!.put(note.id, note);
        }
      }
      onNewNote?.call(data.last);
      print('[DataService] Handled new notes: ${data.length} notes added.');

      List<String> newEventIds = data.map((note) => note.id).toList();
      await Future.wait([
        fetchReactionsForEvents(newEventIds),
        fetchRepliesForEvents(newEventIds),
        fetchRepostsForEvents(newEventIds),
        fetchZapsForEvents(newEventIds),
      ]);
      await _updateReactionSubscription();
    }
  }

  Future<void> fetchReactionsForEvents(List<String> eventIdsToFetch) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(kinds: [7], e: eventIdsToFetch, limit: 1000)
    ]);
    await _broadcastRequest(request);
  }

  Future<void> fetchRepliesForEvents(List<String> parentEventIds) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(kinds: [1], e: parentEventIds, limit: 1000)
    ]);
    await _broadcastRequest(request);
  }

  Future<void> fetchRepostsForEvents(List<String> eventIdsToFetch) async {
    if (_isClosed) return;
    final request = Request(generateUUID(), [
      Filter(kinds: [6], e: eventIdsToFetch, limit: 1000)
    ]);
    await _broadcastRequest(request);
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

  Future<Map<String, dynamic>?> _fetchEventById(String eventId) async {
    if (_isClosed) return null;
    final completer = Completer<Map<String, dynamic>?>();
    String subscriptionId = generateUUID();
    final request = Request(subscriptionId, [
      Filter(ids: [eventId], limit: 1)
    ]);
    StreamSubscription? subscription;

    await Future.wait(_socketManager.activeSockets.map((ws) async {
      if (ws.readyState == WebSocket.open) {
        subscription = ws.listen((event) {
          final decoded = jsonDecode(event);
          if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
            completer.complete(decoded[2] as Map<String, dynamic>);
            subscription?.cancel();
          } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
            if (!completer.isCompleted) completer.complete(null);
            subscription?.cancel();
          }
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete(null);
          subscription?.cancel();
        });

        ws.add(request.serialize());
      }
    }));

    return completer.future.timeout(const Duration(seconds: 1), onTimeout: () {
      return null;
    });
  }

  String generateUUID() => _uuid.v4().replaceAll('-', '');

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;

    _cacheCleanupTimer?.cancel();

    try {
      if (_sendPortReadyCompleter.isCompleted) {
        _sendPort.send(IsolateMessage(MessageType.Close, 'close'));
      }
    } catch (e) {}

    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
    await _socketManager.closeConnections();

    print('[DataService] All connections closed. Hive boxes remain open.');
  }
}
