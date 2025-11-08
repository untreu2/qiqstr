import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

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
import '../../constants/relays.dart';
import 'auth_service.dart';
import 'user_cache_service.dart';
import 'follow_cache_service.dart';

class NostrDataService {
  final AuthService _authService;
  final WebSocketManager _relayManager;
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
  static const int _maxBatchSize = 25;
  static const Duration _batchTimeout = Duration(milliseconds: 100);

  bool _isClosed = false;
  String _currentUserNpub = '';

  Timer? _uiUpdateThrottleTimer;
  bool _uiUpdatePending = false;
  static const Duration _uiUpdateThrottle = Duration(milliseconds: 200);

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
        debugPrint('[NostrDataService] Initializing follow list cache for: $_currentUserNpub');

        final currentUserHex = _authService.npubToHex(_currentUserNpub) ?? _currentUserNpub;
        await _followCacheService.getOrFetch(currentUserHex, () async {
          final result = await getFollowingList(_currentUserNpub);
          return result.isSuccess ? result.data : null;
        });
        debugPrint('[NostrDataService] Follow list cache initialized via FollowCacheService');
      }

      _fetchInitialGlobalContent();
    } catch (e) {
      debugPrint('[NostrDataService]  Error initializing follow list cache: $e');
      _fetchInitialGlobalContent();
    }
  }

  Future<void> _fetchInitialGlobalContent() async {
    try {
      debugPrint('[NostrDataService] Fetching initial global content...');

      final filter = NostrService.createNotesFilter(
        authors: null,
        kinds: [1],
        limit: 30,
        since: (DateTime.now().subtract(const Duration(hours: 24))).millisecondsSinceEpoch ~/ 1000,
      );

      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));

      debugPrint('[NostrDataService] Initial content request sent to relays');
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching initial content: $e');
    }
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

    for (final eventData in batch) {
      _processNostrEvent(eventData['eventData'] as Map<String, dynamic>).catchError((e) {
        debugPrint('[NostrDataService] Error in batch event processing: $e');
      });
    }
  }

  Future<void> _processNostrEvent(Map<String, dynamic> eventData) async {
    try {
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
        case 6:
          await _processRepostEvent(eventData);
          break;
        case 7:
          _processReactionEvent(eventData);
          break;
        case 9735:
          _processZapEvent(eventData);
          break;
      }
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
      debugPrint('[NostrDataService]  Profile cached to 2-tier storage: ${user.name} (image: ${user.profileImage.isNotEmpty ? "✓" : "✗"})');
    } catch (e) {
      debugPrint('[NostrDataService] ️ Error caching profile to 2-tier storage: $e');
    }

    _usersController.add(_getUsersList());
    debugPrint('[NostrDataService] Profile updated and cache invalidated: ${user.name}');
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
    } catch (e) {
      debugPrint('[NostrDataService] Error processing kind 1 event: $e');
    }
  }

  Future<void> _processNoteEvent(Map<String, dynamic> eventData) async {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      if (_eventIds.contains(id) || _noteCache.containsKey(id)) {
        debugPrint(' [NostrDataService] Duplicate note detected, skipping: $id');
        return;
      }

      if (!_shouldIncludeNoteInFeed(pubkey, false)) {
        debugPrint(' [NostrDataService] Note filtered out - author not in follow list: $pubkey');
        return;
      }

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      _ensureProfileExists(pubkey, authorNpub);

      debugPrint('[NostrDataService] Processing note from followed author: $authorNpub');

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

      debugPrint('Note added to cache. Total cached notes: ${_noteCache.length}');

      _fetchInteractionCountsForNotesImmediately([id]);

      debugPrint('[NostrDataService] Note processed and interaction counts requested: $id');

      if (isReply && parentId != null) {
        final parentNote = _noteCache[parentId];
        if (parentNote != null) {
          parentNote.addReply(note);
        }
      }
      
      if (isReply && rootId != null && rootId != parentId) {
        final rootNote = _noteCache[rootId];
        if (rootNote != null) {
          rootNote.addReply(note);
        }
      }

      _updateAllReplyCountsForNote(id);

      _scheduleUIUpdate();

      debugPrint('[NostrDataService] New note processed: ${note.content.substring(0, 30)}...');
    } catch (e) {
      debugPrint('[NostrDataService] Error processing note event: $e');
    }
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      if (_eventIds.contains(id) || _noteCache.containsKey(id)) {
        debugPrint(' [NostrDataService] Duplicate reply detected, skipping: $id');
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

      _ensureProfileExists(pubkey, authorNpub);

      _updateParentNoteReplyCount(actualParentId ?? parentEventId);

      _fetchInteractionCountsForNotesImmediately([id]);

      debugPrint('[NostrDataService] Reply processed and interaction counts requested: $id');

      _scheduleUIUpdate();

      debugPrint('[NostrDataService] Reply processed: ${content.substring(0, 30)}...');
    } catch (e) {
      debugPrint('[NostrDataService] Error processing reply event: $e');
    }
  }

  void _processReactionEvent(Map<String, dynamic> eventData) {
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

      if (targetEventId != null) {
        if (_pendingOptimisticReactionIds.contains(id)) {
          _pendingOptimisticReactionIds.remove(id);
          return;
        }

        final reaction = ReactionModel(
          id: id,
          targetEventId: targetEventId,
          content: content,
          author: _authService.hexToNpub(pubkey) ?? pubkey,
          timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
          fetchedAt: DateTime.now(),
        );

        final targetNote = _noteCache[targetEventId];
        if (targetNote != null) {
          targetNote.addReaction(reaction);
          _scheduleUIUpdate();
        }
        
        _reactionsMap.putIfAbsent(targetEventId, () => []);
        if (!_reactionsMap[targetEventId]!.any((r) => r.id == reaction.id)) {
          _reactionsMap[targetEventId]!.add(reaction);
        }

        _ensureProfileExists(pubkey, reaction.author);
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing reaction event: $e');
    }
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
        debugPrint(' [NostrDataService] Duplicate repost detected, skipping: $id');
        return;
      }

      if (!_shouldIncludeNoteInFeed(pubkey, true)) {
        debugPrint(' [NostrDataService] Repost filtered out - reposter not in follow list: $pubkey');
        return;
      }

      debugPrint('[NostrDataService] Processing repost from followed user: $pubkey');

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

        _fetchInteractionCountsForNotesImmediately([originalEventId]);

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
        debugPrint('[NostrDataService]  Updated follow cache for $pubkey: ${newFollowing.length} following');
      } catch (e) {
        debugPrint('[NostrDataService] Error updating follow cache: $e');
      }

      debugPrint('[NostrDataService] Follow event processed: ${newFollowing.length} following');
    } catch (e) {
      debugPrint('[NostrDataService] Error processing follow event: $e');
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
        
        _zapsMap.putIfAbsent(targetEventId, () => []);
        if (!_zapsMap[targetEventId]!.any((z) => z.id == zap.id)) {
          _zapsMap[targetEventId]!.add(zap);
          _processedZapIds.add(id);
          final senderHex = _authService.npubToHex(zap.sender) ?? zap.sender;
          _ensureProfileExists(senderHex, zap.sender);
          debugPrint('[NostrDataService] Zap processed: ${zap.amount} sats from ${zap.sender} to ${zap.recipient}');
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

    debugPrint('[NostrDataService]  Processing potential notification: kind $kind from $eventAuthor');
    debugPrint('[NostrDataService]  Looking for mentions of user hex: $currentUserHex');

    for (var tag in eventTags) {
      if (tag is List && tag.length >= 2 && tag[0] == 'p') {
        final mentionedUserHex = tag[1] as String;
        debugPrint('[NostrDataService]  Found p tag mentioning: $mentionedUserHex');

        if (mentionedUserHex == currentUserHex) {
          isUserMentioned = true;
          debugPrint('[NostrDataService] User mentioned! Creating notification');
          break;
        }
      }
    }

    if (!isUserMentioned) {
      debugPrint('[NostrDataService]  User not mentioned in this event');
      return;
    }

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

      _notificationCache.putIfAbsent(_currentUserNpub, () => []);
      if (!_notificationCache[_currentUserNpub]!.any((n) => n.id == updatedNotification.id)) {
        _notificationCache[_currentUserNpub]!.add(updatedNotification);
        _notificationCache[_currentUserNpub]!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _notificationsController.add(_notificationCache[_currentUserNpub]!);

        debugPrint('[NostrDataService]  Notification added: $notificationType from ${updatedNotification.author}');
        debugPrint('[NostrDataService]  Total notifications: ${_notificationCache[_currentUserNpub]!.length}');
      } else {
        debugPrint('[NostrDataService]  Duplicate notification ignored: ${updatedNotification.id}');
      }
    } catch (e) {
      debugPrint('[NostrDataService]  Error creating notification: $e');
    }
  }

  void _handleRelayDisconnection(String relayUrl) {
    debugPrint('[NostrDataService] Relay disconnected: $relayUrl');
  }

  void _startCacheCleanup() {
  }

  void _cleanupCacheIfNeeded() {
    if (_profileCache.length > 500) {
      final now = timeService.now;
      final cutoffTime = now.subtract(_profileCacheTTL);
      _profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));
    }

    if (_lastInteractionFetch.length > 1000) {
      final now = timeService.now;
      final interactionCutoff = now.subtract(const Duration(hours: 1));
      _lastInteractionFetch.removeWhere((key, timestamp) => timestamp.isBefore(interactionCutoff));
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
      final result = bTime.compareTo(aTime);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });

    debugPrint('[NostrDataService]  Returning ${notesList.length} sorted notes');
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
      debugPrint(' [NostrDataService] UI updated with ${notesList.length} notes (filtered)');
    });
  }

  List<NoteModel> _getFilteredNotesList() {
    final allNotes = _noteCache.values.toList();

    final filteredNotes = allNotes.where((note) {
      if (!note.isReply) return true;
      if (note.isReply && note.isRepost) return true;
      return false;
    }).toList();

    filteredNotes.sort((a, b) {
      final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      final result = bTime.compareTo(aTime);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });

    debugPrint('[NostrDataService] FILTERING RESULT: ${allNotes.length} → ${filteredNotes.length} notes');

    return filteredNotes;
  }

  void _ensureProfileExists(String pubkeyHex, String npub) {
    try {
      if (_profileCache.containsKey(pubkeyHex)) {
        _fetchUserProfile(npub);
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

      final user = UserModel.fromCachedProfile(pubkeyHex, _profileCache[pubkeyHex]!.data);
      _usersController.add([user]);

      _fetchUserProfile(npub);
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
      bool isFeedMode = false;

      if (authorHexKeys.isEmpty) {
        debugPrint('[NostrDataService] Fetching global timeline');
        targetAuthors = [];
      } else if (authorHexKeys.length == 1 && authorHexKeys.first == _authService.npubToHex(_currentUserNpub)) {
        debugPrint('[NostrDataService] Feed mode - fetching follow list first (NIP-02)');
        isFeedMode = true;

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

      final filter = NostrService.createNotesFilter(
        authors: targetAuthors.isEmpty ? null : targetAuthors,
        kinds: [1, 6],
        limit: limit,
        since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
        until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
      );

      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));

      final cachedNotes = _getNotesList();
      if (cachedNotes.isEmpty) {
        debugPrint('[NostrDataService] Cache empty, waiting for relay responses...');

        final completer = Completer<List<NoteModel>>();
        late StreamSubscription subscription;

        subscription = _notesController.stream.listen((notes) {
          if (notes.isNotEmpty && !completer.isCompleted) {
            debugPrint('[NostrDataService] Received ${notes.length} notes from relays');
            completer.complete(notes);
          }
        });

        Timer(const Duration(seconds: 3), () {
          if (!completer.isCompleted) {
            debugPrint('[NostrDataService] Timeout waiting for relay responses');
            completer.complete([]);
          }
        });

        try {
          final notes = await completer.future;
          await subscription.cancel();
          return Result.success(notes.take(limit).toList());
        } catch (e) {
          await subscription.cancel();
          return Result.success([]);
        }
      }

      debugPrint('[NostrDataService] Returning ${cachedNotes.length} cached notes');

      List<NoteModel> notesToReturn;
      if (isFeedMode && targetAuthors.isNotEmpty) {
        notesToReturn = _filterNotesByFollowList(cachedNotes, targetAuthors).take(limit).toList();
        debugPrint('[NostrDataService] Feed mode: Filtered to ${notesToReturn.length} notes from followed authors');
      } else {
        notesToReturn = cachedNotes.take(limit).toList();
        debugPrint('[NostrDataService] Non-feed mode: Returning ${notesToReturn.length} notes without follow filtering');
      }

      debugPrint('[NostrDataService] Returning ${notesToReturn.length} feed notes without automatic interaction fetch');

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
      debugPrint('[NostrDataService] PROFILE MODE: Fetching fresh notes for $userNpub');

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

      final fetchedNotes = <String, NoteModel>{};
      final limitedRelays = _relayManager.relayUrls.take(5).toList();

      debugPrint('[NostrDataService] PROFILE: Fetching from ${limitedRelays.length} relays');

      await Future.wait(limitedRelays.map((relayUrl) async {
        WebSocket? ws;
        StreamSubscription? sub;
        try {
          debugPrint('[NostrDataService] PROFILE: Connecting to relay: $relayUrl');
          ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
          if (_isClosed) {
            await ws.close();
            return;
          }

          final completer = Completer<void>();
          final request = NostrService.createRequest(filter);
          final subscriptionId = request.subscriptionId;
          int eventCount = 0;

          sub = ws.listen((event) {
            try {
              final decoded = jsonDecode(event);

              if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
                final eventData = decoded[2] as Map<String, dynamic>;
                final eventId = eventData['id'] as String;
                final eventAuthor = eventData['pubkey'] as String;
                final eventKind = eventData['kind'] as int;

                if (eventAuthor == pubkeyHex && (eventKind == 1 || eventKind == 6)) {
                  final note = _processProfileEventDirectly(eventData, userNpub);
                  if (note != null && !fetchedNotes.containsKey(eventId)) {
                    fetchedNotes[eventId] = note;
                    eventCount++;
                    debugPrint('[NostrDataService] PROFILE: ✓ Received note ${eventId.substring(0, 8)}... from $relayUrl (total: $eventCount)');
                  }
                }
              } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
                debugPrint('[NostrDataService] PROFILE: EOSE from $relayUrl (received $eventCount notes)');
                if (!completer.isCompleted) completer.complete();
              }
            } catch (e) {
              debugPrint('[NostrDataService] PROFILE: Error processing event: $e');
            }
          }, onDone: () {
            debugPrint('[NostrDataService] PROFILE: Connection closed: $relayUrl');
            if (!completer.isCompleted) completer.complete();
          }, onError: (error) {
            debugPrint('[NostrDataService] PROFILE: Connection error: $relayUrl - $error');
            if (!completer.isCompleted) completer.complete();
          }, cancelOnError: true);

          if (ws.readyState == WebSocket.open) {
            ws.add(NostrService.serializeRequest(request));
            debugPrint('[NostrDataService] PROFILE: Request sent to $relayUrl');
          }

          await completer.future.timeout(const Duration(seconds: 4), onTimeout: () {
            debugPrint('[NostrDataService] PROFILE: Timeout for $relayUrl (received $eventCount notes)');
          });

          await sub.cancel();
          await ws.close();
        } catch (e) {
          debugPrint('[NostrDataService] PROFILE: Exception with relay $relayUrl: $e');
          await sub?.cancel();
          await ws?.close();
        }
      }));

      debugPrint('[NostrDataService] PROFILE: Fetched ${fetchedNotes.length} notes from relays');

      int addedCount = 0;
      int skippedCount = 0;
      for (final note in fetchedNotes.values) {
        if (!_noteCache.containsKey(note.id) && !_eventIds.contains(note.id)) {
          _noteCache[note.id] = note;
          _eventIds.add(note.id);
          addedCount++;
        } else {
          skippedCount++;
        }
      }

      debugPrint('[NostrDataService] PROFILE: Added $addedCount new notes, skipped $skippedCount existing notes');

      final allProfileNotes = _noteCache.values.where((note) {
        final noteAuthorHex = _authService.npubToHex(note.author);
        return noteAuthorHex == pubkeyHex;
      }).toList();

      debugPrint('[NostrDataService] PROFILE: Total ${allProfileNotes.length} notes in cache for $userNpub');
      debugPrint('[NostrDataService] PROFILE: Note IDs: ${allProfileNotes.take(3).map((n) => n.id.substring(0, 8)).join(", ")}${allProfileNotes.length > 3 ? "..." : ""}');

      _notesController.add(_getFilteredNotesList());

      return Result.success(allProfileNotes);
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
      debugPrint('[NostrDataService] HASHTAG MODE: Fetching GLOBAL notes for #$hashtag with server-side filtering');

      final Map<String, NoteModel> hashtagNotesMap = {};
      final limitedRelays = _relayManager.relayUrls.take(3).toList();

      debugPrint('[NostrDataService] HASHTAG: Using ${limitedRelays.length} relays for PARALLEL fetch');

      await Future.wait(
        limitedRelays.map((relayUrl) async {
          if (_isClosed) return;

          WebSocket? ws;
          StreamSubscription? sub;
          try {
            debugPrint('[NostrDataService] HASHTAG: Connecting to $relayUrl');
            ws = await WebSocket.connect(relayUrl);
            if (_isClosed) {
              await ws.close();
              return;
            }

            final completer = Completer<void>();
            int eventCount = 0;

            sub = ws.listen((event) {
              try {
                final decoded = jsonDecode(event);

                if (decoded[0] == 'EVENT') {
                  final eventData = decoded[2] as Map<String, dynamic>;
                  final eventId = eventData['id'] as String;
                  final eventKind = eventData['kind'] as int;

                  if (eventKind == 1) {
                    if (!hashtagNotesMap.containsKey(eventId)) {
                      final note = _processHashtagEventDirectly(eventData);
                      if (note != null) {
                        hashtagNotesMap[eventId] = note;
                        eventCount++;
                        if (!_noteCache.containsKey(eventId) && !_eventIds.contains(eventId)) {
                          _noteCache[eventId] = note;
                          _eventIds.add(eventId);
                        }
                      }
                    }
                  }
                } else if (decoded[0] == 'EOSE') {
                  debugPrint('[NostrDataService] HASHTAG: EOSE from $relayUrl - $eventCount notes');
                  if (!completer.isCompleted) completer.complete();
                }
              } catch (e) {
                debugPrint('[NostrDataService] HASHTAG: Error processing event: $e');
              }
            }, onDone: () {
              if (!completer.isCompleted) completer.complete();
            }, onError: (error) {
              debugPrint('[NostrDataService] HASHTAG: Connection error on $relayUrl: $error');
              if (!completer.isCompleted) completer.complete();
            }, cancelOnError: true);

            if (ws.readyState == WebSocket.open) {
              final subscriptionId = NostrService.generateUUID();
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

              final request = jsonEncode(['REQ', subscriptionId, filterMap]);
              ws.add(request);
              debugPrint('[NostrDataService] HASHTAG: Query sent to $relayUrl');
            }

            await completer.future;

            await sub.cancel();
            await ws.close();
          } catch (e) {
            debugPrint('[NostrDataService] HASHTAG: Exception with $relayUrl: $e');
            await sub?.cancel();
            await ws?.close();
          }
        }),
      );

      final hashtagNotes = hashtagNotesMap.values.toList();

      hashtagNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final limitedNotes = hashtagNotes.take(limit).toList();

      debugPrint('[NostrDataService] HASHTAG: Returning ${limitedNotes.length} notes for #$hashtag (found ${hashtagNotes.length} total)');

      _scheduleUIUpdate();

      return Result.success(limitedNotes);
    } catch (e) {
      debugPrint('[NostrDataService] HASHTAG: Error fetching hashtag notes: $e');
      return Result.error('Failed to fetch hashtag notes: $e');
    }
  }

  NoteModel? _processHashtagEventDirectly(Map<String, dynamic> eventData) {
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
      debugPrint('[NostrDataService] HASHTAG: Error processing event: $e');
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

      await _fetchUserProfile(npub);

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
      debugPrint('[NostrDataService] Getting follow list for npub: $npub');
      debugPrint('[NostrDataService] Converted to hex: $pubkeyHex');

      final filter = NostrService.createFollowingFilter(
        authors: [pubkeyHex],
        limit: 1000,
      );

      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);

      debugPrint('[NostrDataService] Sending follow list request to relays...');
      debugPrint('[NostrDataService] Request: $serializedRequest');

      final following = <String>[];
      final limitedRelays = _relayManager.relayUrls.take(3).toList();
      debugPrint('[NostrDataService] Using ${limitedRelays.length} relays: $limitedRelays');

      await Future.wait(limitedRelays.map((relayUrl) async {
        WebSocket? ws;
        StreamSubscription? sub;
        try {
          debugPrint('[NostrDataService] Connecting to relay: $relayUrl');
          ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
          if (_isClosed) {
            await ws.close();
            return;
          }

          final completer = Completer<void>();
          bool hasReceivedEvent = false;

          sub = ws.listen((event) {
            try {
              final decoded = jsonDecode(event);
              debugPrint('[NostrDataService] Raw event from $relayUrl: $decoded');

              if (decoded[0] == 'EVENT') {
                hasReceivedEvent = true;
                debugPrint('[NostrDataService] Received follow list EVENT from $relayUrl');
                final eventData = decoded[2] as Map<String, dynamic>;
                final eventAuthor = eventData['pubkey'] as String;
                final eventKind = eventData['kind'] as int;
                final tags = eventData['tags'] as List<dynamic>;

                debugPrint('[NostrDataService] Event author: $eventAuthor (expected: $pubkeyHex)');
                debugPrint('[NostrDataService] Event kind: $eventKind (expected: 3)');
                debugPrint('[NostrDataService] Event tags count: ${tags.length}');

                if (eventAuthor == pubkeyHex && eventKind == 3) {
                  for (var tag in tags) {
                    if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
                      final followedHexPubkey = tag[1] as String;
                      if (!following.contains(followedHexPubkey)) {
                        following.add(followedHexPubkey);
                        debugPrint('[NostrDataService] Found followed user (hex): $followedHexPubkey');
                      }
                    }
                  }
                  debugPrint('[NostrDataService] Follow list now has: ${following.length} users');
                }
              } else if (decoded[0] == 'EOSE') {
                debugPrint('[NostrDataService] EOSE received from $relayUrl');
                if (!completer.isCompleted) completer.complete();
              }
            } catch (e) {
              debugPrint('[NostrDataService] Error processing follow list event from $relayUrl: $e');
            }
          }, onDone: () {
            debugPrint('[NostrDataService] Connection to $relayUrl closed');
            if (!completer.isCompleted) completer.complete();
          }, onError: (error) {
            debugPrint('[NostrDataService] Connection error to $relayUrl: $error');
            if (!completer.isCompleted) completer.complete();
          }, cancelOnError: true);

          if (ws.readyState == WebSocket.open) {
            debugPrint('[NostrDataService] Sending follow list request to $relayUrl');
            ws.add(serializedRequest);
          } else {
            debugPrint('[NostrDataService] WebSocket not open for $relayUrl, state: ${ws.readyState}');
          }

          await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
            debugPrint('[NostrDataService] Timeout waiting for follow list from $relayUrl');
          });

          await sub.cancel();
          await ws.close();

          debugPrint('[NostrDataService]  Finished processing $relayUrl, got ${hasReceivedEvent ? 'events' : 'no events'}');
        } catch (e) {
          debugPrint('[NostrDataService]  Exception with relay $relayUrl: $e');
          await sub?.cancel();
          await ws?.close();
        }
      }));

      final uniqueFollowing = following.toSet().toList();
      debugPrint('[NostrDataService]Finalfollowlist:${uniqueFollowing.length} unique users');

      for (int i = 0; i < uniqueFollowing.length && i < 10; i++) {
        final hexPubkey = uniqueFollowing[i];
        final npub = _authService.hexToNpub(hexPubkey) ?? 'unknown';
        debugPrint('[NostrDataService]   Final[$i]: $hexPubkey -> $npub');
      }

      return Result.success(uniqueFollowing);
    } catch (e) {
      debugPrint('[NostrDataService] Exception in getFollowingList: $e');
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

      final limitedRelays = _relayManager.relayUrls.take(5).toList();
      bool noteFound = false;

      debugPrint('[NostrDataService] THREAD: Using ${limitedRelays.length} relays for direct fetch');

      await Future.wait(limitedRelays.map((relayUrl) async {
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

        final filter = NostrService.createCombinedInteractionFilter(
          eventIds: batch,
          limit: 2000,
        );
        final request = NostrService.createRequest(filter);
        await _relayManager.broadcast(NostrService.serializeRequest(request));

        if (i + batchSize < noteIds.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      debugPrint('[NostrDataService] Interaction fetching completed for ${noteIds.length} notes');
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching interactions: $e');
    }
  }

  final Map<String, Map<String, dynamic>> _pendingCountRequests = {};

  Future<void> _fetchInteractionCountsForNotesImmediately(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    final totalRequests = noteIds.length * 4;
    debugPrint('[NostrDataService] Fetching interaction counts IMMEDIATELY using NIP-45 for ${noteIds.length} notes ($totalRequests queries)...');

    try {
      for (final noteId in noteIds) {
        _fetchCountForNoteWithRetry(noteId, 7, maxRetries: 3);
        _fetchCountForNoteWithRetry(noteId, 1, maxRetries: 3);
        _fetchCountForNoteWithRetry(noteId, 6, maxRetries: 3);
        _fetchCountForNoteWithRetry(noteId, 9735, maxRetries: 3);
      }

      debugPrint('[NostrDataService] $totalRequests COUNT requests sent IMMEDIATELY (parallel)');
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching interaction counts: $e');
    }
  }

  Future<void> _fetchInteractionCountsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    final totalRequests = noteIds.length * 4;
    debugPrint('[NostrDataService] Fetching interaction counts using NIP-45 for ${noteIds.length} notes ($totalRequests queries)...');

    try {
      for (final noteId in noteIds) {
        _fetchCountForNoteWithRetry(noteId, 7, maxRetries: 3);
        _fetchCountForNoteWithRetry(noteId, 1, maxRetries: 3);
        _fetchCountForNoteWithRetry(noteId, 6, maxRetries: 3);
        _fetchCountForNoteWithRetry(noteId, 9735, maxRetries: 3);
      }

      debugPrint('[NostrDataService] $totalRequests COUNT requests sent (parallel)');
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching interaction counts: $e');
    }
  }

  Future<void> _fetchCountForNoteWithRetry(String noteId, int kind, {int maxRetries = 3, int attempt = 1}) async {
    try {
      final filterMap = <String, dynamic>{
        'kinds': [kind],
        '#e': [noteId],
      };
      final subscriptionId = NostrService.generateUUID();
      
      final completer = Completer<void>();
      
      _pendingCountRequests[subscriptionId] = {
        'kind': kind,
        'noteId': noteId,
        'completer': completer,
        'attempt': attempt,
      };
      
      final countRequest = jsonEncode(['COUNT', subscriptionId, filterMap]);
      
      final ws = _relayManager.webSockets[countRelayUrl];
      if (ws != null && ws.readyState == WebSocket.open) {
        ws.add(countRequest);
        
        final kindName = _getKindName(kind);
        if (attempt == 1) {
          debugPrint('[NostrDataService] COUNT → $noteId ($kindName)');
        } else {
          debugPrint('[NostrDataService] COUNT → $noteId ($kindName) - retry $attempt/$maxRetries');
        }
        
        try {
          await completer.future.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              _pendingCountRequests.remove(subscriptionId);
              throw TimeoutException('COUNT timeout');
            },
          );
        } on TimeoutException {
          if (attempt < maxRetries) {
            debugPrint('[NostrDataService] TIMEOUT $noteId ($kindName), retrying...');
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            return _fetchCountForNoteWithRetry(noteId, kind, maxRetries: maxRetries, attempt: attempt + 1);
          } else {
            debugPrint('[NostrDataService] FAILED ✗ $noteId ($kindName) after $maxRetries attempts');
            _setDefaultCount(noteId, kind);
          }
        } catch (e) {
          if (e.toString().contains('CLOSED')) {
            debugPrint('[NostrDataService] RELAY REFUSED ✗ $noteId ($kindName) - not retrying');
            _setDefaultCount(noteId, kind);
          } else if (attempt < maxRetries) {
            debugPrint('[NostrDataService] ERROR $noteId ($kindName): $e - retrying...');
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            return _fetchCountForNoteWithRetry(noteId, kind, maxRetries: maxRetries, attempt: attempt + 1);
          } else {
            debugPrint('[NostrDataService] FAILED ✗ $noteId ($kindName) - $e');
            _setDefaultCount(noteId, kind);
          }
        }
      } else {
        _pendingCountRequests.remove(subscriptionId);
        debugPrint('[NostrDataService] WebSocket not ready for COUNT request');
        _setDefaultCount(noteId, kind);
      }
    } catch (e) {
      debugPrint('[NostrDataService] Exception in COUNT request for $noteId kind $kind: $e');
      _setDefaultCount(noteId, kind);
    }
  }

  void _setDefaultCount(String noteId, int kind) {
    final note = _noteCache[noteId];
    if (note == null) return;

    final kindName = _getKindName(kind);
    debugPrint('[NostrDataService] Keeping existing count for $noteId ($kindName) - COUNT query failed');
    
    _notesController.add(_getNotesList());
  }

  String _getKindName(int kind) {
    switch (kind) {
      case 1:
        return 'replies';
      case 6:
        return 'reposts';
      case 7:
        return 'reactions';
      case 9735:
        return 'zaps';
      default:
        return 'kind-$kind';
    }
  }

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
          final pubkey = requestData['pubkey'] as String;
          debugPrint('[NostrDataService] COUNT ✓ Follower count for $pubkey = $count');
          if (!completer.isCompleted) {
            completer.complete(count);
          }
          _pendingCountRequests.remove(subscriptionId);
          return;
        }
        
        final kind = requestData['kind'] as int;
        final noteId = requestData['noteId'] as String;
        final kindName = _getKindName(kind);
        
        final note = _noteCache[noteId];
        if (note != null) {
          switch (kind) {
            case 7:
              final oldCount = note.reactionCount;
              if (count >= oldCount) {
                note.reactionCount = count;
                if (count > oldCount) {
                  debugPrint('[NostrDataService] COUNT ✓ Note $noteId reactions: $oldCount → $count');
                } else {
                  debugPrint('[NostrDataService] COUNT ✓ Note $noteId reactions: $count');
                }
              } else {
                debugPrint('[NostrDataService] COUNT ⚠ Note $noteId reactions: kept $oldCount (received $count)');
              }
              break;
            case 1:
              final oldCount = note.replyCount;
              if (count >= oldCount) {
                note.replyCount = count;
                if (count > oldCount) {
                  debugPrint('[NostrDataService] COUNT ✓ Note $noteId replies: $oldCount → $count');
                } else {
                  debugPrint('[NostrDataService] COUNT ✓ Note $noteId replies: $count');
                }
              } else {
                debugPrint('[NostrDataService] COUNT ⚠ Note $noteId replies: kept $oldCount (received $count)');
              }
              break;
            case 6:
              final oldCount = note.repostCount;
              if (count >= oldCount) {
                note.repostCount = count;
                if (count > oldCount) {
                  debugPrint('[NostrDataService] COUNT ✓ Note $noteId reposts: $oldCount → $count');
                } else {
                  debugPrint('[NostrDataService] COUNT ✓ Note $noteId reposts: $count');
                }
              } else {
                debugPrint('[NostrDataService] COUNT ⚠ Note $noteId reposts: kept $oldCount (received $count)');
              }
              break;
            case 9735:
              debugPrint('[NostrDataService] COUNT ✓ Note $noteId zaps = $count');
              break;
          }
          
          if (requestData.containsKey('completer')) {
            final completer = requestData['completer'] as Completer<void>;
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
          
          _notesController.add(_getNotesList());
        } else {
          debugPrint('[NostrDataService] COUNT response for unknown note: $noteId ($kindName)');
        }

        _pendingCountRequests.remove(subscriptionId);
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
          final pubkey = requestData['pubkey'] as String;
          debugPrint('[NostrDataService] CLOSED ✗ Follower count for $pubkey - reason: $reason');
          if (!completer.isCompleted) {
            completer.completeError('CLOSED: $reason');
          }
          _pendingCountRequests.remove(subscriptionId);
          return;
        }
        
        final kind = requestData['kind'] as int;
        final noteId = requestData['noteId'] as String;
        final kindName = _getKindName(kind);
        
        debugPrint('[NostrDataService] CLOSED ✗ COUNT for $noteId ($kindName) - reason: $reason');
        
        if (requestData.containsKey('completer')) {
          final completer = requestData['completer'] as Completer<void>;
          if (!completer.isCompleted) {
            completer.completeError('CLOSED: $reason');
          }
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
        
        if (attempt == 1) {
          debugPrint('[NostrDataService] COUNT → follower count for $pubkeyHex');
        } else {
          debugPrint('[NostrDataService] COUNT → follower count for $pubkeyHex - retry $attempt/$maxRetries');
        }
        
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
            debugPrint('[NostrDataService] TIMEOUT follower count for $pubkeyHex, retrying...');
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            return fetchFollowerCount(pubkeyHex, maxRetries: maxRetries, attempt: attempt + 1);
          } else {
            debugPrint('[NostrDataService] FAILED ✗ follower count for $pubkeyHex after $maxRetries attempts');
            return 0;
          }
        } catch (e) {
          if (e.toString().contains('CLOSED')) {
            debugPrint('[NostrDataService] RELAY REFUSED ✗ follower count for $pubkeyHex');
            return 0;
          } else if (attempt < maxRetries) {
            debugPrint('[NostrDataService] ERROR follower count for $pubkeyHex: $e - retrying...');
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            return fetchFollowerCount(pubkeyHex, maxRetries: maxRetries, attempt: attempt + 1);
          } else {
            debugPrint('[NostrDataService] FAILED ✗ follower count for $pubkeyHex - $e');
            return 0;
          }
        }
      } else {
        _pendingCountRequests.remove(subscriptionId);
        debugPrint('[NostrDataService] WebSocket not ready for follower COUNT request');
        return 0;
      }
    } catch (e) {
      debugPrint('[NostrDataService] Exception in follower COUNT request for $pubkeyHex: $e');
      return 0;
    }
  }

  Future<void> fetchInteractionsForNotes(List<String> noteIds, {bool forceLoad = false, bool useCount = false}) async {
    if (_isClosed || noteIds.isEmpty) return;

    const maxNotesPerFetch = 15;
    final cappedNoteIds = noteIds.length > maxNotesPerFetch 
        ? noteIds.take(maxNotesPerFetch).toList() 
        : noteIds;
    
    if (noteIds.length > maxNotesPerFetch) {
      debugPrint('[NostrDataService] Capped interaction fetch from ${noteIds.length} to $maxNotesPerFetch notes');
    }

    debugPrint('[NostrDataService] ${forceLoad ? 'Manual' : 'Automatic'} interaction fetching for ${cappedNoteIds.length} notes (useCount: $useCount)');

    final now = DateTime.now();
    final noteIdsToFetch = <String>[];

    for (final eventId in cappedNoteIds) {
      if (!forceLoad) {
      final lastFetch = _lastInteractionFetch[eventId];
      if (lastFetch != null && now.difference(lastFetch) < _interactionFetchCooldown) {
        continue;
        }
      }

      noteIdsToFetch.add(eventId);
      _lastInteractionFetch[eventId] = now;
    }

    if (noteIdsToFetch.isNotEmpty) {
      debugPrint('[NostrDataService] Actually fetching for ${noteIdsToFetch.length} notes (after cooldown filter)');
      if (useCount) {
        await _fetchInteractionCountsForNotes(noteIdsToFetch);
      } else {
      await _fetchInteractionsForNotes(noteIdsToFetch);
      }

      int updatedCount = 0;
      int notFoundCount = 0;
      for (final eventId in noteIdsToFetch) {
        final note = _noteCache[eventId];
        if (note != null && !useCount) {
          final oldReactionCount = note.reactionCount;
          final oldZapAmount = note.zapAmount;
          final oldRepostCount = note.repostCount;
          
          note.reactionCount = _reactionsMap[eventId]?.length ?? 0;
          note.replyCount = 0;
          note.repostCount = _repostsMap[eventId]?.length ?? 0;
          note.zapAmount = _zapsMap[eventId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
          
          if (oldReactionCount != note.reactionCount || oldZapAmount != note.zapAmount || oldRepostCount != note.repostCount) {
            updatedCount++;
            if (updatedCount <= 3) {
              debugPrint('[NostrDataService] Note ${eventId.substring(0, 8)}: reactions $oldReactionCount→${note.reactionCount}, zaps $oldZapAmount→${note.zapAmount}, reposts $oldRepostCount→${note.repostCount}');
            }
          }
        } else {
          notFoundCount++;
          if (notFoundCount <= 3) {
            debugPrint('[NostrDataService] WARN: Note ${eventId.substring(0, 8)} not found in cache for interaction update');
          }
        }
      }

      debugPrint('[NostrDataService] Updated interaction counts for $updatedCount/${noteIdsToFetch.length} notes ($notFoundCount not in cache)');

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

  Map<String, int> getInteractionCounts(String noteId) {
    return {
      'reactions': _reactionsMap[noteId]?.length ?? 0,
      'reposts': _repostsMap[noteId]?.length ?? 0,
      'zaps': _zapsMap[noteId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0,
    };
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
      
      if (!_isClosed && !_notesController.isClosed) {
        final notesList = _getFilteredNotesList();
        _notesController.add(notesList);
      }

      debugPrint('[NostrDataService] Note deleted successfully: $noteId');
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
