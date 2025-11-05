import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';

import '../../core/base/result.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';
import '../../models/notification_model.dart';
import '../../models/reaction_model.dart';
import '../../models/zap_model.dart';
import '../../services/nostr_service.dart';
import '../../services/relay_service.dart';
import '../../services/time_service.dart';
import '../../services/nip05_verification_service.dart';
import 'auth_service.dart';
import 'user_cache_service.dart';
import 'follow_cache_service.dart';

class NostrDataService {
  final AuthService _authService;
  final WebSocketManager _relayManager;
  final Nip05VerificationService _nip05Service = Nip05VerificationService.instance;
  final UserCacheService _userCacheService = UserCacheService.instance;
  final FollowCacheService _followCacheService = FollowCacheService.instance;

  final StreamController<List<NoteModel>> _notesController = StreamController<List<NoteModel>>.broadcast();
  final StreamController<List<UserModel>> _usersController = StreamController<List<UserModel>>.broadcast();
  final StreamController<List<NotificationModel>> _notificationsController = StreamController<List<NotificationModel>>.broadcast();

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
  static const int _maxBatchSize = 100;
  static const Duration _batchTimeout = Duration(milliseconds: 50);

  bool _isClosed = false;
  String _currentUserNpub = '';

  Timer? _uiUpdateThrottleTimer;
  bool _uiUpdatePending = false;
  static const Duration _uiUpdateThrottle = Duration(milliseconds: 300);

  final Map<String, DateTime> _lastInteractionFetch = {};
  final Duration _interactionFetchCooldown = Duration(seconds: 5);

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

  AuthService get authService => _authService;

  String _currentContext = 'feed';

  void setContext(String context) {
    _currentContext = context;
  }

