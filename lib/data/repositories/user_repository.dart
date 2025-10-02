import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/validation_service.dart';
import '../services/nostr_data_service.dart';

/// Repository for user-related operations
/// Handles user profiles, following relationships, and user data management
class UserRepository {
  final AuthService _authService;
  final ValidationService _validationService;
  final NostrDataService _nostrDataService;

  // Internal state
  final StreamController<UserModel> _currentUserController = StreamController<UserModel>.broadcast();
  final StreamController<List<UserModel>> _followingListController = StreamController<List<UserModel>>.broadcast();
  final Map<String, UserModel> _userCache = {};

  UserRepository({
    required AuthService authService,
    required ValidationService validationService,
    required NostrDataService nostrDataService,
  })  : _authService = authService,
        _validationService = validationService,
        _nostrDataService = nostrDataService;

  // Streams
  Stream<UserModel> get currentUserStream => _currentUserController.stream;
  Stream<List<UserModel>> get followingListStream => _followingListController.stream;

  /// Get current user profile
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

      // Get user profile data
      final profileResult = await getUserProfile(npub);
      return profileResult.fold(
        (user) => Result.success(user),
        (error) {
          // If profile not found, create basic user from auth data
          final basicUser = UserModel(
            pubkeyHex: npub,
            name: npub.substring(0, 8), // Fallback name
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

  /// Get user profile by npub
  Future<Result<UserModel>> getUserProfile(String npub) async {
    try {
      // Validate npub
      final validation = _validationService.validateNpub(npub);
      if (validation.isError) {
        return Result.error(validation.error ?? 'Invalid npub');
      }

      // Check cache first
      if (_userCache.containsKey(npub)) {
        return Result.success(_userCache[npub]!);
      }

      // Use NostrDataService for actual profile fetching
      return await _nostrDataService.fetchUserProfile(npub);
    } catch (e) {
      return Result.error('Failed to get user profile: $e');
    }
  }

  /// Update current user profile
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

      // Validate inputs
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

      // Create updated user
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

      // Use NostrDataService for actual profile update to relays (like legacy DataService)
      debugPrint('[UserRepository] Updating profile via NostrDataService...');
      final updateResult = await _nostrDataService.updateUserProfile(updatedUser);

      if (updateResult.isError) {
        debugPrint('[UserRepository] Profile update failed: ${updateResult.error}');
        return Result.error(updateResult.error!);
      }

      // Update cache after successful relay update
      _userCache[updatedUser.pubkeyHex] = updatedUser;

      // Emit updated user
      _currentUserController.add(updatedUser);

      debugPrint('[UserRepository] Profile updated successfully and broadcasted to relays');
      return Result.success(updatedUser);
    } catch (e) {
      debugPrint('[UserRepository] Profile update error: $e');
      return Result.error('Failed to update profile: $e');
    }
  }

  /// Update user profile (alias for updateProfile)
  Future<Result<UserModel>> updateUserProfile(UserModel user) async {
    try {
      // Use NostrDataService for actual profile update
      return await _nostrDataService.updateUserProfile(user);
    } catch (e) {
      return Result.error('Failed to update user profile: $e');
    }
  }

  /// Follow a user - implements real NIP-02 follow event publishing using legacy logic
  Future<Result<void>> followUser(String npub) async {
    try {
      final validation = _validationService.validateNpub(npub);
      if (validation.isError) {
        return Result.error(validation.error ?? 'Invalid npub');
      }

      debugPrint('[UserRepository] Following user: $npub');

      // Get private key (like legacy DataService)
      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        return const Result.error('Private key not found');
      }

      final privateKey = privateKeyResult.data!;

      // Get current user npub (like legacy DataService)
      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user npub not found');
      }

      final currentUserNpub = currentUserResult.data!;

      // Convert current user npub to hex format (like legacy DataService)
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

      // Convert target npub to hex format (like legacy DataService)
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

      // Get current following list (like legacy DataService.getFollowingList)
      final followingResult = await _nostrDataService.getFollowingList(currentUserHex);

      List<String> currentFollowing = [];
      if (followingResult.isSuccess) {
        currentFollowing = followingResult.data ?? [];
      }

      // Check if already following
      if (currentFollowing.contains(targetUserHex)) {
        debugPrint('[UserRepository] Already following $targetUserHex');
        return const Result.success(null);
      }

      // Add to following list
      currentFollowing.add(targetUserHex);

      if (currentFollowing.isEmpty) {
        debugPrint('[UserRepository] Cannot publish an empty follow list. Follow operation aborted.');
        return const Result.error('Cannot publish empty follow list');
      }

      // Publish using NostrDataService (which handles relay broadcast)
      return await _nostrDataService.publishFollowEvent(
        followingHexList: currentFollowing,
        privateKey: privateKey,
      );
    } catch (e) {
      return Result.error('Failed to follow user: $e');
    }
  }

  /// Unfollow a user - implements real NIP-02 follow event publishing using legacy logic
  Future<Result<void>> unfollowUser(String npub) async {
    try {
      debugPrint('=== [UserRepository] UNFOLLOW OPERATION START ===');

      final validation = _validationService.validateNpub(npub);
      if (validation.isError) {
        debugPrint('[UserRepository] UNFOLLOW FAILED: Invalid npub - ${validation.error}');
        return Result.error(validation.error ?? 'Invalid npub');
      }

      debugPrint('[UserRepository] Unfollowing user: $npub');

      // Get private key (like legacy DataService)
      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        return const Result.error('Private key not found');
      }

      final privateKey = privateKeyResult.data!;

      // Get current user npub (like legacy DataService)
      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Current user npub not found');
      }

      final currentUserNpub = currentUserResult.data!;

      // Convert current user npub to hex format (like legacy DataService)
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

      // Convert target npub to hex format (like legacy DataService)
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

      // Get current following list (like legacy DataService.getFollowingList)
      debugPrint('[UserRepository] Getting following list for: $currentUserHex');
      final followingResult = await _nostrDataService.getFollowingList(currentUserHex);

      List<String> currentFollowing = [];
      if (followingResult.isSuccess) {
        currentFollowing = followingResult.data ?? [];
        debugPrint('[UserRepository] Current following list has ${currentFollowing.length} users');
        debugPrint('[UserRepository] Following list: ${currentFollowing.take(5).toList()}...'); // Show first 5
      } else {
        debugPrint('[UserRepository] Failed to get following list: ${followingResult.error}');
      }

      // Check if currently following
      final isCurrentlyFollowing = currentFollowing.contains(targetUserHex);
      debugPrint('[UserRepository] Is currently following $targetUserHex: $isCurrentlyFollowing');

      if (!isCurrentlyFollowing) {
        debugPrint('[UserRepository] Not following $targetUserHex - returning success (idempotent)');
        return const Result.success(null);
      }

      // Remove from following list
      final beforeRemove = currentFollowing.length;
      currentFollowing.remove(targetUserHex);
      final afterRemove = currentFollowing.length;

      debugPrint('[UserRepository] Removed $targetUserHex from following list');
      debugPrint('[UserRepository] Following count: $beforeRemove → $afterRemove');

      // IMPORTANT: Unlike follow operation, unfollow CAN result in empty list
      // Empty list means "following nobody" which is a valid state
      debugPrint('[UserRepository] Publishing kind 3 unfollow event with ${currentFollowing.length} remaining following');

      // Publish using NostrDataService (which handles relay broadcast)
      final publishResult = await _nostrDataService.publishFollowEvent(
        followingHexList: currentFollowing,
        privateKey: privateKey,
      );

      debugPrint('[UserRepository] Publish result: ${publishResult.isSuccess ? 'SUCCESS' : 'FAILED - ${publishResult.error}'}');
      return publishResult;
    } catch (e) {
      return Result.error('Failed to unfollow user: $e');
    }
  }

  /// Check if current user is following target user
  Future<Result<bool>> isFollowing(String targetNpub) async {
    try {
      // Get current user npub
      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        return const Result.error('Not authenticated');
      }

      final currentUserNpub = currentUserResult.data!;

      // Convert current user npub to hex format
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

      // Convert target npub to hex format
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

      // Get current following list
      final followingResult = await _nostrDataService.getFollowingList(currentUserHex);

      return followingResult.fold(
        (followingList) => Result.success(followingList.contains(targetUserHex)),
        (error) => const Result.success(false), // Not following if can't get list
      );
    } catch (e) {
      return Result.error('Failed to check follow status: $e');
    }
  }

  /// Get following list for current user
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

  /// Get following list for a specific user
  Future<Result<List<UserModel>>> getFollowingListForUser(String userNpub) async {
    try {
      debugPrint('[UserRepository] Getting following list for user: $userNpub');

      // Convert userNpub to hex format
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

      // Get following hex list from NostrDataService
      final followingResult = await _nostrDataService.getFollowingList(userHex);

      if (followingResult.isError) {
        debugPrint('[UserRepository] Error getting following hex list: ${followingResult.error}');
        return Result.error(followingResult.error!);
      }

      final followingHexList = followingResult.data ?? [];
      debugPrint('[UserRepository] Got ${followingHexList.length} following hex keys');

      // Convert hex keys to basic UserModel objects immediately (fast)
      final List<UserModel> followingUsers = [];

      for (final hexKey in followingHexList) {
        try {
          // Convert hex to npub
          String npub = hexKey;
          try {
            final npubResult = _authService.hexToNpub(hexKey);
            if (npubResult != null) {
              npub = npubResult;
            }
          } catch (e) {
            debugPrint('[UserRepository] Error converting hex to npub for $hexKey: $e');
          }

          // Create basic user model immediately - don't wait for profile fetch
          final basicUser = UserModel(
            pubkeyHex: npub,
            name: npub.substring(0, 8), // Show npub prefix as name initially
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
          // Continue with next user
        }
      }

      debugPrint('[UserRepository] Successfully created ${followingUsers.length} basic following users');

      // Update stream for current user's following list
      if (userNpub == (await getCurrentUser()).data?.pubkeyHex) {
        _followingListController.add(followingUsers);
      }

      return Result.success(followingUsers);
    } catch (e) {
      debugPrint('[UserRepository] Error getting following list for user: $e');
      return Result.error('Failed to get following list: $e');
    }
  }

  /// Get following list with full profiles (slower but complete data)
  Future<Result<List<UserModel>>> getFollowingListWithProfiles(String userNpub) async {
    try {
      // First get the basic list quickly
      final basicListResult = await getFollowingListForUser(userNpub);
      if (basicListResult.isError) {
        return basicListResult;
      }

      final basicUsers = basicListResult.data!;
      final List<UserModel> enrichedUsers = [];

      // Then enrich with profile data
      for (final basicUser in basicUsers) {
        try {
          final userProfileResult = await getUserProfile(basicUser.pubkeyHex);
          if (userProfileResult.isSuccess) {
            enrichedUsers.add(userProfileResult.data!);
          } else {
            // Keep basic user if profile fetch fails
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

  /// Search users by npub
  Future<Result<List<UserModel>>> searchUsers(String query) async {
    try {
      final trimmedQuery = query.trim();

      // If query is empty, return cached users
      if (trimmedQuery.isEmpty) {
        final cachedUsers = _userCache.values.toList();
        // Sort by name for better user experience
        cachedUsers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Result.success(cachedUsers);
      }

      final searchResults = <UserModel>[];

      // Check if query looks like an npub
      final npubValidation = _validationService.validateNpub(trimmedQuery);
      if (npubValidation.isSuccess) {
        // Query is a valid npub, try to fetch that specific user
        debugPrint('[UserRepository] Searching for user by npub: $trimmedQuery');

        final userProfileResult = await getUserProfile(trimmedQuery);
        if (userProfileResult.isSuccess) {
          searchResults.add(userProfileResult.data!);
          debugPrint('[UserRepository] Found user by npub: ${userProfileResult.data!.name}');
        } else {
          debugPrint('[UserRepository] Could not fetch user profile for npub: ${userProfileResult.error}');
        }
      } else {
        // Query is not a valid npub, return empty results
        debugPrint('[UserRepository] Query is not a valid npub: $trimmedQuery');
        return Result.success([]);
      }

      return Result.success(searchResults);
    } catch (e) {
      debugPrint('[UserRepository] Search users error: $e');
      return Result.error('Failed to search users: $e');
    }
  }

  /// Get user from cache
  UserModel? getCachedUser(String npub) {
    return _userCache[npub];
  }

  /// Cache user data
  void cacheUser(UserModel user) {
    _userCache[user.pubkeyHex] = user;
  }

  /// Clear user cache
  void clearCache() {
    _userCache.clear();
  }

  /// Dispose repository
  void dispose() {
    _currentUserController.close();
    _followingListController.close();
    _userCache.clear();
  }
}
