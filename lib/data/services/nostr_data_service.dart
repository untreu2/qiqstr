import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/entities.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'dart:typed_data';

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

class NostrDataService {
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

  bool _notificationSubscriptionActive = false;
  String? _notificationSubscriptionId;

  NostrDataService({
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

  bool _shouldIncludeNoteInFeed(String authorHexPubkey, bool isRepost) {
    return true;
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
        debugPrint('[NostrDataService] No user logged in, skipping feed fetch');
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error initializing lists: $e');
      try {
        await _fetchFeedNotesFromFollowList();
      } catch (feedError) {
        debugPrint('[NostrDataService] Error fetching feed notes: $feedError');
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
          debugPrint('[NostrDataService] Cannot convert npub to hex, skipping feed fetch');
          return;
        }

        final followList = await _followCacheService.get(currentUserHex);
        
        if (followList == null || followList.isEmpty) {
          debugPrint('[NostrDataService] No follow list available, skipping feed fetch');
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
      debugPrint('[NostrDataService] Error in _fetchFeedNotesFromFollowList: $e');
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
      debugPrint('[NostrDataService] Error updating lists from network: $e');
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
    final allRelays = _relayManager.relayUrls.toList();

    await Future.wait(allRelays.map((relayUrl) async {
      try {
        if (_isClosed) {
          return;
        }

        final completer = await _relayManager.sendQuery(
          relayUrl,
          request,
          subscriptionId,
          timeout: const Duration(seconds: 3),
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
                    } catch (e) {
                      debugPrint('[NostrDataService] Error parsing profile: $e');
                    }
                  }
                } else if (eventKind == 3) {
                  final tags = eventData['tags'] as List<dynamic>;
                  for (var tag in tags) {
                    if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
                      following.add(tag[1] as String);
                    }
                  }
                } else if (eventKind == 10000) {
                  final tags = eventData['tags'] as List<dynamic>;
                  for (var tag in tags) {
                    if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
                      muted.add(tag[1] as String);
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('[NostrDataService] Error processing combined data: $e');
            }
          },
        );

        await completer.future;
      } catch (e) {
        debugPrint('[NostrDataService] Error fetching combined data: $e');
      }
    }));

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


