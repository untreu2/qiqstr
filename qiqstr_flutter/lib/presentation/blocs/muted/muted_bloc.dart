import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/encrypted_mute_service.dart';
import 'muted_event.dart';
import 'muted_state.dart';

class MutedBloc extends Bloc<MutedEvent, MutedState> {
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;

  MutedBloc({
    required FollowingRepository followingRepository,
    required this._profileRepository,
    required this._syncService,
    required this._authService,
  }) : super(const MutedInitial()) {
    on<MutedEvent>(_onEvent, transformer: sequential());
  }

  bool _isCurrentSession(int generation, String? userHex) =>
      generation == EncryptedMuteService.instance.sessionGeneration &&
      userHex == _authService.currentUserPubkeyHex;

  Future<void> _onEvent(MutedEvent event, Emitter<MutedState> emit) async {
    final sessionGeneration = EncryptedMuteService.instance.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    try {
      switch (event) {
        case MutedLoadRequested():
          await _onMutedLoadRequested(event, emit);
        case MutedUserUnmuted():
          await _onMutedUserUnmuted(event, emit);
        case MutedWordAdded():
          await _onMutedWordAdded(event, emit);
        case MutedWordRemoved():
          await _onMutedWordRemoved(event, emit);
        case MutedRefreshed():
          await _onMutedRefreshed(event, emit);
      }
    } catch (error) {
      if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
      final currentState = state;
      emit(MutedError(error.toString()));
      if (currentState is MutedLoaded) {
        emit(currentState);
      }
    }
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

    final muteService = EncryptedMuteService.instance;

    if (muteService.isInitialized &&
        (muteService.mutedPubkeys.isNotEmpty ||
            muteService.mutedWords.isNotEmpty)) {
      final cachedProfiles = await _profileRepository.getProfiles(
        muteService.mutedPubkeys,
      );
      final users = _buildMutedUsers(muteService.mutedPubkeys, cachedProfiles);
      emit(
        MutedLoaded(
          mutedUsers: users,
          mutedWords: muteService.mutedWords,
          unmutingStates: {},
        ),
      );
      await _syncMuted(currentUserHex, emit);
    } else {
      emit(const MutedLoading());
      await _syncService.syncMuteList(currentUserHex);

      if (muteService.mutedPubkeys.isEmpty && muteService.mutedWords.isEmpty) {
        emit(
          const MutedLoaded(mutedUsers: [], mutedWords: [], unmutingStates: {}),
        );
        return;
      }

      if (muteService.mutedPubkeys.isNotEmpty) {
        await _syncService.syncProfiles(muteService.mutedPubkeys);
      }
      final freshProfiles = await _profileRepository.getProfiles(
        muteService.mutedPubkeys,
      );
      final users = _buildMutedUsers(muteService.mutedPubkeys, freshProfiles);
      emit(
        MutedLoaded(
          mutedUsers: users,
          mutedWords: muteService.mutedWords,
          unmutingStates: {},
        ),
      );
    }
  }

  List<Map<String, dynamic>> _buildMutedUsers(
    List<String> pubkeys,
    Map<String, dynamic> profiles,
  ) {
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

  Future<void> _syncMuted(
    String currentUserHex,
    Emitter<MutedState> emit,
  ) async {
    await _syncService.syncMuteList(currentUserHex);
    final muteService = EncryptedMuteService.instance;
    if (muteService.mutedPubkeys.isNotEmpty) {
      await _syncService.syncProfiles(muteService.mutedPubkeys);
    }
    final profiles = await _profileRepository.getProfiles(
      muteService.mutedPubkeys,
    );
    if (emit.isDone || state is! MutedLoaded) return;
    emit(
      (state as MutedLoaded).copyWith(
        mutedUsers: _buildMutedUsers(muteService.mutedPubkeys, profiles),
        mutedWords: muteService.mutedWords,
      ),
    );
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

    final muteService = EncryptedMuteService.instance;
    final sessionGeneration = muteService.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    final targetHex = _authService.npubToHex(event.userNpub) ?? event.userNpub;
    final wasMuted = muteService.isUserMuted(targetHex);
    try {
      final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      if (pubkeyResult.isError || pubkeyResult.data == null) {
        unmutingStates.remove(event.userNpub);
        emit(currentState.copyWith(unmutingStates: unmutingStates));
        return;
      }

      muteService.removeMutedPubkey(targetHex);

      await _syncService.publishMute(
        mutedPubkeys: muteService.mutedPubkeys,
        mutedWords: muteService.mutedWords,
      );

      if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
      final updatedUsers = currentState.mutedUsers.where((u) {
        final npub = u['npub'] as String? ?? '';
        final pubkey = u['pubkey'] as String? ?? '';
        return npub != event.userNpub && pubkey != event.userNpub;
      }).toList();

      unmutingStates.remove(event.userNpub);
      emit(
        MutedLoaded(
          mutedUsers: updatedUsers,
          mutedWords: muteService.mutedWords,
          unmutingStates: unmutingStates,
        ),
      );
    } catch (_) {
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      if (wasMuted) muteService.addMutedPubkey(targetHex);
      unmutingStates.remove(event.userNpub);
      if (!emit.isDone) {
        emit(currentState.copyWith(unmutingStates: unmutingStates));
      }
      rethrow;
    }
  }

  Future<void> _onMutedWordAdded(
    MutedWordAdded event,
    Emitter<MutedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MutedLoaded) return;

    final muteService = EncryptedMuteService.instance;
    final sessionGeneration = muteService.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    final word = event.word.trim().toLowerCase();
    if (word.isEmpty || muteService.mutedWords.contains(word)) return;
    muteService.addMutedWord(word);

    emit(currentState.copyWith(mutedWords: muteService.mutedWords));

    try {
      await _syncService.publishMute(
        mutedPubkeys: muteService.mutedPubkeys,
        mutedWords: muteService.mutedWords,
      );
    } catch (_) {
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      muteService.removeMutedWord(word);
      if (!emit.isDone) emit(currentState);
      rethrow;
    }
  }

  Future<void> _onMutedWordRemoved(
    MutedWordRemoved event,
    Emitter<MutedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MutedLoaded) return;

    final muteService = EncryptedMuteService.instance;
    final sessionGeneration = muteService.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    final word = event.word.trim().toLowerCase();
    if (!muteService.mutedWords.contains(word)) return;
    muteService.removeMutedWord(word);

    emit(currentState.copyWith(mutedWords: muteService.mutedWords));

    try {
      await _syncService.publishMute(
        mutedPubkeys: muteService.mutedPubkeys,
        mutedWords: muteService.mutedWords,
      );
    } catch (_) {
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      muteService.addMutedWord(word);
      if (!emit.isDone) emit(currentState);
      rethrow;
    }
  }

  Future<void> _onMutedRefreshed(
    MutedRefreshed event,
    Emitter<MutedState> emit,
  ) async {
    await _onMutedLoadRequested(const MutedLoadRequested(), emit);
  }
}
