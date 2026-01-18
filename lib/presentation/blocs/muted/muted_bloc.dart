import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/data_service.dart';
import '../../../data/services/mute_cache_service.dart';
import '../../../data/services/user_batch_fetcher.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'muted_event.dart';
import 'muted_state.dart';

class MutedBloc extends Bloc<MutedEvent, MutedState> {
  final UserRepository _userRepository;
  final AuthService _authService;
  final DataService _dataService;
  final MuteCacheService _muteCacheService;

  MutedBloc({
    required UserRepository userRepository,
    required AuthService authService,
    required DataService dataService,
  })  : _userRepository = userRepository,
        _authService = authService,
        _dataService = dataService,
        _muteCacheService = MuteCacheService.instance,
        super(const MutedInitial()) {
    on<MutedLoadRequested>(_onMutedLoadRequested);
    on<MutedUserUnmuted>(_onMutedUserUnmuted);
    on<MutedRefreshed>(_onMutedRefreshed);
  }

  Future<void> _onMutedLoadRequested(
    MutedLoadRequested event,
    Emitter<MutedState> emit,
  ) async {
    emit(const MutedLoading());

    final currentUserResult = await _authService.getCurrentUserNpub();
    if (currentUserResult.isError || currentUserResult.data == null) {
      emit(const MutedError('Not authenticated'));
      return;
    }

    final currentUserNpub = currentUserResult.data!;
    String currentUserHex = currentUserNpub;

    if (currentUserNpub.startsWith('npub1')) {
      final hexResult = _authService.npubToHex(currentUserNpub);
      if (hexResult != null) {
        currentUserHex = hexResult;
      }
    }

    final mutedPubkeys = await _muteCacheService.getOrFetch(currentUserHex, () async {
      final result = await _dataService.getMuteList(currentUserHex);
      return result.isSuccess ? result.data : null;
    });

    if (mutedPubkeys == null || mutedPubkeys.isEmpty) {
      emit(const MutedLoaded(mutedUsers: [], unmutingStates: {}));
      return;
    }

    final npubs = <String>[];
    for (final pubkey in mutedPubkeys) {
      String npub = pubkey;
      try {
        if (!pubkey.startsWith('npub1')) {
          npub = encodeBasicBech32(pubkey, 'npub');
        }
      } catch (e) {
        npub = pubkey;
      }
      npubs.add(npub);
    }

    final userResults = await _userRepository.getUserProfiles(npubs, priority: FetchPriority.high);

    final users = <Map<String, dynamic>>[];
    for (final entry in userResults.entries) {
      entry.value.fold(
        (user) => users.add(user),
        (error) {
          final npub = entry.key;
          final shortName = npub.length > 8 ? npub.substring(0, 8) : npub;
          users.add({
            'pubkeyHex': npub,
            'npub': npub,
            'name': shortName,
            'about': '',
            'profileImage': '',
            'banner': '',
            'website': '',
            'nip05': '',
            'lud16': '',
            'updatedAt': DateTime.now(),
            'nip05Verified': false,
            'followerCount': 0,
          });
        },
      );
    }

    emit(MutedLoaded(mutedUsers: users, unmutingStates: {}));
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

    final result = await _userRepository.unmuteUser(event.userNpub);

    result.fold(
      (_) {
        final updatedUsers = currentState.mutedUsers.where((u) {
          final npub = u['npub'] as String? ?? '';
          return npub.isNotEmpty && npub != event.userNpub;
        }).toList();
        unmutingStates.remove(event.userNpub);
        emit(MutedLoaded(mutedUsers: updatedUsers, unmutingStates: unmutingStates));
      },
      (error) {
        unmutingStates.remove(event.userNpub);
        emit(currentState.copyWith(unmutingStates: unmutingStates));
      },
    );
  }

  Future<void> _onMutedRefreshed(
    MutedRefreshed event,
    Emitter<MutedState> emit,
  ) async {
    await _onMutedLoadRequested(const MutedLoadRequested(), emit);
  }
}
