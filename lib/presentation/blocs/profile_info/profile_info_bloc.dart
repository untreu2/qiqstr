import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';
import 'profile_info_event.dart';
import 'profile_info_state.dart';

class ProfileInfoBloc extends Bloc<ProfileInfoEvent, ProfileInfoState> {
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final DataService _dataService;
  final String userPubkeyHex;

  StreamSubscription<Map<String, dynamic>>? _userSubscription;

  ProfileInfoBloc({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required DataService dataService,
    required this.userPubkeyHex,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        _dataService = dataService,
        super(const ProfileInfoInitial()) {
    on<ProfileInfoInitialized>(_onProfileInfoInitialized);
    on<ProfileInfoUserUpdated>(_onProfileInfoUserUpdated);
    on<ProfileInfoFollowToggled>(_onProfileInfoFollowToggled);
    on<ProfileInfoMuteToggled>(_onProfileInfoMuteToggled);
  }

  Future<void> _onProfileInfoInitialized(
    ProfileInfoInitialized event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is ProfileInfoLoaded) {
      return;
    }

    emit(const ProfileInfoLoading());

    final userResult = await _userRepository.getUserProfile(event.userPubkeyHex);
    await userResult.fold(
      (user) async {
        final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
        final currentUserNpub = currentUserNpubResult.fold((n) => n, (_) => null);

        if (currentUserNpub == null || event.userPubkeyHex == currentUserNpub) {
          emit(ProfileInfoLoaded(
            user: user,
            currentUserNpub: currentUserNpub,
          ));
          await _loadFollowerCounts(emit, user);
          return;
        }

        final followStatusResult = await _userRepository.isFollowing(event.userPubkeyHex);
        final isFollowing = followStatusResult.fold((f) => f, (_) => false);

        final muteStatusResult = await _userRepository.isMuted(event.userPubkeyHex);
        final isMuted = muteStatusResult.fold((m) => m, (_) => false);

        emit(ProfileInfoLoaded(
          user: user,
          isFollowing: isFollowing,
          isMuted: isMuted,
          currentUserNpub: currentUserNpub,
        ));

        await _loadFollowerCounts(emit, user);
        await _refreshDoesUserFollowMe(emit, user, currentUserNpub);
      },
      (error) async {
        final currentState = state;
        if (currentState is! ProfileInfoLoaded) {
          emit(ProfileInfoError(error));
        }
      },
    );

    _userSubscription?.cancel();
    _userSubscription = _userRepository.currentUserStream.listen(
      (updatedUser) {
        final pubkeyHex = updatedUser['pubkeyHex'] as String? ?? '';
        if (pubkeyHex.isNotEmpty && pubkeyHex == event.userPubkeyHex) {
          add(ProfileInfoUserUpdated(user: updatedUser));
        }
      },
      onError: (_) {
        // Silently handle error - stream error is acceptable
      },
    );
  }

  void _onProfileInfoUserUpdated(
    ProfileInfoUserUpdated event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is ProfileInfoLoaded) {
      emit(currentState.copyWith(user: event.user));
      _loadFollowerCounts(emit, event.user);
    } else if (currentState is ProfileInfoInitial || currentState is ProfileInfoLoading) {
      final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
      final currentUserNpub = currentUserNpubResult.fold((n) => n, (_) => null);

      final userPubkeyHex = event.user['pubkeyHex'] as String? ?? '';
      if (currentUserNpub == null || userPubkeyHex == currentUserNpub) {
        emit(ProfileInfoLoaded(
          user: event.user,
          currentUserNpub: currentUserNpub,
        ));
        await _loadFollowerCounts(emit, event.user);
        return;
      }

      final followStatusResult = await _userRepository.isFollowing(userPubkeyHex);
      final isFollowing = followStatusResult.fold((f) => f, (_) => false);

      final muteStatusResult = await _userRepository.isMuted(userPubkeyHex);
      final isMuted = muteStatusResult.fold((m) => m, (_) => false);

      emit(ProfileInfoLoaded(
        user: event.user,
        isFollowing: isFollowing,
        isMuted: isMuted,
        currentUserNpub: currentUserNpub,
      ));

      await _loadFollowerCounts(emit, event.user);
      await _refreshDoesUserFollowMe(emit, event.user, currentUserNpub);
    }
  }

  Future<void> _onProfileInfoFollowToggled(
    ProfileInfoFollowToggled event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileInfoLoaded) return;

    String targetNpub = userPubkeyHex;
    if (!userPubkeyHex.startsWith('npub1')) {
      final npubResult = _authRepository.hexToNpub(userPubkeyHex);
      if (npubResult != null) {
        targetNpub = npubResult;
      }
    }

    final currentIsFollowing = currentState.isFollowing ?? false;

