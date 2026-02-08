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
    final userHex = _authService.npubToHex(event.userNpub);
    if (userHex == null) {
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

    if (event.pubkeys.isEmpty) {
      emit(const FollowingLoaded(followingUsers: [], loadedUsers: {}));
      return;
    }

    final profiles = await _profileRepository.getProfiles(event.pubkeys);
    final result = _buildFollowingResult(event.pubkeys, profiles);

    emit(FollowingLoaded(
      followingUsers: result.users,
      loadedUsers: result.loadedUsers,
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

      if (profile != null) {
        final userWithNpub = <String, dynamic>{
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
      } else {
        final shortName = npub.length > 8 ? npub.substring(0, 8) : npub;
        final fallbackUser = {
          'pubkey': pubkey,
          'npub': npub,
          'name': shortName,
          'about': '',
          'picture': '',
        };
        followingUsers.add(fallbackUser);
        loadedUsers[npub] = fallbackUser;
      }
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
