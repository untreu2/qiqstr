import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/user_model.dart';
import '../../models/following_model.dart';
import '../../models/mute_model.dart';

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
        [UserModelSchema, FollowingModelSchema, MuteModelSchema],
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
      
      // Get existing user to preserve followerCount if not updating it
      final existingUser = await db.userModels.where().pubkeyHexEqualTo(pubkeyHex).findFirst();
      
      final userModel = UserModel.fromUserModel(pubkeyHex, profileData);
      
      // Preserve followerCount if it exists and is not being updated
      if (existingUser != null && existingUser.followerCount != null && profileData['followerCount'] == null) {
        userModel.followerCount = existingUser.followerCount;
      }

      await db.writeTxn(() async {
        await db.userModels.put(userModel);
      });

      debugPrint('[IsarDatabaseService]  Saved profile: ${profileData['name']} ($pubkeyHex)');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving user profile: $e');
    }
  }

  Future<void> saveUserProfiles(Map<String, Map<String, String>> profiles) async {
    try {
      final db = await isar;
      
      // Get existing users to preserve followerCount
      final pubkeyHexList = profiles.keys.toList();
      final existingUsers = await db.userModels
          .where()
          .anyOf(pubkeyHexList, (q, String pubkeyHex) => q.pubkeyHexEqualTo(pubkeyHex))
          .findAll();
      final existingUsersMap = {for (var u in existingUsers) u.pubkeyHex: u};
      
      final userModels = profiles.entries.map((entry) {
        final userModel = UserModel.fromUserModel(entry.key, entry.value);
        // Preserve followerCount if it exists and is not being updated
        final existingUser = existingUsersMap[entry.key];
        if (existingUser != null && existingUser.followerCount != null && entry.value['followerCount'] == null) {
          userModel.followerCount = existingUser.followerCount;
        }
        return userModel;
      }).toList();

      await db.writeTxn(() async {
        await db.userModels.putAll(userModels);
      });

      debugPrint('[IsarDatabaseService]  Batch saved ${userModels.length} profiles');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch saving profiles: $e');
    }
  }

  Future<Map<String, String>?> getUserProfile(String pubkeyHex) async {
    try {
      final db = await isar;
      final user = await db.userModels.where().pubkeyHexEqualTo(pubkeyHex).findFirst();

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
      if (pubkeyHexList.isEmpty) return {};

      final db = await isar;
      final results = <String, Map<String, String>>{};

      final userModels = await db.userModels
          .where()
          .anyOf(pubkeyHexList, (q, String pubkeyHex) => q.pubkeyHexEqualTo(pubkeyHex))
          .findAll();

      for (final model in userModels) {
        results[model.pubkeyHex] = model.toProfileData();
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
      final count = await db.userModels.where().pubkeyHexEqualTo(pubkeyHex).count();
      return count > 0;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking profile existence: $e');
      return false;
    }
  }

  Future<void> updateFollowerCount(String pubkeyHex, int followerCount) async {
    try {
      if (followerCount == 0) {
        // Don't update if count is 0
        return;
      }

      final db = await isar;
      final user = await db.userModels.where().pubkeyHexEqualTo(pubkeyHex).findFirst();

      if (user != null) {
        await db.writeTxn(() async {
          user.followerCount = followerCount;
          await db.userModels.put(user);
        });
        debugPrint('[IsarDatabaseService] Updated follower count for $pubkeyHex: $followerCount');
      } else {
        debugPrint('[IsarDatabaseService] User not found for follower count update: $pubkeyHex');
      }
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error updating follower count: $e');
    }
  }

  Future<List<UserModel>> getAllUserProfiles() async {
    try {
      final db = await isar;
      return await db.userModels.where().findAll();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting all profiles: $e');
      return [];
    }
  }

  Future<List<UserModel>> searchUsersByName(String query, {int limit = 50}) async {
    try {
      if (query.isEmpty) return [];

      final db = await isar;
      final lowerQuery = query.toLowerCase();

      final allProfiles = await db.userModels.where().findAll();

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

  Future<List<UserModel>> getRandomUsersWithImages({int limit = 50}) async {
    try {
      final db = await isar;

      final allProfiles = await db.userModels.where().findAll();
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
      return await db.userModels.count();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting profile count: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final db = await isar;
      final totalProfiles = await db.userModels.count();
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

  Stream<UserModel?> watchUserProfile(String pubkeyHex) async* {
    final db = await isar;
    yield* db.userModels
        .where()
        .pubkeyHexEqualTo(pubkeyHex)
        .watch(fireImmediately: true)
        .map((users) => users.isEmpty ? null : users.first);
  }

  Stream<List<UserModel>> watchAllUserProfiles() async* {
    final db = await isar;
    yield* db.userModels.where().watch(fireImmediately: true);
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
      final followingModel = FollowingModel.fromFollowingModel(userPubkeyHex, followingPubkeys);

      await db.writeTxn(() async {
        await db.followingModels.put(followingModel);
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
        return FollowingModel.fromFollowingModel(entry.key, entry.value);
      }).toList();

      await db.writeTxn(() async {
        await db.followingModels.putAll(followingModels);
      });

      debugPrint('[IsarDatabaseService] Batch saved ${followingModels.length} following lists');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch saving following lists: $e');
    }
  }

  Future<List<String>?> getFollowingList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final followingModel = await db.followingModels.where().userPubkeyHexEqualTo(userPubkeyHex).findFirst();

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

      if (userPubkeyHexList.isEmpty) return results;

      final followingModels = await db.followingModels
          .where()
          .anyOf(userPubkeyHexList, (q, String userPubkeyHex) => q.userPubkeyHexEqualTo(userPubkeyHex))
          .findAll();

      for (final model in followingModels) {
        results[model.userPubkeyHex] = model.toFollowingList();
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
      final count = await db.followingModels.where().userPubkeyHexEqualTo(userPubkeyHex).count();
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
        await db.followingModels.deleteByUserPubkeyHex(userPubkeyHex);
      });
      debugPrint('[IsarDatabaseService] Deleted following list: $userPubkeyHex');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error deleting following list: $e');
    }
  }

  Future<List<FollowingModel>> getAllFollowingLists() async {
    try {
      final db = await isar;
      return await db.followingModels.where().findAll();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting all following lists: $e');
      return [];
    }
  }

  Future<int> getFollowingListCount() async {
    try {
      final db = await isar;
      return await db.followingModels.count();
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting following list count: $e');
      return 0;
    }
  }

  Future<int> cleanupExpiredFollowingLists({Duration ttl = const Duration(days: 3)}) async {
    try {
      final db = await isar;
      final cutoffDate = DateTime.now().subtract(ttl);

      final expiredFollowingLists = await db.followingModels.filter().cachedAtLessThan(cutoffDate).findAll();

      if (expiredFollowingLists.isEmpty) {
        return 0;
      }

      await db.writeTxn(() async {
        for (final followingList in expiredFollowingLists) {
          await db.followingModels.delete(followingList.id);
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
        await db.followingModels.clear();
      });
      debugPrint('[IsarDatabaseService] Cleared all following lists');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error clearing following lists: $e');
    }
  }

  Stream<FollowingModel?> watchFollowingList(String userPubkeyHex) async* {
    final db = await isar;
    yield* db.followingModels
        .where()
        .userPubkeyHexEqualTo(userPubkeyHex)
        .watch(fireImmediately: true)
        .map((followingLists) => followingLists.isEmpty ? null : followingLists.first);
  }

  Stream<List<FollowingModel>> watchAllFollowingLists() async* {
    final db = await isar;
    yield* db.followingModels.where().watch(fireImmediately: true);
  }

  Future<void> saveMuteList(String userPubkeyHex, List<String> mutedPubkeys) async {
    try {
      final db = await isar;
      final muteModel = MuteModel.fromMuteModel(userPubkeyHex, mutedPubkeys);

      await db.writeTxn(() async {
        await db.muteModels.put(muteModel);
      });

      debugPrint('[IsarDatabaseService] Saved mute list: ${mutedPubkeys.length} muted for $userPubkeyHex');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error saving mute list: $e');
    }
  }

  Future<void> saveMuteLists(Map<String, List<String>> muteLists) async {
    try {
      final db = await isar;
      final muteModels = muteLists.entries.map((entry) {
        return MuteModel.fromMuteModel(entry.key, entry.value);
      }).toList();

      await db.writeTxn(() async {
        await db.muteModels.putAll(muteModels);
      });

      debugPrint('[IsarDatabaseService] Batch saved ${muteModels.length} mute lists');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch saving mute lists: $e');
    }
  }

  Future<List<String>?> getMuteList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final muteModel = await db.muteModels.where().userPubkeyHexEqualTo(userPubkeyHex).findFirst();

      if (muteModel != null) {
        debugPrint('[IsarDatabaseService] Retrieved mute list from Isar: ${muteModel.mutedPubkeys.length} muted');
        return muteModel.toMuteList();
      }

      return null;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error getting mute list: $e');
      return null;
    }
  }

  Future<Map<String, List<String>>> getMuteLists(List<String> userPubkeyHexList) async {
    try {
      final db = await isar;
      final results = <String, List<String>>{};

      if (userPubkeyHexList.isEmpty) return results;

      final muteModels = await db.muteModels
          .where()
          .anyOf(userPubkeyHexList, (q, String userPubkeyHex) => q.userPubkeyHexEqualTo(userPubkeyHex))
          .findAll();

      for (final model in muteModels) {
        results[model.userPubkeyHex] = model.toMuteList();
      }

      debugPrint('[IsarDatabaseService] Batch retrieved ${results.length}/${userPubkeyHexList.length} mute lists from Isar');
      return results;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error batch getting mute lists: $e');
      return {};
    }
  }

  Future<bool> hasMuteList(String userPubkeyHex) async {
    try {
      final db = await isar;
      final count = await db.muteModels.where().userPubkeyHexEqualTo(userPubkeyHex).count();
      return count > 0;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error checking mute list existence: $e');
      return false;
    }
  }

  Future<void> deleteMuteList(String userPubkeyHex) async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.muteModels.deleteByUserPubkeyHex(userPubkeyHex);
      });
      debugPrint('[IsarDatabaseService] Deleted mute list: $userPubkeyHex');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error deleting mute list: $e');
    }
  }

  Future<void> clearAllMuteLists() async {
    try {
      final db = await isar;
      await db.writeTxn(() async {
        await db.muteModels.clear();
      });
      debugPrint('[IsarDatabaseService] Cleared all mute lists');
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error clearing mute lists: $e');
    }
  }

  Future<int> cleanupExpiredMuteLists({Duration ttl = const Duration(days: 3)}) async {
    try {
      final db = await isar;
      final cutoffDate = DateTime.now().subtract(ttl);

      final expiredMuteLists = await db.muteModels.filter().cachedAtLessThan(cutoffDate).findAll();

      if (expiredMuteLists.isEmpty) {
        return 0;
      }

      await db.writeTxn(() async {
        for (final muteList in expiredMuteLists) {
          await db.muteModels.delete(muteList.id);
        }
      });

      debugPrint('[IsarDatabaseService] Cleaned up ${expiredMuteLists.length} expired mute lists');
      return expiredMuteLists.length;
    } catch (e) {
      debugPrint('[IsarDatabaseService] Error cleaning up expired mute lists: $e');
      return 0;
    }
  }

  static void reset() {
    _instance?._isar?.close();
    _instance = null;
  }
}
