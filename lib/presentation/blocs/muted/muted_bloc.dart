import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import 'muted_event.dart';
import 'muted_state.dart';

class MutedBloc extends Bloc<MutedEvent, MutedState> {
  final FollowingRepository _followingRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;

  MutedBloc({
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        super(const MutedInitial()) {
    on<MutedLoadRequested>(_onMutedLoadRequested);
    on<MutedUserUnmuted>(_onMutedUserUnmuted);
    on<MutedRefreshed>(_onMutedRefreshed);
  }

  Future<void> _onMutedLoadRequested(
    MutedLoadRequested event,
    Emitter<MutedState> emit,
  ) async {
    final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
    if (pubkeyResult.isError || pubkeyResult.data == null) {
      emit(const MutedError('Not authenticated'));
      return;
    }
    final currentUserHex = pubkeyResult.data!;

    final cachedMutedPubkeys =
        await _followingRepository.getMuteList(currentUserHex);

    if (cachedMutedPubkeys != null && cachedMutedPubkeys.isNotEmpty) {
      final cachedProfiles =
          await _profileRepository.getProfiles(cachedMutedPubkeys);
      final users = _buildMutedUsers(cachedMutedPubkeys, cachedProfiles);
      emit(MutedLoaded(mutedUsers: users, unmutingStates: {}));
      _syncMutedInBackground(currentUserHex, emit);
    } else {
      emit(const MutedLoading());
      await _syncService.syncMuteList(currentUserHex);
      final freshMutedPubkeys =
          await _followingRepository.getMuteList(currentUserHex);

      if (freshMutedPubkeys == null || freshMutedPubkeys.isEmpty) {
        emit(const MutedLoaded(mutedUsers: [], unmutingStates: {}));
        return;
      }

      await _syncService.syncProfiles(freshMutedPubkeys);
      final freshProfiles =
          await _profileRepository.getProfiles(freshMutedPubkeys);
      final users = _buildMutedUsers(freshMutedPubkeys, freshProfiles);
      emit(MutedLoaded(mutedUsers: users, unmutingStates: {}));
    }
  }

  List<Map<String, dynamic>> _buildMutedUsers(
      List<String> pubkeys, Map<String, dynamic> profiles) {
    final users = <Map<String, dynamic>>[];
    for (final pubkey in pubkeys) {
      final profile = profiles[pubkey];
      final npub = _authService.hexToNpub(pubkey) ?? pubkey;

      if (profile != null) {
        users.add({
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
        });
      } else {
        final shortName = npub.length > 8 ? npub.substring(0, 8) : npub;
        users.add({
          'pubkey': pubkey,
          'npub': npub,
          'name': shortName,
          'about': '',
          'picture': '',
          'banner': '',
          'website': '',
          'nip05': '',
          'lud16': '',
        });
      }
    }
    return users;
  }

  void _syncMutedInBackground(String currentUserHex, Emitter<MutedState> emit) {
    _syncService.syncMuteList(currentUserHex).then((_) async {
      final freshMutedPubkeys =
          await _followingRepository.getMuteList(currentUserHex);
      if (freshMutedPubkeys == null || freshMutedPubkeys.isEmpty) return;

      await _syncService.syncProfiles(freshMutedPubkeys);
      final freshProfiles =
          await _profileRepository.getProfiles(freshMutedPubkeys);
      final users = _buildMutedUsers(freshMutedPubkeys, freshProfiles);

      if (state is MutedLoaded) {
        final currentState = state as MutedLoaded;
        emit(MutedLoaded(
            mutedUsers: users, unmutingStates: currentState.unmutingStates));
      }
    });
  }

  Future<void> _onMutedUserUnmuted(
    MutedUserUnmuted event,
    Emitter<MutedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MutedLoaded) return;

    final unmutingStates = Map<String, bool>.from(currentState.unmutingStates);
    if (unmutingStates[event.userNpub] == true) return;

    unmutingStates[event.userNpub] = true;
    emit(currentState.copyWith(unmutingStates: unmutingStates));

    try {
      final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
      if (pubkeyResult.isError || pubkeyResult.data == null) {
        unmutingStates.remove(event.userNpub);
        emit(currentState.copyWith(unmutingStates: unmutingStates));
        return;
      }
      final currentUserHex = pubkeyResult.data!;

      final targetHex =
          _authService.npubToHex(event.userNpub) ?? event.userNpub;

      final currentMuteList =
          await _followingRepository.getMuteList(currentUserHex);
      final updatedMuteList =
          (currentMuteList ?? []).where((p) => p != targetHex).toList();

      await _syncService.publishMute(mutedPubkeys: updatedMuteList);

      final updatedUsers = currentState.mutedUsers.where((u) {
        final npub = u['npub'] as String? ?? '';
        final pubkey = u['pubkey'] as String? ?? '';
        return npub != event.userNpub && pubkey != event.userNpub;
      }).toList();

      unmutingStates.remove(event.userNpub);
      emit(MutedLoaded(
          mutedUsers: updatedUsers, unmutingStates: unmutingStates));
    } catch (e) {
      unmutingStates.remove(event.userNpub);
      emit(currentState.copyWith(unmutingStates: unmutingStates));
    }
  }

  Future<void> _onMutedRefreshed(
    MutedRefreshed event,
    Emitter<MutedState> emit,
  ) async {
    await _onMutedLoadRequested(const MutedLoadRequested(), emit);
  }
}
