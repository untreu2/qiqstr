import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/rust_database_service.dart';
import '../services/relay_service.dart';
import '../services/auth_service.dart';
import '../services/encrypted_mute_service.dart';
import '../services/encrypted_bookmark_service.dart';
import '../services/pinned_notes_service.dart';
import '../services/follow_set_service.dart';
import 'publishers/event_publisher.dart';
import '../../domain/entities/article.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../../src/rust/api/relay.dart' as rust_relay;

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
  Timer? _lastSyncCleanupTimer;
  final _syncStatusController =
      StreamController<SyncOperationStatus>.broadcast();
  final Map<String, DateTime> _lastSyncTime = {};
  static const _minSyncInterval = Duration(minutes: 3);
  static const _lastSyncMaxAge = Duration(hours: 2);

  StreamSubscription<Map<String, dynamic>>? _feedSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  final _recentEventIds = <String>{};
  static const _maxCachedIds = 2000;

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
      final follows = await rust_db.dbGetFollowingList(pubkeyHex: userPubkey);
      if (follows.isEmpty) return;

      final since = _getSincestamp(key) ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400 * 2);
      final notesFilter = <String, dynamic>{
        'authors': follows,
        'kinds': [1, 5, 6],
        'since': since,
        'limit': 100,
      };
      final articlesFilter = <String, dynamic>{
        'kinds': [30023],
        'authors': follows,
        'since': since,
        'limit': 30,
      };

      final results = await Future.wait([
        _fetchAndStore(notesFilter),
        _fetchAndStore(articlesFilter),
      ]);

      await rust_db.dbProcessDeletionEvents();
      _db.notifyFeedChange();
      _queueMissingRepostOriginals(since);
      final noteEvents = results[0];
      if (noteEvents.isNotEmpty) {
        _fetchThreadAncestorsInBackground(noteEvents);
        _syncMissingProfilesInBackground(noteEvents);
      }
      _markSynced(key);
    });
  }

  Future<void> syncListFeed(List<String> pubkeys, {bool force = false}) async {
    if (pubkeys.isEmpty) return;
    final key = 'list_feed_${pubkeys.hashCode}';
    if (!force && !_shouldSync(key)) return;

    await _sync('list_feed', () async {
      final since = _getSincestamp(key) ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400 * 2);
      final notesFilter = <String, dynamic>{
        'authors': pubkeys,
        'kinds': [1, 5, 6],
        'since': since,
        'limit': 100,
      };

      final noteEvents = await _fetchAndStore(notesFilter);
      await rust_db.dbProcessDeletionEvents();
      _notifyFeedChanged();
      _queueMissingRepostOriginals(since);
      if (noteEvents.isNotEmpty) {
        _fetchThreadAncestorsInBackground(noteEvents);
        _syncMissingProfilesInBackground(noteEvents);
      }
      _markSynced(key);
    });
  }

  Future<void> syncProfile(String pubkey) async {
    final key = 'profile_$pubkey';
    if (!_shouldSync(key)) return;

    await _sync('profile', () async {
      final filter = <String, dynamic>{
        'kinds': [0],
        'authors': [pubkey],
        'limit': 1
      };
      await _queryRelays(filter);
      _notifyProfileChanged();
      _markSynced(key);
    });
  }

  Future<void> syncProfileNotes(String pubkey,
      {int limit = 50, bool force = false}) async {
    final key = 'profile_notes_$pubkey';
    if (!force && !_shouldSync(key)) return;

    await _sync('profile_notes', () async {
      final since = _getSincestamp(key);
      final profileFilter = <String, dynamic>{
        'kinds': [0],
        'authors': [pubkey],
        'limit': 1
      };
      final notesFilter = <String, dynamic>{
        'authors': [pubkey],
        'kinds': [1, 5, 6],
        'limit': limit,
        if (since != null) 'since': since,
      };

      final results = await Future.wait([
        _queryRelays(profileFilter),
        _queryRelays(notesFilter),
      ]);

      final noteEvents = results[1];

      await rust_db.dbProcessDeletionEvents();
      _notifyFeedChanged();
      _syncMissingProfilesInBackground(noteEvents);
      _fetchReferencedEventsInBackground(noteEvents);
      _fetchThreadAncestorsInBackground(noteEvents);
      _markSynced(key);
    });
  }

  Stream<int> streamProfileNotesProgress(String pubkey,
      {bool force = false}) async* {
    final key = 'profile_notes_$pubkey';
    if (!force && !_shouldSync(key)) return;

    _syncStatusController.add(const SyncOperationStatus(
        operation: 'profile_notes_stream', state: SyncOperationState.syncing));

    int count = 0;
    final pubkeys = <String>{};
    final repostRefIds = <String>{};

    try {
      final sinceRaw = _getSincestamp(key);
      final since = sinceRaw ?? -1;

      await for (final event in _relayService
          .fetchProfileEvents(pubkey, '1,5,6', sinceTimestamp: since)) {
        final eventPubkey = event['pubkey'] as String?;
        if (eventPubkey != null && eventPubkey.isNotEmpty) {
          pubkeys.add(eventPubkey);
        }

        final kind = (event['kind'] as num?)?.toInt();
        if (kind == 6) {
          final tags = event['tags'] as List<dynamic>? ?? [];
          for (final tag in tags) {
            if (tag is List && tag.length > 1 && tag[0] == 'e') {
              final id = tag[1] as String?;
              if (id != null && id.isNotEmpty) {
                repostRefIds.add(id);
                break;
              }
            }
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

        count++;
        if (count == 1 || count % 50 == 0) {
          _notifyFeedChanged();
          yield count;
        }
      }

      await rust_db.dbProcessDeletionEvents();
      _notifyFeedChanged();
      if (pubkeys.isNotEmpty) {
        _fetchMissingProfilesInBackground(pubkeys.toList());
      }
      if (repostRefIds.isNotEmpty) {
        _fetchRepostOriginalsInBackground(repostRefIds.toList());
      }
      _markSynced(key);

      _syncStatusController.add(const SyncOperationStatus(
          operation: 'profile_notes_stream',
          state: SyncOperationState.completed));
    } catch (e) {
      _notifyFeedChanged();
      _syncStatusController.add(SyncOperationStatus(
          operation: 'profile_notes_stream',
          state: SyncOperationState.error,
          error: e.toString()));
    }

    yield count;
  }

  Future<void> syncProfileReactions(String pubkey,
      {int limit = 50, bool force = false}) async {
    final key = 'profile_reactions_$pubkey';
    if (!force && !_shouldSync(key)) return;

    await _sync('profile_reactions', () async {
      final since = _getSincestamp(key);
      final filter = <String, dynamic>{
        'authors': [pubkey],
        'kinds': [7],
        'limit': limit,
        if (since != null) 'since': since,
      };
      await _queryRelays(filter);
      _notifyInteractionChanged();
      _markSynced(key);
    });
  }

  Future<void> syncProfiles(List<String> pubkeys) async {
    if (pubkeys.isEmpty) return;
    await _sync('profiles', () async {
      final filter = <String, dynamic>{
        'kinds': [0],
        'authors': pubkeys,
        'limit': pubkeys.length
      };
      await _queryRelays(filter);
      _notifyProfileChanged();
    });
  }

  Future<void> syncNotifications(String userPubkey) async {
    final key = 'notifications_$userPubkey';
    if (!_shouldSync(key)) return;

    await _sync('notifications', () async {
      final since = _getSincestamp(key) ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400 * 2);
      final filter = <String, dynamic>{
        '#p': [userPubkey],
        'kinds': [1, 6, 7, 9735],
        'since': since,
        'limit': 100,
      };
      await _fetchAndStore(filter);
      _db.notifyNotificationChange();

      final mute = EncryptedMuteService.instance;
      final notificationsJson = await rust_db.dbGetHydratedNotifications(
        userPubkeyHex: userPubkey,
        limit: 100,
        mutedPubkeys: mute.mutedPubkeys,
        mutedWords: mute.mutedWords,
      );
      final notifications = (jsonDecode(notificationsJson) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final missingPubkeys = <String>{};
      for (final n in notifications) {
        final pk = n['fromPubkey'] as String? ?? '';
        if (pk.isNotEmpty &&
            pk != userPubkey &&
            n['fromName'] == null &&
            n['fromImage'] == null) {
          missingPubkeys.add(pk);
        }
      }
      if (missingPubkeys.isNotEmpty) {
        await _syncMissingProfiles(missingPubkeys);
        _notifyProfileChanged();
      }

      _markSynced(key);
    });
  }

  Future<void> syncFollowingList(String userPubkey) async {
    final key = 'following_$userPubkey';
    if (!_shouldSync(key)) return;

    await _sync('following', () async {
      final filter = <String, dynamic>{
        'kinds': [3],
        'authors': [userPubkey],
        'limit': 1
      };
      final events = await _queryRelays(filter);

      if (events.isNotEmpty) {
        final event = events.first;
        final tags = event['tags'] as List<dynamic>? ?? [];
        final followList = tags
            .where((tag) => tag is List && tag.isNotEmpty && tag[0] == 'p')
            .map((tag) => (tag as List)[1] as String)
            .toList();

        final listWithUser = followList.toSet()..add(userPubkey);
        await rust_db.dbSaveFollowingList(
            pubkeyHex: userPubkey, followsHex: listWithUser.toList());
      } else {
        final existing =
            await rust_db.dbGetFollowingList(pubkeyHex: userPubkey);
        if (!existing.contains(userPubkey)) {
          final listWithUser = existing.toSet()..add(userPubkey);
          await rust_db.dbSaveFollowingList(
              pubkeyHex: userPubkey, followsHex: listWithUser.toList());
        }
      }

      _notifyFeedChanged();
      _markSynced(key);
    });
  }

  Future<void> syncFollowsOfFollows(String userPubkey) async {
    final key = 'fof_$userPubkey';
    if (!_shouldSync(key)) return;

    await _sync('follows_of_follows', () async {
      final follows = await rust_db.dbGetFollowingList(pubkeyHex: userPubkey);
      if (follows.isEmpty) return;

      final pubkeysToSync = follows.where((p) => p != userPubkey).toList();
      if (pubkeysToSync.isEmpty) return;

      const batchSize = 30;
      const maxBatches = 5;
      final totalToSync =
          (maxBatches * batchSize).clamp(0, pubkeysToSync.length);

      for (var i = 0; i < totalToSync; i += batchSize) {
        final end = (i + batchSize).clamp(0, totalToSync);
        final batch = pubkeysToSync.sublist(i, end);
        final filter = <String, dynamic>{
          'kinds': [3],
          'authors': batch,
          'limit': batch.length
        };
        await _queryRelays(filter);
      }

      _markSynced(key);
    });
  }

  Future<void> _syncEncryptedList({
    required String syncKey,
    required Map<String, dynamic> filter,
    required Future<void> Function({
      required String userPubkeyHex,
      required String privateKeyHex,
    }) loadFromDatabase,
  }) async {
    await _sync(syncKey, () async {
      await _queryRelays(filter);
      final authService = AuthService.instance;
      final pkResult = await authService.getCurrentUserPrivateKey();
      final pubResult = await authService.getCurrentUserPublicKeyHex();
      if (!pkResult.isError &&
          pkResult.data != null &&
          !pubResult.isError &&
          pubResult.data != null) {
        await loadFromDatabase(
          userPubkeyHex: pubResult.data!,
          privateKeyHex: pkResult.data!,
        );
      }
    });
  }

  Future<void> syncMuteList(String userPubkey) => _syncEncryptedList(
        syncKey: 'mute',
        filter: <String, dynamic>{
          'kinds': [10000],
          'authors': [userPubkey],
          'limit': 1
        },
        loadFromDatabase: EncryptedMuteService.instance.loadFromDatabase,
      );

  Future<void> syncBookmarkList(String userPubkey) => _syncEncryptedList(
        syncKey: 'bookmark',
        filter: <String, dynamic>{
          'kinds': [30001],
          '#d': ['bookmark'],
          'authors': [userPubkey],
          'limit': 1
        },
        loadFromDatabase: EncryptedBookmarkService.instance.loadFromDatabase,
      );

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
      final filter = <String, dynamic>{
        'kinds': [10001],
        'authors': [userPubkey],
        'limit': 1
      };
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
      final follows = await rust_db.dbGetFollowingList(pubkeyHex: userPubkey);
      final allAuthors = [userPubkey, ...follows];

      final filter = <String, dynamic>{
        'kinds': [30000],
        'authors': allAuthors,
        'limit': 500
      };
      await _queryRelays(filter);

      await FollowSetService.instance
          .loadFromDatabase(userPubkeyHex: userPubkey);

      if (follows.isNotEmpty) {
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
      final since = _getSincestamp(key) ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400 * 7);
      final filter = <String, dynamic>{
        'kinds': [30023],
        if (authors != null && authors.isNotEmpty) 'authors': authors,
        'since': since,
        'limit': limit,
      };
      await _fetchAndStore(filter);
      _notifyFeedChanged();
      _markSynced(key);
    });
  }

  Future<Article?> fetchArticleByNaddr({
    required String pubkey,
    required String identifier,
  }) async {
    try {
      final filter = <String, dynamic>{
        'kinds': [30023],
        'authors': [pubkey],
        '#d': [identifier],
        'limit': 1,
      };
      final fetched = await _relayService.fetchEvents(filter, timeoutSecs: 10);
      if (fetched.isEmpty) return null;
      await rust_db.dbSaveEvents(eventsJson: jsonEncode(fetched));
      _notifyFeedChanged();

      Future<Map<String, dynamic>?> fetchProfile() async {
        final pJson = await rust_db.dbGetProfile(pubkeyHex: pubkey);
        if (pJson == null) return null;
        return jsonDecode(pJson) as Map<String, dynamic>;
      }

      var profile = await fetchProfile();
      if (profile == null) {
        final profileFilter = <String, dynamic>{
          'kinds': [0],
          'authors': [pubkey],
          'limit': 1
        };
        final profileEvents =
            await _relayService.fetchEvents(profileFilter, timeoutSecs: 8);
        if (profileEvents.isNotEmpty) {
          await rust_db.dbSaveEvents(eventsJson: jsonEncode(profileEvents));
          profile = await fetchProfile();
        }
      }

      final article = _articleFromRawEvent(fetched.first);
      return article.copyWith(
        authorName:
            profile?['name'] as String? ?? profile?['display_name'] as String?,
        authorImage:
            profile?['picture'] as String? ?? profile?['picture'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Article _articleFromRawEvent(Map<String, dynamic> event) {
    final tags = event['tags'] as List<dynamic>? ?? [];
    String title = '';
    String? image;
    String? summary;
    String dTag = '';
    int? publishedAt;
    final hashtags = <String>[];

    for (final tag in tags) {
      if (tag is! List || tag.isEmpty) continue;
      final name = tag[0] as String?;
      final value = tag.length > 1 ? tag[1] as String? ?? '' : '';
      switch (name) {
        case 'd':
          dTag = value;
        case 'title':
          title = value;
        case 'image':
          image = value.isNotEmpty ? value : null;
        case 'summary':
          summary = value.isNotEmpty ? value : null;
        case 'published_at':
          publishedAt = int.tryParse(value);
        case 't':
          if (value.isNotEmpty) hashtags.add(value);
      }
    }

    final createdAt = (event['created_at'] as num?)?.toInt() ?? 0;
    return Article(
      id: event['id'] as String? ?? '',
      pubkey: event['pubkey'] as String? ?? '',
      title: title,
      content: event['content'] as String? ?? '',
      image: image,
      summary: summary,
      dTag: dTag,
      publishedAt: publishedAt ?? createdAt,
      createdAt: createdAt,
      hashtags: hashtags,
    );
  }

  Future<void> syncHashtag(String hashtag, {bool force = false}) async {
    final normalizedHashtag = hashtag.toLowerCase();
    final key = 'hashtag_$normalizedHashtag';
    if (!force && !_shouldSync(key)) return;

    await _sync('hashtag', () async {
      final since = _getSincestamp(key) ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400 * 2);
      final filter = <String, dynamic>{
        'kinds': [1],
        '#t': [normalizedHashtag],
        'since': since,
        'limit': 100,
      };
      await _fetchAndStore(filter);
      _notifyFeedChanged();
      _markSynced(key);
    });
  }

  Future<void> syncInteractionsForNote(String noteId) async {
    await _sync('interactions_$noteId', () async {
      final filter = <String, dynamic>{
        'kinds': [7, 1, 5, 6, 9735],
        '#e': [noteId],
        'limit': 200,
      };
      final events = await _queryRelays(filter);
      if (events.isNotEmpty) {
        await _saveEventsAndProfiles(events);
      }
    });
  }

  Future<void> syncInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    await _sync('interactions_batch', () async {
      final limitPerNote = (500 ~/ noteIds.length).clamp(10, 100);
      final filter = <String, dynamic>{
        'kinds': [7, 1, 5, 6, 9735],
        '#e': noteIds,
        'limit': noteIds.length * limitPerNote,
      };
      final events = await _queryRelays(filter);
      if (events.isNotEmpty) {
        await _saveEventsAndProfiles(events);
      }
    });
  }

  Future<void> fetchThreadAncestors(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    try {
      final fetched = await _relayService.fetchThreadAncestors(noteIds);
      if (fetched > 0) _notifyFeedChanged();
    } catch (_) {}
  }

  Future<void> syncReplies(String noteId) async {
    await _sync('replies', () async {
      await _relayService.syncRepliesRecursive(noteId, maxDepth: 3);
      _notifyFeedChanged();
    });
  }

  Future<void> syncNote(String noteId) async {
    await _sync('note', () async {
      final allEvents = <Map<String, dynamic>>[];
      final processedIds = <String>{};
      var pendingIds = <String>[noteId];

      for (var depth = 0; depth < 5 && pendingIds.isNotEmpty; depth++) {
        final idsToFetch =
            pendingIds.where((id) => !processedIds.contains(id)).toList();
        if (idsToFetch.isEmpty) break;

        final filter = <String, dynamic>{'ids': idsToFetch};
        final events = await _queryRelays(filter);
        allEvents.addAll(events);
        for (final id in idsToFetch) {
          processedIds.add(id);
        }

        final parentIds = _extractParentIds(events);
        pendingIds =
            parentIds.where((id) => !processedIds.contains(id)).toList();
        if (allEvents.length > 200) break;
      }

      await _saveEventsAndProfiles(allEvents);
    });
  }

  Future<String> resolveThreadRoot(String noteId) async {
    try {
      return await _relayService.resolveThreadRoot(noteId);
    } catch (e) {
      if (kDebugMode) print('[SyncService] resolveThreadRoot error: $e');
      return noteId;
    }
  }

  Future<Map<String, dynamic>> fetchFullThread(
    String noteId, {
    String? currentUserPubkeyHex,
  }) async {
    final mute = EncryptedMuteService.instance;
    final result = await _relayService.fetchFullThread(
      noteId,
      currentUserPubkeyHex: currentUserPubkeyHex,
      mutedPubkeys: mute.mutedPubkeys,
      mutedWords: mute.mutedWords,
    );
    _notifyFeedChanged();
    return result;
  }

  Future<Map<String, dynamic>?> fetchFullThreadLocal(
    String noteId, {
    String? currentUserPubkeyHex,
    List<String> mutedPubkeys = const [],
    List<String> mutedWords = const [],
  }) =>
      _relayService.fetchFullThreadLocal(
        noteId,
        currentUserPubkeyHex: currentUserPubkeyHex,
        mutedPubkeys: mutedPubkeys,
        mutedWords: mutedWords,
      );

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
      await rust_db.dbDeleteEventsByIds(eventIds: eventIds);
      await rust_db.dbSaveEvents(eventsJson: jsonEncode([event]));
    } catch (_) {}
    return event;
  }

  Future<Map<String, dynamic>> publishFollow(
      {required List<String> followingPubkeys}) async {
    final event = await _publish(
        () => _publisher.createFollow(followingPubkeys: followingPubkeys));
    final pubkey = event['pubkey'] as String? ?? '';

    final listWithUser = followingPubkeys.toSet()..add(pubkey);
    await rust_db.dbSaveFollowingList(
        pubkeyHex: pubkey, followsHex: listWithUser.toList());

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
    await rust_db.dbSaveProfile(
        pubkeyHex: pubkey, profileJson: jsonEncode(profileData));
    return event;
  }

  void startPeriodicSync(String userPubkey,
      {Duration interval = const Duration(minutes: 10)}) {
    stopPeriodicSync();
    _periodicTimer = Timer.periodic(interval, (_) async {
      if (_feedSubscription != null || _notificationSubscription != null) {
        return;
      }
      await Future.wait([
        syncFeed(userPubkey),
        syncNotifications(userPubkey),
      ]);
    });
    _lastSyncCleanupTimer?.cancel();
    _lastSyncCleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _cleanupLastSyncTime();
    });
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _lastSyncCleanupTimer?.cancel();
    _lastSyncCleanupTimer = null;
  }

  void _cleanupLastSyncTime() {
    final now = DateTime.now();
    _lastSyncTime.removeWhere(
      (_, time) => now.difference(time) > _lastSyncMaxAge,
    );
  }

  Future<void> startRealtimeSubscriptions(String userPubkey) async {
    await Future.wait([
      _startFeedSubscription(userPubkey),
      _startNotificationSubscription(userPubkey),
    ]);
  }

  Future<void> _startFeedSubscription(String userPubkey) async {
    _feedSubscription?.cancel();
    try {
      final follows = await rust_db.dbGetFollowingList(pubkeyHex: userPubkey);
      if (follows.isEmpty) return;

      final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
      final filter = <String, dynamic>{
        'kinds': [1, 5, 6],
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
            final kind = (eventData['kind'] as num?)?.toInt();
            if (kind == 5) {
              await rust_db.dbProcessDeletionEvents();
              return;
            }
            if (muteService.shouldFilterEvent(eventData)) return;
            _notifyFeedChanged();
            _syncMissingProfilesInBackground([eventData]);
            if (kind == 6) {
              _fetchReferencedNoteForRepost(eventData);
            }
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
            _notifyNotificationChange();
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

  void prefetchQuotedNotes(List<String> eventIds) {
    if (eventIds.isEmpty) return;
    Future.microtask(() async {
      try {
        var ids = eventIds;
        if (ids.length > 50) ids = ids.sublist(0, 50);
        final fetched = await _relayService.fetchMissingReferences(ids);
        if (fetched > 0) _notifyFeedChanged();
      } catch (_) {}
    });
  }

  void prefetchArticlesByAuthors(List<String> pubkeys) {
    if (pubkeys.isEmpty) return;
    Future.microtask(() async {
      try {
        await syncArticles(authors: pubkeys, limit: 20);
      } catch (_) {}
    });
  }

  void dispose() {
    stopPeriodicSync();
    stopRealtimeSubscriptions();
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

    await rust_db.dbSaveEvents(eventsJson: jsonEncode([event]));

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

  Future<List<Map<String, dynamic>>> _fetchAndStore(dynamic filter) async {
    final filterMap = Map<String, dynamic>.from(filter as Map<String, dynamic>);

    final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sinceSecs = filterMap['since'] as int? ?? (nowSecs - 86400 * 2);
    final isRecent = (nowSecs - sinceSecs) <= 86400;

    if (isRecent) {
      final syncFilter = Map<String, dynamic>.from(filterMap)..remove('limit');
      if (!syncFilter.containsKey('since')) {
        syncFilter['since'] = nowSecs - 86400 * 2;
      }

      try {
        final result = await _relayService
            .syncEvents(syncFilter)
            .timeout(const Duration(seconds: 15));
        final received = result['received'] as int? ?? 0;
        if (received > 0) {
          return [];
        }
      } catch (_) {}
    }

    return await _relayService.fetchEvents(filterMap, timeoutSecs: 10);
  }

  Future<List<Map<String, dynamic>>> _queryRelays(dynamic filter) async {
    final filterMap = filter as Map<String, dynamic>;
    return await _relayService.fetchEvents(filterMap);
  }

  void _notifyFeedChanged() {
    _db.notifyFeedChange();
  }

  void _notifyProfileChanged() {
    _db.notifyProfileChange();
  }

  void _notifyInteractionChanged() {
    _db.notifyInteractionChange();
  }

  void _notifyNotificationChange() {
    _db.notifyNotificationChange();
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
    final existingProfilesJson =
        await rust_db.dbGetProfiles(pubkeysHex: pubkeys.toList());
    final existingProfiles =
        (jsonDecode(existingProfilesJson) as Map<String, dynamic>);
    final missingProfiles =
        pubkeys.where((p) => !existingProfiles.containsKey(p)).toList();
    if (missingProfiles.isNotEmpty) {
      await syncProfiles(missingProfiles);
    }
  }

  void _syncMissingProfilesInBackground(List<Map<String, dynamic>> events) {
    final pubkeys = _extractAllPubkeys(events);
    if (pubkeys.isEmpty) return;
    _fetchMissingProfilesInBackground(pubkeys.toList());
  }

  void _fetchMissingProfilesInBackground(List<String> pubkeys) {
    if (pubkeys.isEmpty) return;
    Future.microtask(() async {
      try {
        final eventsJson = jsonEncode(
          pubkeys.map((pk) => {'pubkey': pk}).toList(),
        );
        await rust_relay.fetchMissingProfilesForEvents(eventsJson: eventsJson);
        _db.notifyProfileChange(ids: pubkeys);
      } catch (_) {
        try {
          await _syncMissingProfiles(pubkeys.toSet());
          _db.notifyProfileChange(ids: pubkeys);
        } catch (_) {}
      }
    });
  }

  void _fetchRepostOriginalsInBackground(List<String> eventIds) {
    if (eventIds.isEmpty) return;
    Future.microtask(() async {
      try {
        var ids = eventIds;
        if (ids.length > 50) ids = ids.sublist(0, 50);
        final fetched = await rust_relay.fetchRepostOriginals(
          repostEventIdsJson: jsonEncode(ids),
        );
        if (fetched > 0) _notifyFeedChanged();
      } catch (_) {}
    });
  }

  Future<void> _saveEventsAndProfiles(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    _notifyFeedChanged();
    _syncMissingProfilesInBackground(events);
    _fetchReferencedEventsInBackground(events);
    _fetchThreadAncestorsInBackground(events);
  }

  void _fetchThreadAncestorsInBackground(List<Map<String, dynamic>> events) {
    final replyEventIds = <String>[];
    for (final event in events) {
      final kind = (event['kind'] as num?)?.toInt() ?? 1;
      if (kind != 1) continue;
      final tags = event['tags'] as List<dynamic>? ?? [];
      var hasParent = false;
      for (final tag in tags) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          final marker = tag.length >= 4 ? tag[3] as String? : null;
          if (marker == 'root' || marker == 'reply' || marker == null) {
            hasParent = true;
            break;
          }
        }
      }
      if (hasParent) {
        final id = event['id'] as String? ?? '';
        if (id.isNotEmpty) replyEventIds.add(id);
      }
    }
    if (replyEventIds.isEmpty) return;

    Future.microtask(() async {
      try {
        var ids = replyEventIds;
        if (ids.length > 40) ids = ids.sublist(0, 40);
        final fetched = await _relayService.fetchThreadAncestors(ids);
        if (fetched > 0) _notifyFeedChanged();
      } catch (_) {}
    });
  }

  void _fetchReferencedNoteForRepost(Map<String, dynamic> repostEvent) {
    final tags = repostEvent['tags'] as List<dynamic>? ?? [];
    for (final tag in tags) {
      if (tag is List && tag.length > 1 && tag[0] == 'e') {
        final originalId = tag[1] as String?;
        if (originalId != null && originalId.isNotEmpty) {
          _fetchRepostOriginalsInBackground([originalId]);
          return;
        }
      }
    }
  }

  void _fetchReferencedEventsInBackground(List<Map<String, dynamic>> events) {
    final repostOriginalIds = <String>{};
    for (final event in events) {
      final kind = (event['kind'] as num?)?.toInt();
      if (kind != 6) continue;
      final tags = event['tags'] as List<dynamic>? ?? [];
      for (final tag in tags) {
        if (tag is List && tag.length > 1 && tag[0] == 'e') {
          final id = tag[1] as String?;
          if (id != null && id.isNotEmpty) {
            repostOriginalIds.add(id);
            break;
          }
        }
      }
    }
    if (repostOriginalIds.isEmpty) return;
    _fetchRepostOriginalsInBackground(repostOriginalIds.toList());
  }

  Future<void> _queueMissingRepostOriginals(int sinceTimestamp) async {
    try {
      final filterJson = jsonEncode({
        'kinds': [6],
        'since': sinceTimestamp,
      });
      final repostEventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: 100);
      final repostEvents = (jsonDecode(repostEventsJson) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      _fetchReferencedEventsInBackground(repostEvents);
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

  Future<Map<String, dynamic>> getRelayStatus() =>
      _relayService.getRelayStatus();

  List<String> get relayUrls => _relayService.relayUrls;

  Future<bool> broadcastEvent(Map<String, dynamic> event) =>
      _relayService.broadcastEvent(event);

  Future<Map<String, dynamic>> broadcastEvents(
    List<Map<String, dynamic>> events, {
    List<String>? relayUrls,
  }) =>
      _relayService.broadcastEvents(events, relayUrls: relayUrls);

  Future<List<Map<String, dynamic>>> fetchEventsForAuthor(
    String pubkeyHex, {
    int timeoutSecs = 30,
  }) =>
      _relayService.fetchEvents(
        {
          'authors': [pubkeyHex]
        },
        timeoutSecs: timeoutSecs,
      );

  Future<List<Map<String, dynamic>>> fetchEventsWithFilter(
    Map<String, dynamic> filter, {
    int timeoutSecs = 10,
  }) =>
      _relayService.fetchEvents(filter, timeoutSecs: timeoutSecs);

  Stream<Map<String, dynamic>> fetchAllEventsForAuthor(String pubkeyHex) =>
      _relayService.fetchAllEventsForAuthor(pubkeyHex);

  Stream<Map<String, dynamic>> streamBroadcastEvents(
          List<Map<String, dynamic>> events) =>
      _relayService.streamBroadcastEvents(events);

  Future<Map<String, dynamic>> sendEventJson(String eventJson) =>
      _relayService.sendEvent(eventJson);

  Future<void> reloadCustomRelays() => _relayService.reloadCustomRelays();

  Stream<Map<String, dynamic>> streamRelayStatus() =>
      _relayService.streamRelayStatus();
}
