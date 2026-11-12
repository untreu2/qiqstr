import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/vertex_search_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/entities/user_profile.dart';
import 'user_search_event.dart';
import 'user_search_state.dart';

class UserSearchBloc extends Bloc<UserSearchEvent, UserSearchState> {
  final ProfileRepository _profileRepository;
  final AuthService _authService;
  final SyncService _syncService;
  final VertexSearchService _vertexSearchService;

  UserSearchBloc({
    required this._profileRepository,
    required this._authService,
    required this._syncService,
    required this._vertexSearchService,
  })  : super(const UserSearchLoaded(filteredUsers: [])) {
    on<UserSearchQueryChanged>(
      _onUserSearchQueryChanged,
      transformer: restartable(),
    );
  }

  Map<String, dynamic> _profileToMap(UserProfile profile) {
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
        if (emit.isDone) return;
        final profile = await _profileRepository.getProfile(pubkeyHex);
        if (emit.isDone) return;

        if (profile == null) {
          emit(const UserSearchLoaded(filteredUsers: [], isSearching: false));
          return;
        }

        emit(UserSearchLoaded(
          filteredUsers: [_profileToMap(profile)],
          isSearching: false,
        ));
        return;
      }

      final results = await Future.wait([
        _vertexSearchService.searchProfiles(query, limit: 20),
        _profileRepository.searchProfiles(query),
      ]);

      if (emit.isDone) return;
      final vertexProfiles = results[0];
      final localProfiles = results[1];

      final seenPubkeys = <String>{};
      final merged = <Map<String, dynamic>>[];

      for (final profile in localProfiles) {
        if (seenPubkeys.add(profile.pubkey)) {
          merged.add(_profileToMap(profile));
        }
      }

      for (final profile in vertexProfiles) {
        if (seenPubkeys.add(profile.pubkey)) {
          merged.add(_profileToMap(profile));
        }
      }

      emit(UserSearchLoaded(
        filteredUsers: merged,
        isSearching: false,
      ));
    } catch (e) {
      if (emit.isDone) return;
      emit(UserSearchError(e.toString()));
    }
  }
}
