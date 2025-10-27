import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/user_model_isar.dart';
import '../../models/following_model_isar.dart';

class IsarDatabaseService {
  static IsarDatabaseService? _instance;
  static IsarDatabaseService get instance => _instance ??= IsarDatabaseService._internal();

  IsarDatabaseService._internal();

  Isar? _isar;
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();

  Future<Isar> get isar async {
    if (!_isInitialized) {
      await initialize();
    }
    return _isar!;
  }

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initCompleter.isCompleted) return;

    try {
      debugPrint('[IsarDatabaseService] Initializing Isar database...');

      final dir = await getApplicationDocumentsDirectory();

      _isar = await Isar.open(
        [UserModelIsarSchema, FollowingModelIsarSchema],
        directory: dir.path,
        name: 'qiqstr_db',
        inspector: kDebugMode,
      );

      _isInitialized = true;
      _initCompleter.complete();

      debugPrint('[IsarDatabaseService]  Isar database initialized successfully');
      debugPrint('[IsarDatabaseService] Database path: ${dir.path}');
      debugPrint('[IsarDatabaseService] User profiles in cache: ${await getUserProfileCount()}');
    } catch (e) {
      debugPrint('[IsarDatabaseService]  Error initializing Isar: $e');
      _initCompleter.completeError(e);
      rethrow;
    }
  }

  Future<void> waitForInitialization() async {
    await _initCompleter.future;
  }

  Future<void> saveUserProfile(String pubkeyHex, Map<String, String> profileData) async {
    try {
      final db = await isar;
      final userModel = UserModelIsar.fromUserModel(pubkeyHex, profileData);

      await db.writeTxn(() async {
        await db.userModelIsars.put(userModel);
      });

      debugPrint('[IsarDatabaseService]  Saved profile: ${profileData['name']} ($pubkeyHex)');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving user profile: $e');
    }
  }

  Future<void> saveUserProfiles(Map<String, Map<String, String>> profiles) async {
    try {
      final db = await isar;
      final userModels = profiles.entries.map((entry) {
        return UserModelIsar.fromUserModel(entry.key, entry.value);
      }).toList();

      await db.writeTxn(() async {
        await db.userModelIsars.putAll(userModels);
      });

      debugPrint('[IsarDatabaseService]  Batch saved ${userModels.length} profiles');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch saving profiles: $e');
    }
  }

  Future<Map<String, String>?> getUserProfile(String pubkeyHex) async {
    try {
      final db = await isar;
      final user = await db.userModelIsars.where().pubkeyHexEqualTo(pubkeyHex).findFirst();

      if (user != null) {
        debugPrint('[IsarDatabaseService]  Retrieved profile from Isar: ${user.name}');
        return user.toProfileData();
      }

      return null;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting user profile: $e');
      return null;
    }
  }

  Future<Map<String, Map<String, String>>> getUserProfiles(List<String> pubkeyHexList) async {
    try {
      final db = await isar;
      final results = <String, Map<String, String>>{};

      for (final pubkeyHex in pubkeyHexList) {
        final user = await db.userModelIsars.where().pubkeyHexEqualTo(pubkeyHex).findFirst();

        if (user != null) {
          results[pubkeyHex] = user.toProfileData();
        }
      }

      debugPrint('[IsarDatabaseService]  Batch retrieved ${results.length}/${pubkeyHexList.length} profiles from Isar');
      return results;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch getting profiles: $e');
      return {};
    }
  }

  Future<bool> hasUserProfile(String pubkeyHex) async {
    try {
      final db = await isar;
      final count = await db.userModelIsars.where().pubkeyHexEqualTo(pubkeyHex).count();
      return count > 0;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking profile existence: $e');
      return false;
    }
  }

  Future<void> deleteUserProfile(String pubkeyHex) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.userModelIsars.deleteByPubkeyHex(pubkeyHex);
      });
      debugPrint('[IsarDatabaseService] ️ Deleted profile: $pubkeyHex');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error deleting user profile: $e');
    }
  }

  Future<List<UserModelIsar>> getAllUserProfiles() async {
    try {
      final db = await isar;
      return await db.userModelIsars.where().findAll();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting all profiles: $e');
      return [];
    }
  }

  Future<List<UserModelIsar>> searchUsersByName(String query, {int limit = 50}) async {
    try {
      if (query.isEmpty) return [];

      final db = await isar;
      final lowerQuery = query.toLowerCase();

      final allProfiles = await db.userModelIsars.where().findAll();

      final matchingProfiles = allProfiles
          .where((profile) {
            final nameLower = profile.name.toLowerCase();
            final nip05Lower = profile.nip05.toLowerCase();

            return nameLower.contains(lowerQuery) || nip05Lower.contains(lowerQuery);
          })
          .take(limit)
          .toList();

      debugPrint('[IsarDatabaseService]  Found ${matchingProfiles.length} profiles matching "$query"');
      return matchingProfiles;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error searching profiles by name: $e');
      return [];
    }
  }

  Future<List<UserModelIsar>> getRandomUsersWithImages({int limit = 50}) async {
    try {
      final db = await isar;

      final allProfiles = await db.userModelIsars.where().findAll();
      final completeProfiles = allProfiles
          .where((profile) =>
              profile.profileImage.isNotEmpty &&
              profile.name != 'Anonymous' &&
              profile.name.isNotEmpty &&
              (profile.about.isNotEmpty || profile.nip05.isNotEmpty))
          .toList();

      if (completeProfiles.isEmpty) {
        debugPrint('[IsarDatabaseService] No complete profiles found');
        return [];
      }

      completeProfiles.shuffle();
      final randomProfiles = completeProfiles.take(limit).toList();

      debugPrint('[IsarDatabaseService]  Retrieved ${randomProfiles.length} random complete profiles');
      return randomProfiles;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting random profiles: $e');
      return [];
    }
  }

  Future<int> getUserProfileCount() async {
    try {
      final db = await isar;
      return await db.userModelIsars.count();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting profile count: $e');
      return 0;
    }
  }

  Future<int> cleanupExpiredProfiles({Duration ttl = const Duration(days: 7)}) async {
    try {
      final db = await isar;
      final cutoffDate = DateTime.now().subtract(ttl);

      final expiredProfiles = await db.userModelIsars.filter().cachedAtLessThan(cutoffDate).findAll();

      if (expiredProfiles.isEmpty) {
        return 0;
      }

      await db.writeTxn(() async {
        for (final profile in expiredProfiles) {
          await db.userModelIsars.delete(profile.id);
        }
      });

      debugPrint('[IsarDatabaseService]  Cleaned up ${expiredProfiles.length} expired profiles');
      return expiredProfiles.length;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error cleaning up expired profiles: $e');
      return 0;
    }
  }

  Future<void> clearAllUserProfiles() async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.userModelIsars.clear();
      });
      debugPrint('[IsarDatabaseService] ️ Cleared all user profiles');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error clearing profiles: $e');
    }
  }

  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final db = await isar;
      final totalProfiles = await db.userModelIsars.count();
      final dbSize = await db.getSize();

      return {
        'totalProfiles': totalProfiles,
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

  Stream<UserModelIsar?> watchUserProfile(String pubkeyHex) async* {
    final db = await isar;
    yield* db.userModelIsars
        .where()
        .pubkeyHexEqualTo(pubkeyHex)
        .watch(fireImmediately: true)
        .map((users) => users.isEmpty ? null : users.first);
  }

  Stream<List<UserModelIsar>> watchAllUserProfiles() async* {
    final db = await isar;
    yield* db.userModelIsars.where().watch(fireImmediately: true);
  }

  Future<void> close() async {
    if (_isar != null && _isar!.isOpen) {
      await _isar!.close();
      _isInitialized = false;
      debugPrint('[IsarDatabaseService] Database closed');
    }
  }

  Future<void> saveFollowingList(String userPubkeyHex, List<String> followingPubkeys) async {
    try {
      final db = await isar;
      final followingModel = FollowingModelIsar.fromFollowingModel(userPubkeyHex, followingPubkeys);

      await db.writeTxn(() async {
        await db.followingModelIsars.put(followingModel);
      });

      debugPrint('[IsarDatabaseService] Saved following list: ${followingPubkeys.length} following for $userPubkeyHex');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving following list: $e');
    }
  }

  Future<void> saveFollowingLists(Map<String, List<String>> followingLists) async {
    try {
      final db = await isar;
      final followingModels = followingLists.entries.map((entry) {
        return FollowingModelIsar.fromFollowingModel(entry.key, entry.value);
      }).toList();

      await db.writeTxn(() async {
        await db.followingModelIsars.putAll(followingModels);
      });

      debugPrint('[IsarDatabaseService] Batch saved ${followingModels.length} following lists');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch saving following lists: $e');
    }
  }

  Future<List<String>?> getFollowingList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final followingModel = await db.followingModelIsars.where().userPubkeyHexEqualTo(userPubkeyHex).findFirst();

      if (followingModel != null) {
        debugPrint('[IsarDatabaseService] Retrieved following list from Isar: ${followingModel.followingPubkeys.length} following');
        return followingModel.toFollowingList();
      }

      return null;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting following list: $e');
      return null;
    }
  }

  Future<Map<String, List<String>>> getFollowingLists(List<String> userPubkeyHexList) async {
    try {
      final db = await isar;
      final results = <String, List<String>>{};

      for (final userPubkeyHex in userPubkeyHexList) {
        final followingModel = await db.followingModelIsars.where().userPubkeyHexEqualTo(userPubkeyHex).findFirst();

        if (followingModel != null) {
          results[userPubkeyHex] = followingModel.toFollowingList();
        }
      }

      debugPrint('[IsarDatabaseService] Batch retrieved ${results.length}/${userPubkeyHexList.length} following lists from Isar');
      return results;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch getting following lists: $e');
      return {};
    }
  }

  Future<bool> hasFollowingList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final count = await db.followingModelIsars.where().userPubkeyHexEqualTo(userPubkeyHex).count();
      return count > 0;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking following list existence: $e');
      return false;
    }
  }

  Future<void> deleteFollowingList(String userPubkeyHex) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.followingModelIsars.deleteByUserPubkeyHex(userPubkeyHex);
      });
      debugPrint('[IsarDatabaseService] Deleted following list: $userPubkeyHex');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error deleting following list: $e');
    }
  }

  Future<List<FollowingModelIsar>> getAllFollowingLists() async {
    try {
      final db = await isar;
      return await db.followingModelIsars.where().findAll();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting all following lists: $e');
      return [];
    }
  }

  Future<int> getFollowingListCount() async {
    try {
      final db = await isar;
      return await db.followingModelIsars.count();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting following list count: $e');
      return 0;
    }
  }

  Future<int> cleanupExpiredFollowingLists({Duration ttl = const Duration(days: 3)}) async {
    try {
      final db = await isar;
      final cutoffDate = DateTime.now().subtract(ttl);

      final expiredFollowingLists = await db.followingModelIsars.filter().cachedAtLessThan(cutoffDate).findAll();

      if (expiredFollowingLists.isEmpty) {
        return 0;
      }

      await db.writeTxn(() async {
        for (final followingList in expiredFollowingLists) {
          await db.followingModelIsars.delete(followingList.id);
        }
      });

      debugPrint('[IsarDatabaseService] Cleaned up ${expiredFollowingLists.length} expired following lists');
      return expiredFollowingLists.length;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error cleaning up expired following lists: $e');
      return 0;
    }
  }

  Future<void> clearAllFollowingLists() async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.followingModelIsars.clear();
      });
      debugPrint('[IsarDatabaseService] Cleared all following lists');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error clearing following lists: $e');
    }
  }

  Stream<FollowingModelIsar?> watchFollowingList(String userPubkeyHex) async* {
    final db = await isar;
    yield* db.followingModelIsars
        .where()
        .userPubkeyHexEqualTo(userPubkeyHex)
        .watch(fireImmediately: true)
        .map((followingLists) => followingLists.isEmpty ? null : followingLists.first);
  }

  Stream<List<FollowingModelIsar>> watchAllFollowingLists() async* {
    final db = await isar;
    yield* db.followingModelIsars.where().watch(fireImmediately: true);
  }

  static void reset() {
    _instance?._isar?.close();
    _instance = null;
  }
}