  void _handleRelayEvent(dynamic rawEvent, String relayUrl) {
    try {
      final eventData = jsonDecode(rawEvent);
      if (eventData is List && eventData.isNotEmpty) {
        final messageType = eventData[0];

        if (messageType == 'EVENT' && eventData.length >= 3) {
          final event = eventData[2] as Map<String, dynamic>;

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
        } else if (messageType == 'COUNT' && eventData.length >= 3) {
          _handleCountResponse(eventData);
        } else if (messageType == 'CLOSED' && eventData.length >= 2) {
          _handleClosedMessage(eventData);
        }
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error handling relay event: $e');
    }
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
      debugPrint('[NostrDataService] Error processing event: $e');
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
      debugPrint('[NostrDataService] Error processing profile event: $e');
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

    final user = UserModel(
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
        debugPrint('[NostrDataService] Error caching profile: $e');
      }

      if (!_usersController.isClosed) {
        _usersController.add(_getUsersList());
      }
  }

  Future<void> _processKind1Event(Map<String, dynamic> eventData) async {
    try {
      final tags = List<dynamic>.from(eventData['tags'] ?? []);
      String? rootId;

      for (var tag in tags) {
        if (tag is List && tag.length >= 4 && tag[0] == 'e' && tag[3] == 'root') {
          rootId = tag[1] as String;
          break;
        }
      }

      if (rootId != null) {
        await _handleReplyEvent(eventData, rootId);
      } else {
        await _processNoteEvent(eventData);
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing kind 1 event: $e');
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

      String? rootId;
      String? parentId;
      final List<Map<String, String>> eTags = [];
      final List<Map<String, String>> pTags = [];
      final List<String> tTags = [];

      for (final tag in tags) {
        if (tag is List && tag.length >= 2) {
          final tagType = tag[0] as String;
          if (tagType == 'e') {
            final eventId = tag[1] as String;
            final relayUrl = tag.length > 2 ? (tag[2] as String? ?? '') : '';
            final marker = tag.length >= 4 ? tag[3] as String : '';
            final pubkeyTag = tag.length > 4 ? (tag[4] as String? ?? '') : '';

            eTags.add({
              'eventId': eventId,
              'relayUrl': relayUrl,
              'marker': marker,
              'pubkey': pubkeyTag,
            });

            if (marker == 'root') {
              rootId = eventId;
            } else if (marker == 'reply') {
              parentId = eventId;
            }
          } else if (tagType == 'p') {
            pTags.add({
              'pubkey': tag[1] as String,
              'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
              'petname': tag.length > 3 ? (tag[3] as String? ?? '') : '',
            });
          } else if (tagType == 't') {
            final hashtag = (tag[1] as String).toLowerCase();
            if (!tTags.contains(hashtag)) {
              tTags.add(hashtag);
            }
          }
        }
      }

      final bool isReply = rootId != null;

      final note = NoteModel(
        id: id,
        content: content,
        author: authorNpub,
        timestamp: timestamp,
        isReply: isReply,
        isRepost: false,
        rootId: rootId,
        parentId: parentId,
        repostedBy: null,
        reactionCount: _reactionsMap[id]?.length ?? 0,
        replyCount: 0,
        repostCount: _repostsMap[id]?.length ?? 0,
        zapAmount: _zapsMap[id]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0,
        rawWs: jsonEncode(eventData),
        eTags: eTags,
        pTags: pTags,
        tTags: tTags,
      );

      _noteCache[id] = note;
      _eventIds.add(id);

      if (isReply) {
        if (parentId != null) {
          _noteCache[parentId]?.addReply(note);
        }
        if (rootId != parentId) {
          _noteCache[rootId]?.addReply(note);
        }
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing note event: $e');
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
      final filter = Filter(
        kinds: [1],
        eTags: [rootNoteId],
        limit: 100,
      );

      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);
      final requestJson = jsonDecode(serializedRequest) as List;
      final actualSubscriptionId = requestJson[1] as String;

      final allRelays = _relayManager.relayUrls.toList();
      final processedReplyIds = <String>{};

      await Future.wait(allRelays.map((relayUrl) async {
        try {
          if (_isClosed) {
            return;
          }

          final completer = await _relayManager.sendQuery(
            relayUrl,
            serializedRequest,
            actualSubscriptionId,
            timeout: const Duration(seconds: 3),
            onEvent: (eventData, url) {
              try {
                final eventId = eventData['id'] as String;
                final eventKind = eventData['kind'] as int;

                if (eventKind == 1 && !processedReplyIds.contains(eventId)) {
                  processedReplyIds.add(eventId);
                  unawaited(_processNostrEvent(eventData));
                }
              } catch (e) {
              }
            },
          );

          await completer.future;
        } catch (e) {
          debugPrint('[NostrDataService] Error fetching thread replies: $e');
        }
      }));

      _pendingThreadFetches.remove(rootNoteId);
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching thread replies for $rootNoteId: $e');
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

      String? rootId;
      String? actualParentId = parentEventId;
      String? replyMarker;
      final List<Map<String, String>> eTags = [];
      final List<Map<String, String>> pTags = [];
      final List<String> tTags = [];

      for (var tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          if (tag[0] == 'e' && tag.length >= 2) {
            final eTag = <String, String>{
              'eventId': tag[1] as String,
              'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
              'marker': tag.length > 3 ? (tag[3] as String? ?? '') : '',
              'pubkey': tag.length > 4 ? (tag[4] as String? ?? '') : '',
            };
            eTags.add(eTag);

            if (tag.length >= 4 && tag[3] == 'root') {
              rootId = tag[1] as String;
              replyMarker = 'root';
            } else if (tag.length >= 4 && tag[3] == 'reply') {
              actualParentId = tag[1] as String;
              replyMarker = 'reply';
            }
          } else if (tag[0] == 'p' && tag.length >= 2) {
            final pTag = <String, String>{
              'pubkey': tag[1] as String,
              'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
              'petname': tag.length > 3 ? (tag[3] as String? ?? '') : '',
            };
            pTags.add(pTag);
          } else if (tag[0] == 't' && tag.length >= 2) {
            final hashtag = (tag[1] as String).toLowerCase();
            if (!tTags.contains(hashtag)) {
              tTags.add(hashtag);
            }
          }
        }
      }

      final finalParentId = actualParentId ?? parentEventId;
      final parentNote = _noteCache[finalParentId];

      final replyNote = NoteModel(
        id: id,
        content: content,
        author: authorNpub,
        timestamp: timestamp,
        isReply: true,
        parentId: actualParentId ?? parentEventId,
        rootId: rootId ?? parentNote?.rootId,
        rawWs: jsonEncode(eventData),
        eTags: eTags,
        pTags: pTags,
        tTags: tTags,
        replyMarker: replyMarker,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
      );

      _noteCache[id] = replyNote;
      _eventIds.add(id);

      _ensureProfileExists(pubkey, authorNpub);

      _updateParentNoteReplyCount(actualParentId ?? parentEventId);

      _scheduleUIUpdate();
    } catch (e) {
      debugPrint('[NostrDataService] Error processing reply event: $e');
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

      String? targetEventId;
      for (final tag in tags) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          targetEventId = tag[1] as String;
          break;
        }
      }

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
      debugPrint('[NostrDataService] Error processing reaction event: $e');
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

        debugPrint(' [NostrDataService] Processing repost $id by $reposterNpub');
        debugPrint(' [NostrDataService] Original event ID: $originalEventId');
        debugPrint(' [NostrDataService] Original author hex: $originalAuthorHex');
        debugPrint(' [NostrDataService] Repost content length: ${content.length}');

        bool detectedIsReply = false;
        String? detectedRootId;
        String? detectedParentId;

        final originalNote = _noteCache[originalEventId];
        String displayContent = 'Reposted note';
        String displayAuthor = originalAuthorHex != null ? (_authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex) : 'Unknown';

        debugPrint(' [NostrDataService] Original note in cache: ${originalNote != null}');
        if (originalNote != null) {
          debugPrint(' [NostrDataService] Original note isReply: ${originalNote.isReply}');
          detectedIsReply = originalNote.isReply;
          detectedRootId = originalNote.rootId;
          detectedParentId = originalNote.parentId;
        }

        if (originalNote != null) {
          displayContent = originalNote.content;
          displayAuthor = originalNote.author;
        } else if (content.isNotEmpty) {
          debugPrint(' [NostrDataService] Parsing content since original not in cache...');
          debugPrint(' [NostrDataService] Content to parse (first 300 chars): ${content.substring(0, math.min(300, content.length))}');

          try {
            final originalContent = jsonDecode(content) as Map<String, dynamic>;
            debugPrint('[NostrDataService] Successfully parsed repost JSON content');
            debugPrint(' [NostrDataService] Original content field: ${originalContent['content']}');
            debugPrint(' [NostrDataService] Original tags field: ${originalContent['tags']}');

            displayContent = originalContent['content'] as String? ?? displayContent;
            if (originalAuthorHex != null) {
              displayAuthor = _authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex;
            }

            final originalTags = originalContent['tags'] as List<dynamic>? ?? [];

            debugPrint(' [NostrDataService] Checking if original note is reply. Tags count: ${originalTags.length}');
            debugPrint(' [NostrDataService] All tags: $originalTags');

            for (int i = 0; i < originalTags.length; i++) {
              final tag = originalTags[i];
              debugPrint('   Tag[$i]: $tag (type: ${tag.runtimeType})');

              if (tag is List && tag.length >= 2 && tag[0] == 'e') {
                final eventId = tag[1] as String;
                debugPrint('   E-tag[$i]: eventId=$eventId, length=${tag.length}');

                if (tag.length >= 4) {
                  final marker = tag[3] as String;
                  debugPrint('   Marker[$i]: "$marker"');
                  if (marker == 'root') {
                    detectedRootId = eventId;
                    detectedParentId = eventId;
                    detectedIsReply = true;
                    debugPrint('  ROOT marker found - this is a direct reply! rootId: $detectedRootId, parentId: $detectedParentId');
                  } else if (marker == 'reply') {
                    detectedParentId = eventId;
                    detectedIsReply = true;
                    debugPrint('  REPLY marker found - this is a reply! parentId: $detectedParentId');
                  } else if (marker == 'mention') {
                    debugPrint('  ℹ MENTION marker - not a reply indicator');
                  } else {
                    debugPrint('   Unknown marker: "$marker"');
                  }
                } else {
                  if (detectedParentId == null) {
                    detectedParentId = eventId;
                    detectedRootId = eventId;
                    detectedIsReply = true;
                    debugPrint('  Legacy e-tag found - this is a reply! eventId: $detectedParentId');
                  }
                }
              }
            }

            debugPrint(' [NostrDataService] PARSED Original note reply status: isReply=$detectedIsReply');
            debugPrint(' [NostrDataService] PARSED rootId=$detectedRootId, parentId=$detectedParentId');

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

              _noteCache[originalEventId] = originalNoteFromRepost;
              _eventIds.add(originalEventId);
              debugPrint(' [NostrDataService] Cached original ${detectedIsReply ? "REPLY" : "NOTE"}: $originalEventId');
              debugPrint(' [NostrDataService] Original note parentId: $detectedParentId, rootId: $detectedRootId');
            }
          } catch (e) {
            debugPrint(' [NostrDataService] Failed to parse repost content as JSON: $e');
            debugPrint(' Content that failed: $content');
            displayContent = content.isNotEmpty ? content : displayContent;
          }
        }

