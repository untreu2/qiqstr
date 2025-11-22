import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/validation_service.dart';
import '../services/nostr_data_service.dart';
import '../services/user_cache_service.dart';
import '../services/user_batch_fetcher.dart';
import '../services/isar_database_service.dart';
import '../services/follow_cache_service.dart';
import '../services/mute_cache_service.dart';

class UserRepository {
  final AuthService _authService;
  final ValidationService _validationService;
  final NostrDataService _nostrDataService;
  final UserCacheService _cacheService;
  final UserBatchFetcher _batchFetcher;
  final FollowCacheService _followCacheService;
  final MuteCacheService _muteCacheService;

  final StreamController<UserModel> _currentUserController = StreamController<UserModel>.broadcast();
  final StreamController<List<UserModel>> _followingListController = StreamController<List<UserModel>>.broadcast();

  UserRepository({
    required AuthService authService,
    required ValidationService validationService,
    required NostrDataService nostrDataService,
    UserCacheService? cacheService,
    UserBatchFetcher? batchFetcher,
    FollowCacheService? followCacheService,
    MuteCacheService? muteCacheService,
  })  : _authService = authService,
        _validationService = validationService,
        _nostrDataService = nostrDataService,
        _cacheService = cacheService ?? UserCacheService.instance,
        _batchFetcher = batchFetcher ?? UserBatchFetcher.instance,
        _followCacheService = followCacheService ?? FollowCacheService.instance,
        _muteCacheService = muteCacheService ?? MuteCacheService.instance;

  Stream<UserModel> get currentUserStream => _currentUserController.stream;
  Stream<List<UserModel>> get followingListStream => _followingListController.stream;

  IsarDatabaseService get isarService => _cacheService.isarService;

  Future<Result<UserModel>> getCurrentUser() async {
    try {
      final userResult = await _authService.getCurrentUserNpub();

      if (userResult.isError) {
        return Result.error(userResult.error!);
      }

      final npub = userResult.data;
      if (npub == null || npub.isEmpty) {
        return const Result.error('No authenticated user');
      }

      final profileResult = await getUserProfile(npub);
      return profileResult.fold(
        (user) => Result.success(user),
        (error) {
          final basicUser = UserModel(
            pubkeyHex: npub,
            name: npub.substring(0, 8),
            profileImage: '',
            about: '',
            nip05: '',
            lud16: '',
            banner: '',
            website: '',
            updatedAt: DateTime.now(),
          );
          return Result.success(basicUser);
        },
      );
    } catch (e) {
      return Result.error('Failed to get current user: $e');
    }
  }

  Future<Result<UserModel>> getUserProfile(
    String npub, {
    FetchPriority priority = FetchPriority.normal,
  }) async {
    try {
      final validation = _validationService.validateNpub(npub);
      if (validation.isError) {
        return Result.error(validation.error ?? 'Invalid npub');
      }

      final pubkeyHex = _authService.npubToHex(npub) ?? npub;

      final user = await _cacheService.getOrFetch(
        pubkeyHex,
        () => _batchFetcher.fetchUser(pubkeyHex, priority: priority),
      );

      if (user != null) {
        return Result.success(user);
      }

      final directResult = await _nostrDataService.fetchUserProfile(npub);
      if (directResult.isSuccess && directResult.data != null) {
        _cacheService.put(directResult.data!);
        return directResult;
      }

      return const Result.error('User profile not found');
    } catch (e) {
      return Result.error('Failed to get user profile: $e');
    }
  }