  bool _shouldIncludeNoteInFeed(String authorHexPubkey, bool isRepost) {
    if (_currentContext != 'feed') {
      return true;
    }

    if (!_isFollowingListReady || _cachedFollowingList == null) {
      return false;
    }

    final currentUserHex = _authService.npubToHex(_currentUserNpub);
    if (currentUserHex == authorHexPubkey) {
      return true;
    }

    return _cachedFollowingList!.contains(authorHexPubkey);
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

  bool _isFollowingListReady = false;
  List<String>? _cachedFollowingList;

  Future<void> _initializeFollowListCache() async {
    try {
      final currentUser = await _authService.getCurrentUserNpub();
      if (currentUser.isSuccess && currentUser.data != null) {
        _currentUserNpub = currentUser.data!;

        final currentUserHex = _authService.npubToHex(_currentUserNpub) ?? _currentUserNpub;
        final followingList = await _followCacheService.getOrFetch(currentUserHex, () async {
          final result = await getFollowingList(_currentUserNpub);
          return result.isSuccess ? result.data : null;
        });

        if (followingList != null && followingList.isNotEmpty) {
          _cachedFollowingList = followingList;
          _isFollowingListReady = true;
        } else {
          _isFollowingListReady = false;
        }
      }
    } catch (e) {
      _isFollowingListReady = false;
    }
  }

  void _handleRelayEvent(dynamic rawEvent, String relayUrl) {
    try {
      final eventData = jsonDecode(rawEvent);
      if (eventData is List && eventData.length >= 3) {
        final messageType = eventData[0];

        if (messageType == 'EVENT') {
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
        }
      }
    } catch (e) {}
  }

  void _flushEventQueue() {
    if (_eventQueue.isEmpty) return;

    _batchProcessingTimer?.cancel();
    _batchProcessingTimer = null;

    final batch = List<Map<String, dynamic>>.from(_eventQueue);
    _eventQueue.clear();

    _processBatchEvents(batch);
  }

  Future<void> _processBatchEvents(List<Map<String, dynamic>> batch) async {
    try {
      final profileEvents = <Map<String, dynamic>>[];
      final noteEvents = <Map<String, dynamic>>[];
      final reactionEvents = <Map<String, dynamic>>[];
      final repostEvents = <Map<String, dynamic>>[];
      final followEvents = <Map<String, dynamic>>[];
      final zapEvents = <Map<String, dynamic>>[];

      for (final eventData in batch) {
        final event = eventData['eventData'] as Map<String, dynamic>;
        final kind = event['kind'] as int;

        switch (kind) {
          case 0:
            profileEvents.add(event);
            break;
          case 1:
            noteEvents.add(event);
            break;
          case 3:
            followEvents.add(event);
            break;
          case 6:
            repostEvents.add(event);
            break;
          case 7:
            reactionEvents.add(event);
            break;
          case 9735:
            zapEvents.add(event);
            break;
        }
      }

      await Future.wait([
        _processProfileEventsBatch(profileEvents),
        _processNoteEventsBatch(noteEvents),
        _processReactionEventsBatch(reactionEvents),
        _processRepostEventsBatch(repostEvents),
        _processFollowEventsBatch(followEvents),
        _processZapEventsBatch(zapEvents),
      ]);

      if (batch.isNotEmpty) {
        _scheduleUIUpdate();
      }
    } catch (e) {
      // Handle error silently to avoid spam
    }
  }

  Future<void> _processProfileEventsBatch(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    final profileUpdates = <String, Map<String, dynamic>>{};

    for (final eventData in events) {
      try {
        final pubkey = eventData['pubkey'] as String;
        final content = eventData['content'] as String;
        final createdAt = eventData['created_at'] as int;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

        final cachedProfile = _profileCache[pubkey];
        if (cachedProfile != null && timestamp.isBefore(cachedProfile.fetchedAt)) {
          continue;
        }

        if (content.isNotEmpty) {
          Map<String, dynamic> profileData;
          try {
            profileData = jsonDecode(content) as Map<String, dynamic>;
          } catch (e) {
            profileData = {};
          }

          profileUpdates[pubkey] = {
            'data': profileData,
            'timestamp': timestamp,
            'nip05': profileData['nip05'] as String? ?? '',
          };
        }
      } catch (e) {
        continue;
      }
    }

    final futures = <Future>[];
    for (final entry in profileUpdates.entries) {
      futures.add(_verifyAndCacheProfile(
        entry.key,
        entry.value['data'],
        entry.value['timestamp'],
        entry.value['nip05'],
      ));
    }

    await Future.wait(futures);
  }

  Future<void> _processNoteEventsBatch(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    for (final eventData in events) {
      try {
        await _processKind1Event(eventData);
      } catch (e) {
        continue;
      }
    }
  }

  Future<void> _processReactionEventsBatch(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    final reactionUpdates = <String, List<ReactionModel>>{};

    for (final eventData in events) {
      try {
        final id = eventData['id'] as String;
        final pubkey = eventData['pubkey'] as String;
        final content = eventData['content'] as String;
        final createdAt = eventData['created_at'] as int;
        final tags = eventData['tags'] as List<dynamic>;

        String? targetEventId;
        for (final tag in tags) {
          if (tag is List && tag.isNotEmpty && tag[0] == 'e' && tag.length >= 2) {
            targetEventId = tag[1] as String;
            break;
          }
        }

        if (targetEventId != null && !_pendingOptimisticReactionIds.contains(id)) {
          final reaction = ReactionModel(
            id: id,
            targetEventId: targetEventId,
            content: content,
            author: _authService.hexToNpub(pubkey) ?? pubkey,
            timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
            fetchedAt: DateTime.now(),
          );

          reactionUpdates.putIfAbsent(targetEventId, () => []);
          reactionUpdates[targetEventId]!.add(reaction);
        }
      } catch (e) {
        continue;
      }
    }

    for (final entry in reactionUpdates.entries) {
      final targetEventId = entry.key;
      final reactions = entry.value;

      _reactionsMap.putIfAbsent(targetEventId, () => []);

      for (final reaction in reactions) {
        if (!_reactionsMap[targetEventId]!.any((r) => r.id == reaction.id)) {
          _reactionsMap[targetEventId]!.add(reaction);
        }
      }

      final targetNote = _noteCache[targetEventId];
      if (targetNote != null) {
        targetNote.reactionCount = _reactionsMap[targetEventId]!.length;
      }
    }
  }

  Future<void> _processRepostEventsBatch(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    for (final eventData in events) {
      try {
        await _processRepostEvent(eventData);
      } catch (e) {
        continue;
      }
    }
  }

  Future<void> _processFollowEventsBatch(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    for (final eventData in events) {
      try {
        await _processFollowEvent(eventData);
      } catch (e) {
        continue;
      }
    }
  }

  Future<void> _processZapEventsBatch(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    final zapUpdates = <String, List<ZapModel>>{};

    for (final eventData in events) {
      try {
        final id = eventData['id'] as String;
        final walletPubkey = eventData['pubkey'] as String;

        if (_processedZapIds.contains(id) || _userPublishedZapIds.contains(id)) {
          continue;
        }

        final currentUserHex = _authService.npubToHex(_currentUserNpub);
        if (currentUserHex != null && walletPubkey == currentUserHex) {
          continue;
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
            }
            if (zapRequest.containsKey('content')) {
              final requestContent = zapRequest['content'] as String;
              if (requestContent.isNotEmpty) {
                zapComment = requestContent;
              }
            }
          } catch (e) {
            // Use wallet pubkey
          }
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

          zapUpdates.putIfAbsent(targetEventId, () => []);
          zapUpdates[targetEventId]!.add(zap);
        }
      } catch (e) {
        continue;
      }
    }

