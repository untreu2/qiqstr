import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/event_model.dart';
export '../../models/event_model.dart' show SyncStatus;

class IsarDatabaseService {
  static IsarDatabaseService? _instance;
  static IsarDatabaseService get instance =>
      _instance ??= IsarDatabaseService._internal();

  IsarDatabaseService._internal();

  Isar? _isar;
  bool _isInitialized = false;
  bool _isInitializing = false;
  Completer<void> _initCompleter = Completer<void>();

  List<String> _extractPubkeysFromTags(List<List<String>> tags) {
    return tags
        .where((tag) => tag.length > 1 && tag[0] == 'p' && tag[1].isNotEmpty)
        .map((tag) => tag[1])
        .toList();
  }

  Map<String, String>? _parseProfileContent(String content) {
    if (content.isEmpty) return null;
    try {
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final result = <String, String>{};
      parsed.forEach((key, value) {
        result[key == 'picture' ? 'profileImage' : key] =
            value?.toString() ?? '';
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _profileDataToContentMap(
      Map<String, String> profileData) {
    final contentMap = <String, dynamic>{};
    profileData.forEach((key, value) {
      contentMap[key == 'profileImage' ? 'picture' : key] = value;
    });
    return contentMap;
  }

  Future<Map<String, List<String>>> _getPubkeyLists(
      List<String> userPubkeys, int kind) async {
    final result = <String, List<String>>{};
    if (userPubkeys.isEmpty) return result;
    try {
      final db = await isar;
      final events = await db.eventModels
          .filter()
          .kindEqualTo(kind)
          .anyOf(userPubkeys, (q, pubkey) => q.pubkeyEqualTo(pubkey))
          .sortByCreatedAtDesc()
          .findAll();

      final seen = <String>{};
      for (final event in events) {
        if (seen.contains(event.pubkey)) continue;
        seen.add(event.pubkey);
        final list = _extractPubkeysFromTags(event.getTags());
        if (list.isNotEmpty) result[event.pubkey] = list;
      }
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting pubkey lists: $e');
    }
    return result;
  }

  Future<void> _savePubkeyList(String userPubkey, List<String> pubkeys,
      int kind, String idPrefix) async {
    try {
      final db = await isar;
      final tags = pubkeys.map((p) => ['p', p]).toList();
      final tagsSerialized = tags.map((tag) => jsonEncode(tag)).toList();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eventId = '${idPrefix}_$userPubkey';

      await db.writeTxn(() async {
        final existing =
            await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
        final eventModel = existing ?? EventModel();
        eventModel.eventId = eventId;
        eventModel.pubkey = userPubkey;
        eventModel.kind = kind;
        eventModel.createdAt = now;
        eventModel.content = '';
        eventModel.tags = tagsSerialized;
        eventModel.sig = '';
        eventModel.rawEvent = jsonEncode({
          'id': eventId,
          'pubkey': userPubkey,
          'kind': kind,
          'created_at': now,
          'content': '',
          'tags': tags,
          'sig': '',
        });
        eventModel.cachedAt = DateTime.now();
        await db.eventModels.put(eventModel);
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving pubkey list: $e');
    }
  }

  Future<void> _savePubkeyLists(
      Map<String, List<String>> lists, int kind, String idPrefix) async {
    try {
      final db = await isar;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.writeTxn(() async {
        for (final entry in lists.entries) {
          final tags = entry.value.map((p) => ['p', p]).toList();
          final tagsSerialized = tags.map((tag) => jsonEncode(tag)).toList();
          final eventId = '${idPrefix}_${entry.key}';

          final existing =
              await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
          final eventModel = existing ?? EventModel();
          eventModel.eventId = eventId;
          eventModel.pubkey = entry.key;
          eventModel.kind = kind;
          eventModel.createdAt = now;
          eventModel.content = '';
          eventModel.tags = tagsSerialized;
          eventModel.sig = '';
          eventModel.rawEvent = jsonEncode({
            'id': eventId,
            'pubkey': entry.key,
            'kind': kind,
            'created_at': now,
            'content': '',
            'tags': tags,
            'sig': '',
          });
          eventModel.cachedAt = DateTime.now();
          await db.eventModels.put(eventModel);
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving pubkey lists: $e');
    }
  }

  Future<Isar> get isar async {
    if (_isInitialized) {
      return _isar!;
    }

    if (_isInitializing) {
      await _initCompleter.future;
      return _isar!;
    }

    await initialize();
    return _isar!;
  }

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_isInitializing) {
      await _initCompleter.future;
      return;
    }

    _isInitializing = true;

    try {
      debugPrint('[IsarDatabaseService] Initializing Isar database...');

      final dir = await getApplicationDocumentsDirectory();

      _isar = await Isar.open(
        [EventModelSchema],
        directory: dir.path,
        name: 'qiqstr_db',
        inspector: kDebugMode,
      );

      _isInitialized = true;
      _isInitializing = false;
      _initCompleter.complete();

      debugPrint(
          '[IsarDatabaseService] Isar database initialized successfully');
      debugPrint('[IsarDatabaseService] Database path: ${dir.path}');
    } catch (e) {
      _isInitializing = false;
      debugPrint('[IsarDatabaseService] Error initializing Isar: $e');
      _initCompleter.completeError(e);
      _initCompleter = Completer<void>();
      rethrow;
    }
  }

  Future<void> waitForInitialization() async {
    await _initCompleter.future;
  }

  Future<void> close() async {
    if (_isar != null && _isar!.isOpen) {
      await _isar!.close();
      _isInitialized = false;
      debugPrint('[IsarDatabaseService] Database closed');
    }
  }

  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final db = await isar;
      final dbSize = await db.getSize();

      return {
        'databaseSize': '${(dbSize / 1024 / 1024).toStringAsFixed(2)} MB',
        'databaseSizeBytes': dbSize,
        'isInitialized': _isInitialized,
      };
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting statistics: $e');
      return {
        'error': e.toString(),
        'isInitialized': _isInitialized,
      };
    }
  }

  Future<void> printStatistics() async {
    final stats = await getStatistics();
    debugPrint('\n=== Isar Database Statistics ===');
    stats.forEach((key, value) {
      debugPrint('  $key: $value');
    });
    debugPrint('===============================\n');
  }

  static void reset() {
    _instance?._isar?.close();
    _instance = null;
  }

  Future<List<String>?> getFollowingList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final event = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkeyHex)
          .kindEqualTo(3)
          .sortByCreatedAtDesc()
          .findFirst();
      if (event == null) return null;

      final list = _extractPubkeysFromTags(event.getTags());
      return list.isEmpty ? null : list;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting following list: $e');
      return null;
    }
  }

  Future<void> saveFollowingList(
      String userPubkeyHex, List<String> followingList) async {
    await _savePubkeyList(userPubkeyHex, followingList, 3, 'following_list');
  }

  Stream<List<String>> watchFollowingList(String userPubkeyHex) async* {
    final db = await isar;
    yield* db.eventModels
        .filter()
        .pubkeyEqualTo(userPubkeyHex)
        .kindEqualTo(3)
        .sortByCreatedAtDesc()
        .limit(1)
        .watch(fireImmediately: true)
        .map((events) {
      if (events.isEmpty) return <String>[];
      return _extractPubkeysFromTags(events.first.getTags());
    });
  }

  Future<Map<String, List<String>>> getFollowingLists(
      List<String> userPubkeyHexList) async {
    return _getPubkeyLists(userPubkeyHexList, 3);
  }

  Future<void> saveFollowingLists(
      Map<String, List<String>> followingLists) async {
    await _savePubkeyLists(followingLists, 3, 'following_list');
  }

  Future<bool> hasFollowingList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final exists = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkeyHex)
          .kindEqualTo(3)
          .isEmpty();
      return !exists;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking following list: $e');
      return false;
    }
  }

  Future<void> deleteFollowingList(String userPubkeyHex) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.eventModels
            .filter()
            .pubkeyEqualTo(userPubkeyHex)
            .kindEqualTo(3)
            .deleteAll();
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error deleting following list: $e');
    }
  }

  Future<void> clearAllFollowingLists() async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.eventModels.filter().kindEqualTo(3).deleteAll();
      });
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error clearing all following lists: $e');
    }
  }

  Future<List<String>?> getMuteList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final event = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkeyHex)
          .kindEqualTo(10000)
          .sortByCreatedAtDesc()
          .findFirst();
      if (event == null) return null;

      final list = _extractPubkeysFromTags(event.getTags());
      return list.isEmpty ? null : list;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting mute list: $e');
      return null;
    }
  }

  Future<void> saveMuteList(String userPubkeyHex, List<String> muteList) async {
    await _savePubkeyList(userPubkeyHex, muteList, 10000, 'mute_list');
  }

  Future<Map<String, List<String>>> getMuteLists(
      List<String> userPubkeyHexList) async {
    return _getPubkeyLists(userPubkeyHexList, 10000);
  }

  Future<void> saveMuteLists(Map<String, List<String>> muteLists) async {
    await _savePubkeyLists(muteLists, 10000, 'mute_list');
  }

  Future<bool> hasMuteList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final exists = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkeyHex)
          .kindEqualTo(10000)
          .isEmpty();
      return !exists;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking mute list: $e');
      return false;
    }
  }

  Future<void> deleteMuteList(String userPubkeyHex) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.eventModels
            .filter()
            .pubkeyEqualTo(userPubkeyHex)
            .kindEqualTo(10000)
            .deleteAll();
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error deleting mute list: $e');
    }
  }

  Future<void> clearAllMuteLists() async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.eventModels.filter().kindEqualTo(10000).deleteAll();
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error clearing all mute lists: $e');
    }
  }

  Future<Map<String, String>?> getUserProfile(String pubkeyHex) async {
    try {
      final db = await isar;
      final event = await db.eventModels
          .filter()
          .pubkeyEqualTo(pubkeyHex)
          .kindEqualTo(0)
          .sortByCreatedAtDesc()
          .findFirst();
      if (event == null) return null;
      return _parseProfileContent(event.content);
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting user profile: $e');
      return null;
    }
  }

  Future<void> saveUserProfile(
      String pubkeyHex, Map<String, String> profileData) async {
    try {
      final db = await isar;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eventId = 'profile_$pubkeyHex';
      final contentMap = _profileDataToContentMap(profileData);
      final contentJson = jsonEncode(contentMap);

      await db.writeTxn(() async {
        final existing =
            await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
        final eventModel = existing ?? EventModel();
        eventModel.eventId = eventId;
        eventModel.pubkey = pubkeyHex;
        eventModel.kind = 0;
        eventModel.createdAt = now;
        eventModel.content = contentJson;
        eventModel.tags = [];
        eventModel.sig = '';
        eventModel.rawEvent = jsonEncode({
          'id': eventId,
          'pubkey': pubkeyHex,
          'kind': 0,
          'created_at': now,
          'content': contentJson,
          'tags': [],
          'sig': '',
        });
        eventModel.cachedAt = DateTime.now();
        await db.eventModels.put(eventModel);
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving user profile: $e');
    }
  }

  Future<Map<String, Map<String, String>>> getUserProfiles(
      List<String> pubkeyHexList) async {
    final result = <String, Map<String, String>>{};
    if (pubkeyHexList.isEmpty) return result;

    try {
      final db = await isar;
      final pubkeySet = pubkeyHexList.toSet();

      final profileEvents = await db.eventModels
          .filter()
          .kindEqualTo(0)
          .anyOf(pubkeyHexList, (q, pubkey) => q.pubkeyEqualTo(pubkey))
          .sortByCreatedAtDesc()
          .findAll();

      final seen = <String>{};
      for (final event in profileEvents) {
        if (!pubkeySet.contains(event.pubkey) || seen.contains(event.pubkey)) {
          continue;
        }
        seen.add(event.pubkey);

        final profileData = _parseProfileContent(event.content);
        if (profileData != null && profileData.isNotEmpty) {
          result[event.pubkey] = profileData;
        }
      }
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting user profiles: $e');
    }
    return result;
  }

  Future<void> saveUserProfiles(
      Map<String, Map<String, String>> profiles) async {
    try {
      final db = await isar;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.writeTxn(() async {
        for (final entry in profiles.entries) {
          final eventId = 'profile_${entry.key}';
          final contentMap = _profileDataToContentMap(entry.value);
          final contentJson = jsonEncode(contentMap);

          final existing =
              await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
          final eventModel = existing ?? EventModel();
          eventModel.eventId = eventId;
          eventModel.pubkey = entry.key;
          eventModel.kind = 0;
          eventModel.createdAt = now;
          eventModel.content = contentJson;
          eventModel.tags = [];
          eventModel.sig = '';
          eventModel.rawEvent = jsonEncode({
            'id': eventId,
            'pubkey': entry.key,
            'kind': 0,
            'created_at': now,
            'content': contentJson,
            'tags': [],
            'sig': '',
          });
          eventModel.cachedAt = DateTime.now();
          await db.eventModels.put(eventModel);
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving user profiles: $e');
    }
  }

  Future<bool> hasUserProfile(String pubkeyHex) async {
    try {
      final db = await isar;
      final exists = await db.eventModels
          .filter()
          .pubkeyEqualTo(pubkeyHex)
          .kindEqualTo(0)
          .isEmpty();
      return !exists;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking user profile: $e');
      return false;
    }
  }

  Future<int> getUserProfileCount() async {
    try {
      final db = await isar;
      final count = await db.eventModels.filter().kindEqualTo(0).count();
      return count;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting user profile count: $e');
      return 0;
    }
  }

  Future<List<Map<String, String>>> searchUserProfiles(String query,
      {int limit = 50}) async {
    if (query.isEmpty) return [];
    try {
      final db = await isar;
      final matchingEvents = await db.eventModels
          .filter()
          .kindEqualTo(0)
          .contentContains(query, caseSensitive: false)
          .sortByCreatedAtDesc()
          .limit(limit * 2)
          .findAll();

      final matchingProfiles = <Map<String, String>>[];
      final seen = <String>{};
      for (final event in matchingEvents) {
        if (seen.contains(event.pubkey)) continue;
        seen.add(event.pubkey);
        if (matchingProfiles.length >= limit) break;
        final profileData = _parseProfileContent(event.content);
        if (profileData == null) continue;
        profileData['pubkeyHex'] = event.pubkey;
        matchingProfiles.add(profileData);
      }
      return matchingProfiles;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error searching user profiles: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> getRandomUsersWithImages(
      {int limit = 50}) async {
    try {
      final db = await isar;
      final profileEvents = await db.eventModels
          .filter()
          .kindEqualTo(0)
          .contentContains('picture', caseSensitive: false)
          .limit(limit * 3)
          .findAll();

      final profilesWithImages = <Map<String, String>>[];
      final seen = <String>{};
      for (final event in profileEvents) {
        if (seen.contains(event.pubkey)) continue;
        seen.add(event.pubkey);
        final profileData = _parseProfileContent(event.content);
        if (profileData == null) continue;

        final image = profileData['profileImage'] ?? '';
        if (image.isNotEmpty) {
          profileData['pubkeyHex'] = event.pubkey;
          profilesWithImages.add(profileData);
        }
      }

      profilesWithImages.shuffle();
      return profilesWithImages.take(limit).toList();
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error getting random users with images: $e');
      return [];
    }
  }

  Future<List<EventModel>> getCachedFeedNotes(List<String> authorPubkeys,
      {int limit = 100}) async {
    if (authorPubkeys.isEmpty) return [];

    try {
      final db = await isar;
      final result = <EventModel>[];
      final targetCount = limit * 3;

      final events = await db.eventModels
          .filter()
          .anyOf(authorPubkeys, (q, pubkey) => q.pubkeyEqualTo(pubkey))
          .group((q) => q.kindEqualTo(1).or().kindEqualTo(6))
          .sortByCreatedAtDesc()
          .limit(targetCount)
          .findAll();

      for (final event in events) {
        if (event.kind == 6) {
          result.add(event);
        } else if (event.kind == 1 && !_isReplyNote(event)) {
          result.add(event);
        }
        if (result.length >= limit) break;
      }

      return result;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting cached feed notes: $e');
      return [];
    }
  }

  bool _isReplyNote(EventModel event) {
    // NIP-10 compliant reply detection
    // A note is a reply if it has e-tags with root/reply markers,
    // OR unmarked e-tags (deprecated threading style)
    // Notes with only 'q' tags (quotes) or only 'mention' markers are NOT replies
    final tags = event.getTags();
    bool hasQTag = false;
    bool hasRootOrReplyMarker = false;
    final unmarkedETags = <String>[];

    for (final tag in tags) {
      if (tag.isEmpty || tag.length < 2) continue;

      if (tag[0] == 'q') {
        hasQTag = true;
        continue;
      }

      if (tag[0] == 'e') {
        if (tag.length >= 4) {
          final marker = tag[3];
          if (marker == 'root' || marker == 'reply') {
            hasRootOrReplyMarker = true;
          }
          // 'mention' marker means it's just a reference, not a reply - ignore it
        } else {
          // No marker = deprecated NIP-10 style, treat as reply reference
          unmarkedETags.add(tag[1]);
        }
      }
    }

    // Quote posts (q tag) are new threads, not replies
    if (hasQTag && !hasRootOrReplyMarker && unmarkedETags.isEmpty) {
      return false;
    }

    // Has explicit root or reply marker = definitely a reply
    if (hasRootOrReplyMarker) {
      return true;
    }

    // Deprecated style: unmarked e-tags = reply (first is root, last is reply)
    if (unmarkedETags.isNotEmpty) {
      return true;
    }

    return false;
  }

  Future<List<EventModel>> getCachedProfileNotes(String authorPubkey,
      {int limit = 50}) async {
    try {
      final db = await isar;

      final events = await db.eventModels
          .filter()
          .pubkeyEqualTo(authorPubkey)
          .group((q) => q.kindEqualTo(1).or().kindEqualTo(6))
          .sortByCreatedAtDesc()
          .limit(limit * 3)
          .findAll();

      final result = <EventModel>[];
      for (final event in events) {
        if (event.kind == 6) {
          result.add(event);
        } else if (event.kind == 1 && !_isReplyNote(event)) {
          result.add(event);
        }
        if (result.length >= limit) break;
      }

      return result;
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error getting cached profile notes: $e');
      return [];
    }
  }

  Future<void> saveFeedNotes(List<Map<String, dynamic>> notes) async {
    if (notes.isEmpty) return;

    try {
      final db = await isar;

      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final note in notes) {
        final eventId = note['id'] as String?;
        if (eventId != null && eventId.isNotEmpty && seen.add(eventId)) {
          unique.add(note);
        }
      }
      if (unique.isEmpty) return;

      await db.writeTxn(() async {
        for (final note in unique) {
          final eventId = note['id'] as String;
          final existing =
              await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
          if (existing == null) {
            await db.eventModels.put(EventModel.fromEventData(note));
          }
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving feed notes: $e');
    }
  }

  Future<int> getCachedNotesCount() async {
    try {
      final db = await isar;
      return await db.eventModels
          .filter()
          .kindEqualTo(1)
          .or()
          .kindEqualTo(6)
          .count();
    } catch (e) {
      return 0;
    }
  }

  Future<List<EventModel>> searchNotes(String query, {int limit = 50}) async {
    if (query.isEmpty) return [];

    try {
      final db = await isar;
      final lowerQuery = query.toLowerCase();

      // Search in kind=1 (text notes) content
      final results = await db.eventModels
          .filter()
          .kindEqualTo(1)
          .contentContains(lowerQuery, caseSensitive: false)
          .sortByCreatedAtDesc()
          .limit(limit)
          .findAll();

      return results;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error searching notes: $e');
      return [];
    }
  }

  Future<void> saveEvents(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    try {
      final db = await isar;

      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final event in events) {
        final id = event['id'] as String?;
        if (id != null && id.isNotEmpty && seen.add(id)) {
          unique.add(event);
        }
      }
      if (unique.isEmpty) return;

      await db.writeTxn(() async {
        for (final event in unique) {
          final id = event['id'] as String;
          final existing =
              await db.eventModels.where().eventIdEqualTo(id).findFirst();
          if (existing == null) {
            await db.eventModels.put(EventModel.fromEventData(event));
          }
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving events: $e');
    }
  }

  Future<Map<String, dynamic>?> getEvent(String eventId) async {
    try {
      final db = await isar;
      final event =
          await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
      return event?.toEventData();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting event: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getEventsByKind(int kind,
      {int limit = 100}) async {
    try {
      final db = await isar;
      final events = await db.eventModels
          .filter()
          .kindEqualTo(kind)
          .sortByCreatedAtDesc()
          .limit(limit)
          .findAll();
      return events.map((e) => e.toEventData()).toList();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting events by kind: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getEventsByPubkey(String pubkey,
      {List<int>? kinds, int limit = 100}) async {
    try {
      final db = await isar;
      var query = db.eventModels.filter().pubkeyEqualTo(pubkey);

      if (kinds != null && kinds.isNotEmpty) {
        query = query.group((q) {
          var kindQuery = q.kindEqualTo(kinds.first);
          for (int i = 1; i < kinds.length; i++) {
            kindQuery = kindQuery.or().kindEqualTo(kinds[i]);
          }
          return kindQuery;
        });
      }

      final events = await query.sortByCreatedAtDesc().limit(limit).findAll();
      return events.map((e) => e.toEventData()).toList();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting events by pubkey: $e');
      return [];
    }
  }

  Future<List<EventModel>> getCachedNotifications(String userPubkey,
      {int limit = 100}) async {
    try {
      final db = await isar;

      final events = await db.eventModels
          .filter()
          .group((q) => q
              .kindEqualTo(1)
              .or()
              .kindEqualTo(6)
              .or()
              .kindEqualTo(7)
              .or()
              .kindEqualTo(9735))
          .tagsElementContains(userPubkey)
          .not()
          .pubkeyEqualTo(userPubkey)
          .sortByCreatedAtDesc()
          .limit(limit)
          .findAll();

      return events;
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error getting cached notifications: $e');
      return [];
    }
  }

  Future<void> saveNotifications(
      String userPubkey, List<Map<String, dynamic>> notifications) async {
    if (notifications.isEmpty) return;

    try {
      final db = await isar;

      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final notification in notifications) {
        final eventId = notification['id'] as String?;
        if (eventId != null && eventId.isNotEmpty && seen.add(eventId)) {
          unique.add(notification);
        }
      }
      if (unique.isEmpty) return;

      await db.writeTxn(() async {
        for (final notification in unique) {
          final eventId = notification['id'] as String;
          final existing =
              await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
          if (existing == null) {
            await db.eventModels.put(EventModel.fromEventData(notification));
          }
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving notifications: $e');
    }
  }

  Future<Map<String, dynamic>?> getCachedArticle(String articleId) async {
    try {
      final db = await isar;

      final event = await db.eventModels
          .where()
          .eventIdEqualTo(articleId)
          .filter()
          .kindEqualTo(30023)
          .findFirst();

      if (event == null) return null;

      final eventData = event.toEventData();
      return _processArticleFromCache(eventData);
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting cached article: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getCachedArticles({int limit = 50}) async {
    try {
      final db = await isar;

      final events = await db.eventModels
          .filter()
          .kindEqualTo(30023)
          .sortByCreatedAtDesc()
          .limit(limit)
          .findAll();

      final articles = <Map<String, dynamic>>[];

      for (final event in events) {
        final eventData = event.toEventData();
        articles.add(_processArticleFromCache(eventData));
      }

      return articles;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting cached articles: $e');
      return [];
    }
  }

  Map<String, dynamic> _processArticleFromCache(Map<String, dynamic> event) {
    final tags = event['tags'] as List<dynamic>? ?? [];

    String? title;
    String? image;
    String? summary;
    String? dTag;
    int? publishedAt;
    List<String> tTags = [];

    for (final tag in tags) {
      if (tag is! List || tag.isEmpty) continue;
      final tagName = tag[0].toString();
      final tagValue = tag.length > 1 ? tag[1].toString() : '';

      switch (tagName) {
        case 'd':
          dTag = tagValue;
          break;
        case 'title':
          title = tagValue;
          break;
        case 'image':
          image = tagValue;
          break;
        case 'summary':
          summary = tagValue;
          break;
        case 'published_at':
          publishedAt = int.tryParse(tagValue);
          break;
        case 't':
          if (tagValue.isNotEmpty) tTags.add(tagValue);
          break;
      }
    }

    return {
      ...event,
      'title': title ?? '',
      'image': image ?? '',
      'summary': summary ?? '',
      'dTag': dTag ?? '',
      'publishedAt': publishedAt ?? event['created_at'],
      'tTags': tTags,
    };
  }

  Future<void> saveArticles(List<Map<String, dynamic>> articles) async {
    if (articles.isEmpty) return;

    try {
      final db = await isar;

      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final article in articles) {
        final eventId = article['id'] as String?;
        if (eventId != null && eventId.isNotEmpty && seen.add(eventId)) {
          unique.add(article);
        }
      }
      if (unique.isEmpty) return;

      await db.writeTxn(() async {
        for (final article in unique) {
          final eventId = article['id'] as String;
          final existing =
              await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
          if (existing == null) {
            await db.eventModels.put(EventModel.fromEventData(article));
          }
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving articles: $e');
    }
  }

  Future<Map<String, Map<String, int>>> getCachedInteractionCounts(
      List<String> noteIds) async {
    if (noteIds.isEmpty) return {};

    try {
      final db = await isar;
      final counts = <String, Map<String, int>>{};

      for (final noteId in noteIds) {
        counts[noteId] = {
          'reactions': 0,
          'reposts': 0,
          'replies': 0,
          'zaps': 0
        };
      }

      final interactionEvents = await db.eventModels
          .filter()
          .group((q) => q
              .kindEqualTo(6)
              .or()
              .kindEqualTo(7)
              .or()
              .kindEqualTo(9735)
              .or()
              .kindEqualTo(1))
          .anyOf(noteIds, (q, noteId) => q.tagsElementContains(noteId))
          .findAll();

      for (final event in interactionEvents) {
        final tags = event.getTags();
        String? targetNoteId;

        for (final tag in tags) {
          if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
            if (noteIds.contains(tag[1])) {
              targetNoteId = tag[1];
              break;
            }
          }
        }

        if (targetNoteId == null) continue;

        final noteCount = counts[targetNoteId]!;
        switch (event.kind) {
          case 7:
            noteCount['reactions'] = (noteCount['reactions'] ?? 0) + 1;
            break;
          case 6:
            noteCount['reposts'] = (noteCount['reposts'] ?? 0) + 1;
            break;
          case 9735:
            noteCount['zaps'] =
                (noteCount['zaps'] ?? 0) + _extractZapAmountFromEvent(event);
            break;
          case 1:
            bool isReply = false;
            for (final tag in tags) {
              if (tag.isNotEmpty && tag[0] == 'e' && tag.length >= 4) {
                if (tag[3] == 'root' || tag[3] == 'reply') {
                  isReply = true;
                  break;
                }
              }
            }
            if (isReply) {
              noteCount['replies'] = (noteCount['replies'] ?? 0) + 1;
            }
            break;
        }
      }

      return counts;
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error getting cached interaction counts: $e');
      return {};
    }
  }

  Future<int> getTotalEventCount() async {
    try {
      final db = await isar;
      return await db.eventModels.count();
    } catch (e) {
      return 0;
    }
  }

  Future<Map<int, int>> getEventCountsByKind() async {
    try {
      final db = await isar;
      final counts = <int, int>{};

      for (final kind in [0, 1, 3, 6, 7, 9735, 10000]) {
        counts[kind] = await db.eventModels.filter().kindEqualTo(kind).count();
      }

      return counts;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting event counts: $e');
      return {};
    }
  }

  Future<EventModel?> getLatestByPubkeyAndKind(String pubkey, int kind) async {
    try {
      final db = await isar;
      return await db.eventModels
          .filter()
          .pubkeyEqualTo(pubkey)
          .kindEqualTo(kind)
          .sortByCreatedAtDesc()
          .findFirst();
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error getting latest by pubkey and kind: $e');
      return null;
    }
  }

  Future<EventModel?> getLatestByPubkeyKindAndDTag(
      String pubkey, int kind, String dTag) async {
    try {
      final db = await isar;
      return await db.eventModels
          .filter()
          .pubkeyEqualTo(pubkey)
          .kindEqualTo(kind)
          .dTagEqualTo(dTag)
          .sortByCreatedAtDesc()
          .findFirst();
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error getting latest by pubkey, kind and dTag: $e');
      return null;
    }
  }

  Future<bool> eventExists(String eventId) async {
    try {
      final db = await isar;
      return await db.eventModels.where().eventIdEqualTo(eventId).isNotEmpty();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking event exists: $e');
      return false;
    }
  }

  Future<void> deleteEventById(int id) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.eventModels.delete(id);
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error deleting event by id: $e');
    }
  }

  Future<void> updateSyncStatus(String eventId, SyncStatus status) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        final event =
            await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
        if (event != null) {
          event.syncStatus = status;
          event.lastSyncedAt = DateTime.now();
          await db.eventModels.put(event);
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error updating sync status: $e');
    }
  }

  Stream<List<EventModel>> watchFeedNotes(List<String> authors,
      {int limit = 100}) async* {
    if (authors.isEmpty) {
      yield [];
      return;
    }

    final db = await isar;
    final targetCount = limit * 3;

    yield* db.eventModels
        .filter()
        .anyOf(authors, (q, pubkey) => q.pubkeyEqualTo(pubkey))
        .group((q) => q.kindEqualTo(1).or().kindEqualTo(6))
        .sortByCreatedAtDesc()
        .limit(targetCount)
        .watch(fireImmediately: true)
        .map((events) {
      final filtered = <EventModel>[];
      for (final event in events) {
        if (event.kind == 6) {
          filtered.add(event);
        } else if (event.kind == 1 && !_isReplyNote(event)) {
          filtered.add(event);
        }
        if (filtered.length >= limit) break;
      }
      return filtered;
    });
  }

  Stream<List<EventModel>> watchHashtagNotes(String hashtag,
      {int limit = 100}) async* {
    final normalizedHashtag = hashtag.toLowerCase();
    final db = await isar;

    yield* db.eventModels
        .filter()
        .kindEqualTo(1)
        .tagsElementContains(normalizedHashtag)
        .sortByCreatedAtDesc()
        .limit(limit)
        .watch(fireImmediately: true)
        .map((events) {
      final sorted = List<EventModel>.from(events);
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted.take(limit).toList();
    });
  }

  Stream<EventModel?> watchProfile(String pubkey) async* {
    final db = await isar;
    yield* db.eventModels
        .filter()
        .pubkeyEqualTo(pubkey)
        .kindEqualTo(0)
        .sortByCreatedAtDesc()
        .limit(1)
        .watch(fireImmediately: true)
        .map((events) => events.isNotEmpty ? events.first : null);
  }

  Stream<List<EventModel>> watchNotifications(String userPubkey,
      {int limit = 100}) async* {
    final db = await isar;
    yield* db.eventModels
        .filter()
        .group((q) => q
            .kindEqualTo(1)
            .or()
            .kindEqualTo(6)
            .or()
            .kindEqualTo(7)
            .or()
            .kindEqualTo(9735))
        .tagsElementContains(userPubkey)
        .not()
        .pubkeyEqualTo(userPubkey)
        .sortByCreatedAtDesc()
        .limit(limit)
        .watch(fireImmediately: true)
        .map((events) {
      final sorted = List<EventModel>.from(events);
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted.take(limit).toList();
    });
  }

  Stream<List<EventModel>> watchArticles({int limit = 50}) async* {
    final db = await isar;
    yield* db.eventModels
        .filter()
        .kindEqualTo(30023)
        .sortByCreatedAtDesc()
        .limit(limit * 2)
        .watch(fireImmediately: true)
        .map((events) {
      // Sort by createdAt descending to ensure newest first
      // (Isar watch may not preserve sort order on updates)
      final sorted = List<EventModel>.from(events);
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted.take(limit).toList();
    });
  }

  Future<void> saveEvent(EventModel event) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        final exists = await db.eventModels
            .where()
            .eventIdEqualTo(event.eventId)
            .isNotEmpty();
        if (exists) return;
        await db.eventModels.put(event);
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving event: $e');
    }
  }

  Future<void> saveEventsBatch(List<EventModel> events) async {
    if (events.isEmpty) return;
    try {
      final db = await isar;

      final seen = <String>{};
      final unique = <EventModel>[];
      for (final event in events) {
        if (seen.add(event.eventId)) {
          unique.add(event);
        }
      }

      await db.writeTxn(() async {
        for (final event in unique) {
          final existing = await db.eventModels
              .where()
              .eventIdEqualTo(event.eventId)
              .findFirst();
          if (existing == null) {
            await db.eventModels.put(event);
          }
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving events batch: $e');
    }
  }

  Future<void> saveEventWithReplacement(
      EventModel event, int? existingId) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        if (existingId != null) {
          await db.eventModels.delete(existingId);
        }
        final existsByEventId = await db.eventModels
            .where()
            .eventIdEqualTo(event.eventId)
            .findFirst();
        if (existsByEventId == null) {
          await db.eventModels.put(event);
        }
      });
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error saving event with replacement: $e');
    }
  }

  Stream<List<EventModel>> watchProfileNotes(String pubkey,
      {int limit = 50}) async* {
    final db = await isar;
    yield* db.eventModels
        .filter()
        .pubkeyEqualTo(pubkey)
        .group((q) => q.kindEqualTo(1).or().kindEqualTo(6))
        .sortByCreatedAtDesc()
        .limit(limit * 3)
        .watch(fireImmediately: true)
        .map((events) {
      final notes = <EventModel>[];
      for (final event in events) {
        if (event.kind == 6) {
          notes.add(event);
        } else if (event.kind == 1 && !_isReplyNote(event)) {
          notes.add(event);
        }
        if (notes.length >= limit) break;
      }
      notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notes.take(limit).toList();
    });
  }

  Stream<List<EventModel>> watchReplies(String noteId,
      {int limit = 100}) async* {
    final db = await isar;
    yield* db.eventModels
        .filter()
        .kindEqualTo(1)
        .tagsElementContains(noteId)
        .sortByCreatedAtDesc()
        .limit(limit * 2)
        .watch(fireImmediately: true)
        .map((events) {
      final replies = <EventModel>[];
      for (final event in events) {
        final tags = event.getTags();
        for (final tag in tags) {
          if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
            if (tag[1] == noteId) {
              replies.add(event);
              break;
            }
          }
        }
      }
      // Sort by createdAt descending to ensure newest first
      // (Isar watch may not preserve sort order on updates)
      replies.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return replies.take(limit).toList();
    });
  }

  Future<List<EventModel>> getReplies(String noteId, {int limit = 500}) async {
    try {
      final db = await isar;
      final allReplies = <EventModel>[];
      final processedIds = <String>{noteId};
      var targetIds = <String>{noteId};
      const maxDepth = 5;
      var depth = 0;

      while (targetIds.isNotEmpty &&
          depth < maxDepth &&
          allReplies.length < limit) {
        final newTargetIds = <String>{};

        for (final targetId in targetIds) {
          final events = await db.eventModels
              .filter()
              .kindEqualTo(1)
              .tagsElementContains(targetId)
              .sortByCreatedAtDesc()
              .limit(100)
              .findAll();

          for (final event in events) {
            if (processedIds.contains(event.eventId)) continue;

            final tags = event.getTags();
            bool referencesTarget = false;
            for (final tag in tags) {
              if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
                if (tag[1] == targetId) {
                  referencesTarget = true;
                  break;
                }
              }
            }

            if (referencesTarget) {
              processedIds.add(event.eventId);
              allReplies.add(event);
              newTargetIds.add(event.eventId);
            }
          }
        }

        targetIds = newTargetIds;
        depth++;
      }

      allReplies.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return allReplies.take(limit).toList();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting replies: $e');
      return [];
    }
  }

  Future<EventModel?> getEventModel(String eventId) async {
    try {
      final db = await isar;
      return await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting event model: $e');
      return null;
    }
  }

  Future<List<EventModel>> getEventModels(List<String> eventIds) async {
    if (eventIds.isEmpty) return [];
    try {
      final db = await isar;
      return await db.eventModels
          .filter()
          .anyOf(eventIds, (q, id) => q.eventIdEqualTo(id))
          .findAll();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting event models: $e');
      return [];
    }
  }

  Future<List<EventModel>> getEventsByAuthors(List<String> authors,
      {List<int>? kinds, int limit = 100}) async {
    if (authors.isEmpty) return [];
    try {
      final db = await isar;

      var query = db.eventModels
          .filter()
          .anyOf(authors, (q, pubkey) => q.pubkeyEqualTo(pubkey));

      if (kinds != null && kinds.isNotEmpty) {
        query = query.group((q) {
          var kindQuery = q.kindEqualTo(kinds.first);
          for (int i = 1; i < kinds.length; i++) {
            kindQuery = kindQuery.or().kindEqualTo(kinds[i]);
          }
          return kindQuery;
        });
      }

      return await query.sortByCreatedAtDesc().limit(limit).findAll();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting events by authors: $e');
      return [];
    }
  }

  Future<Map<String, int>> getInteractionCounts(String noteId) async {
    try {
      final db = await isar;

      final reactions = await db.eventModels
          .filter()
          .kindEqualTo(7)
          .tagsElementContains(noteId)
          .count();

      final reposts = await db.eventModels
          .filter()
          .kindEqualTo(6)
          .tagsElementContains(noteId)
          .count();

      final replies = await db.eventModels
          .filter()
          .kindEqualTo(1)
          .tagsElementContains(noteId)
          .tagsElementContains('"root"')
          .or()
          .kindEqualTo(1)
          .tagsElementContains(noteId)
          .tagsElementContains('"reply"')
          .count();

      final zapEvents = await db.eventModels
          .filter()
          .kindEqualTo(9735)
          .tagsElementContains(noteId)
          .findAll();

      int totalZapAmount = 0;
      for (final zapEvent in zapEvents) {
        totalZapAmount += _extractZapAmountFromEvent(zapEvent);
      }

      return {
        'reactions': reactions,
        'reposts': reposts,
        'replies': replies,
        'zaps': totalZapAmount,
      };
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting interaction counts: $e');
      return {'reactions': 0, 'reposts': 0, 'replies': 0, 'zaps': 0};
    }
  }

  Future<List<Map<String, dynamic>>> getDetailedInteractions(
      String noteId) async {
    try {
      final db = await isar;
      final interactions = <Map<String, dynamic>>[];

      final events = await db.eventModels
          .filter()
          .group((q) =>
              q.kindEqualTo(6).or().kindEqualTo(7).or().kindEqualTo(9735))
          .tagsElementContains(noteId)
          .sortByCreatedAtDesc()
          .findAll();

      for (final event in events) {
        String type;
        int? zapAmount;
        String content = event.content;
        String pubkeyToUse = event.pubkey;

        switch (event.kind) {
          case 7:
            type = 'reaction';
            if (content.isEmpty) content = '+';
            break;
          case 6:
            type = 'repost';
            content = '';
            break;
          case 9735:
            type = 'zap';
            zapAmount = _extractZapAmountFromEvent(event);
            pubkeyToUse = _extractZapSenderPubkey(event) ?? event.pubkey;
            content = '';
            break;
          default:
            continue;
        }

        interactions.add({
          'type': type,
          'pubkey': pubkeyToUse,
          'content': content,
          'zapAmount': zapAmount,
          'createdAt': event.createdAt,
        });
      }

      return interactions;
    } catch (e) {
      debugPrint(
          '[IsarDatabaseService] Error getting detailed interactions: $e');
      return [];
    }
  }

  int _extractZapAmountFromEvent(EventModel event) {
    try {
      final tags = event.getTags();
      for (final tag in tags) {
        if (tag.isNotEmpty && tag[0] == 'bolt11' && tag.length > 1) {
          return _parseAmountFromBolt11(tag[1]);
        }
      }
    } catch (_) {}
    return 0;
  }

  int _parseAmountFromBolt11(String bolt11) {
    try {
      final lowerBolt11 = bolt11.toLowerCase();
      if (!lowerBolt11.startsWith('lnbc')) return 0;

      final amountPart = lowerBolt11.substring(4);
      final match = RegExp(r'^(\d+)([munp]?)').firstMatch(amountPart);
      if (match == null) return 0;

      final amount = int.tryParse(match.group(1) ?? '0') ?? 0;
      final multiplier = match.group(2) ?? '';

      switch (multiplier) {
        case 'm':
          return amount * 100000;
        case 'u':
          return amount * 100;
        case 'n':
          return (amount * 100) ~/ 1000;
        case 'p':
          return (amount * 100) ~/ 1000000;
        default:
          return amount * 100000000;
      }
    } catch (_) {
      return 0;
    }
  }

  String? _extractZapSenderPubkey(EventModel event) {
    try {
      final tags = event.getTags();
      for (final tag in tags) {
        if (tag.isNotEmpty && tag[0] == 'P' && tag.length > 1) {
          return tag[1];
        }
      }
      for (final tag in tags) {
        if (tag.isNotEmpty && tag[0] == 'description' && tag.length > 1) {
          final descJson = jsonDecode(tag[1]) as Map<String, dynamic>;
          if (descJson.containsKey('pubkey')) {
            return descJson['pubkey'] as String?;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> hasUserReacted(String noteId, String userPubkey) async {
    try {
      final db = await isar;
      final count = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkey)
          .kindEqualTo(7)
          .tagsElementContains(noteId)
          .count();
      return count > 0;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking user reaction: $e');
      return false;
    }
  }

  Future<bool> hasUserReposted(String noteId, String userPubkey) async {
    try {
      final db = await isar;
      final count = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkey)
          .kindEqualTo(6)
          .tagsElementContains(noteId)
          .count();
      return count > 0;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking user repost: $e');
      return false;
    }
  }

  Future<Map<String, bool>> batchHasUserReacted(
      List<String> noteIds, String userPubkey) async {
    if (noteIds.isEmpty) return {};
    try {
      final db = await isar;
      final result = <String, bool>{};

      for (final noteId in noteIds) {
        result[noteId] = false;
      }

      final reactions = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkey)
          .kindEqualTo(7)
          .anyOf(noteIds, (q, noteId) => q.tagsElementContains(noteId))
          .findAll();

      for (final reaction in reactions) {
        final eTag = reaction.getTagValue('e');
        if (eTag != null && result.containsKey(eTag)) {
          result[eTag] = true;
        }
      }

      return result;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch checking reactions: $e');
      return {};
    }
  }

  Future<Map<String, bool>> batchHasUserReposted(
      List<String> noteIds, String userPubkey) async {
    if (noteIds.isEmpty) return {};
    try {
      final db = await isar;
      final result = <String, bool>{};

      for (final noteId in noteIds) {
        result[noteId] = false;
      }

      final reposts = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkey)
          .kindEqualTo(6)
          .anyOf(noteIds, (q, noteId) => q.tagsElementContains(noteId))
          .findAll();

      for (final repost in reposts) {
        final eTag = repost.getTagValue('e');
        if (eTag != null && result.containsKey(eTag)) {
          result[eTag] = true;
        }
      }

      return result;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch checking reposts: $e');
      return {};
    }
  }

  Future<String?> findUserRepostEventId(
      String userPubkey, String noteId) async {
    try {
      final db = await isar;
      final repost = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkey)
          .kindEqualTo(6)
          .tagsElementContains(noteId)
          .findFirst();
      return repost?.eventId;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error finding user repost event: $e');
      return null;
    }
  }
}