  Future<Map<String, Result<UserModel>>> getUserProfiles(
    List<String> npubs, {
    FetchPriority priority = FetchPriority.normal,
  }) async {
    final results = <String, Result<UserModel>>{};

    try {
      final pubkeyHexMap = <String, String>{};
      for (final npub in npubs) {
        final validation = _validationService.validateNpub(npub);
        if (validation.isSuccess) {
          final hex = _authService.npubToHex(npub) ?? npub;
          pubkeyHexMap[hex] = npub;
        } else {
          results[npub] = Result.error('Invalid npub');
        }
      }

      final cachedUsers = await _cacheService.batchGet(pubkeyHexMap.keys.toList());
      for (final entry in cachedUsers.entries) {
        final npub = pubkeyHexMap[entry.key]!;
        results[npub] = Result.success(entry.value);
      }

      final missingHexKeys = pubkeyHexMap.keys.where((hex) => !cachedUsers.containsKey(hex)).toList();

      if (missingHexKeys.isNotEmpty) {
        debugPrint('[UserRepository] Batch fetching ${missingHexKeys.length} missing profiles');

        final fetchedUsers = await _batchFetcher.fetchUsers(
          missingHexKeys,
          priority: priority,
        );

        for (final entry in fetchedUsers.entries) {
          final npub = pubkeyHexMap[entry.key]!;
          if (entry.value != null) {
            await _cacheService.put(entry.value!);
            results[npub] = Result.success(entry.value!);
          } else {
            results[npub] = const Result.error('User not found');
          }
        }
      }

      return results;
    } catch (e) {
      debugPrint('[UserRepository] Error batch fetching profiles: $e');

      for (final npub in npubs) {
        if (!results.containsKey(npub)) {
          results[npub] = Result.error('Failed to fetch profile: $e');
        }
      }

      return results;
    }
  }

  Future<Result<UserModel>> updateProfile({
    String? name,
    String? about,
    String? profileImage,
    String? banner,
    String? website,
    String? nip05,
    String? lud16,
  }) async {
    try {
      final currentUserResult = await getCurrentUser();

      if (currentUserResult.isError) {
        return Result.error(currentUserResult.error!);
      }

      final currentUser = currentUserResult.data!;

      if (name != null && name.trim().isEmpty) {
        return const Result.error('Name cannot be empty');
      }

      if (website != null && website.isNotEmpty) {
        final urlValidation = _validationService.validateUrl(website);
        if (urlValidation.isError) {
          return Result.error(urlValidation.error ?? 'Invalid website URL');
        }
      }

      if (nip05 != null && nip05.isNotEmpty) {
        final nip05Validation = _validationService.validateNip05(nip05);
        if (nip05Validation.isError) {
          return Result.error(nip05Validation.error ?? 'Invalid NIP-05 identifier');
        }
      }

      final updatedUser = UserModel(
        pubkeyHex: currentUser.pubkeyHex,
        name: name ?? currentUser.name,
        about: about ?? currentUser.about,
        profileImage: profileImage ?? currentUser.profileImage,
        banner: banner ?? currentUser.banner,
        website: website ?? currentUser.website,
        nip05: nip05 ?? currentUser.nip05,
        lud16: lud16 ?? currentUser.lud16,
        updatedAt: DateTime.now(),
      );

      debugPrint('[UserRepository] Updating profile via NostrDataService...');
      final updateResult = await _nostrDataService.updateUserProfile(updatedUser);

      if (updateResult.isError) {
        debugPrint('[UserRepository] Profile update failed: ${updateResult.error}');
        return Result.error(updateResult.error!);
      }

      await _cacheService.put(updatedUser);

      _currentUserController.add(updatedUser);

      debugPrint('[UserRepository] Profile updated successfully, cache invalidated, and broadcasted to relays');
      return Result.success(updatedUser);
    } catch (e) {
      debugPrint('[UserRepository] Profile update error: $e');
      return Result.error('Failed to update profile: $e');
    }
  }

  Future<Result<UserModel>> updateUserProfile(UserModel user) async {
    try {
      return await _nostrDataService.updateUserProfile(user);
    } catch (e) {
      return Result.error('Failed to update user profile: $e');
    }
  }

  Future<Result<void>> followUser(String npub) async {
    try {
      final validation = _validationService.validateNpub(npub);
      if (validation.isError) {
        return Result.error(validation.error ?? 'Invalid npub');
      }

      debugPrint('[UserRepository] Following user: $npub');

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        return const Result.error('Private key not found');
      }

      final privateKey = privateKeyResult.data!;

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user npub not found');
      }

      final currentUserNpub = currentUserResult.data!;

