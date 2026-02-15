import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../data/services/encrypted_mute_service.dart';
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
  final RustDatabaseService _db;
  final String userPubkeyHex;
  StreamSubscription<Map<String, dynamic>?>? _profileSubscription;
  Timer? _followingPollTimer;
  Timer? _followsYouPollTimer;

  ProfileInfoBloc({
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
    required this.userPubkeyHex,
    RustDatabaseService? db,
  })  : _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        _db = db ?? RustDatabaseService.instance,
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
      final localFollows =
          await _followingRepository.getFollowingList(targetHex);
      if (localFollows != null) followingCount = localFollows.length;
    } catch (_) {}

    emit(ProfileInfoLoaded(
      user: event.user ?? {},
      currentUserHex: currentUserHex,
      isLoadingCounts: false,
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
        final follows = await _followingRepository.getFollowingList(pubkeyHex);
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
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncProfile(pubkey);
      } catch (_) {}
    });
  }

  void _watchProfile(String pubkey) {
    _profileSubscription?.cancel();
    _profileSubscription = _db.watchProfile(pubkey).listen((profileData) {
      if (isClosed || profileData == null) return;
      final currentState = state;
      if (currentState is! ProfileInfoLoaded) return;

      final updatedUser = Map<String, dynamic>.from(currentState.user);
      updatedUser['name'] = profileData['name'] ?? updatedUser['name'];
      updatedUser['profileImage'] =
          profileData['picture'] ?? updatedUser['profileImage'];
      updatedUser['banner'] = profileData['banner'] ?? updatedUser['banner'];
      updatedUser['about'] = profileData['about'] ?? updatedUser['about'];
      updatedUser['nip05'] = profileData['nip05'] ?? updatedUser['nip05'];
      updatedUser['website'] = profileData['website'] ?? updatedUser['website'];

      add(_InternalStateUpdate(currentState.copyWith(user: updatedUser)));
    });
  }

  void _loadFollowStateInBackground(String targetHex, String currentUserHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        final isFollowing =
            await _followingRepository.isFollowing(currentUserHex, targetHex);
        final isMuted =
            await _followingRepository.isMuted(currentUserHex, targetHex);

        if (isClosed) return;
        final currentState = state;
        if (currentState is ProfileInfoLoaded) {
          add(_InternalStateUpdate(currentState.copyWith(
            isFollowing: isFollowing,
            isMuted: isMuted,
          )));
        }

        _refreshDoesUserFollowMeInBackground(targetHex, currentUserHex);
      } catch (_) {}
    });
  }

  void _syncCountsInBackground(ProfileInfoLoaded currentState) {
    final pubkeyHex = currentState.user['pubkeyHex'] as String? ??
        currentState.user['pubkey'] as String? ??
        userPubkeyHex;
    if (pubkeyHex.isEmpty) return;

    Future.microtask(() async {
      if (isClosed) return;
      try {
        final count = await _profileRepository.getFollowerCount(pubkeyHex);
        if (!isClosed && state is ProfileInfoLoaded) {
          add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
            followerCount: count,
          )));
        }
      } catch (_) {}
    });

    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncFollowingList(pubkeyHex);
        if (isClosed) return;
        final follows = await _followingRepository.getFollowingList(pubkeyHex);
        if (!isClosed && state is ProfileInfoLoaded) {
          add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
            followingCount: follows?.length ?? 0,
          )));
        }
      } catch (_) {}
    });

    _calculateFollowScoreInBackground(pubkeyHex, currentState.currentUserHex);
  }

  void _calculateFollowScoreInBackground(
      String targetHex, String? currentUserHex) {
    if (currentUserHex == null || currentUserHex.isEmpty) return;
    if (currentUserHex.toLowerCase() == targetHex.toLowerCase()) return;

    Future.microtask(() async {
      if (isClosed) return;
      try {
        final result = await _followingRepository.calculateFollowScore(
            currentUserHex, targetHex);
        if (result != null && !isClosed && state is ProfileInfoLoaded) {
          add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
            followScoreCount: result.count,
            followScoreAvatars: result.avatarUrls,
          )));
        }
      } catch (_) {}
    });
  }

  void _refreshDoesUserFollowMeInBackground(
      String targetHex, String currentUserHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        final targetFollows =
            await _followingRepository.getFollowingList(targetHex);
        if (targetFollows != null && targetFollows.isNotEmpty) {
          final doesUserFollowMe = targetFollows
              .any((f) => f.toLowerCase() == currentUserHex.toLowerCase());

          if (isClosed) return;
          final currentState = state;
          if (currentState is ProfileInfoLoaded) {
            add(_InternalStateUpdate(
                currentState.copyWith(doesUserFollowMe: doesUserFollowMe)));
          }
        } else {
          _startFollowsYouPoll(targetHex, currentUserHex);
        }
      } catch (_) {
        _startFollowsYouPoll(targetHex, currentUserHex);
      }
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
            await _followingRepository.getFollowingList(targetHex);
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
          await _followingRepository.getFollowingList(currentUserHex) ?? [];

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
