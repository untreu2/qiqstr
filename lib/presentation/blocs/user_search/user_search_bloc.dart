import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/sync/sync_service.dart';
import 'user_search_event.dart';
import 'user_search_state.dart';

class UserSearchBloc extends Bloc<UserSearchEvent, UserSearchState> {
  final ProfileRepository _profileRepository;
  final AuthService _authService;
  final SyncService _syncService;

  UserSearchBloc({
    required ProfileRepository profileRepository,
    required AuthService authService,
    required SyncService syncService,
  })  : _profileRepository = profileRepository,
        _authService = authService,
        _syncService = syncService,
        super(const UserSearchLoaded(filteredUsers: [])) {
    on<UserSearchQueryChanged>(_onUserSearchQueryChanged);
  }

  Future<void> _onUserSearchQueryChanged(
    UserSearchQueryChanged event,
    Emitter<UserSearchState> emit,
  ) async {
    final query = event.query.trim();

    if (query.isEmpty) {
      emit(const UserSearchLoaded(filteredUsers: []));
      return;
    }

    final currentState = state;
    if (currentState is UserSearchLoaded) {
      emit(currentState.copyWith(isSearching: true));
    } else {
      emit(const UserSearchLoaded(filteredUsers: [], isSearching: true));
    }

    try {
      final isNpub = query.startsWith('npub1');
      final isHex = RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(query);

      if (isNpub || isHex) {
        final pubkeyHex = isNpub ? _authService.npubToHex(query) : query;
        if (pubkeyHex == null) {
          emit(const UserSearchLoaded(filteredUsers: [], isSearching: false));
          return;
        }

        await _syncService.syncProfile(pubkeyHex);
        final profile = await _profileRepository.getProfile(pubkeyHex);

        if (profile == null) {
          emit(const UserSearchLoaded(filteredUsers: [], isSearching: false));
          return;
        }

        final user = <String, dynamic>{
          'pubkey': pubkeyHex,
          'npub': _authService.hexToNpub(pubkeyHex) ?? pubkeyHex,
          'name': profile.name ?? '',
          'about': profile.about ?? '',
          'picture': profile.picture ?? '',
          'banner': profile.banner ?? '',
          'website': profile.website ?? '',
          'nip05': profile.nip05 ?? '',
          'lud16': profile.lud16 ?? '',
          'updatedAt': DateTime.now(),
          'nip05Verified': false,
          'followerCount': 0,
        };

        emit(UserSearchLoaded(
          filteredUsers: [user],
          isSearching: false,
        ));
        return;
      }

      final userResults = await _profileRepository.searchProfiles(query);

      final users = userResults.map((profile) {
        final pubkeyHex = profile.pubkey;
        return <String, dynamic>{
          'pubkey': pubkeyHex,
          'npub': _authService.hexToNpub(pubkeyHex) ?? pubkeyHex,
          'name': profile.name ?? '',
          'about': profile.about ?? '',
          'picture': profile.picture ?? '',
          'banner': profile.banner ?? '',
          'website': profile.website ?? '',
          'nip05': profile.nip05 ?? '',
          'lud16': profile.lud16 ?? '',
          'updatedAt': DateTime.now(),
          'nip05Verified': false,
          'followerCount': 0,
        };
      }).toList();

      emit(UserSearchLoaded(
        filteredUsers: users,
        isSearching: false,
      ));
    } catch (e) {
      emit(UserSearchError(e.toString()));
    }
  }
}
