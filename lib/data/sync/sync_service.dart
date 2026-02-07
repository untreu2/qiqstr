import 'dart:async';
import 'dart:convert';
import '../services/isar_database_service.dart';
import '../services/relay_service.dart';
import '../services/nostr_service.dart';
import '../../models/event_model.dart';
import 'replacement_handler.dart';
import 'sync_queue.dart';
import 'sync_task.dart';
import 'publishers/event_publisher.dart';

enum SyncOperationState { idle, syncing, completed, error }

class SyncOperationStatus {
  final String operation;
  final SyncOperationState state;
  final String? error;

  const SyncOperationStatus({
    required this.operation,
    required this.state,
    this.error,
  });
}

class SyncService {
  final IsarDatabaseService _db;
  final ReplacementHandler _replacementHandler;
  final SyncQueue _queue;
  final EventPublisher _publisher;

  Timer? _periodicTimer;
  final _syncStatusController =
      StreamController<SyncOperationStatus>.broadcast();
  bool _isProcessingQueue = false;

  final Map<String, DateTime> _lastSyncTime = {};
  static const _minSyncInterval = Duration(seconds: 30);

  Stream<SyncOperationStatus> get syncStatus => _syncStatusController.stream;

  SyncService({
    required IsarDatabaseService db,
    required EventPublisher publisher,
  })  : _db = db,
        _replacementHandler = ReplacementHandler(db),
        _queue = SyncQueue(),
        _publisher = publisher;

