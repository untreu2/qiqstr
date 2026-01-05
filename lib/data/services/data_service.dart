import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';
import '../../models/notification_model.dart';
import '../../models/reaction_model.dart';
import '../../models/zap_model.dart';
import 'nostr_service.dart';
import 'relay_service.dart';
import 'time_service.dart';
import '../../constants/relays.dart';
import 'auth_service.dart';
import 'user_cache_service.dart';
import 'follow_cache_service.dart';
import 'mute_cache_service.dart';
import 'primal_cache_service.dart';

class DataService {
  final AuthService _authService;
  final WebSocketManager _relayManager;
  final UserCacheService _userCacheService = UserCacheService.instance;
  final FollowCacheService _followCacheService = FollowCacheService.instance;
  final MuteCacheService _muteCacheService = MuteCacheService.instance;

  final StreamController<List<NoteModel>> _notesController = StreamController<List<NoteModel>>.broadcast();
  final StreamController<List<UserModel>> _usersController = StreamController<List<UserModel>>.broadcast();
  final StreamController<List<NotificationModel>> _notificationsController = StreamController<List<NotificationModel>>.broadcast();
  final StreamController<String> _noteDeletedController = StreamController<String>.broadcast();

  final Map<String, NoteModel> _noteCache = {};
  final Map<String, CachedProfile> _profileCache = {};
  final Map<String, List<NotificationModel>> _notificationCache = {};
  final Map<String, List<ReactionModel>> _reactionsMap = {};
  final Map<String, List<ZapModel>> _zapsMap = {};
  final Map<String, List<ReactionModel>> _repostsMap = {};
  final Set<String> _eventIds = {};
  final Set<String> _processedZapIds = {};
  final Set<String> _userPublishedZapIds = {};

  final Set<String> _pendingOptimisticReactionIds = {};
  final Duration _profileCacheTTL = const Duration(minutes: 30);

  final List<Map<String, dynamic>> _eventQueue = [];
  Timer? _batchProcessingTimer;
  static const int _maxBatchSize = 50;
  static const Duration _batchTimeout = Duration(milliseconds: 30);

  bool _isClosed = false;
  String _currentUserNpub = '';

  Timer? _uiUpdateThrottleTimer;
  bool _uiUpdatePending = false;
  static const Duration _uiUpdateThrottle = Duration(milliseconds: 200);
  int _uiUpdateCounter = 0;

  final Map<String, DateTime> _lastInteractionFetch = {};
  final Map<String, bool> _eventProcessingLock = {};
  final Set<String> _processedInteractionIds = {};

  bool _notificationSubscriptionActive = false;
  String? _notificationSubscriptionId;

  final Map<String, int> _interactionFetchPriority = {};
  Timer? _interactionFetchTimer;
  static const Duration _interactionFetchDebounce = Duration(milliseconds: 500);
  static const Duration _interactionFetchTTL = Duration(seconds: 60);
  static const int _maxInteractionBatchSize = 50;
  static const int _maxRelayQueriesPerSecond = 3;
  DateTime _lastRelayQueryTime = DateTime(2000);

  DataService({
    required AuthService authService,
    WebSocketManager? relayManager,
  })  : _authService = authService,
        _relayManager = relayManager ?? WebSocketManager.instance {
    _setupRelayEventHandling();
    _startCacheCleanup();
  }

  Stream<List<NoteModel>> get notesStream => _notesController.stream;
  Stream<List<UserModel>> get usersStream => _usersController.stream;
  Stream<List<NotificationModel>> get notificationsStream => _notificationsController.stream;
  Stream<String> get noteDeletedStream => _noteDeletedController.stream;

  AuthService get authService => _authService;
  String get currentUserNpub => _currentUserNpub;

  static const int _profileCacheMaxSize = 2000;
  static const int _interactionFetchMaxSize = 3000;
  static const int _eventProcessingLockMaxSize = 10000;
  static const int _noteCacheMaxSize = 8000;
  static const int _noteCacheKeepSize = 5000;
  static const Duration _interactionCutoff = Duration(hours: 1);
  static const int _queryTimeoutSeconds = 3;
  static const int _longQueryTimeoutSeconds = 30;
  static const int _followerCountTimeoutSeconds = 5;
  static const int _profileFetchTimeoutMs = 1500;

  bool _shouldIncludeNoteInFeed(String authorHexPubkey, bool isRepost) {
    return true;
  }

  Map<String, String> _parseETag(List<dynamic> tag) {
    return {
      'eventId': tag[1] as String,
      'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
      'marker': tag.length >= 4 ? tag[3] as String : '',
      'pubkey': tag.length > 4 ? (tag[4] as String? ?? '') : '',
    };
  }

  Map<String, String> _parsePTag(List<dynamic> tag) {
    return {
      'pubkey': tag[1] as String,
      'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
      'petname': tag.length > 3 ? (tag[3] as String? ?? '') : '',
    };
  }

