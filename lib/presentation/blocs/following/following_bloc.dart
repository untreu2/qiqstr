import 'dart:async';
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
    on<FollowingLoadRequested>(_onFollowingLoadRequested);
    on<_FollowingListUpdated>(_onFollowingListUpdated);
  }

  Future<void> _onFollowingLoadRequested(
    FollowingLoadRequested event,
    Emitter<FollowingState> emit,
  ) async {
    String? userHex;
    if (event.userNpub.startsWith('npub1')) {
      userHex = _authService.npubToHex(event.userNpub);
    } else if (event.userNpub.isNotEmpty) {
      userHex = event.userNpub;
    }

    if (userHex == null || userHex.isEmpty) {
      emit(const FollowingError('Invalid user npub'));
      return;
    }

    emit(const FollowingLoaded(followingUsers: [], loadedUsers: {}));

    _watchFollowing(userHex);
    _syncInBackground(userHex);
  }

  void _watchFollowing(String userHex) {
    _followingSubscription?.cancel();
    _followingSubscription =
        _followingRepository.watchFollowingList(userHex).listen((pubkeys) {
      if (isClosed) return;
      add(_FollowingListUpdated(pubkeys));
    });
  }

  Future<void> _onFollowingListUpdated(
    _FollowingListUpdated event,
    Emitter<FollowingState> emit,
  ) async {
    if (state is! FollowingLoaded) return;
    final currentState = state as FollowingLoaded;

    if (event.pubkeys.isEmpty) {
      emit(const FollowingLoaded(followingUsers: [], loadedUsers: {}));
      return;
    }

    final profiles = await _profileRepository.getProfiles(event.pubkeys);
    final result = _buildFollowingResult(event.pubkeys, profiles);

    final existingKeys = <String>{};
    for (final user in currentState.followingUsers) {
      existingKeys.add(user['pubkey'] as String? ?? '');
    }

    final merged = List<Map<String, dynamic>>.from(currentState.followingUsers);
    final mergedLoaded =
        Map<String, Map<String, dynamic>>.from(currentState.loadedUsers);

    for (final user in result.users) {
      final pk = user['pubkey'] as String? ?? '';
      if (!existingKeys.contains(pk)) {
        merged.add(user);
        existingKeys.add(pk);
      }
      final npub = user['npub'] as String? ?? '';
      if (npub.isNotEmpty) {
        mergedLoaded[npub] = user;
      }
    }

    emit(FollowingLoaded(
      followingUsers: merged,
      loadedUsers: mergedLoaded,
    ));
  }

  void _syncInBackground(String userHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncFollowingList(userHex);
        final pubkeys = await _followingRepository.getFollowingList(userHex);
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
      List<String> pubkeys, Map<String, dynamic> profiles) {
    final followingUsers = <Map<String, dynamic>>[];
    final loadedUsers = <String, Map<String, dynamic>>{};

    for (final pubkey in pubkeys) {
      final profile = profiles[pubkey];
      final npub = _authService.hexToNpub(pubkey) ?? pubkey;

      if (profile == null) continue;

      final userWithNpub = <String, dynamic>{
        'pubkey': pubkey,
        'pubkeyHex': pubkey,
        'npub': npub,
        'name': profile.name ?? profile.displayName,
        'display_name': profile.displayName,
        'about': profile.about ?? '',
        'picture': profile.picture ?? '',
        'profileImage': profile.picture ?? '',
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
    _followingSubscription?.cancel();
    return super.close();
  }
}

class _FollowingListUpdated extends FollowingEvent {
  final List<String> pubkeys;
  const _FollowingListUpdated(this.pubkeys);

  @override
  List<Object?> get props => [pubkeys];
}
