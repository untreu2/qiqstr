import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/event_model.dart';

class IsarDatabaseService {
  static IsarDatabaseService? _instance;
  static IsarDatabaseService get instance =>
      _instance ??= IsarDatabaseService._internal();

  IsarDatabaseService._internal();

  Isar? _isar;
  bool _isInitialized = false;
  bool _isInitializing = false;
  Completer<void> _initCompleter = Completer<void>();

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
      final kind3Events = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkeyHex)
          .kindEqualTo(3)
          .sortByCreatedAtDesc()
          .findFirst();

      if (kind3Events == null) {
        return null;
      }

      final tags = kind3Events.getTags();
      final followingList = <String>[];

      for (final tag in tags) {
        if (tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
          final pubkey = tag[1];
          if (pubkey.isNotEmpty) {
            followingList.add(pubkey);
          }
        }
      }

      return followingList.isEmpty ? null : followingList;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting following list: $e');
      return null;
    }
  }

  Future<void> saveFollowingList(
      String userPubkeyHex, List<String> followingList) async {
    try {
      final db = await isar;

      final tags = followingList.map((pubkey) => ['p', pubkey]).toList();
      final tagsSerialized = tags.map((tag) => jsonEncode(tag)).toList();

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eventId = 'following_list_$userPubkeyHex';

      final eventData = {
        'id': eventId,
        'pubkey': userPubkeyHex,
        'kind': 3,
        'created_at': now,
        'content': '',
        'tags': tags,
        'sig': '',
      };

      await db.writeTxn(() async {
        final existing =
            await db.eventModels.where().eventIdEqualTo(eventId).findFirst();

        final eventModel = existing ?? EventModel();
        eventModel.eventId = eventId;
        eventModel.pubkey = userPubkeyHex;
        eventModel.kind = 3;
        eventModel.createdAt = now;
        eventModel.content = '';
        eventModel.tags = tagsSerialized;
        eventModel.sig = '';
        eventModel.rawEvent = jsonEncode(eventData);
        eventModel.cachedAt = DateTime.now();

        await db.eventModels.put(eventModel);
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving following list: $e');
    }
  }

  Future<Map<String, List<String>>> getFollowingLists(
      List<String> userPubkeyHexList) async {
    final result = <String, List<String>>{};

    try {
      final db = await isar;

      for (final userPubkeyHex in userPubkeyHexList) {
        final kind3Event = await db.eventModels
            .filter()
            .pubkeyEqualTo(userPubkeyHex)
            .kindEqualTo(3)
            .sortByCreatedAtDesc()
            .findFirst();

        if (kind3Event != null) {
          final tags = kind3Event.getTags();
          final followingList = <String>[];

          for (final tag in tags) {
            if (tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
              final pubkey = tag[1];
              if (pubkey.isNotEmpty) {
                followingList.add(pubkey);
              }
            }
          }

          if (followingList.isNotEmpty) {
            result[userPubkeyHex] = followingList;
          }
        }
      }
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting following lists: $e');
    }

    return result;
  }

  Future<void> saveFollowingLists(
      Map<String, List<String>> followingLists) async {
    try {
      final db = await isar;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.writeTxn(() async {
        for (final entry in followingLists.entries) {
          final userPubkeyHex = entry.key;
          final followingList = entry.value;

          final tags = followingList.map((pubkey) => ['p', pubkey]).toList();
          final tagsSerialized = tags.map((tag) => jsonEncode(tag)).toList();

          final eventId = 'following_list_$userPubkeyHex';

          final eventData = {
            'id': eventId,
            'pubkey': userPubkeyHex,
            'kind': 3,
            'created_at': now,
            'content': '',
            'tags': tags,
            'sig': '',
          };

          final existing =
              await db.eventModels.where().eventIdEqualTo(eventId).findFirst();

          final eventModel = existing ?? EventModel();
          eventModel.eventId = eventId;
          eventModel.pubkey = userPubkeyHex;
          eventModel.kind = 3;
          eventModel.createdAt = now;
          eventModel.content = '';
          eventModel.tags = tagsSerialized;
          eventModel.sig = '';
          eventModel.rawEvent = jsonEncode(eventData);
          eventModel.cachedAt = DateTime.now();

          await db.eventModels.put(eventModel);
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving following lists: $e');
    }
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
      final muteEvent = await db.eventModels
          .filter()
          .pubkeyEqualTo(userPubkeyHex)
          .kindEqualTo(10000)
          .sortByCreatedAtDesc()
          .findFirst();

      if (muteEvent == null) {
        return null;
      }

      final tags = muteEvent.getTags();
      final muteList = <String>[];

      for (final tag in tags) {
        if (tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
          final pubkey = tag[1];
          if (pubkey.isNotEmpty) {
            muteList.add(pubkey);
          }
        }
      }

      return muteList.isEmpty ? null : muteList;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting mute list: $e');
      return null;
    }
  }

  Future<void> saveMuteList(String userPubkeyHex, List<String> muteList) async {
    try {
      final db = await isar;

      final tags = muteList.map((pubkey) => ['p', pubkey]).toList();
      final tagsSerialized = tags.map((tag) => jsonEncode(tag)).toList();

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eventId = 'mute_list_$userPubkeyHex';

      final eventData = {
        'id': eventId,
        'pubkey': userPubkeyHex,
        'kind': 10000,
        'created_at': now,
        'content': '',
        'tags': tags,
        'sig': '',
      };

      await db.writeTxn(() async {
        final existing =
            await db.eventModels.where().eventIdEqualTo(eventId).findFirst();

        final eventModel = existing ?? EventModel();
        eventModel.eventId = eventId;
        eventModel.pubkey = userPubkeyHex;
        eventModel.kind = 10000;
        eventModel.createdAt = now;
        eventModel.content = '';
        eventModel.tags = tagsSerialized;
        eventModel.sig = '';
        eventModel.rawEvent = jsonEncode(eventData);
        eventModel.cachedAt = DateTime.now();

        await db.eventModels.put(eventModel);
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving mute list: $e');
    }
  }

  Future<Map<String, List<String>>> getMuteLists(
      List<String> userPubkeyHexList) async {
    final result = <String, List<String>>{};

    try {
      final db = await isar;

      for (final userPubkeyHex in userPubkeyHexList) {
        final muteEvent = await db.eventModels
            .filter()
            .pubkeyEqualTo(userPubkeyHex)
            .kindEqualTo(10000)
            .sortByCreatedAtDesc()
            .findFirst();

        if (muteEvent != null) {
          final tags = muteEvent.getTags();
          final muteList = <String>[];

          for (final tag in tags) {
            if (tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
              final pubkey = tag[1];
              if (pubkey.isNotEmpty) {
                muteList.add(pubkey);
              }
            }
          }

          if (muteList.isNotEmpty) {
            result[userPubkeyHex] = muteList;
          }
        }
      }
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting mute lists: $e');
    }

    return result;
  }

  Future<void> saveMuteLists(Map<String, List<String>> muteLists) async {
    try {
      final db = await isar;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.writeTxn(() async {
        for (final entry in muteLists.entries) {
          final userPubkeyHex = entry.key;
          final muteList = entry.value;

          final tags = muteList.map((pubkey) => ['p', pubkey]).toList();
          final tagsSerialized = tags.map((tag) => jsonEncode(tag)).toList();

          final eventId = 'mute_list_$userPubkeyHex';

          final eventData = {
            'id': eventId,
            'pubkey': userPubkeyHex,
            'kind': 10000,
            'created_at': now,
            'content': '',
            'tags': tags,
            'sig': '',
          };

          final existing =
              await db.eventModels.where().eventIdEqualTo(eventId).findFirst();

          final eventModel = existing ?? EventModel();
          eventModel.eventId = eventId;
          eventModel.pubkey = userPubkeyHex;
          eventModel.kind = 10000;
          eventModel.createdAt = now;
          eventModel.content = '';
          eventModel.tags = tagsSerialized;
          eventModel.sig = '';
          eventModel.rawEvent = jsonEncode(eventData);
          eventModel.cachedAt = DateTime.now();

          await db.eventModels.put(eventModel);
        }
      });
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving mute lists: $e');
    }
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
      final profileEvent = await db.eventModels
          .filter()
          .pubkeyEqualTo(pubkeyHex)
          .kindEqualTo(0)
          .sortByCreatedAtDesc()
          .findFirst();

      if (profileEvent == null) {
        return null;
      }

      final content = profileEvent.content;
      if (content.isEmpty) {
        return null;
      }

      try {
        final parsedContent = jsonDecode(content) as Map<String, dynamic>;
        final profileData = <String, String>{};

        parsedContent.forEach((key, value) {
          final keyStr = key.toString();
          if (keyStr == 'picture') {
            profileData['profileImage'] = value?.toString() ?? '';
          } else {
            profileData[keyStr] = value?.toString() ?? '';
          }
        });

        return profileData;
      } catch (e) {
        debugPrint('[IsarDatabaseService] Error parsing profile content: $e');
        return null;
      }
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

      final contentMap = <String, dynamic>{};
      profileData.forEach((key, value) {
        if (key == 'profileImage') {
          contentMap['picture'] = value;
        } else {
          contentMap[key] = value;
        }
      });

      final eventData = {
        'id': eventId,
        'pubkey': pubkeyHex,
        'kind': 0,
        'created_at': now,
        'content': jsonEncode(contentMap),
        'tags': [],
        'sig': '',
      };

      await db.writeTxn(() async {
        final existing =
            await db.eventModels.where().eventIdEqualTo(eventId).findFirst();

        final eventModel = existing ?? EventModel();
        eventModel.eventId = eventId;
        eventModel.pubkey = pubkeyHex;
        eventModel.kind = 0;
        eventModel.createdAt = now;
        eventModel.content = jsonEncode(contentMap);
        eventModel.tags = [];
        eventModel.sig = '';
        eventModel.rawEvent = jsonEncode(eventData);
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

    try {
      final db = await isar;

      for (final pubkeyHex in pubkeyHexList) {
        final profileEvent = await db.eventModels
            .filter()
            .pubkeyEqualTo(pubkeyHex)
            .kindEqualTo(0)
            .sortByCreatedAtDesc()
            .findFirst();

        if (profileEvent != null) {
          final content = profileEvent.content;
          if (content.isNotEmpty) {
            try {
              final parsedContent = jsonDecode(content) as Map<String, dynamic>;
              final profileData = <String, String>{};

              parsedContent.forEach((key, value) {
                final keyStr = key.toString();
                if (keyStr == 'picture') {
                  profileData['profileImage'] = value?.toString() ?? '';
                } else {
                  profileData[keyStr] = value?.toString() ?? '';
                }
              });

              if (profileData.isNotEmpty) {
                result[pubkeyHex] = profileData;
              }
            } catch (e) {
              debugPrint(
                  '[IsarDatabaseService] Error parsing profile content for $pubkeyHex: $e');
            }
          }
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
          final pubkeyHex = entry.key;
          final profileData = entry.value;

          final eventId = 'profile_$pubkeyHex';

          final contentMap = <String, dynamic>{};
          profileData.forEach((key, value) {
            if (key == 'profileImage') {
              contentMap['picture'] = value;
            } else {
              contentMap[key] = value;
            }
          });

          final eventData = {
            'id': eventId,
            'pubkey': pubkeyHex,
            'kind': 0,
            'created_at': now,
            'content': jsonEncode(contentMap),
            'tags': [],
            'sig': '',
          };

          final existing =
              await db.eventModels.where().eventIdEqualTo(eventId).findFirst();

          final eventModel = existing ?? EventModel();
          eventModel.eventId = eventId;
          eventModel.pubkey = pubkeyHex;
          eventModel.kind = 0;
          eventModel.createdAt = now;
          eventModel.content = jsonEncode(contentMap);
          eventModel.tags = [];
          eventModel.sig = '';
          eventModel.rawEvent = jsonEncode(eventData);
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
    try {
      final db = await isar;
      final queryLower = query.toLowerCase();
      final allProfiles =
          await db.eventModels.filter().kindEqualTo(0).findAll();

      final matchingProfiles = <Map<String, String>>[];

      for (final profileEvent in allProfiles) {
        if (matchingProfiles.length >= limit) break;

        final content = profileEvent.content;
        if (content.isEmpty) continue;

        try {
          final parsedContent = jsonDecode(content) as Map<String, dynamic>;
          final name = (parsedContent['name'] as String? ?? '').toLowerCase();

          if (name.contains(queryLower)) {
            final profileData = <String, String>{};
            parsedContent.forEach((key, value) {
              final keyStr = key.toString();
              if (keyStr == 'picture') {
                profileData['profileImage'] = value?.toString() ?? '';
              } else {
                profileData[keyStr] = value?.toString() ?? '';
              }
            });
            profileData['pubkeyHex'] = profileEvent.pubkey;
            matchingProfiles.add(profileData);
          }
        } catch (e) {
          continue;
        }
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
      final allProfiles =
          await db.eventModels.filter().kindEqualTo(0).findAll();

      final profilesWithImages = <Map<String, String>>[];

      for (final profileEvent in allProfiles) {
        if (profilesWithImages.length >= limit) break;

        final content = profileEvent.content;
        if (content.isEmpty) continue;

        try {
          final parsedContent = jsonDecode(content) as Map<String, dynamic>;
          final picture = parsedContent['picture'] as String?;

          if (picture != null && picture.isNotEmpty) {
            final profileData = <String, String>{};
            parsedContent.forEach((key, value) {
              final keyStr = key.toString();
              if (keyStr == 'picture') {
                profileData['profileImage'] = value?.toString() ?? '';
              } else {
                profileData[keyStr] = value?.toString() ?? '';
              }
            });
            profileData['pubkeyHex'] = profileEvent.pubkey;
            profilesWithImages.add(profileData);
          }
        } catch (e) {
          continue;
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
}