  bool _shouldSync(String key) {
    final lastSync = _lastSyncTime[key];
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync) > _minSyncInterval;
  }

  void _markSynced(String key) {
    _lastSyncTime[key] = DateTime.now();
  }

  Future<void> syncFeed(String userPubkey, {bool force = false}) async {
    final key = 'feed_$userPubkey';
    if (!force && !_shouldSync(key)) return;

    await _sync('feed', () async {
      final follows = await _db.getFollowingList(userPubkey);
      if (follows == null || follows.isEmpty) return;

      final notesFilter = NostrService.createNotesFilter(
          authors: follows, kinds: [1, 6], limit: 300);
      final articlesFilter =
          NostrService.createArticlesFilter(authors: follows, limit: 50);

      final results = await Future.wait([
        _queryRelays(notesFilter),
        _queryRelays(articlesFilter),
      ]);

      final noteEvents = results[0];
      final articleEvents = results[1];
      final allEvents = [...noteEvents, ...articleEvents];

      await _saveEventsAndProfiles(allEvents);

      final noteIds = <String>{};
      for (final event in noteEvents) {
        final id = event['id'] as String?;
        if (id != null && id.isNotEmpty) {
          noteIds.add(id);
        }
        final kind = event['kind'] as int?;
        if (kind == 6) {
          final originalId = _extractOriginalNoteIdFromEvent(event);
          if (originalId != null) {
            noteIds.add(originalId);
          }
        }
      }

      if (noteIds.isNotEmpty) {
        final interactionFilter = NostrService.createCombinedInteractionFilter(
            eventIds: noteIds.toList(), limit: noteIds.length * 10);
        final interactionEvents = await _queryRelays(interactionFilter);
        await _saveEvents(interactionEvents);
      }

      _markSynced(key);
    });
  }

  Future<void> syncProfile(String pubkey) async {
    final key = 'profile_$pubkey';
    if (!_shouldSync(key)) return;

    await _sync('profile', () async {
      final filter =
          NostrService.createProfileFilter(authors: [pubkey], limit: 1);
      final events = await _queryRelays(filter);
      await _saveEvents(events);
      _markSynced(key);
    });
  }

  Future<void> syncProfileNotes(String pubkey,
      {int limit = 50, bool force = false}) async {
    final key = 'profile_notes_$pubkey';
    if (!force && !_shouldSync(key)) return;

    await _sync('profile_notes', () async {
      final profileFilter =
          NostrService.createProfileFilter(authors: [pubkey], limit: 1);
      final notesFilter = NostrService.createNotesFilter(
          authors: [pubkey], kinds: [1, 6], limit: 500);

      final results = await Future.wait([
        _queryRelays(profileFilter),
        _queryRelays(notesFilter),
      ]);

      final profileEvents = results[0];
      final noteEvents = results[1];

      await Future.wait([
        _saveEvents(profileEvents),
        _saveEvents(noteEvents),
      ]);

      final noteIds = <String>{};
      for (final event in noteEvents) {
        final id = event['id'] as String?;
        if (id != null && id.isNotEmpty) {
          noteIds.add(id);
        }
        final kind = event['kind'] as int?;
        if (kind == 6) {
          final originalId = _extractOriginalNoteIdFromEvent(event);
          if (originalId != null) {
            noteIds.add(originalId);
          }
        }
      }

      if (noteIds.isNotEmpty) {
        final interactionFilter = NostrService.createCombinedInteractionFilter(
            eventIds: noteIds.toList(), limit: noteIds.length * 20);
        final interactionEvents = await _queryRelays(interactionFilter);
        await _saveEvents(interactionEvents);
      }

      _markSynced(key);
    });
  }

  Future<void> syncProfiles(List<String> pubkeys) async {
    if (pubkeys.isEmpty) return;
    await _sync('profiles', () async {
      final filter = NostrService.createProfileFilter(
          authors: pubkeys, limit: pubkeys.length);
      final events = await _queryRelays(filter);
      await _saveEvents(events);
    });
  }

  Future<void> syncNotifications(String userPubkey) async {
    final key = 'notifications_$userPubkey';
    if (!_shouldSync(key)) return;

    await _sync('notifications', () async {
      final filter = NostrService.createNotificationFilter(
          pubkeys: [userPubkey], kinds: [1, 6, 7, 9735], limit: 100);
      final events = await _queryRelays(filter);
      await _saveEventsAndProfiles(events);
      _markSynced(key);
    });
  }

  Future<void> syncFollowingList(String userPubkey) async {
    final key = 'following_$userPubkey';
    if (!_shouldSync(key)) return;

    await _sync('following', () async {
      final filter =
          NostrService.createFollowingFilter(authors: [userPubkey], limit: 1);
      final events = await _queryRelays(filter);
      await _saveEvents(events);
      _markSynced(key);
    });
  }

  Future<void> syncMuteList(String userPubkey) async {
    await _sync('mute', () async {
      final filter =
          NostrService.createMuteFilter(authors: [userPubkey], limit: 1);
      final events = await _queryRelays(filter);
      await _saveEvents(events);
    });
  }

  Future<void> syncArticles({List<String>? authors, int limit = 50}) async {
    final key = 'articles_${authors?.join('_') ?? 'global'}';
    if (!_shouldSync(key)) return;

    await _sync('articles', () async {
      final filter = NostrService.createArticlesFilter(
        authors: authors,
        limit: limit,
      );
      final events = await _queryRelays(filter);
      await _saveEventsAndProfiles(events);
      _markSynced(key);
    });
  }

  Future<void> syncHashtag(String hashtag, {bool force = false}) async {
    final normalizedHashtag = hashtag.toLowerCase();
    final key = 'hashtag_$normalizedHashtag';
    if (!force && !_shouldSync(key)) return;

    await _sync('hashtag', () async {
      final filter = NostrService.createHashtagFilter(
        hashtag: normalizedHashtag,
        kinds: [1],
        limit: 100,
      );
      final events = await _queryRelays(filter);
      await _saveEventsAndProfiles(events);

      final noteIds = events
          .map((e) => e['id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      if (noteIds.isNotEmpty) {
        final interactionFilter = NostrService.createCombinedInteractionFilter(
            eventIds: noteIds, limit: noteIds.length * 10);
        final interactionEvents = await _queryRelays(interactionFilter);
        await _saveEvents(interactionEvents);
      }

      _markSynced(key);
    });
  }

  Future<void> syncReplies(String noteId) async {
    await _sync('replies', () async {
      final allEvents = <Map<String, dynamic>>[];
      final processedIds = <String>{noteId};
      var pendingIds = <String>[noteId];

      for (var depth = 0; depth < 5 && pendingIds.isNotEmpty; depth++) {
        final filter = NostrService.createInteractionFilter(
            kinds: [1], eventIds: pendingIds, limit: 500);
        final events = await _queryRelays(filter);
        final newIds = <String>[];

        for (final event in events) {
          final eventId = event['id'] as String?;
          if (eventId != null && !processedIds.contains(eventId)) {
            processedIds.add(eventId);
            allEvents.add(event);
            newIds.add(eventId);
          }
        }
        pendingIds = newIds;
      }

      await _saveEventsAndProfiles(allEvents);
    });
  }

  Future<void> syncNote(String noteId) async {
    await _sync('note', () async {
      final filter = NostrService.createEventByIdFilter(eventIds: [noteId]);
      final events = await _queryRelays(filter);
      await _saveEvents(events);

      final parentIds = _extractParentIds(events);
      if (parentIds.isNotEmpty) {
        final parentFilter =
            NostrService.createEventByIdFilter(eventIds: parentIds);
        final parentEvents = await _queryRelays(parentFilter);
        await _saveEventsAndProfiles([...events, ...parentEvents]);
      } else {
        await _saveEventsAndProfiles(events);
      }
    });
  }

  Future<EventModel> publishNote(
          {required String content, List<List<String>>? tags}) =>
      _publish(() => _publisher.createNote(content: content, tags: tags));

  Future<EventModel> publishReply({
    required String content,
    required String rootId,
    String? replyToId,
    required String parentAuthor,
    String? replyAuthor,
  }) =>
      _publish(() => _publisher.createReply(
            content: content,
            rootId: rootId,
            replyToId: replyToId,
            rootAuthor: parentAuthor,
            replyAuthor: replyAuthor,
          ));

  Future<EventModel> publishQuote(
          {required String content,
          required String quotedNoteId,
          String? quotedAuthor}) =>
      _publish(() => _publisher.createQuote(
          content: content,
          quotedNoteId: quotedNoteId,
          quotedAuthor: quotedAuthor));

  Future<EventModel> publishReaction(
          {required String targetEventId,
          required String targetAuthor,
          String content = '+'}) =>
      _publish(() => _publisher.createReaction(
          targetEventId: targetEventId,
          targetAuthor: targetAuthor,
          content: content));

  Future<EventModel> publishRepost(
          {required String noteId,
          required String noteAuthor,
          required String originalContent}) =>
      _publish(() => _publisher.createRepost(
          noteId: noteId,
          noteAuthor: noteAuthor,
          originalContent: originalContent));

  Future<EventModel> publishDeletion(
          {required List<String> eventIds, String? reason}) =>
      _publish(
          () => _publisher.createDeletion(eventIds: eventIds, reason: reason));

  Future<EventModel> publishFollow(
      {required List<String> followingPubkeys}) async {
    final event = await _publish(
        () => _publisher.createFollow(followingPubkeys: followingPubkeys));
    await _db.saveFollowingList(event.pubkey, followingPubkeys);
    return event;
  }

  Future<EventModel> publishMute({required List<String> mutedPubkeys}) async {
    final event =
        await _publish(() => _publisher.createMute(mutedPubkeys: mutedPubkeys));
    await _db.saveMuteList(event.pubkey, mutedPubkeys);
    return event;
  }

  Future<EventModel> publishProfileUpdate(
      {required Map<String, dynamic> profileContent}) async {
    final event = await _publish(
        () => _publisher.createProfileUpdate(profileContent: profileContent));
    final profileData =
        profileContent.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    await _db.saveUserProfile(event.pubkey, profileData);
    return event;
  }

  void startPeriodicSync(String userPubkey,
      {Duration interval = const Duration(minutes: 5)}) {
    stopPeriodicSync();
    _periodicTimer = Timer.periodic(interval, (_) async {
      await syncFeed(userPubkey);
      await syncNotifications(userPubkey);
    });
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<String?> uploadMedia(String filePath,
          {String blossomUrl = 'https://blossom.primal.net'}) =>
      _publisher.uploadMedia(filePath, blossomUrl: blossomUrl);

  void dispose() {
    stopPeriodicSync();
    _syncStatusController.close();
  }

  Future<void> _sync(String operation, Future<void> Function() action) async {
    _syncStatusController.add(SyncOperationStatus(
        operation: operation, state: SyncOperationState.syncing));
    try {
      await action();
      _syncStatusController.add(SyncOperationStatus(
          operation: operation, state: SyncOperationState.completed));
    } catch (e) {
      _syncStatusController.add(SyncOperationStatus(
          operation: operation,
          state: SyncOperationState.error,
          error: e.toString()));
    }
  }

  Future<EventModel> _publish(Future<EventModel> Function() createEvent) async {
    final event = await createEvent();
    event.syncStatus = SyncStatus.pending;
    await _db.saveEvent(event);
    _queue.add(
        PublishTask(eventId: event.eventId, priority: SyncPriority.critical));
    _processQueue();
    return event;
  }

  Future<List<Map<String, dynamic>>> _queryRelays(dynamic filter) async {
    final request = NostrService.createRequest(filter);
    final subscriptionId = (jsonDecode(request) as List<dynamic>)[1] as String;

    await _ensureRelayConnection();

    final wsManager = WebSocketManager.instance;
    final relays = wsManager.healthyRelays.isNotEmpty
        ? wsManager.healthyRelays
        : wsManager.relayUrls;
    if (relays.isEmpty) return [];

    final events = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    final completers = relays.take(5).map((relayUrl) {
      return wsManager.sendQuery(
        relayUrl,
        request,
        subscriptionId,
        onEvent: (eventMap, url) {
          final id = eventMap['id'] as String?;
          if (id != null && seenIds.add(id)) {
            events.add(eventMap);
          }
        },
        timeout: const Duration(seconds: 15),
      ).then((c) => c.future);
    }).toList();

    await Future.wait(completers)
        .timeout(const Duration(seconds: 20), onTimeout: () => []);
    return events;
  }

  Future<void> _ensureRelayConnection() async {
    final wsManager = WebSocketManager.instance;
    if (wsManager.activeSockets.isNotEmpty) return;

    if (wsManager.relayUrls.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (wsManager.relayUrls.isEmpty) return;
    }

    await Future.wait(
      wsManager.relayUrls.map((url) =>
          wsManager.getOrCreateConnection(url).catchError((_) => null)),
    ).timeout(const Duration(seconds: 10), onTimeout: () => []);

    for (var i = 0; i < 20 && wsManager.activeSockets.isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _saveEvents(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    final toInsert = <EventModel>[];
    final toReplace = <(EventModel, int)>[];

    for (final eventData in events) {
      final event = EventModel.fromEventData(eventData);
      final decision = await _replacementHandler.shouldSave(event);
      switch (decision) {
        case SkipDecision():
          continue;
        case InsertDecision():
          toInsert.add(event);
        case ReplaceDecision(existingId: final existingId):
          toReplace.add((event, existingId));
      }
    }

    if (toInsert.isNotEmpty) {
      await _db.saveEventsBatch(toInsert);
    }

    for (final (event, existingId) in toReplace) {
      await _db.saveEventWithReplacement(event, existingId);
    }
  }

  Future<void> _saveEventsAndProfiles(List<Map<String, dynamic>> events) async {
    await _saveEvents(events);

    final pubkeys = events
        .map((e) => e['pubkey'] as String?)
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>()
        .toSet();
    if (pubkeys.isEmpty) return;

    final existingProfiles = await _db.getUserProfiles(pubkeys.toList());
    final missingProfiles =
        pubkeys.where((p) => !existingProfiles.containsKey(p)).toList();
    if (missingProfiles.isNotEmpty) {
      await syncProfiles(missingProfiles);
    }
  }

  List<String> _extractParentIds(List<Map<String, dynamic>> events) {
    final parentIds = <String>{};
    for (final event in events) {
      final tags = event['tags'] as List<dynamic>? ?? [];
      for (final tag in tags) {
        if (tag is List && tag.length > 1 && tag[0] == 'e') {
          final marker = tag.length >= 4 ? tag[3] as String? : null;
          if (marker == 'root' || marker == 'reply' || marker == null) {
            parentIds.add(tag[1] as String);
          }
        }
      }
    }
    return parentIds.toList();
  }

  String? _extractOriginalNoteIdFromEvent(Map<String, dynamic> event) {
    final tags = event['tags'] as List<dynamic>? ?? [];
    for (final tag in tags) {
      if (tag is List && tag.length > 1 && tag[0] == 'e') {
        return tag[1] as String;
      }
    }
    return null;
  }

  Future<void> _syncInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    final filter = NostrService.createCombinedInteractionFilter(
        eventIds: noteIds, limit: 500);
    final events = await _queryRelays(filter);
    await _saveEvents(events);
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue || _queue.isEmpty) return;
    _isProcessingQueue = true;

    try {
      while (_queue.isNotEmpty) {
        final task = _queue.next();
        if (task == null) break;
        if (task is PublishTask) {
          await _processPublishTask(task);
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _processPublishTask(PublishTask task) async {
    try {
      final event = await _db.getEventModel(task.eventId);
      if (event == null) return;

      final success = await _publisher.broadcast(event);
      if (success) {
        await _db.updateSyncStatus(task.eventId, SyncStatus.synced);
      } else if (task.retryCount < 3) {
        _queue.add(task.incrementRetry() as PublishTask);
      } else {
        await _db.updateSyncStatus(task.eventId, SyncStatus.failed);
      }
    } catch (e) {
      if (task.retryCount < 3) {
        _queue.add(task.incrementRetry() as PublishTask);
      }
    }
  }
}
