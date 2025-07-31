import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/zap_model.dart';
import '../models/notification_model.dart';
import '../models/following_model.dart';
import '../models/user_model.dart';
import 'cache_service.dart';
import 'profile_service.dart';

class EventHandlerService {
  final CacheService _cacheService;
  final ProfileService _profileService;
  final String npub;

  // Callbacks
  final Function(String, List<ReactionModel>)? onReactionsUpdated;
  final Function(String, List<ReplyModel>)? onRepliesUpdated;
  final Function(String, List<RepostModel>)? onRepostsUpdated;
  final Function(NoteModel)? onNewNote;

  // Event batching for performance
  final Queue<Map<String, dynamic>> _pendingEvents = Queue();
  Timer? _batchTimer;
  bool _isProcessing = false;

  // Performance metrics
  int _eventsProcessed = 0;
  int _eventsSkipped = 0;
  final Map<String, int> _eventTypeCounts = {};

  // Deduplication
  final Set<String> _processedEventIds = {};
  Timer? _cleanupTimer;

  EventHandlerService({
    required CacheService cacheService,
    required ProfileService profileService,
    required this.npub,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
    this.onRepostsUpdated,
    this.onNewNote,
  })  : _cacheService = cacheService,
        _profileService = profileService {
    _startBatchProcessing();
    _startPeriodicCleanup();
  }

