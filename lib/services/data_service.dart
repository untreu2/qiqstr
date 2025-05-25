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

  final List<Map<String, dynamic>> _pendingEvents = [];
  Timer? _batchTimer;

  late WebSocketManager _socketManager;
  bool _isInitialized = false;
  bool _isClosed = false;

  Timer? _cacheCleanupTimer;
  final int currentLimit = 75;

  final Map<String, Completer<Map<String, String>>> _pendingProfileRequests =
      {};

  late ReceivePort _receivePort;
  late Isolate _isolate;
  late SendPort _sendPort;
  final Completer<void> _sendPortReadyCompleter = Completer<void>();

  Function(List<NoteModel>)? _onCacheLoad;

  final Uuid _uuid = Uuid();

  final Duration profileCacheTTL = const Duration(hours: 1);
  final Duration cacheCleanupInterval = const Duration(hours: 12);

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
    await Future.wait([
      _initializeEventProcessorIsolate(),
      _initializeFetchProcessorIsolate(),
      _initializeIsolate(),
    ]);

    final boxes = await Future.wait([
      _openHiveBox<NoteModel>('notes_${dataType}_$npub'),
      _openHiveBox<UserModel>('users'),
      _openHiveBox<ReactionModel>('reactions_${dataType}_$npub'),
      _openHiveBox<ReplyModel>('replies_${dataType}_$npub'),
      _openHiveBox<RepostModel>('reposts_${dataType}_$npub'),
      _openHiveBox<ZapModel>('zaps_${dataType}_$npub'),
      _openHiveBox<FollowingModel>('followingBox'),
    ]);

    notesBox = boxes[0] as Box<NoteModel>;
    usersBox = boxes[1] as Box<UserModel>;
    reactionsBox = boxes[2] as Box<ReactionModel>;
    repliesBox = boxes[3] as Box<ReplyModel>;
    repostsBox = boxes[4] as Box<RepostModel>;
    zapsBox = boxes[5] as Box<ZapModel>;
    followingBox = boxes[6] as Box<FollowingModel>;

    print('[DataService] Hive boxes opened successfully.');

    await Future.wait([
      loadReactionsFromCache(),
      loadRepliesFromCache(),
      loadRepostsFromCache(),
      loadZapsFromCache(),
    ]);

    Future.microtask(() {
      loadNotesFromCache((loadedNotes) {
        print('[DataService] Cache loaded with ${loadedNotes.length} notes.');
      });
    });

    _socketManager = WebSocketManager(relayUrls: relaySetMainSockets);

    _isInitialized = true;
    _startCacheCleanup();
  }

  Future<void> reloadInteractionCounts() async {
    for (var note in notes) {
      note.reactionCount = reactionsMap[note.id]?.length ?? 0;
      note.replyCount = repliesMap[note.id]?.length ?? 0;
      note.repostCount = repostsMap[note.id]?.length ?? 0;
    }
    notesNotifier.value = _itemsTree.toList();
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

  Future<void> _fetchProfilesBatch(List<String> npubs) async {
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

      _batchTimer ??= Timer(const Duration(milliseconds: 200), () {
        if (_pendingEvents.isNotEmpty) {
          final batch = List<Map<String, dynamic>>.from(_pendingEvents);
          _pendingEvents.clear();
          _eventProcessorSendPort.send(batch);
        }
        _batchTimer = null;
      });
    } catch (e) {
      print('[DataService ERROR] Error batching events: $e');
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
        final model = FollowingModel(
            pubkeys: newFollowing, updatedAt: DateTime.now(), npub: npub);
        await followingBox!.put('following', model);
        print('[DataService] Following model updated with new event.');
      }
    } catch (e) {
      print('[DataService ERROR] Error handling following event: $e');
    }
  }

  Future<void> _processNoteEvent(
    Map<String, dynamic> eventData,
    List<String> targetNpubs, {
    String? rawWs,
  }) async {
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
        } catch (_) {}
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
          final fetchedNote = await fetchNoteByIdIndependently(originalEventId);
          if (fetchedNote != null) {
            originalEventData = {
              'id': fetchedNote.id,
              'pubkey': fetchedNote.author,
              'content': fetchedNote.content,
              'created_at':
                  fetchedNote.timestamp.millisecondsSinceEpoch ~/ 1000,
              'kind': fetchedNote.isRepost ? 6 : 1,
              'tags': [],
            };
          }
        }
      }

      if (originalEventData == null) {
        print('[DataService] Skipped repost: original event missing');
        return;
      }

      eventData = originalEventData;
    }

    final eventId = eventData['id'] as String?;
    if (eventId == null) return;

    final noteAuthor = eventData['pubkey'] as String;
    final noteContentRaw = eventData['content'];
    String noteContent =
        noteContentRaw is String ? noteContentRaw : jsonEncode(noteContentRaw);
    final tags = eventData['tags'] as List<dynamic>? ?? [];

    if (eventIds.contains(eventId) || noteContent.trim().isEmpty) return;

    if (dataType == DataType.feed) {
      if (isRepost) {
        if (!targetNpubs.contains(author) && !targetNpubs.contains(noteAuthor))
          return;
      } else {
        if (!targetNpubs.contains(noteAuthor)) return;
      }
    } else if (dataType == DataType.profile) {
      if (isRepost) {
        if (author != npub && noteAuthor != npub) return;
      } else {
        if (noteAuthor != npub) return;
      }
    }

    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      (eventData['created_at'] as int) * 1000,
    );

    final rootTag = tags.firstWhereOrNull(
      (tag) => tag is List && tag.length >= 4 && tag[0] == 'e' && tag[3] == 'root',
    );
    final replyTag = tags.firstWhereOrNull(
      (tag) => tag is List && tag.length >= 4 && tag[0] == 'e' && tag[3] == 'reply',
    );

    final isReply = rootTag != null;
    final rootId = rootTag != null ? rootTag[1] : null;
    final parentId = replyTag != null ? replyTag[1] : rootId;

    final newNote = NoteModel(
      id: eventId,
      content: noteContent,
      author: noteAuthor,
      timestamp: timestamp,
      isRepost: isRepost,
      repostedBy: isRepost ? author : null,
      repostTimestamp: repostTimestamp,
      rawWs: isRepost ? repostRawWs : rawWs,
      isReply: isReply,
      rootId: rootId,
      parentId: parentId,
    );

    parseContentForNote(newNote);

    if (!eventIds.contains(newNote.id)) {
      notes.add(newNote);
      eventIds.add(newNote.id);
      if (notesBox != null && notesBox!.isOpen) {
        await notesBox!.put(newNote.id, newNote);
      }

      onNewNote?.call(newNote);
      addPendingNote(newNote);

      final fetchKeys = isRepost ? [noteAuthor, author] : [noteAuthor];
      await _fetchProfilesBatch(fetchKeys);
    }

    Future.microtask(() async {
      await Future.wait([
        fetchInteractionsForEvents([newNote.id]),
      ]);
    });
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
        await _fetchProfilesBatch([reaction.author]);
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
        await _fetchProfilesBatch([repost.repostedBy]);
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
        }

        final isRepost = eventData['kind'] == 6;
        final repostTimestamp =
            isRepost ? DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000) : null;

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
        );

        parseContentForNote(noteModel);

        if (!eventIds.contains(noteModel.id)) {
          notes.add(noteModel);
          eventIds.add(noteModel.id);
          await notesBox?.put(noteModel.id, noteModel);
          addPendingNote(noteModel);
        }

        notesNotifier.value = _itemsTree.toList();
        await _fetchProfilesBatch([reply.author]);
      }
    } catch (e) {
      print('[DataService ERROR] Error handling reply event: $e');
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
      try {
        final ws = await WebSocket.connect(relayUrl)
            .timeout(const Duration(seconds: 3));
        if (_isClosed) {
          await ws.close();
          return;
        }
        final request = _createRequest(
            Filter(authors: [targetNpub], kinds: [3], limit: 1000));
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
        await completer.future.timeout(const Duration(seconds: 3),
            onTimeout: () async {
          await ws.close();
        });
        await ws.close();
      } catch (e) {
        print('[DataService] Error fetching following from $relayUrl: $e');
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
      try {
        final ws = await WebSocket.connect(relayUrl)
            .timeout(const Duration(seconds: 2));

        if (_isClosed) {
          await ws.close();
          return;
        }

        final filter = Filter(
          kinds: [3],
          p: [targetNpub],
          limit: 1000,
        );

        final request = Request(generateUUID(), [filter]);
        final completer = Completer<void>();

        ws.listen((event) {
          final decoded = jsonDecode(event);
          if (decoded[0] == 'EVENT') {
            final author = decoded[2]['pubkey'];
            followers.add(author);
          }
          if (decoded[0] == 'EOSE') {
            if (!completer.isCompleted) completer.complete();
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete();
        });

        ws.add(request.serialize());

        await completer.future.timeout(const Duration(seconds: 3),
            onTimeout: () async {
          await ws.close();
        });

        await ws.close();
      } catch (e) {
        print(
            '[DataService] Error fetching global followers from $relayUrl: $e');
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
    if (_isClosed) return;
    String subscriptionId = generateUUID();
    List<String> allEventIds = notes.map((note) => note.id).toList();
    if (allEventIds.isEmpty) return;

    final filter = Filter(kinds: [7], e: allEventIds, limit: 1000);
    final request = Request(subscriptionId, [filter]);
    await _broadcastRequest(request);
  }

  Future<void> _subscribeToAllReplies() async {
    if (_isClosed) return;
    List<String> allEventIds = notes.map((n) => n.id).toList();
    if (allEventIds.isEmpty) return;
    final filter = Filter(kinds: [1], e: allEventIds, limit: 1000);
    await _broadcastRequest(_createRequest(filter));
  }

  Future<void> _subscribeToAllReposts() async {
    if (_isClosed) return;
    List<String> allEventIds = notes.map((n) => n.id).toList();
    if (allEventIds.isEmpty) return;
    final filter = Filter(kinds: [6], e: allEventIds, limit: 1000);
    await _broadcastRequest(_createRequest(filter));
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
          (key, cached) => now.difference(cached.fetchedAt) > profileCacheTTL);

      reactionsMap.forEach((eventId, reactions) {
        reactions.removeWhere(
            (reaction) => now.difference(reaction.fetchedAt) > profileCacheTTL);
      });

      repliesMap.forEach((eventId, replies) {
        replies.removeWhere(
            (reply) => now.difference(reply.fetchedAt) > profileCacheTTL);
      });

      await Future.wait([
        if (reactionsBox != null && reactionsBox!.isOpen)
          reactionsBox!.deleteAll(reactionsBox!.keys.where((key) {
            final reaction = reactionsBox!.get(key);
            return reaction != null &&
                now.difference(reaction.fetchedAt) > profileCacheTTL;
          })),
        if (repliesBox != null && repliesBox!.isOpen)
          repliesBox!.deleteAll(repliesBox!.keys.where((key) {
            final reply = repliesBox!.get(key);
            return reply != null &&
                now.difference(reply.fetchedAt) > profileCacheTTL;
          })),
      ]);

      print('[DataService] Performed cache cleanup.');
    });
    print('[DataService] Started cache cleanup timer.');
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

    final username = parts[0];
    final domain = parts[1];

    final uri = Uri.parse('https://$domain/.well-known/lnurlp/$username');
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

      final tags = [
        ['e', parentNote.id, '', 'root'],
        ['e', parentEventId, '', 'reply'],
        ['p', parentNote.author],
      ];

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

      final note = notes.firstWhereOrNull((n) => n.id == parentEventId);
      if (note != null) {
        note.replyCount = repliesMap[parentEventId]!.length;
      }

      onRepliesUpdated?.call(parentEventId, repliesMap[parentEventId]!);
      notesNotifier.value = _itemsTree.toList();
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
    if (notesBox != null && notesBox!.isOpen) {
      try {
        final Map<String, NoteModel> notesMap = {
          for (var note in notes.take(200)) note.id: note
        };
        await notesBox!.clear();
        await notesBox!.putAll(notesMap);
        print(
            '[DataService] Notes saved to cache successfully. (${notesMap.length} notes)');
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

      allNotes.sort((a, b) {
        final aTime =
            a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
        final bTime =
            b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
        return bTime.compareTo(aTime);
      });

      final limitedNotes = allNotes.take(200).toList();

      for (final note in limitedNotes) {
        if (!eventIds.contains(note.id)) {
          parseContentForNote(note);
          notes.add(note);
          eventIds.add(note.id);
          _addNote(note);
        }

        note.reactionCount = reactionsMap[note.id]?.length ?? 0;
        note.replyCount = repliesMap[note.id]?.length ?? 0;
        note.repostCount = repostsMap[note.id]?.length ?? 0;
        note.zapAmount =
            zapsMap[note.id]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
      }

      notesNotifier.value = _itemsTree.toList();
      onLoad(limitedNotes);

      final cachedEventIds = limitedNotes.map((note) => note.id).toList();

      Future.microtask(() async {
        await Future.wait([
          fetchInteractionsForEvents(cachedEventIds),
        ]);
      });

      Future.microtask(() async {
        await _fetchProfilesForAllData();
        profilesNotifier.value = {
          for (var entry in profileCache.entries)
            entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data),
        };
      });
    } catch (e) {
      print('[DataService ERROR] Error loading notes from cache: $e');
    }
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
      final int kind = parsedData['kind'];
      final Map<String, dynamic> eventData = parsedData['eventData'];
      final List<String> targetNpubs = parsedData['targetNpubs'];

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
        final rootTag = tags.firstWhere(
          (tag) => tag is List && tag.isNotEmpty && tag[0] == 'e' && tag.contains('root'),
          orElse: () => null,
        );

        if (rootTag != null && rootTag is List && rootTag.length >= 2) {
          final rootId = rootTag[1] as String;
          await _handleReplyEvent(eventData, rootId);
        } else {
          await _processNoteEvent(eventData, targetNpubs, rawWs: jsonEncode(eventData));
        }
      } else if (kind == 6) {
        await _handleRepostEvent(eventData);
        await _processNoteEvent(eventData, targetNpubs);
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
    Set<String> allAuthors = notes.map((note) => note.author).toSet();

    for (var replies in repliesMap.values) {
      allAuthors.addAll(replies.map((reply) => reply.author));
    }
    for (var reactions in reactionsMap.values) {
      allAuthors.addAll(reactions.map((reaction) => reaction.author));
    }

    await _fetchProfilesBatch(allAuthors.toList());
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
        final decoded = jsonDecode(event);
        if (decoded is List && decoded.length >= 2) {
          if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
            completer.complete(decoded[2]);
          } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
            if (!completer.isCompleted) completer.complete(null);
          }
        }
      }, onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });

      ws.add(request);
      final eventData = await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      await sub.cancel();
      await ws.close();

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
        final decoded = jsonDecode(event);

        if (decoded is List && decoded.length >= 2) {
          if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
            completer.complete(decoded[2]);
          } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        }
      }, onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });

      ws.add(request);

      final eventData = await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () {
        return null;
      });

      await sub.cancel();
      await ws.close();

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
