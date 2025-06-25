import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:nostr/nostr.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/constants/relays.dart';
import 'package:qiqstr/models/zap_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/models/notification_model.dart';
import 'package:qiqstr/services/isolate_manager.dart';
import 'package:qiqstr/services/media_service.dart';
import 'package:qiqstr/services/relay_service.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/following_model.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:qiqstr/services/note_processor.dart';
import 'package:crypto/crypto.dart';

enum DataType { feed, profile, note }

enum MessageType { newnotes, cacheload, error, close }

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
  late Isolate _eventProcessorIsolate;
  late SendPort _eventProcessorSendPort;
  final Completer<void> _eventProcessorReady = Completer<void>();

  late Isolate _fetchProcessorIsolate;
  late SendPort _fetchProcessorSendPort;
  final Completer<void> _fetchProcessorReady = Completer<void>();

  final String npub;
  final DataType dataType;
  final Function(NoteModel)? onNewNote;
  final Function(String, List<ReactionModel>)? onReactionsUpdated;
  final Function(String, List<ReplyModel>)? onRepliesUpdated;
  final Function(String, int)? onReactionCountUpdated;
  final Function(String, int)? onReplyCountUpdated;
  final Function(String, List<RepostModel>)? onRepostsUpdated;
  final Function(String, int)? onRepostCountUpdated;

  List<NoteModel> notes = [];
  final Set<String> eventIds = {};

  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Map<String, List<RepostModel>> repostsMap = {};
  final Map<String, List<ZapModel>> zapsMap = {};

  final Map<String, CachedProfile> profileCache = {};

  Box<UserModel>? usersBox;
  Box<NoteModel>? notesBox;
  Box<ReactionModel>? reactionsBox;
  Box<ReplyModel>? repliesBox;
  Box<RepostModel>? repostsBox;
  Box<FollowingModel>? followingBox;
  Box<ZapModel>? zapsBox;
  Box<NotificationModel>? notificationsBox;

  final List<Map<String, dynamic>> _pendingEvents = [];
  Timer? _batchTimer;

  late WebSocketManager _socketManager;
  bool _isInitialized = false;
  bool _isClosed = false;

  Timer? _cacheCleanupTimer;
  final int currentLimit = 50;

  final Map<String, Completer<Map<String, String>>> _pendingProfileRequests =
      {};

  late ReceivePort _receivePort;
  late Isolate _isolate;
  late SendPort _sendPort;
  final Completer<void> _sendPortReadyCompleter = Completer<void>();

  Function(List<NoteModel>)? _onCacheLoad;

  static final Uuid _uuid = Uuid();

  final Duration profileCacheTTL = const Duration(minutes: 30);
  final Duration cacheCleanupInterval = const Duration(hours: 6);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  DataService({
    required this.npub,
    required this.dataType,
    this.onNewNote,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
    this.onReactionCountUpdated,
    this.onReplyCountUpdated,
    this.onRepostsUpdated,
    this.onRepostCountUpdated,
  });

  int get connectedRelaysCount => _socketManager.activeSockets.length;

  Future<void> initialize() async {
    final isolateInitFutures = [
      _initializeEventProcessorIsolate(),
      _initializeFetchProcessorIsolate(),
      _initializeIsolate(),
    ];

    final boxInitFutures = [
      _openHiveBox<NoteModel>('notes_${dataType}_$npub'),
      _openHiveBox<UserModel>('users'),
      _openHiveBox<ReactionModel>('reactions_${dataType}_$npub'),
      _openHiveBox<ReplyModel>('replies_${dataType}_$npub'),
      _openHiveBox<RepostModel>('reposts_${dataType}_$npub'),
      _openHiveBox<ZapModel>('zaps_${dataType}_$npub'),
      _openHiveBox<FollowingModel>('followingBox'),
      _openHiveBox<NotificationModel>('notifications_$npub'),
    ];

    final results = await Future.wait([
      Future.wait(isolateInitFutures),
      Future.wait(boxInitFutures),
    ]);

    final boxes = results[1] as List<Box>;
    notesBox = boxes[0] as Box<NoteModel>;
    usersBox = boxes[1] as Box<UserModel>;
    reactionsBox = boxes[2] as Box<ReactionModel>;
    repliesBox = boxes[3] as Box<ReplyModel>;
    repostsBox = boxes[4] as Box<RepostModel>;
    zapsBox = boxes[5] as Box<ZapModel>;
    followingBox = boxes[6] as Box<FollowingModel>;
    notificationsBox = boxes[7] as Box<NotificationModel>;

    await Future.wait([
      loadReactionsFromCache(),
      loadRepliesFromCache(),
      loadRepostsFromCache(),
      loadZapsFromCache(),
      _loadNotificationsFromCache(),
    ]);

    loadNotesFromCache((loadedNotes) {});

    _socketManager = WebSocketManager(relayUrls: relaySetMainSockets);
    _isInitialized = true;
    _startCacheCleanup();
  }

  Future<void> reloadInteractionCounts() async {
    var hasChanges = false;
    for (var note in notes) {
      final newReactionCount = reactionsMap[note.id]?.length ?? 0;
      final newReplyCount = repliesMap[note.id]?.length ?? 0;
      final newRepostCount = repostsMap[note.id]?.length ?? 0;
      
      if (note.reactionCount != newReactionCount ||
          note.replyCount != newReplyCount ||
          note.repostCount != newRepostCount) {
        note.reactionCount = newReactionCount;
        note.replyCount = newReplyCount;
        note.repostCount = newRepostCount;
        hasChanges = true;
      }
    }
    if (hasChanges) {
      notesNotifier.value = _itemsTree.toList();
    }
  }

  Future<Map<String, String>> resolveMentions(List<String> ids) async {
    final Map<String, String> results = {};

    for (final id in ids) {
      try {
        String? pubHex;
        if (id.startsWith('npub1')) {
          pubHex = decodeBasicBech32(id, 'npub');
        } else if (id.startsWith('nprofile1')) {
          pubHex = decodeTlvBech32Full(id, 'nprofile')['type_0_main'];
        }
        if (pubHex != null) {
          final profile = await getCachedUserProfile(pubHex);
          final user = UserModel.fromCachedProfile(pubHex, profile);
          if (user.name.isNotEmpty) {
            results[id] = user.name;
          }
        }
      } catch (_) {}
    }

    return results;
  }

  Future<void> _initializeEventProcessorIsolate() async {
    final ReceivePort receivePort = ReceivePort();

    _eventProcessorIsolate = await Isolate.spawn(
      IsolateManager.eventProcessorEntryPoint,
      receivePort.sendPort,
    );

    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        _eventProcessorSendPort = message;
        _eventProcessorReady.complete();
      } else if (message is Map<String, dynamic>) {
        if (message.containsKey('error')) {
          print('[Event Isolate ERROR] ${message['error']}');
        } else if (message.containsKey('type') && message['type'] == 'batch_results') {
          // Handle batch results from optimized isolate
          final results = message['results'] as List<dynamic>? ?? [];
          for (final result in results) {
            if (result is Map<String, dynamic> && !result.containsKey('error')) {
              _processParsedEvent(result);
            }
          }
        } else {
          _processParsedEvent(message);
        }
      }
    });
  }

  Future<void> _initializeFetchProcessorIsolate() async {
    final ReceivePort receivePort = ReceivePort();

    _fetchProcessorIsolate = await Isolate.spawn(
      IsolateManager.fetchProcessorEntryPoint,
      receivePort.sendPort,
    );

    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        _fetchProcessorSendPort = message;
        _fetchProcessorReady.complete();
      } else if (message is Map<String, dynamic>) {
        if (message.containsKey('error')) {
          print('[Fetch Isolate ERROR] ${message['error']}');
        } else {
          _handleFetchedData(message);
        }
      }
    });
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

    _isolate = await Isolate.spawn(
      IsolateManager.dataProcessorEntryPoint,
      _receivePort.sendPort,
    );

    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!_sendPortReadyCompleter.isCompleted) {
          _sendPortReadyCompleter.complete();
          print('[DataService] Isolate initialized successfully.');
        }
      } else if (message is IsolateMessage) {
        switch (message.type) {
          case MessageType.newnotes:
            _handleNewNotes(message.data);
            break;
          case MessageType.cacheload:
            _handleCacheLoad(message.data);
            break;
          case MessageType.error:
            print('[DataService ERROR] Isolate error: ${message.data}');
            break;
          case MessageType.close:
            print('[DataService] Isolate received close message.');
            break;
        }
      }
    });
  }

  Map<String, dynamic> parseContent(String content) {
    final RegExp mediaRegExp = RegExp(
      r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4|mov))',
      caseSensitive: false,
    );
    final mediaMatches = mediaRegExp.allMatches(content);
    final List<String> mediaUrls =
        mediaMatches.map((m) => m.group(0)!).toList();

    final RegExp linkRegExp = RegExp(r'(https?:\/\/\S+)', caseSensitive: false);
    final linkMatches = linkRegExp.allMatches(content);
    final List<String> linkUrls = linkMatches
        .map((m) => m.group(0)!)
        .where((u) =>
            !mediaUrls.contains(u) &&
            !u.toLowerCase().endsWith('.mp4') &&
            !u.toLowerCase().endsWith('.mov'))
        .toList();

    final RegExp quoteRegExp = RegExp(
      r'(?:nostr:)?(note1[0-9a-z]+|nevent1[0-9a-z]+)',
      caseSensitive: false,
    );
    final quoteMatches = quoteRegExp.allMatches(content);
    final List<String> quoteIds = quoteMatches.map((m) => m.group(1)!).toList();

    String cleanedText = content;
    for (final m in [...mediaMatches, ...quoteMatches]) {
      cleanedText = cleanedText.replaceFirst(m.group(0)!, '');
    }
    cleanedText = cleanedText.trim();

    final RegExp mentionRegExp = RegExp(
      r'nostr:(npub1[0-9a-z]+|nprofile1[0-9a-z]+)',
      caseSensitive: false,
    );
    final mentionMatches = mentionRegExp.allMatches(cleanedText);

    final List<Map<String, dynamic>> textParts = [];
    int lastEnd = 0;
    for (final m in mentionMatches) {
      if (m.start > lastEnd) {
        textParts.add({
          'type': 'text',
          'text': cleanedText.substring(lastEnd, m.start),
        });
      }

      final id = m.group(1)!;
      textParts.add({'type': 'mention', 'id': id});
      lastEnd = m.end;
    }

    if (lastEnd < cleanedText.length) {
      textParts.add({
        'type': 'text',
        'text': cleanedText.substring(lastEnd),
      });
    }

    return {
      'mediaUrls': mediaUrls,
      'linkUrls': linkUrls,
      'quoteIds': quoteIds,
      'textParts': textParts,
    };
  }

  Future<void> openUserProfile(BuildContext context, String bech32OrHex) async {
    try {
      String? pubHex;

      if (bech32OrHex.startsWith('npub1')) {
        pubHex = decodeBasicBech32(bech32OrHex, 'npub');
      } else if (bech32OrHex.startsWith('nprofile1')) {
        pubHex = decodeTlvBech32Full(bech32OrHex, 'nprofile')['type_0_main'];
      } else {
        pubHex = bech32OrHex;
      }

      if (pubHex == null) return;

      final data = await getCachedUserProfile(pubHex);
      final user = UserModel.fromCachedProfile(pubHex, data);

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(user: user)),
      );
    } catch (e) {}
  }

  void parseContentForNote(NoteModel note) {
    final parsed = parseContent(note.content);
    note.parsedContent = parsed;
    note.hasMedia = (parsed['mediaUrls'] as List).isNotEmpty;

    final List<String> mediaUrls = List<String>.from(parsed['mediaUrls']);

    final imageUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif');
    }).toList();

    if (imageUrls.isNotEmpty) {
      MediaService().cacheMediaUrls(imageUrls);
    }

    note.isVideo = false;
    note.videoUrl = null;
  }

  Request _createRequest(Filter filter) => Request(generateUUID(), [filter]);

  void _startRealTimeSubscription(List<String> targetNpubs) {
    final filterNotes = Filter(
      authors: targetNpubs,
      kinds: [1],
      since: (notes.isNotEmpty)
          ? (notes.first.timestamp.millisecondsSinceEpoch ~/ 1000)
          : null,
    );
    final requestNotes = Request(generateUUID(), [filterNotes]);
    _safeBroadcast(requestNotes.serialize());

    final filterReposts = Filter(
      authors: targetNpubs,
      kinds: [6],
      since: (notes.isNotEmpty)
          ? (notes.first.timestamp.millisecondsSinceEpoch ~/ 1000)
          : null,
    );

    final requestReposts = Request(generateUUID(), [filterReposts]);
    _safeBroadcast(requestReposts.serialize());

    print(
        '[DataService] Started real-time subscription for notes, reactions, and reposts separately.');
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

  Future<void> initializeConnections() async {
    if (!_isInitialized) return;

    List<String> targetNpubs;
    if (dataType == DataType.feed) {
      final following = await getFollowingList(npub);
      following.add(npub);
      targetNpubs = following.toSet().toList();

      await Future.wait(
        following
            .where((followedNpub) => followedNpub != npub)
            .map((followedNpub) => getFollowingList(followedNpub)),
      );
    } else {
      targetNpubs = [npub];
    }

    if (_isClosed) return;

    await _socketManager.connectRelays(
      targetNpubs,
      onEvent: (event, relayUrl) => _handleEvent(event, targetNpubs),
      onDisconnected: (relayUrl) =>
          _socketManager.reconnectRelay(relayUrl, targetNpubs),
    );

    await fetchNotes(targetNpubs, initialLoad: true);

    await Future.wait([
      loadReactionsFromCache(),
      loadRepliesFromCache(),
      loadRepostsFromCache(),
    ]);

    await _subscribeToAllReactions();
    await _subscribeToAllReplies();
    await _subscribeToAllReposts();
    await _subscribeToAllZaps();
    await _subscribeToNotifications();

    if (dataType == DataType.feed) {
      _startRealTimeSubscription(targetNpubs);
      await _subscribeToFollowing();
    }

    await getCachedUserProfile(npub);
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

  Future<void> fetchProfilesBatch(List<String> npubs) async {
    if (_isClosed) return;

    final primal = PrimalCacheClient();
    final now = DateTime.now();

    final List<String> remainingForRelay = [];

    for (final pub in npubs.toSet()) {
      if (profileCache.containsKey(pub)) {
        if (now.difference(profileCache[pub]!.fetchedAt) < profileCacheTTL) {
          continue;
        } else {
          profileCache.remove(pub);
        }
      }

      final user = usersBox?.get(pub);
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
        profileCache[pub] = CachedProfile(data, user.updatedAt);
        continue;
      }

      final primalProfile = await primal.fetchUserProfile(pub);
      if (primalProfile != null) {
        profileCache[pub] = CachedProfile(primalProfile, now);

        if (usersBox != null && usersBox!.isOpen) {
          final userModel = UserModel.fromCachedProfile(pub, primalProfile);
          await usersBox!.put(pub, userModel);
        }
        continue;
      }

      remainingForRelay.add(pub);
    }

    if (remainingForRelay.isNotEmpty) {
      final filter = Filter(
        authors: remainingForRelay,
        kinds: [0],
        limit: remainingForRelay.length,
      );

      await _broadcastRequest(_createRequest(filter));
      print(
          '[DataService] Relay profile fetch fallback for ${remainingForRelay.length} npubs.');
    }

    profilesNotifier.value = {
      for (var entry in profileCache.entries)
        entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data)
    };
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {
    if (_isClosed) return;
    try {
      await _eventProcessorReady.future;

      _pendingEvents.add({
        'eventRaw': event,
        'targetNpubs': targetNpubs,
        'priority': 1,
      });

      if (_pendingEvents.length >= 10) {
        _flushPendingEvents();
      } else {
        _batchTimer ??= Timer(const Duration(milliseconds: 100), _flushPendingEvents);
      }
    } catch (e) {}
  }

  void _flushPendingEvents() {
    if (_pendingEvents.isNotEmpty) {
      final batch = List<Map<String, dynamic>>.from(_pendingEvents);
      _pendingEvents.clear();
      _eventProcessorSendPort.send(batch);
    }
    _batchTimer?.cancel();
    _batchTimer = null;
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
        final model = FollowingModel(
            pubkeys: newFollowing, updatedAt: DateTime.now(), npub: npub);
        await followingBox!.put('following', model);
        print('[DataService] Following model updated with new event.');
      }
    } catch (e) {
      print('[DataService ERROR] Error handling following event: $e');
    }
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
        await reactionsBox?.put(reaction.id, reaction);

        onReactionsUpdated?.call(targetEventId, reactionsMap[targetEventId]!);

        final note = notes.firstWhereOrNull((n) => n.id == targetEventId);
        if (note != null) {
          note.reactionCount = reactionsMap[targetEventId]!.length;
        }

        notesNotifier.value = _itemsTree.toList();
        await fetchProfilesBatch([reaction.author]);
      }
    } catch (e) {
      print('[DataService ERROR] Error handling reaction event: $e');
    }
  }

  Future<void> _handleRepostEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      String? originalNoteId;
      for (var tag in eventData['tags']) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          originalNoteId = tag[1] as String;
          break;
        }
      }
      if (originalNoteId == null) return;

      final repost = RepostModel.fromEvent(eventData, originalNoteId);
      repostsMap.putIfAbsent(originalNoteId, () => []);

      if (!repostsMap[originalNoteId]!.any((r) => r.id == repost.id)) {
        repostsMap[originalNoteId]!.add(repost);
        await repostsBox?.put(repost.id, repost);

        onRepostsUpdated?.call(originalNoteId, repostsMap[originalNoteId]!);

        final note = notes.firstWhereOrNull((n) => n.id == originalNoteId);
        if (note != null) {
          note.repostCount = repostsMap[originalNoteId]!.length;
        }

        notesNotifier.value = _itemsTree.toList();
        await fetchProfilesBatch([repost.repostedBy]);
      }
    } catch (e) {
      print('[DataService ERROR] Error handling repost event: $e');
    }
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    if (_isClosed) return;
    try {
      final reply = ReplyModel.fromEvent(eventData);
      repliesMap.putIfAbsent(parentEventId, () => []);

      if (!repliesMap[parentEventId]!.any((r) => r.id == reply.id)) {
        repliesMap[parentEventId]!.add(reply);
        await repliesBox?.put(reply.id, reply);

        onRepliesUpdated?.call(parentEventId, repliesMap[parentEventId]!);

        final parentNote = notes.firstWhereOrNull((n) => n.id == parentEventId);
        if (parentNote != null) {
          parentNote.replyCount = repliesMap[parentEventId]!.length;
          if (!parentNote.replyIds.contains(reply.id)) {
            parentNote.replyIds.add(reply.id);
          }
        }

        if (reply.rootEventId != null && reply.rootEventId != parentEventId) {
          final rootNote = notes.firstWhereOrNull((n) => n.id == reply.rootEventId);
          if (rootNote != null && !rootNote.replyIds.contains(reply.id)) {
            rootNote.replyIds.add(reply.id);
          }
        }

        final isRepost = eventData['kind'] == 6;
        final createdAtRaw = eventData['created_at'];
        final repostTimestamp = isRepost && createdAtRaw is int
            ? DateTime.fromMillisecondsSinceEpoch(createdAtRaw * 1000)
            : null;

        final noteModel = NoteModel(
          id: reply.id,
          content: reply.content,
          author: reply.author,
          timestamp: reply.timestamp,
          isReply: true,
          isRepost: isRepost,
          repostedBy: isRepost ? reply.author : null,
          repostTimestamp: repostTimestamp,
          parentId: parentEventId,
          rootId: reply.rootEventId,
          rawWs: jsonEncode(eventData),
        );

        parseContentForNote(noteModel);

        if (!eventIds.contains(noteModel.id)) {
          notes.add(noteModel);
          eventIds.add(noteModel.id);
          await notesBox?.put(noteModel.id, noteModel);
          _addNote(noteModel);

          if (reply.author == npub) {
            onNewNote?.call(noteModel);
            print('[DataService] Own reply processed and added: ${reply.id}');
          }
        }

        notesNotifier.value = _itemsTree.toList();
        await fetchProfilesBatch([reply.author]);
      }
    } catch (e) {
      print('[DataService ERROR] Error handling reply event: $e');
    }
  }

  Future<void> _handleProfileEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final author = eventData['pubkey'] as String;
      final createdAtRaw = eventData['created_at'];
      if (createdAtRaw is! int) {
        print('[DataService] Skipping profile event with invalid created_at: $createdAtRaw');
        return;
      }
      final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtRaw * 1000);
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

      final display_name = profileContent['name'] as String? ?? 'Anonymous';
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
        'name': display_name,
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
          name: display_name,
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

      profilesNotifier.value = {
        for (var entry in profileCache.entries)
          entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data)
      };
    } catch (e) {
      print('[DataService ERROR] Error handling profile event: $e');
    }
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (_isClosed)
      return {
        'name': 'Anonymous',
        'profileImage': '',
        'about': '',
        'nip05': '',
        'banner': '',
        'lud16': '',
        'website': ''
      };

    final now = DateTime.now();
    if (profileCache.containsKey(npub)) {
      final cached = profileCache[npub]!;
      if (now.difference(cached.fetchedAt) < profileCacheTTL) {
        return cached.data;
      } else {
        profileCache.remove(npub);
      }
    }

    final primal = PrimalCacheClient();
    final primalProfile = await primal.fetchUserProfile(npub);
    if (primalProfile != null) {
      final cached = CachedProfile(primalProfile, DateTime.now());
      profileCache[npub] = cached;

      if (usersBox != null && usersBox!.isOpen) {
        final userModel = UserModel.fromCachedProfile(npub, primalProfile);
        await usersBox!.put(npub, userModel);
      }

      return primalProfile;
    }

    final fetched = await fetchUserProfileIndependently(npub);
    if (fetched != null) {
      profileCache[npub] = CachedProfile(fetched, DateTime.now());
      await usersBox?.put(npub, UserModel.fromCachedProfile(npub, fetched));
      return fetched;
    }

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

  Future<NoteModel?> getCachedNote(String eventIdHex) async {
    final inMemory = notes.firstWhereOrNull((n) => n.id == eventIdHex);
    if (inMemory != null) return inMemory;

    if (notesBox != null && notesBox!.isOpen) {
      final inHive = notesBox!.get(eventIdHex);
      if (inHive != null) return inHive;
    }

    final fetchedNote = await fetchNoteByIdIndependently(eventIdHex);
    if (fetchedNote == null) return null;

    notes.add(fetchedNote);
    eventIds.add(fetchedNote.id);
    await notesBox?.put(fetchedNote.id, fetchedNote);

    return fetchedNote;
  }

  Future<List<String>> getFollowingList(String targetNpub) async {
    if (targetNpub != npub) {
      print(
          '[DataService] Skipping following fetch for non-logged-in user: $targetNpub');
      return [];
    }

    if (followingBox != null && followingBox!.isOpen) {
      final cachedFollowing = followingBox!.get('following_$targetNpub');
      if (cachedFollowing != null) {
        print('[DataService] Using cached following list for $targetNpub.');
        return cachedFollowing.pubkeys;
      }
    }

    List<String> following = [];
    final limitedRelays = _socketManager.relayUrls.take(3).toList();

    await Future.wait(limitedRelays.map((relayUrl) async {
      WebSocket? ws;
      StreamSubscription? sub;
      try {
        ws = await WebSocket.connect(relayUrl)
            .timeout(const Duration(seconds: 3));
        if (_isClosed) {
          try {
            await ws.close();
          } catch (_) {}
          return;
        }
        final request = _createRequest(
            Filter(authors: [targetNpub], kinds: [3], limit: 1000));
        final completer = Completer<void>();

        sub = ws.listen((event) {
          try {
            if (completer.isCompleted) return;
            final decoded = jsonDecode(event);
            if (decoded[0] == 'EVENT') {
              for (var tag in decoded[2]['tags']) {
                if (tag is List && tag.isNotEmpty && tag[0] == 'p') {
                  following.add(tag[1] as String);
                }
              }
              completer.complete();
            }
          } catch (e) {
            if (!completer.isCompleted) completer.complete();
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete();
        }, cancelOnError: true);

        if (ws.readyState == WebSocket.open) {
          ws.add(request.serialize());
        }
        
        await completer.future.timeout(const Duration(seconds: 3),
            onTimeout: () {});
            
        try {
          await sub.cancel();
        } catch (_) {}
        
        try {
          await ws.close();
        } catch (_) {}
      } catch (e) {
        try {
          await sub?.cancel();
        } catch (_) {}
        try {
          await ws?.close();
        } catch (_) {}
      }
    }));

    following = following.toSet().toList();

    if (followingBox != null && followingBox!.isOpen) {
      final newFollowingModel = FollowingModel(
          pubkeys: following, updatedAt: DateTime.now(), npub: targetNpub);
      await followingBox!.put('following_$targetNpub', newFollowingModel);
      print('[DataService] Updated Hive following model for $targetNpub.');
    }
    return following;
  }

  Future<List<String>> getGlobalFollowers(String targetNpub) async {
    if (_isClosed) {
      print('[DataService] Service is closed. Skipping global follower fetch.');
      return [];
    }

    List<String> followers = [];
    final allRelays = _socketManager.relayUrls;

    await Future.wait(allRelays.map((relayUrl) async {
      WebSocket? ws;
      StreamSubscription? sub;
      try {
        ws = await WebSocket.connect(relayUrl)
            .timeout(const Duration(seconds: 2));

        if (_isClosed) {
          try {
            await ws.close();
          } catch (_) {}
          return;
        }

        final filter = Filter(
          kinds: [3],
          p: [targetNpub],
          limit: 1000,
        );

        final request = Request(generateUUID(), [filter]);
        final completer = Completer<void>();

        sub = ws.listen((event) {
          try {
            if (completer.isCompleted) return;
            final decoded = jsonDecode(event);
            if (decoded[0] == 'EVENT') {
              final author = decoded[2]['pubkey'];
              followers.add(author);
            }
            if (decoded[0] == 'EOSE') {
              completer.complete();
            }
          } catch (e) {
            if (!completer.isCompleted) completer.complete();
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete();
        }, cancelOnError: true);

        if (ws.readyState == WebSocket.open) {
          ws.add(request.serialize());
        }

        await completer.future.timeout(const Duration(seconds: 3),
            onTimeout: () {});

        try {
          await sub.cancel();
        } catch (_) {}
        
        try {
          await ws.close();
        } catch (_) {}
      } catch (e) {
        try {
          await sub?.cancel();
        } catch (_) {}
        try {
          await ws?.close();
        } catch (_) {}
      }
    }));

    followers = followers.toSet().toList();

    return followers;
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

    _onCacheLoad = (List<NoteModel> newNotes) async {
      for (var note in newNotes) {
        if (!eventIds.contains(note.id)) {
          parseContentForNote(note);
          notes.add(note);
          eventIds.add(note.id);
          onOlderNote(note);
        }
      }
      print(
          '[DataService] Fetched and processed ${newNotes.length} older notes.');
    };
  }

  final SplayTreeSet<NoteModel> _itemsTree = SplayTreeSet(_compareNotes);
  final ValueNotifier<List<NoteModel>> notesNotifier = ValueNotifier([]);
  final ValueNotifier<Map<String, UserModel>> profilesNotifier =
      ValueNotifier({});
  final ValueNotifier<List<NotificationModel>> notificationsNotifier = ValueNotifier([]);
  final ValueNotifier<int> unreadNotificationsCountNotifier = ValueNotifier(0);

  static int _compareNotes(NoteModel a, NoteModel b) {
    final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
    final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
    final result = bTime.compareTo(aTime);
    return result == 0 ? a.id.compareTo(b.id) : result;
  }

  final List<NoteModel> pendingNotes = [];
  void addPendingNote(NoteModel note) {
    pendingNotes.add(note);
  }

  void applyPendingNotes() {
    for (var note in pendingNotes) {
      _addNote(note);
    }
    pendingNotes.clear();
    notesNotifier.value = _itemsTree.toList();
  }

  void _addNote(NoteModel note) {
    _itemsTree.add(note);
  }

  Future<void> _subscribeToAllZaps() async {
    if (_isClosed) return;
    List<String> allEventIds = notes.map((n) => n.id).toList();
    if (allEventIds.isEmpty) return;
    final filter = Filter(kinds: [9735], e: allEventIds, limit: 1000);
    await _broadcastRequest(_createRequest(filter));
  }

  Future<void> _subscribeToAllReactions() async {
    if (_isClosed || notes.isEmpty) return;
    
    final allEventIds = notes.map((note) => note.id).toList();
    const batchSize = 50;
    
    final futures = <Future>[];
    for (int i = 0; i < allEventIds.length; i += batchSize) {
      final endIndex = (i + batchSize > allEventIds.length) ? allEventIds.length : i + batchSize;
      final batch = allEventIds.sublist(i, endIndex);
      
      if (batch.isNotEmpty) {
        final filter = Filter(kinds: [7], e: batch, limit: 500);
        final request = Request(generateUUID(), [filter]);
        futures.add(_broadcastRequest(request));
      }
      
      if (futures.length >= 3) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<void> _subscribeToAllReplies() async {
    if (_isClosed || notes.isEmpty) return;
    
    final allEventIds = notes.map((n) => n.id).toList();
    const batchSize = 50;
    
    final futures = <Future>[];
    for (int i = 0; i < allEventIds.length; i += batchSize) {
      final endIndex = (i + batchSize > allEventIds.length) ? allEventIds.length : i + batchSize;
      final batch = allEventIds.sublist(i, endIndex);
      
      if (batch.isNotEmpty) {
        final filter = Filter(kinds: [1], e: batch, limit: 500);
        futures.add(_broadcastRequest(_createRequest(filter)));
      }
      
      if (futures.length >= 3) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<void> _subscribeToAllReposts() async {
    if (_isClosed || notes.isEmpty) return;
    
    final allEventIds = notes.map((n) => n.id).toList();
    const batchSize = 50;
    
    final futures = <Future>[];
    for (int i = 0; i < allEventIds.length; i += batchSize) {
      final endIndex = (i + batchSize > allEventIds.length) ? allEventIds.length : i + batchSize;
      final batch = allEventIds.sublist(i, endIndex);
      
      if (batch.isNotEmpty) {
        final filter = Filter(kinds: [6], e: batch, limit: 500);
        futures.add(_broadcastRequest(_createRequest(filter)));
      }
      
      if (futures.length >= 3) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  void _startCacheCleanup() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(cacheCleanupInterval, (timer) async {
      if (_isClosed) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final cutoffTime = now.subtract(profileCacheTTL);
      
      profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));

      final expiredReactionKeys = <String>[];
      final expiredReplyKeys = <String>[];

      if (reactionsBox?.isOpen == true) {
        for (final key in reactionsBox!.keys) {
          final reaction = reactionsBox!.get(key);
          if (reaction?.fetchedAt.isBefore(cutoffTime) == true) {
            expiredReactionKeys.add(key);
          }
        }
      }

      if (repliesBox?.isOpen == true) {
        for (final key in repliesBox!.keys) {
          final reply = repliesBox!.get(key);
          if (reply?.fetchedAt.isBefore(cutoffTime) == true) {
            expiredReplyKeys.add(key);
          }
        }
      }

      final cleanupFutures = <Future>[];
      if (expiredReactionKeys.isNotEmpty) {
        cleanupFutures.add(reactionsBox!.deleteAll(expiredReactionKeys));
      }
      if (expiredReplyKeys.isNotEmpty) {
        cleanupFutures.add(repliesBox!.deleteAll(expiredReplyKeys));
      }

      if (cleanupFutures.isNotEmpty) {
        await Future.wait(cleanupFutures);
      }

      reactionsMap.removeWhere((eventId, reactions) {
        reactions.removeWhere((reaction) => reaction.fetchedAt.isBefore(cutoffTime));
        return reactions.isEmpty;
      });

      repliesMap.removeWhere((eventId, replies) {
        replies.removeWhere((reply) => reply.fetchedAt.isBefore(cutoffTime));
        return replies.isEmpty;
      });
    });
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
      await initializeConnections();
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

  Future<String> sendMedia(String filePath, String blossomUrl) async {
    final privateKey = await _secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileBytes = await file.readAsBytes();
    final sha256Hash = sha256.convert(fileBytes).toString();

    String mimeType = 'application/octet-stream';
    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      mimeType = 'image/jpeg';
    } else if (lowerPath.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (lowerPath.endsWith('.gif')) {
      mimeType = 'image/gif';
    } else if (lowerPath.endsWith('.mp4')) {
      mimeType = 'video/mp4';
    }

    final expiration =
        DateTime.now().add(Duration(minutes: 10)).millisecondsSinceEpoch ~/
            1000;

    final authEvent = Event.from(
      kind: 24242,
      content: 'Upload ${file.uri.pathSegments.last}',
      tags: [
        ['t', 'upload'],
        ['x', sha256Hash],
        ['expiration', expiration.toString()],
      ],
      privkey: privateKey,
    );

    final encodedAuth =
        base64.encode(utf8.encode(jsonEncode(authEvent.toJson())));
    final authHeader = 'Nostr $encodedAuth';

    final cleanedUrl = blossomUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanedUrl/upload');

    final httpClient = HttpClient();
    final request = await httpClient.putUrl(uri);

    request.headers.set(HttpHeaders.authorizationHeader, authHeader);
    request.headers.set(HttpHeaders.contentTypeHeader, mimeType);
    request.headers.set(HttpHeaders.contentLengthHeader, fileBytes.length);

    request.add(fileBytes);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception(
          'Upload failed with status ${response.statusCode}: $responseBody');
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is Map && decoded.containsKey('url')) {
      return decoded['url'];
    }

    throw Exception(
        'Upload succeeded but response does not contain a valid URL.');
  }

  Future<void> sendProfileEdit({
    required String name,
    required String about,
    required String picture,
    String nip05 = '',
    String banner = '',
    String lud16 = '',
    String website = '',
  }) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final Map<String, dynamic> profileContent = {
        'name': name,
        'about': about,
        'picture': picture,
      };

      if (nip05.isNotEmpty) profileContent['nip05'] = nip05;
      if (banner.isNotEmpty) profileContent['banner'] = banner;
      if (lud16.isNotEmpty) profileContent['lud16'] = lud16;
      if (website.isNotEmpty) profileContent['website'] = website;

      final event = Event.from(
        kind: 0,
        tags: [],
        content: jsonEncode(profileContent),
        privkey: privateKey,
      );
      await initializeConnections();
      await _socketManager.broadcast(event.serialize());

      final updatedAt =
          DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);

      final userModel = UserModel(
        npub: event.pubkey,
        name: name,
        about: about,
        profileImage: picture,
        nip05: nip05,
        banner: banner,
        lud16: lud16,
        website: website,
        updatedAt: updatedAt,
      );

      profileCache[event.pubkey] = CachedProfile(
        profileContent.map((key, value) => MapEntry(key, value.toString())),
        updatedAt,
      );

      if (usersBox != null && usersBox!.isOpen) {
        await usersBox!.put(event.pubkey, userModel);
      }

      profilesNotifier.value = {
        ...profilesNotifier.value,
        event.pubkey: userModel,
      };

      print('[DataService] Profile updated and sent successfully.');
    } catch (e, st) {
      print('[DataService ERROR] Error sending profile edit: $e\n$st');
      throw e;
    }
  }

  Future<void> sendFollow(String followNpub) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final currentFollowing = await getFollowingList(npub);
      if (currentFollowing.contains(followNpub)) {
        print('[DataService] Already following $followNpub');
        return;
      }

      currentFollowing.add(followNpub);

      final tags = currentFollowing.map((pubkey) => ['p', pubkey, '']).toList();

      final event = Event.from(
        kind: 3,
        tags: tags,
        content: "",
        privkey: privateKey,
      );
      await initializeConnections();

      await _socketManager.broadcast(event.serialize());

      final updatedFollowingModel = FollowingModel(
        pubkeys: currentFollowing,
        updatedAt: DateTime.now(),
        npub: npub,
      );
      await followingBox?.put('following_$npub', updatedFollowingModel);

      print('[DataService] Follow event sent and following list updated.');
    } catch (e) {
      print('[DataService ERROR] Error sending follow: $e');
      throw e;
    }
  }

  Future<void> sendUnfollow(String unfollowNpub) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final currentFollowing = await getFollowingList(npub);
      if (!currentFollowing.contains(unfollowNpub)) {
        print('[DataService] Not following $unfollowNpub');
        return;
      }

      currentFollowing.remove(unfollowNpub);

      final tags = currentFollowing.map((pubkey) => ['p', pubkey, '']).toList();

      final event = Event.from(
        kind: 3,
        tags: tags,
        content: "",
        privkey: privateKey,
      );
      await initializeConnections();

      await _socketManager.broadcast(event.serialize());

      final updatedFollowingModel = FollowingModel(
        pubkeys: currentFollowing,
        updatedAt: DateTime.now(),
        npub: npub,
      );
      await followingBox?.put('following_$npub', updatedFollowingModel);

      print('[DataService] Unfollow event sent and following list updated.');
    } catch (e) {
      print('[DataService ERROR] Error sending unfollow: $e');
      throw e;
    }
  }

  Future<String> sendZap({
    required String recipientPubkey,
    required String lud16,
    required int amountSats,
    String? noteId,
    String content = '',
  }) async {
    final privateKey = await _secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    if (!lud16.contains('@')) {
      throw Exception('Invalid lud16 format.');
    }

    final parts = lud16.split('@');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      throw Exception('Invalid lud16 format.');
    }

    final display_name = parts[0];
    final domain = parts[1];

    final uri = Uri.parse('https://$domain/.well-known/lnurlp/$display_name');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('LNURL fetch failed with status: ${response.statusCode}');
    }

    final lnurlJson = jsonDecode(response.body);
    if (lnurlJson['allowsNostr'] != true || lnurlJson['nostrPubkey'] == null) {
      throw Exception('Recipient does not support zaps.');
    }

    final callback = lnurlJson['callback'];
    if (callback == null || callback.isEmpty) {
      throw Exception('Zap callback is missing.');
    }

    final lnurlBech32 = lnurlJson['lnurl'] ?? '';
    final amountMillisats = (amountSats * 1000).toString();
    final relays = relaySetMainSockets;

    if (relays.isEmpty) {
      throw Exception('No relays available for zap.');
    }

    final List<List<String>> tags = [
      ['relays', ...relays.map((e) => e.toString())],
      ['amount', amountMillisats],
      if (lnurlBech32.isNotEmpty) ['lnurl', lnurlBech32],
      ['p', recipientPubkey],
    ];

    if (noteId != null && noteId.isNotEmpty) {
      tags.add(['e', noteId]);
    }

    final zapRequest = Event.from(
      kind: 9734,
      tags: tags,
      content: content,
      privkey: privateKey,
    );

    final encodedZap = Uri.encodeComponent(jsonEncode(zapRequest.toJson()));
    final zapUrl = Uri.parse(
      '$callback?amount=$amountMillisats&nostr=$encodedZap${lnurlBech32.isNotEmpty ? '&lnurl=$lnurlBech32' : ''}',
    );

    final invoiceResponse = await http.get(zapUrl);
    if (invoiceResponse.statusCode != 200) {
      throw Exception('Zap callback failed: ${invoiceResponse.body}');
    }

    final invoiceJson = jsonDecode(invoiceResponse.body);
    final invoice = invoiceJson['pr'];
    if (invoice == null || invoice.toString().isEmpty) {
      throw Exception('Invoice not returned by zap server.');
    }

    print('[sendZap] Invoice ready: $invoice');
    return invoice;
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
      await initializeConnections();
      await _socketManager.broadcast(event.serialize());

      final reaction = ReactionModel.fromEvent(event.toJson());
      reactionsMap.putIfAbsent(targetEventId, () => []);
      reactionsMap[targetEventId]!.add(reaction);
      await reactionsBox?.put(reaction.id, reaction);

      final note = notes.firstWhereOrNull((n) => n.id == targetEventId);
      if (note != null) {
        note.reactionCount = reactionsMap[targetEventId]!.length;
      }

      onReactionsUpdated?.call(targetEventId, reactionsMap[targetEventId]!);
      notesNotifier.value = _itemsTree.toList();
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

      final parentNote =
          notes.firstWhereOrNull((note) => note.id == parentEventId);
      if (parentNote == null) {
        throw Exception('Parent note not found.');
      }

      String rootId;
      String replyId = parentEventId;

      if (parentNote.isReply && parentNote.rootId != null) {
        rootId = parentNote.rootId!;
      } else {
        rootId = parentEventId;
      }

      List<List<String>> tags = [];

      if (rootId != replyId) {
        tags.add(['e', rootId, '', 'root']);
        tags.add(['e', replyId, '', 'reply']);
      } else {
        tags.add(['e', rootId, '', 'root']);
      }

      tags.add(['p', parentNote.author, '', 'mention']);

      for (final relayUrl in relaySetMainSockets) {
        tags.add(['r', relayUrl]);
      }

      final event = Event.from(
        kind: 1,
        tags: tags,
        content: replyContent,
        privkey: privateKey,
      );
      await initializeConnections();
      await _socketManager.broadcast(event.serialize());

      final reply = ReplyModel.fromEvent(event.toJson());
      repliesMap.putIfAbsent(parentEventId, () => []);
      repliesMap[parentEventId]!.add(reply);
      await repliesBox?.put(reply.id, reply);

      
      final replyNoteModel = NoteModel(
        id: reply.id,
        content: reply.content,
        author: reply.author,
        timestamp: reply.timestamp,
        isReply: true,
        parentId: parentEventId,
        rootId: rootId,
        rawWs: jsonEncode(event.toJson()),
      );

      parseContentForNote(replyNoteModel);

      if (!eventIds.contains(replyNoteModel.id)) {
        notes.add(replyNoteModel);
        eventIds.add(replyNoteModel.id);
        await notesBox?.put(replyNoteModel.id, replyNoteModel);
        _addNote(replyNoteModel);
      }

      final note = notes.firstWhereOrNull((n) => n.id == parentEventId);
      if (note != null) {
        note.replyCount = repliesMap[parentEventId]!.length;
        
        if (!note.replyIds.contains(reply.id)) {
          note.replyIds.add(reply.id);
        }
      }

      if (rootId != parentEventId) {
        final rootNote = notes.firstWhereOrNull((n) => n.id == rootId);
        if (rootNote != null && !rootNote.replyIds.contains(reply.id)) {
          rootNote.replyIds.add(reply.id);
        }
      }

      onRepliesUpdated?.call(parentEventId, repliesMap[parentEventId]!);
      onNewNote?.call(replyNoteModel); 
      notesNotifier.value = _itemsTree.toList();
      
      print('[DataService] Reply sent and added to local notes: ${reply.id}');
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

      final tags = [
        ['e', note.id],
        ['p', note.author],
      ];

      final content = note.rawWs ??
          jsonEncode({
            'id': note.id,
            'pubkey': note.author,
            'content': note.content,
            'created_at': note.timestamp.millisecondsSinceEpoch ~/ 1000,
            'kind': note.isRepost ? 6 : 1,
            'tags': [],
          });

      final event = Event.from(
        kind: 6,
        tags: tags,
        content: content,
        privkey: privateKey,
      );
      await initializeConnections();
      await _socketManager.broadcast(event.serialize());

      final repost = RepostModel.fromEvent(event.toJson(), note.id);
      repostsMap.putIfAbsent(note.id, () => []);
      repostsMap[note.id]!.add(repost);
      await repostsBox?.put(repost.id, repost);

      final updatedNote = notes.firstWhereOrNull((n) => n.id == note.id);
      if (updatedNote != null) {
        updatedNote.repostCount = repostsMap[note.id]!.length;
      }

      onRepostsUpdated?.call(note.id, repostsMap[note.id]!);
      notesNotifier.value = _itemsTree.toList();
    } catch (e) {
      print('[DataService ERROR] Error sending repost: $e');
      throw e;
    }
  }

  Future<void> saveNotesToCache() async {
    if (notesBox?.isOpen != true || notes.isEmpty) return;
    
    try {
      final notesToSave = notes.take(150).toList();
      final notesMap = <String, NoteModel>{};
      
      for (final note in notesToSave) {
        notesMap[note.id] = note;
      }
      
      await notesBox!.clear();
      await notesBox!.putAll(notesMap);
    } catch (e) {}
  }

  Future<void> loadNotesFromCache(Function(List<NoteModel>) onLoad) async {
    if (notesBox?.isOpen != true) return;

    try {
      final allNotes = notesBox!.values.cast<NoteModel>().toList();
      if (allNotes.isEmpty) return;

      allNotes.sort((a, b) {
        final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
        final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
        return bTime.compareTo(aTime);
      });

      final limitedNotes = allNotes.take(150).toList();
      final newNotes = <NoteModel>[];

      for (final note in limitedNotes) {
        if (!eventIds.contains(note.id)) {
          parseContentForNote(note);
          notes.add(note);
          eventIds.add(note.id);
          _addNote(note);
          newNotes.add(note);
        }

        note.reactionCount = reactionsMap[note.id]?.length ?? 0;
        note.replyCount = repliesMap[note.id]?.length ?? 0;
        note.repostCount = repostsMap[note.id]?.length ?? 0;
        note.zapAmount = zapsMap[note.id]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
      }

      if (newNotes.isNotEmpty) {
        notesNotifier.value = _itemsTree.toList();
        onLoad(newNotes);

        final cachedEventIds = newNotes.map((note) => note.id).toList();
        
        Future.microtask(() => fetchInteractionsForEvents(cachedEventIds));
        Future.microtask(() async {
          await _fetchProfilesForAllData();
          profilesNotifier.value = {
            for (var entry in profileCache.entries)
              entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data),
          };
        });
      }
    } catch (e) {}
  }

  Future<void> loadZapsFromCache() async {
    if (zapsBox == null || !zapsBox!.isOpen) return;
    try {
      final allZaps = zapsBox!.values.cast<ZapModel>().toList();
      if (allZaps.isEmpty) return;

      for (var zap in allZaps) {
        zapsMap.putIfAbsent(zap.targetEventId, () => []);
        if (!zapsMap[zap.targetEventId]!.any((r) => r.id == zap.id)) {
          zapsMap[zap.targetEventId]!.add(zap);
        }
      }
    } catch (e) {
      print('[DataService ERROR] Error loading zaps from cache: $e');
    }
  }

  Future<void> _handleZapEvent(Map<String, dynamic> eventData) async {
    try {
      final zap = ZapModel.fromEvent(eventData);
      final key = zap.targetEventId;

      if (key.isEmpty) {
        return;
      }

      if (!zapsMap.containsKey(key)) {
        zapsMap[key] = [];
      }

      if (zapsMap[key]!.any((z) => z.id == zap.id)) return;

      zapsMap[key]!.add(zap);
      await zapsBox?.put(zap.id, zap);

      final note = notes.firstWhereOrNull((n) => n.id == key);
      if (note != null) {
        note.zapAmount = zapsMap[key]!.fold(0, (sum, z) => sum + z.amount);
        notesNotifier.value = _itemsTree.toList();
      }
    } catch (e) {
      print("error: $e");
    }
  }

  Future<void> fetchInteractionsForEvents(List<String> eventIdsToFetch) async {
    if (_isClosed) return;
    await _fetchProcessorReady.future;

    final kindsToFetch = [
      {'type': 'reaction', 'kind': 7},
      {'type': 'reply', 'kind': 1},
      {'type': 'repost', 'kind': 6},
      {'type': 'zap', 'kind': 9735},
    ];

    for (final interaction in kindsToFetch) {
      final type = interaction['type'] as String;

      _fetchProcessorSendPort.send({
        'type': type,
        'eventIds': eventIdsToFetch,
        'priority': 2,
      });

      for (final eventId in eventIdsToFetch) {
        if (type == 'reaction') {
          final reactions = reactionsMap[eventId] ?? [];
          onReactionsUpdated?.call(eventId, reactions);
          final note = notes.firstWhereOrNull((n) => n.id == eventId);
          if (note != null) note.reactionCount = reactions.length;
        } else if (type == 'reply') {
          final replies = repliesMap[eventId] ?? [];
          onRepliesUpdated?.call(eventId, replies);
          final note = notes.firstWhereOrNull((n) => n.id == eventId);
          if (note != null) note.replyCount = replies.length;
        } else if (type == 'repost') {
          final reposts = repostsMap[eventId] ?? [];
          onRepostsUpdated?.call(eventId, reposts);
          final note = notes.firstWhereOrNull((n) => n.id == eventId);
          if (note != null) note.repostCount = reposts.length;
        } else if (type == 'zap') {
          final zaps = zapsMap[eventId] ?? [];
          final note = notes.firstWhereOrNull((n) => n.id == eventId);
          if (note != null) {
            note.zapAmount = zaps.fold<int>(0, (sum, z) => sum + z.amount);
          }
        }
      }
    }

    notesNotifier.value = _itemsTree.toList();
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

      final replyIds = allReplies.map((r) => r.id).toList();
      if (replyIds.isNotEmpty) {
        Future.microtask(() async {
          await Future.wait([
            fetchInteractionsForEvents(replyIds),
          ]);
        });
      }
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

  Future<void> _loadNotificationsFromCache() async {
    if (notificationsBox == null || !notificationsBox!.isOpen) return;
    try {
      final allNotifications = notificationsBox!.values.toList();
      allNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notificationsNotifier.value = allNotifications;
      _updateUnreadNotificationCount();
      final count = allNotifications.length;
      print('[DataService] Notifications cache contains $count notifications.');
    } catch (e) {
      print('[DataService ERROR] Error loading notifications from cache: $e');
    }
  }

  void _updateUnreadNotificationCount() {
    if (notificationsBox != null && notificationsBox!.isOpen) {
      final unreadCount = notificationsBox!.values.where((n) => !n.isRead).length;
      unreadNotificationsCountNotifier.value = unreadCount;
    }
  }

  Future<void> refreshUnreadNotificationCount() async {
    _updateUnreadNotificationCount();
  }

  Future<void> markAllUserNotificationsAsRead() async {
    if (notificationsBox == null || !notificationsBox!.isOpen) return;

    List<Future<void>> saveFutures = [];
    bool madeChanges = false;

    final relevantNotifications =
        notificationsBox!.values.where((n) => ['mention', 'reaction', 'repost', 'zap'].contains(n.type)).toList();

    for (final notification in relevantNotifications) {
      if (!notification.isRead) {
        notification.isRead = true;
        saveFutures.add(notification.save());
        madeChanges = true;
      }
    }

    if (saveFutures.isNotEmpty) {
      await Future.wait(saveFutures);
      print('[DataService] Marked ${saveFutures.length} notifications as read.');
    }

    _updateUnreadNotificationCount();

    if (madeChanges) {
      final allNotifications = notificationsBox!.values.toList();
      allNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notificationsNotifier.value = allNotifications;
    }
  }

Future<void> _subscribeToNotifications() async {
    if (_isClosed || npub.isEmpty || notificationsBox == null || !notificationsBox!.isOpen) return;

    int? sinceTimestamp;
    try {
      if (notificationsBox!.isNotEmpty) {
        final List<NotificationModel> sortedNotifications = notificationsBox!.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        sinceTimestamp = (sortedNotifications.first.timestamp.millisecondsSinceEpoch ~/ 1000) + 1;
      }
    } catch (e) {
      print('[DataService ERROR] Error getting latest notification timestamp from cache: $e');
    }

    sinceTimestamp ??= DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

    final filter = Filter(
      p: [npub],
      kinds: [1, 6, 7, 9735],
      since: sinceTimestamp,
      limit: 50,
    );

    final request = _createRequest(filter);

    try {
      await _broadcastRequest(request);
      print(
          '[DataService] Subscribed to notifications for $npub since $sinceTimestamp with filter: ${filter.toJson()}');
    } catch (e) {
      print('[DataService ERROR] Failed to subscribe to notifications: $e');
    }
  }



  Future<void> _handleNewNotes(dynamic data) async {
    if (data is List<NoteModel> && data.isNotEmpty) {
      for (var note in data) {
        if (!eventIds.contains(note.id)) {
          parseContentForNote(note);
          notes.add(note);
          eventIds.add(note.id);

          await notesBox?.put(note.id, note);
          addPendingNote(note);
        }
      }

      print('[DataService] Handled new notes: ${data.length} notes added.');

      data.map((note) => note.id).toList();
    }
  }

Future<void> _processParsedEvent(Map<String, dynamic> parsedData) async {
    try {
      final int? kindNullable = parsedData['kind'] as int?;
      if (kindNullable == null) {
        print('[DataService] Skipping event with null kind');
        return;
      }
      final int kind = kindNullable;
      
      final Map<String, dynamic>? eventDataNullable = parsedData['eventData'] as Map<String, dynamic>?;
      if (eventDataNullable == null) {
        print('[DataService] Skipping event with null eventData');
        return;
      }
      final Map<String, dynamic> eventData = eventDataNullable;
      
      final List<String> targetNpubs = List<String>.from(parsedData['targetNpubs'] ?? []);
      final String? eventAuthorNullable = eventData['pubkey'] as String?;
      if (eventAuthorNullable == null) {
        print('[DataService] Skipping event with null pubkey');
        return;
      }
      final String eventAuthor = eventAuthorNullable;

      if (eventAuthor != npub) {
        final List<dynamic> eventTags = List<dynamic>.from(eventData['tags'] ?? []);
        bool isUserPMentioned = eventTags.any((tag) {
          return tag is List && tag.length >= 2 && tag[0] == 'p' && tag[1] == npub;
        });

        if (isUserPMentioned && [1, 6, 7, 9735].contains(kind)) {
          String notificationType;
          String? firstETagValue;

          for (var tag in eventTags) {
            if (tag is List && tag.length >= 2 && tag[0] == 'e') {
              firstETagValue = tag[1] as String;
              break;
            }
          }

          if (kind == 1) {
            notificationType = "mention";
            firstETagValue ??= eventData['id'];
          } else if (kind == 6) {
            notificationType = "repost";
          } else if (kind == 7) {
            notificationType = "reaction";
          } else if (kind == 9735) {
            notificationType = "zap";
          } else {
            return;
          }

          final notification = NotificationModel.fromEvent(eventData, notificationType);

          if (notificationsBox != null && notificationsBox!.isOpen) {
            if (!notificationsBox!.containsKey(notification.id)) {
              await notificationsBox!.put(notification.id, notification);
              print("[DataService] New $notificationType notification stored: ${notification.id}");
              final currentNotifications = List<NotificationModel>.from(notificationsNotifier.value);
              currentNotifications.insert(0, notification);
              notificationsNotifier.value = currentNotifications;
              if (!notification.isRead) {
                unreadNotificationsCountNotifier.value++;
              }
            }
          }
        }
      }

      if (kind == 0) {
        await _handleProfileEvent(eventData);
      } else if (kind == 3) {
        await _handleFollowingEvent(eventData);
      } else if (kind == 7) {
        await _handleReactionEvent(eventData);
      } else if (kind == 9735) {
        await _handleZapEvent(eventData);
      } else if (kind == 1) {
        final tags = eventData['tags'] as List<dynamic>;
        final eventAuthor = eventData['pubkey'] as String;

        String? rootId;
        String? replyId;

        for (var tag in tags) {
          if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
            if (tag.length > 3 && tag[3] == 'root') {
              rootId = tag[1] as String;
            } else if (tag.length > 3 && tag[3] == 'reply') {
              replyId = tag[1] as String;
            }
          }
        }

        if (rootId != null || replyId != null) {
          String parentId = replyId ?? rootId!;
          await _handleReplyEvent(eventData, parentId);

          if (eventAuthor == npub) {
            print('[DataService] Processing own reply: ${eventData['id']}');
          }
        } else {
          final eTags = tags.where((tag) => tag is List && tag.isNotEmpty && tag[0] == 'e').toList();

          if (eTags.isNotEmpty) {
            final lastETag = eTags.last;
            if (lastETag is List && lastETag.length >= 2) {
              final parentId = lastETag[1] as String;
              await _handleReplyEvent(eventData, parentId);
              
              
              if (eventAuthor == npub) {
                print('[DataService] Processing own legacy reply: ${eventData['id']}');
              }
            } else {
              await NoteProcessor.processNoteEvent(this, eventData, targetNpubs, rawWs: jsonEncode(eventData));
            }
          } else {
            await NoteProcessor.processNoteEvent(this, eventData, targetNpubs, rawWs: jsonEncode(eventData));
          }
        }
      } else if (kind == 6) {
        await _handleRepostEvent(eventData);
        await NoteProcessor.processNoteEvent(this, eventData, targetNpubs, rawWs: jsonEncode(eventData['content']));
      }
    } catch (e) {
      print('[DataService ERROR] Error processing parsed event: $e');
    }
  }


  Future<void> _handleFetchedData(Map<String, dynamic> fetchData) async {
    try {
      final String type = fetchData['type'];
      final List<String> eventIds = List<String>.from(fetchData['eventIds']);

      Request request;
      if (type == 'reaction') {
        request = Request(generateUUID(), [
          Filter(kinds: [7], e: eventIds, limit: 1000)
        ]);
      } else if (type == 'reply') {
        request = Request(generateUUID(), [
          Filter(kinds: [1], e: eventIds, limit: 1000)
        ]);
      } else if (type == 'repost') {
        request = Request(generateUUID(), [
          Filter(kinds: [6], e: eventIds, limit: 1000)
        ]);
      } else if (type == 'zap') {
        request = Request(generateUUID(), [
          Filter(kinds: [9735], e: eventIds, limit: 1000)
        ]);
      } else {
        return;
      }

      await _broadcastRequest(request);
    } catch (e) {
      print('[DataService ERROR] Error handling fetched data: $e');
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
    
    final allAuthors = <String>{};
    allAuthors.addAll(notes.map((note) => note.author));

    for (var replies in repliesMap.values) {
      for (var reply in replies) {
        allAuthors.add(reply.author);
      }
    }
    
    for (var reactions in reactionsMap.values) {
      for (var reaction in reactions) {
        allAuthors.add(reaction.author);
      }
    }

    final uncachedAuthors = allAuthors.where((author) =>
      !profileCache.containsKey(author) ||
      DateTime.now().difference(profileCache[author]!.fetchedAt) > profileCacheTTL
    ).toList();

    if (uncachedAuthors.isNotEmpty) {
      await fetchProfilesBatch(uncachedAuthors);
    }
  }

  Future<NoteModel?> fetchNoteByIdIndependently(String eventId) async {
    final primal = PrimalCacheClient();

    final primalEvent = await primal.fetchEvent(eventId);
    if (primalEvent != null) {
      return NoteModel(
        id: primalEvent['id'],
        content: primalEvent['content'] is String
            ? primalEvent['content']
            : jsonEncode(primalEvent['content']),
        author: primalEvent['pubkey'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            primalEvent['created_at'] * 1000),
        isRepost: primalEvent['kind'] == 6,
        rawWs: jsonEncode(primalEvent),
      );
    }

    final fetchTasks = relaySetIndependentFetch
        .map((relayUrl) => _fetchFromSingleRelay(relayUrl, eventId))
        .toList();

    try {
      final result = await Future.any(fetchTasks);
      return result;
    } catch (e) {
      print('[fetchNoteByIdIndependently] All fetch attempts failed: $e');
      return null;
    }
  }

  Future<Map<String, String>?> fetchUserProfileIndependently(
      String npub) async {
    for (final relayUrl in relaySetIndependentFetch) {
      final result = await _fetchProfileFromSingleRelay(relayUrl, npub);
      if (result != null) {
        return result;
      }
    }
    print('[fetchUserProfileIndependently] No result from any relay.');
    return null;
  }

  Future<Map<String, String>?> _fetchProfileFromSingleRelay(
      String relayUrl, String npub) async {
    WebSocket? ws;
    try {
      ws =
          await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
      final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
      final request = jsonEncode([
        "REQ",
        subscriptionId,
        {
          "authors": [npub],
          "kinds": [0],
          "limit": 1
        }
      ]);

      final completer = Completer<Map<String, dynamic>?>();

      late StreamSubscription sub;
      sub = ws.listen((event) {
        try {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(event);
          if (decoded is List && decoded.length >= 2) {
            if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
              completer.complete(decoded[2]);
            } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
              completer.complete(null);
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      }, cancelOnError: true);

      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }
      
      final eventData = await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      try {
        await sub.cancel();
      } catch (_) {}
      
      try {
        await ws.close();
      } catch (_) {}

      if (eventData != null) {
        final contentRaw = eventData['content'];
        Map<String, dynamic> profileContent = {};
        if (contentRaw is String && contentRaw.isNotEmpty) {
          try {
            profileContent = jsonDecode(contentRaw);
          } catch (_) {}
        }

        return {
          'name': profileContent['name'] ?? 'Anonymous',
          'profileImage': profileContent['picture'] ?? '',
          'about': profileContent['about'] ?? '',
          'nip05': profileContent['nip05'] ?? '',
          'banner': profileContent['banner'] ?? '',
          'lud16': profileContent['lud16'] ?? '',
          'website': profileContent['website'] ?? '',
        };
      } else {
        return null;
      }
    } catch (e) {
      print('[fetchProfileFromSingleRelay] Error fetching from $relayUrl: $e');
      try {
        await ws?.close();
      } catch (_) {}
      return null;
    }
  }

  Future<NoteModel?> _fetchFromSingleRelay(
      String relayUrl, String eventId) async {
    WebSocket? ws;

    try {
      ws =
          await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
      final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
      final request = jsonEncode([
        "REQ",
        subscriptionId,
        {
          "ids": [eventId]
        }
      ]);

      final completer = Completer<Map<String, dynamic>?>();

      late StreamSubscription sub;
      sub = ws.listen((event) {
        try {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(event);

          if (decoded is List && decoded.length >= 2) {
            if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
              completer.complete(decoded[2]);
            } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
              completer.complete(null);
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      }, cancelOnError: true);

      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }

      final eventData = await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      try {
        await sub.cancel();
      } catch (_) {}
      
      try {
        await ws.close();
      } catch (_) {}

      if (eventData != null) {
        return NoteModel(
          id: eventData['id'],
          content: eventData['content'] is String
              ? eventData['content']
              : jsonEncode(eventData['content']),
          author: eventData['pubkey'],
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              eventData['created_at'] * 1000),
          isRepost: eventData['kind'] == 6,
          rawWs: jsonEncode(eventData),
        );
      } else {
        return null;
      }
    } catch (e) {
      print('[fetchFromSingleRelay] Error fetching from $relayUrl: $e');
      try {
        await ws?.close();
      } catch (_) {}
      return null;
    }
  }

  String generateUUID() => _uuid.v4().replaceAll('-', '');

  
  List<NoteModel> getThreadReplies(String rootNoteId) {
    final List<NoteModel> threadReplies = [];

    for (final note in notes) {
      if (note.isReply && (note.rootId == rootNoteId || note.parentId == rootNoteId)) {
        threadReplies.add(note);
      }
    }

    threadReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return threadReplies;
  }

  List<NoteModel> getDirectReplies(String noteId) {
    final List<NoteModel> directReplies = [];

    for (final note in notes) {
      if (note.isReply && note.parentId == noteId) {
        directReplies.add(note);
      }
    }

    directReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return directReplies;
  }

  Map<String, List<NoteModel>> buildThreadHierarchy(String rootNoteId) {
    final Map<String, List<NoteModel>> hierarchy = {};
    final threadReplies = getThreadReplies(rootNoteId);

    for (final reply in threadReplies) {
      final parentId = reply.parentId ?? rootNoteId;
      hierarchy.putIfAbsent(parentId, () => []);
      hierarchy[parentId]!.add(reply);
    }

    hierarchy.forEach((key, replies) {
      replies.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });

    return hierarchy;
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;

    _cacheCleanupTimer?.cancel();

    try {
      if (_sendPortReadyCompleter.isCompleted) {
        _sendPort.send(IsolateMessage(MessageType.close, 'close'));
      }
    } catch (e) {}

    try {
      _eventProcessorIsolate.kill(priority: Isolate.immediate);
    } catch (e) {
      print('[DataService] Failed to kill eventProcessorIsolate: $e');
    }

    try {
      _fetchProcessorIsolate.kill(priority: Isolate.immediate);
    } catch (e) {
      print('[DataService] Failed to kill fetchProcessorIsolate: $e');
    }

    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
    await _socketManager.closeConnections();

    print('[DataService] All connections closed. Hive boxes remain open.');
  }
}