      String currentUserHex = currentUserNpub;
      try {
        if (currentUserNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(currentUserNpub);
          if (hexResult != null) {
            currentUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting current user npub to hex: $e');
      }

      String targetUserHex = npub;
      try {
        if (npub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(npub);
          if (hexResult != null) {
            targetUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting target npub to hex: $e');
      }

      final cachedFollowing = await _followCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getFollowingList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      List<String> currentFollowing = cachedFollowing ?? [];

      if (currentFollowing.contains(targetUserHex)) {
        debugPrint('[UserRepository] Already following $targetUserHex');
        return const Result.success(null);
      }

      currentFollowing.add(targetUserHex);

      if (currentFollowing.isEmpty) {
        debugPrint('[UserRepository] Cannot publish an empty follow list. Follow operation aborted.');
        return const Result.error('Cannot publish empty follow list');
      }

      final result = await _nostrDataService.publishFollowEvent(
        followingHexList: currentFollowing,
        privateKey: privateKey,
      );

      if (result.isSuccess) {
        await _followCacheService.put(currentUserHex, currentFollowing);
      }

      return result;
    } catch (e) {
      return Result.error('Failed to follow user: $e');
    }
  }

  Future<Result<void>> unfollowUser(String npub) async {
    try {
      debugPrint('=== [UserRepository] UNFOLLOW OPERATION START ===');

      final validation = _validationService.validateNpub(npub);
      if (validation.isError) {
        debugPrint('[UserRepository] UNFOLLOW FAILED: Invalid npub - ${validation.error}');
        return Result.error(validation.error ?? 'Invalid npub');
      }

      debugPrint('[UserRepository] Unfollowing user: $npub');

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        return const Result.error('Private key not found');
      }

      final privateKey = privateKeyResult.data!;

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user npub not found');
      }

      final currentUserNpub = currentUserResult.data!;

      String currentUserHex = currentUserNpub;
      try {
        if (currentUserNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(currentUserNpub);
          if (hexResult != null) {
            currentUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting current user npub to hex: $e');
      }

      String targetUserHex = npub;
      try {
        if (npub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(npub);
          if (hexResult != null) {
            targetUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting target npub to hex: $e');
      }

      debugPrint('[UserRepository] Getting following list for: $currentUserHex');
      final cachedFollowing = await _followCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getFollowingList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      List<String> currentFollowing = cachedFollowing ?? [];
      debugPrint('[UserRepository] Current following list has ${currentFollowing.length} users');
      if (currentFollowing.isNotEmpty) {
        debugPrint('[UserRepository] Following list: ${currentFollowing.take(5).toList()}...');
      }

      final isCurrentlyFollowing = currentFollowing.contains(targetUserHex);
      debugPrint('[UserRepository] Is currently following $targetUserHex: $isCurrentlyFollowing');

      if (!isCurrentlyFollowing) {
        debugPrint('[UserRepository] Not following $targetUserHex - returning success (idempotent)');
        return const Result.success(null);
      }

      final beforeRemove = currentFollowing.length;
      currentFollowing.remove(targetUserHex);
      final afterRemove = currentFollowing.length;

      debugPrint('[UserRepository] Removed $targetUserHex from following list');
      debugPrint('[UserRepository] Following count: $beforeRemove → $afterRemove');

      debugPrint('[UserRepository] Publishing kind 3 unfollow event with ${currentFollowing.length} remaining following');

      final publishResult = await _nostrDataService.publishFollowEvent(
        followingHexList: currentFollowing,
        privateKey: privateKey,
      );

      if (publishResult.isSuccess) {
        await _followCacheService.put(currentUserHex, currentFollowing);
      }

      debugPrint('[UserRepository] Publish result: ${publishResult.isSuccess ? 'SUCCESS' : 'FAILED - ${publishResult.error}'}');
      return publishResult;
    } catch (e) {
      return Result.error('Failed to unfollow user: $e');
    }
  }

  Future<Result<bool>> isFollowing(String targetNpub) async {
    try {
      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Not authenticated');
      }

      final currentUserNpub = currentUserResult.data!;

      String currentUserHex = currentUserNpub;
      try {
        if (currentUserNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(currentUserNpub);
          if (hexResult != null) {
            currentUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting current user npub to hex: $e');
      }

      String targetUserHex = targetNpub;
      try {
        if (targetNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(targetNpub);
          if (hexResult != null) {
            targetUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting target npub to hex: $e');
      }

      final cachedFollowing = await _followCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getFollowingList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      return Result.success(cachedFollowing?.contains(targetUserHex) ?? false);
    } catch (e) {
      return Result.error('Failed to check follow status: $e');
    }
  }

  Future<Result<List<UserModel>>> getFollowingList() async {
    try {
      final currentUserResult = await getCurrentUser();

      if (currentUserResult.isError) {
        return Result.error(currentUserResult.error!);
      }

      final currentUser = currentUserResult.data!;
      return await getFollowingListForUser(currentUser.pubkeyHex);
    } catch (e) {
      return Result.error('Failed to get following list: $e');
    }
  }

  Future<Result<List<UserModel>>> getFollowingListForUser(String userNpub) async {
    try {
      debugPrint('[UserRepository] Getting following list for user: $userNpub');

      String userHex = userNpub;
      try {
        if (userNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(userNpub);
          if (hexResult != null) {
            userHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting user npub to hex: $e');
      }

      final cachedFollowing = await _followCacheService.getOrFetch(userHex, () async {
        final result = await _nostrDataService.getFollowingList(userHex);
        return result.isSuccess ? result.data : null;
      });

      if (cachedFollowing == null) {
        debugPrint('[UserRepository] Error getting following hex list for $userHex');
        return const Result.error('Failed to get following list');
      }

      final followingHexList = cachedFollowing;
      debugPrint('[UserRepository] Got ${followingHexList.length} following hex keys');

      final List<UserModel> followingUsers = [];

      for (final hexKey in followingHexList) {
        try {
          String npub = hexKey;
          try {
            final npubResult = _authService.hexToNpub(hexKey);
            if (npubResult != null) {
              npub = npubResult;
            }
          } catch (e) {
            debugPrint('[UserRepository] Error converting hex to npub for $hexKey: $e');
          }

          final basicUser = UserModel(
            pubkeyHex: npub,
            name: npub.substring(0, 8),
            profileImage: '',
            about: '',
            nip05: '',
            lud16: '',
            banner: '',
            website: '',
            updatedAt: DateTime.now(),
          );
          followingUsers.add(basicUser);
        } catch (e) {
          debugPrint('[UserRepository] Error processing following user $hexKey: $e');
        }
      }

      debugPrint('[UserRepository] Successfully created ${followingUsers.length} basic following users');

      if (userNpub == (await getCurrentUser()).data?.pubkeyHex) {
        _followingListController.add(followingUsers);
      }

      return Result.success(followingUsers);
    } catch (e) {
      debugPrint('[UserRepository] Error getting following list for user: $e');
      return Result.error('Failed to get following list: $e');
    }
  }

  Future<Result<List<UserModel>>> getFollowingListWithProfiles(String userNpub) async {
    try {
      final basicListResult = await getFollowingListForUser(userNpub);
      if (basicListResult.isError) {
        return basicListResult;
      }

      final basicUsers = basicListResult.data!;
      final List<UserModel> enrichedUsers = [];

      for (final basicUser in basicUsers) {
        try {
          final userProfileResult = await getUserProfile(basicUser.pubkeyHex);
          if (userProfileResult.isSuccess) {
            enrichedUsers.add(userProfileResult.data!);
          } else {
            enrichedUsers.add(basicUser);
          }
        } catch (e) {
          debugPrint('[UserRepository] Error enriching user profile: $e');
          enrichedUsers.add(basicUser);
        }
      }

      return Result.success(enrichedUsers);
    } catch (e) {
      return Result.error('Failed to get following list with profiles: $e');
    }
  }

  Future<Result<List<UserModel>>> searchUsers(String query) async {
    try {
      final trimmedQuery = query.trim();

      if (trimmedQuery.isEmpty) {
        return Result.success([]);
      }

      final results = <UserModel>[];

      final npubValidation = _validationService.validateNpub(trimmedQuery);
      if (npubValidation.isSuccess) {
        debugPrint('[UserRepository] Searching for user by npub: $trimmedQuery');

        final userProfileResult = await getUserProfile(trimmedQuery);
        if (userProfileResult.isSuccess) {
          results.add(userProfileResult.data!);
          debugPrint('[UserRepository] Found user by npub: ${userProfileResult.data!.name}');
        } else {
          debugPrint('[UserRepository] Could not fetch user profile for npub: ${userProfileResult.error}');
        }
      } else {
        debugPrint('[UserRepository] Searching users in Isar cache: "$trimmedQuery"');

        final isarService = _cacheService.isarService;
        if (isarService.isInitialized) {
          final matchingProfiles = await isarService.searchUsersByName(trimmedQuery, limit: 50);

          for (final isarProfile in matchingProfiles) {
            final profileData = isarProfile.toProfileData();
            final userModel = UserModel.fromCachedProfile(
              isarProfile.pubkeyHex,
              profileData,
            );
            results.add(userModel);
          }

          debugPrint('[UserRepository] Found ${results.length} users from Isar cache');
        } else {
          debugPrint('[UserRepository] Isar not initialized');
        }
      }

      return Result.success(results);
    } catch (e) {
      debugPrint('[UserRepository] Search users error: $e');
      return Result.error('Failed to search users: $e');
    }
  }

  Future<UserModel?> getCachedUser(String npub) async {
    final pubkeyHex = _authService.npubToHex(npub) ?? npub;
    return await _cacheService.get(pubkeyHex);
  }

  UserModel? getCachedUserSync(String npub) {
    final pubkeyHex = _authService.npubToHex(npub) ?? npub;
    return _cacheService.getSync(pubkeyHex);
  }

  Future<void> cacheUser(UserModel user) async {
    await _cacheService.put(user);
  }

  Future<void> clearCache() async {
    await _cacheService.clear();
  }

  Future<void> invalidateUserCache(String npub) async {
    final pubkeyHex = _authService.npubToHex(npub) ?? npub;
    await _cacheService.invalidate(pubkeyHex);
  }

  Future<Map<String, dynamic>> getCacheStats() async {
    return {
      'cache': await _cacheService.getStats(),
      'batchFetcher': _batchFetcher.getStats(),
    };
  }

  Future<void> printCacheStats() async {
    debugPrint('\n=== UserRepository Statistics ===');
    await _cacheService.printStats();
    _batchFetcher.printStats();
    debugPrint('================================\n');
  }

  int getCachedUserCount() {
    return _cacheService.memoryCache.length;
  }

  Map<String, UserModel> getAllCachedUsers() {
    final cache = _cacheService.memoryCache;
    final result = <String, UserModel>{};
    for (final entry in cache.entries) {
      result[entry.key] = entry.value.user;
    }
    return result;
  }

  Future<void> pruneLeastRecentlyUsed(int maxUsers) async {
    try {
      final cache = _cacheService.memoryCache;
      if (cache.length <= maxUsers) {
        return;
      }

      final sortedEntries = cache.entries.toList()
        ..sort((a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt));

      final toRemoveCount = cache.length - maxUsers;
      final keysToRemove = sortedEntries.take(toRemoveCount).map((e) => e.key).toList();

      for (final key in keysToRemove) {
        cache.remove(key);
      }

      debugPrint('[UserRepository] Pruned $toRemoveCount least recently used profiles');
    } catch (e) {
      debugPrint('[UserRepository] Error pruning users: $e');
    }
  }

  Future<Result<void>> muteUser(String npub) async {
    try {
      final validation = _validationService.validateNpub(npub);
      if (validation.isError) {
        return Result.error(validation.error ?? 'Invalid npub');
      }

      debugPrint('[UserRepository] Muting user: $npub');

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        return const Result.error('Private key not found');
      }

      final privateKey = privateKeyResult.data!;

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user npub not found');
      }

      final currentUserNpub = currentUserResult.data!;

      String currentUserHex = currentUserNpub;
      try {
        if (currentUserNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(currentUserNpub);
          if (hexResult != null) {
            currentUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting current user npub to hex: $e');
      }

      String targetUserHex = npub;
      try {
        if (npub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(npub);
          if (hexResult != null) {
            targetUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting target npub to hex: $e');
      }

      final cachedMuted = await _muteCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getMuteList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      List<String> currentMuted = cachedMuted ?? [];

      if (currentMuted.contains(targetUserHex)) {
        debugPrint('[UserRepository] Already muting $targetUserHex');
        return const Result.success(null);
      }

      currentMuted.add(targetUserHex);

      final result = await _nostrDataService.publishMuteEvent(
        mutedHexList: currentMuted,
        privateKey: privateKey,
      );

      if (result.isSuccess) {
        await _muteCacheService.put(currentUserHex, currentMuted);
      }

      return result;
    } catch (e) {
      return Result.error('Failed to mute user: $e');
    }
  }

  Future<Result<void>> unmuteUser(String npub) async {
    try {
      debugPrint('[UserRepository] Unmuting user: $npub');

      final validation = _validationService.validateNpub(npub);
      if (validation.isError) {
        return Result.error(validation.error ?? 'Invalid npub');
      }

      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        return const Result.error('Private key not found');
      }

      final privateKey = privateKeyResult.data!;

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user npub not found');
      }

      final currentUserNpub = currentUserResult.data!;

      String currentUserHex = currentUserNpub;
      try {
        if (currentUserNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(currentUserNpub);
          if (hexResult != null) {
            currentUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting current user npub to hex: $e');
      }

      String targetUserHex = npub;
      try {
        if (npub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(npub);
          if (hexResult != null) {
            targetUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting target npub to hex: $e');
      }

      debugPrint('[UserRepository] Getting mute list for: $currentUserHex');
      final cachedMuted = await _muteCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getMuteList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      List<String> currentMuted = cachedMuted ?? [];
      debugPrint('[UserRepository] Current mute list has ${currentMuted.length} users');

      final isCurrentlyMuted = currentMuted.contains(targetUserHex);
      debugPrint('[UserRepository] Is currently muting $targetUserHex: $isCurrentlyMuted');

      if (!isCurrentlyMuted) {
        debugPrint('[UserRepository] Not muting $targetUserHex - returning success (idempotent)');
        return const Result.success(null);
      }

      currentMuted.remove(targetUserHex);

      debugPrint('[UserRepository] Publishing kind 10000 unmute event with ${currentMuted.length} remaining muted');

      final publishResult = await _nostrDataService.publishMuteEvent(
        mutedHexList: currentMuted,
        privateKey: privateKey,
      );

      if (publishResult.isSuccess) {
        await _muteCacheService.put(currentUserHex, currentMuted);
      }

      debugPrint('[UserRepository] Publish result: ${publishResult.isSuccess ? 'SUCCESS' : 'FAILED - ${publishResult.error}'}');
      return publishResult;
    } catch (e) {
      return Result.error('Failed to unmute user: $e');
    }
  }

  Future<Result<bool>> isMuted(String targetNpub) async {
    try {
      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Not authenticated');
      }

      final currentUserNpub = currentUserResult.data!;

      String currentUserHex = currentUserNpub;
      try {
        if (currentUserNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(currentUserNpub);
          if (hexResult != null) {
            currentUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting current user npub to hex: $e');
      }

      String targetUserHex = targetNpub;
      try {
        if (targetNpub.startsWith('npub1')) {
          final hexResult = _authService.npubToHex(targetNpub);
          if (hexResult != null) {
            targetUserHex = hexResult;
          }
        }
      } catch (e) {
        debugPrint('[UserRepository] Error converting target npub to hex: $e');
      }

      final cachedMuted = await _muteCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getMuteList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      return Result.success(cachedMuted?.contains(targetUserHex) ?? false);
    } catch (e) {
      return Result.error('Failed to check mute status: $e');
    }
  }

  Future<void> updateUserFollowerCount(String pubkeyHex, int followerCount) async {
    try {
      if (followerCount == 0) {
        // Don't update if count is 0
        return;
      }

      final hex = _authService.npubToHex(pubkeyHex) ?? pubkeyHex;
      await _cacheService.isarService.updateFollowerCount(hex, followerCount);
      
      debugPrint('[UserRepository] Updated follower count for $hex: $followerCount');
    } catch (e) {
      debugPrint('[UserRepository] Error updating follower count: $e');
    }
  }

  Future<void> dispose() async {
    _currentUserController.close();
    _followingListController.close();
    await _cacheService.dispose();
  }
}
