import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/isar_database_service.dart';
import '../../../models/event_model.dart';
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
  final IsarDatabaseService _db;
  final String userPubkeyHex;
  StreamSubscription<EventModel?>? _profileSubscription;

  ProfileInfoBloc({
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
    required this.userPubkeyHex,
    IsarDatabaseService? db,
  })  : _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        _db = db ?? IsarDatabaseService.instance,
        super(const ProfileInfoInitial()) {
    on<ProfileInfoInitialized>(_onProfileInfoInitialized);
    on<ProfileInfoUserUpdated>(_onProfileInfoUserUpdated);
    on<ProfileInfoFollowToggled>(_onProfileInfoFollowToggled);
    on<ProfileInfoMuteToggled>(_onProfileInfoMuteToggled);
    on<_InternalStateUpdate>(_onInternalStateUpdate);
  }

  Future<void> _onProfileInfoInitialized(
    ProfileInfoInitialized event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is ProfileInfoLoaded) {
      _loadFollowerCountsInBackground(currentState);
      return;
    }

    final targetHex =
        _authService.npubToHex(event.userPubkeyHex) ?? event.userPubkeyHex;
    final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
    final currentUserHex = pubkeyResult.data ?? '';
    final isCurrentUser =
        currentUserHex.isNotEmpty && currentUserHex == targetHex;

    emit(ProfileInfoLoaded(
      user: event.user ?? {},
      currentUserHex: currentUserHex,
      isLoadingCounts: true,
    ));

    _watchProfile(targetHex);
    _syncProfileInBackground(targetHex);

    if (!isCurrentUser && currentUserHex.isNotEmpty) {
      _loadFollowStateInBackground(targetHex, currentUserHex);
    }

    _loadFollowerCountsInBackground(state as ProfileInfoLoaded);
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
    _profileSubscription = _db.watchProfile(pubkey).listen((event) {
      if (isClosed || event == null) return;
      final currentState = state;
      if (currentState is! ProfileInfoLoaded) return;

      final profile = _parseProfileContent(event.content);
      if (profile == null) return;

      final updatedUser = Map<String, dynamic>.from(currentState.user);
      updatedUser['name'] = profile['name'] ?? updatedUser['name'];
      updatedUser['profileImage'] =
          profile['profileImage'] ?? updatedUser['profileImage'];
      updatedUser['banner'] = profile['banner'] ?? updatedUser['banner'];
      updatedUser['about'] = profile['about'] ?? updatedUser['about'];
      updatedUser['nip05'] = profile['nip05'] ?? updatedUser['nip05'];
      updatedUser['website'] = profile['website'] ?? updatedUser['website'];

      add(_InternalStateUpdate(currentState.copyWith(user: updatedUser)));
    });
  }

  Map<String, String>? _parseProfileContent(String content) {
    if (content.isEmpty) return null;
    try {
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final result = <String, String>{};
      parsed.forEach((key, value) {
        result[key == 'picture' ? 'profileImage' : key] =
            value?.toString() ?? '';
      });
      return result;
    } catch (_) {
      return null;
    }
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

        await _syncService.syncFollowingList(targetHex);
        if (isClosed) return;
        _refreshDoesUserFollowMeInBackground(targetHex, currentUserHex);
      } catch (_) {}
    });
  }

  void _loadFollowerCountsInBackground(ProfileInfoLoaded currentState) {
    final pubkeyHex = currentState.user['pubkeyHex'] as String? ??
        currentState.user['pubkey'] as String? ??
        userPubkeyHex;
    if (pubkeyHex.isEmpty) return;

    Future.microtask(() async {
      if (isClosed) return;
      try {
        var follows = await _followingRepository.getFollowingList(pubkeyHex);

        if (isClosed) return;
        if (state is ProfileInfoLoaded) {
          add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
            followingCount: follows?.length ?? 0,
            isLoadingCounts: false,
          )));
        }

        await _syncService.syncFollowingList(pubkeyHex);
        follows = await _followingRepository.getFollowingList(pubkeyHex);

        if (isClosed) return;
        if (state is ProfileInfoLoaded) {
          add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
            followingCount: follows?.length ?? 0,
          )));
        }

        final followerCount =
            await _profileRepository.getFollowerCount(pubkeyHex);
        if (isClosed) return;
        if (state is ProfileInfoLoaded) {
          add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
            followerCount: followerCount,
          )));
        }
      } catch (_) {
        if (isClosed) return;
        if (state is ProfileInfoLoaded) {
          add(_InternalStateUpdate((state as ProfileInfoLoaded).copyWith(
            followingCount: 0,
            followerCount: 0,
            isLoadingCounts: false,
          )));
        }
      }
    });
  }

  void _refreshDoesUserFollowMeInBackground(
      String targetHex, String currentUserHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        final targetFollows =
            await _followingRepository.getFollowingList(targetHex);
        final doesUserFollowMe = targetFollows
                ?.any((f) => f.toLowerCase() == currentUserHex.toLowerCase()) ??
            false;

        if (isClosed) return;
        final currentState = state;
        if (currentState is ProfileInfoLoaded) {
          add(_InternalStateUpdate(
              currentState.copyWith(doesUserFollowMe: doesUserFollowMe)));
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
      _loadFollowerCountsInBackground(updated);
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
    } catch (e) {}
  }

  Future<void> _onProfileInfoMuteToggled(
    ProfileInfoMuteToggled event,
    Emitter<ProfileInfoState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ProfileInfoLoaded) return;

    final currentIsMuted = currentState.isMuted ?? false;

    try {
      final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
      if (pubkeyResult.isError || pubkeyResult.data == null) return;
      final currentUserHex = pubkeyResult.data!;

      final targetHex = _authService.npubToHex(userPubkeyHex) ?? userPubkeyHex;

      final currentMutes =
          await _followingRepository.getMuteList(currentUserHex) ?? [];

      List<String> updatedMutes;
      if (currentIsMuted) {
        updatedMutes = currentMutes.where((p) => p != targetHex).toList();
        emit(currentState.copyWith(isMuted: false));
      } else {
        updatedMutes = [...currentMutes, targetHex];
        emit(currentState.copyWith(isMuted: true));
      }

      await _syncService.publishMute(mutedPubkeys: updatedMutes);
    } catch (e) {}
  }

  @override
  Future<void> close() {
    _profileSubscription?.cancel();
    return super.close();
  }
}