    for (final entry in zapUpdates.entries) {
      final targetEventId = entry.key;
      final zaps = entry.value;

      _zapsMap.putIfAbsent(targetEventId, () => []);

      for (final zap in zaps) {
        if (!_zapsMap[targetEventId]!.any((z) => z.id == zap.id)) {
          _zapsMap[targetEventId]!.add(zap);
          _processedZapIds.add(zap.id);
        }
      }

      final targetNote = _noteCache[targetEventId];
      if (targetNote != null) {
        targetNote.zapAmount = _zapsMap[targetEventId]!.fold<int>(0, (sum, z) => sum + z.amount);
      }
    }
  }

  Future<void> _verifyAndCacheProfile(String pubkey, Map<String, dynamic> profileData, DateTime timestamp, String nip05) async {
    bool nip05Verified = false;

    if (nip05.isNotEmpty) {
      try {
        nip05Verified = await _nip05Service.verifyNip05(nip05, pubkey);
      } catch (e) {
        nip05Verified = false;
      }
    }

    final dataToCache = {
      'name': profileData['name'] as String? ?? 'Anonymous',
      'profileImage': profileData['picture'] as String? ?? '',
      'about': profileData['about'] as String? ?? '',
      'nip05': nip05,
      'banner': profileData['banner'] as String? ?? '',
      'lud16': profileData['lud16'] as String? ?? '',
      'website': profileData['website'] as String? ?? '',
      'nip05Verified': nip05Verified.toString(),
    };

    _profileCache.remove(pubkey);
    _profileCache[pubkey] = CachedProfile(dataToCache, timestamp);

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
      nip05Verified: nip05Verified,
    );

    try {
      await _userCacheService.invalidate(pubkey);
      await _userCacheService.put(user);
    } catch (e) {}

    _usersController.add(_getUsersList());
  }

  Future<void> _processKind1Event(Map<String, dynamic> eventData) async {
    try {
      final tags = List<dynamic>.from(eventData['tags'] ?? []);
      String? rootId;
      String? replyId;
      bool isReply = false;

      for (var tag in tags) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          if (tag.length >= 4 && tag[3] == 'mention') continue;

          if (tag.length >= 4) {
            if (tag[3] == 'root') {
              rootId = tag[1] as String;
              isReply = true;
            } else if (tag[3] == 'reply') {
              replyId = tag[1] as String;
              isReply = true;
            }
          } else if (rootId == null && replyId == null) {
            replyId = tag[1] as String;
            isReply = true;
          }
        }
      }

      if (isReply && replyId != null) {
        await _handleReplyEvent(eventData, replyId);
      } else if (isReply && rootId != null && replyId == null) {
        await _handleReplyEvent(eventData, rootId);
      } else {
        await _processNoteEvent(eventData);
      }
    } catch (e) {}
  }

  Future<void> _processNoteEvent(Map<String, dynamic> eventData) async {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      if (_eventIds.contains(id) || _noteCache.containsKey(id)) {
        return;
      }

      if (!_shouldIncludeNoteInFeed(pubkey, false)) {
        return;
      }

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      String? rootId;
      String? parentId;
      bool isReply = false;
      final List<Map<String, String>> eTags = [];
      final List<Map<String, String>> pTags = [];

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          final tagType = tag[0] as String;
          if (tagType == 'e' && tag.length >= 2) {
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
              isReply = true;
            } else if (marker == 'reply') {
              parentId = eventId;
              isReply = true;
            } else if (rootId == null) {
              rootId = eventId;
              isReply = true;
            }
          } else if (tagType == 'p' && tag.length >= 2) {
            final pubkeyTag = tag[1] as String;
            final relayUrl = tag.length > 2 ? (tag[2] as String? ?? '') : '';
            final petname = tag.length > 3 ? (tag[3] as String? ?? '') : '';

            pTags.add({
              'pubkey': pubkeyTag,
              'relayUrl': relayUrl,
              'petname': petname,
            });
          }
        }
      }

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
      );

      _noteCache[id] = note;
      _eventIds.add(id);

      _updateAllReplyCountsForNote(id);
      _scheduleUIUpdate();
      _fetchUserProfile(authorNpub);
    } catch (e) {}
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      if (_eventIds.contains(id) || _noteCache.containsKey(id)) {
        return;
      }

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      String? rootId;
      String? actualParentId = parentEventId;
      String? replyMarker;
      final List<Map<String, String>> eTags = [];
      final List<Map<String, String>> pTags = [];

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
        replyMarker: replyMarker,
        reactionCount: 0,
        replyCount: 0,
        repostCount: 0,
        zapAmount: 0,
      );

      _noteCache[id] = replyNote;
      _eventIds.add(id);

      _updateParentNoteReplyCount(actualParentId ?? parentEventId);
      _scheduleUIUpdate();
      _fetchUserProfile(authorNpub);
    } catch (e) {}
  }

  Future<void> _processRepostEvent(Map<String, dynamic> eventData) async {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;
      final content = eventData['content'] as String? ?? '';

      _trackRepostForCount(eventData);

      if (_eventIds.contains(id) || _noteCache.containsKey(id)) {
        return;
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

              _noteCache[originalEventId] = originalNoteFromRepost;
              _eventIds.add(originalEventId);
            }
          } catch (e) {
            displayContent = content.isNotEmpty ? content : displayContent;
          }
        }

        final repostNote = NoteModel(
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

        _noteCache[id] = repostNote;
        _eventIds.add(id);

        final targetNote = _noteCache[originalEventId];
        if (targetNote != null) {
          targetNote.repostCount = _repostsMap[originalEventId]?.length ?? 0;
        }

        _scheduleUIUpdate();
        _fetchUserProfile(reposterNpub);
      }
    } catch (e) {}
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
          }
        }
      }
    } catch (e) {}
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

        final currentUserHex = _authService.npubToHex(_currentUserNpub) ?? _currentUserNpub;
        if (pubkey == currentUserHex) {
          _cachedFollowingList = newFollowing;
          _isFollowingListReady = true;
        }
      } catch (e) {
        // Handle silently
      }
    } catch (e) {
      // Handle silently
    }
  }

  void markZapAsUserPublished(String zapEventId) {
    _userPublishedZapIds.add(zapEventId);
  }

  void _handleRelayDisconnection(String relayUrl) {}

  void _startCacheCleanup() {
    Timer.periodic(const Duration(hours: 6), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }

      final now = timeService.now;
      final cutoffTime = now.subtract(_profileCacheTTL);
      _profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));

      if (_lastInteractionFetch.length > 1000) {
        final interactionCutoff = now.subtract(const Duration(hours: 1));
        _lastInteractionFetch.removeWhere((key, timestamp) => timestamp.isBefore(interactionCutoff));
      }
    });
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
      final result = bTime.compareTo(aTime);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });

    return notesList;
  }

  void _scheduleUIUpdate() {
    if (!_uiUpdatePending) _uiUpdatePending = true;

    _uiUpdateThrottleTimer?.cancel();
    _uiUpdateThrottleTimer = Timer(_uiUpdateThrottle, () {
      if (_isClosed || !_uiUpdatePending) return;

      final notesList = _getFilteredNotesList();
      _notesController.add(notesList);

      _uiUpdatePending = false;
    });
  }

  List<NoteModel> _getFilteredNotesList() {
    final allNotes = _noteCache.values.toList();

    final filteredNotes = allNotes.where((note) {
      if (!note.isReply) {
        return true;
      }

      if (note.isReply && note.isRepost) {
        return true;
      }

      return false;
    }).toList();

    filteredNotes.sort((a, b) {
      final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      final result = bTime.compareTo(aTime);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });

    return filteredNotes;
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
    } catch (e) {}
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
      bool isFeedMode = false;

      if (authorHexKeys.isEmpty) {
        setContext('global');
        targetAuthors = [];
      } else if (authorHexKeys.length == 1 && authorHexKeys.first == _authService.npubToHex(_currentUserNpub)) {
        setContext('feed');
        isFeedMode = true;

        final currentUserHex = _authService.npubToHex(_currentUserNpub);
        if (currentUserHex == null) {
          return const Result.error('Invalid current user npub format');
        }

        final cachedFollowing = _followCacheService.getSync(currentUserHex);
        List<String>? followingList;

        if (cachedFollowing != null) {
          followingList = cachedFollowing;
        } else {
          final followingResult = await getFollowingList(_currentUserNpub);
          if (followingResult.isSuccess && followingResult.data != null) {
            followingList = followingResult.data!;
            await _followCacheService.put(currentUserHex, followingList);
          }
        }

        if (followingList != null && followingList.isNotEmpty) {
          targetAuthors = List<String>.from(followingList);
          targetAuthors.add(currentUserHex);
        } else {
          return Result.success([]);
        }
      } else {
        setContext('profile');
        targetAuthors = authorHexKeys;
      }

      final filter = NostrService.createNotesFilter(
        authors: targetAuthors.isEmpty ? null : targetAuthors,
        kinds: [1, 6],
        limit: limit,
        since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
        until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
      );

      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));

      await Future.delayed(const Duration(milliseconds: 1500));

      final cachedNotes = _getNotesList();

      List<NoteModel> notesToReturn;
      if (isFeedMode && targetAuthors.isNotEmpty) {
        notesToReturn = _filterNotesByFollowList(cachedNotes, targetAuthors).take(limit).toList();
      } else {
        notesToReturn = cachedNotes.take(limit).toList();
      }

      return Result.success(notesToReturn);
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
      setContext('profile');

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

      final profileNotes = <NoteModel>[];
      final allRelays = _relayManager.relayUrls.toList();

      await Future.wait(allRelays.map((relayUrl) async {
        WebSocket? ws;
        StreamSubscription? sub;
        try {
          ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
          if (_isClosed) {
            await ws.close();
            return;
          }

          final completer = Completer<void>();

          sub = ws.listen((event) {
            try {
              final decoded = jsonDecode(event);

              if (decoded[0] == 'EVENT') {
                final eventData = decoded[2] as Map<String, dynamic>;
                final eventId = eventData['id'] as String;
                final eventAuthor = eventData['pubkey'] as String;
                final eventKind = eventData['kind'] as int;

                if (eventAuthor == pubkeyHex && (eventKind == 1 || eventKind == 6)) {
                  if (!profileNotes.any((n) => n.id == eventId)) {
                    final note = _processProfileEventDirectly(eventData, userNpub);
                    if (note != null) {
                      profileNotes.add(note);

                      if (!_noteCache.containsKey(eventId) && !_eventIds.contains(eventId)) {
                        _noteCache[eventId] = note;
                        _eventIds.add(eventId);
                      }
                    }
                  }
                }
              } else if (decoded[0] == 'EOSE') {
                if (!completer.isCompleted) completer.complete();
              }
            } catch (e) {}
          }, onDone: () {
            if (!completer.isCompleted) completer.complete();
          }, onError: (error) {
            if (!completer.isCompleted) completer.complete();
          }, cancelOnError: true);

          if (ws.readyState == WebSocket.open) {
            ws.add(NostrService.serializeRequest(NostrService.createRequest(filter)));
          }

          await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {});

          await sub.cancel();
          await ws.close();
        } catch (e) {
          await sub?.cancel();
          await ws?.close();
        }
      }));

      profileNotes.sort((a, b) {
        final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
        final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
        return bTime.compareTo(aTime);
      });

      final limitedNotes = profileNotes.take(limit).toList();

      debugPrint('[NostrDataService] PROFILE: Returning ${limitedNotes.length} profile notes for $userNpub');
      debugPrint(
          '[NostrDataService] PROFILE: Breakdown - Posts: ${limitedNotes.where((n) => !n.isReply && !n.isRepost).length}, Replies: ${limitedNotes.where((n) => n.isReply && !n.isRepost).length}, Reposts: ${limitedNotes.where((n) => n.isRepost).length}');
      debugPrint('[NostrDataService] PROFILE: Main cache now has ${_noteCache.length} total notes for thread access');

      _scheduleUIUpdate();

      return Result.success(limitedNotes);
    } catch (e) {
      debugPrint('[NostrDataService] PROFILE: Error fetching profile notes: $e');
      return Result.error('Failed to fetch profile notes: $e');
    }
  }

  NoteModel? _processProfileEventDirectly(Map<String, dynamic> eventData, String userNpub) {
    try {
      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final kind = eventData['kind'] as int;

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      if (kind == 1) {
        return _processKind1ForProfile(eventData, authorNpub, timestamp);
      } else if (kind == 6) {
        return _processKind6ForProfile(eventData, authorNpub, timestamp);
      }

      return null;
    } catch (e) {
      debugPrint('[NostrDataService] PROFILE: Error processing event: $e');
      return null;
    }
  }

  NoteModel? _processKind1ForProfile(Map<String, dynamic> eventData, String authorNpub, DateTime timestamp) {
    try {
      final id = eventData['id'] as String;
      final content = eventData['content'] as String;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      String? rootId;
      String? parentId;
      bool isReply = false;
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
              isReply = true;
            } else if (marker == 'reply') {
              parentId = eventId;
              isReply = true;
            } else if (rootId == null) {
              rootId = eventId;
              isReply = true;
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

      return NoteModel(
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
    } catch (e) {
      debugPrint('[NostrDataService] PROFILE: Error processing kind 1: $e');
      return null;
    }
  }

  NoteModel? _processKind6ForProfile(Map<String, dynamic> eventData, String reposterNpub, DateTime timestamp) {
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
      bool detectedIsReply = false;
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
              } else {
                if (detectedParentId == null) {
                  detectedParentId = eventId;
                  detectedRootId = eventId;
                  detectedIsReply = true;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[NostrDataService] PROFILE: Failed to parse repost content: $e');
        }
      }

      return NoteModel(
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
    } catch (e) {
      debugPrint('[NostrDataService] PROFILE: Error processing kind 6: $e');
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
      setContext('hashtag');

      final filterMap = {
        'kinds': [1],
        '#t': [hashtag.toLowerCase()],
        'limit': limit,
      };

      if (since != null) {
        filterMap['since'] = since.millisecondsSinceEpoch ~/ 1000;
      }
      if (until != null) {
        filterMap['until'] = until.millisecondsSinceEpoch ~/ 1000;
      }

      final subscriptionId = NostrService.generateUUID();
      final request = jsonEncode(['REQ', subscriptionId, filterMap]);
      await _relayManager.broadcast(request);

      await Future.delayed(const Duration(milliseconds: 2000));

      final hashtagNotes = _noteCache.values.where((note) {
        return note.content.toLowerCase().contains('#${hashtag.toLowerCase()}');
      }).toList();

      hashtagNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final limitedNotes = hashtagNotes.take(limit).toList();

      return Result.success(limitedNotes);
    } catch (e) {
      return Result.error('Failed to fetch hashtag notes: $e');
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

      await _fetchUserProfile(npub);

      await Future.delayed(const Duration(milliseconds: 500));

      final updatedProfile = _profileCache[pubkeyHex];
      if (updatedProfile != null) {
        final user = UserModel.fromCachedProfile(pubkeyHex, updatedProfile.data);
        return Result.success(user);
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

      try {
        if (_relayManager.activeSockets.isEmpty) {
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'note_post',
          );
        }
      } catch (e) {}

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

      _noteCache[note.id] = note;
      _eventIds.add(note.id);
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
          } catch (e) {}
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

      _noteCache[reply.id] = reply;
      _eventIds.add(reply.id);
      _scheduleUIUpdate();
      return Result.success(reply);
    } catch (e) {
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

      await Future.delayed(const Duration(seconds: 3));

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
        limit: 1000,
      );

      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);

      final following = <String>[];
      final allRelays = _relayManager.relayUrls.toList();

      await Future.wait(allRelays.map((relayUrl) async {
        WebSocket? ws;
        StreamSubscription? sub;
        try {
          ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 2));
          if (_isClosed) {
            await ws.close();
            return;
          }

          final completer = Completer<void>();

          sub = ws.listen((event) {
            try {
              final decoded = jsonDecode(event);

              if (decoded[0] == 'EVENT') {
                final eventData = decoded[2] as Map<String, dynamic>;
                final eventAuthor = eventData['pubkey'] as String;
                final eventKind = eventData['kind'] as int;
                final tags = eventData['tags'] as List<dynamic>;

                if (eventAuthor == pubkeyHex && eventKind == 3) {
                  for (var tag in tags) {
                    if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
                      final followedHexPubkey = tag[1] as String;
                      if (!following.contains(followedHexPubkey)) {
                        following.add(followedHexPubkey);
                      }
                    }
                  }
                }
              } else if (decoded[0] == 'EOSE') {
                if (!completer.isCompleted) completer.complete();
              }
            } catch (e) {}
          }, onDone: () {
            if (!completer.isCompleted) completer.complete();
          }, onError: (error) {
            if (!completer.isCompleted) completer.complete();
          }, cancelOnError: true);

          if (ws.readyState == WebSocket.open) {
            ws.add(serializedRequest);
          }

          await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});

          await sub.cancel();
          await ws.close();
        } catch (e) {
          await sub?.cancel();
          await ws?.close();
        }
      }));

      final uniqueFollowing = following.toSet().toList();
      return Result.success(uniqueFollowing);
    } catch (e) {
      return Result.error('Failed to get following list: $e');
    }
  }

  Future<bool> fetchSpecificNote(String noteId) async {
    try {
      debugPrint('[NostrDataService] THREAD: Fetching specific note: $noteId');

      if (_noteCache.containsKey(noteId)) {
        debugPrint('[NostrDataService] THREAD: Note already in cache: $noteId');
        return true;
      }

      final allRelays = _relayManager.relayUrls.toList();
      bool noteFound = false;

      debugPrint('[NostrDataService] THREAD: Using ${allRelays.length} relays for direct fetch');

      await Future.wait(allRelays.map((relayUrl) async {
        WebSocket? ws;
        StreamSubscription? sub;
        try {
          debugPrint('[NostrDataService] THREAD: Connecting to $relayUrl');
          ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
          if (_isClosed) {
            await ws.close();
            return;
          }

          final completer = Completer<void>();
          bool hasReceivedEvents = false;

          final filter = NostrService.createEventByIdFilter(eventIds: [noteId]);
          final request = NostrService.createRequest(filter);

          sub = ws.listen((event) {
            try {
              final decoded = jsonDecode(event);

              if (decoded[0] == 'EVENT') {
                hasReceivedEvents = true;
                final eventData = decoded[2] as Map<String, dynamic>;
                final eventId = eventData['id'] as String;

                debugPrint('[NostrDataService] THREAD: Received event $eventId from $relayUrl');

                if (eventId == noteId) {
                  final kind = eventData['kind'] as int;
                  if (kind == 1 || kind == 6) {
                    final pubkeyHex = eventData['pubkey'] as String;
                    final userNpub = _authService.hexToNpub(pubkeyHex) ?? pubkeyHex;
                    final note = _processProfileEventDirectly(eventData, userNpub);
                    if (note != null) {
                      _noteCache[eventId] = note;
                      _eventIds.add(eventId);
                      noteFound = true;
                      debugPrint('[NostrDataService] THREAD: Successfully cached note $eventId');
                    }
                  }
                }
              } else if (decoded[0] == 'EOSE') {
                debugPrint('[NostrDataService] THREAD: EOSE received from $relayUrl');
                if (!completer.isCompleted) completer.complete();
              }
            } catch (e) {
              debugPrint('[NostrDataService] THREAD: Error processing event: $e');
            }
          }, onDone: () {
            if (!completer.isCompleted) completer.complete();
          }, onError: (error) {
            debugPrint('[NostrDataService] THREAD: Connection error: $error');
            if (!completer.isCompleted) completer.complete();
          }, cancelOnError: true);

          if (ws.readyState == WebSocket.open) {
            ws.add(NostrService.serializeRequest(request));
          }

          await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
            debugPrint('[NostrDataService] THREAD: Timeout waiting for note from $relayUrl');
          });

          await sub.cancel();
          await ws.close();

          debugPrint('[NostrDataService] THREAD: Finished $relayUrl, received ${hasReceivedEvents ? 'events' : 'no events'}');
        } catch (e) {
          debugPrint('[NostrDataService] THREAD: Exception with relay $relayUrl: $e');
          await sub?.cancel();
          await ws?.close();
        }
      }));

      if (noteFound || _noteCache.containsKey(noteId)) {
        debugPrint('[NostrDataService] THREAD: Note successfully fetched: $noteId');
        return true;
      } else {
        debugPrint('[NostrDataService] THREAD: Note not found after fetch: $noteId');
        return false;
      }
    } catch (e) {
      debugPrint('[NostrDataService] THREAD: Error fetching specific note: $e');
      return false;
    }
  }

  Future<void> fetchSpecificNotes(List<String> noteIds) async {
    try {
      if (noteIds.isEmpty) return;

      debugPrint('[NostrDataService] Fetching ${noteIds.length} specific notes...');

      final notesToFetch = noteIds.where((id) => !_noteCache.containsKey(id)).toList();

      if (notesToFetch.isEmpty) {
        debugPrint('[NostrDataService] All notes already in cache');
        return;
      }

      debugPrint('[NostrDataService]  Need to fetch ${notesToFetch.length} notes');

      final filter = NostrService.createEventByIdFilter(eventIds: notesToFetch);
      final request = NostrService.createRequest(filter);

      await _relayManager.broadcast(NostrService.serializeRequest(request));

      debugPrint('[NostrDataService] Batch note request sent for ${notesToFetch.length} notes');
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching specific notes: $e');
    }
  }

  List<NoteModel> get cachedNotes => _getNotesList();

  List<UserModel> get cachedUsers => _getUsersList();

  Future<void> _fetchInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    debugPrint('[NostrDataService] Fetching interactions for ${noteIds.length} notes...');

    try {
      const batchSize = 12;

      for (int i = 0; i < noteIds.length; i += batchSize) {
        final batch = noteIds.skip(i).take(batchSize).toList();

        await Future.wait([
          _fetchReactionsForBatch(batch),
          _fetchRepliesForBatch(batch),
          _fetchRepostsForBatch(batch),
          _fetchZapsForBatch(batch),
        ], eagerError: false);

        if (i + batchSize < noteIds.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      debugPrint('[NostrDataService] Interaction fetching completed for ${noteIds.length} notes');
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching interactions: $e');
    }
  }

  Future<void> _fetchReactionsForBatch(List<String> noteIds) async {
    try {
      final filter = NostrService.createReactionFilter(
        eventIds: noteIds,
        limit: 500,
      );
      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));
    } catch (e) {
      debugPrint('[NostrDataService] Failed to fetch reactions: $e');
    }
  }

  Future<void> _fetchRepliesForBatch(List<String> noteIds) async {
    try {
      final filter = NostrService.createReplyFilter(
        eventIds: noteIds,
        limit: 500,
      );
      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));
    } catch (e) {
      debugPrint('[NostrDataService] Failed to fetch replies: $e');
    }
  }

  Future<void> _fetchRepostsForBatch(List<String> noteIds) async {
    try {
      final filter = NostrService.createRepostFilter(
        eventIds: noteIds,
        limit: 500,
      );
      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));
    } catch (e) {
      debugPrint('[NostrDataService] Failed to fetch reposts: $e');
    }
  }

  Future<void> _fetchZapsForBatch(List<String> noteIds) async {
    try {
      final filter = NostrService.createZapFilter(
        eventIds: noteIds,
        limit: 500,
      );
      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));
    } catch (e) {
      debugPrint('[NostrDataService] Failed to fetch zaps: $e');
    }
  }

  Future<void> fetchInteractionsForNotes(List<String> noteIds, {bool forceLoad = false}) async {
    if (_isClosed || noteIds.isEmpty) return;

    debugPrint('[NostrDataService] ${forceLoad ? 'Manual' : 'Automatic'} interaction fetching for ${noteIds.length} notes');

    final now = DateTime.now();
    final noteIdsToFetch = <String>[];

    for (final eventId in noteIds) {
      final lastFetch = _lastInteractionFetch[eventId];
      if (lastFetch != null && now.difference(lastFetch) < _interactionFetchCooldown) {
        continue;
      }

      noteIdsToFetch.add(eventId);
      _lastInteractionFetch[eventId] = now;
    }

    if (noteIdsToFetch.isNotEmpty) {
      await _fetchInteractionsForNotes(noteIdsToFetch);

      for (final eventId in noteIdsToFetch) {
        final note = _noteCache[eventId];
        if (note != null) {
          note.reactionCount = _reactionsMap[eventId]?.length ?? 0;
          note.replyCount = 0;
          note.repostCount = _repostsMap[eventId]?.length ?? 0;
          note.zapAmount = _zapsMap[eventId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
        }
      }

      _scheduleUIUpdate();

      for (final eventId in noteIdsToFetch) {
        _updateNoteReplyCount(eventId);
      }

      debugPrint('[NostrDataService] Manual interaction fetching completed for ${noteIdsToFetch.length} notes');
    }

    if (_lastInteractionFetch.length > 1000) {
      final cutoffTime = now.subtract(const Duration(hours: 1));
      _lastInteractionFetch.removeWhere((key, timestamp) => timestamp.isBefore(cutoffTime));
    }
  }

  void _updateParentNoteReplyCount(String parentNoteId) {
    try {
      final parentNote = _noteCache[parentNoteId];
      if (parentNote != null) {
        final replyCount =
            _noteCache.values.where((note) => note.isReply && (note.parentId == parentNoteId || note.rootId == parentNoteId)).length;

        parentNote.replyCount = replyCount;
        debugPrint('[NostrDataService] Updated reply count for note $parentNoteId: $replyCount');
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
          debugPrint('[NostrDataService] Updated reply count for note $noteId: $replyCount');

          _scheduleUIUpdate();
        }
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error updating note reply count: $e');
    }
  }

  void _updateAllReplyCountsForNote(String noteId) {
    try {
      _updateNoteReplyCount(noteId);

      final note = _noteCache[noteId];
      if (note != null && note.isReply) {
        if (note.parentId != null) {
          _updateNoteReplyCount(note.parentId!);
        }
        if (note.rootId != null && note.rootId != note.parentId) {
          _updateNoteReplyCount(note.rootId!);
        }
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error updating all reply counts: $e');
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
      final sha256Hash = sha256.convert(fileBytes).toString();

      debugPrint('[NostrDataService] File read: ${fileBytes.length} bytes, SHA256: $sha256Hash');

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

      final expiration = timeService.add(Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;

      final authEvent = NostrService.createBlossomAuthEvent(
        content: 'Upload ${file.uri.pathSegments.last}',
        sha256Hash: sha256Hash,
        expiration: expiration,
        privateKey: privateKey,
      );

      final encodedAuth = base64.encode(utf8.encode(jsonEncode(NostrService.eventToJson(authEvent))));
      final authHeader = 'Nostr $encodedAuth';

      debugPrint('[NostrDataService] Blossom auth created, expiration: $expiration');

      final cleanedUrl = blossomUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$cleanedUrl/upload');

      debugPrint('[NostrDataService] Uploading to: $uri');

      final httpClient = HttpClient();
      final request = await httpClient.putUrl(uri);

      request.headers.set(HttpHeaders.authorizationHeader, authHeader);
      request.headers.set(HttpHeaders.contentTypeHeader, mimeType);
      request.headers.set(HttpHeaders.contentLengthHeader, fileBytes.length);

      request.add(fileBytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      debugPrint('[NostrDataService] Upload response: ${response.statusCode}');

      if (response.statusCode != 200) {
        return Result.error('Upload failed with status ${response.statusCode}: $responseBody');
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded.containsKey('url')) {
        final mediaUrl = decoded['url'] as String;
        debugPrint('[NostrDataService] Media uploaded successfully: $mediaUrl');
        return Result.success(mediaUrl);
      }

      return const Result.error('Upload succeeded but response does not contain a valid URL.');
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
      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user not found');
      }

      final currentUserNpub = currentUserResult.data!;

      try {
        if (_relayManager.activeSockets.isEmpty) {
          await _relayManager.connectRelays(
            [],
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'follow_event',
          );
        }
      } catch (e) {
        // Continue anyway
      }

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
            // Continue to next socket
          }
        }
      }

      try {
        final currentUserHex = _authService.npubToHex(currentUserNpub) ?? currentUserNpub;
        await _followCacheService.put(currentUserHex, followingHexList);

        _cachedFollowingList = followingHexList;
        _isFollowingListReady = true;
      } catch (e) {
        // Handle silently
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to publish follow event: $e');
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

  List<NoteModel> _filterNotesByFollowList(List<NoteModel> notes, List<String> followedHexPubkeys) {
    debugPrint('[NostrDataService] Filtering ${notes.length} notes by follow list with ${followedHexPubkeys.length} followed users');

    final filteredNotes = notes.where((note) {
      if (note.isRepost && note.repostedBy != null) {
        final reposterHex = _authService.npubToHex(note.repostedBy!) ?? note.repostedBy!;
        final isReposterFollowed = followedHexPubkeys.contains(reposterHex);

        debugPrint(
            '[NostrDataService] Repost${note.isReply ? " (reply)" : ""} by ${note.repostedBy} (hex: $reposterHex), followed: $isReposterFollowed');
        return isReposterFollowed;
      }

      if (note.isReply) {
        debugPrint('[NostrDataService] Excluding standalone reply: ${note.id}');
        return false;
      }

      final noteAuthorHex = _authService.npubToHex(note.author) ?? note.author;
      final isAuthorFollowed = followedHexPubkeys.contains(noteAuthorHex);

      debugPrint('[NostrDataService] Original post by ${note.author} (hex: $noteAuthorHex), followed: $isAuthorFollowed');
      return isAuthorFollowed;
    }).toList();

    debugPrint('[NostrDataService] Filtered result: ${filteredNotes.length} notes (${notes.length - filteredNotes.length} excluded)');
    return filteredNotes;
  }

  void dispose() {
    _isClosed = true;
    _batchProcessingTimer?.cancel();
    _uiUpdateThrottleTimer?.cancel();
    _relayManager.unregisterService('nostr_data_service');
    _notesController.close();
    _usersController.close();
    _notificationsController.close();
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
