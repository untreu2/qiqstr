import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../constants/suggestions.dart';
import 'suggested_follows_event.dart';
import 'suggested_follows_state.dart';

class SuggestedFollowsBloc
    extends Bloc<SuggestedFollowsEvent, SuggestedFollowsState> {
  final FollowingRepository _followingRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;

  SuggestedFollowsBloc({
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        super(const SuggestedFollowsInitial()) {
    on<SuggestedFollowsLoadRequested>(_onSuggestedFollowsLoadRequested);
    on<SuggestedFollowsUserToggled>(_onSuggestedFollowsUserToggled);
    on<SuggestedFollowsFollowSelectedRequested>(
        _onSuggestedFollowsFollowSelectedRequested);
    on<SuggestedFollowsSkipRequested>(_onSuggestedFollowsSkipRequested);
  }

  Future<void> _onSuggestedFollowsLoadRequested(
    SuggestedFollowsLoadRequested event,
    Emitter<SuggestedFollowsState> emit,
  ) async {
    emit(const SuggestedFollowsLoading());

    try {
      await _syncService.syncProfiles(suggestedUsers);
      final profiles = await _profileRepository.getProfiles(suggestedUsers);

      final List<Map<String, dynamic>> users = [];
      for (final pubkeyHex in suggestedUsers) {
        final profile = profiles[pubkeyHex];
        final npub = _authService.hexToNpub(pubkeyHex) ?? pubkeyHex;

        if (profile != null) {
          final userWithNpub = <String, dynamic>{
            'npub': npub,
            'pubkeyHex': pubkeyHex,
            'name': profile.name ?? profile.displayName ?? '',
            'about': profile.about ?? '',
            'profileImage': profile.picture ?? '',
            'picture': profile.picture ?? '',
            'nip05': profile.nip05 ?? '',
            'banner': profile.banner ?? '',
            'lud16': profile.lud16 ?? '',
            'website': profile.website ?? '',
            'updatedAt': DateTime.now(),
            'nip05Verified': false,
            'followerCount': 0,
          };
          users.add(userWithNpub);
        } else {
          final fallbackUser = {
            'pubkeyHex': pubkeyHex,
            'npub': npub,
            'name': 'Nostr User',
            'about': 'A Nostr user',
            'profileImage': '',
            'picture': '',
            'nip05': '',
            'banner': '',
            'lud16': '',
            'website': '',
            'updatedAt': DateTime.now(),
            'nip05Verified': false,
            'followerCount': 0,
          };
          users.add(fallbackUser);
        }
      }

      final selectedUsers = users
          .map((user) => user['npub'] as String? ?? '')
          .where((npub) => npub.isNotEmpty)
          .toSet();

      emit(SuggestedFollowsLoaded(
        suggestedUsers: users,
        selectedUsers: selectedUsers,
      ));
    } catch (e) {
      emit(SuggestedFollowsError('Failed to load suggested users: $e'));
    }
  }

  void _onSuggestedFollowsUserToggled(
    SuggestedFollowsUserToggled event,
    Emitter<SuggestedFollowsState> emit,
  ) {
    final currentState = state;
    if (currentState is! SuggestedFollowsLoaded) return;

    final selectedUsers = Set<String>.from(currentState.selectedUsers);
    if (selectedUsers.contains(event.npub)) {
      selectedUsers.remove(event.npub);
    } else {
      selectedUsers.add(event.npub);
    }

    emit(currentState.copyWith(selectedUsers: selectedUsers));
  }

  Future<void> _onSuggestedFollowsFollowSelectedRequested(
    SuggestedFollowsFollowSelectedRequested event,
    Emitter<SuggestedFollowsState> emit,
  ) async {
    final currentState = state;
    if (currentState is! SuggestedFollowsLoaded || currentState.isProcessing) {
      return;
    }

    emit(currentState.copyWith(isProcessing: true));

    try {
      final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
      if (pubkeyResult.isError || pubkeyResult.data == null) {
        emit(currentState.copyWith(isProcessing: false));
        return;
      }
      final currentUserHex = pubkeyResult.data!;

      final currentFollows =
          await _followingRepository.getFollowingList(currentUserHex) ?? [];

      final selectedHexes = currentState.selectedUsers
          .map((npub) => _authService.npubToHex(npub) ?? npub)
          .toList();

      final newFollows = <String>{
        currentUserHex,
        ...currentFollows,
        ...selectedHexes
      }.toList();

      await _syncService.publishFollow(followingPubkeys: newFollows);
      
      emit(currentState.copyWith(isProcessing: false, shouldNavigate: true));
    } catch (_) {
      emit(currentState.copyWith(isProcessing: false));
    }
  }

  void _onSuggestedFollowsSkipRequested(
    SuggestedFollowsSkipRequested event,
    Emitter<SuggestedFollowsState> emit,
  ) {
    final currentState = state;
    if (currentState is! SuggestedFollowsLoaded || currentState.isProcessing) {
      return;
    }

    emit(currentState.copyWith(selectedUsers: {}));
  }
}
