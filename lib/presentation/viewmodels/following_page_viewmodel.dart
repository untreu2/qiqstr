import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../data/repositories/user_repository.dart';
import '../../models/user_model.dart';
import '../../data/services/user_batch_fetcher.dart';

class FollowingPageViewModel extends BaseViewModel {
  final UserRepository _userRepository;

  FollowingPageViewModel({
    required UserRepository userRepository,
  }) : _userRepository = userRepository;

  UIState<List<UserModel>> _followingState = const InitialState();
  UIState<List<UserModel>> get followingState => _followingState;

  bool _isLoadingProfiles = false;
  bool get isLoadingProfiles => _isLoadingProfiles;

  Future<void> loadFollowingList(String userNpub) async {
    await executeOperation('loadFollowingList', () async {
      _followingState = const LoadingState();
      safeNotifyListeners();

      final result = await _userRepository.getFollowingListForUser(userNpub);

      await result.fold(
        (users) async {
          if (users.isEmpty) {
            _followingState = const EmptyState('No following found');
            safeNotifyListeners();
            return;
          }

          await _loadUserProfilesOptimized(users);
        },
        (error) {
          _followingState = ErrorState(error);
          safeNotifyListeners();
        },
      );
    }, showLoading: false);
  }

  Future<void> _loadUserProfilesOptimized(List<UserModel> users) async {
    if (_isLoadingProfiles) return;

    _isLoadingProfiles = true;
    safeNotifyListeners();

    try {
      final npubsToLoad = <String>[];
      final enrichedUsers = <UserModel>[];

      for (final user in users) {
        final npub = user.npub;
        final cachedUser = await _userRepository.getCachedUser(npub);
        
        if (cachedUser != null && 
            cachedUser.name.isNotEmpty && 
            cachedUser.name != cachedUser.npub.substring(0, 8)) {
          enrichedUsers.add(cachedUser);
        } else {
          enrichedUsers.add(user);
          npubsToLoad.add(npub);
        }
      }

      if (enrichedUsers.isNotEmpty) {
        _followingState = LoadedState(enrichedUsers);
        safeNotifyListeners();
      }

      if (npubsToLoad.isNotEmpty) {
        final results = await _userRepository.getUserProfiles(
          npubsToLoad,
          priority: FetchPriority.urgent,
        );

        final finalUsers = List<UserModel>.from(enrichedUsers);
        
        for (final entry in results.entries) {
          final npub = entry.key;
          entry.value.fold(
            (user) {
              final index = finalUsers.indexWhere((u) => u.npub == npub);
              if (index != -1) {
                finalUsers[index] = user;
              }
            },
            (error) {
              debugPrint('[FollowingPageViewModel] Failed to load user $npub: $error');
            },
          );
        }

        _followingState = LoadedState(finalUsers);
        safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('[FollowingPageViewModel] Error loading user profiles: $e');
    } finally {
      _isLoadingProfiles = false;
      safeNotifyListeners();
    }
  }

  List<UserModel> get followingUsers {
    if (_followingState is LoadedState<List<UserModel>>) {
      return (_followingState as LoadedState<List<UserModel>>).data;
    }
    return [];
  }

  @override
  void onRetry() {
    if (_followingState is ErrorState) {
      safeNotifyListeners();
    }
  }
}

