import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import 'following_event.dart';
import 'following_state.dart';

class FollowingBloc extends Bloc<FollowingEvent, FollowingState> {
  final FollowingRepository _followingRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;

  StreamSubscription<List<String>>? _followingSubscription;
  int _generation = 0;

  FollowingBloc({
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        super(const FollowingInitial()) {
    on<FollowingLoadRequested>(
      _onFollowingLoadRequested,
      transformer: restartable(),
    );
    on<_FollowingListUpdated>(
      _onFollowingListUpdated,
      transformer: restartable(),
    );
  }

  Future<void> _onFollowingLoadRequested(
    FollowingLoadRequested event,
    Emitter<FollowingState> emit,
  ) async {
    final generation = ++_generation;
    String? userHex;
    if (event.userNpub.startsWith('npub1')) {
      userHex = _authService.npubToHex(event.userNpub);
    } else if (event.userNpub.isNotEmpty) {
      userHex = event.userNpub;
    }

    if (userHex == null || userHex.isEmpty) {
      await _followingSubscription?.cancel();
      _followingSubscription = null;
      if (emit.isDone) return;
      emit(const FollowingError('Invalid user npub'));
      return;
    }

    emit(const FollowingLoaded(followingUsers: [], loadedUsers: {}));

    await _followingSubscription?.cancel();
    if (isClosed || generation != _generation || emit.isDone) return;
    _watchFollowing(userHex, generation);
    _syncInBackground(userHex, generation);
  }

  void _watchFollowing(String userHex, int generation) {
    void subscribe() {
      if (isClosed || generation != _generation) return;
      _followingSubscription =
          _followingRepository.watchFollowing(userHex).listen((pubkeys) {
        if (isClosed || generation != _generation) return;
        add(_FollowingListUpdated(pubkeys, userHex, generation));
      }, onError: (_) {
        Future.delayed(const Duration(seconds: 2), subscribe);
      }, onDone: () {
        Future.delayed(const Duration(seconds: 2), subscribe);
      });
    }

    subscribe();
  }

  Future<void> _onFollowingListUpdated(
    _FollowingListUpdated event,
    Emitter<FollowingState> emit,
  ) async {
    if (event.generation != _generation || state is! FollowingLoaded) return;

    if (event.pubkeys.isEmpty) {
      emit(const FollowingLoaded(followingUsers: [], loadedUsers: {}));
      return;
    }

    final profiles = await _profileRepository.getProfiles(event.pubkeys);
    if (isClosed ||
        event.generation != _generation ||
        state is! FollowingLoaded ||
        emit.isDone) {
      return;
    }
    final currentState = state as FollowingLoaded;
    final existingByPubkey = <String, Map<String, dynamic>>{
      for (final user in currentState.followingUsers)
        if ((user['pubkey'] as String? ?? '').isNotEmpty)
          user['pubkey'] as String: user,
    };
    final result =
        _buildFollowingResult(event.pubkeys, profiles, existingByPubkey);

    emit(FollowingLoaded(
      followingUsers: result.users,
      loadedUsers: result.loadedUsers,
    ));
  }

  void _syncInBackground(String userHex, int generation) {
    Future.microtask(() async {
      if (isClosed || generation != _generation) return;
      try {
        await _syncService.syncFollowingList(userHex);
        final pubkeys = await _followingRepository.getFollowing(userHex);
        if (pubkeys != null && pubkeys.isNotEmpty) {
          await _syncService.syncProfiles(pubkeys);
        }
      } catch (_) {}
    });
  }

  ({
    List<Map<String, dynamic>> users,
    Map<String, Map<String, dynamic>> loadedUsers
  }) _buildFollowingResult(
    List<String> pubkeys,
    Map<String, dynamic> profiles,
    Map<String, Map<String, dynamic>> existingByPubkey,
  ) {
    final followingUsers = <Map<String, dynamic>>[];
    final loadedUsers = <String, Map<String, dynamic>>{};

    for (final pubkey in pubkeys) {
      final profile = profiles[pubkey];
      final npub = _authService.hexToNpub(pubkey) ?? pubkey;

      final userWithNpub = profile == null
          ? existingByPubkey[pubkey] ??
              <String, dynamic>{
                'pubkey': pubkey,
                'npub': npub,
                'name': pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey,
              }
          : <String, dynamic>{
              'pubkey': pubkey,
              'npub': npub,
              'name': profile.name ?? profile.displayName,
              'display_name': profile.displayName,
              'about': profile.about ?? '',
              'picture': profile.picture ?? '',
              'banner': profile.banner ?? '',
              'nip05': profile.nip05 ?? '',
              'lud16': profile.lud16 ?? '',
              'website': profile.website ?? '',
            };
      followingUsers.add(userWithNpub);
      loadedUsers[npub] = userWithNpub;
    }

    return (users: followingUsers, loadedUsers: loadedUsers);
  }

  @override
  Future<void> close() {
    _generation++;
    _followingSubscription?.cancel();
    return super.close();
  }
}

class _FollowingListUpdated extends FollowingEvent {
  final List<String> pubkeys;
  final String userHex;
  final int generation;
  const _FollowingListUpdated(this.pubkeys, this.userHex, this.generation);

  @override
  List<Object?> get props => [pubkeys, userHex, generation];
}
