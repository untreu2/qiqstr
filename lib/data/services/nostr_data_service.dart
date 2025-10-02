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
import '../../services/nip05_verification_service.dart';
import 'auth_service.dart';

/// Complete Nostr protocol data service
/// Handles all real Nostr operations with proper caching and error handling
class NostrDataService {
  final AuthService _authService;
  final WebSocketManager _relayManager;
  final Nip05VerificationService _nip05Service = Nip05VerificationService.instance;

  // Stream controllers for real-time data
  final StreamController<List<NoteModel>> _notesController = StreamController<List<NoteModel>>.broadcast();
  final StreamController<List<UserModel>> _usersController = StreamController<List<UserModel>>.broadcast();
  final StreamController<List<NotificationModel>> _notificationsController = StreamController<List<NotificationModel>>.broadcast();

  // Cache with TTL management
  final Map<String, NoteModel> _noteCache = {};
  final Map<String, CachedProfile> _profileCache = {};
  final Map<String, List<NotificationModel>> _notificationCache = {};
  final Map<String, List<ReactionModel>> _reactionsMap = {};
  final Map<String, List<ZapModel>> _zapsMap = {};
  final Map<String, List<ReactionModel>> _repostsMap = {}; // Track reposts for each note
  final Set<String> _eventIds = {};

  // Follow list cache for feed filtering
  final Map<String, List<String>> _followingCache = {}; // npub -> list of followed hex pubkeys
  final Map<String, DateTime> _followingCacheTime = {};
  final Duration _followingCacheTTL = const Duration(minutes: 10);

  // Performance optimization
  final Set<String> _pendingOptimisticReactionIds = {};
  final Duration _profileCacheTTL = const Duration(minutes: 30);

  // Event processing
  final List<Map<String, dynamic>> _eventQueue = [];
  Timer? _batchProcessingTimer;
  static const int _maxBatchSize = 25;
  static const Duration _batchTimeout = Duration(milliseconds: 100);

  // State management
  bool _isClosed = false;
  String _currentUserNpub = '';

  // UI update throttling (like legacy)
  Timer? _uiUpdateThrottleTimer;
  bool _uiUpdatePending = false;
  static const Duration _uiUpdateThrottle = Duration(milliseconds: 200);

  // Interaction fetching control
  final Map<String, DateTime> _lastInteractionFetch = {};
  final Duration _interactionFetchCooldown = Duration(seconds: 5);

  NostrDataService({
    required AuthService authService,
    WebSocketManager? relayManager,
  })  : _authService = authService,
        _relayManager = relayManager ?? WebSocketManager.instance {
    _setupRelayEventHandling();
    _startCacheCleanup();
  }

  // Streams
  Stream<List<NoteModel>> get notesStream => _notesController.stream;
  Stream<List<UserModel>> get usersStream => _usersController.stream;
  Stream<List<NotificationModel>> get notificationsStream => _notificationsController.stream;

  // Expose AuthService for other services
  AuthService get authService => _authService;

  /// Check if a note should be included in the feed based on follow list
  bool _shouldIncludeNoteInFeed(String authorHexPubkey, bool isRepost) {
    // Always include current user's content
    final currentUserHex = _authService.npubToHex(_currentUserNpub);
    if (currentUserHex == authorHexPubkey) {
      return true;
    }

    // Check cached follow list for current user
    final cachedFollowing = _followingCache[_currentUserNpub];
    final cacheTime = _followingCacheTime[_currentUserNpub];

    if (cachedFollowing != null && cacheTime != null) {
      final isValid = DateTime.now().difference(cacheTime) < _followingCacheTTL;
      if (isValid) {
        final isFollowed = cachedFollowing.contains(authorHexPubkey);
        debugPrint('[NostrDataService]  Author $authorHexPubkey ${isFollowed ? 'IS' : 'NOT'} in follow list (cached)');
        return isFollowed;
      }
    }

    // CRITICAL FIX: If no valid cache, REJECT the note instead of allowing
    debugPrint('[NostrDataService] No valid follow cache - REJECTING note from: $authorHexPubkey');
    _refreshFollowCacheInBackground();
    return false; // STRICT: Don't allow notes when follow list is not available
  }

  /// Refresh follow cache in background
  void _refreshFollowCacheInBackground() async {
    if (_currentUserNpub.isNotEmpty) {
      try {
        debugPrint('[NostrDataService]  Refreshing follow cache in background...');
        final result = await getFollowingList(_currentUserNpub);
        if (result.isSuccess && result.data != null) {
          _followingCache[_currentUserNpub] = result.data!;
          _followingCacheTime[_currentUserNpub] = DateTime.now();
          debugPrint('[NostrDataService] Follow cache refreshed: ${result.data!.length} following');
        }
      } catch (e) {
        debugPrint('[NostrDataService]  Error refreshing follow cache: $e');
      }
    }
  }

