import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../utils/string_optimizer.dart';
import 'user_search_event.dart';
import 'user_search_state.dart';

class UserSearchBloc extends Bloc<UserSearchEvent, UserSearchState> {
  final ProfileRepository _profileRepository;
  final AuthService _authService;
  final RustDatabaseService _db;
  final SyncService _syncService;

  UserSearchBloc({
    required ProfileRepository profileRepository,
    required AuthService authService,
    required SyncService syncService,
    RustDatabaseService? db,
  })  : _profileRepository = profileRepository,
        _authService = authService,
        _syncService = syncService,
        _db = db ?? RustDatabaseService.instance,
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
          'pubkeyHex': pubkeyHex,
          'npub': _authService.hexToNpub(pubkeyHex) ?? pubkeyHex,
          'name': profile.name ?? '',
          'about': profile.about ?? '',
          'profileImage': profile.picture ?? '',
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
          filteredNotes: const [],
          noteProfiles: const {},
          isSearching: false,
        ));
        return;
      }

      final userResultsFuture = _profileRepository.searchProfiles(query);
      final noteResultsFuture = _db.searchNotes(query, limit: 30);

      final results = await Future.wait([userResultsFuture, noteResultsFuture]);
      final userResults = results[0] as List<dynamic>;
      final noteResults = results[1] as List<dynamic>;

      final users = userResults.map((profile) {
        final pubkeyHex = profile.pubkey;
        return <String, dynamic>{
          'pubkeyHex': pubkeyHex,
          'npub': _authService.hexToNpub(pubkeyHex) ?? pubkeyHex,
          'name': profile.name ?? '',
          'about': profile.about ?? '',
          'profileImage': profile.picture ?? '',
          'banner': profile.banner ?? '',
          'website': profile.website ?? '',
          'nip05': profile.nip05 ?? '',
          'lud16': profile.lud16 ?? '',
          'updatedAt': DateTime.now(),
          'nip05Verified': false,
          'followerCount': 0,
        };
      }).toList();

      final notes = <Map<String, dynamic>>[];
      final authorPubkeys = <String>{};

      for (final event in noteResults) {
        final noteMap = _eventToNoteMap(event as Map<String, dynamic>);
        if (noteMap != null) {
          notes.add(noteMap);
          final author = noteMap['pubkey'] as String? ??
              noteMap['author'] as String? ??
              '';
          if (author.isNotEmpty) {
            authorPubkeys.add(author);
          }
        }
      }

      final noteProfiles = <String, Map<String, dynamic>>{};
      if (authorPubkeys.isNotEmpty) {
        final profiles =
            await _profileRepository.getProfiles(authorPubkeys.toList());
        for (final entry in profiles.entries) {
          final profile = entry.value;
          noteProfiles[entry.key] = {
            'pubkeyHex': entry.key,
            'npub': _authService.hexToNpub(entry.key) ?? entry.key,
            'name': profile.name ?? '',
            'about': profile.about ?? '',
            'profileImage': profile.picture ?? '',
            'banner': profile.banner ?? '',
            'website': profile.website ?? '',
            'nip05': profile.nip05 ?? '',
            'lud16': profile.lud16 ?? '',
          };
        }
      }

      emit(UserSearchLoaded(
        filteredUsers: users,
        filteredNotes: notes,
        noteProfiles: noteProfiles,
        isSearching: false,
      ));
    } catch (e) {
      emit(UserSearchError(e.toString()));
    }
  }

  Map<String, dynamic>? _eventToNoteMap(Map<String, dynamic> event) {
    try {
      final eventId = event['id'] as String? ?? '';
      final pubkey = event['pubkey'] as String? ?? '';
      final content = event['content'] as String? ?? '';
      final createdAt = event['created_at'] as int? ?? 0;
      final kind = event['kind'] as int? ?? 1;

      if (eventId.isEmpty || kind != 1) return null;

      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
      final parsedContent = stringOptimizer.parseContentOptimized(content);

      return {
        'id': eventId,
        'pubkey': pubkey,
        'author': pubkey,
        'content': content,
        'parsedContent': parsedContent,
        'timestamp': timestamp,
        'kind': kind,
        'isRepost': false,
        'isReply': false,
      };
    } catch (e) {
      return null;
    }
  }
}
