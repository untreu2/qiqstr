import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../../src/rust/api/relay.dart' as rust_relay;

class RustDatabaseService {
  static final RustDatabaseService _instance = RustDatabaseService._internal();
  static RustDatabaseService get instance => _instance;

  RustDatabaseService._internal();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  final _changeController = StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;

  void notifyChange() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  Future<void> initialize() async {
    _initialized = true;
    autoCleanupIfNeeded();
  }

  Future<void> close() async {}

  Future<Map<String, String>?> getUserProfile(String pubkeyHex) async {
    try {
      final json = await rust_db.dbGetProfile(pubkeyHex: pubkeyHex);
      if (json == null) return null;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return _metadataToProfileMap(pubkeyHex, decoded);
    } catch (e) {
      if (kDebugMode) print('[RustDB] getUserProfile error: $e');
      return null;
    }
  }

  Future<Map<String, Map<String, String>>> getUserProfiles(
      List<String> pubkeyHexList) async {
    try {
      final json = await rust_db.dbGetProfiles(pubkeysHex: pubkeyHexList);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        final meta = entry.value as Map<String, dynamic>;
        result[entry.key] = _metadataToProfileMap(entry.key, meta);
      }
      return result;
    } catch (e) {
      if (kDebugMode) print('[RustDB] getUserProfiles error: $e');
      return {};
    }
  }

  Future<bool> hasUserProfile(String pubkeyHex) async {
    try {
      return await rust_db.dbHasProfile(pubkeyHex: pubkeyHex);
    } catch (_) {
      return false;
    }
  }

  Future<void> saveUserProfile(
      String pubkeyHex, Map<String, String> profileData) async {
    try {
      final profileJson = jsonEncode(profileData);
      await rust_db.dbSaveProfile(
          pubkeyHex: pubkeyHex, profileJson: profileJson);
      notifyChange();
    } catch (e) {
      if (kDebugMode) print('[RustDB] saveUserProfile error: $e');
    }
  }

  Future<void> saveUserProfiles(
      Map<String, Map<String, String>> profiles) async {
    for (final entry in profiles.entries) {
      await saveUserProfile(entry.key, entry.value);
    }
  }

  Future<List<Map<String, dynamic>>> searchUserProfiles(String query,
      {int limit = 50}) async {
    try {
      final json = await rust_db.dbSearchProfiles(query: query, limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] searchUserProfiles error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRandomUsersWithImages(
      {int limit = 50}) async {
    try {
      final json = await rust_db.dbGetRandomProfiles(limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getRandomUsersWithImages error: $e');
      return [];
    }
  }

  Stream<Map<String, dynamic>?> watchProfile(String pubkey) {
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 500))
        .startWith(null)
        .asyncMap((_) async {
      final profile = await getUserProfile(pubkey);
      if (profile == null) return null;
      return <String, dynamic>{...profile};
    });
  }

  Future<List<String>?> getFollowingList(String userPubkeyHex) async {
    try {
      final list = await rust_db.dbGetFollowingList(pubkeyHex: userPubkeyHex);
      if (list.isEmpty) return null;
      return list;
    } catch (e) {
      if (kDebugMode) print('[RustDB] getFollowingList error: $e');
      return null;
    }
  }

  Future<void> saveFollowingList(
      String userPubkeyHex, List<String> followingList) async {
    try {
      await rust_db.dbSaveFollowingList(
          pubkeyHex: userPubkeyHex, followsHex: followingList);
      notifyChange();
    } catch (e) {
      if (kDebugMode) print('[RustDB] saveFollowingList error: $e');
    }
  }

  Future<bool> hasFollowingList(String userPubkeyHex) async {
    try {
      return await rust_db.dbHasFollowingList(pubkeyHex: userPubkeyHex);
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteFollowingList(String userPubkeyHex) async {
    try {
      await rust_db.dbDeleteFollowingList(pubkeyHex: userPubkeyHex);
    } catch (e) {
      if (kDebugMode) print('[RustDB] deleteFollowingList error: $e');
    }
  }

  Stream<List<String>> watchFollowingList(String userPubkeyHex) {
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 500))
        .startWith(null)
        .asyncMap((_) async {
      final list = await getFollowingList(userPubkeyHex);
      return list ?? [];
    });
  }

  Future<List<String>?> getMuteList(String userPubkeyHex) async {
    try {
      final list = await rust_db.dbGetMuteList(pubkeyHex: userPubkeyHex);
      if (list.isEmpty) return null;
      return list;
    } catch (e) {
      if (kDebugMode) print('[RustDB] getMuteList error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getRawMuteEvent(String userPubkeyHex) async {
    try {
      final filterJson = jsonEncode({
        'kinds': [10000],
        'authors': [userPubkeyHex],
      });
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: 1);
      final events = jsonDecode(eventsJson) as List<dynamic>;
      if (events.isEmpty) return null;
      return events.first as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) print('[RustDB] getRawMuteEvent error: $e');
      return null;
    }
  }

  Future<void> saveMuteList(String userPubkeyHex, List<String> muteList) async {
    try {
      await rust_db.dbSaveMuteList(
          pubkeyHex: userPubkeyHex, mutedHex: muteList);
    } catch (e) {
      if (kDebugMode) print('[RustDB] saveMuteList error: $e');
    }
  }

  Future<bool> hasMuteList(String userPubkeyHex) async {
    try {
      return await rust_db.dbHasMuteList(pubkeyHex: userPubkeyHex);
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteMuteList(String userPubkeyHex) async {
    try {
      await rust_db.dbDeleteMuteList(pubkeyHex: userPubkeyHex);
    } catch (e) {
      if (kDebugMode) print('[RustDB] deleteMuteList error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getCachedFeedNotes(
      List<String> authorPubkeys,
      {int limit = 100}) async {
    try {
      final json =
          await rust_db.dbGetFeedNotes(authorsHex: authorPubkeys, limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getCachedFeedNotes error: $e');
      return [];
    }
  }

  Future<void> saveFeedNotes(List<Map<String, dynamic>> notes) async {
    try {
      final json = jsonEncode(notes);
      await rust_db.dbSaveEvents(eventsJson: json);
      notifyChange();
    } catch (e) {
      if (kDebugMode) print('[RustDB] saveFeedNotes error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getCachedProfileNotes(String authorPubkey,
      {int limit = 50}) async {
    try {
      final json = await rust_db.dbGetProfileNotes(
          pubkeyHex: authorPubkey, limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getCachedProfileNotes error: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> watchFeedNotes(List<String> authors,
      {int limit = 100}) {
    List<Map<String, dynamic>>? lastResult;
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) async {
      final result = await getCachedFeedNotes(authors, limit: limit);
      if (lastResult != null && result.length == lastResult!.length) {
        final newFirst = result.isNotEmpty ? result.first['id'] : null;
        final oldFirst =
            lastResult!.isNotEmpty ? lastResult!.first['id'] : null;
        if (newFirst == oldFirst) return lastResult!;
      }
      lastResult = result;
      return result;
    });
  }

  Stream<List<Map<String, dynamic>>> watchProfileNotes(String pubkey,
      {int limit = 50}) {
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) => getCachedProfileNotes(pubkey, limit: limit));
  }

  Stream<List<Map<String, dynamic>>> watchHashtagNotes(String hashtag,
      {int limit = 100}) {
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) async {
      try {
        final json =
            await rust_db.dbGetHashtagNotes(hashtag: hashtag, limit: limit);
        final decoded = jsonDecode(json) as List<dynamic>;
        return decoded.cast<Map<String, dynamic>>();
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    });
  }

  Future<Map<String, dynamic>?> getEvent(String eventId) async {
    try {
      final json = await rust_db.dbGetEvent(eventId: eventId);
      if (json == null) return null;
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) print('[RustDB] getEvent error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getEventModel(String eventId) async {
    return getEvent(eventId);
  }

  Future<bool> eventExists(String eventId) async {
    try {
      return await rust_db.dbEventExists(eventId: eventId);
    } catch (_) {
      return false;
    }
  }

  Future<void> saveEvents(List<Map<String, dynamic>> events) async {
    try {
      final json = jsonEncode(events);
      await rust_db.dbSaveEvents(eventsJson: json);
      notifyChange();
    } catch (e) {
      if (kDebugMode) print('[RustDB] saveEvents error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getReplies(String noteId,
      {int limit = 500}) async {
    try {
      final json = await rust_db.dbGetReplies(noteId: noteId, limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getReplies error: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> watchReplies(String noteId,
      {int limit = 100}) {
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) => getReplies(noteId, limit: limit));
  }

  Future<List<Map<String, dynamic>>> getCachedNotifications(String userPubkey,
      {int limit = 100}) async {
    try {
      final json = await rust_db.dbGetNotifications(
          userPubkeyHex: userPubkey, limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getCachedNotifications error: $e');
      return [];
    }
  }

  Future<void> saveNotifications(
      String userPubkey, List<Map<String, dynamic>> notifications) async {
    try {
      final json = jsonEncode(notifications);
      await rust_db.dbSaveEvents(eventsJson: json);
      notifyChange();
    } catch (e) {
      if (kDebugMode) print('[RustDB] saveNotifications error: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> watchNotifications(String userPubkey,
      {int limit = 100}) {
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) => getCachedNotifications(userPubkey, limit: limit));
  }

  Future<Map<String, int>> getInteractionCounts(String noteId) async {
    try {
      final json = await rust_db.dbGetInteractionCounts(noteId: noteId);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as int));
    } catch (e) {
      if (kDebugMode) print('[RustDB] getInteractionCounts error: $e');
      return {'reactions': 0, 'reposts': 0, 'zaps': 0, 'replies': 0};
    }
  }

  Future<Map<String, Map<String, int>>> getCachedInteractionCounts(
      List<String> noteIds) async {
    try {
      final json = await rust_db.dbGetBatchInteractionCounts(noteIds: noteIds);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final result = <String, Map<String, int>>{};
      for (final entry in decoded.entries) {
        final counts = entry.value as Map<String, dynamic>;
        result[entry.key] = counts.map((k, v) => MapEntry(k, v as int));
      }
      return result;
    } catch (e) {
      if (kDebugMode) print('[RustDB] getCachedInteractionCounts error: $e');
      return {};
    }
  }

  Future<Map<String, Map<String, dynamic>>> getBatchInteractionData(
      List<String> noteIds, String userPubkey) async {
    try {
      final json = await rust_db.dbGetBatchInteractionData(
          noteIds: noteIds, userPubkeyHex: userPubkey);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final result = <String, Map<String, dynamic>>{};
      for (final entry in decoded.entries) {
        result[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
      return result;
    } catch (e) {
      if (kDebugMode) print('[RustDB] getBatchInteractionData error: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getDetailedInteractions(
      String noteId) async {
    try {
      final json = await rust_db.dbGetDetailedInteractions(noteId: noteId);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getDetailedInteractions error: $e');
      return [];
    }
  }

  Future<bool> hasUserReacted(String noteId, String userPubkey) async {
    try {
      return await rust_db.dbHasUserReacted(
          noteId: noteId, userPubkeyHex: userPubkey);
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasUserReposted(String noteId, String userPubkey) async {
    try {
      return await rust_db.dbHasUserReposted(
          noteId: noteId, userPubkeyHex: userPubkey);
    } catch (_) {
      return false;
    }
  }

  Future<String?> findUserRepostEventId(
      String userPubkey, String noteId) async {
    try {
      return await rust_db.dbFindUserRepostEventId(
          userPubkeyHex: userPubkey, noteId: noteId);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getCachedArticles(
      {int limit = 50, List<String>? authors}) async {
    try {
      final String json;
      if (authors != null && authors.isNotEmpty) {
        json = await rust_db.dbGetArticlesByAuthors(
            authorsHex: authors, limit: limit);
      } else {
        json = await rust_db.dbGetArticles(limit: limit);
      }
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getCachedArticles error: $e');
      return [];
    }
  }

  Future<void> saveArticles(List<Map<String, dynamic>> articles) async {
    try {
      final json = jsonEncode(articles);
      await rust_db.dbSaveEvents(eventsJson: json);
      notifyChange();
    } catch (e) {
      if (kDebugMode) print('[RustDB] saveArticles error: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> watchArticles(
      {int limit = 50, List<String>? authors}) {
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 500))
        .startWith(null)
        .asyncMap((_) => getCachedArticles(limit: limit, authors: authors));
  }

  Future<List<Map<String, dynamic>>> searchNotes(String query,
      {int limit = 50}) async {
    try {
      final json = await rust_db.dbSearchNotes(query: query, limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] searchNotes error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> queryEvents(String filterJson,
      {int limit = 50}) async {
    try {
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: limit);
      final events = jsonDecode(eventsJson) as List<dynamic>;
      return events.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] queryEvents error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProfileReactions(String authorPubkey,
      {int limit = 50}) async {
    try {
      final filterJson = jsonEncode({
        'kinds': [7],
        'authors': [authorPubkey],
      });
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: limit);
      final decoded = jsonDecode(eventsJson) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getProfileReactions error: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> watchProfileReactions(String pubkey,
      {int limit = 50}) {
    return _changeController.stream
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) => getProfileReactions(pubkey, limit: limit));
  }

  Future<void> wipe() async {
    try {
      await rust_db.dbWipe();
    } catch (e) {
      if (kDebugMode) print('[RustDB] wipe error: $e');
    }
  }

  Future<int> cleanupOldEvents({int daysToKeep = 30}) async {
    try {
      final count = await rust_db.dbCleanupOldEvents(daysToKeep: daysToKeep);
      notifyChange();
      return count;
    } catch (e) {
      if (kDebugMode) print('[LMDB] cleanupOldEvents error: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final json = await rust_db.dbGetDatabaseStats();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      if (kDebugMode) print('[LMDB] getDatabaseStats error: $e');
      return {};
    }
  }

  Future<void> autoCleanupIfNeeded() async {
    try {
      final sizeMb = await getDatabaseSizeMB();
      final stats = await getDatabaseStats();
      final totalEvents = stats['totalEvents'] as int? ?? 0;

      if (kDebugMode) {
        print('[LMDB] Database size: ${sizeMb}MB | Total events: $totalEvents');
      }

      if (sizeMb > 1024) {
        if (kDebugMode) {
          print(
              '[LMDB] Database size exceeded 1GB threshold, starting cleanup...');
        }

        final deletedCount = await cleanupOldEvents(daysToKeep: 30);
        final newSize = await getDatabaseSizeMB();
        final newStats = await getDatabaseStats();
        final newTotalEvents = newStats['totalEvents'] as int? ?? 0;

        if (kDebugMode) {
          print('[LMDB] Cleanup completed:');
          print('[LMDB]   - Deleted events: $deletedCount');
          print('[LMDB]   - Old size: ${sizeMb}MB → New size: ${newSize}MB');
          print(
              '[LMDB]   - Old events: $totalEvents → New events: $newTotalEvents');
        }
      } else {
        if (kDebugMode) {
          print('[LMDB] Database size OK (below 1GB threshold)');
        }
      }
    } catch (e) {
      if (kDebugMode) print('[LMDB] autoCleanupIfNeeded error: $e');
    }
  }

  Future<int> getDatabaseSizeMB() async {
    try {
      final size = await rust_relay.getDatabaseSizeMb();
      return size.toInt();
    } catch (e) {
      if (kDebugMode) print('[LMDB] getDatabaseSizeMB error: $e');
      return 0;
    }
  }

  Map<String, String> _metadataToProfileMap(
      String pubkey, Map<String, dynamic> metadata) {
    final result = <String, String>{};
    result['pubkey'] = pubkey;

    void addIfPresent(String key, dynamic value) {
      if (value != null && value.toString().isNotEmpty) {
        result[key] = value.toString();
      }
    }

    addIfPresent('name', metadata['name']);
    addIfPresent('display_name', metadata['display_name']);
    addIfPresent('about', metadata['about']);
    addIfPresent('picture', metadata['picture']);
    addIfPresent('banner', metadata['banner']);
    addIfPresent('nip05', metadata['nip05']);
    addIfPresent('lud16', metadata['lud16']);
    addIfPresent('lud06', metadata['lud06']);
    addIfPresent('website', metadata['website']);
    addIfPresent('location', metadata['location']);

    return result;
  }
}
