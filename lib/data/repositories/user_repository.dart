import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../services/auth_service.dart';
import '../services/validation_service.dart';
import '../services/data_service.dart';
import '../services/user_cache_service.dart';
import '../services/user_batch_fetcher.dart';
import '../services/isar_database_service.dart';
import '../services/follow_cache_service.dart';
import '../services/mute_cache_service.dart';
import '../services/primal_cache_service.dart';

class UserRepository {
  final AuthService _authService;
  final ValidationService _validationService;
  final DataService _nostrDataService;
  final UserCacheService _cacheService;
  final UserBatchFetcher _batchFetcher;
  final FollowCacheService _followCacheService;
  final MuteCacheService _muteCacheService;
  final PrimalCacheService _primalCacheService = PrimalCacheService.instance;

  final StreamController<Map<String, dynamic>> _currentUserController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _followingListController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  UserRepository({
    required AuthService authService,
    required ValidationService validationService,
    required DataService nostrDataService,
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

  Stream<Map<String, dynamic>> get currentUserStream =>
      _currentUserController.stream;
  Stream<List<Map<String, dynamic>>> get followingListStream =>
      _followingListController.stream;

  IsarDatabaseService get isarService => _cacheService.isarService;

  Map<String, dynamic>? _userToMap(dynamic user) {
    if (user == null) return null;
    if (user is Map<String, dynamic>) {
      final userMap = Map<String, dynamic>.from(user);
      if (!userMap.containsKey('npub') ||
          (userMap['npub'] as String? ?? '').isEmpty) {
        final pubkeyHex = userMap['pubkeyHex'] as String? ?? '';
        if (pubkeyHex.isNotEmpty) {
          final npub = _authService.hexToNpub(pubkeyHex) ?? pubkeyHex;
          userMap['npub'] = npub;
        }
      }
      return userMap;
    }

    try {
      final pubkeyHex = (user as dynamic).pubkeyHex as String? ?? '';
      final npub = pubkeyHex.isNotEmpty
          ? (_authService.hexToNpub(pubkeyHex) ?? pubkeyHex)
          : '';

      return {
        'pubkeyHex': pubkeyHex,
        'npub': npub,
        'name': (user as dynamic).name as String? ?? '',
        'about': (user as dynamic).about as String? ?? '',
        'profileImage': (user as dynamic).profileImage as String? ?? '',
        'banner': (user as dynamic).banner as String? ?? '',
        'website': (user as dynamic).website as String? ?? '',
        'nip05': (user as dynamic).nip05 as String? ?? '',
        'lud16': (user as dynamic).lud16 as String? ?? '',
        'updatedAt': (user as dynamic).updatedAt as DateTime? ?? DateTime.now(),
        'nip05Verified': (user as dynamic).nip05Verified as bool? ?? false,
        'followerCount': (user as dynamic).followerCount as int? ?? 0,
      };
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _createUserMap({
    required String pubkeyHex,
    String name = '',
    String about = '',
    String profileImage = '',
    String banner = '',
    String website = '',
    String nip05 = '',
    String lud16 = '',
    DateTime? updatedAt,
    bool nip05Verified = false,
    int followerCount = 0,
  }) {
    final npub = pubkeyHex.isNotEmpty
        ? (_authService.hexToNpub(pubkeyHex) ?? pubkeyHex)
        : '';

    return {
      'pubkeyHex': pubkeyHex,
      'npub': npub,
      'name': name,
      'about': about,
      'profileImage': profileImage,
      'banner': banner,
      'website': website,
      'nip05': nip05,
      'lud16': lud16,
      'updatedAt': updatedAt ?? DateTime.now(),
      'nip05Verified': nip05Verified,
      'followerCount': followerCount,
    };
  }

  Map<String, dynamic> _copyUserMap(
    Map<String, dynamic> user, {
    String? name,
    String? about,
    String? profileImage,
    String? banner,
    String? website,
    String? nip05,
    String? lud16,
    DateTime? updatedAt,
    bool? nip05Verified,
    int? followerCount,
  }) {
    return {
      'pubkeyHex': user['pubkeyHex'] as String? ?? '',
      'name': name ?? user['name'] as String? ?? '',
      'about': about ?? user['about'] as String? ?? '',
      'profileImage': profileImage ?? user['profileImage'] as String? ?? '',
      'banner': banner ?? user['banner'] as String? ?? '',
      'website': website ?? user['website'] as String? ?? '',
      'nip05': nip05 ?? user['nip05'] as String? ?? '',
      'lud16': lud16 ?? user['lud16'] as String? ?? '',
      'updatedAt':
          updatedAt ?? user['updatedAt'] as DateTime? ?? DateTime.now(),
      'nip05Verified': nip05Verified ?? user['nip05Verified'] as bool? ?? false,
      'followerCount': followerCount ?? user['followerCount'] as int? ?? 0,
    };
  }

  Future<Result<Map<String, dynamic>>> getCurrentUser() async {
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
      if (profileResult.isSuccess && profileResult.data != null) {
        return Result.success(profileResult.data!);
      }

      final basicUser = _createUserMap(
        pubkeyHex: npub,
        name: npub.length > 8 ? npub.substring(0, 8) : npub,
        profileImage: '',
        about: '',
        nip05: '',
        lud16: '',
        banner: '',
        website: '',
      );
      return Result.success(basicUser);
    } catch (e) {
      return Result.error('Failed to get current user: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> getUserProfile(
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
        final userMap = _userToMap(user);
        if (userMap != null) {
          return Result.success(userMap);
        }
      }

      try {
        final primalProfiles =
            await _primalCacheService.fetchUserInfos([pubkeyHex]);
        if (primalProfiles.containsKey(pubkeyHex)) {
          final userMap =
              _mapPrimalProfileToUser(pubkeyHex, primalProfiles[pubkeyHex]!);
          final userModel = _userFromMap(userMap);
          if (userModel != null) {
            await _cacheService.put(userModel);
          }
          return Result.success(userMap);
        }
      } catch (_) {}

      final directResult = await _nostrDataService.fetchUserProfile(npub);
      if (directResult.isSuccess && directResult.data != null) {
        final userModel = directResult.data!;
        await _cacheService.put(userModel);
        final userMap = _userToMap(userModel);
        if (userMap != null) {
          return Result.success(userMap);
        }
      }

      return const Result.error('User profile not found');
    } catch (e) {
      return Result.error('Failed to get user profile: $e');
    }
  }

  dynamic _userFromMap(Map<String, dynamic> userMap) {
    try {
      final pubkeyHex = userMap['pubkeyHex'] as String? ?? '';
      final name = userMap['name'] as String? ?? '';
      final about = userMap['about'] as String? ?? '';
      final profileImage = userMap['profileImage'] as String? ?? '';
      final banner = userMap['banner'] as String? ?? '';
      final website = userMap['website'] as String? ?? '';
      final nip05 = userMap['nip05'] as String? ?? '';
      final lud16 = userMap['lud16'] as String? ?? '';
      final updatedAt = userMap['updatedAt'] as DateTime? ?? DateTime.now();
      final nip05Verified = userMap['nip05Verified'] as bool? ?? false;
      final followerCount = userMap['followerCount'] as int? ?? 0;

      return {
        'pubkeyHex': pubkeyHex,
        'name': name,
        'about': about,
        'profileImage': profileImage,
        'banner': banner,
        'website': website,
        'nip05': nip05,
        'lud16': lud16,
        'updatedAt': updatedAt,
        'nip05Verified': nip05Verified,
        'followerCount': followerCount,
      };
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, Result<Map<String, dynamic>>>> getUserProfiles(
    List<String> npubs, {
    FetchPriority priority = FetchPriority.normal,
  }) async {
    final results = <String, Result<Map<String, dynamic>>>{};

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

      final cachedUsers =
          await _cacheService.batchGet(pubkeyHexMap.keys.toList());
      for (final entry in cachedUsers.entries) {
        final npub = pubkeyHexMap[entry.key]!;
        final userMap = _userToMap(entry.value);
        if (userMap != null) {
          results[npub] = Result.success(userMap);
        } else {
          results[npub] = const Result.error('Failed to convert user');
        }
      }

      var missingHexKeys = pubkeyHexMap.keys
          .where((hex) => !cachedUsers.containsKey(hex))
          .toList();

      if (missingHexKeys.isNotEmpty) {
        debugPrint(
            '[UserRepository] Batch fetching ${missingHexKeys.length} missing profiles');

        try {
          final primalProfiles =
              await _primalCacheService.fetchUserInfos(missingHexKeys);
          if (primalProfiles.isNotEmpty) {
            for (final entry in primalProfiles.entries) {
              final npub = pubkeyHexMap[entry.key];
              if (npub != null) {
                final userMap = _mapPrimalProfileToUser(entry.key, entry.value);
                final userModel = _userFromMap(userMap);
                if (userModel != null) {
                  await _cacheService.put(userModel);
                }
                results[npub] = Result.success(userMap);
              }
            }
          }
          missingHexKeys = missingHexKeys
              .where((hex) => !primalProfiles.containsKey(hex))
              .toList();
        } catch (_) {}

        if (missingHexKeys.isNotEmpty) {
          final fetchedUsers = await _batchFetcher.fetchUsers(
            missingHexKeys,
            priority: priority,
          );

          for (final entry in fetchedUsers.entries) {
            final npub = pubkeyHexMap[entry.key]!;
            if (entry.value != null) {
              await _cacheService.put(entry.value!);
              final userMap = _userToMap(entry.value);
              if (userMap != null) {
                results[npub] = Result.success(userMap);
              } else {
                results[npub] = const Result.error('Failed to convert user');
              }
            } else {
              results[npub] = const Result.error('User not found');
            }
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

  Future<Result<Map<String, dynamic>>> updateProfile({
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
          return Result.error(
              nip05Validation.error ?? 'Invalid NIP-05 identifier');
        }
      }

      final updatedUser = _copyUserMap(
        currentUser,
        name: name,
        about: about,
        profileImage: profileImage,
        banner: banner,
        website: website,
        nip05: nip05,
        lud16: lud16,
        updatedAt: DateTime.now(),
      );

      debugPrint('[UserRepository] Updating profile via NostrDataService...');
      final userModel = _userFromMap(updatedUser);
      if (userModel == null) {
        return const Result.error('Failed to convert user map');
      }
      final updateResult = await _nostrDataService.updateUserProfile(userModel);

      if (updateResult.isError) {
        debugPrint(
            '[UserRepository] Profile update failed: ${updateResult.error}');
        return Result.error(updateResult.error!);
      }

      await _cacheService.put(userModel);

      _currentUserController.add(updatedUser);

      debugPrint(
          '[UserRepository] Profile updated successfully, cache invalidated, and broadcasted to relays');
      return Result.success(updatedUser);
    } catch (e) {
      debugPrint('[UserRepository] Profile update error: $e');
      return Result.error('Failed to update profile: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> updateUserProfile(
      Map<String, dynamic> user) async {
    try {
      final userModel = _userFromMap(user);
      if (userModel == null) {
        return const Result.error('Failed to convert user map');
      }
      final result = await _nostrDataService.updateUserProfile(userModel);
      if (result.isSuccess && result.data != null) {
        final userMap = _userToMap(result.data!);
        if (userMap != null) {
          return Result.success(userMap);
        }
      }
      return Result.error(result.error ?? 'Failed to update user profile');
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
        debugPrint(
            '[UserRepository] Error converting current user npub to hex: $e');
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

      final cachedFollowing =
          await _followCacheService.getOrFetch(currentUserHex, () async {
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
        debugPrint(
            '[UserRepository] Cannot publish an empty follow list. Follow operation aborted.');
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
        debugPrint(
            '[UserRepository] UNFOLLOW FAILED: Invalid npub - ${validation.error}');
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
        debugPrint(
            '[UserRepository] Error converting current user npub to hex: $e');
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

      debugPrint(
          '[UserRepository] Getting following list for: $currentUserHex');
      final cachedFollowing =
          await _followCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getFollowingList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      List<String> currentFollowing = cachedFollowing ?? [];
      debugPrint(
          '[UserRepository] Current following list has ${currentFollowing.length} users');
      if (currentFollowing.isNotEmpty) {
        debugPrint(
            '[UserRepository] Following list: ${currentFollowing.take(5).toList()}...');
      }

      final isCurrentlyFollowing = currentFollowing.contains(targetUserHex);
      debugPrint(
          '[UserRepository] Is currently following $targetUserHex: $isCurrentlyFollowing');

      if (!isCurrentlyFollowing) {
        debugPrint(
            '[UserRepository] Not following $targetUserHex - returning success (idempotent)');
        return const Result.success(null);
      }

      final beforeRemove = currentFollowing.length;
      currentFollowing.remove(targetUserHex);
      final afterRemove = currentFollowing.length;

      debugPrint('[UserRepository] Removed $targetUserHex from following list');
      debugPrint(
          '[UserRepository] Following count: $beforeRemove → $afterRemove');

      debugPrint(
          '[UserRepository] Publishing kind 3 unfollow event with ${currentFollowing.length} remaining following');

      final publishResult = await _nostrDataService.publishFollowEvent(
        followingHexList: currentFollowing,
        privateKey: privateKey,
      );

      if (publishResult.isSuccess) {
        await _followCacheService.put(currentUserHex, currentFollowing);
      }

      debugPrint(
          '[UserRepository] Publish result: ${publishResult.isSuccess ? 'SUCCESS' : 'FAILED - ${publishResult.error}'}');
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
        debugPrint(
            '[UserRepository] Error converting current user npub to hex: $e');
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

      final cachedFollowing =
          await _followCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getFollowingList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      return Result.success(cachedFollowing?.contains(targetUserHex) ?? false);
    } catch (e) {
      return Result.error('Failed to check follow status: $e');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getFollowingList() async {
    try {
      final currentUserResult = await getCurrentUser();

      if (currentUserResult.isError) {
        return Result.error(currentUserResult.error!);
      }

      final currentUser = currentUserResult.data!;
      final pubkeyHex = currentUser['pubkeyHex'] as String? ?? '';
      return await getFollowingListForUser(pubkeyHex);
    } catch (e) {
      return Result.error('Failed to get following list: $e');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getFollowingListForUser(
      String userNpub) async {
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

      final cachedFollowing =
          await _followCacheService.getOrFetch(userHex, () async {
        final result = await _nostrDataService.getFollowingList(userHex);
        return result.isSuccess ? result.data : null;
      });

      if (cachedFollowing == null) {
        debugPrint(
            '[UserRepository] Error getting following hex list for $userHex');
        return const Result.error('Failed to get following list');
      }

      final followingHexList = cachedFollowing;
      debugPrint(
          '[UserRepository] Got ${followingHexList.length} following hex keys');

      final List<Map<String, dynamic>> followingUsers = [];

      for (final hexKey in followingHexList) {
        try {
          String npub = hexKey;
          try {
            final npubResult = _authService.hexToNpub(hexKey);
            if (npubResult != null) {
              npub = npubResult;
            }
          } catch (e) {
            debugPrint(
                '[UserRepository] Error converting hex to npub for $hexKey: $e');
          }

          final basicUser = _createUserMap(
            pubkeyHex: npub,
            name: npub.length > 8 ? npub.substring(0, 8) : npub,
            profileImage: '',
            about: '',
            nip05: '',
            lud16: '',
            banner: '',
            website: '',
          );
          followingUsers.add(basicUser);
        } catch (e) {
          debugPrint(
              '[UserRepository] Error processing following user $hexKey: $e');
        }
      }

      debugPrint(
          '[UserRepository] Successfully created ${followingUsers.length} basic following users');

      final currentUserResult = await getCurrentUser();
      final currentUserPubkeyHex =
          currentUserResult.data?['pubkeyHex'] as String? ?? '';
      if (userNpub == currentUserPubkeyHex) {
        _followingListController.add(followingUsers);
      }

      return Result.success(followingUsers);
    } catch (e) {
      debugPrint('[UserRepository] Error getting following list for user: $e');
      return Result.error('Failed to get following list: $e');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getFollowingListWithProfiles(
      String userNpub) async {
    try {
      final basicListResult = await getFollowingListForUser(userNpub);
      if (basicListResult.isError) {
        return basicListResult;
      }

      final basicUsers = basicListResult.data!;
      final List<Map<String, dynamic>> enrichedUsers = [];

      for (final basicUser in basicUsers) {
        try {
          final pubkeyHex = basicUser['pubkeyHex'] as String? ?? '';
          final userProfileResult = await getUserProfile(pubkeyHex);
          if (userProfileResult.isSuccess && userProfileResult.data != null) {
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

  Future<Result<List<Map<String, dynamic>>>> searchUsers(String query) async {
    try {
      final trimmedQuery = query.trim();

      if (trimmedQuery.isEmpty) {
        return Result.success([]);
      }

      final results = <Map<String, dynamic>>[];

      final npubValidation = _validationService.validateNpub(trimmedQuery);
      if (npubValidation.isSuccess) {
        debugPrint(
            '[UserRepository] Searching for user by npub: $trimmedQuery');

        final userProfileResult = await getUserProfile(trimmedQuery);
        if (userProfileResult.isSuccess && userProfileResult.data != null) {
          results.add(userProfileResult.data!);
          final userName = userProfileResult.data!['name'] as String? ?? '';
          debugPrint('[UserRepository] Found user by npub: $userName');
        } else {
          debugPrint(
              '[UserRepository] Could not fetch user profile for npub: ${userProfileResult.error}');
        }
      } else {
        debugPrint(
            '[UserRepository] Searching users in cache: "$trimmedQuery"');

        final isarService = _cacheService.isarService;
        if (isarService.isInitialized) {
          try {
            final matchingProfiles =
                await isarService.searchUserProfiles(trimmedQuery, limit: 50);

            final seenPubkeys = <String>{};

            for (final profileData in matchingProfiles) {
              final pubkeyHex = profileData['pubkeyHex'] ?? '';
              if (pubkeyHex.isEmpty || seenPubkeys.contains(pubkeyHex)) {
                continue;
              }
              seenPubkeys.add(pubkeyHex);

              final npub = _authService.hexToNpub(pubkeyHex) ?? pubkeyHex;
              final userMap = <String, dynamic>{
                'pubkeyHex': pubkeyHex,
                'npub': npub,
                'name': profileData['name'] ?? '',
                'about': profileData['about'] ?? '',
                'profileImage': profileData['profileImage'] ?? '',
                'banner': profileData['banner'] ?? '',
                'website': profileData['website'] ?? '',
                'nip05': profileData['nip05'] ?? '',
                'lud16': profileData['lud16'] ?? '',
                'nip05Verified': profileData['nip05Verified'] == 'true',
              };
              results.add(userMap);
            }

            debugPrint(
                '[UserRepository] Found ${results.length} users from cache');
          } catch (e) {
            debugPrint('[UserRepository] Error searching cache: $e');
          }
        } else {
          debugPrint('[UserRepository] Isar not initialized');
        }
      }

      final seenPubkeys = <String>{};
      final deduplicatedResults = <Map<String, dynamic>>[];
      for (final user in results) {
        final pubkeyHex = user['pubkeyHex'] as String? ?? '';
        if (pubkeyHex.isNotEmpty && !seenPubkeys.contains(pubkeyHex)) {
          seenPubkeys.add(pubkeyHex);
          deduplicatedResults.add(user);
        }
      }

      return Result.success(deduplicatedResults);
    } catch (e) {
      debugPrint('[UserRepository] Search users error: $e');
      return Result.error('Failed to search users: $e');
    }
  }

  Future<Map<String, dynamic>?> getCachedUser(String npub) async {
    final pubkeyHex = _authService.npubToHex(npub) ?? npub;
    final user = await _cacheService.get(pubkeyHex);
    return _userToMap(user);
  }

  Future<void> cacheUser(Map<String, dynamic> user) async {
    final userModel = _userFromMap(user);
    if (userModel != null) {
      await _cacheService.put(userModel);
    }
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

  Future<int> getCachedUserCount() async {
    return await _cacheService.isarService.getUserProfileCount();
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
        debugPrint(
            '[UserRepository] Error converting current user npub to hex: $e');
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

      final cachedMuted =
          await _muteCacheService.getOrFetch(currentUserHex, () async {
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
        debugPrint(
            '[UserRepository] Error converting current user npub to hex: $e');
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
      final cachedMuted =
          await _muteCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getMuteList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      List<String> currentMuted = cachedMuted ?? [];
      debugPrint(
          '[UserRepository] Current mute list has ${currentMuted.length} users');

      final isCurrentlyMuted = currentMuted.contains(targetUserHex);
      debugPrint(
          '[UserRepository] Is currently muting $targetUserHex: $isCurrentlyMuted');

      if (!isCurrentlyMuted) {
        debugPrint(
            '[UserRepository] Not muting $targetUserHex - returning success (idempotent)');
        return const Result.success(null);
      }

      currentMuted.remove(targetUserHex);

      debugPrint(
          '[UserRepository] Publishing kind 10000 unmute event with ${currentMuted.length} remaining muted');

      final publishResult = await _nostrDataService.publishMuteEvent(
        mutedHexList: currentMuted,
        privateKey: privateKey,
      );

      if (publishResult.isSuccess) {
        await _muteCacheService.put(currentUserHex, currentMuted);
      }

      debugPrint(
          '[UserRepository] Publish result: ${publishResult.isSuccess ? 'SUCCESS' : 'FAILED - ${publishResult.error}'}');
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
        debugPrint(
            '[UserRepository] Error converting current user npub to hex: $e');
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

      final cachedMuted =
          await _muteCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getMuteList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      return Result.success(cachedMuted?.contains(targetUserHex) ?? false);
    } catch (e) {
      return Result.error('Failed to check mute status: $e');
    }
  }

  Future<void> updateUserFollowerCount(
      String pubkeyHex, int followerCount) async {
    try {
      if (followerCount == 0) {
        // Don't update if count is 0
        return;
      }

      final hex = _authService.npubToHex(pubkeyHex) ?? pubkeyHex;
      try {
        final user = await _cacheService.get(hex);
        if (user != null) {
          final userMap = _userToMap(user);
          if (userMap != null) {
            final updatedUser =
                _copyUserMap(userMap, followerCount: followerCount);
            final userModel = _userFromMap(updatedUser);
            if (userModel != null) {
              await _cacheService.put(userModel);
            }
          }
        }
        debugPrint(
            '[UserRepository] Updated follower count for $hex: $followerCount');
      } catch (e) {
        debugPrint('[UserRepository] Error updating follower count: $e');
      }
    } catch (e) {
      debugPrint('[UserRepository] Error updating follower count: $e');
    }
  }

  Future<void> dispose() async {
    _currentUserController.close();
    _followingListController.close();
    await _cacheService.dispose();
  }

  Map<String, dynamic> _mapPrimalProfileToUser(
      String pubkeyHex, Map<String, dynamic> data) {
    String stringValue(dynamic v) => v is String ? v : (v?.toString() ?? '');
    final name = stringValue(data['name']).isNotEmpty
        ? stringValue(data['name'])
        : (stringValue(data['display_name']).isNotEmpty
            ? stringValue(data['display_name'])
            : (pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex));
    final profileImage = stringValue(data['picture']);
    final banner = stringValue(data['banner']);
    final about = stringValue(data['about']);
    final website = stringValue(data['website']);
    final nip05 = stringValue(data['nip05']);
    final lud16 = stringValue(data['lud16']);
    final followerCountRaw = data['followers_count'];
    final followerCount = followerCountRaw is int
        ? followerCountRaw
        : (followerCountRaw != null
                ? int.tryParse(stringValue(followerCountRaw))
                : null) ??
            0;
    final nip05VerifiedRaw = data['nip05_verified'];
    final nip05Verified = nip05VerifiedRaw is bool
        ? nip05VerifiedRaw
        : nip05VerifiedRaw == 'true';

    return _createUserMap(
      pubkeyHex: pubkeyHex,
      name: name,
      about: about,
      profileImage: profileImage,
      banner: banner,
      website: website,
      nip05: nip05,
      lud16: lud16,
      nip05Verified: nip05Verified,
      followerCount: followerCount,
    );
  }
}