        final finalIsReply = detectedIsReply;
        final finalRootId = detectedRootId;
        final finalParentId = detectedParentId;

        debugPrint(' [NostrDataService] FINAL repost determination: isReply=$finalIsReply');
        debugPrint(' [NostrDataService] FINAL rootId=$finalRootId, parentId=$finalParentId');

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

        debugPrint(' [NostrDataService] Created repost note: id=$id');
        debugPrint(' [NostrDataService]   - isReply=${repostNote.isReply}');
        debugPrint(' [NostrDataService]   - isRepost=${repostNote.isRepost}');
        debugPrint(' [NostrDataService]   - rootId=${repostNote.rootId}');
        debugPrint(' [NostrDataService]   - parentId=${repostNote.parentId}');
        debugPrint(' [NostrDataService]   - repostedBy=${repostNote.repostedBy}');
        debugPrint(' [NostrDataService]   - content preview: ${displayContent.substring(0, math.min(50, displayContent.length))}...');

        if (repostNote.isReply && repostNote.parentId != null) {
          debugPrint('[NostrDataService] This repost note SHOULD show "Reply to..." text in UI');
        } else {
          debugPrint(' [NostrDataService] This repost note will NOT show "Reply to..." text');
          debugPrint(' [NostrDataService]   isReply=${repostNote.isReply}, parentId=${repostNote.parentId}');
        }

        _noteCache[id] = repostNote;
        _eventIds.add(id);

        final targetNote = _noteCache[originalEventId];
        if (targetNote != null) {
          targetNote.repostCount = _repostsMap[originalEventId]?.length ?? 0;
          debugPrint(' [NostrDataService] Updated original note $originalEventId repost count: ${targetNote.repostCount}');
        }
      