  /// Setup relay event handling with comprehensive processing
  void _setupRelayEventHandling() {
    // Connect to default relays with empty target (global timeline)
    _relayManager.connectRelays(
      [], // Empty target npubs for global timeline initially
      onEvent: _handleRelayEvent,
      onDisconnected: _handleRelayDisconnection,
      serviceId: 'nostr_data_service',
    );

    // CRITICAL: Initialize follow list cache immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFollowListCache();
    });
  }

  /// Initialize follow list cache on service startup
  Future<void> _initializeFollowListCache() async {
    try {
      // Get current user first
      final currentUser = await _authService.getCurrentUserNpub();
      if (currentUser.isSuccess && currentUser.data != null) {
        _currentUserNpub = currentUser.data!;
        debugPrint('[NostrDataService] Initializing follow list cache for: $_currentUserNpub');

        // Load follow list immediately
        final followingResult = await getFollowingList(_currentUserNpub);
        if (followingResult.isSuccess && followingResult.data != null) {
          _followingCache[_currentUserNpub] = followingResult.data!;
          _followingCacheTime[_currentUserNpub] = DateTime.now();
          debugPrint('[NostrDataService] Follow list cache initialized: ${followingResult.data!.length} following');
        } else {
          debugPrint('[NostrDataService]  No follow list found during initialization');
        }
      }

      // After follow list is set up, then fetch content
      _fetchInitialGlobalContent();
    } catch (e) {
      debugPrint('[NostrDataService]  Error initializing follow list cache: $e');
      // Still fetch some content even if follow list fails
      _fetchInitialGlobalContent();
    }
  }

  /// Fetch initial global content for new users
  Future<void> _fetchInitialGlobalContent() async {
    try {
      debugPrint('[NostrDataService] Fetching initial global content...');

      // Create a basic global timeline filter
      final filter = NostrService.createNotesFilter(
        authors: null, // Global timeline
        kinds: [1], // Just text notes first
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

  /// Handle incoming relay events with batching
  void _handleRelayEvent(dynamic rawEvent, String relayUrl) {
    try {
      final eventData = jsonDecode(rawEvent);
      if (eventData is List && eventData.length >= 3) {
        final messageType = eventData[0];

        if (messageType == 'EVENT') {
          final event = eventData[2] as Map<String, dynamic>;

          // Add to batch queue for processing
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
    } catch (e) {
      debugPrint('[NostrDataService] Error handling relay event: $e');
    }
  }

  /// Flush event queue for batch processing
  void _flushEventQueue() {
    if (_eventQueue.isEmpty) return;

    _batchProcessingTimer?.cancel();
    _batchProcessingTimer = null;

    final batch = List<Map<String, dynamic>>.from(_eventQueue);
    _eventQueue.clear();

    // Process batch asynchronously but don't wait for completion to avoid blocking
    for (final eventData in batch) {
      // Process events without blocking each other
      _processNostrEvent(eventData['eventData'] as Map<String, dynamic>).catchError((e) {
        debugPrint('[NostrDataService] Error in batch event processing: $e');
      });
    }
  }

  /// Process incoming Nostr event with complete handling
  Future<void> _processNostrEvent(Map<String, dynamic> eventData) async {
    try {
      final kind = eventData['kind'] as int;
      final eventAuthor = eventData['pubkey'] as String? ?? '';

      // Process notification if it mentions current user
      if (eventAuthor.isNotEmpty && eventAuthor != _currentUserNpub) {
        _processNotificationFast(eventData, kind, eventAuthor);
      }

      switch (kind) {
        case 0: // User profile
          _processProfileEvent(eventData);
          break;
        case 1: // Text note
          await _processKind1Event(eventData);
          break;
        case 3: // Follow list
          _processFollowEvent(eventData);
          break;
        case 6: // Repost
          await _processRepostEvent(eventData);
          break;
        case 7: // Reaction
          _processReactionEvent(eventData);
          break;
        case 9735: // Zap
          _processZapEvent(eventData);
          break;
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing event: $e');
    }
  }

  /// Process profile event (kind 0) with NIP-05 verification
  void _processProfileEvent(Map<String, dynamic> eventData) {
    try {
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      // Check if we have newer cached profile
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

        // Handle NIP-05 verification asynchronously
        _verifyAndCacheProfile(pubkey, profileData, timestamp, nip05);
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing profile event: $e');
    }
  }

  /// Verify NIP-05 and cache profile
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

    _usersController.add(_getUsersList());
    debugPrint('[NostrDataService] Profile updated: ${user.name} (NIP-05: $nip05Verified)');
  }

  /// Process kind 1 events (text notes) with reply detection
  Future<void> _processKind1Event(Map<String, dynamic> eventData) async {
    try {
      final tags = List<dynamic>.from(eventData['tags'] ?? []);
      String? rootId;
      String? replyId;
      bool isReply = false;

      // Parse reply structure according to NIP-10
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

  /// Process regular note event
  Future<void> _processNoteEvent(Map<String, dynamic> eventData) async {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      // CRITICAL FIX: Strong duplicate checking
      if (_eventIds.contains(id) || _noteCache.containsKey(id)) {
        debugPrint(' [NostrDataService] Duplicate note detected, skipping: $id');
        return;
      }

      // CRITICAL: Filter notes by follow list BEFORE adding to cache
      if (!_shouldIncludeNoteInFeed(pubkey, false)) {
        debugPrint(' [NostrDataService] Note filtered out - author not in follow list: $pubkey');
        return;
      }

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      debugPrint('[NostrDataService] Processing note from followed author: $authorNpub');

      // Parse tags for reply structure
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

      // Debug: Verify cache addition
      debugPrint('Note added to cache. Total cached notes: ${_noteCache.length}');

      // LEGACY PATTERN: Don't auto-fetch interactions, only update existing counts
      debugPrint('[NostrDataService] Note processed without automatic interaction fetch: $id');

      // Schedule UI update with throttling (like legacy)
      _scheduleUIUpdate();

      // Fetch profile for note author
      _fetchUserProfile(authorNpub);

      debugPrint('[NostrDataService] New note processed: ${note.content.substring(0, 30)}...');
    } catch (e) {
      debugPrint('[NostrDataService] Error processing note event: $e');
    }
  }

  /// Handle reply events with proper threading
  Future<void> _handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      // CRITICAL FIX: Strong duplicate checking for replies
      if (_eventIds.contains(id) || _noteCache.containsKey(id)) {
        debugPrint(' [NostrDataService] Duplicate reply detected, skipping: $id');
        return;
      }

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      // Parse tags for thread structure
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

      // Simple approach: Just create the note model, no separate reply tracking
      final finalParentId = actualParentId ?? parentEventId;
      final parentNote = _noteCache[finalParentId];

      // Create note model for the reply
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

      // Note: Interaction fetching removed - only fetch when explicitly needed (e.g., ThreadPage)
      debugPrint('[NostrDataService] Reply processed without automatic interaction fetch: $id');

      // Schedule UI update with throttling (like legacy)
      _scheduleUIUpdate();

      // Fetch profile for reply author
      _fetchUserProfile(authorNpub);

      debugPrint('[NostrDataService] Reply processed: ${content.substring(0, 30)}...');
    } catch (e) {
      debugPrint('[NostrDataService] Error processing reply event: $e');
    }
  }

  /// Process reaction event (kind 7)
  void _processReactionEvent(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      // Find target event
      String? targetEventId;
      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'e' && tag.length >= 2) {
          targetEventId = tag[1] as String;
          break;
        }
      }

      if (targetEventId != null) {
        // Skip if this is an optimistic reaction we sent
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

        _reactionsMap.putIfAbsent(targetEventId, () => []);

        if (!_reactionsMap[targetEventId]!.any((r) => r.id == reaction.id)) {
          _reactionsMap[targetEventId]!.add(reaction);

          // Update target note reaction count
          final targetNote = _noteCache[targetEventId];
          if (targetNote != null) {
            targetNote.reactionCount = _reactionsMap[targetEventId]!.length;
            // Schedule UI update with throttling (like legacy)
            _scheduleUIUpdate();
          }

          // Fetch profile for reaction author
          _fetchUserProfile(reaction.author);
        }
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing reaction event: $e');
    }
  }

  /// Process repost event (kind 6) according to NIP-18
  Future<void> _processRepostEvent(Map<String, dynamic> eventData) async {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;
      final content = eventData['content'] as String? ?? '';

      // First, always track repost count for interaction purposes
      _trackRepostForCount(eventData);

      // CRITICAL FIX: Strong duplicate checking for reposts
      if (_eventIds.contains(id) || _noteCache.containsKey(id)) {
        debugPrint(' [NostrDataService] Duplicate repost detected, skipping: $id');
        return;
      }

      // CRITICAL: Filter reposts by follow list BEFORE adding to cache
      if (!_shouldIncludeNoteInFeed(pubkey, true)) {
        debugPrint(' [NostrDataService] Repost filtered out - reposter not in follow list: $pubkey');
        return;
      }

      debugPrint('[NostrDataService] Processing repost from followed user: $pubkey');

      // Find original event and original author from tags
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

        debugPrint(' [NostrDataService] Processing repost $id by $reposterNpub');
        debugPrint(' [NostrDataService] Original event ID: $originalEventId');
        debugPrint(' [NostrDataService] Original author hex: $originalAuthorHex');
        debugPrint(' [NostrDataService] Repost content length: ${content.length}');

        // Variables to track original note's reply status
        bool detectedIsReply = false;
        String? detectedRootId;
        String? detectedParentId;

        // Get the original note to display its content
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

        // If we have the original note, use its content and author
        if (originalNote != null) {
          displayContent = originalNote.content;
          displayAuthor = originalNote.author;
        } else if (content.isNotEmpty) {
          debugPrint(' [NostrDataService] Parsing content since original not in cache...');
          debugPrint(' [NostrDataService] Content to parse (first 300 chars): ${content.substring(0, math.min(300, content.length))}');

          // Try to extract original content from repost content (NIP-18)
          try {
            final originalContent = jsonDecode(content) as Map<String, dynamic>;
            debugPrint('[NostrDataService] Successfully parsed repost JSON content');
            debugPrint(' [NostrDataService] Original content field: ${originalContent['content']}');
            debugPrint(' [NostrDataService] Original tags field: ${originalContent['tags']}');

            displayContent = originalContent['content'] as String? ?? displayContent;
            if (originalAuthorHex != null) {
              displayAuthor = _authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex;
            }

            // CRITICAL: Check if the original content is a reply according to NIP-10
            final originalTags = originalContent['tags'] as List<dynamic>? ?? [];

            debugPrint(' [NostrDataService] Checking if original note is reply. Tags count: ${originalTags.length}');
            debugPrint(' [NostrDataService] All tags: $originalTags');

            // Check EVERY e-tag for any reply indicators
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
                    detectedParentId = eventId; // CRITICAL: For root replies, parentId = rootId
                    detectedIsReply = true;
                    debugPrint('  ROOT marker found - this is a direct reply! rootId: $detectedRootId, parentId: $detectedParentId');
                  } else if (marker == 'reply') {
                    detectedParentId = eventId;
                    detectedIsReply = true;
                    debugPrint('  REPLY marker found - this is a reply! parentId: $detectedParentId');
                  } else if (marker == 'mention') {
                    debugPrint('  ℹ️ MENTION marker - not a reply indicator');
                  } else {
                    debugPrint('   Unknown marker: "$marker"');
                  }
                } else {
                  // Legacy positional e-tags (any e-tag without marker indicates reply)
                  if (detectedParentId == null) {
                    detectedParentId = eventId;
                    detectedRootId = eventId; // For legacy, assume parentId = rootId
                    detectedIsReply = true;
                    debugPrint('  Legacy e-tag found - this is a reply! eventId: $detectedParentId');
                  }
                }
              }
            }

            debugPrint(' [NostrDataService] PARSED Original note reply status: isReply=$detectedIsReply');
            debugPrint(' [NostrDataService] PARSED rootId=$detectedRootId, parentId=$detectedParentId');

            // Create and cache the original note if it doesn't exist
            if (originalAuthorHex != null && !_noteCache.containsKey(originalEventId)) {
              final originalNoteFromRepost = NoteModel(
                id: originalEventId,
                content: displayContent,
                author: displayAuthor,
                timestamp: DateTime.fromMillisecondsSinceEpoch((originalContent['created_at'] as int? ?? createdAt) * 1000),
                isReply: detectedIsReply, // CRITICAL: Set reply flag correctly
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

        // CRITICAL: Use the detected reply information from parsing or cache
        final finalIsReply = detectedIsReply;
        final finalRootId = detectedRootId;
        final finalParentId = detectedParentId;

        debugPrint(' [NostrDataService] FINAL repost determination: isReply=$finalIsReply');
        debugPrint(' [NostrDataService] FINAL rootId=$finalRootId, parentId=$finalParentId');

        // Create visible repost note
        final repostNote = NoteModel(
          id: id,
          content: displayContent,
          author: displayAuthor,
          timestamp: timestamp,
          isReply: finalIsReply, // CRITICAL: Use determined reply status
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

        // CRITICAL CHECK: Verify the repost note will show "Reply to..." text
        if (repostNote.isReply && repostNote.parentId != null) {
          debugPrint('[NostrDataService] This repost note SHOULD show "Reply to..." text in UI');
        } else {
          debugPrint(' [NostrDataService] This repost note will NOT show "Reply to..." text');
          debugPrint(' [NostrDataService]   isReply=${repostNote.isReply}, parentId=${repostNote.parentId}');
        }

        _noteCache[id] = repostNote;
        _eventIds.add(id);

        // Update original note's repost count
        final targetNote = _noteCache[originalEventId];
        if (targetNote != null) {
          targetNote.repostCount = _repostsMap[originalEventId]?.length ?? 0;
          debugPrint(' [NostrDataService] Updated original note $originalEventId repost count: ${targetNote.repostCount}');
        }

        _scheduleUIUpdate();
        _fetchUserProfile(reposterNpub);
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing repost event: $e');
    }
  }

  /// Track repost for count only (used for interaction fetching)
  void _trackRepostForCount(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String;
      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      // Find original event from tags
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

        // Track this repost for count purposes
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

          // Update original note's repost count
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

  /// Process follow event (kind 3)
  void _processFollowEvent(Map<String, dynamic> eventData) {
    try {
      final pubkey = eventData['pubkey'] as String;
      final tags = eventData['tags'] as List<dynamic>;

      final List<String> newFollowing = [];
      for (var tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
          newFollowing.add(tag[1] as String);
        }
      }

      // Update follow cache for current user
      final userNpub = _authService.hexToNpub(pubkey);
      if (userNpub != null) {
        _followingCache[userNpub] = newFollowing;
        _followingCacheTime[userNpub] = DateTime.now();
        debugPrint('[NostrDataService]  Updated follow cache for $userNpub: ${newFollowing.length} following');
      }

      debugPrint('[NostrDataService] Follow event processed: ${newFollowing.length} following');
    } catch (e) {
      debugPrint('[NostrDataService] Error processing follow event: $e');
    }
  }

  /// Process zap event (kind 9735)
  void _processZapEvent(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String;
      final walletPubkey = eventData['pubkey'] as String; // This is the wallet/server pubkey
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List<dynamic>;

      // Find target event, amount, recipient, bolt11, and description
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
              amount = int.parse(tag[1] as String) ~/ 1000; // Convert millisats to sats
            } catch (e) {
              amount = 0;
            }
          }
        }
      }

      // Extract real zapper from description tag (NIP-57)
      String realZapperPubkey = walletPubkey; // Fallback to wallet pubkey
      String? zapComment;

      if (description.isNotEmpty) {
        try {
          // Parse the description which should contain the original zap request (kind 9734)
          final zapRequest = jsonDecode(description) as Map<String, dynamic>;

          // Extract the real zapper's pubkey from the zap request
          if (zapRequest.containsKey('pubkey')) {
            realZapperPubkey = zapRequest['pubkey'] as String;
            debugPrint('[NostrDataService] Extracted real zapper from description: $realZapperPubkey');
          }

          // Extract zap comment from the zap request content
          if (zapRequest.containsKey('content')) {
            final requestContent = zapRequest['content'] as String;
            if (requestContent.isNotEmpty) {
              zapComment = requestContent;
              debugPrint('[NostrDataService] Extracted zap comment: $zapComment');
            }
          }
        } catch (e) {
          debugPrint('[NostrDataService]  Failed to parse zap description, using wallet pubkey: $e');
          // Keep realZapperPubkey as walletPubkey fallback
        }
      } else {
        debugPrint('[NostrDataService]  No description tag found in zap receipt, using wallet pubkey');
      }

      // Try to parse amount from bolt11 if not found in tags
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
          sender: _authService.hexToNpub(realZapperPubkey) ?? realZapperPubkey, // Use real zapper, not wallet
          recipient: _authService.hexToNpub(recipient) ?? recipient,
          targetEventId: targetEventId,
          timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
          bolt11: bolt11,
          comment: zapComment ?? (content.isNotEmpty ? content : null), // Prefer zap request comment
          amount: amount,
        );

        _zapsMap.putIfAbsent(targetEventId, () => []);

        if (!_zapsMap[targetEventId]!.any((z) => z.id == zap.id)) {
          _zapsMap[targetEventId]!.add(zap);

          // Update target note zap amount
          final targetNote = _noteCache[targetEventId];
          if (targetNote != null) {
            targetNote.zapAmount = _zapsMap[targetEventId]!.fold<int>(0, (sum, z) => sum + z.amount);
            // Schedule UI update with throttling (like legacy)
            _scheduleUIUpdate();
          }

          // Fetch profile for the real zapper (not the wallet)
          _fetchUserProfile(zap.sender);

          debugPrint('[NostrDataService]  Zap processed: ${zap.amount} sats from ${zap.sender} to ${zap.recipient}');
        }
      }
    } catch (e) {
      debugPrint('[NostrDataService] Error processing zap event: $e');
    }
  }

  /// Process notifications for current user
  /// Checks for kind 1, 6, 7, 9735 events where the user's hex pubkey is mentioned
  void _processNotificationFast(Map<String, dynamic> eventData, int kind, String eventAuthor) {
    if (![1, 6, 7, 9735].contains(kind)) return;
    if (_currentUserNpub.isEmpty) return;

    // Get current user's hex pubkey for comparison
    final currentUserHex = _authService.npubToHex(_currentUserNpub);
    if (currentUserHex == null) return;

    final List<dynamic> eventTags = List<dynamic>.from(eventData['tags'] ?? []);
    bool isUserMentioned = false;

    debugPrint('[NostrDataService]  Processing potential notification: kind $kind from $eventAuthor');
    debugPrint('[NostrDataService]  Looking for mentions of user hex: $currentUserHex');

    // Check if current user's hex pubkey is mentioned in p tags
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

      // Convert author hex to npub for consistency
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

  /// Handle relay disconnection
  void _handleRelayDisconnection(String relayUrl) {
    debugPrint('[NostrDataService] Relay disconnected: $relayUrl');
  }

  /// Start cache cleanup timer
  void _startCacheCleanup() {
    Timer.periodic(const Duration(hours: 6), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }

      final now = timeService.now;
      final cutoffTime = now.subtract(_profileCacheTTL);
      _profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));

      // Clean interaction fetch cache
      if (_lastInteractionFetch.length > 1000) {
        final interactionCutoff = now.subtract(const Duration(hours: 1));
        _lastInteractionFetch.removeWhere((key, timestamp) => timestamp.isBefore(interactionCutoff));
      }
    });
  }

  /// Get users list from cache
  List<UserModel> _getUsersList() {
    return _profileCache.entries.map((entry) {
      return UserModel.fromCachedProfile(entry.key, entry.value.data);
    }).toList();
  }

  /// Get notes list from cache with proper sorting (like legacy)
  List<NoteModel> _getNotesList() {
    final notesList = _noteCache.values.toList();

    // Sort with repost timestamp consideration (like legacy)
    notesList.sort((a, b) {
      final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      final result = bTime.compareTo(aTime);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });

    debugPrint('[NostrDataService]  Returning ${notesList.length} sorted notes');
    return notesList;
  }

  /// Schedule UI update with throttling and filtering
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

  /// Get filtered notes list - basit mantık: sadece (!isReply) veya (isReply && isRepost)
  List<NoteModel> _getFilteredNotesList() {
    final allNotes = _noteCache.values.toList();

    debugPrint('[NostrDataService] FILTERING: Starting with ${allNotes.length} notes');

    // Filtering: Sadece normal posts ve reposted replies
    final filteredNotes = allNotes.where((note) {
      debugPrint(' Note ${note.id.substring(0, 8)}: isReply=${note.isReply}, isRepost=${note.isRepost}, repostedBy=${note.repostedBy}');

      // Normal post (reply değil) → göster
      if (!note.isReply) {
        debugPrint('    Including: Normal post (not a reply)');
        return true;
      }

      // Reply ama aynı zamanda repost → göster (reposted reply)
      if (note.isReply && note.isRepost) {
        debugPrint('Including: Reposted reply (isReply=true AND isRepost=true)');
        return true;
      }

      // Standalone reply → gizle
      debugPrint('     Excluding: Standalone reply (isReply=true BUT isRepost=false)');
      return false;
    }).toList();

    // Sort with repost timestamp consideration
    filteredNotes.sort((a, b) {
      final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      final result = bTime.compareTo(aTime);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });

    debugPrint('[NostrDataService] FILTERING RESULT: ${allNotes.length} → ${filteredNotes.length} notes');
    debugPrint('[NostrDataService] Filtered notes breakdown:');
    final normalPosts = filteredNotes.where((n) => !n.isReply && !n.isRepost).length;
    final reposts = filteredNotes.where((n) => !n.isReply && n.isRepost).length;
    final repostedReplies = filteredNotes.where((n) => n.isReply && n.isRepost).length;
    debugPrint(' Normal posts: $normalPosts');
    debugPrint('   Reposts (non-replies): $reposts');
    debugPrint('   Reposted replies: $repostedReplies');

    return filteredNotes;
  }

  /// Fetch user profile with caching
  Future<void> _fetchUserProfile(String npub) async {
    try {
      // Convert npub to hex if needed
      final pubkeyHex = _authService.npubToHex(npub) ?? npub;

      // Check cache first
      final cachedProfile = _profileCache[pubkeyHex];
      final now = timeService.now;

      if (cachedProfile != null && now.difference(cachedProfile.fetchedAt) < _profileCacheTTL) {
        return; // Cache is still valid
      }

      // Create profile filter
      final filter = NostrService.createProfileFilter(
        authors: [pubkeyHex],
        limit: 1,
      );

      // Create request
      final request = NostrService.createRequest(filter);

      // Send request to relays
      await _relayManager.broadcast(NostrService.serializeRequest(request));
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching user profile: $e');
    }
  }

  /// Fetch feed notes according to NIP-02 follow list protocol
  /// Feed mode: Shows notes from followed users (kind 3 follow list)
  /// Profile mode: Shows notes from specific user only
  Future<Result<List<NoteModel>>> fetchFeedNotes({
    required List<String> authorNpubs,
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      // Get current user for feed context
      final currentUser = await _authService.getCurrentUserNpub();
      if (currentUser.isSuccess && currentUser.data != null) {
        _currentUserNpub = currentUser.data!;
      }

      // Convert npubs to hex format
      final authorHexKeys = authorNpubs.map((npub) => _authService.npubToHex(npub)).where((hex) => hex != null).cast<String>().toList();

      List<String> targetAuthors = [];
      bool isFeedMode = false;

      if (authorHexKeys.isEmpty) {
        // Global timeline mode - fetch recent notes from all relays
        debugPrint('[NostrDataService] Fetching global timeline');
        targetAuthors = []; // null authors = global timeline
      } else if (authorHexKeys.length == 1 && authorHexKeys.first == _authService.npubToHex(_currentUserNpub)) {
        // Feed mode: Get NIP-02 follow list FIRST, then fetch their notes
        debugPrint('[NostrDataService] Feed mode - fetching follow list first (NIP-02)');
        isFeedMode = true;

        final currentUserHex = _authService.npubToHex(_currentUserNpub);
        if (currentUserHex == null) {
          debugPrint(' [NostrDataService] Cannot convert current user npub to hex: $_currentUserNpub');
          return const Result.error('Invalid current user npub format');
        }

        debugPrint('[NostrDataService] Current user hex: $currentUserHex');

        // Step 1: Get following list (kind 3 events)
        debugPrint('[NostrDataService]  Getting follow list for: $_currentUserNpub (hex: $currentUserHex)');
        final followingResult = await getFollowingList(_currentUserNpub);

        debugPrint(
            '[NostrDataService]  Follow list result: success=${followingResult.isSuccess}, data=${followingResult.data?.length ?? 0}');

        if (followingResult.isSuccess && followingResult.data != null && followingResult.data!.isNotEmpty) {
          // Step 2: Use the hex pubkeys from follow list for note fetching
          targetAuthors = List<String>.from(followingResult.data!); // These are already hex pubkeys
          targetAuthors.add(currentUserHex); // Add self in hex format
          debugPrint('[NostrDataService] Following list found: ${targetAuthors.length} hex pubkeys');
          debugPrint('[NostrDataService]  Target authors (hex): ${targetAuthors.take(5).toList()}... (showing first 5)');

          // Debug: Show which users we're following
          for (int i = 0; i < targetAuthors.length && i < 10; i++) {
            final hexPubkey = targetAuthors[i];
            final npub = _authService.hexToNpub(hexPubkey) ?? 'unknown';
            debugPrint('[NostrDataService]   - Following[$i]: $hexPubkey -> $npub');
          }
        } else {
          // CRITICAL FIX: No follow list - return empty feed instead of user posts
          debugPrint('[NostrDataService]  No follow list found - returning empty feed');
          debugPrint('[NostrDataService] Follow result error: ${followingResult.error}');
          return Result.success([]); // Return empty feed when no follow list exists
        }
      } else {
        // Profile mode: Show notes from specific users only (already in hex)
        targetAuthors = authorHexKeys;
        debugPrint('[NostrDataService] Profile mode - fetching notes for: ${authorHexKeys.length} hex pubkeys');
        debugPrint('[NostrDataService] Profile authors (hex): $targetAuthors');
      }

      // Create filter for notes according to NIP-01
      final filter = NostrService.createNotesFilter(
        authors: targetAuthors.isEmpty ? null : targetAuthors,
        kinds: [1, 6], // NIP-01 text notes + NIP-18 reposts
        limit: limit,
        since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
        until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
      );

      // Create request and broadcast to relays
      final request = NostrService.createRequest(filter);
      await _relayManager.broadcast(NostrService.serializeRequest(request));

      // Wait for relay responses if cache is empty
      final cachedNotes = _getNotesList();
      if (cachedNotes.isEmpty) {
        debugPrint('[NostrDataService] Cache empty, waiting for relay responses...');

        // Wait up to 3 seconds for relay responses
        final completer = Completer<List<NoteModel>>();
        late StreamSubscription subscription;

        subscription = _notesController.stream.listen((notes) {
          if (notes.isNotEmpty && !completer.isCompleted) {
            debugPrint('[NostrDataService] Received ${notes.length} notes from relays');
            completer.complete(notes);
          }
        });

        // Set timeout
        Timer(const Duration(seconds: 3), () {
          if (!completer.isCompleted) {
            debugPrint('[NostrDataService] Timeout waiting for relay responses');
            completer.complete([]); // Return empty list on timeout
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

      // Return cached notes if available
      debugPrint('[NostrDataService] Returning ${cachedNotes.length} cached notes');

      // Apply follow list filtering for feed mode
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

  /// Fetch profile notes for specific user only (not their follows)
  /// Used in profile mode according to user requirements
  /// COMPLETELY BYPASSES feed filtering - shows ALL user content regardless of follow status
  Future<Result<List<NoteModel>>> fetchProfileNotes({
    required String userNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      debugPrint('[NostrDataService] PROFILE MODE: Fetching notes for $userNpub (bypassing ALL feed filters)');

      // Convert npub to hex format
      final pubkeyHex = _authService.npubToHex(userNpub);
      if (pubkeyHex == null) {
        return const Result.error('Invalid npub format');
      }

      // Create filter for user's notes only (NIP-01)
      final filter = NostrService.createNotesFilter(
        authors: [pubkeyHex], // Only this specific user
        kinds: [1, 6], // NIP-01 text notes + NIP-18 reposts
        limit: limit,
        since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
        until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
      );

      // PROFILE MODE: Direct relay connection with isolated event handling
      final profileNotes = <NoteModel>[];
      final limitedRelays = _relayManager.relayUrls.take(3).toList();

      debugPrint('[NostrDataService] PROFILE: Using ${limitedRelays.length} relays for direct fetch');

      await Future.wait(limitedRelays.map((relayUrl) async {
        WebSocket? ws;
        StreamSubscription? sub;
        try {
          debugPrint('[NostrDataService] PROFILE: Connecting to $relayUrl');
          ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
          if (_isClosed) {
            await ws.close();
            return;
          }

          final completer = Completer<void>();
          bool hasReceivedEvents = false;

          sub = ws.listen((event) {
            try {
              final decoded = jsonDecode(event);

              if (decoded[0] == 'EVENT') {
                hasReceivedEvents = true;
                final eventData = decoded[2] as Map<String, dynamic>;
                final eventId = eventData['id'] as String;
                final eventAuthor = eventData['pubkey'] as String;
                final eventKind = eventData['kind'] as int;

                debugPrint('[NostrDataService] PROFILE: Received event $eventId from $relayUrl');

                // PROFILE MODE: Accept ALL notes from this user, NO FEED FILTERING
                if (eventAuthor == pubkeyHex && (eventKind == 1 || eventKind == 6)) {
                  // Check for duplicates
                  if (!profileNotes.any((n) => n.id == eventId)) {
                    final note = _processProfileEventDirectly(eventData, userNpub);
                    if (note != null) {
                      profileNotes.add(note);

                      // CRITICAL: Also add to main cache for ThreadPage access
                      if (!_noteCache.containsKey(eventId) && !_eventIds.contains(eventId)) {
                        _noteCache[eventId] = note;
                        _eventIds.add(eventId);
                        debugPrint('[NostrDataService] PROFILE: Also added ${eventId.substring(0, 8)}... to main cache for thread access');
                      }

                      debugPrint('[NostrDataService] PROFILE: Added note ${eventId.substring(0, 8)}... to profile list');
                    }
                  }
                }
              } else if (decoded[0] == 'EOSE') {
                debugPrint('[NostrDataService] PROFILE: EOSE received from $relayUrl');
                if (!completer.isCompleted) completer.complete();
              }
            } catch (e) {
              debugPrint('[NostrDataService] PROFILE: Error processing event: $e');
            }
          }, onDone: () {
            if (!completer.isCompleted) completer.complete();
          }, onError: (error) {
            debugPrint('[NostrDataService] PROFILE: Connection error: $error');
            if (!completer.isCompleted) completer.complete();
          }, cancelOnError: true);

          if (ws.readyState == WebSocket.open) {
            ws.add(NostrService.serializeRequest(NostrService.createRequest(filter)));
          }

          await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
            debugPrint('[NostrDataService] PROFILE: Timeout waiting for notes from $relayUrl');
          });

          await sub.cancel();
          await ws.close();

          debugPrint('[NostrDataService] PROFILE: Finished $relayUrl, received ${hasReceivedEvents ? 'events' : 'no events'}');
        } catch (e) {
          debugPrint('[NostrDataService] PROFILE: Exception with relay $relayUrl: $e');
          await sub?.cancel();
          await ws?.close();
        }
      }));

      // Sort profile notes by timestamp
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

      // Trigger UI update so other components know about the new notes in cache
      _scheduleUIUpdate();

      return Result.success(limitedNotes);
    } catch (e) {
      debugPrint('[NostrDataService] PROFILE: Error fetching profile notes: $e');
      return Result.error('Failed to fetch profile notes: $e');
    }
  }

  /// Process event directly for profile mode (bypasses all feed filtering)
  NoteModel? _processProfileEventDirectly(Map<String, dynamic> eventData, String userNpub) {
    try {
      final pubkey = eventData['pubkey'] as String;
      final createdAt = eventData['created_at'] as int;
      final kind = eventData['kind'] as int;

      final authorNpub = _authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      if (kind == 1) {
        // Text note
        return _processKind1ForProfile(eventData, authorNpub, timestamp);
      } else if (kind == 6) {
        // Repost
        return _processKind6ForProfile(eventData, authorNpub, timestamp);
      }

      return null;
    } catch (e) {
      debugPrint('[NostrDataService] PROFILE: Error processing event: $e');
      return null;
    }
  }

  /// Process kind 1 event for profile mode
  NoteModel? _processKind1ForProfile(Map<String, dynamic> eventData, String authorNpub, DateTime timestamp) {
    try {
      final id = eventData['id'] as String;
      final content = eventData['content'] as String;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      // Parse reply structure
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

  /// Process kind 6 event (repost) for profile mode
  NoteModel? _processKind6ForProfile(Map<String, dynamic> eventData, String reposterNpub, DateTime timestamp) {
    try {
      final id = eventData['id'] as String;
      final content = eventData['content'] as String? ?? '';
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      // Find original event and original author from tags
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

      // Try to extract original content from repost content
      if (content.isNotEmpty) {
        try {
          final originalContent = jsonDecode(content) as Map<String, dynamic>;
          displayContent = originalContent['content'] as String? ?? displayContent;

          if (originalAuthorHex != null) {
            displayAuthor = _authService.hexToNpub(originalAuthorHex) ?? originalAuthorHex;
          }

          // Check if original is a reply
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

  /// Fetch user profile
  Future<Result<UserModel>> fetchUserProfile(String npub) async {
    try {
      // Convert npub to hex
      final pubkeyHex = _authService.npubToHex(npub);
      if (pubkeyHex == null) {
        return const Result.error('Invalid npub format');
      }

      // Check cache first
      final cachedProfile = _profileCache[pubkeyHex];
      final now = timeService.now;

      if (cachedProfile != null && now.difference(cachedProfile.fetchedAt) < _profileCacheTTL) {
        final user = UserModel.fromCachedProfile(pubkeyHex, cachedProfile.data);
        return Result.success(user);
      }

      // Fetch from network
      await _fetchUserProfile(npub);

      // Wait a bit for response
      await Future.delayed(const Duration(milliseconds: 500));

      // Check cache again
      final updatedProfile = _profileCache[pubkeyHex];
      if (updatedProfile != null) {
        final user = UserModel.fromCachedProfile(pubkeyHex, updatedProfile.data);
        return Result.success(user);
      }

      // Return basic profile if not found
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

  /// Post a note - mimics legacy DataService.shareNote
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

      // Create note event (like legacy DataService.shareNote)
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

      // Ensure relay connections (like legacy DataService.initializeConnections)
      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [], // Empty target for global
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'note_post',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      // Broadcast IMMEDIATELY to relays (like working code)
      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));
      debugPrint('[NostrDataService] Note broadcasted IMMEDIATELY to ${_relayManager.activeSockets.length} relays');

      // Create note model for immediate UI update (like legacy)
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

      // Add to cache immediately (like legacy)
      _noteCache[note.id] = note;
      _eventIds.add(note.id);
      // Schedule UI update with throttling (like legacy)
      _scheduleUIUpdate();

      debugPrint('[NostrDataService] Note posted and cached successfully');
      return Result.success(note);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error posting note: $e');
      return Result.error('Failed to post note: $e');
    }
  }

  /// React to a note
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

      // Create reaction event
      final event = NostrService.createReactionEvent(
        targetEventId: noteId,
        content: reaction,
        privateKey: privateKey,
      );

      // Add optimistic reaction ID to prevent duplicate processing
      _pendingOptimisticReactionIds.add(event.id);

      // Broadcast IMMEDIATELY to relays (like working code)
      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));

      // Create optimistic reaction for immediate UI update
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

      // Update note reaction count
      final note = _noteCache[noteId];
      if (note != null) {
        note.reactionCount = _reactionsMap[noteId]!.length;
        // Schedule UI update with throttling (like legacy)
        _scheduleUIUpdate();
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to react to note: $e');
    }
  }

  /// Repost a note - mimics legacy DataService.sendRepost
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

      // Get original note for content (like legacy)
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

      // Create repost event (like legacy DataService.sendRepost)
      final event = NostrService.createRepostEvent(
        noteId: noteId,
        noteAuthor: _authService.npubToHex(noteAuthor) ?? noteAuthor,
        content: repostContent,
        privateKey: privateKey,
      );

      // Ensure relay connections (like legacy)
      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [], // Empty target for global
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'repost',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      // Broadcast IMMEDIATELY to relays (like working code)
      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));
      debugPrint('[NostrDataService] Repost broadcasted IMMEDIATELY to ${_relayManager.activeSockets.length} relays');

      // Simplified: No separate repost tracking, just update UI
      _scheduleUIUpdate();

      debugPrint('[NostrDataService] Repost completed successfully');
      return const Result.success(null);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error reposting note: $e');
      return Result.error('Failed to repost note: $e');
    }
  }

  /// Post a reply - EXACTLY like working DataService.sendReply
  Future<Result<NoteModel>> postReply({
    required String content,
    required String rootId,
    String? replyId,
    required String parentAuthor,
    required List<String> relayUrls,
  }) async {
    try {
      // EXACTLY like working code - use parentEventId as primary reference
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

      // Find parent note EXACTLY like working code
      final parentNote = _noteCache.values.where((note) => note.id == parentEventId).firstOrNull;

      if (parentNote == null) {
        debugPrint('[NostrDataService] Parent note not found: $parentEventId');
        return const Result.error('Parent note not found.');
      }

      debugPrint('[NostrDataService] Found parent note: ${parentNote.id}');
      debugPrint('[NostrDataService] Parent note author: ${parentNote.author}');
      debugPrint('[NostrDataService] Building reply tags EXACTLY like working code...');

      // Calculate rootId and replyId EXACTLY like working code
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

      // Manual tag building EXACTLY like working code - DON'T use NostrService.createReplyTags!
      List<List<String>> tags = [];

      // Build eTags and pTags for NoteModel based on working format
      final List<Map<String, String>> eTags = [];
      final List<Map<String, String>> pTags = [];

      // Build tags EXACTLY like working code - use parentNote.author directly
      final authorHex = _authService.npubToHex(parentNote.author) ?? parentNote.author; // Convert to hex format

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

      // Collect mentioned pubkeys EXACTLY like working code - HEX FORMAT!
      Set<String> mentionedPubkeys = {authorHex};

      if (parentNote.pTags.isNotEmpty == true) {
        for (final pTag in parentNote.pTags) {
          if (pTag['pubkey'] != null && pTag['pubkey']!.isNotEmpty) {
            mentionedPubkeys.add(pTag['pubkey']!);
          }
        }
      }

      // Add p tags EXACTLY like working code - HEX FORMAT!
      for (final pubkey in mentionedPubkeys) {
        tags.add(['p', pubkey]);
        pTags.add({
          'pubkey': pubkey,
          'relayUrl': '',
          'petname': '',
        });
      }

      debugPrint('[NostrDataService] Creating NIP-10 compliant reply event...');

      // Create reply event (like legacy)
      final event = NostrService.createReplyEvent(
        content: content,
        privateKey: privateKey,
        tags: tags,
      );

      // Direct WebSocket broadcast EXACTLY like working code
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

      // Create reply model for immediate UI update (like legacy)
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

      // Add to cache immediately (like legacy)
      _noteCache[reply.id] = reply;
      _eventIds.add(reply.id);
      // Schedule UI update with throttling (like legacy)
      _scheduleUIUpdate();

      // Simplified: No separate reply tracking

      debugPrint('[NostrDataService] NIP-10 compliant reply posted successfully');
      return Result.success(reply);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error posting reply: $e');
      return Result.error('Failed to post reply: $e');
    }
  }

  /// Update user profile - mimics legacy DataService.sendProfileEdit
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

      // Create profile content (like legacy DataService)
      final Map<String, dynamic> profileContent = {
        'name': user.name,
        'about': user.about,
        'picture': user.profileImage,
      };

      // Add optional fields only if they're not empty (like legacy)
      if (user.nip05.isNotEmpty) profileContent['nip05'] = user.nip05;
      if (user.banner.isNotEmpty) profileContent['banner'] = user.banner;
      if (user.lud16.isNotEmpty) profileContent['lud16'] = user.lud16;
      if (user.website.isNotEmpty) profileContent['website'] = user.website;

      debugPrint('[NostrDataService] Profile content: $profileContent');

      // Create profile event (kind 0)
      final event = NostrService.createProfileEvent(
        profileContent: profileContent,
        privateKey: privateKey,
      );

      debugPrint('[NostrDataService] Profile event created, broadcasting to relays...');

      // Ensure we have relay connections (like legacy DataService.initializeConnections)
      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [], // Empty target for global
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'profile_update',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      // Broadcast IMMEDIATELY to relays (like working code)
      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));
      debugPrint('[NostrDataService] Profile event broadcasted IMMEDIATELY to ${_relayManager.activeSockets.length} relays');

      // Update cache immediately with proper format (like legacy)
      final eventJson = NostrService.eventToJson(event);
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(eventJson['created_at'] * 1000);
      final pubkeyHex = eventJson['pubkey'] as String;

      // Create updated user model
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
        nip05Verified: false, // Will be verified later asynchronously
      );

      // Update profile cache (like legacy profileCache)
      _profileCache[pubkeyHex] = CachedProfile(
        profileContent.map((key, value) => MapEntry(key, value.toString())),
        updatedAt,
      );

      // Emit updated users list
      _usersController.add(_getUsersList());

      debugPrint('[NostrDataService] Profile updated and cached successfully.');
      return Result.success(updatedUser);
    } catch (e, st) {
      debugPrint('[NostrDataService ERROR] Error updating profile: $e\n$st');
      return Result.error('Failed to update profile: $e');
    }
  }

  /// Fetch notifications for current user
  /// Fetches kind 1, 6, 7, 9735 events where the logged-in user's hex pubkey is mentioned
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

      // Calculate since timestamp
      int? sinceTimestamp;
      if (since != null) {
        sinceTimestamp = since.millisecondsSinceEpoch ~/ 1000;
      } else {
        // Default to last 24 hours for notifications
        sinceTimestamp = timeService.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
      }

      debugPrint('[NostrDataService]  Notification filter since: $sinceTimestamp');

      // Create filter that looks for events mentioning the user's hex pubkey
      // This covers: mentions (kind 1), reposts (kind 6), reactions (kind 7), zaps (kind 9735)
      final filter = {
        'kinds': [1, 6, 7, 9735], // mentions, reposts, reactions, zaps
        '#p': [pubkeyHex], // Events that mention the user in p tags
        'since': sinceTimestamp,
        'limit': limit,
      };

      // Create request with unique subscription ID
      final subscriptionId = 'notifications_${DateTime.now().millisecondsSinceEpoch}';
      final request = ['REQ', subscriptionId, filter];

      debugPrint('[NostrDataService]  Broadcasting notification request: $request');

      // Send request to relays
      await _relayManager.broadcast(jsonEncode(request));

      // Wait for relay responses for a short time
      await Future.delayed(const Duration(seconds: 2));

      // Return current cached notifications for this user
      final notifications = _notificationCache[_currentUserNpub] ?? [];

      debugPrint('[NostrDataService]  Returning ${notifications.length} cached notifications');

      return Result.success(notifications.take(limit).toList());
    } catch (e) {
      debugPrint('[NostrDataService]  Error fetching notifications: $e');
      return Result.error('Failed to fetch notifications: $e');
    }
  }

  /// Get following list for a user
  Future<Result<List<String>>> getFollowingList(String npub) async {
    try {
      final pubkeyHex = _authService.npubToHex(npub) ?? npub;
      debugPrint('[NostrDataService] Getting follow list for npub: $npub');
      debugPrint('[NostrDataService] Converted to hex: $pubkeyHex');

      // Create following filter
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
                        following.add(followedHexPubkey); // Store as hex pubkey
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

      // Debug: Show final follow list
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

  /// Fetch a specific note by ID from relays - Enhanced version for Thread Pages
  Future<bool> fetchSpecificNote(String noteId) async {
    try {
      debugPrint('[NostrDataService] THREAD: Fetching specific note: $noteId');

      // Check if we already have this note in cache
      if (_noteCache.containsKey(noteId)) {
        debugPrint('[NostrDataService] THREAD: Note already in cache: $noteId');
        return true;
      }

      // Use direct relay connections for critical thread note fetching
      final limitedRelays = _relayManager.relayUrls.take(3).toList();
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

          // Create filter for specific note
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
                  // Process this note regardless of feed filtering (for thread access)
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

          await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {
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

  /// Fetch multiple notes by IDs - batch version for better performance
  Future<void> fetchSpecificNotes(List<String> noteIds) async {
    try {
      if (noteIds.isEmpty) return;

      debugPrint('[NostrDataService] Fetching ${noteIds.length} specific notes...');

      // Filter out notes that are already in cache
      final notesToFetch = noteIds.where((id) => !_noteCache.containsKey(id)).toList();

      if (notesToFetch.isEmpty) {
        debugPrint('[NostrDataService] All notes already in cache');
        return;
      }

      debugPrint('[NostrDataService]  Need to fetch ${notesToFetch.length} notes');

      // Create filter for batch fetching
      final filter = NostrService.createEventByIdFilter(eventIds: notesToFetch);
      final request = NostrService.createRequest(filter);

      // Broadcast to relays
      await _relayManager.broadcast(NostrService.serializeRequest(request));

      debugPrint('[NostrDataService] Batch note request sent for ${notesToFetch.length} notes');
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching specific notes: $e');
    }
  }

  /// Get cached notes
  List<NoteModel> get cachedNotes => _getNotesList();

  /// Get cached users
  List<UserModel> get cachedUsers => _getUsersList();

  /// Fetch interactions for notes (reactions, replies, reposts, zaps)
  /// This mirrors the legacy DataService behavior
  Future<void> _fetchInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    debugPrint('[NostrDataService] Fetching interactions for ${noteIds.length} notes...');

    try {
      // Batch the noteIds for efficient fetching
      const batchSize = 12;

      for (int i = 0; i < noteIds.length; i += batchSize) {
        final batch = noteIds.skip(i).take(batchSize).toList();

        // Fetch all interaction types in parallel for this batch
        await Future.wait([
          _fetchReactionsForBatch(batch),
          _fetchRepliesForBatch(batch),
          _fetchRepostsForBatch(batch),
          _fetchZapsForBatch(batch),
        ], eagerError: false);

        // Small delay between batches to avoid overwhelming relays
        if (i + batchSize < noteIds.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      debugPrint('[NostrDataService] Interaction fetching completed for ${noteIds.length} notes');
    } catch (e) {
      debugPrint('[NostrDataService] Error fetching interactions: $e');
    }
  }

  /// Fetch reactions for batch of note IDs
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

  /// Fetch replies for batch of note IDs
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

  /// Fetch reposts for batch of note IDs
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

  /// Fetch zaps for batch of note IDs
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

  /// Public method to fetch interactions for thread/specific notes (like legacy)
  /// Used by ThreadViewModel for intensive interaction loading
  /// Set forceLoad=true to actually fetch interactions (like legacy pattern)
  Future<void> fetchInteractionsForNotes(List<String> noteIds, {bool forceLoad = false}) async {
    if (_isClosed || noteIds.isEmpty) return;

    if (!forceLoad) {
      debugPrint('[NostrDataService] Automatic interaction fetching disabled - use forceLoad=true for thread pages only');
      return;
    }

    debugPrint('[NostrDataService] Manual interaction fetching for ${noteIds.length} notes');

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

      // Update note counts after fetch
      for (final eventId in noteIdsToFetch) {
        final note = _noteCache[eventId];
        if (note != null) {
          note.reactionCount = _reactionsMap[eventId]?.length ?? 0;
          note.replyCount = 0;
          note.repostCount = _repostsMap[eventId]?.length ?? 0;
          note.zapAmount = _zapsMap[eventId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
        }
      }

      // Schedule UI update after interaction fetch
      _scheduleUIUpdate();

      debugPrint('[NostrDataService] Manual interaction fetching completed for ${noteIdsToFetch.length} notes');
    }

    // Clean up interaction fetch cache if it gets too large
    if (_lastInteractionFetch.length > 1000) {
      final cutoffTime = now.subtract(const Duration(hours: 1));
      _lastInteractionFetch.removeWhere((key, timestamp) => timestamp.isBefore(cutoffTime));
    }
  }

  /// Post a quote note - mimics legacy DataService.sendQuote
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

      // Create quote event (like legacy DataService.sendQuote)
      final event = NostrService.createQuoteEvent(
        content: content,
        quotedEventId: quotedEventId,
        quotedEventPubkey: quotedEventPubkey,
        relayUrl: relayUrl,
        privateKey: privateKey,
        additionalTags: additionalTags,
      );

      // Ensure relay connections (like legacy)
      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [], // Empty target for global
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'quote_post',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      // Broadcast IMMEDIATELY to relays (like working code)
      await _relayManager.priorityBroadcastToAll(NostrService.serializeEvent(event));
      debugPrint('[NostrDataService] Quote note broadcasted IMMEDIATELY to ${_relayManager.activeSockets.length} relays');

      // Create note model for immediate UI update (like legacy)
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

      // Add to cache immediately (like legacy)
      _noteCache[note.id] = note;
      _eventIds.add(note.id);
      // Schedule UI update with throttling (like legacy)
      _scheduleUIUpdate();

      debugPrint('[NostrDataService] Quote note posted successfully');
      return Result.success(note);
    } catch (e) {
      debugPrint('[NostrDataService ERROR] Error posting quote: $e');
      return Result.error('Failed to post quote: $e');
    }
  }

  /// Send media to Blossom server - mimics legacy DataService.sendMedia
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

      // Determine MIME type (like legacy)
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

      // Create Blossom auth event (kind 24242) - like legacy
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

      // Upload to Blossom server (like legacy)
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

  /// Publish follow event (kind 3) to relays
  /// Used by UserRepository for follow/unfollow operations
  Future<Result<void>> publishFollowEvent({
    required List<String> followingHexList,
    required String privateKey,
  }) async {
    try {
      debugPrint('[NostrDataService] Publishing kind 3 follow event with ${followingHexList.length} following');

      // Get current user for cache update (like working code)
      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user not found');
      }

      final currentUserNpub = currentUserResult.data!;

      // Ensure relay connections EXACTLY like working code
      try {
        if (_relayManager.activeSockets.isEmpty) {
          debugPrint('[NostrDataService] No active relay connections, attempting to connect...');
          await _relayManager.connectRelays(
            [], // Empty target for global
            onEvent: _handleRelayEvent,
            onDisconnected: _handleRelayDisconnection,
            serviceId: 'follow_event',
          );
        }
      } catch (e) {
        debugPrint('[NostrDataService] Relay connection failed: $e, continuing anyway');
      }

      // Create kind 3 follow event using NostrService
      final event = NostrService.createFollowEvent(
        followingPubkeys: followingHexList,
        privateKey: privateKey,
      );

      // Direct WebSocket broadcast EXACTLY like working code
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

      // Update local follow cache EXACTLY like working code
      _followingCache[currentUserNpub] = followingHexList;
      _followingCacheTime[currentUserNpub] = DateTime.now();

      debugPrint('[NostrDataService] Follow event broadcasted DIRECTLY and cached locally');
      debugPrint('[NostrDataService] Updated follow cache for $currentUserNpub: ${followingHexList.length} following');

      return const Result.success(null);
    } catch (e) {
      debugPrint('[NostrDataService] Failed to publish follow event: $e');
      return Result.error('Failed to publish follow event: $e');
    }
  }

  /// Clear all caches
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

  /// Get reactions for specific note - for NoteStatisticsPage
  List<ReactionModel> getReactionsForNote(String noteId) {
    return _reactionsMap[noteId] ?? [];
  }

  /// Get reposts for specific note - for NoteStatisticsPage
  List<ReactionModel> getRepostsForNote(String noteId) {
    return _repostsMap[noteId] ?? [];
  }

  /// Get zaps for specific note - for NoteStatisticsPage
  List<ZapModel> getZapsForNote(String noteId) {
    return _zapsMap[noteId] ?? [];
  }

  /// Get all interaction maps for debugging
  Map<String, List<ReactionModel>> get reactionsMap => Map.unmodifiable(_reactionsMap);
  Map<String, List<ReactionModel>> get repostsMap => Map.unmodifiable(_repostsMap);
  Map<String, List<ZapModel>> get zapsMap => Map.unmodifiable(_zapsMap);

  /// Filter notes by follow list for feed mode
  /// Shows only:
  /// 1. Original posts from followed authors (excluding standalone replies)
  /// 2. Reposts (including reposted replies) where the reposter is in the follow list
  /// 3. Standalone replies are NEVER shown, only reposted replies
  List<NoteModel> _filterNotesByFollowList(List<NoteModel> notes, List<String> followedHexPubkeys) {
    debugPrint('[NostrDataService] Filtering ${notes.length} notes by follow list with ${followedHexPubkeys.length} followed users');

    final filteredNotes = notes.where((note) {
      // PRIORITY: Show reposts (including reposted replies) from followed users
      if (note.isRepost && note.repostedBy != null) {
        // For reposts: Check if the REPOSTER is in follow list
        final reposterHex = _authService.npubToHex(note.repostedBy!) ?? note.repostedBy!;
        final isReposterFollowed = followedHexPubkeys.contains(reposterHex);

        debugPrint(
            '[NostrDataService] Repost${note.isReply ? " (reply)" : ""} by ${note.repostedBy} (hex: $reposterHex), followed: $isReposterFollowed');
        return isReposterFollowed;
      }

      // EXCLUDE all standalone replies (only reposted replies should be shown)
      if (note.isReply) {
        debugPrint('[NostrDataService] Excluding standalone reply: ${note.id}');
        return false;
      }

      // For original posts (non-replies): Check if the AUTHOR is in follow list
      final noteAuthorHex = _authService.npubToHex(note.author) ?? note.author;
      final isAuthorFollowed = followedHexPubkeys.contains(noteAuthorHex);

      debugPrint('[NostrDataService] Original post by ${note.author} (hex: $noteAuthorHex), followed: $isAuthorFollowed');
      return isAuthorFollowed;
    }).toList();

    debugPrint('[NostrDataService] Filtered result: ${filteredNotes.length} notes (${notes.length - filteredNotes.length} excluded)');
    return filteredNotes;
  }

  /// Dispose service
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

/// Cached profile with TTL
class CachedProfile {
  final Map<String, String> data;
  final DateTime fetchedAt;

  CachedProfile(this.data, this.fetchedAt);
}

/// Parse amount from bolt11 invoice
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
