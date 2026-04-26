import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/encrypted_mute_service.dart';
import '../../../domain/entities/user_profile.dart';
import 'profile_info_event.dart';
import 'profile_info_state.dart';

class _InternalStateUpdate extends ProfileInfoEvent {
  final ProfileInfoLoaded newState;
  const _InternalStateUpdate(this.newState);

  @override
  List<Object?> get props => [newState];
}

class ProfileInfoBloc extends Bloc<ProfileInfoEvent, ProfileInfoState> {
  final FollowingRepository _followingRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;
  final String userPubkeyHex;
  StreamSubscription<UserProfile?>? _profileSubscription;
  Timer? _followingPollTimer;
  Timer? _followsYouPollTimer;

  ProfileInfoBloc({
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
    required this.userPubkeyHex,
  })  : _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        super(const ProfileInfoInitial()) {
    on<ProfileInfoInitialized>(_onProfileInfoInitialized);
    on<ProfileInfoUserUpdated>(_onProfileInfoUserUpdated);
    on<ProfileInfoFollowToggled>(_onProfileInfoFollowToggled);
    on<ProfileInfoMuteToggled>(_onProfileInfoMuteToggled);
    on<ProfileInfoReportSubmitted>(_onProfileInfoReportSubmitted);
    on<_InternalStateUpdate>(_onInternalStateUpdate);
  }

  Future<void> _onProfileInfoInitialized(
    ProfileInfoInitialized event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is ProfileInfoLoaded) {
      _syncCountsInBackground(currentState);
      return;
    }

    final targetHex =
        _authService.npubToHex(event.userPubkeyHex) ?? event.userPubkeyHex;
    final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
    final currentUserHex = pubkeyResult.data ?? '';
    final isCurrentUser =
        currentUserHex.isNotEmpty && currentUserHex == targetHex;

    int followingCount = 0;
    try {
      final localFollows = await _followingRepository.getFollowing(targetHex);
      if (localFollows != null) followingCount = localFollows.length;
    } catch (_) {}

    emit(ProfileInfoLoaded(
      user: event.user ?? {},
      currentUserHex: currentUserHex,
      isLoadingCounts: true,
      followingCount: followingCount,
    ));

    if (followingCount == 0) {
      _startFollowingPoll(targetHex);
    }

    _watchProfile(targetHex);
    _syncProfileInBackground(targetHex);

    if (!isCurrentUser && currentUserHex.isNotEmpty) {
      _loadFollowStateInBackground(targetHex, currentUserHex);
    }