  void _startBatchProcessing() {
    _batchTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _processPendingEvents();
    });
  }

  void _startPeriodicCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _cleanupProcessedEvents();
    });
  }

  void _cleanupProcessedEvents() {
    // Keep only recent event IDs to prevent memory bloat
    if (_processedEventIds.length > 10000) {
      final idsToRemove = _processedEventIds.take(_processedEventIds.length - 5000);
      _processedEventIds.removeAll(idsToRemove);
    }
  }

  void addEventToBatch(Map<String, dynamic> eventData) {
    final eventId = eventData['id'] as String?;
    if (eventId != null && _processedEventIds.contains(eventId)) {
      _eventsSkipped++;
      return;
    }

    _pendingEvents.add(eventData);

    // Process immediately if queue is getting large
    if (_pendingEvents.length >= 20) {
      _processPendingEvents();
    }
  }

  // INSTANT PROCESSING FOR USER INTERACTIONS
  // Process user events immediately without batching delays

  // Process user reaction
  Future<void> processUserReaction(Map<String, dynamic> eventData) async {
    final eventId = eventData['id'] as String?;
    if (eventId != null && _processedEventIds.contains(eventId)) {
      return;
    }

    if (eventId != null) {
      _processedEventIds.add(eventId);
    }

    await handleReactionEvent(eventData);
    _eventsProcessed++;
    print('[EventHandler] User reaction processed: $eventId');
  }

  // Process user reply
  Future<void> processUserReply(Map<String, dynamic> eventData, String parentEventId) async {
    final eventId = eventData['id'] as String?;
    if (eventId != null && _processedEventIds.contains(eventId)) {
      return;
    }

    if (eventId != null) {
      _processedEventIds.add(eventId);
    }

    await handleReplyEvent(eventData, parentEventId);
    _eventsProcessed++;
    print('[EventHandler] User reply processed: $eventId');
  }

  // Process user repost
  Future<void> processUserRepost(Map<String, dynamic> eventData) async {
    final eventId = eventData['id'] as String?;
    if (eventId != null && _processedEventIds.contains(eventId)) {
      return;
    }

    if (eventId != null) {
      _processedEventIds.add(eventId);
    }

    await handleRepostEvent(eventData);
    _eventsProcessed++;
    print('[EventHandler] User repost processed: $eventId');
  }

  // Process user note
  Future<void> processUserNote(Map<String, dynamic> eventData) async {
    final eventId = eventData['id'] as String?;
    if (eventId != null && _processedEventIds.contains(eventId)) {
      return;
    }

    if (eventId != null) {
      _processedEventIds.add(eventId);
    }

    await _handleNoteOrReply(eventData);
    _eventsProcessed++;
    print('[EventHandler] User note processed: $eventId');
  }

  // Process user zap
  Future<void> processUserZap(Map<String, dynamic> eventData) async {
    final eventId = eventData['id'] as String?;
    if (eventId != null && _processedEventIds.contains(eventId)) {
      return;
    }

    if (eventId != null) {
      _processedEventIds.add(eventId);
    }

    await handleZapEvent(eventData);
    _eventsProcessed++;
    print('[EventHandler] User zap processed: $eventId');
  }

  Future<void> processUserEventInstantly(Map<String, dynamic> eventData) async {
    final eventId = eventData['id'] as String?;
    final kind = eventData['kind'] as int?;

    if (eventId == null || kind == null) return;

    if (_processedEventIds.contains(eventId)) {
      return;
    }

    _processedEventIds.add(eventId);
    _eventsProcessed++;

    final eventType = _getEventTypeName(kind);
    _eventTypeCounts[eventType] = (_eventTypeCounts[eventType] ?? 0) + 1;

    switch (kind) {
      case 7: // Reaction
        await handleReactionEvent(eventData);
        break;
      case 6: // Repost
        await handleRepostEvent(eventData);
        break;
      case 1: // Note/Reply
        await _handleNoteOrReply(eventData);
        break;
      case 9735: // Zap
        await handleZapEvent(eventData);
        break;
      case 0: // Profile
        await handleProfileEvent(eventData);
        break;
      case 3: // Following
        await handleFollowingEvent(eventData);
        break;
      default:
        break;
    }

    print('[EventHandler] User $eventType processed: $eventId');
  }

  void _processPendingEvents() {
    if (_isProcessing || _pendingEvents.isEmpty) return;

    _isProcessing = true;

    final eventsToProcess = <Map<String, dynamic>>[];
    while (_pendingEvents.isNotEmpty && eventsToProcess.length < 10) {
      eventsToProcess.add(_pendingEvents.removeFirst());
    }

    Future.microtask(() async {
      try {
        for (final eventData in eventsToProcess) {
          await _processEvent(eventData);
        }
      } finally {
        _isProcessing = false;
      }
    });
  }

  Future<void> _processEvent(Map<String, dynamic> eventData) async {
    final eventId = eventData['id'] as String?;
    final kind = eventData['kind'] as int?;

    if (eventId == null || kind == null) return;

    if (_processedEventIds.contains(eventId)) {
      _eventsSkipped++;
      return;
    }

    _processedEventIds.add(eventId);
    _eventsProcessed++;

    final eventType = _getEventTypeName(kind);
    _eventTypeCounts[eventType] = (_eventTypeCounts[eventType] ?? 0) + 1;

    switch (kind) {
      case 7: // Reaction
        await handleReactionEvent(eventData);
        break;
      case 6: // Repost
        await handleRepostEvent(eventData);
        break;
      case 1: // Note/Reply
        await _handleNoteOrReply(eventData);
        break;
      case 9735: // Zap
        await handleZapEvent(eventData);
        break;
      case 0: // Profile
        await handleProfileEvent(eventData);
        break;
      case 3: // Following
        await handleFollowingEvent(eventData);
        break;
      default:
        // Handle other event types if needed
        break;
    }
  }

  String _getEventTypeName(int kind) {
    switch (kind) {
      case 0:
        return 'profile';
      case 1:
        return 'note';
      case 3:
        return 'following';
      case 6:
        return 'repost';
      case 7:
        return 'reaction';
      case 9735:
        return 'zap';
      default:
        return 'other';
    }
  }

  Future<void> _handleNoteOrReply(Map<String, dynamic> eventData) async {
    // Check if it's a reply by looking for 'e' tags
    final tags = eventData['tags'] as List<dynamic>? ?? [];
    String? parentEventId;

    for (var tag in tags) {
      if (tag is List && tag.length >= 2 && tag[0] == 'e') {
        parentEventId = tag[1] as String;
        break;
      }
    }

    if (parentEventId != null) {
      await handleReplyEvent(eventData, parentEventId);
    }
    // Note: Regular notes are typically handled elsewhere in the app
  }

  Future<void> handleReactionEvent(Map<String, dynamic> eventData) async {
    try {
      String? targetEventId;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      for (var tag in tags) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          targetEventId = tag[1] as String;
          break;
        }
      }
      if (targetEventId == null) return;

      final reaction = ReactionModel.fromEvent(eventData);

      // Efficient duplicate check
      final existingReactions = _cacheService.reactionsMap[targetEventId];
      if (existingReactions != null && existingReactions.any((r) => r.id == reaction.id)) {
        return; // Already exists
      }

      _cacheService.reactionsMap.putIfAbsent(targetEventId, () => []);
      _cacheService.reactionsMap[targetEventId]!.add(reaction);

      // Batch save to reduce I/O
      final reactionsBox = _cacheService.reactionsBox;
      if (reactionsBox != null) {
        unawaited(reactionsBox.put(reaction.id, reaction));
      }

      onReactionsUpdated?.call(targetEventId, _cacheService.reactionsMap[targetEventId]!);

      // Batch profile fetching
      unawaited(_profileService.batchFetchProfiles([reaction.author]));
    } catch (e) {
      print('[EventHandler ERROR] Error handling reaction event: $e');
    }
  }

  Future<void> handleRepostEvent(Map<String, dynamic> eventData) async {
    try {
      String? originalNoteId;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      for (var tag in tags) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          originalNoteId = tag[1] as String;
          break;
        }
      }
      if (originalNoteId == null) return;

      final repost = RepostModel.fromEvent(eventData, originalNoteId);

      // Efficient duplicate check
      final existingReposts = _cacheService.repostsMap[originalNoteId];
      if (existingReposts != null && existingReposts.any((r) => r.id == repost.id)) {
        return; // Already exists
      }

      _cacheService.repostsMap.putIfAbsent(originalNoteId, () => []);
      _cacheService.repostsMap[originalNoteId]!.add(repost);

      // Batch save to reduce I/O
      final repostsBox = _cacheService.repostsBox;
      if (repostsBox != null) {
        unawaited(repostsBox.put(repost.id, repost));
      }

      onRepostsUpdated?.call(originalNoteId, _cacheService.repostsMap[originalNoteId]!);

      // Batch profile fetching
      unawaited(_profileService.batchFetchProfiles([repost.repostedBy]));
    } catch (e) {
      print('[EventHandler ERROR] Error handling repost event: $e');
    }
  }

  Future<void> handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    try {
      final reply = ReplyModel.fromEvent(eventData);

      // Efficient duplicate check
      final existingReplies = _cacheService.repliesMap[parentEventId];
      if (existingReplies != null && existingReplies.any((r) => r.id == reply.id)) {
        return; // Already exists
      }

      _cacheService.repliesMap.putIfAbsent(parentEventId, () => []);
      _cacheService.repliesMap[parentEventId]!.add(reply);

      // Batch save to reduce I/O
      final repliesBox = _cacheService.repliesBox;
      if (repliesBox != null) {
        unawaited(repliesBox.put(reply.id, reply));
      }

      onRepliesUpdated?.call(parentEventId, _cacheService.repliesMap[parentEventId]!);

      // Create note model for the reply only if it's from the current user
      if (reply.author == npub) {
        final isRepost = eventData['kind'] == 6;
        final repostTimestamp = isRepost ? DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000) : null;

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

        final notesBox = _cacheService.notesBox;
        if (notesBox != null) {
          unawaited(notesBox.put(noteModel.id, noteModel));
        }
        onNewNote?.call(noteModel);
      }

      // Batch profile fetching
      unawaited(_profileService.batchFetchProfiles([reply.author]));
    } catch (e) {
      print('[EventHandler ERROR] Error handling reply event: $e');
    }
  }

  Future<void> handleZapEvent(Map<String, dynamic> eventData) async {
    try {
      final zap = ZapModel.fromEvent(eventData);
      final key = zap.targetEventId;

      if (key.isEmpty) return;

      // Efficient duplicate check
      final existingZaps = _cacheService.zapsMap[key];
      if (existingZaps != null && existingZaps.any((z) => z.id == zap.id)) {
        return; // Already exists
      }

      _cacheService.zapsMap.putIfAbsent(key, () => []);
      _cacheService.zapsMap[key]!.add(zap);

      // Batch save to reduce I/O
      final zapsBox = _cacheService.zapsBox;
      if (zapsBox != null) {
        unawaited(zapsBox.put(zap.id, zap));
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling zap event: $e');
    }
  }

  Future<void> handleProfileEvent(Map<String, dynamic> eventData) async {
    try {
      final author = eventData['pubkey'] as String;
      final createdAt = DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000);
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

      final profileData = {
        'name': profileContent['name'] as String? ?? 'Anonymous',
        'profileImage': profileContent['picture'] as String? ?? '',
        'about': profileContent['about'] as String? ?? '',
        'nip05': profileContent['nip05'] as String? ?? '',
        'banner': profileContent['banner'] as String? ?? '',
        'lud16': profileContent['lud16'] as String? ?? '',
        'website': profileContent['website'] as String? ?? '',
      };

      // Update profile cache
      await _profileService.getCachedUserProfile(author);

      if (_cacheService.usersBox != null && _cacheService.usersBox!.isOpen) {
        final userModel = UserModel(
          npub: author,
          name: profileData['name']!,
          about: profileData['about']!,
          nip05: profileData['nip05']!,
          banner: profileData['banner']!,
          profileImage: profileData['profileImage']!,
          lud16: profileData['lud16']!,
          website: profileData['website']!,
          updatedAt: createdAt,
        );
        await _cacheService.usersBox!.put(author, userModel);
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling profile event: $e');
    }
  }

  Future<void> handleFollowingEvent(Map<String, dynamic> eventData) async {
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

      if (_cacheService.followingBox != null && _cacheService.followingBox!.isOpen) {
        final model = FollowingModel(pubkeys: newFollowing, updatedAt: DateTime.now(), npub: npub);
        await _cacheService.followingBox!.put('following', model);
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling following event: $e');
    }
  }

  Future<void> handleNotificationEvent(Map<String, dynamic> eventData, String notificationType) async {
    try {
      final notification = NotificationModel.fromEvent(eventData, notificationType);

      if (_cacheService.notificationsBox != null && _cacheService.notificationsBox!.isOpen) {
        if (!_cacheService.notificationsBox!.containsKey(notification.id)) {
          await _cacheService.notificationsBox!.put(notification.id, notification);
        }
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling notification event: $e');
    }
  }

  // Enhanced statistics and monitoring
  Map<String, dynamic> getEventStats() {
    return {
      'eventsProcessed': _eventsProcessed,
      'eventsSkipped': _eventsSkipped,
      'pendingEvents': _pendingEvents.length,
      'processedEventIds': _processedEventIds.length,
      'eventTypeCounts': Map<String, int>.from(_eventTypeCounts),
      'isProcessing': _isProcessing,
    };
  }

  // Cleanup method
  void dispose() {
    _batchTimer?.cancel();
    _cleanupTimer?.cancel();
    _pendingEvents.clear();
    _processedEventIds.clear();
    _eventTypeCounts.clear();
  }

  // Force process pending events
  void flushPendingEvents() {
    _processPendingEvents();
  }
}

// Helper function for fire-and-forget operations
void unawaited(Future<void> future) {
  future.catchError((error) {
    print('[EventHandler] Background operation failed: $error');
  });
}
