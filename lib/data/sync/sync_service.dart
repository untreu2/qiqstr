import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/rust_database_service.dart';
import '../services/relay_service.dart';
import '../services/nostr_service.dart';
import '../services/auth_service.dart';
import '../services/encrypted_mute_service.dart';
import '../services/encrypted_bookmark_service.dart';
import '../services/pinned_notes_service.dart';
import '../services/follow_set_service.dart';
import 'publishers/event_publisher.dart';

final _relayService = RustRelayService.instance;

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
  final RustDatabaseService _db;
  final EventPublisher _publisher;

  Timer? _periodicTimer;
  final _syncStatusController =
      StreamController<SyncOperationStatus>.broadcast();
  final Map<String, DateTime> _lastSyncTime = {};
  static const _minSyncInterval = Duration(minutes: 3);

  StreamSubscription<Map<String, dynamic>>? _feedSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  final _recentEventIds = <String>{};
  static const _maxCachedIds = 10000;

  final _pendingRefIds = <String>{};
  Timer? _refFetchTimer;
  final _pendingProfilePubkeys = <String>{};
  Timer? _profileSyncTimer;

  Stream<SyncOperationStatus> get syncStatus => _syncStatusController.stream;

  SyncService({
    required RustDatabaseService db,
    required EventPublisher publisher,
  })  : _db = db,
        _publisher = publisher;

  bool _shouldSync(String key) {
    final lastSync = _lastSyncTime[key];
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync) > _minSyncInterval;
  }

  void _markSynced(String key) {
    _lastSyncTime[key] = DateTime.now();
  }

  int? _getSincestamp(String key) {
    final lastSync = _lastSyncTime[key];
    if (lastSync == null) return null;
    return lastSync.millisecondsSinceEpoch ~/ 1000 - 60;
  }

  bool _isDuplicate(String? eventId) {
    if (eventId == null || eventId.isEmpty) return false;
    if (_recentEventIds.contains(eventId)) return true;
    if (_recentEventIds.length >= _maxCachedIds) {
      _recentEventIds.clear();
    }
    _recentEventIds.add(eventId);
    return false;
  }

  Future<void> syncFeed(String userPubkey, {bool force = false}) async {
    final key = 'feed_$userPubkey';
    if (!force && !_shouldSync(key)) return;

    await _sync('feed', () async {
      final follows = await _db.getFollowingList(userPubkey);
      if (follows == null || follows.isEmpty) return;

      final since = _getSincestamp(key);
      final notesFilter = NostrService.createNotesFilter(
          authors: follows, kinds: [1, 6], limit: 300, since: since);
      final articlesFilter =
          NostrService.createArticlesFilter(authors: follows, limit: 50, since: since);

      final results = await Future.wait([
        _queryRelays(notesFilter),
        _queryRelays(articlesFilter),
      ]);

      final noteEvents = results[0];
      final articleEvents = results[1];
      final allEvents = [...noteEvents, ...articleEvents];

      await _saveEventsAndProfiles(allEvents);

      _markSynced(key);
    });
  }

  Future<void> syncListFeed(List<String> pubkeys, {bool force = false}) async {
    if (pubkeys.isEmpty) return;
    final key = 'list_feed_${pubkeys.hashCode}';
    if (!force && !_shouldSync(key)) return;

    await _sync('list_feed', () async {
      final since = _getSincestamp(key);
      final notesFilter = NostrService.createNotesFilter(
          authors: pubkeys, kinds: [1, 6], limit: 300, since: since);

      final noteEvents = await _queryRelays(notesFilter);
      await _saveEventsAndProfiles(noteEvents);
      _markSynced(key);
    });
  }

  Future<void> syncProfile(String pubkey) async {
    final key = 'profile_$pubkey';
    if (!_shouldSync(key)) return;

    await _sync('profile', () async {
      final filter =
          NostrService.createProfileFilter(authors: [pubkey], limit: 1);
      await _queryRelays(filter);
      _notifyDbChanged();
      _markSynced(key);
    });
  }

  Future<void> syncProfileNotes(String pubkey,
      {int limit = 50, bool force = false}) async {
    final key = 'profile_notes_$pubkey';
    if (!force && !_shouldSync(key)) return;

    await _sync('profile_notes', () async {
      final since = _getSincestamp(key);
      final profileFilter =
          NostrService.createProfileFilter(authors: [pubkey], limit: 1);
      final notesFilter = NostrService.createNotesFilter(
          authors: [pubkey], kinds: [1, 6], limit: 500, since: since);

      final results = await Future.wait([
        _queryRelays(profileFilter),
        _queryRelays(notesFilter),
      ]);

      final noteEvents = results[1];

      _notifyDbChanged();
      _syncMissingProfilesInBackground(noteEvents);
      _fetchReferencedEventsInBackground(noteEvents);

      _markSynced(key);
    });
  }

  Future<void> syncProfileReactions(String pubkey,
      {int limit = 500, bool force = false}) async {
    final key = 'profile_reactions_$pubkey';
    if (!force && !_shouldSync(key)) return;

    await _sync('profile_reactions', () async {
      final since = _getSincestamp(key);
      final filter = NostrService.createNotesFilter(
          authors: [pubkey], kinds: [7], limit: limit, since: since);
      await _queryRelays(filter);
      _notifyDbChanged();
      _markSynced(key);
    });
  }

  Future<void> syncProfiles(List<String> pubkeys) async {
    if (pubkeys.isEmpty) return;
    await _sync('profiles', () async {
      final filter = NostrService.createProfileFilter(
          authors: pubkeys, limit: pubkeys.length);
      await _queryRelays(filter);
      _notifyDbChanged();
    });
  }

  Future<void> syncNotifications(String userPubkey) async {
    final key = 'notifications_$userPubkey';
    if (!_shouldSync(key)) return;

    await _sync('notifications', () async {
      final since = _getSincestamp(key);
      final filter = NostrService.createNotificationFilter(
          pubkeys: [userPubkey], kinds: [1, 6, 7, 9735], limit: 100, since: since);
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

      if (events.isNotEmpty) {
        final event = events.first;
        final tags = event['tags'] as List<dynamic>? ?? [];
        final followList = tags
            .where((tag) => tag is List && tag.isNotEmpty && tag[0] == 'p')
            .map((tag) => (tag as List)[1] as String)
            .toList();

        final listWithUser = followList.toSet()..add(userPubkey);
        await _db.saveFollowingList(userPubkey, listWithUser.toList());
      }

      _notifyDbChanged();
      _markSynced(key);
    });
  }

  Future<void> syncFollowsOfFollows(String userPubkey) async {
    final key = 'fof_$userPubkey';
    if (!_shouldSync(key)) return;

    await _sync('follows_of_follows', () async {
      final follows = await _db.getFollowingList(userPubkey);
      if (follows == null || follows.isEmpty) return;

      final pubkeysToSync = follows.where((p) => p != userPubkey).toList();
      if (pubkeysToSync.isEmpty) return;

      const batchSize = 20;
      for (var i = 0; i < pubkeysToSync.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, pubkeysToSync.length);
        final batch = pubkeysToSync.sublist(i, end);
        final filter = NostrService.createFollowingFilter(
            authors: batch, limit: batch.length);
        final events = await _queryRelays(filter);

        for (final event in events) {
          final authorPubkey = event['pubkey'] as String? ?? '';
          if (authorPubkey.isEmpty) continue;

          final tags = event['tags'] as List<dynamic>? ?? [];
          final followList = tags
              .where((tag) => tag is List && tag.isNotEmpty && tag[0] == 'p')
              .map((tag) => (tag as List)[1] as String)
              .toList();

          final listWithUser = followList.toSet()..add(authorPubkey);
          await _db.saveFollowingList(authorPubkey, listWithUser.toList());
        }
      }

      _markSynced(key);
    });
  }

  Future<void> syncMuteList(String userPubkey) async {
    await _sync('mute', () async {
      final filter =
          NostrService.createMuteFilter(authors: [userPubkey], limit: 1);
      await _queryRelays(filter);
      final authService = AuthService.instance;
      final pkResult = await authService.getCurrentUserPrivateKey();
      final pubResult = await authService.getCurrentUserPublicKeyHex();
      if (!pkResult.isError &&
          pkResult.data != null &&
          !pubResult.isError &&
          pubResult.data != null) {
        await EncryptedMuteService.instance.loadFromDatabase(
          userPubkeyHex: pubResult.data!,
          privateKeyHex: pkResult.data!,
        );
      }
    });
  }

  Future<void> syncBookmarkList(String userPubkey) async {
    await _sync('bookmark', () async {
      final filter =
          NostrService.createBookmarkFilter(authors: [userPubkey], limit: 1);
      await _queryRelays(filter);

      final authService = AuthService.instance;
      final pkResult = await authService.getCurrentUserPrivateKey();
      final pubResult = await authService.getCurrentUserPublicKeyHex();
      if (!pkResult.isError &&
          pkResult.data != null &&
          !pubResult.isError &&
          pubResult.data != null) {
        await EncryptedBookmarkService.instance.loadFromDatabase(
          userPubkeyHex: pubResult.data!,
          privateKeyHex: pkResult.data!,
        );
      }
    });
  }

  Future<Map<String, dynamic>> publishBookmark({
    required List<String> bookmarkedEventIds,
  }) async {
    final event = await _publish(() => _publisher.createBookmark(
          bookmarkedEventIds: bookmarkedEventIds,
        ));
    return event;
  }

  Future<void> syncPinnedNotes(String userPubkey) async {
    await _sync('pinned_notes', () async {
      final filter = NostrService.createPinnedNotesFilter(
          authors: [userPubkey], limit: 1);
      await _queryRelays(filter);

      final authService = AuthService.instance;
      final pubResult = await authService.getCurrentUserPublicKeyHex();
      if (!pubResult.isError &&
          pubResult.data != null &&
          pubResult.data == userPubkey) {
        await PinnedNotesService.instance.loadFromDatabase(
          userPubkeyHex: userPubkey,
        );
      }
    });
  }

  Future<Map<String, dynamic>> publishPinnedNotes({
    required List<String> pinnedNoteIds,
  }) async {
    final event = await _publish(() => _publisher.createPinnedNotes(
          pinnedNoteIds: pinnedNoteIds,
        ));
    return event;
  }

  Future<void> syncFollowSets(String userPubkey) async {
    await _sync('follow_sets', () async {
      final follows = await _db.getFollowingList(userPubkey);
      final allAuthors = [userPubkey, ...?follows];

      final filter =
          NostrService.createFollowSetsFilter(authors: allAuthors, limit: 500);
      await _queryRelays(filter);

      await FollowSetService.instance
          .loadFromDatabase(userPubkeyHex: userPubkey);

      if (follows != null && follows.isNotEmpty) {
        await FollowSetService.instance
            .loadFollowedUsersSets(followedPubkeys: follows);
      }
    });
  }

  Future<Map<String, dynamic>> publishFollowSet({
    required String dTag,
    required String title,
    required String description,
    required String image,
    required List<String> pubkeys,
  }) async {
    final event = await _publish(() => _publisher.createFollowSet(
          dTag: dTag,
          title: title,
          description: description,
          image: image,
          pubkeys: pubkeys,
        ));
    return event;
  }

  Future<void> syncArticles(
      {List<String>? authors, int limit = 50, bool force = false}) async {
    final key = 'articles_${authors?.join('_') ?? 'global'}';
    if (!force && !_shouldSync(key)) return;

    await _sync('articles', () async {
      final since = _getSincestamp(key);
      final filter = NostrService.createArticlesFilter(
        authors: authors,
        limit: limit,
        since: since,
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
      final since = _getSincestamp(key);
      final filter = NostrService.createHashtagFilter(
        hashtag: normalizedHashtag,
        kinds: [1],
        limit: 100,
        since: since,
      );
      final events = await _queryRelays(filter);
      await _saveEventsAndProfiles(events);

      _markSynced(key);
    });
  }

  Future<void> syncInteractionsForNote(String noteId) async {
    await _sync('interactions_$noteId', () async {
      final filter = NostrService.createCombinedInteractionFilter(
          eventIds: [noteId], limit: 500);
      final events = await _queryRelays(filter);
      if (events.isNotEmpty) {
        await _saveEventsAndProfiles(events);
      }
    });
  }

  Future<void> syncInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    await _sync('interactions_batch', () async {
      final filter = NostrService.createCombinedInteractionFilter(
          eventIds: noteIds, limit: noteIds.length * 10);
      final events = await _queryRelays(filter);
      if (events.isNotEmpty) {
        await _saveEventsAndProfiles(events);
      }
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
      final allEvents = <Map<String, dynamic>>[];
      final processedIds = <String>{};
      var pendingIds = <String>[noteId];

      for (var depth = 0; depth < 10 && pendingIds.isNotEmpty; depth++) {
        final idsToFetch =
            pendingIds.where((id) => !processedIds.contains(id)).toList();
        if (idsToFetch.isEmpty) break;

        final filter =
            NostrService.createEventByIdFilter(eventIds: idsToFetch);
        final events = await _queryRelays(filter);
        allEvents.addAll(events);
        for (final id in idsToFetch) {
          processedIds.add(id);
        }

        final parentIds = _extractParentIds(events);
        final referencedIds = _extractReferencedEventIds(events);
        pendingIds = <String>{...parentIds, ...referencedIds}
            .where((id) => !processedIds.contains(id))
            .toList();
      }

      await _saveEventsAndProfiles(allEvents);
    });
  }

  Future<String> resolveThreadRoot(String noteId) async {
    var currentId = noteId;
    final visited = <String>{};

    for (var depth = 0; depth < 15; depth++) {
      if (visited.contains(currentId)) break;
      visited.add(currentId);

      var event = await _db.getEventModel(currentId);
      if (event == null) {
        await syncNote(currentId);
        event = await _db.getEventModel(currentId);
        if (event == null) break;
      }

      final tags = event['tags'] as List<dynamic>? ?? [];
      String? rootId;
      String? parentId;

      for (final tag in tags) {
        if (tag is List && tag.length > 1 && tag[0] == 'e') {
          final marker = tag.length >= 4 ? tag[3] as String? : null;
          if (marker == 'root') {
            rootId = tag[1] as String;
            break;
          } else if (marker == 'reply') {
            parentId = tag[1] as String;
          } else if (marker == null && parentId == null) {
            parentId = tag[1] as String;
          }
        }
      }

      if (rootId != null && rootId.isNotEmpty) {
        var rootEvent = await _db.getEventModel(rootId);
        if (rootEvent == null) {
          await syncNote(rootId);
        }
        return rootId;
      }

      if (parentId != null && parentId.isNotEmpty && parentId != currentId) {
        currentId = parentId;
        continue;
      }

      break;
    }

    return currentId;
  }

  Future<Map<String, dynamic>> publishNote(
          {required String content, List<List<String>>? tags}) =>
      _publish(() => _publisher.createNote(content: content, tags: tags));

  Future<Map<String, dynamic>> publishReply({
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

  Future<Map<String, dynamic>> publishQuote(
          {required String content,
          required String quotedNoteId,
          String? quotedAuthor}) =>
      _publish(() => _publisher.createQuote(
          content: content,
          quotedNoteId: quotedNoteId,
          quotedAuthor: quotedAuthor));

  Future<Map<String, dynamic>> publishReaction(
          {required String targetEventId,
          required String targetAuthor,
          String content = '+'}) =>
      _publish(() => _publisher.createReaction(
          targetEventId: targetEventId,
          targetAuthor: targetAuthor,
          content: content));

  Future<Map<String, dynamic>> publishRepost(
          {required String noteId,
          required String noteAuthor,
          required String originalContent}) =>
      _publish(() => _publisher.createRepost(
          noteId: noteId,
          noteAuthor: noteAuthor,
          originalContent: originalContent));

  Future<Map<String, dynamic>> publishDeletion(
      {required List<String> eventIds, String? reason}) async {
    final event = await _publish(
        () => _publisher.createDeletion(eventIds: eventIds, reason: reason));
    try {
      await _db.saveEvents([event]);
    } catch (_) {}
    return event;
  }

  Future<Map<String, dynamic>> publishFollow(
      {required List<String> followingPubkeys}) async {
    final event = await _publish(
        () => _publisher.createFollow(followingPubkeys: followingPubkeys));
    final pubkey = event['pubkey'] as String? ?? '';

    final listWithUser = followingPubkeys.toSet()..add(pubkey);
    await _db.saveFollowingList(pubkey, listWithUser.toList());

    return event;
  }

  Future<Map<String, dynamic>> publishMute({
    required List<String> mutedPubkeys,
    List<String>? mutedWords,
  }) async {
    final words = mutedWords ?? EncryptedMuteService.instance.mutedWords;
    final event = await _publish(() => _publisher.createMute(
          mutedPubkeys: mutedPubkeys,
          mutedWords: words,
        ));
    return event;
  }

  Future<Map<String, dynamic>> publishReport({
    required String reportedPubkey,
    required String reportType,
    String content = '',
  }) =>
      _publish(() => _publisher.createReport(
            reportedPubkey: reportedPubkey,
            reportType: reportType,
            content: content,
          ));

  Future<Map<String, dynamic>> publishProfileUpdate(
      {required Map<String, dynamic> profileContent}) async {
    final event = await _publish(
        () => _publisher.createProfileUpdate(profileContent: profileContent));
    final pubkey = event['pubkey'] as String? ?? '';
    final profileData =
        profileContent.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    await _db.saveUserProfile(pubkey, profileData);
    return event;
  }

  void startPeriodicSync(String userPubkey,
      {Duration interval = const Duration(minutes: 10)}) {
    stopPeriodicSync();
    _periodicTimer = Timer.periodic(interval, (_) async {
      if (_feedSubscription != null || _notificationSubscription != null) return;
      await syncFeed(userPubkey);
      await syncNotifications(userPubkey);
    });
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<void> startRealtimeSubscriptions(String userPubkey) async {
    await _startFeedSubscription(userPubkey);
    await _startNotificationSubscription(userPubkey);
  }

  Future<void> _startFeedSubscription(String userPubkey) async {
    _feedSubscription?.cancel();
    try {
      final follows = await _db.getFollowingList(userPubkey);
      if (follows == null || follows.isEmpty) return;

      final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
      final filter = <String, dynamic>{
        'kinds': [1, 6],
        'authors': follows,
        'since': since,
      };

      final muteService = EncryptedMuteService.instance;
      final stream = _relayService.subscribeToEvents(filter);
      _feedSubscription = stream.listen(
        (eventData) async {
          try {
            final eventId = eventData['id'] as String?;
            if (_isDuplicate(eventId)) return;
            if (muteService.shouldFilterEvent(eventData)) return;
            _notifyDbChanged();
            _syncMissingProfilesInBackground([eventData]);
          } catch (_) {}
        },
        onError: (_) {
          _feedSubscription = null;
        },
        onDone: () {
          _feedSubscription = null;
        },
      );
    } catch (_) {}
  }

  Future<void> _startNotificationSubscription(String userPubkey) async {
    _notificationSubscription?.cancel();
    try {
      final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
      final filter = <String, dynamic>{
        'kinds': [1, 6, 7, 9735],
        '#p': [userPubkey],
        'since': since,
      };

      final muteService = EncryptedMuteService.instance;
      final stream = _relayService.subscribeToEvents(filter);
      _notificationSubscription = stream.listen(
        (eventData) async {
          try {
            final eventId = eventData['id'] as String?;
            if (_isDuplicate(eventId)) return;
            if (muteService.shouldFilterEvent(eventData)) return;
            _notifyDbChanged();
            _syncMissingProfilesInBackground([eventData]);
          } catch (_) {}
        },
        onError: (_) {
          _notificationSubscription = null;
        },
        onDone: () {
          _notificationSubscription = null;
        },
      );
    } catch (_) {}
  }

  void stopRealtimeSubscriptions() {
    _feedSubscription?.cancel();
    _feedSubscription = null;
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
  }

  Future<String?> uploadMedia(String filePath,
          {String blossomUrl = 'https://blossom.primal.net'}) =>
      _publisher.uploadMedia(filePath, blossomUrl: blossomUrl);

  void dispose() {
    stopPeriodicSync();
    stopRealtimeSubscriptions();
    _refFetchTimer?.cancel();
    _profileSyncTimer?.cancel();
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

  Future<Map<String, dynamic>> _publish(
      Future<Map<String, dynamic>> Function() createEvent) async {
    final event = await createEvent();

    await _db.saveEvents([event]);

    final eventJson = jsonEncode(event);
    try {
      final result = await _relayService.sendEvent(eventJson);
      if (kDebugMode) {
        print('[SyncService] Event dispatched: ${result['id']} '
            'success=${result['success']} failed=${result['failed']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[SyncService] Failed to dispatch event: $e');
      }
    }

    return event;
  }

  Future<List<Map<String, dynamic>>> _queryRelays(dynamic filter) async {
    final filterMap = filter as Map<String, dynamic>;
    return await _relayService.fetchEvents(filterMap);
  }

  void _notifyDbChanged() {
    _db.notifyChange();
  }

  Set<String> _extractAllPubkeys(List<Map<String, dynamic>> events) {
    final pubkeys = <String>{};
    for (final event in events) {
      final pubkey = event['pubkey'] as String?;
      if (pubkey != null && pubkey.isNotEmpty) {
        pubkeys.add(pubkey);
      }
      final kind = event['kind'] as int? ?? 1;
      if (kind == 6) {
        final tags = event['tags'] as List<dynamic>? ?? [];
        for (final tag in tags) {
          if (tag is List &&
              tag.isNotEmpty &&
              tag[0] == 'p' &&
              tag.length > 1) {
            final originalAuthor = tag[1] as String?;
            if (originalAuthor != null && originalAuthor.isNotEmpty) {
              pubkeys.add(originalAuthor);
            }
          }
        }
      }
    }
    return pubkeys;
  }

  Future<void> _syncMissingProfiles(Set<String> pubkeys) async {
    if (pubkeys.isEmpty) return;
    final existingProfiles = await _db.getUserProfiles(pubkeys.toList());
    final missingProfiles =
        pubkeys.where((p) => !existingProfiles.containsKey(p)).toList();
    if (missingProfiles.isNotEmpty) {
      await syncProfiles(missingProfiles);
    }
  }

  void _syncMissingProfilesInBackground(List<Map<String, dynamic>> events) {
    _schedulePendingProfileSync(_extractAllPubkeys(events));
  }

  void _schedulePendingProfileSync(Set<String> pubkeys) {
    if (pubkeys.isEmpty) return;
    _pendingProfilePubkeys.addAll(pubkeys);
    _profileSyncTimer?.cancel();
    _profileSyncTimer = Timer(const Duration(seconds: 5), () {
      _processPendingProfiles();
    });
  }

  Future<void> _processPendingProfiles() async {
    final pubkeys = _pendingProfilePubkeys.toSet();
    _pendingProfilePubkeys.clear();
    if (pubkeys.isEmpty) return;
    try {
      await _syncMissingProfiles(pubkeys);
    } catch (_) {}
  }

  Future<void> _saveEventsAndProfiles(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    _notifyDbChanged();
    _syncMissingProfilesInBackground(events);
    _fetchReferencedEventsInBackground(events);
  }

  Set<String> _extractReferencedEventIds(List<Map<String, dynamic>> events) {
    final refIds = <String>{};
    final ownIds = events
        .map((e) => e['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final event in events) {
      final tags = event['tags'] as List<dynamic>? ?? [];
      for (final tag in tags) {
        if (tag is List && tag.length > 1) {
          final tagType = tag[0] as String?;
          final refId = tag[1] as String?;
          if (refId == null || refId.isEmpty || ownIds.contains(refId)) {
            continue;
          }

          if (tagType == 'q') {
            refIds.add(refId);
          } else if (tagType == 'e') {
            final marker = tag.length >= 4 ? tag[3] as String? : null;
            if (marker == 'mention' || marker == null) {
              refIds.add(refId);
            }
          }
        }
      }
    }
    return refIds;
  }

  void _fetchReferencedEventsInBackground(List<Map<String, dynamic>> events) {
    final refIds = _extractReferencedEventIds(events);
    if (refIds.isEmpty) return;
    _pendingRefIds.addAll(refIds);
    _refFetchTimer?.cancel();
    _refFetchTimer = Timer(const Duration(seconds: 5), () {
      _processPendingRefs();
    });
  }

  Future<void> _processPendingRefs() async {
    final ids = _pendingRefIds.toList();
    _pendingRefIds.clear();
    if (ids.isEmpty) return;
    try {
      final existResults = await _db.eventsExistBatch(ids);
      final missingIds = <String>[];
      for (var i = 0; i < ids.length; i++) {
        if (!existResults[i]) missingIds.add(ids[i]);
      }
      if (missingIds.isEmpty) return;

      final filter = NostrService.createEventByIdFilter(eventIds: missingIds);
      final fetchedEvents = await _queryRelays(filter);
      if (fetchedEvents.isNotEmpty) {
        _notifyDbChanged();
        _schedulePendingProfileSync(_extractAllPubkeys(fetchedEvents));
      }
    } catch (_) {}
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
}