    if (currentIsFollowing) {
      final result = await _userRepository.unfollowUser(targetNpub);
      result.fold(
        (_) {
          emit(currentState.copyWith(isFollowing: false));
        },
        (_) {},
      );
    } else {
      final result = await _userRepository.followUser(targetNpub);
      result.fold(
        (_) {
          emit(currentState.copyWith(isFollowing: true));
        },
        (_) {},
      );
    }
  }

  Future<void> _onProfileInfoMuteToggled(
    ProfileInfoMuteToggled event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileInfoLoaded) return;

    String targetNpub = userPubkeyHex;
    if (!userPubkeyHex.startsWith('npub1')) {
      final npubResult = _authRepository.hexToNpub(userPubkeyHex);
      if (npubResult != null) {
        targetNpub = npubResult;
      }
    }

    final currentIsMuted = currentState.isMuted ?? false;

    if (currentIsMuted) {
      final result = await _userRepository.unmuteUser(targetNpub);
      result.fold(
        (_) {
          emit(currentState.copyWith(isMuted: false));
        },
        (_) {},
      );
    } else {
      final result = await _userRepository.muteUser(targetNpub);
      result.fold(
        (_) {
          emit(currentState.copyWith(isMuted: true));
        },
        (_) {},
      );
    }
  }

  Future<void> _loadFollowerCounts(Emitter<ProfileInfoState> emit, Map<String, dynamic> user) async {
    final currentState = state;
    if (currentState is! ProfileInfoLoaded) return;

    try {
      final userPubkeyHex = user['pubkeyHex'] as String? ?? '';
      if (userPubkeyHex.isEmpty) return;
      
      final followingResult = await _userRepository.getFollowingListForUser(userPubkeyHex);

      await followingResult.fold(
        (followingUsers) async {
          final followerCount = await _dataService.fetchFollowerCount(userPubkeyHex);

          if (state is ProfileInfoLoaded) {
            emit((state as ProfileInfoLoaded).copyWith(
              followingCount: followingUsers.length,
              followerCount: followerCount,
              isLoadingCounts: false,
            ));

            if (followerCount > 0) {
              await _userRepository.updateUserFollowerCount(userPubkeyHex, followerCount);
            }
          }
        },
        (error) async {
          if (state is ProfileInfoLoaded) {
            emit((state as ProfileInfoLoaded).copyWith(
              followingCount: 0,
              followerCount: 0,
              isLoadingCounts: false,
            ));
          }
        },
      );
    } catch (e) {
      if (state is ProfileInfoLoaded) {
        emit((state as ProfileInfoLoaded).copyWith(
          followingCount: 0,
          followerCount: 0,
          isLoadingCounts: false,
        ));
      }
    }
  }

  Future<void> _refreshDoesUserFollowMe(
    Emitter<ProfileInfoState> emit,
    Map<String, dynamic> user,
    String? currentUserNpub,
  ) async {
    if (currentUserNpub == null || userPubkeyHex == currentUserNpub) {
      return;
    }

    try {
      final followingResult = await _userRepository.getFollowingListForUser(userPubkeyHex);
      followingResult.fold(
        (followingUsers) {
          final currentState = state;
          if (currentState is ProfileInfoLoaded) {
            final doesUserFollowMe = _checkIfUserFollowsMe(followingUsers, currentUserNpub);
            emit(currentState.copyWith(doesUserFollowMe: doesUserFollowMe));
          }
        },
        (_) {
          final currentState = state;
          if (currentState is ProfileInfoLoaded) {
            emit(currentState.copyWith(doesUserFollowMe: false));
          }
        },
      );
    } catch (e) {
      final currentState = state;
      if (currentState is ProfileInfoLoaded) {
        emit(currentState.copyWith(doesUserFollowMe: false));
      }
    }
  }

  bool _checkIfUserFollowsMe(List<Map<String, dynamic>> followingUsers, String currentUserNpub) {
    String? currentUserHex;
    try {
      if (currentUserNpub.startsWith('npub1')) {
        currentUserHex = _authRepository.npubToHex(currentUserNpub);
      } else {
        currentUserHex = currentUserNpub;
      }
    } catch (e) {
      currentUserHex = currentUserNpub;
    }

    currentUserHex ??= currentUserNpub;

    final currentUserNpubNormalized = currentUserNpub.toLowerCase();
    final currentUserHexNormalized = currentUserHex.toLowerCase();

    return followingUsers.any((user) {
      final userPubkey = user['pubkeyHex'] as String? ?? '';
      if (userPubkey.isEmpty) return false;
      
      final userPubkeyNormalized = userPubkey.toLowerCase();

      if (userPubkeyNormalized == currentUserNpubNormalized || userPubkeyNormalized == currentUserHexNormalized) {
        return true;
      }

      String? userHex;
      try {
        if (userPubkey.startsWith('npub1')) {
          userHex = _authRepository.npubToHex(userPubkey);
        } else {
          userHex = userPubkey;
        }
      } catch (e) {
        userHex = userPubkey;
      }

      userHex ??= userPubkey;

      final userHexNormalized = userHex.toLowerCase();

      return userHexNormalized == currentUserHexNormalized ||
          userHexNormalized == currentUserNpubNormalized ||
          userPubkeyNormalized == currentUserHexNormalized;
    });
  }

  @override
  Future<void> close() {
    _userSubscription?.cancel();
    return super.close();
  }
}