  String? _getTagValue(List<dynamic> tags, String tagType, {int index = 1}) {
    for (final tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == tagType && tag.length > index) {
        return tag[index] as String?;
      }
    }
    return null;
  }

  List<String> _extractPTags(List<dynamic> tags) {
    final result = <String>[];
    for (final tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
        result.add(tag[1] as String);
      }
    }
    return result;
  }

  ParsedTags _parseTags(List<dynamic> tags, {bool includeTTags = true}) {
    final eTags = <Map<String, String>>[];
    final pTags = <Map<String, String>>[];
    final tTags = <String>{};
    String? rootId;
    String? parentId;

    for (final tag in tags) {
      if (tag is! List || tag.isEmpty) continue;
      
      final tagType = tag[0] as String?;
      if (tagType == null || tag.length < 2) continue;

      if (tagType == 'e') {
        final eTag = _parseETag(tag);
        eTags.add(eTag);
        final marker = eTag['marker'] ?? '';
        if (marker == 'root') {
          rootId = eTag['eventId'];
        } else if (marker == 'reply') {
          parentId = eTag['eventId'];
        }
      } else if (tagType == 'p') {
        pTags.add(_parsePTag(tag));
      } else if (tagType == 't' && includeTTags) {
        final hashtag = (tag[1] as String).toLowerCase();
        tTags.add(hashtag);
      }
    }

    return ParsedTags(
      eTags: eTags,
      pTags: pTags,
      tTags: tTags.toList(),
      rootId: rootId,
      parentId: parentId,
    );
  }

  Future<void> _ensureRelayConnection([String? serviceId]) async {
    if (_relayManager.activeSockets.isEmpty) {
      try {
        await _relayManager.connectRelays(
          [],
          onEvent: _handleRelayEvent,
          onDisconnected: _handleRelayDisconnection,
          serviceId: serviceId ?? 'data_service_connection',
        );
      } catch (_) {}
    }
  }

  List<String> get _allRelays => _relayManager.relayUrls.toList();

  String _extractSubscriptionId(String serializedRequest) {
    final requestJson = jsonDecode(serializedRequest) as List;
    return requestJson[1] as String;
  }

  Future<void> _queryAllRelays({
    required String request,
    required String subscriptionId,
    required Function(Map<String, dynamic>, String) onEvent,
    Duration? timeout,
    bool checkClosed = true,
  }) async {
    final allRelays = _allRelays;
    if (allRelays.isEmpty) return;

    await Future.wait(allRelays.map((relayUrl) async {
      try {
        if (checkClosed && _isClosed) return;

        final completer = await _relayManager.sendQuery(
          relayUrl,
          request,
          subscriptionId,
          timeout: timeout ?? const Duration(seconds: _queryTimeoutSeconds),
          onEvent: onEvent,
        );

        await completer.future;
      } catch (_) {}
    }));
  }

  void _setupRelayEventHandling() {
    _relayManager.connectRelays(
      [],
      onEvent: _handleRelayEvent,
      onDisconnected: _handleRelayDisconnection,
      serviceId: 'nostr_data_service',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFollowListCache();
    });
  }

  Future<void> _initializeFollowListCache() async {
    try {
      final currentUser = await _authService.getCurrentUserNpub();
      if (currentUser.isSuccess && currentUser.data != null) {
        _currentUserNpub = currentUser.data!;
        final currentUserHex = _authService.npubToHex(_currentUserNpub) ?? _currentUserNpub;

        final cachedFollowing = await _followCacheService.get(currentUserHex);
        final cachedMuted = await _muteCacheService.get(currentUserHex);

        final hasValidFollowing = cachedFollowing != null && cachedFollowing.isNotEmpty;
        final hasValidMuted = cachedMuted != null && cachedMuted.isNotEmpty;

        if (hasValidMuted) {
          _cleanMutedNotesFromCache(cachedMuted);
        }

        if (!hasValidFollowing || !hasValidMuted) {
          final result = await _fetchUserListsCombined(currentUserHex);

          if (result['following'] != null) {
            await _followCacheService.put(currentUserHex, result['following']!);
          }

          if (result['muted'] != null) {
            await _muteCacheService.put(currentUserHex, result['muted']!);
            if (result['muted']!.isNotEmpty) {
              _cleanMutedNotesFromCache(result['muted']!);
            }
          }
        } else {
          unawaited(_fetchAndUpdateUserLists(currentUserHex));
        }

        await _fetchFeedNotesFromFollowList();
      } else {
      }
    } catch (e) {
      try {
        await _fetchFeedNotesFromFollowList();
      } catch (feedError) {
      }
    }
  }

  Future<void> _fetchFeedNotesFromFollowList() async {
    try {
      final currentUser = await _authService.getCurrentUserNpub();
      if (currentUser.isSuccess && currentUser.data != null && currentUser.data!.isNotEmpty) {
        final currentUserNpub = currentUser.data!;
        final currentUserHex = _authService.npubToHex(currentUserNpub);
        
        if (currentUserHex == null) {
          return;
        }

        final followList = await _followCacheService.get(currentUserHex);
        
        if (followList == null || followList.isEmpty) {
          return;
        }

        final targetAuthors = List<String>.from(followList);
        targetAuthors.add(currentUserHex);
        
        final filter = NostrService.createNotesFilter(
          authors: targetAuthors,
          kinds: [1, 6],
          limit: 30,
        );

        final request = NostrService.createRequest(filter);
        await _relayManager.broadcast(NostrService.serializeRequest(request));
      }
    } catch (e) {
    }
  }

  Future<void> _fetchAndUpdateUserLists(String currentUserHex) async {
    try {
      final result = await _fetchUserListsCombined(currentUserHex);

      if (result['following'] != null) {
        await _followCacheService.put(currentUserHex, result['following']!);
      }

      if (result['muted'] != null) {
        await _muteCacheService.put(currentUserHex, result['muted']!);
        if (result['muted']!.isNotEmpty) {
          _cleanMutedNotesFromCache(result['muted']!);
        }
      }
    } catch (e) {
    }
  }

  Future<Map<String, dynamic>> _fetchUserListsCombined(String pubkeyHex) async {
    final following = <String>{};
    final muted = <String>{};
    final processedEventIds = <String>{};
    Map<String, dynamic>? userProfile;

    final filter = {
      'authors': [pubkeyHex],
      'kinds': [0, 3, 10000],
      'limit': 3,
    };

    final subscriptionId = NostrService.generateUUID();
    final request = jsonEncode(['REQ', subscriptionId, filter]);

    await _queryAllRelays(
      request: request,
      subscriptionId: subscriptionId,
      onEvent: (eventData, url) {
        try {
          final eventId = eventData['id'] as String;
          final eventKind = eventData['kind'] as int;
          final eventAuthor = eventData['pubkey'] as String;

          if (eventAuthor == pubkeyHex && !processedEventIds.contains(eventId)) {
            processedEventIds.add(eventId);

            if (eventKind == 0) {
              final content = eventData['content'] as String;
              if (content.isNotEmpty && userProfile == null) {
                try {
                  userProfile = jsonDecode(content) as Map<String, dynamic>;
                  userProfile!['pubkey'] = pubkeyHex;
                  userProfile!['created_at'] = eventData['created_at'];
                } catch (_) {}
              }
            } else if (eventKind == 3) {
              following.addAll(_extractPTags(eventData['tags'] as List<dynamic>));
            } else if (eventKind == 10000) {
              muted.addAll(_extractPTags(eventData['tags'] as List<dynamic>));
            }
          }
        } catch (_) {}
      },
    );

    if (userProfile != null) {
      final createdAt = userProfile!['created_at'] as int? ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      _processProfileEvent({
        'pubkey': pubkeyHex,
        'content': jsonEncode(userProfile),
        'created_at': createdAt,
        'kind': 0,
      });
    }

    return {
      'following': following.toList(),
      'muted': muted.toList(),
      'profile': userProfile,
    };
  }


  Future<void> _handleRelayEvent(List<dynamic> decoded, String relayUrl) async {
    try {
      if (decoded.isEmpty) return;
      final messageType = decoded[0];

      if (messageType == 'EVENT' && decoded.length >= 3) {
        final event = decoded[2] as Map<String, dynamic>;

        _eventQueue.add({
          'eventData': event,
          'relayUrl': relayUrl,
          'timestamp': timeService.millisecondsSinceEpoch,
        });

        if (_eventQueue.length >= _maxBatchSize) {
          _flushEventQueue();
        } else {
          _batchProcessingTimer ??= Timer(_batchTimeout, _flushEventQueue);
        }
      } else if (messageType == 'COUNT' && decoded.length >= 3) {
        _handleCountResponse(decoded);
      } else if (messageType == 'CLOSED' && decoded.length >= 2) {
        _handleClosedMessage(decoded);
      }
    } catch (_) {}
  }

  void _flushEventQueue() {
    if (_eventQueue.isEmpty) return;

    _batchProcessingTimer?.cancel();
    _batchProcessingTimer = null;

    final batch = List<Map<String, dynamic>>.from(_eventQueue);
    _eventQueue.clear();

    Future.microtask(() async {
      await Future.wait(
        batch.map((eventData) => 
          _processNostrEvent(eventData['eventData'] as Map<String, dynamic>)
            .catchError((e) => null)
        ),
        eagerError: false,
      );
      _scheduleUIUpdate();
    });
  }

  Future<void> _processNostrEvent(Map<String, dynamic> eventData) async {
    try {
      final eventId = eventData['id'] as String? ?? '';
      if (eventId.isEmpty) return;

      if (_eventProcessingLock[eventId] == true) return;
      _eventProcessingLock[eventId] = true;

      final kind = eventData['kind'] as int;
      final eventAuthor = eventData['pubkey'] as String? ?? '';

      if (eventAuthor.isNotEmpty && eventAuthor != _currentUserNpub) {
        _processNotificationFast(eventData, kind, eventAuthor);
      }

      switch (kind) {
        case 0:
          _processProfileEvent(eventData);
          break;
        case 1:
          await _processKind1Event(eventData);
          break;
        case 3:
          await _processFollowEvent(eventData);
          break;
        case 5:
          await _processDeletionEvent(eventData);
          break;
        case 6:
          await _processRepostEvent(eventData);
          break;
        case 7:
          _processReactionEvent(eventData);
          break;
        case 10000:
          await _processMuteEvent(eventData);
          break;
        case 9735:
          _processZapEvent(eventData);
          break;
      }

      _eventProcessingLock.remove(eventId);
    } catch (e) {
    }
  }

  void _processProfileEvent(Map<String, dynamic> eventData) {
    try {
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      final cachedProfile = _profileCache[pubkey];
      if (cachedProfile != null && timestamp.isBefore(cachedProfile.fetchedAt)) {
        return;
      }

      if (content.isNotEmpty) {
        Map<String, dynamic> profileData;
        try {
          profileData = jsonDecode(content) as Map<String, dynamic>;
        } catch (e) {
          profileData = {};
        }

        final nip05 = profileData['nip05'] as String? ?? '';

        _verifyAndCacheProfile(pubkey, profileData, timestamp, nip05);
      }
    } catch (e) {
    }
  }

  Future<void> _verifyAndCacheProfile(String pubkey, Map<String, dynamic> profileData, DateTime timestamp, String nip05) async {
    final dataToCache = {
      'name': profileData['name'] as String? ?? 'Anonymous',
      'profileImage': profileData['picture'] as String? ?? '',
      'about': profileData['about'] as String? ?? '',
      'nip05': nip05,
      'banner': profileData['banner'] as String? ?? '',
      'lud16': profileData['lud16'] as String? ?? '',
      'website': profileData['website'] as String? ?? '',
      'nip05Verified': 'false',
    };

    _profileCache.remove(pubkey);
    _profileCache[pubkey] = CachedProfile(dataToCache, timestamp);
    _cleanupCacheIfNeeded();

    final user = UserModel.create(
      pubkeyHex: pubkey,
      name: dataToCache['name']!,
      about: dataToCache['about']!,
      profileImage: dataToCache['profileImage']!,
      banner: dataToCache['banner']!,
      website: dataToCache['website']!,
      nip05: dataToCache['nip05']!,
      lud16: dataToCache['lud16']!,
      updatedAt: timestamp,
      nip05Verified: false,
    );

      try {
        await _userCacheService.invalidate(pubkey);
        await _userCacheService.put(user);
      } catch (e) {
      }

      if (!_usersController.isClosed) {
        _usersController.add(_getUsersList());
      }
  }

  Future<void> _processKind1Event(Map<String, dynamic> eventData) async {
    try {
      final tags = List<dynamic>.from(eventData['tags'] ?? []);
      String? firstETag;
      String? rootId;
      String? replyId;

      for (var tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
          final eventId = tag.length >= 2 ? tag[1] as String? : null;
          if (eventId == null || eventId.isEmpty) continue;

          firstETag ??= eventId;

          if (tag.length >= 4) {
            final marker = tag[3] as String?;
            if (marker == 'root') {
              rootId = eventId;
            } else if (marker == 'reply') {
              replyId = eventId;
            }
          }
        }
      }

      if (rootId != null || replyId != null || firstETag != null) {
        final parentId = replyId ?? rootId ?? firstETag!;
        await _handleReplyEvent(eventData, parentId);
      } else {
        await _processNoteEvent(eventData);
      }
    } catch (e) {
    }
  }

  Future<void> _processNoteEvent(Map<String, dynamic> eventData) async {
    try {
      final id = eventData['id'] as String;
      
      if (_eventIds.contains(id)) return;

      final pubkey = eventData['pubkey'] as String;
      
      final currentUserHex = _authService.npubToHex(_currentUserNpub);
      if (currentUserHex != null) {
        final mutedList = _muteCacheService.getSync(currentUserHex);
        if (mutedList != null && mutedList.contains(pubkey)) {
          return;
        }
      }

      if (!_shouldIncludeNoteInFeed(pubkey, false)) {
        return;
      }

      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      unawaited(_ensureProfileExists(pubkey, authorNpub));

      final parsedTags = _parseTags(tags);
      final isReply = parsedTags.rootId != null;

      final note = NoteModel(
        id: id,
        content: content,
        author: authorNpub,
        timestamp: timestamp,
        isReply: isReply,
        isRepost: false,
        rootId: parsedTags.rootId,
        parentId: parsedTags.parentId,
        repostedBy: null,
        reactionCount: _reactionsMap[id]?.length ?? 0,
        replyCount: 0,
        repostCount: _repostsMap[id]?.length ?? 0,
        zapAmount: _zapsMap[id]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0,
        rawWs: jsonEncode(eventData),
        eTags: parsedTags.eTags,
        pTags: parsedTags.pTags,
        tTags: parsedTags.tTags,
      );

      _addNoteToCache(note);

      if (isReply) {
        if (parsedTags.parentId != null) {
          _noteCache[parsedTags.parentId]?.addReply(note);
        }
        if (parsedTags.rootId != null && parsedTags.rootId != parsedTags.parentId) {
          _noteCache[parsedTags.rootId]?.addReply(note);
        }
      }
    } catch (e) {
    }
  }

  final Set<String> _pendingThreadFetches = {};

  Future<void> fetchThreadRepliesForNote(String rootNoteId) async {
    return _fetchThreadRepliesForNote(rootNoteId);
  }

  Future<void> _fetchThreadRepliesForNote(String rootNoteId) async {
    if (_pendingThreadFetches.contains(rootNoteId)) {
      return;
    }

    _pendingThreadFetches.add(rootNoteId);

    try {
      final filter = NostrService.createThreadRepliesFilter(
        rootNoteId: rootNoteId,
        limit: 100,
      );

      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);
      final actualSubscriptionId = _extractSubscriptionId(serializedRequest);
      final processedReplyIds = <String>{};

      await _queryAllRelays(
        request: serializedRequest,
        subscriptionId: actualSubscriptionId,
        timeout: const Duration(seconds: _queryTimeoutSeconds),
        onEvent: (eventData, url) {
          try {
            final eventId = eventData['id'] as String;
            final eventKind = eventData['kind'] as int;

            if (eventKind == 1 && !processedReplyIds.contains(eventId)) {
              processedReplyIds.add(eventId);
              unawaited(_processNostrEvent(eventData));
            }
          } catch (_) {}
        },
      );

      _pendingThreadFetches.remove(rootNoteId);
    } catch (e) {
      _pendingThreadFetches.remove(rootNoteId);
    }
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    try {
      final id = eventData['id'] as String;
      
      if (_eventIds.contains(id)) return;

      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      final parsedTags = _parseTags(tags);
      final actualParentId = parsedTags.parentId ?? parentEventId;
      final rootId = parsedTags.rootId;
      final replyMarker = rootId != null ? 'root' : (parsedTags.parentId != null ? 'reply' : null);
      final parentNote = _noteCache[actualParentId];

      final replyNote = NoteModel(
        id: id,
        content: content,
        author: authorNpub,
        timestamp: timestamp,
        isReply: true,
        parentId: actualParentId,
        rootId: rootId ?? parentNote?.rootId,
        rawWs: jsonEncode(eventData),
        eTags: parsedTags.eTags,
        pTags: parsedTags.pTags,
        tTags: parsedTags.tTags,
        replyMarker: replyMarker,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
      );

      _addNoteToCache(replyNote);

      _ensureProfileExists(pubkey, authorNpub);

      _updateParentNoteReplyCount(actualParentId);

      _scheduleUIUpdate();
    } catch (e) {
    }
  }

  void _processReactionEvent(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String;
      
      if (_pendingOptimisticReactionIds.contains(id)) {
        _pendingOptimisticReactionIds.remove(id);
        return;
      }

      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      final targetEventId = _getTagValue(tags, 'e');

      if (targetEventId != null) {
        final reaction = ReactionModel(
          id: id,
          targetEventId: targetEventId,
          content: content,
          author: _authService.hexToNpub(pubkey) ?? pubkey,
          timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
          fetchedAt: DateTime.now(),
        );

        _noteCache[targetEventId]?.addReaction(reaction);

        final reactions = _reactionsMap.putIfAbsent(targetEventId, () => []);
        if (!reactions.any((r) => r.id == reaction.id)) {
          reactions.add(reaction);
        }
      }
    } catch (e) {
    }
  }

  Future<void> _processRepostEvent(Map<String, dynamic> eventData) async {
    try {
      final id = eventData['id'] as String;
      
      _trackRepostForCount(eventData);

      if (_eventIds.contains(id)) return;

      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;
      final content = eventData['content'] as String? ?? '';

      final currentUserHex = _authService.npubToHex(_currentUserNpub);
      if (currentUserHex != null) {
        final mutedList = _muteCacheService.getSync(currentUserHex);
        if (mutedList != null && mutedList.contains(pubkey)) {
          return;
        }
      }

      if (!_shouldIncludeNoteInFeed(pubkey, true)) {
        return;
      }

      String? originalEventId;
      String? originalAuthorHex;

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          if (tag[0] == 'e' && tag.length >= 2) {
            originalEventId = tag[1] as String;
          } else if (tag[0] == 'p' && tag.length >= 2) {
            originalAuthorHex = tag[1] as String;
          }
        }
      }

      if (originalEventId != null) {
        final reposterNpub = _authService.hexToNpub(pubkey) ?? pubkey;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

        _ensureProfileExists(pubkey, reposterNpub);
        if (originalAuthorHex != null) {
          final originalAuthorNpub = _authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex;
          _ensureProfileExists(originalAuthorHex, originalAuthorNpub);
        }


        bool detectedIsReply = false;
        String? detectedRootId;
        String? detectedParentId;

        final originalNote = _noteCache[originalEventId];
        String displayContent = 'Reposted note';
        String displayAuthor = originalAuthorHex != null ? (_authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex) : 'Unknown';

        if (originalNote != null) {
          detectedIsReply = originalNote.isReply;
          detectedRootId = originalNote.rootId;
          detectedParentId = originalNote.parentId;
        }

        if (originalNote != null) {
          displayContent = originalNote.content;
          displayAuthor = originalNote.author;
        } else if (content.isNotEmpty) {

          try {
            final originalContent = jsonDecode(content) as Map<String, dynamic>;

            displayContent = originalContent['content'] as String? ?? displayContent;
            if (originalAuthorHex != null) {
              displayAuthor = _authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex;
            }

            final originalTags = originalContent['tags'] as List<dynamic>? ?? [];


            for (int i = 0; i < originalTags.length; i++) {
              final tag = originalTags[i];

              if (tag is List && tag.length >= 2 && tag[0] == 'e') {
                final eventId = tag[1] as String;

                if (tag.length >= 4) {
                  final marker = tag[3] as String;
                  if (marker == 'root') {
                    detectedRootId = eventId;
                    detectedParentId = eventId;
                    detectedIsReply = true;
                  } else if (marker == 'reply') {
                    detectedParentId = eventId;
                    detectedIsReply = true;
                  } else if (marker == 'mention') {
                  } else {
                  }
                } else {
                  if (detectedParentId == null) {
                    detectedParentId = eventId;
                    detectedRootId = eventId;
                    detectedIsReply = true;
                  }
                }
              }
            }


            if (originalAuthorHex != null && !_noteCache.containsKey(originalEventId)) {
              final originalNoteFromRepost = NoteModel(
                id: originalEventId,
                content: displayContent,
                author: displayAuthor,
                timestamp: DateTime.fromMillisecondsSinceEpoch((originalContent['created_at'] as int? ?? createdAt) * 1000),
                isReply: detectedIsReply,
                isRepost: false,
                rootId: detectedRootId,
                parentId: detectedParentId,
                reactionCount: 0,
                replyCount: 0,
                repostCount: 0,
                zapAmount: 0,
                rawWs: content,
              );

              _addNoteToCache(originalNoteFromRepost);
            }
          } catch (e) {
            displayContent = content.isNotEmpty ? content : displayContent;
          }
        }

        final finalIsReply = detectedIsReply;
        final finalRootId = detectedRootId;
        final finalParentId = detectedParentId;


        final repostNote = NoteModel(
          id: id,
          content: displayContent,
          author: displayAuthor,
          timestamp: timestamp,
          isReply: finalIsReply,
          isRepost: true,
          rootId: finalRootId ?? originalEventId,
          parentId: finalParentId,
          repostedBy: reposterNpub,
          repostTimestamp: timestamp,
          reactionCount: 0,
          replyCount: 0,
          repostCount: 0,
          zapAmount: 0,
          rawWs: jsonEncode(eventData),
        );


        if (repostNote.isReply && repostNote.parentId != null) {
        } else {
        }

        _addNoteToCache(repostNote);

        final targetNote = _noteCache[originalEventId];
        if (targetNote != null) {
          targetNote.repostCount = _repostsMap[originalEventId]?.length ?? 0;
        }
      
        _scheduleUIUpdate();
      }
    } catch (e) {
    }
  }

  void _trackRepostForCount(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      final originalEventId = _getTagValue(tags, 'e');

      if (originalEventId != null) {
        final reposterNpub = _authService.hexToNpub(pubkey) ?? pubkey;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

        final repost = ReactionModel(
          id: id,
          targetEventId: originalEventId,
          content: '',
          author: reposterNpub,
          timestamp: timestamp,
          fetchedAt: DateTime.now(),
        );

        _repostsMap.putIfAbsent(originalEventId, () => []);
        if (!_repostsMap[originalEventId]!.any((r) => r.id == repost.id)) {
          _repostsMap[originalEventId]!.add(repost);

          final targetNote = _noteCache[originalEventId];
          if (targetNote != null) {
            targetNote.repostCount = _repostsMap[originalEventId]!.length;
          }

        }
      }
    } catch (e) {
    }
  }

  Future<void> _processFollowEvent(Map<String, dynamic> eventData) async {
    try {
      final pubkey = eventData['pubkey'] as String;
      final tags = eventData['tags'] as List<dynamic>;
      final newFollowing = _extractPTags(tags);

      try {
        await _followCacheService.put(pubkey, newFollowing);
      } catch (_) {}
    } catch (e) {
    }
  }

  Future<void> _processMuteEvent(Map<String, dynamic> eventData) async {
    try {
      final pubkey = eventData['pubkey'] as String;
      final tags = eventData['tags'] as List<dynamic>;
      final newMuted = _extractPTags(tags);

      try {
        await _muteCacheService.put(pubkey, newMuted);
      } catch (_) {}
    } catch (e) {
    }
  }

  Future<void> _processDeletionEvent(Map<String, dynamic> eventData) async {
    try {
      final tags = eventData['tags'] as List<dynamic>;

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'e' && tag.length >= 2) {
          final deletedNoteId = tag[1] as String;

          if (_noteCache.containsKey(deletedNoteId)) {
            _noteCache.remove(deletedNoteId);
            _eventIds.remove(deletedNoteId);
            _reactionsMap.remove(deletedNoteId);
            _repostsMap.remove(deletedNoteId);
            _zapsMap.remove(deletedNoteId);

            if (!_isClosed && !_noteDeletedController.isClosed) {
              _noteDeletedController.add(deletedNoteId);
            }
          }
        }
      }
    } catch (e) {
    }
  }

  void markZapAsUserPublished(String zapEventId) {
    _userPublishedZapIds.add(zapEventId);
  }

  void _processZapEvent(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String;
      final walletPubkey = eventData['pubkey'] as String;

      if (_processedZapIds.contains(id)) {
        return;
      }

      if (_userPublishedZapIds.contains(id)) {
        return;
      }

      final currentUserHex = _authService.npubToHex(_currentUserNpub);
      if (currentUserHex != null && walletPubkey == currentUserHex) {
        return;
      }
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      final targetEventId = _getTagValue(tags, 'e');
      final recipient = _getTagValue(tags, 'p') ?? '';
      final bolt11 = _getTagValue(tags, 'bolt11') ?? '';
      final description = _getTagValue(tags, 'description') ?? '';
      
      int amount = 0;
      final amountStr = _getTagValue(tags, 'amount');
      if (amountStr != null) {
        try {
          amount = int.parse(amountStr) ~/ 1000;
        } catch (_) {
          amount = 0;
        }
      }

      String realZapperPubkey = walletPubkey;
      String? zapComment;

      if (description.isNotEmpty) {
        try {
          final zapRequest = jsonDecode(description) as Map<String, dynamic>;
          realZapperPubkey = zapRequest['pubkey'] as String? ?? walletPubkey;
          final requestContent = zapRequest['content'] as String?;
          if (requestContent?.isNotEmpty == true) {
            zapComment = requestContent;
          }
        } catch (_) {}
      }

      if (amount == 0 && bolt11.isNotEmpty) {
        try {
          amount = parseAmountFromBolt11(bolt11);
        } catch (_) {
          amount = 0;
        }
      }

      if (targetEventId != null) {
        final zap = ZapModel(
          id: id,
          sender: _authService.hexToNpub(realZapperPubkey) ?? realZapperPubkey,
          recipient: _authService.hexToNpub(recipient) ?? recipient,
          targetEventId: targetEventId,
          timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
          bolt11: bolt11,
          comment: zapComment ?? (content.isNotEmpty ? content : null),
          amount: amount,
        );

        final targetNote = _noteCache[targetEventId];
        if (targetNote != null) {
          targetNote.addZap(zap);
          _scheduleUIUpdate();
        }

        final zaps = _zapsMap.putIfAbsent(targetEventId, () => []);
        if (!zaps.any((z) => z.id == zap.id)) {
          zaps.add(zap);
          _processedZapIds.add(id);
        }
      }
    } catch (e) {
    }
  }

  void _processNotificationFast(Map<String, dynamic> eventData, int kind, String eventAuthor) {
    if (![1, 6, 7, 9735].contains(kind)) return;
    if (_currentUserNpub.isEmpty) return;

    final currentUserHex = _authService.npubToHex(_currentUserNpub);
    if (currentUserHex == null) return;

    final List<dynamic> eventTags = List<dynamic>.from(eventData['tags'] ?? []);
    bool isUserMentioned = false;

    for (var tag in eventTags) {
      if (tag is List && tag.length >= 2 && tag[0] == 'p') {
        final mentionedUserHex = tag[1] as String;
        if (mentionedUserHex == currentUserHex) {
          isUserMentioned = true;
          break;
        }
      }
    }

    if (!isUserMentioned) return;

    String notificationType;
    switch (kind) {
      case 1:
        notificationType = "mention";
        break;
      case 6:
        notificationType = "repost";
        break;
      case 7:
        notificationType = "reaction";
        break;
      case 9735:
        notificationType = "zap";
        break;
      default:
        return;
    }

    try {
      final notification = NotificationModel.fromEvent(eventData, notificationType);

      final authorNpub = _authService.hexToNpub(notification.author) ?? notification.author;
      final updatedNotification = NotificationModel(
        id: notification.id,
        targetEventId: notification.targetEventId,
        author: authorNpub,
        type: notification.type,
        content: notification.content,
        timestamp: notification.timestamp,
        fetchedAt: notification.fetchedAt,
        isRead: notification.isRead,
        amount: notification.amount,
      );

      final notifications = _notificationCache.putIfAbsent(_currentUserNpub, () => []);
      if (!notifications.any((n) => n.id == updatedNotification.id)) {
        notifications.add(updatedNotification);
        notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (!_notificationsController.isClosed) {
          _notificationsController.add(notifications);
        }
      }
    } catch (e) {
    }
  }

  void _handleRelayDisconnection(String relayUrl) {
  }

  void _startCacheCleanup() {}

  void _scheduleInteractionFetch(String noteId, {int priority = 0}) {
    if (_isClosed) return;

    final now = timeService.now;
    final lastFetch = _lastInteractionFetch[noteId];

    if (lastFetch != null && now.difference(lastFetch) < _interactionFetchTTL) {
      return;
    }

    _interactionFetchPriority[noteId] = priority;

    _interactionFetchTimer?.cancel();
    _interactionFetchTimer = Timer(_interactionFetchDebounce, () {
      if (_isClosed) return;
      unawaited(_processPendingInteractionFetches());
    });
  }

  Future<void> _processPendingInteractionFetches() async {
    if (_interactionFetchPriority.isEmpty) return;

    final sortedNotes = _interactionFetchPriority.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final notesToFetch = sortedNotes
        .take(_maxInteractionBatchSize)
        .map((e) => e.key)
        .toList();

    _interactionFetchPriority.clear();

    await _fetchInteractionsOptimized(notesToFetch);
  }

  void _addNoteToCache(NoteModel note) {
    if (_noteCache.containsKey(note.id)) return;
    
    _noteCache[note.id] = note;
    _eventIds.add(note.id);
    
    _scheduleInteractionFetch(note.id);
  }

  void _cleanupCacheIfNeeded() {
    final now = timeService.now;

    if (_profileCache.length > _profileCacheMaxSize) {
      final cutoffTime = now.subtract(_profileCacheTTL);
      _profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));
    }

    if (_lastInteractionFetch.length > _interactionFetchMaxSize) {
      final interactionCutoff = now.subtract(_interactionCutoff);
      _lastInteractionFetch.removeWhere((key, timestamp) => timestamp.isBefore(interactionCutoff));
    }

    if (_processedInteractionIds.length > 10000) {
      _processedInteractionIds.clear();
    }

    if (_eventProcessingLock.length > _eventProcessingLockMaxSize) {
      _eventProcessingLock.clear();
    }

    if (_noteCache.length > _noteCacheMaxSize) {
      final sortedNotes = _noteCache.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final notesToRemove = sortedNotes.skip(_noteCacheKeepSize).map((n) => n.id).toList();
      for (final id in notesToRemove) {
        _noteCache.remove(id);
        _eventIds.remove(id);
        _reactionsMap.remove(id);
        _repostsMap.remove(id);
        _zapsMap.remove(id);
        _lastInteractionFetch.remove(id);
        _interactionFetchPriority.remove(id);
      }
    }
  }

  List<UserModel> _getUsersList() {
    return _profileCache.entries.map((entry) {
      return UserModel.fromCachedProfile(entry.key, entry.value.data);
    }).toList();
  }

  List<NoteModel> _getNotesList() {
    final notesList = _noteCache.values.toList();

    notesList.sort((a, b) {
      final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      return bTime.compareTo(aTime);
    });

    return notesList;
  }

  void _scheduleUIUpdate() {
    if (_uiUpdatePending) return;
    _uiUpdatePending = true;

    _uiUpdateThrottleTimer?.cancel();
    _uiUpdateThrottleTimer = Timer(_uiUpdateThrottle, () {
      if (_isClosed) return;

      _uiUpdatePending = false;
      _uiUpdateCounter++;
      
      if (_uiUpdateCounter % 3 == 0 || _eventQueue.isEmpty) {
        final notesList = _getFilteredNotesList();
        if (!_notesController.isClosed) {
          _notesController.add(notesList);
        }
      }
    });
  }

  List<NoteModel> _getFilteredNotesList() {
    final allNotes = _noteCache.values.toList();

    final replyFilteredNotes = allNotes.where((note) {
      if (!note.isReply) return true;
      if (note.isReply && note.isRepost) return true;
      return false;
    }).toList();

    replyFilteredNotes.sort((a, b) {
      final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      return bTime.compareTo(aTime);
    });

    return replyFilteredNotes;
  }

  Future<void> _ensureProfileExists(String pubkeyHex, String npub) async {
    try {
      if (_profileCache.containsKey(pubkeyHex)) {
        return;
      }

      _profileCache[pubkeyHex] = CachedProfile({
        'name': npub.substring(0, 16),
        'about': '',
        'picture': '',
        'banner': '',
        'website': '',
        'nip05': '',
        'lud16': '',
      }, timeService.now);

      unawaited(_fetchUserProfile(npub));
    } catch (e) {
    }
  }

  Future<void> _fetchUserProfile(String npub) async {
    try {
      final pubkeyHex = _authService.npubToHex(npub) ?? npub;

      final cachedProfile = _profileCache[pubkeyHex];
      final now = timeService.now;

      if (cachedProfile != null && now.difference(cachedProfile.fetchedAt) < _profileCacheTTL) {
        return;
      }

      final filter = NostrService.createProfileFilter(
        authors: [pubkeyHex],
        limit: 1,
      );

      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));
    } catch (e) {
    }
  }

  Future<Result<List<NoteModel>>> fetchFeedNotes({
    required List<String> authorNpubs,
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      final currentUser = await _authService.getCurrentUserNpub();
      if (currentUser.isSuccess && currentUser.data != null) {
        _currentUserNpub = currentUser.data!;
      }

      final authorHexKeys = authorNpubs.map((npub) => _authService.npubToHex(npub)).where((hex) => hex != null).cast<String>().toList();

      List<String> targetAuthors = [];

      if (authorHexKeys.isEmpty) {
        return Result.success([]);
      } else if (authorHexKeys.length == 1 && authorHexKeys.first == _authService.npubToHex(_currentUserNpub)) {

        final currentUserHex = _authService.npubToHex(_currentUserNpub);
        if (currentUserHex == null) {
          return const Result.error('Invalid current user npub format');
        }


        final followingResult = await getFollowingList(_currentUserNpub);

        if (followingResult.isSuccess && followingResult.data != null && followingResult.data!.isNotEmpty) {
          targetAuthors = List<String>.from(followingResult.data!);
          targetAuthors.add(currentUserHex);

        } else {
          return Result.success([]);
        }
      } else {
        targetAuthors = authorHexKeys;
      }

      if (targetAuthors.isEmpty) {
        return Result.success([]);
      }

      final filter = NostrService.createNotesFilter(
        authors: targetAuthors,
        kinds: [1, 6],
        limit: limit,
        since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
        until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
      );

      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));

      return Result.success([]);
    } catch (e) {
      return Result.error('Failed to fetch feed notes: $e');
    }
  }

  Future<Result<List<NoteModel>>> fetchProfileNotes({
    required String userNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      final pubkeyHex = _authService.npubToHex(userNpub);
      if (pubkeyHex == null) {
        return const Result.error('Invalid npub format');
      }

      final filter = NostrService.createNotesFilter(
        authors: [pubkeyHex],
        kinds: [1, 6],
        limit: limit,
        since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
        until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
      );

      final serializedRequest = NostrService.createRequest(filter);
      final subscriptionId = _extractSubscriptionId(serializedRequest);
      final fetchedNotes = <String, NoteModel>{};

      await _queryAllRelays(
        request: serializedRequest,
        subscriptionId: subscriptionId,
        timeout: const Duration(seconds: _longQueryTimeoutSeconds),
        onEvent: (data, url) {
          try {
            final eventData = data;
            final eventAuthor = eventData['pubkey'] as String? ?? '';
            final eventKind = eventData['kind'] as int? ?? 0;
            final eventId = eventData['id'] as String? ?? '';

            if (eventAuthor == pubkeyHex && (eventKind == 1 || eventKind == 6) && eventId.isNotEmpty) {
              if (!fetchedNotes.containsKey(eventId)) {
                final note = _processProfileEventDirectlySync(eventData, userNpub);
                if (note != null) {
                  fetchedNotes[eventId] = note;
                }
              }
            }
          } catch (_) {}
        },
      );

      for (final note in fetchedNotes.values) {
        _addNoteToCache(note);
      }

      final allProfileNotes = _noteCache.values.where((note) {
        final noteAuthorHex = _authService.npubToHex(note.author);
        return noteAuthorHex == pubkeyHex;
      }).toList();

      final filteredProfileNotes = await filterNotesByMuteList(allProfileNotes);

      _notesController.add(_getFilteredNotesList());

      return Result.success(filteredProfileNotes);
    } catch (e) {
      return Result.error('Failed to fetch profile notes: $e');
    }
  }

  NoteModel? _processProfileEventDirectlySync(Map<String, dynamic> eventData, String userNpub) {
    try {
      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final kind = eventData['kind'] as int;

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      if (kind == 1) {
        return _processKind1ForProfileSync(eventData, authorNpub, timestamp);
      } else if (kind == 6) {
        return _processKind6ForProfileSync(eventData, authorNpub, timestamp);
      }

      return null;
    } catch (e) {
      return null;
    }
  }


  NoteModel? _processKind1ForProfileSync(Map<String, dynamic> eventData, String authorNpub, DateTime timestamp) {
    try {
      final id = eventData['id'] as String;
      final content = eventData['content'] as String;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      final parsedTags = _parseTags(tags, includeTTags: false);
      final isReply = parsedTags.rootId != null;

      final note = NoteModel(
        id: id,
        content: content,
        author: authorNpub,
        timestamp: timestamp,
        isReply: isReply,
        isRepost: false,
        rootId: parsedTags.rootId,
        parentId: parsedTags.parentId,
        repostedBy: null,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(eventData),
        eTags: parsedTags.eTags,
        pTags: parsedTags.pTags,
      );

      return note;
    } catch (e) {
      return null;
    }
  }


  NoteModel? _processKind6ForProfileSync(Map<String, dynamic> eventData, String reposterNpub, DateTime timestamp) {
    try {
      final id = eventData['id'] as String;
      final content = eventData['content'] as String? ?? '';
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      String? originalEventId;
      String? originalAuthorHex;

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          if (tag[0] == 'e' && tag.length >= 2) {
            originalEventId = tag[1] as String;
          } else if (tag[0] == 'p' && tag.length >= 2) {
            originalAuthorHex = tag[1] as String;
          }
        }
      }

      if (originalEventId == null) return null;

      String displayContent = 'Reposted note';
      String displayAuthor = originalAuthorHex != null ? (_authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex) : 'Unknown';
      String? detectedRootId;
      String? detectedParentId;

      if (content.isNotEmpty) {
        try {
          final originalContent = jsonDecode(content) as Map<String, dynamic>;
          displayContent = originalContent['content'] as String? ?? displayContent;

          if (originalAuthorHex != null) {
            displayAuthor = _authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex;
          }

          final originalTags = originalContent['tags'] as List<dynamic>? ?? [];
          for (final tag in originalTags) {
            if (tag is List && tag.length >= 4 && tag[0] == 'e' && tag[3] == 'root') {
              detectedRootId = tag[1] as String;
              detectedParentId = tag[1] as String;
              break;
            } else if (tag is List && tag.length >= 4 && tag[0] == 'e' && tag[3] == 'reply') {
              detectedParentId = tag[1] as String;
            }
          }
        } catch (e) {
        }
      }

      final bool detectedIsReply = detectedRootId != null;

      final note = NoteModel(
        id: id,
        content: displayContent,
        author: displayAuthor,
        timestamp: timestamp,
        isReply: detectedIsReply,
        isRepost: true,
        rootId: detectedRootId ?? originalEventId,
        parentId: detectedParentId,
        repostedBy: reposterNpub,
        repostTimestamp: timestamp,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(eventData),
      );
    
      return note;
    } catch (e) {
      return null;
    }
  }


  Future<Result<List<NoteModel>>> fetchHashtagNotes({
    required String hashtag,
    int limit = 20,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      final targetHashtag = hashtag.toLowerCase();

      final filterMap = {
        'kinds': [1],
        '#t': [targetHashtag],
        'limit': limit,
        if (until != null) 'until': until.millisecondsSinceEpoch ~/ 1000,
        if (since != null) 'since': since.millisecondsSinceEpoch ~/ 1000,
      };

      final subscriptionId = NostrService.generateUUID();
      final serializedRequest = jsonEncode(['REQ', subscriptionId, filterMap]);
      final hashtagNotes = <NoteModel>[];

      await _queryAllRelays(
        request: serializedRequest,
        subscriptionId: subscriptionId,
        timeout: const Duration(seconds: _longQueryTimeoutSeconds),
        checkClosed: false,
        onEvent: (data, url) {
          try {
            final eventData = data;
            final eventId = eventData['id'] as String? ?? '';
            final eventKind = eventData['kind'] as int? ?? 0;

            if (eventKind == 1 && eventId.isNotEmpty) {
              if (_eventIds.contains(eventId)) {
                final cachedNote = _noteCache[eventId];
                if (cachedNote != null && !hashtagNotes.any((n) => n.id == eventId)) {
                  hashtagNotes.add(cachedNote);
                }
              } else {
                final note = _processHashtagEventDirectlySync(eventData);
                if (note != null) {
                  _addNoteToCache(note);
                  if (!hashtagNotes.any((n) => n.id == eventId)) {
                    hashtagNotes.add(note);
                  }
                }
              }
            }
          } catch (_) {}
        },
      );

      final validatedHashtagNotes = hashtagNotes.where((note) {
        if (note.tTags.isNotEmpty) {
          return note.tTags.contains(targetHashtag);
        }

        final content = note.content.toLowerCase();
        final hashtagRegex = RegExp(r'#(\w+)');
        final matches = hashtagRegex.allMatches(content);

        for (final match in matches) {
          final extractedHashtag = match.group(1)?.toLowerCase();
          if (extractedHashtag == targetHashtag) {
            return true;
          }
        }

        return false;
      }).toList();

      final filteredHashtagNotes = await filterNotesByMuteList(validatedHashtagNotes);

      final uniqueNotes = <String, NoteModel>{};
      for (final note in filteredHashtagNotes) {
        uniqueNotes[note.id] = note;
      }
      final deduplicated = uniqueNotes.values.toList();

      deduplicated.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final limitedNotes = deduplicated.take(limit).toList();

      _scheduleUIUpdate();

      return Result.success(limitedNotes);
    } catch (e) {
      return Result.error('Failed to fetch hashtag notes: $e');
    }
  }

  NoteModel? _processHashtagEventDirectlySync(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      final parsedTags = _parseTags(tags);
      final isReply = parsedTags.rootId != null;

      final note = NoteModel(
        id: id,
        content: content,
        author: authorNpub,
        timestamp: timestamp,
        isReply: isReply,
        isRepost: false,
        rootId: parsedTags.rootId,
        parentId: parsedTags.parentId,
        repostedBy: null,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(eventData),
        eTags: parsedTags.eTags,
        pTags: parsedTags.pTags,
        tTags: parsedTags.tTags,
      );

      return note;
    } catch (e) {
      return null;
    }
  }


  Future<Result<UserModel>> fetchUserProfile(String npub) async {
    try {
      final pubkeyHex = _authService.npubToHex(npub);
      if (pubkeyHex == null) {
        return const Result.error('Invalid npub format');
      }

      final cachedProfile = _profileCache[pubkeyHex];
      final now = timeService.now;

      if (cachedProfile != null && now.difference(cachedProfile.fetchedAt) < _profileCacheTTL) {
        final user = UserModel.fromCachedProfile(pubkeyHex, cachedProfile.data);
        return Result.success(user);
      }

      final filter = NostrService.createProfileFilter(
        authors: [pubkeyHex],
        limit: 1,
      );

      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);

      final completer = Completer<UserModel?>();
      late StreamSubscription subscription;

      subscription = _usersController.stream.listen((users) {
        if (!completer.isCompleted) {
          for (final user in users) {
            if (user.pubkeyHex == pubkeyHex) {
              completer.complete(user);
              subscription.cancel();
              return;
            }
          }
        }
      });

      await _relayManager.broadcast(serializedRequest);

      final user = await completer.future.timeout(
        const Duration(milliseconds: _profileFetchTimeoutMs),
        onTimeout: () => null,
      );

      await subscription.cancel();

      if (user != null) {
        return Result.success(user);
      }

      final updatedProfile = _profileCache[pubkeyHex];
      if (updatedProfile != null) {
        final cachedUser = UserModel.fromCachedProfile(pubkeyHex, updatedProfile.data);
        return Result.success(cachedUser);
      }

      final basicUser = UserModel.create(
        pubkeyHex: npub,
        name: npub.substring(0, 8),
        about: '',
        profileImage: '',
        banner: '',
        website: '',
        nip05: '',
        lud16: '',
        updatedAt: DateTime.now(),
        nip05Verified: false,
      );

      return Result.success(basicUser);
    } catch (e) {
      return Result.error('Failed to fetch user profile: $e');
    }
  }

  Future<Result<NoteModel>> postNote({
    required String content,
    List<List<String>>? tags,
  }) async {
    try {

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Private key not found: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Private key not found.');
      }


      dynamic event;
      try {
        event = NostrService.createNoteEvent(
          content: content,
          privateKey: privateKey,
          tags: tags,
        );
      } catch (e) {
        return Result.error('Failed to create note event: $e');
      }

      await _ensureRelayConnection();

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      final userResult = await _authService.getCurrentUserNpub();
      final authorNpub = userResult.data ?? '';

      final note = NoteModel(
        id: event.id,
        content: content,
        author: authorNpub,
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        isReply: tags?.any((tag) => tag.isNotEmpty && tag[0] == 'e') ?? false,
        isRepost: false,
        rootId: null,
        parentId: null,
        repostedBy: null,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(NostrService.eventToJson(event)),
      );

      _addNoteToCache(note);

      _scheduleUIUpdate();

      return Result.success(note);
    } catch (e) {
      return Result.error('Failed to post note: $e');
    }
  }

  Future<Result<void>> reactToNote({
    required String noteId,
    required String reaction,
  }) async {
    try {
      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Not authenticated: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null) {
        return const Result.error('No private key available');
      }

      final event = NostrService.createReactionEvent(
        targetEventId: noteId,
        content: reaction,
        privateKey: privateKey,
      );

      _pendingOptimisticReactionIds.add(event.id);

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      final userResult = await _authService.getCurrentUserNpub();
      final authorNpub = userResult.data ?? '';

      final optimisticReaction = ReactionModel(
        id: event.id,
        targetEventId: noteId,
        content: reaction,
        author: authorNpub,
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        fetchedAt: DateTime.now(),
      );

      _reactionsMap.putIfAbsent(noteId, () => []);
      _reactionsMap[noteId]!.add(optimisticReaction);

      final note = _noteCache[noteId];
      if (note != null) {
        note.reactionCount = _reactionsMap[noteId]!.length;
        _scheduleUIUpdate();
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to react to note: $e');
    }
  }

  Future<Result<void>> deleteRepost({
    required String noteId,
  }) async {
    try {
      final userResult = await _authService.getCurrentUserNpub();
      if (userResult.isError || userResult.data == null) {
        return const Result.error('User not authenticated');
      }

      final userNpub = userResult.data!;
      final reposts = _repostsMap[noteId] ?? [];
      final userRepost = reposts.firstWhere(
        (repost) => repost.author == userNpub,
        orElse: () => throw Exception('User has not reposted this note'),
      );

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Private key not found: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Private key not found.');
      }

      final repostNote = _noteCache[userRepost.id];
      
      _repostsMap[noteId]?.removeWhere((repost) => repost.id == userRepost.id);
      if (_repostsMap[noteId]?.isEmpty ?? false) {
        _repostsMap.remove(noteId);
      }

      if (repostNote != null && repostNote.isRepost) {
        _noteCache.remove(userRepost.id);
        _eventIds.remove(userRepost.id);

        if (!_isClosed && !_noteDeletedController.isClosed) {
          _noteDeletedController.add(userRepost.id);
        }
      }

      final note = _noteCache[noteId];
      if (note != null) {
        if (repostNote != null && repostNote.isRepost) {
          note.removeBoost(repostNote);
        }
        note.repostCount = _repostsMap[noteId]?.length ?? 0;
        _scheduleUIUpdate();
      }

      final event = NostrService.createDeletionEvent(
        eventIds: [userRepost.id],
        privateKey: privateKey,
      );

      await _ensureRelayConnection('repost_delete');

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to delete repost: $e');
    }
  }

  Future<Result<void>> repostNote({
    required String noteId,
    required String noteAuthor,
    String? content,
  }) async {
    try {

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Authentication error: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Authentication credentials not available.');
      }

      final originalNote = _noteCache[noteId];
      final repostContent = content ??
          (originalNote?.rawWs ??
              jsonEncode({
                'id': noteId,
                'pubkey': _authService.npubToHex(noteAuthor) ?? noteAuthor,
                'content': originalNote?.content ?? '',
                'created_at': originalNote?.timestamp.millisecondsSinceEpoch ?? 0 ~/ 1000,
                'kind': originalNote?.isRepost ?? false ? 6 : 1,
                'tags': [],
              }));


      final event = NostrService.createRepostEvent(
        noteId: noteId,
        noteAuthor: _authService.npubToHex(noteAuthor) ?? noteAuthor,
        content: repostContent,
        privateKey: privateKey,
      );

      await _ensureRelayConnection('repost');

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      final userResult = await _authService.getCurrentUserNpub();
      final reposterNpub = userResult.data ?? '';
      final timestamp = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);

      String displayContent = 'Reposted note';
      String displayAuthor = noteAuthor;
      bool detectedIsReply = false;
      String? detectedRootId;
      String? detectedParentId;

      if (originalNote != null) {
        displayContent = originalNote.content;
        displayAuthor = originalNote.author;
        detectedIsReply = originalNote.isReply;
        detectedRootId = originalNote.rootId;
        detectedParentId = originalNote.parentId;
      } else if (repostContent.isNotEmpty) {
        try {
          final originalContent = jsonDecode(repostContent) as Map<String, dynamic>;
          displayContent = originalContent['content'] as String? ?? 'Reposted note';
          final originalAuthorHex = _authService.npubToHex(noteAuthor) ?? noteAuthor;
          displayAuthor = _authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex;

          final originalTags = originalContent['tags'] as List<dynamic>? ?? [];
          for (final tag in originalTags) {
            if (tag is List && tag.length >= 2 && tag[0] == 'e') {
              final eventId = tag[1] as String;
              if (tag.length >= 4) {
                final marker = tag[3] as String;
                if (marker == 'root') {
                  detectedRootId = eventId;
                  detectedParentId = eventId;
                  detectedIsReply = true;
                } else if (marker == 'reply') {
                  detectedParentId = eventId;
                  detectedIsReply = true;
                }
              } else if (detectedParentId == null) {
                detectedParentId = eventId;
                detectedRootId = eventId;
                detectedIsReply = true;
              }
            }
          }
        } catch (e) {
          displayContent = 'Reposted note';
          displayAuthor = _authService.hexToNpub(_authService.npubToHex(noteAuthor) ?? noteAuthor) ?? noteAuthor;
        }
      }

      final repostNote = NoteModel(
        id: event.id,
        content: displayContent,
        author: displayAuthor,
        timestamp: timestamp,
        isReply: detectedIsReply,
        isRepost: true,
        rootId: detectedRootId ?? noteId,
        parentId: detectedParentId,
        repostedBy: reposterNpub,
        repostTimestamp: timestamp,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(NostrService.eventToJson(event)),
      );

      _addNoteToCache(repostNote);

      _trackRepostForCount(NostrService.eventToJson(event));

      _scheduleUIUpdate();

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to repost note: $e');
    }
  }

  Future<Result<NoteModel>> postReply({
    required String content,
    required String rootId,
    String? replyId,
    required String parentAuthor,
    required List<String> relayUrls,
    List<List<String>>? additionalTags,
  }) async {
    try {
      final parentEventId = replyId ?? rootId;

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Authentication error: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Authentication credentials not available.');
      }

      final parentNote = _noteCache.values.where((note) => note.id == parentEventId).firstOrNull;

      if (parentNote == null) {
        return const Result.error('Parent note not found.');
      }


      String actualRootId;
      String actualReplyId = parentEventId;
      String replyMarker;

      if (parentNote.isReply && parentNote.rootId != null && parentNote.rootId!.isNotEmpty) {
        actualRootId = parentNote.rootId!;
        replyMarker = 'reply';
      } else {
        actualRootId = parentEventId;
        replyMarker = 'root';
      }


      List<List<String>> tags = [];

      final List<Map<String, String>> eTags = [];
      final List<Map<String, String>> pTags = [];

      final authorHex = _authService.npubToHex(parentNote.author) ?? parentNote.author;

      if (actualRootId != actualReplyId) {
        tags.add(['e', actualRootId, '', 'root', authorHex]);
        tags.add(['e', actualReplyId, '', 'reply', authorHex]);

        eTags.add({
          'eventId': actualRootId,
          'relayUrl': '',
          'marker': 'root',
          'pubkey': authorHex,
        });
        eTags.add({
          'eventId': actualReplyId,
          'relayUrl': '',
          'marker': 'reply',
          'pubkey': authorHex,
        });
      } else {
        tags.add(['e', actualRootId, '', 'root', authorHex]);

        eTags.add({
          'eventId': actualRootId,
          'relayUrl': '',
          'marker': 'root',
          'pubkey': authorHex,
        });
      }

      Set<String> mentionedPubkeys = {authorHex};

      if (parentNote.pTags.isNotEmpty == true) {
        for (final pTag in parentNote.pTags) {
          if (pTag['pubkey'] != null && pTag['pubkey']!.isNotEmpty) {
            mentionedPubkeys.add(pTag['pubkey']!);
          }
        }
      }

      for (final pubkey in mentionedPubkeys) {
        tags.add(['p', pubkey]);
        pTags.add({
          'pubkey': pubkey,
          'relayUrl': '',
          'petname': '',
        });
      }

      if (additionalTags != null && additionalTags.isNotEmpty) {
        tags.addAll(additionalTags);
      }


      final event = NostrService.createReplyEvent(
        content: content,
        privateKey: privateKey,
        tags: tags,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _relayManager.activeSockets;

      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          try {
            ws.add(serializedEvent);
          } catch (e) {
          }
        } else {
        }
      }

      final userResult = await _authService.getCurrentUserNpub();
      final authorNpub = userResult.data ?? '';

      final reply = NoteModel(
        id: event.id,
        content: content,
        author: authorNpub,
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        isReply: true,
        isRepost: false,
        rootId: actualRootId,
        parentId: actualReplyId,
        repostedBy: null,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(NostrService.eventToJson(event)),
        eTags: eTags,
        pTags: pTags,
        replyMarker: replyMarker,
      );

      _addNoteToCache(reply);
      _scheduleUIUpdate();

      return Result.success(reply);
    } catch (e) {
      return Result.error('Failed to post reply: $e');
    }
  }

  Future<Result<UserModel>> updateUserProfile(UserModel user) async {
    try {

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Authentication error: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Authentication credentials not available.');
      }

      final Map<String, dynamic> profileContent = {
        'name': user.name,
        'about': user.about,
        'picture': user.profileImage,
      };

      if (user.nip05.isNotEmpty) profileContent['nip05'] = user.nip05;
      if (user.banner.isNotEmpty) profileContent['banner'] = user.banner;
      if (user.lud16.isNotEmpty) profileContent['lud16'] = user.lud16;
      if (user.website.isNotEmpty) profileContent['website'] = user.website;


      final event = NostrService.createProfileEvent(
        profileContent: profileContent,
        privateKey: privateKey,
      );


      await _ensureRelayConnection('profile_update');

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      final eventJson = NostrService.eventToJson(event);
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(eventJson['created_at'] * 1000);
      final pubkeyHex = eventJson['pubkey'] as String;

      final updatedUser = UserModel.create(
        pubkeyHex: user.pubkeyHex,
        name: user.name,
        about: user.about,
        profileImage: user.profileImage,
        nip05: user.nip05,
        banner: user.banner,
        lud16: user.lud16,
        website: user.website,
        updatedAt: updatedAt,
        nip05Verified: false,
      );

      _profileCache.remove(pubkeyHex);
      _profileCache[pubkeyHex] = CachedProfile(
        profileContent.map((key, value) => MapEntry(key, value.toString())),
        updatedAt,
      );
      _cleanupCacheIfNeeded();

      _usersController.add(_getUsersList());

      return Result.success(updatedUser);
    } catch (e) {
      return Result.error('Failed to update profile: $e');
    }
  }

  Future<Result<List<NotificationModel>>> fetchNotifications({
    DateTime? since,
  }) async {
    try {
      final userResult = await _authService.getCurrentUserPublicKeyHex();
      if (userResult.isError) {
        return Result.error('Not authenticated: ${userResult.error}');
      }

      final pubkeyHex = userResult.data;
      if (pubkeyHex == null) {
        return const Result.error('No user public key available');
      }

      _currentUserNpub = (await _authService.getCurrentUserNpub()).data ?? '';

      final filter = <String, dynamic>{
        'kinds': [1, 6, 7, 9735],
        '#p': [pubkeyHex],
      };

      if (since != null) {
        filter['since'] = since.millisecondsSinceEpoch ~/ 1000;
      }

      final subscriptionId = NostrService.generateUUID();
      final request = ['REQ', subscriptionId, filter];
      final serializedRequest = jsonEncode(request);

      if (_allRelays.isEmpty) {
        return const Result.error('No relays available');
      }

      final fetchedNotifications = <String, NotificationModel>{};

      await _queryAllRelays(
        request: serializedRequest,
        subscriptionId: subscriptionId,
        timeout: const Duration(seconds: _longQueryTimeoutSeconds),
        checkClosed: false,
        onEvent: (eventData, url) {
          try {
            final eventId = eventData['id'] as String? ?? '';
            final eventKind = eventData['kind'] as int? ?? 0;
            final eventPubkey = eventData['pubkey'] as String? ?? '';
            final eventCreatedAt = eventData['created_at'] as int? ?? 0;
            final eventTags = eventData['tags'] as List<dynamic>? ?? [];
            final eventContent = eventData['content'] as String? ?? '';

            if (eventId.isEmpty || eventPubkey.isEmpty) return;

            final notification = _processNotificationEvent(
              eventId: eventId,
              eventKind: eventKind,
              eventPubkey: eventPubkey,
              eventCreatedAt: eventCreatedAt,
              eventTags: eventTags,
              eventContent: eventContent,
              targetUserHex: pubkeyHex,
            );

            if (notification != null && !fetchedNotifications.containsKey(notification.id)) {
              fetchedNotifications[notification.id] = notification;
            }
          } catch (_) {}
        },
      );

      final notificationsList = fetchedNotifications.values.toList();
      notificationsList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final notifications = _notificationCache.putIfAbsent(_currentUserNpub, () => []);
      notifications.clear();
      notifications.addAll(notificationsList);
      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (!_notificationsController.isClosed) {
        _notificationsController.add(List.unmodifiable(notifications));
      }

      return Result.success(notificationsList);
    } catch (e) {
      return Result.error('Failed to fetch notifications: $e');
    }
  }

  NotificationModel? _processNotificationEvent({
    required String eventId,
    required int eventKind,
    required String eventPubkey,
    required int eventCreatedAt,
    required List<dynamic> eventTags,
    required String eventContent,
    required String targetUserHex,
  }) {
    try {
      if (eventPubkey == targetUserHex) {
        return null;
      }

      String? targetEventId;
      String notificationType = 'mention';
      int zapAmount = 0;
      String actualAuthor = eventPubkey;

      if (eventKind == 1) {
        final mentionedUser = _getTagValue(eventTags, 'p');
        if (mentionedUser == targetUserHex) {
          notificationType = 'mention';
          targetEventId = _getTagValue(eventTags, 'e') ?? eventId;
        } else {
          return null;
        }
      } else if (eventKind == 6) {
        notificationType = 'repost';
        targetEventId = _getTagValue(eventTags, 'e');
      } else if (eventKind == 7) {
        notificationType = 'reaction';
        targetEventId = _getTagValue(eventTags, 'e');
      } else if (eventKind == 9735) {
        notificationType = 'zap';
        targetEventId = _getTagValue(eventTags, 'e');

        final bolt11 = _getTagValue(eventTags, 'bolt11') ?? '';
        final descriptionJson = _getTagValue(eventTags, 'description') ?? '';

        zapAmount = parseAmountFromBolt11(bolt11);

        try {
          final decoded = jsonDecode(descriptionJson);
          if (decoded is Map<String, dynamic> && decoded.containsKey('pubkey')) {
            actualAuthor = decoded['pubkey'] as String;
          }
        } catch (e) {
        }
      } else {
        return null;
      }

      final timestamp = DateTime.fromMillisecondsSinceEpoch(eventCreatedAt * 1000);
      targetEventId ??= eventId;

      final authorNpub = _authService.hexToNpub(actualAuthor) ?? actualAuthor;

      return NotificationModel(
        id: eventId,
        type: notificationType,
        author: authorNpub,
        targetEventId: targetEventId,
        timestamp: timestamp,
        content: eventContent,
        fetchedAt: DateTime.now(),
        isRead: false,
        amount: zapAmount,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> stopNotificationSubscription() async {
    if (_notificationSubscriptionActive && _notificationSubscriptionId != null) {
      await _relayManager.broadcast(jsonEncode(['CLOSE', _notificationSubscriptionId]));
      _notificationSubscriptionActive = false;
      _notificationSubscriptionId = null;
    }
  }

  Future<Result<List<String>>> getFollowingList(String npub) async {
    try {
      final pubkeyHex = _authService.npubToHex(npub) ?? npub;

      final filter = NostrService.createFollowingFilter(
        authors: [pubkeyHex],
        limit: 1,
      );

      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);

      final following = <String>{};
      final processedEventIds = <String>{};
      final subscriptionId = _extractSubscriptionId(serializedRequest);

      await _queryAllRelays(
        request: serializedRequest,
        subscriptionId: subscriptionId,
        onEvent: (eventData, url) {
          try {
            final eventId = eventData['id'] as String;
            final eventAuthor = eventData['pubkey'] as String;
            final eventKind = eventData['kind'] as int;

            if (eventAuthor == pubkeyHex && eventKind == 3 && !processedEventIds.contains(eventId)) {
              processedEventIds.add(eventId);
              following.addAll(_extractPTags(eventData['tags'] as List<dynamic>));
            }
          } catch (_) {}
        },
      );

      final uniqueFollowing = following.toList();

      return Result.success(uniqueFollowing);
    } catch (e) {
      return Result.error('Failed to get following list: $e');
    }
  }

  Future<bool> fetchSpecificNote(String noteId) async {
    try {
      if (_noteCache.containsKey(noteId)) {
        return true;
      }

      bool noteFound = false;
      final filter = NostrService.createEventByIdFilter(eventIds: [noteId]);
      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);
      final subscriptionId = _extractSubscriptionId(serializedRequest);

      await _queryAllRelays(
        request: serializedRequest,
        subscriptionId: subscriptionId,
        onEvent: (eventData, url) {
          try {
            final eventId = eventData['id'] as String;

            if (eventId == noteId) {
              final kind = eventData['kind'] as int;
              if (kind == 1 || kind == 6) {
                final pubkeyHex = eventData['pubkey'] as String;
                final userNpub = _authService.hexToNpub(pubkeyHex) ?? pubkeyHex;
                final note = _processProfileEventDirectlySync(eventData, userNpub);
                if (note != null) {
                  _addNoteToCache(note);
                  noteFound = true;
                }
              }
            }
          } catch (_) {}
        },
      );

      return noteFound || _noteCache.containsKey(noteId);
    } catch (e) {
      return false;
    }
  }

  Future<void> fetchSpecificNotes(List<String> noteIds) async {
    try {
      if (noteIds.isEmpty) return;

      final notesToFetch = noteIds.where((id) => !_noteCache.containsKey(id)).toList();
      if (notesToFetch.isEmpty) return;

      final filter = NostrService.createEventByIdFilter(eventIds: notesToFetch);
      final request = NostrService.createRequest(filter);

      await _relayManager.broadcast(NostrService.serializeRequest(request));
    } catch (e) {
    }
  }

  List<NoteModel> get cachedNotes => _getNotesList();

  List<UserModel> get cachedUsers => _getUsersList();

  final Map<String, Map<String, dynamic>> _pendingCountRequests = {};

  void _handleCountResponse(List<dynamic> response) {
    try {
      if (response.length < 3) return;

      final subscriptionId = response[1] as String;
      final countData = response[2] as Map<String, dynamic>;
      final count = countData['count'] as int;

      if (_pendingCountRequests.containsKey(subscriptionId)) {
        final requestData = _pendingCountRequests[subscriptionId]!;

        if (requestData['type'] == 'follower') {
          final completer = requestData['completer'] as Completer<int>;
          if (!completer.isCompleted) {
            completer.complete(count);
          }
          _pendingCountRequests.remove(subscriptionId);
          return;
        }
      }
    } catch (e) {
    }
  }

  void _handleClosedMessage(List<dynamic> message) {
    try {
      final subscriptionId = message[1] as String;
      final reason = message.length > 2 ? message[2] as String : 'unknown';

      if (_pendingCountRequests.containsKey(subscriptionId)) {
        final requestData = _pendingCountRequests[subscriptionId]!;

        if (requestData['type'] == 'follower') {
          final completer = requestData['completer'] as Completer<int>;
          if (!completer.isCompleted) {
            completer.completeError('CLOSED: $reason');
          }
          _pendingCountRequests.remove(subscriptionId);
          return;
        }

        _pendingCountRequests.remove(subscriptionId);
      }
    } catch (e) {
    }
  }

  Future<int> fetchFollowerCount(String pubkeyHex, {int maxRetries = 3, int attempt = 1}) async {
    try {
      final primalService = PrimalCacheService.instance;
      final primalCount = await primalService.fetchFollowerCount(pubkeyHex);
      
      if (primalCount > 0) {
        return primalCount;
      }
    } catch (e) {
    }

    try {
      final filterMap = <String, dynamic>{
        'kinds': [3],
        '#p': [pubkeyHex],
      };
      final subscriptionId = NostrService.generateUUID();

      final completer = Completer<int>();

      _pendingCountRequests[subscriptionId] = {
        'type': 'follower',
        'pubkey': pubkeyHex,
        'completer': completer,
        'attempt': attempt,
      };

      final countRequest = jsonEncode(['COUNT', subscriptionId, filterMap]);

      final ws = _relayManager.webSockets[countRelayUrl];
      if (ws != null && ws.readyState == WebSocket.open) {
        ws.add(countRequest);

        try {
          return await completer.future.timeout(
            const Duration(seconds: _followerCountTimeoutSeconds),
            onTimeout: () {
              _pendingCountRequests.remove(subscriptionId);
              throw TimeoutException('Follower COUNT timeout');
            },
          );
        } on TimeoutException {
          if (attempt < maxRetries) {
            await Future.delayed(Duration(milliseconds: 300 * attempt));
            return fetchFollowerCount(pubkeyHex, maxRetries: maxRetries, attempt: attempt + 1);
          }
          return 0;
        } catch (e) {
          if (e.toString().contains('CLOSED')) {
            return 0;
          } else if (attempt < maxRetries) {
            await Future.delayed(Duration(milliseconds: 300 * attempt));
            return fetchFollowerCount(pubkeyHex, maxRetries: maxRetries, attempt: attempt + 1);
          }
          return 0;
        }
      } else {
        _pendingCountRequests.remove(subscriptionId);
        return 0;
      }
    } catch (e) {
      return 0;
    }
  }

  Future<void> fetchInteractionsForNotesWithEOSE(String noteId) async {
    _scheduleInteractionFetch(noteId, priority: 100);
  }

  Future<void> fetchInteractionsForNotesBatchWithEOSE(List<String>? noteIds) async {
    if (noteIds == null || noteIds.isEmpty) return;
    for (final noteId in noteIds) {
      _scheduleInteractionFetch(noteId, priority: 50);
    }
  }

  void fetchInteractionsForVisibleNotes(List<String> visibleNoteIds) {
    for (final noteId in visibleNoteIds) {
      _scheduleInteractionFetch(noteId, priority: 200);
    }
  }

  Future<void> _fetchInteractionsOptimized(List<String> noteIds) async {
    if (_isClosed || noteIds.isEmpty) return;

    final now = timeService.now;
    final minDelay = Duration(milliseconds: 1000 ~/ _maxRelayQueriesPerSecond);
    final timeSinceLastQuery = now.difference(_lastRelayQueryTime);

    if (timeSinceLastQuery < minDelay) {
      await Future.delayed(minDelay - timeSinceLastQuery);
    }
    _lastRelayQueryTime = timeService.now;

    try {
      final allRelays = _relayManager.relayUrls.toList();
      if (allRelays.isEmpty) return;

      final replyKinds = [1];
      final interactionKinds = [7, 6, 9735];
      final deletionKinds = [5];

      final oldestFetch = noteIds
          .map((id) => _lastInteractionFetch[id])
          .whereType<DateTime>()
          .fold<DateTime?>(null, (oldest, date) =>
              oldest == null || date.isBefore(oldest) ? date : oldest);

      final since = oldestFetch != null ? oldestFetch.millisecondsSinceEpoch ~/ 1000 : null;

      final filters = [
        NostrService.createInteractionFilter(
          kinds: replyKinds,
          eventIds: noteIds,
          limit: 200,
          since: since,
        ),
        NostrService.createInteractionFilter(
          kinds: interactionKinds,
          eventIds: noteIds,
          limit: 500,
          since: since,
        ),
        NostrService.createInteractionFilter(
          kinds: deletionKinds,
          eventIds: noteIds,
          limit: 50,
          since: since,
        ),
      ];

      final request = NostrService.createMultiFilterRequest(filters);
      final subscriptionId = _extractSubscriptionId(request);

      await _queryAllRelays(
        request: request,
        subscriptionId: subscriptionId,
        checkClosed: true,
        timeout: const Duration(seconds: 5),
        onEvent: (eventData, url) {
          try {
            final eventId = eventData['id'] as String;
            final eventKind = eventData['kind'] as int;

            if (_processedInteractionIds.contains(eventId)) return;

            if (replyKinds.contains(eventKind) ||
                interactionKinds.contains(eventKind) ||
                deletionKinds.contains(eventKind)) {
              _processedInteractionIds.add(eventId);
              unawaited(_processNostrEvent(eventData));
            }
          } catch (_) {}
        },
      );

      for (final noteId in noteIds) {
        _lastInteractionFetch[noteId] = now;
        final note = _noteCache[noteId];
        if (note != null) {
          note.reactionCount = _reactionsMap[noteId]?.length ?? 0;
          note.repostCount = _repostsMap[noteId]?.length ?? 0;
          note.zapAmount = _zapsMap[noteId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
          _updateNoteReplyCount(noteId);
        }
      }

      _scheduleUIUpdate();
    } catch (e) {
    }
  }


  void _updateParentNoteReplyCount(String parentNoteId) {
    try {
      final parentNote = _noteCache[parentNoteId];
      if (parentNote != null) {
        final replyCount =
            _noteCache.values.where((note) => note.isReply && (note.parentId == parentNoteId || note.rootId == parentNoteId)).length;
        parentNote.replyCount = replyCount;
      }
    } catch (e) {
    }
  }

  void _updateNoteReplyCount(String noteId) {
    try {
      final note = _noteCache[noteId];
      if (note != null) {
        final replyCount = _noteCache.values.where((reply) => reply.isReply && (reply.parentId == noteId || reply.rootId == noteId)).length;
        if (note.replyCount != replyCount) {
          note.replyCount = replyCount;
          _scheduleUIUpdate();
        }
      }
    } catch (e) {
    }
  }

  Future<Result<NoteModel>> postQuote({
    required String content,
    required String quotedEventId,
    String? quotedEventPubkey,
    String? relayUrl,
    List<List<String>>? additionalTags,
  }) async {
    try {

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Authentication error: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Authentication credentials not available.');
      }


      final event = NostrService.createQuoteEvent(
        content: content,
        quotedEventId: quotedEventId,
        quotedEventPubkey: quotedEventPubkey,
        relayUrl: relayUrl,
        privateKey: privateKey,
        additionalTags: additionalTags,
      );

      await _ensureRelayConnection('quote_post');

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      final userResult = await _authService.getCurrentUserNpub();
      final authorNpub = userResult.data ?? '';

      final note = NoteModel(
        id: event.id,
        content: content,
        author: authorNpub,
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        isReply: false,
        isRepost: false,
        rootId: null,
        parentId: null,
        repostedBy: null,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(NostrService.eventToJson(event)),
      );

      _addNoteToCache(note);
      _scheduleUIUpdate();

      return Result.success(note);
    } catch (e) {
      return Result.error('Failed to post quote: $e');
    }
  }

  Future<Result<void>> deleteNote({
    required String noteId,
    String? reason,
  }) async {
    try {
      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Private key not found: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Private key not found.');
      }

      final event = NostrService.createDeletionEvent(
        eventIds: [noteId],
        privateKey: privateKey,
        reason: reason,
      );

      await _ensureRelayConnection('note_delete');

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      _noteCache.remove(noteId);
      _eventIds.remove(noteId);
      _reactionsMap.remove(noteId);
      _repostsMap.remove(noteId);
      _zapsMap.remove(noteId);

      if (!_isClosed && !_noteDeletedController.isClosed) {
        _noteDeletedController.add(noteId);
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to delete note: $e');
    }
  }

  Future<Result<String>> sendMedia(String filePath, String blossomUrl) async {
    try {

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Authentication error: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Authentication credentials not available.');
      }

      final url = await NostrService.sendMedia(
        filePath: filePath,
        blossomUrl: blossomUrl,
        privateKey: privateKey,
      );

      return Result.success(url);
    } catch (e) {
      return Result.error('Failed to upload media: $e');
    }
  }

  Future<Result<void>> publishFollowEvent({
    required List<String> followingHexList,
    required String privateKey,
  }) async {
    try {

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user not found');
      }

      final currentUserNpub = currentUserResult.data!;

      await _ensureRelayConnection('follow_event');

      final event = NostrService.createFollowEvent(
        followingPubkeys: followingHexList,
        privateKey: privateKey,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _relayManager.activeSockets;

      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          try {
            ws.add(serializedEvent);
          } catch (e) {
          }
        }
      }

      try {
        final currentUserHex = _authService.npubToHex(currentUserNpub) ?? currentUserNpub;
        await _followCacheService.put(currentUserHex, followingHexList);
      } catch (e) {
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to publish follow event: $e');
    }
  }

  Future<Result<List<String>>> getMuteList(String npub) async {
    try {
      final pubkeyHex = _authService.npubToHex(npub) ?? npub;

      final filter = NostrService.createMuteFilter(
        authors: [pubkeyHex],
        limit: 1,
      );

      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);

      final muted = <String>{};
      final processedEventIds = <String>{};
      final subscriptionId = _extractSubscriptionId(serializedRequest);

      await _queryAllRelays(
        request: serializedRequest,
        subscriptionId: subscriptionId,
        onEvent: (eventData, url) {
          try {
            final eventId = eventData['id'] as String;
            final eventAuthor = eventData['pubkey'] as String;
            final eventKind = eventData['kind'] as int;

            if (eventAuthor == pubkeyHex && eventKind == 10000 && !processedEventIds.contains(eventId)) {
              processedEventIds.add(eventId);
              muted.addAll(_extractPTags(eventData['tags'] as List<dynamic>));
            }
          } catch (_) {}
        },
      );

      final uniqueMuted = muted.toList();

      if (uniqueMuted.isNotEmpty) {
        await _muteCacheService.put(pubkeyHex, uniqueMuted);
      }

      return Result.success(uniqueMuted);
    } catch (e) {
      return Result.error('Failed to get mute list: $e');
    }
  }

  Future<Result<void>> publishMuteEvent({
    required List<String> mutedHexList,
    required String privateKey,
  }) async {
    try {

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user not found');
      }

      final currentUserNpub = currentUserResult.data!;

      await _ensureRelayConnection('mute_event');

      final event = NostrService.createMuteEvent(
        mutedPubkeys: mutedHexList,
        privateKey: privateKey,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _relayManager.activeSockets;

      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          try {
            ws.add(serializedEvent);
          } catch (e) {
          }
        }
      }

      try {
        final currentUserHex = _authService.npubToHex(currentUserNpub) ?? currentUserNpub;
        await _muteCacheService.put(currentUserHex, mutedHexList);
      } catch (e) {
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to publish mute event: $e');
    }
  }

  void _cleanMutedNotesFromCache(List<String> mutedHexList) {
    try {
      final mutedSet = mutedHexList.toSet();
      int removedCount = 0;

      final notesToRemove = <String>[];
      for (final note in _noteCache.values) {
        final noteAuthorHex = _authService.npubToHex(note.author);
        if (noteAuthorHex != null && mutedSet.contains(noteAuthorHex)) {
          notesToRemove.add(note.id);
          removedCount++;
        } else if (note.isRepost && note.repostedBy != null) {
          final reposterHex = _authService.npubToHex(note.repostedBy!);
          if (reposterHex != null && mutedSet.contains(reposterHex)) {
            notesToRemove.add(note.id);
            removedCount++;
          }
        }
      }

      for (final noteId in notesToRemove) {
        _noteCache.remove(noteId);
        _eventIds.remove(noteId);
      }

      if (removedCount > 0) {
        _scheduleUIUpdate();
      }
    } catch (e) {
    }
  }

  void clearCaches() {
    _noteCache.clear();
    _profileCache.clear();
    _notificationCache.clear();
    _reactionsMap.clear();
    _repostsMap.clear();
    _zapsMap.clear();
    _eventIds.clear();
    _lastInteractionFetch.clear();
    _pendingOptimisticReactionIds.clear();
    _eventProcessingLock.clear();
    NostrService.clearAllCaches();
  }

  List<ReactionModel> getReactionsForNote(String noteId) {
    return _reactionsMap[noteId] ?? [];
  }

  List<ReactionModel> getRepostsForNote(String noteId) {
    return _repostsMap[noteId] ?? [];
  }

  List<ZapModel> getZapsForNote(String noteId) {
    return _zapsMap[noteId] ?? [];
  }

  bool hasUserReacted(String noteId, String userNpub) {
    try {
      final reactions = _reactionsMap[noteId] ?? [];
      return reactions.any((reaction) => reaction.author == userNpub);
    } catch (e) {
      return false;
    }
  }

  bool hasUserReposted(String noteId, String userNpub) {
    try {
      final reposts = _repostsMap[noteId] ?? [];
      return reposts.any((repost) => repost.author == userNpub);
    } catch (e) {
      return false;
    }
  }

  bool hasUserZapped(String noteId, String userNpub) {
    try {
      final zaps = _zapsMap[noteId] ?? [];
      return zaps.any((zap) => zap.sender == userNpub);
    } catch (e) {
      return false;
    }
  }

  Map<String, List<ReactionModel>> get reactionsMap => Map.unmodifiable(_reactionsMap);
  Map<String, List<ReactionModel>> get repostsMap => Map.unmodifiable(_repostsMap);
  Map<String, List<ZapModel>> get zapsMap => Map.unmodifiable(_zapsMap);


  Future<List<NoteModel>> filterNotesByMuteList(List<NoteModel> notes) async {
    try {
      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return notes;
      }

      final currentUserNpub = currentUserResult.data!;
      final currentUserHex = _authService.npubToHex(currentUserNpub) ?? currentUserNpub;

      final mutedList = _muteCacheService.getSync(currentUserHex);
      if (mutedList == null || mutedList.isEmpty) {
        return notes;
      }

      final mutedSet = mutedList.toSet();

      final filteredNotes = notes.where((note) {
        if (note.isRepost && note.repostedBy != null) {
          final reposterHex = _authService.npubToHex(note.repostedBy!) ?? note.repostedBy!;
          if (mutedSet.contains(reposterHex)) {
            return false;
          }
        }

        final noteAuthorHex = _authService.npubToHex(note.author) ?? note.author;
        if (mutedSet.contains(noteAuthorHex)) {
          return false;
        }

        return true;
      }).toList();

      return filteredNotes;
    } catch (e) {
      return notes;
    }
  }

  void dispose() {
    _isClosed = true;
    _batchProcessingTimer?.cancel();
    _uiUpdateThrottleTimer?.cancel();
    _interactionFetchTimer?.cancel();
    _relayManager.unregisterService('nostr_data_service');
    _notesController.close();
    _usersController.close();
    _notificationsController.close();
    _noteDeletedController.close();
    clearCaches();
  }
}

class ParsedTags {
  final List<Map<String, String>> eTags;
  final List<Map<String, String>> pTags;
  final List<String> tTags;
  final String? rootId;
  final String? parentId;

  ParsedTags({
    required this.eTags,
    required this.pTags,
    required this.tTags,
    this.rootId,
    this.parentId,
  });
}

class CachedProfile {
  final Map<String, String> data;
  final DateTime fetchedAt;

  CachedProfile(this.data, this.fetchedAt);
}

int parseAmountFromBolt11(String bolt11) {
  final match = RegExp(r'^lnbc(\d+)([munp]?)', caseSensitive: false).firstMatch(bolt11);
  if (match == null) return 0;

  final number = int.tryParse(match.group(1) ?? '') ?? 0;
  final unit = match.group(2)?.toLowerCase();

  switch (unit) {
    case 'm':
      return number * 100000;
    case 'u':
      return number * 100;
    case 'n':
      return (number * 0.1).round();
    case 'p':
      return (number * 0.001).round();
    default:
      return number * 1000;
  }
}