    _syncCountsInBackground(state as ProfileInfoLoaded);
  }

  void _startFollowingPoll(String pubkeyHex) {
    _followingPollTimer?.cancel();
    int attempts = 0;
    _followingPollTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      attempts++;
      if (isClosed || attempts > 15) {
        timer.cancel();
        return;
      }
      try {
        final follows = await _followingRepository.getFollowing(pubkeyHex);
        if (follows != null && follows.isNotEmpty) {
          timer.cancel();
          if (!isClosed && state is ProfileInfoLoaded) {
            add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
              followingCount: follows.length,
            )));
          }
        }
      } catch (_) {}
    });
  }

  void _syncProfileInBackground(String pubkey) {
    _syncService.syncProfile(pubkey).catchError((_) {});
  }

  void _watchProfile(String pubkey) {
    _profileSubscription?.cancel();
    _profileSubscription =
        _profileRepository.watchProfile(pubkey).listen((profile) {
      if (isClosed || profile == null) return;
      final currentState = state;
      if (currentState is! ProfileInfoLoaded) return;

      final updatedUser = Map<String, dynamic>.from(currentState.user);
      updatedUser['name'] = profile.name ?? updatedUser['name'];
      updatedUser['picture'] =
          profile.picture ?? updatedUser['picture'];
      updatedUser['banner'] = profile.banner ?? updatedUser['banner'];
      updatedUser['about'] = profile.about ?? updatedUser['about'];
      updatedUser['nip05'] = profile.nip05 ?? updatedUser['nip05'];
      updatedUser['website'] = profile.website ?? updatedUser['website'];

      add(_InternalStateUpdate(currentState.copyWith(user: updatedUser)));
    });
  }

  void _loadFollowStateInBackground(String targetHex, String currentUserHex) {
    Future.wait([
      _followingRepository.isFollowing(currentUserHex, targetHex),
      _followingRepository.isMuted(currentUserHex, targetHex),
    ]).then((results) {
      if (isClosed) return;
      final currentState = state;
      if (currentState is ProfileInfoLoaded) {
        add(_InternalStateUpdate(currentState.copyWith(
          isFollowing: results[0],
          isMuted: results[1],
        )));
      }
      _refreshDoesUserFollowMeInBackground(targetHex, currentUserHex);
    }).catchError((_) {});
  }

  void _syncCountsInBackground(ProfileInfoLoaded currentState) {
    final rawPubkey = currentState.user['pubkey'] as String? ?? '';
    final pubkeyHex = rawPubkey.isNotEmpty ? rawPubkey : userPubkeyHex;
    if (pubkeyHex.isEmpty) {
      if (!isClosed && state is ProfileInfoLoaded) {
        add(_InternalStateUpdate(
            (state as ProfileInfoLoaded).copyWith(isLoadingCounts: false)));
      }
      return;
    }

    Future.wait([
      _profileRepository.getFollowerCount(pubkeyHex),
      _syncService.syncFollowingList(pubkeyHex).then((_) =>
          _followingRepository.getFollowing(pubkeyHex)),
    ]).then((results) {
      if (isClosed || state is! ProfileInfoLoaded) return;
      final followerCount = results[0] as int;
      final follows = results[1] as List<String>?;
      add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
        followerCount: followerCount,
        followingCount: follows?.length ?? 0,
        isLoadingCounts: false,
      )));
    }).catchError((_) {
      if (isClosed || state is! ProfileInfoLoaded) return;
      add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
        isLoadingCounts: false,
      )));
    });

    _calculateFollowScoreInBackground(pubkeyHex, currentState.currentUserHex);
  }

  void _calculateFollowScoreInBackground(
      String targetHex, String? currentUserHex) {
    if (currentUserHex == null || currentUserHex.isEmpty) return;
    if (currentUserHex.toLowerCase() == targetHex.toLowerCase()) return;

    _followingRepository.getFollowScore(currentUserHex, targetHex).then((result) {
      if (result != null && !isClosed && state is ProfileInfoLoaded) {
        add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
          followScoreCount: result.count,
          followScoreAvatars: result.avatarUrls,
        )));
      }
    }).catchError((_) {});
  }

  void _refreshDoesUserFollowMeInBackground(
      String targetHex, String currentUserHex) {
    _followingRepository.getFollowing(targetHex).then((targetFollows) {
      if (isClosed) return;
      if (targetFollows != null && targetFollows.isNotEmpty) {
        final doesUserFollowMe = targetFollows
            .any((f) => f.toLowerCase() == currentUserHex.toLowerCase());
        final currentState = state;
        if (currentState is ProfileInfoLoaded) {
          add(_InternalStateUpdate(
              currentState.copyWith(doesUserFollowMe: doesUserFollowMe)));
        }
      } else {
        _startFollowsYouPoll(targetHex, currentUserHex);
      }
    }).catchError((_) {
      _startFollowsYouPoll(targetHex, currentUserHex);
    });
  }

  void _startFollowsYouPoll(String targetHex, String currentUserHex) {
    _followsYouPollTimer?.cancel();
    int attempts = 0;
    _followsYouPollTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      attempts++;
      if (isClosed || attempts > 15) {
        timer.cancel();
        return;
      }
      try {
        final targetFollows =
            await _followingRepository.getFollowing(targetHex);
        if (targetFollows != null && targetFollows.isNotEmpty) {
          timer.cancel();
          final doesUserFollowMe = targetFollows
              .any((f) => f.toLowerCase() == currentUserHex.toLowerCase());
          if (!isClosed && state is ProfileInfoLoaded) {
            add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
              doesUserFollowMe: doesUserFollowMe,
            )));
          }
        }
      } catch (_) {}
    });
  }

  void _onInternalStateUpdate(
    _InternalStateUpdate event,
    Emitter<ProfileInfoState> emit,
  ) {
    emit(event.newState);
  }

  Future<void> _onProfileInfoUserUpdated(
    ProfileInfoUserUpdated event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is ProfileInfoLoaded) {
      final updated = currentState.copyWith(user: event.user);
      emit(updated);
    }
  }

  Future<void> _onProfileInfoFollowToggled(
    ProfileInfoFollowToggled event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileInfoLoaded) return;

    final currentIsFollowing = currentState.isFollowing ?? false;

    try {
      final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
      if (pubkeyResult.isError || pubkeyResult.data == null) return;
      final currentUserHex = pubkeyResult.data!;

      final targetHex = _authService.npubToHex(userPubkeyHex) ?? userPubkeyHex;

      final currentFollows =
          await _followingRepository.getFollowing(currentUserHex) ?? [];

      List<String> updatedFollows;
      if (currentIsFollowing) {
        updatedFollows = currentFollows.where((p) => p != targetHex).toList();
        emit(currentState.copyWith(isFollowing: false));
      } else {
        updatedFollows = [...currentFollows, targetHex];
        emit(currentState.copyWith(isFollowing: true));
      }

      await _syncService.publishFollow(followingPubkeys: updatedFollows);
    } catch (_) {}
  }

  Future<void> _onProfileInfoMuteToggled(
    ProfileInfoMuteToggled event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileInfoLoaded) return;

    final currentIsMuted = currentState.isMuted ?? false;

    try {
      final targetHex = _authService.npubToHex(userPubkeyHex) ?? userPubkeyHex;
      final muteService = EncryptedMuteService.instance;

      if (currentIsMuted) {
        muteService.removeMutedPubkey(targetHex);
        emit(currentState.copyWith(isMuted: false));
      } else {
        muteService.addMutedPubkey(targetHex);
        emit(currentState.copyWith(isMuted: true));
      }

      await _syncService.publishMute(
        mutedPubkeys: muteService.mutedPubkeys,
        mutedWords: muteService.mutedWords,
      );
    } catch (_) {}
  }

  Future<void> _onProfileInfoReportSubmitted(
    ProfileInfoReportSubmitted event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileInfoLoaded) return;

    try {
      final targetHex = _authService.npubToHex(userPubkeyHex) ?? userPubkeyHex;

      await _syncService.publishReport(
        reportedPubkey: targetHex,
        reportType: event.reportType,
        content: event.content,
      );
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _followingPollTimer?.cancel();
    _followsYouPollTimer?.cancel();
    _profileSubscription?.cancel();
    return super.close();
  }
}