        _scheduleUIUpdate();
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing repost event: $e');
    }
  }

  void _trackRepostForCount(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      String? originalEventId;
      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'e' && tag.length >= 2) {
          originalEventId = tag[1] as String;
          break;
        }
      }

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
            debugPrint(' [NostrDataService] Updated repost count for $originalEventId: ${targetNote.repostCount}');
          }

          debugPrint(' [NostrDataService] Tracked repost count: ${_repostsMap[originalEventId]!.length} reposts for $originalEventId');
        }
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error tracking repost for count: $e');
    }
  }

  Future<void> _processFollowEvent(Map<String, dynamic> eventData) async {
    try {
      final pubkey = eventData['pubkey'] as String;
      final tags = eventData['tags'] as List<dynamic>;

      final List<String> newFollowing = [];
      for (var tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
          newFollowing.add(tag[1] as String);
        }
      }

      try {
        await _followCacheService.put(pubkey, newFollowing);
      } catch (e) {
        debugPrint('[NostrDataService] Error updating follow cache: $e');
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing follow event: $e');
    }
  }

  Future<void> _processMuteEvent(Map<String, dynamic> eventData) async {
    try {
      final pubkey = eventData['pubkey'] as String;
      final tags = eventData['tags'] as List<dynamic>;

      final List<String> newMuted = [];
      for (var tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
          newMuted.add(tag[1] as String);
        }
      }

      try {
        await _muteCacheService.put(pubkey, newMuted);
      } catch (e) {
        debugPrint('[NostrDataService] Error updating mute cache: $e');
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing mute event: $e');
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
      debugPrint('[NostrDataService] Error processing deletion event: $e');
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

      String? targetEventId;
      String recipient = '';
      String bolt11 = '';
      String description = '';
      int amount = 0;

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          if (tag[0] == 'e' && tag.length >= 2) {
            targetEventId = tag[1] as String;
          } else if (tag[0] == 'p' && tag.length >= 2) {
            recipient = tag[1] as String;
          } else if (tag[0] == 'bolt11' && tag.length >= 2) {
            bolt11 = tag[1] as String;
          } else if (tag[0] == 'description' && tag.length >= 2) {
            description = tag[1] as String;
          } else if (tag[0] == 'amount' && tag.length >= 2) {
            try {
              amount = int.parse(tag[1] as String) ~/ 1000;
            } catch (e) {
              amount = 0;
            }
          }
        }
      }

      String realZapperPubkey = walletPubkey;
      String? zapComment;

      if (description.isNotEmpty) {
        try {
          final zapRequest = jsonDecode(description) as Map<String, dynamic>;

          if (zapRequest.containsKey('pubkey')) {
            realZapperPubkey = zapRequest['pubkey'] as String;
            debugPrint('[NostrDataService] Extracted real zapper from description: $realZapperPubkey');
          }

          if (zapRequest.containsKey('content')) {
            final requestContent = zapRequest['content'] as String;
            if (requestContent.isNotEmpty) {
              zapComment = requestContent;
              debugPrint('[NostrDataService] Extracted zap comment: $zapComment');
            }
          }
        } catch (e) {
          debugPrint('[NostrDataService]  Failed to parse zap description, using wallet pubkey: $e');
        }
      } else {
        debugPrint('[NostrDataService]  No description tag found in zap receipt, using wallet pubkey');
      }

      if (amount == 0 && bolt11.isNotEmpty) {
        try {
          amount = parseAmountFromBolt11(bolt11);
        } catch (e) {
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
      debugPrint('[NostrDataService] Error processing zap event: $e');
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
      debugPrint('[NostrDataService]  Error creating notification: $e');
    }
  }

  void _handleRelayDisconnection(String relayUrl) {
    debugPrint('[NostrDataService] Relay disconnected: $relayUrl');
  }

  void _startCacheCleanup() {}

  void _cleanupCacheIfNeeded() {
    if (_profileCache.length > 2000) {
      final now = timeService.now;
      final cutoffTime = now.subtract(_profileCacheTTL);
      _profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));
    }

    if (_lastInteractionFetch.length > 3000) {
      final now = timeService.now;
      final interactionCutoff = now.subtract(const Duration(hours: 1));
      _lastInteractionFetch.removeWhere((key, timestamp) => timestamp.isBefore(interactionCutoff));
    }

    if (_eventProcessingLock.length > 10000) {
      _eventProcessingLock.clear();
    }

    if (_noteCache.length > 8000) {
      final sortedNotes = _noteCache.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      final notesToRemove = sortedNotes.skip(5000).map((n) => n.id).toList();
      for (final id in notesToRemove) {
        _noteCache.remove(id);
        _eventIds.remove(id);
        _reactionsMap.remove(id);
        _repostsMap.remove(id);
        _zapsMap.remove(id);
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
      debugPrint('[NostrDataService] Error ensuring profile exists: $e');
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
      debugPrint('[NostrDataService] Error fetching user profile: $e');
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
        debugPrint('[NostrDataService] No authors provided - returning empty result');
        return Result.success([]);
      } else if (authorHexKeys.length == 1 && authorHexKeys.first == _authService.npubToHex(_currentUserNpub)) {
        debugPrint('[NostrDataService] Feed mode - fetching follow list first (NIP-02)');

        final currentUserHex = _authService.npubToHex(_currentUserNpub);
        if (currentUserHex == null) {
          debugPrint(' [NostrDataService] Cannot convert current user npub to hex: $_currentUserNpub');
          return const Result.error('Invalid current user npub format');
        }

        debugPrint('[NostrDataService] Current user hex: $currentUserHex');

        debugPrint('[NostrDataService]  Getting follow list for: $_currentUserNpub (hex: $currentUserHex)');
        final followingResult = await getFollowingList(_currentUserNpub);

        debugPrint(
            '[NostrDataService]  Follow list result: success=${followingResult.isSuccess}, data=${followingResult.data?.length ?? 0}');

        if (followingResult.isSuccess && followingResult.data != null && followingResult.data!.isNotEmpty) {
          targetAuthors = List<String>.from(followingResult.data!);
          targetAuthors.add(currentUserHex);
          debugPrint('[NostrDataService] Following list found: ${targetAuthors.length} hex pubkeys');
          debugPrint('[NostrDataService]  Target authors (hex): ${targetAuthors.take(5).toList()}... (showing first 5)');

          for (int i = 0; i < targetAuthors.length && i < 10; i++) {
            final hexPubkey = targetAuthors[i];
            final npub = _authService.hexToNpub(hexPubkey) ?? 'unknown';
            debugPrint('[NostrDataService]   - Following[$i]: $hexPubkey -> $npub');
          }
        } else {
          debugPrint('[NostrDataService]  No follow list found - returning empty feed');
          debugPrint('[NostrDataService] Follow result error: ${followingResult.error}');
          return Result.success([]);
        }
      } else {
        targetAuthors = authorHexKeys;
        debugPrint('[NostrDataService] Profile mode - fetching notes for: ${authorHexKeys.length} hex pubkeys');
        debugPrint('[NostrDataService] Profile authors (hex): $targetAuthors');
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
      final requestJson = jsonDecode(serializedRequest) as List;
      final subscriptionId = requestJson[1] as String;
      final allRelays = _relayManager.relayUrls.toList();

      final fetchedNotes = <String, NoteModel>{};

      await Future.wait(allRelays.map((relayUrl) async {
        try {
          final completer = await _relayManager.sendQuery(
            relayUrl,
            serializedRequest,
            subscriptionId,
            timeout: const Duration(seconds: 30),
            onEvent: (data, url) {
              try {
                final eventData = data is Map<String, dynamic> ? data : jsonDecode(data.toString()) as Map<String, dynamic>;
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
              } catch (e) {
                debugPrint('[NostrDataService] Error processing profile event: $e');
              }
            },
          );

          await completer.future.timeout(const Duration(seconds: 30), onTimeout: () {});
        } catch (e) {
          debugPrint('[NostrDataService] Error querying relay $relayUrl: $e');
        }
      }));

      for (final note in fetchedNotes.values) {
        if (!_eventIds.contains(note.id)) {
          _noteCache[note.id] = note;
          _eventIds.add(note.id);
        }
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
      debugPrint('[NostrDataService] PROFILE: Error processing event: $e');
      return null;
    }
  }


  NoteModel? _processKind1ForProfileSync(Map<String, dynamic> eventData, String authorNpub, DateTime timestamp) {
    try {
      final id = eventData['id'] as String;
      final content = eventData['content'] as String;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      String? rootId;
      String? parentId;
      final List<Map<String, String>> eTags = [];
      final List<Map<String, String>> pTags = [];

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          if (tag[0] == 'e' && tag.length >= 2) {
            final eventId = tag[1] as String;
            final relayUrl = tag.length > 2 ? (tag[2] as String? ?? '') : '';
            final marker = tag.length >= 4 ? tag[3] as String : '';
            final pubkeyTag = tag.length > 4 ? (tag[4] as String? ?? '') : '';

            eTags.add({
              'eventId': eventId,
              'relayUrl': relayUrl,
              'marker': marker,
              'pubkey': pubkeyTag,
            });

            if (marker == 'root') {
              rootId = eventId;
            } else if (marker == 'reply') {
              parentId = eventId;
            }
          } else if (tag[0] == 'p' && tag.length >= 2) {
            pTags.add({
              'pubkey': tag[1] as String,
              'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
              'petname': tag.length > 3 ? (tag[3] as String? ?? '') : '',
            });
          }
        }
      }

      final bool isReply = rootId != null;

      final note = NoteModel(
        id: id,
        content: content,
        author: authorNpub,
        timestamp: timestamp,
        isReply: isReply,
        isRepost: false,
        rootId: rootId,
        parentId: parentId,
        repostedBy: null,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(eventData),
        eTags: eTags,
        pTags: pTags,
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
          debugPrint('[NostrDataService] PROFILE: Failed to parse repost content: $e');
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

      final allRelays = _relayManager.relayUrls.toList();
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

      await Future.wait(allRelays.map((relayUrl) async {
        try {
          final completer = await _relayManager.sendQuery(
            relayUrl,
            serializedRequest,
            subscriptionId,
            timeout: const Duration(seconds: 30),
            onEvent: (data, url) {
              try {
                final eventData = data is Map<String, dynamic> ? data : jsonDecode(data.toString()) as Map<String, dynamic>;
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
                      _noteCache[eventId] = note;
                      _eventIds.add(eventId);
                      if (!hashtagNotes.any((n) => n.id == eventId)) {
                        hashtagNotes.add(note);
                      }
                    }
                  }
                }
              } catch (e) {
                debugPrint('[NostrDataService] Error processing hashtag event: $e');
              }
            },
          );

          await completer.future.timeout(const Duration(seconds: 30), onTimeout: () {});
        } catch (e) {
          debugPrint('[NostrDataService] Error querying relay $relayUrl: $e');
        }
      }));

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

      String? rootId;
      String? parentId;
      final List<Map<String, String>> eTags = [];
      final List<Map<String, String>> pTags = [];
      final List<String> tTags = [];

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          if (tag[0] == 'e' && tag.length >= 2) {
            final eventId = tag[1] as String;
            final relayUrl = tag.length > 2 ? (tag[2] as String? ?? '') : '';
            final marker = tag.length >= 4 ? tag[3] as String : '';
            final pubkeyTag = tag.length > 4 ? (tag[4] as String? ?? '') : '';

            eTags.add({
              'eventId': eventId,
              'relayUrl': relayUrl,
              'marker': marker,
              'pubkey': pubkeyTag,
            });

            if (marker == 'root') {
              rootId = eventId;
            } else if (marker == 'reply') {
              parentId = eventId;
            }
          } else if (tag[0] == 'p' && tag.length >= 2) {
            pTags.add({
              'pubkey': tag[1] as String,
              'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
              'petname': tag.length > 3 ? (tag[3] as String? ?? '') : '',
            });
          } else if (tag[0] == 't' && tag.length >= 2) {
            final hashtag = (tag[1] as String).toLowerCase();
            if (!tTags.contains(hashtag)) {
              tTags.add(hashtag);
            }
          }
        }
      }

      final bool isReply = rootId != null;

      final note = NoteModel(
        id: id,
        content: content,
        author: authorNpub,
        timestamp: timestamp,
        isReply: isReply,
        isRepost: false,
        rootId: rootId,
        parentId: parentId,
        repostedBy: null,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
        rawWs: jsonEncode(eventData),
        eTags: eTags,
        pTags: pTags,
        tTags: tTags,
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
        const Duration(milliseconds: 1500),
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

      final basicUser = UserModel(
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
      debugPrint('[NostrDataService] Starting note post: ${content.length > 30 ? content.substring(0, 30) : content}...');

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        debugPrint('[NostrDataService ERROR] Authentication error: ${privateKeyResult.error}');
        return Result.error('Private key not found: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        debugPrint('[NostrDataService ERROR] Authentication credentials invalid');
        return const Result.error('Private key not found.');
      }

      debugPrint('[NostrDataService] Credentials validated, creating note event...');

      dynamic event;
      try {
        event = NostrService.createNoteEvent(
          content: content,
          privateKey: privateKey,
          tags: tags,
        );
        debugPrint(
            '[NostrDataService] Note event created successfully (id: ${event.id.substring(0, 8)}...), ensuring relay connections...');
      } catch (e, st) {
        debugPrint('[NostrDataService ERROR] Failed to create note event: $e');
        debugPrint('[NostrDataService ERROR] Stack trace: $st');
        return Result.error('Failed to create note event: $e');
      }

      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'note_post',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));
      debugPrint('[NostrDataService] Note broadcasted IMMEDIATELY to ${_relayManager.activeSockets.length} relays');

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

      _noteCache[note.id] = note;
      _eventIds.add(note.id);

      _scheduleUIUpdate();

      debugPrint('[NostrDataService] Note posted and cached successfully');
      return Result.success(note);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error posting note: $e');
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

  Future<Result<void>> repostNote({
    required String noteId,
    required String noteAuthor,
    String? content,
  }) async {
    try {
      debugPrint('[NostrDataService] Starting repost of note: $noteId');

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

      debugPrint('[NostrDataService] Creating repost event...');

      final event = NostrService.createRepostEvent(
        noteId: noteId,
        noteAuthor: _authService.npubToHex(noteAuthor) ?? noteAuthor,
        content: repostContent,
        privateKey: privateKey,
      );

      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'repost',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));
      debugPrint('[NostrDataService] Repost broadcasted IMMEDIATELY to ${_relayManager.activeSockets.length} relays');

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

      _noteCache[event.id] = repostNote;
      _eventIds.add(event.id);

      _trackRepostForCount(NostrService.eventToJson(event));

      _scheduleUIUpdate();

      debugPrint('[NostrDataService] Repost completed successfully');
      return const Result.success(null);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error reposting note: $e');
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
      debugPrint('[NostrDataService] Starting reply post to parentEventId: $parentEventId');

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
        debugPrint('[NostrDataService] Parent note not found: $parentEventId');
        return const Result.error('Parent note not found.');
      }

      debugPrint('[NostrDataService] Found parent note: ${parentNote.id}');
      debugPrint('[NostrDataService] Parent note author: ${parentNote.author}');
      debugPrint('[NostrDataService] Building reply tags EXACTLY like working code...');

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

      debugPrint('[NostrDataService] Reply logic: rootId=$actualRootId, replyId=$actualReplyId, marker=$replyMarker');

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
        debugPrint('[NostrDataService] Added ${additionalTags.length} additional tags to reply');
      }

      debugPrint('[NostrDataService] Creating NIP-10 compliant reply event...');

      final event = NostrService.createReplyEvent(
        content: content,
        privateKey: privateKey,
        tags: tags,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _relayManager.activeSockets;

      debugPrint('[NostrDataService] Broadcasting reply to ${activeSockets.length} active sockets...');
      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          try {
            ws.add(serializedEvent);
            debugPrint('[NostrDataService] Reply sent to relay via WebSocket');
          } catch (e) {
            debugPrint('[NostrDataService] Error sending reply to WebSocket: $e');
          }
        } else {
          debugPrint('[NostrDataService] WebSocket not open, state: ${ws.readyState}');
        }
      }
      debugPrint('[NostrDataService] Reply broadcasted DIRECTLY to ${activeSockets.length} relays like working code');

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

      _noteCache[reply.id] = reply;
      _eventIds.add(reply.id);
      _scheduleUIUpdate();

      debugPrint('[NostrDataService] NIP-10 compliant reply posted successfully');
      return Result.success(reply);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error posting reply: $e');
      return Result.error('Failed to post reply: $e');
    }
  }

  Future<Result<UserModel>> updateUserProfile(UserModel user) async {
    try {
      debugPrint('[NostrDataService] Starting profile update for: ${user.name}');

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

      debugPrint('[NostrDataService] Profile content: $profileContent');

      final event = NostrService.createProfileEvent(
        profileContent: profileContent,
        privateKey: privateKey,
      );

      debugPrint('[NostrDataService] Profile event created, broadcasting to relays...');

      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'profile_update',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));
      debugPrint('[NostrDataService] Profile event broadcasted IMMEDIATELY to ${_relayManager.activeSockets.length} relays');

      final eventJson = NostrService.eventToJson(event);
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(eventJson['created_at'] * 1000);
      final pubkeyHex = eventJson['pubkey'] as String;

      final updatedUser = UserModel(
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

      debugPrint('[NostrDataService] Profile updated, cache invalidated, and cached successfully.');
      return Result.success(updatedUser);
    } catch (e, st) {
      debugPrint('[NostrDataService ERROR] Error updating profile: $e\n$st');
      return Result.error('Failed to update profile: $e');
    }
  }

  Future<Result<List<NotificationModel>>> fetchNotifications({
    int limit = 50,
    DateTime? since,
  }) async {
    try {
      debugPrint('[NostrDataService]  Fetching notifications...');

      final userResult = await _authService.getCurrentUserPublicKeyHex();
      if (userResult.isError) {
        return Result.error('Not authenticated: ${userResult.error}');
      }

      final pubkeyHex = userResult.data;
      if (pubkeyHex == null) {
        return const Result.error('No user public key available');
      }

      _currentUserNpub = (await _authService.getCurrentUserNpub()).data ?? '';

      debugPrint('[NostrDataService]  Fetching notifications for user hex: $pubkeyHex');
      debugPrint('[NostrDataService]  User npub: $_currentUserNpub');

      int? sinceTimestamp;
      if (since != null) {
        sinceTimestamp = since.millisecondsSinceEpoch ~/ 1000;
      } else {
        sinceTimestamp = timeService.subtract(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;
      }

      debugPrint('[NostrDataService]  Notification filter since: $sinceTimestamp');

      if (_notificationSubscriptionActive && _notificationSubscriptionId != null) {
        debugPrint('[NostrDataService]  Closing existing notification subscription: $_notificationSubscriptionId');
        await _relayManager.broadcast(jsonEncode(['CLOSE', _notificationSubscriptionId]));
      }

      final filter = {
        'kinds': [1, 6, 7, 9735],
        '#p': [pubkeyHex],
        'since': sinceTimestamp,
        'limit': limit,
      };

      _notificationSubscriptionId = 'notifications_persistent';
      final request = ['REQ', _notificationSubscriptionId, filter];

      debugPrint('[NostrDataService]  Broadcasting persistent notification request: $request');

      await _relayManager.broadcast(jsonEncode(request));
      _notificationSubscriptionActive = true;

      final notifications = _notificationCache[_currentUserNpub] ?? [];

      debugPrint('[NostrDataService]  Returning ${notifications.length} cached notifications (subscription remains active)');

      return Result.success(notifications.take(limit).toList());
    } catch (e) {
      debugPrint('[NostrDataService]  Error fetching notifications: $e');
      return Result.error('Failed to fetch notifications: $e');
    }
  }

  Future<void> stopNotificationSubscription() async {
    if (_notificationSubscriptionActive && _notificationSubscriptionId != null) {
      debugPrint('[NostrDataService]  Stopping notification subscription: $_notificationSubscriptionId');
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
      final allRelays = _relayManager.relayUrls.toList();
      final processedEventIds = <String>{};

      final requestJson = jsonDecode(serializedRequest) as List;
      final subscriptionId = requestJson[1] as String;

      await Future.wait(allRelays.map((relayUrl) async {
        try {
          if (_isClosed) {
            return;
          }

          final completer = await _relayManager.sendQuery(
            relayUrl,
            serializedRequest,
            subscriptionId,
            timeout: const Duration(seconds: 3),
            onEvent: (eventData, url) {
              try {
                final eventId = eventData['id'] as String;
                final eventAuthor = eventData['pubkey'] as String;
                final eventKind = eventData['kind'] as int;

                if (eventAuthor == pubkeyHex && eventKind == 3 && !processedEventIds.contains(eventId)) {
                  processedEventIds.add(eventId);

                  final tags = eventData['tags'] as List<dynamic>;
                  for (var tag in tags) {
                    if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
                      following.add(tag[1] as String);
                    }
                  }
                }
              } catch (e) {
                debugPrint('[NostrDataService] Error processing follow list: $e');
              }
            },
          );

          await completer.future;
        } catch (e) {
          debugPrint('[NostrDataService] Error fetching follow list: $e');
        }
      }));

      final uniqueFollowing = following.toList();
      debugPrint('[NostrDataService] Follow list: ${uniqueFollowing.length} users');

      return Result.success(uniqueFollowing);
    } catch (e) {
      debugPrint('[NostrDataService] Error in getFollowingList: $e');
      return Result.error('Failed to get following list: $e');
    }
  }

  Future<bool> fetchSpecificNote(String noteId) async {
    try {
      if (_noteCache.containsKey(noteId)) {
        return true;
      }

      final allRelays = _relayManager.relayUrls.toList();
      bool noteFound = false;

      await Future.wait(allRelays.map((relayUrl) async {
        try {
          if (_isClosed) {
            return;
          }

          final filter = NostrService.createEventByIdFilter(eventIds: [noteId]);
          final request = NostrService.createRequest(filter);
          final serializedRequest = NostrService.serializeRequest(request);
          final requestJson = jsonDecode(serializedRequest) as List;
          final subscriptionId = requestJson[1] as String;

          final completer = await _relayManager.sendQuery(
            relayUrl,
            serializedRequest,
            subscriptionId,
            timeout: const Duration(seconds: 3),
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
                      _noteCache[eventId] = note;
                      _eventIds.add(eventId);
                      noteFound = true;
                    }
                  }
                }
              } catch (e) {
              }
            },
          );

          await completer.future;
        } catch (e) {
        }
      }));

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
      debugPrint('[NostrDataService] Error fetching specific notes: $e');
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
      debugPrint('[NostrDataService] Error handling COUNT response: $e');
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
      debugPrint('[NostrDataService] Error handling CLOSED message: $e');
    }
  }

  Future<int> fetchFollowerCount(String pubkeyHex, {int maxRetries = 3, int attempt = 1}) async {
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
            const Duration(seconds: 5),
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
      debugPrint('[NostrDataService] Exception in follower COUNT request for $pubkeyHex: $e');
      return 0;
    }
  }

  Future<void> fetchInteractionsForNotesWithEOSE(String noteId) async {
    await fetchInteractionsForNotesBatchWithEOSE([noteId]);
  }

  Future<void> fetchInteractionsForNotesBatchWithEOSE(List<String> noteIds) async {
    if (_isClosed || noteIds.isEmpty) return;

    try {
      final allRelays = _relayManager.relayUrls.toList();
      if (allRelays.isEmpty) return;

      final processedInteractionIds = <String>{};
      final sortedNoteIds = noteIds.toSet().toList()..sort();

      final interactionKinds = [1, 7, 6, 9735];
      final deletionKinds = [5];
      final quoteKinds = [1];

      await Future.wait(allRelays.map((relayUrl) async {
        try {
          if (_isClosed) return;

          final quoteFilter = Filter(
            kinds: quoteKinds,
            limit: 1000,
          );
          quoteFilter.setTag('q', sortedNoteIds);

          final filters = [
            Filter(
              kinds: interactionKinds,
              eTags: sortedNoteIds,
              limit: 1000,
            ),
            Filter(
              kinds: deletionKinds,
              eTags: sortedNoteIds,
              limit: 100,
            ),
            quoteFilter,
          ];

          final request = NostrService.createMultiFilterRequest(filters);
          final requestJson = jsonDecode(request) as List;
          final subscriptionId = requestJson[1] as String;

          final completer = await _relayManager.sendQuery(
            relayUrl,
            request,
            subscriptionId,
            onEvent: (eventData, url) {
              try {
                final eventId = eventData['id'] as String;
                final eventKind = eventData['kind'] as int;

                if ((interactionKinds.contains(eventKind) || 
                     deletionKinds.contains(eventKind) || 
                     quoteKinds.contains(eventKind)) && 
                    !processedInteractionIds.contains(eventId)) {
                  processedInteractionIds.add(eventId);
                  unawaited(_processNostrEvent(eventData));
                }
              } catch (e) {
              }
            },
          );

          await completer.future;
        } catch (e) {
          debugPrint('[NostrDataService] Error fetching interactions from $relayUrl: $e');
        }
      }));

      for (final noteId in noteIds) {
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
      debugPrint('[NostrDataService] Error fetching interactions with EOSE: $e');
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
      debugPrint('[NostrDataService] Error updating parent note reply count: $e');
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
      debugPrint('[NostrDataService] Error updating note reply count: $e');
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
      debugPrint('[NostrDataService] Starting quote post of event: $quotedEventId');

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Authentication error: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Authentication credentials not available.');
      }

      debugPrint('[NostrDataService] Creating quote event...');

      final event = NostrService.createQuoteEvent(
        content: content,
        quotedEventId: quotedEventId,
        quotedEventPubkey: quotedEventPubkey,
        relayUrl: relayUrl,
        privateKey: privateKey,
        additionalTags: additionalTags,
      );

      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'quote_post',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));
      debugPrint('[NostrDataService] Quote note broadcasted IMMEDIATELY to ${_relayManager.activeSockets.length} relays');

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

      _noteCache[note.id] = note;
      _eventIds.add(note.id);
      _scheduleUIUpdate();

      debugPrint('[NostrDataService] Quote note posted successfully');
      return Result.success(note);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error posting quote: $e');
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

      try {
        if (_relayManager.activeSockets.isEmpty) {
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'note_delete',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      _noteCache.remove(noteId);
      _eventIds.remove(noteId);
      _reactionsMap.remove(noteId);
      _repostsMap.remove(noteId);
      _zapsMap.remove(noteId);

      if (!_isClosed && !_noteDeletedController.isClosed) {
        _noteDeletedController.add(noteId);
      }

      debugPrint('[NostrDataService] Note deleted: $noteId');
      return const Result.success(null);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error deleting note: $e');
      return Result.error('Failed to delete note: $e');
    }
  }

  Future<Result<String>> sendMedia(String filePath, String blossomUrl) async {
    try {
      debugPrint('[NostrDataService] Starting media upload to Blossom: $filePath -> $blossomUrl');

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError) {
        return Result.error('Authentication error: ${privateKeyResult.error}');
      }

      final privateKey = privateKeyResult.data;
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('Authentication credentials not available.');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        return Result.error('File not found: $filePath');
      }

      final fileBytes = await file.readAsBytes();
      debugPrint('[NostrDataService] File read: ${fileBytes.length} bytes');

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

      debugPrint('[NostrDataService] Detected MIME type: $mimeType');

      final publicKey = Bip340.getPublicKey(privateKey);

      final ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [],
        ),
      );

      ndk.accounts.loginPrivateKey(
        pubkey: publicKey,
        privkey: privateKey,
      );

      final ndkFile = NdkFile(
        data: Uint8List.fromList(fileBytes),
        mimeType: mimeType,
      );

      final cleanedUrl = blossomUrl.replaceAll(RegExp(r'/+$'), '');
      debugPrint('[NostrDataService] Uploading to: $cleanedUrl');

      final uploadResults = await ndk.files.upload(
        file: ndkFile,
        serverUrls: [cleanedUrl],
      );

      debugPrint('[NostrDataService] Upload response: ${uploadResults.length} result(s)');

      if (uploadResults.isEmpty || !uploadResults.first.success) {
        return Result.error('Upload failed: ${uploadResults.first.error ?? 'Unknown error'}');
      }

      final blobDescriptor = uploadResults.first.descriptor;
      if (blobDescriptor == null) {
        return const Result.error('Upload succeeded but no descriptor returned.');
      }

      final url = blobDescriptor.url.isNotEmpty ? blobDescriptor.url : blobDescriptor.sha256;
      debugPrint('[NostrDataService] Media uploaded successfully: $url');
      return Result.success(url);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error uploading media: $e');
      return Result.error('Failed to upload media: $e');
    }
  }

  Future<Result<void>> publishFollowEvent({
    required List<String> followingHexList,
    required String privateKey,
  }) async {
    try {
      debugPrint('[NostrDataService] Publishing kind 3 follow event with ${followingHexList.length} following');

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user not found');
      }

      final currentUserNpub = currentUserResult.data!;

      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'follow_event',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      final event = NostrService.createFollowEvent(
        followingPubkeys: followingHexList,
        privateKey: privateKey,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _relayManager.activeSockets;

      debugPrint('[NostrDataService] Broadcasting follow event to ${activeSockets.length} active sockets...');
      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          try {
            ws.add(serializedEvent);
            debugPrint('[NostrDataService] Follow event sent to relay via WebSocket');
          } catch (e) {
            debugPrint('[NostrDataService] Error sending follow event to WebSocket: $e');
          }
        }
      }

      try {
        final currentUserHex = _authService.npubToHex(currentUserNpub) ?? currentUserNpub;
        await _followCacheService.put(currentUserHex, followingHexList);
        debugPrint('[NostrDataService] Follow event broadcasted DIRECTLY and cached locally');
        debugPrint('[NostrDataService] Updated follow cache for $currentUserNpub: ${followingHexList.length} following');
      } catch (e) {
        debugPrint('[NostrDataService] Error caching follow list: $e');
      }

      return const Result.success(null);
    } catch (e) {
      debugPrint('[NostrDataService] Failed to publish follow event: $e');
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
      final allRelays = _relayManager.relayUrls.toList();
      final processedEventIds = <String>{};

      final requestJson = jsonDecode(serializedRequest) as List;
      final subscriptionId = requestJson[1] as String;

      await Future.wait(allRelays.map((relayUrl) async {
        try {
          if (_isClosed) {
            return;
          }

          final completer = await _relayManager.sendQuery(
            relayUrl,
            serializedRequest,
            subscriptionId,
            timeout: const Duration(seconds: 3),
            onEvent: (eventData, url) {
              try {
                final eventId = eventData['id'] as String;
                final eventAuthor = eventData['pubkey'] as String;
                final eventKind = eventData['kind'] as int;

                if (eventAuthor == pubkeyHex && eventKind == 10000 && !processedEventIds.contains(eventId)) {
                  processedEventIds.add(eventId);

                  final tags = eventData['tags'] as List<dynamic>;
                  for (var tag in tags) {
                    if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
                      muted.add(tag[1] as String);
                    }
                  }
                }
              } catch (e) {
                debugPrint('[NostrDataService] Error processing mute list: $e');
              }
            },
          );

          await completer.future;
        } catch (e) {
          debugPrint('[NostrDataService] Error fetching mute list: $e');
        }
      }));

      final uniqueMuted = muted.toList();
      debugPrint('[NostrDataService] Mute list: ${uniqueMuted.length} users');

      if (uniqueMuted.isNotEmpty) {
        await _muteCacheService.put(pubkeyHex, uniqueMuted);
      }

      return Result.success(uniqueMuted);
    } catch (e) {
      debugPrint('[NostrDataService] Error getting mute list: $e');
      return Result.error('Failed to get mute list: $e');
    }
  }

  Future<Result<void>> publishMuteEvent({
    required List<String> mutedHexList,
    required String privateKey,
  }) async {
    try {
      debugPrint('[NostrDataService] Publishing kind 10000 mute event with ${mutedHexList.length} muted');

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user not found');
      }

      final currentUserNpub = currentUserResult.data!;

      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'mute_event',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      final event = NostrService.createMuteEvent(
        mutedPubkeys: mutedHexList,
        privateKey: privateKey,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _relayManager.activeSockets;

      debugPrint('[NostrDataService] Broadcasting mute event to ${activeSockets.length} active sockets...');
      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          try {
            ws.add(serializedEvent);
            debugPrint('[NostrDataService] Mute event sent to relay via WebSocket');
          } catch (e) {
            debugPrint('[NostrDataService] Error sending mute event to WebSocket: $e');
          }
        }
      }

      try {
        final currentUserHex = _authService.npubToHex(currentUserNpub) ?? currentUserNpub;
        await _muteCacheService.put(currentUserHex, mutedHexList);
        debugPrint('[NostrDataService] Mute event broadcasted DIRECTLY and cached locally');
        debugPrint('[NostrDataService] Updated mute cache for $currentUserNpub: ${mutedHexList.length} muted');
      } catch (e) {
        debugPrint('[NostrDataService] Error caching mute list: $e');
      }

      return const Result.success(null);
    } catch (e) {
      debugPrint('[NostrDataService] Failed to publish mute event: $e');
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
        debugPrint('[NostrDataService] Cleaned $removedCount muted notes from cache');
        _scheduleUIUpdate();
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error cleaning muted notes from cache: $e');
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
      debugPrint('[NostrDataService] Error checking user reaction: $e');
      return false;
    }
  }

  bool hasUserReposted(String noteId, String userNpub) {
    try {
      final reposts = _repostsMap[noteId] ?? [];
      return reposts.any((repost) => repost.author == userNpub);
    } catch (e) {
      debugPrint('[NostrDataService] Error checking user repost: $e');
      return false;
    }
  }

  bool hasUserZapped(String noteId, String userNpub) {
    try {
      final zaps = _zapsMap[noteId] ?? [];
      return zaps.any((zap) => zap.sender == userNpub);
    } catch (e) {
      debugPrint('[NostrDataService] Error checking user zap: $e');
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
      debugPrint('[NostrDataService] Filtering ${notes.length} notes by mute list with ${mutedSet.length} muted users');

      final filteredNotes = notes.where((note) {
        if (note.isRepost && note.repostedBy != null) {
          final reposterHex = _authService.npubToHex(note.repostedBy!) ?? note.repostedBy!;
          if (mutedSet.contains(reposterHex)) {
            debugPrint('[NostrDataService] Excluding repost by muted user: ${note.repostedBy}');
            return false;
          }
        }

        final noteAuthorHex = _authService.npubToHex(note.author) ?? note.author;
        if (mutedSet.contains(noteAuthorHex)) {
          debugPrint('[NostrDataService] Excluding note by muted user: ${note.author}');
          return false;
        }

        return true;
      }).toList();

      debugPrint(
          '[NostrDataService] Mute filtered result: ${filteredNotes.length} notes (${notes.length - filteredNotes.length} excluded)');
      return filteredNotes;
    } catch (e) {
      debugPrint('[NostrDataService] Error filtering notes by mute list: $e');
      return notes;
    }
  }

  void dispose() {
    _isClosed = true;
    _batchProcessingTimer?.cancel();
    _uiUpdateThrottleTimer?.cancel();
    _relayManager.unregisterService('nostr_data_service');
    _notesController.close();
    _usersController.close();
    _notificationsController.close();
    _noteDeletedController.close();
    clearCaches();
  }
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
