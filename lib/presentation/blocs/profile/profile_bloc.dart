import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../domain/entities/feed_note.dart';
import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final FeedRepository _feedRepository;
  final ProfileRepository _profileRepository;
  final FollowingRepository _followingRepository;
  final SyncService _syncService;
  final AuthService _authService;
  final RustDatabaseService _db;

  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  String? _currentProfileHex;
  StreamSubscription? _profileSubscription;
  StreamSubscription<List<FeedNote>>? _notesSubscription;

  ProfileBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required FollowingRepository followingRepository,
    required SyncService syncService,
    required AuthService authService,
    RustDatabaseService? db,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _followingRepository = followingRepository,
        _syncService = syncService,
        _authService = authService,
        _db = db ?? RustDatabaseService.instance,
        super(const ProfileInitial()) {
    on<ProfileLoadRequested>(_onProfileLoaded);
    on<ProfileRefreshed>(_onProfileRefreshed);
    on<ProfileFollowToggled>(_onProfileFollowToggled);
    on<ProfileEditRequested>(_onProfileEditRequested);
    on<ProfileFollowingListRequested>(_onProfileFollowingListRequested);
    on<ProfileFollowersListRequested>(_onProfileFollowersListRequested);
    on<ProfileNotesLoaded>(_onProfileNotesLoaded);
    on<ProfileLoadMoreNotesRequested>(_onProfileLoadMoreNotesRequested);
    on<ProfileUserUpdated>(_onProfileUserUpdated);
    on<ProfileUserNotePublished>(_onProfileUserNotePublished);
    on<ProfileProfilesLoaded>(_onProfileProfilesLoaded);
    on<_ProfileNotesUpdated>(_onProfileNotesUpdatedInternal);
    on<ProfileSyncCompleted>(_onProfileSyncCompleted);
  }

  void _onProfileProfilesLoaded(
    ProfileProfilesLoaded event,
    Emitter<ProfileState> emit,
  ) {
    if (state is ProfileLoaded) {
      final currentState = state as ProfileLoaded;
      final updatedProfiles =
          Map<String, Map<String, dynamic>>.from(currentState.profiles);
      updatedProfiles.addAll(event.profiles);
      emit(currentState.copyWith(profiles: updatedProfiles));
    }
  }

  Future<void> _onProfileLoaded(
    ProfileLoadRequested event,
    Emitter<ProfileState> emit,
  ) async {
    try {
      final currentUserHex = _authService.currentUserPubkeyHex ?? '';
      final targetHex =
          _authService.npubToHex(event.pubkeyHex) ?? event.pubkeyHex;

      final cachedProfile = await _profileRepository.getProfile(targetHex);

      final isCurrentUser =
          currentUserHex.isNotEmpty && currentUserHex == targetHex;

      if (cachedProfile != null) {
        final userMap = cachedProfile.toMap();
        userMap['pubkeyHex'] = targetHex;

        bool isFollowing = false;
        if (!isCurrentUser && currentUserHex.isNotEmpty) {
          isFollowing =
              await _followingRepository.isFollowing(currentUserHex, targetHex);
        }

        emit(ProfileLoaded(
          user: userMap,
          isFollowing: isFollowing,
          isCurrentUser: isCurrentUser,
          profiles: {targetHex: userMap},
          notes: const [],
          currentProfileHex: targetHex,
          currentUserHex: currentUserHex,
          isSyncing: true,
        ));

        add(ProfileNotesLoaded(targetHex));
        _watchProfile(targetHex);
        _syncProfileInBackground(targetHex, emit);
      } else {
        final placeholderUser = <String, dynamic>{
          'pubkeyHex': targetHex,
          'name': targetHex.length > 8 ? targetHex.substring(0, 8) : targetHex,
          'about': '',
          'profileImage': '',
          'banner': '',
          'website': '',
          'nip05': '',
          'lud16': '',
        };

        emit(ProfileLoaded(
          user: placeholderUser,
          isFollowing: false,
          isCurrentUser: isCurrentUser,
          profiles: {targetHex: placeholderUser},
          notes: const [],
          currentProfileHex: targetHex,
          currentUserHex: currentUserHex,
          isSyncing: true,
        ));

        add(ProfileNotesLoaded(targetHex));
        _watchProfile(targetHex);
        _syncProfileInBackground(targetHex, emit);
      }
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  void _watchProfile(String pubkey) {
    _profileSubscription?.cancel();
    _profileSubscription = _db.watchProfile(pubkey).listen((profileData) {
      if (profileData == null || isClosed) return;

      try {
        final userMap = <String, dynamic>{};
        profileData.forEach((key, value) {
          userMap[key == 'picture' ? 'profileImage' : key] =
              value?.toString() ?? '';
        });
        userMap['pubkeyHex'] = pubkey;
        add(ProfileUserUpdated(userMap));
      } catch (_) {}
    });
  }


  void _syncProfileInBackground(String targetHex, Emitter<ProfileState> emit) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncProfile(targetHex);
        if (isClosed) return;
        final freshProfile = await _profileRepository.getProfile(targetHex);
        if (freshProfile != null && !isClosed && state is ProfileLoaded) {
          final userMap = freshProfile.toMap();
          userMap['pubkeyHex'] = targetHex;
          add(ProfileUserUpdated(userMap));
        }
      } catch (_) {}
      if (!isClosed) {
        add(const ProfileSyncCompleted());
      }
    });
  }

  Future<void> _onProfileRefreshed(
    ProfileRefreshed event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    final targetHex = currentState.currentProfileHex;

    if (targetHex.isEmpty) return;

    try {
      await _syncService.syncProfile(targetHex);

      final notes =
          await _feedRepository.getProfileNotes(targetHex, limit: _pageSize);
      final noteMaps = _feedNotesToMaps(notes);

      if (state is ProfileLoaded) {
        emit((state as ProfileLoaded).copyWith(notes: noteMaps));
        if (noteMaps.isNotEmpty) {
          _loadProfilesForNotes(noteMaps, emit);
        }
      }
    } catch (_) {}
  }

  Future<void> _onProfileFollowToggled(
    ProfileFollowToggled event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    if (currentState.isCurrentUser) return;

    final wasFollowing = currentState.isFollowing;
    emit(currentState.copyWith(isFollowing: !wasFollowing));

    try {
      final targetHex = currentState.currentProfileHex;
      final currentUserHex = currentState.currentUserHex;

      if (wasFollowing) {
        await _followingRepository.unfollow(currentUserHex, targetHex);
        final updatedFollows =
            await _followingRepository.getFollowingList(currentUserHex);
        if (updatedFollows != null) {
          await _syncService.publishFollow(followingPubkeys: updatedFollows);
        }
      } else {
        await _followingRepository.follow(currentUserHex, targetHex);
        final updatedFollows =
            await _followingRepository.getFollowingList(currentUserHex);
        if (updatedFollows != null) {
          await _syncService.publishFollow(followingPubkeys: updatedFollows);
        }
      }
    } catch (e) {
      emit(currentState.copyWith(isFollowing: wasFollowing));
      emit(ProfileError(
          'Failed to ${wasFollowing ? 'unfollow' : 'follow'} user'));
    }
  }

  void _onProfileEditRequested(
    ProfileEditRequested event,
    Emitter<ProfileState> emit,
  ) {}

  Future<void> _onProfileFollowingListRequested(
    ProfileFollowingListRequested event,
    Emitter<ProfileState> emit,
  ) async {
    try {
      final currentUserHex = _authService.currentUserPubkeyHex;
      if (currentUserHex == null) {
        emit(const ProfileError('Not authenticated'));
        return;
      }

      final followingPubkeys =
          await _followingRepository.getFollowingList(currentUserHex);
      if (followingPubkeys == null || followingPubkeys.isEmpty) {
        emit(const ProfileFollowingListLoaded([]));
        return;
      }

      await _syncService.syncProfiles(followingPubkeys);
      final profiles = await _profileRepository.getProfiles(followingPubkeys);

      final users = <Map<String, dynamic>>[];
      for (final pubkey in followingPubkeys) {
        final profile = profiles[pubkey];
        if (profile != null) {
          final userMap = profile.toMap();
          userMap['pubkeyHex'] = pubkey;
          users.add(userMap);
        } else {
          users.add({
            'pubkeyHex': pubkey,
            'pubkey': pubkey,
            'name': pubkey.substring(0, 8)
          });
        }
      }

      emit(ProfileFollowingListLoaded(users));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onProfileFollowersListRequested(
    ProfileFollowersListRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(const ProfileError('Followers list is not available'));
  }

  Future<void> _onProfileNotesLoaded(
    ProfileNotesLoaded event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    if (event.pubkeyHex.isEmpty) {
      emit(const ProfileError('Pubkey cannot be empty'));
      return;
    }

    _currentProfileHex = event.pubkeyHex;

    _watchProfileNotes(event.pubkeyHex);
    _syncProfileNotesInBackground(event.pubkeyHex);
  }

  void _syncProfileNotesInBackground(String pubkeyHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncProfileNotes(pubkeyHex,
            limit: _pageSize, force: true);

        if (isClosed || state is! ProfileLoaded) return;
        final currentState = state as ProfileLoaded;

        final authorIds = currentState.notes
            .map((n) {
              final pubkey = n['pubkey'] as String? ?? '';
              final reposter = n['repostedBy'] as String? ?? '';
              return [pubkey, reposter];
            })
            .expand((ids) => ids)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        if (authorIds.isNotEmpty) {
          await _syncService.syncProfiles(authorIds);
        }

        await InteractionService.instance.refreshAllActive();
      } catch (_) {}
      if (!isClosed) {
        add(const ProfileSyncCompleted());
      }
    });
  }

  void _onProfileSyncCompleted(
    ProfileSyncCompleted event,
    Emitter<ProfileState> emit,
  ) {
    if (state is ProfileLoaded) {
      final currentState = state as ProfileLoaded;
      emit(currentState.copyWith(isSyncing: false));
    }
  }

  Future<void> _onProfileUserNotePublished(
    ProfileUserNotePublished event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    final noteAuthor = event.note['pubkey'] as String? ?? '';

    if (_currentProfileHex == null || noteAuthor != _currentProfileHex) return;

    final noteId = event.note['id'] as String?;
    if (noteId == null) return;

    final existingIds =
        currentState.notes.map((n) => n['id'] as String? ?? '').toSet();
    if (existingIds.contains(noteId)) return;

    final tags = event.note['tags'] as List<dynamic>? ?? [];
    bool isReply = false;
    for (final tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
        if (tag.length >= 4 && (tag[3] == 'root' || tag[3] == 'reply')) {
          isReply = true;
          break;
        }
      }
    }
    if (isReply) return;

    final updatedNotes = [event.note, ...currentState.notes];
    updatedNotes.sort((a, b) {
      final aTime =
          a['repostCreatedAt'] as int? ?? a['created_at'] as int? ?? 0;
      final bTime =
          b['repostCreatedAt'] as int? ?? b['created_at'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });

    emit(currentState.copyWith(notes: updatedNotes));
  }

  Future<void> _onProfileLoadMoreNotesRequested(
    ProfileLoadMoreNotesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    if (_isLoadingMore || !currentState.canLoadMore) return;

    final currentNotes = currentState.notes;
    if (currentNotes.isEmpty) return;

    _isLoadingMore = true;
    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final targetHex = currentState.currentProfileHex;

      final moreNotes = await _feedRepository.getProfileNotes(
        targetHex,
        limit: _pageSize + currentNotes.length,
      );
      final moreNoteMaps = _feedNotesToMaps(moreNotes);

      if (moreNoteMaps.length > currentNotes.length) {
        final currentIds = currentNotes
            .map((n) => n['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        final uniqueNewNotes = moreNoteMaps.where((n) {
          final noteId = n['id'] as String? ?? '';
          return noteId.isNotEmpty && !currentIds.contains(noteId);
        }).toList();

        if (uniqueNewNotes.isNotEmpty) {
          final allNotes = [...currentNotes, ...uniqueNewNotes];
          emit(currentState.copyWith(notes: allNotes, isLoadingMore: false));
          _loadProfilesForNotes(uniqueNewNotes, emit);
        } else {
          emit(currentState.copyWith(isLoadingMore: false));
        }
      } else {
        emit(currentState.copyWith(isLoadingMore: false));
      }
    } catch (e) {
      emit(currentState.copyWith(isLoadingMore: false));
    }

    _isLoadingMore = false;
  }

  void _onProfileUserUpdated(
    ProfileUserUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is ProfileLoaded) {
      final currentState = state as ProfileLoaded;
      final updatedProfiles =
          Map<String, Map<String, dynamic>>.from(currentState.profiles);
      final pubkeyHex = event.user['pubkeyHex'] as String? ??
          event.user['pubkey'] as String? ??
          '';
      if (pubkeyHex.isNotEmpty) {
        updatedProfiles[pubkeyHex] = event.user;
        emit(currentState.copyWith(profiles: updatedProfiles));
      }
    }
  }

  void _loadProfilesForNotes(
    List<Map<String, dynamic>> notes,
    Emitter<ProfileState> emit,
  ) {
    Future.microtask(() async {
      if (isClosed || state is! ProfileLoaded) return;

      final authorIds = notes
          .map((n) => n['pubkey'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (authorIds.isEmpty) return;

      try {
        final profiles = await _profileRepository.getProfiles(authorIds);

        if (isClosed || state is! ProfileLoaded) return;
        final currentState = state as ProfileLoaded;

        final updatedProfiles =
            Map<String, Map<String, dynamic>>.from(currentState.profiles);

        for (final entry in profiles.entries) {
          updatedProfiles[entry.key] = entry.value.toMap();
        }

        if (!isClosed && state is ProfileLoaded) {
          add(ProfileProfilesLoaded(updatedProfiles));
        }
      } catch (_) {}
    });
  }

  List<Map<String, dynamic>> _feedNotesToMaps(List<FeedNote> notes) {
    return notes.map((note) => note.toMap()).toList();
  }

  void _watchProfileNotes(String pubkeyHex) {
    _notesSubscription?.cancel();
    _notesSubscription =
        _feedRepository.watchProfileNotes(pubkeyHex).listen((notes) {
      if (isClosed) return;
      add(_ProfileNotesUpdated(notes));
    });
  }

  void _onProfileNotesUpdatedInternal(
    _ProfileNotesUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;

    final newNoteMaps = _feedNotesToMaps(event.notes);
    final currentNotes = currentState.notes;

    // Merge: keep all current notes and add any new ones from DB
    // This preserves load-more results while adding fresh data
    if (currentNotes.isEmpty) {
      emit(currentState.copyWith(notes: newNoteMaps));
    } else {
      final currentIds = currentNotes
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      // Find truly new notes not in current list
      final trulyNewNotes = newNoteMaps.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentIds.contains(noteId);
      }).toList();

      // Update existing notes with fresh data and add new ones
      final updatedNotes = <Map<String, dynamic>>[];
      final newNoteMap = <String, Map<String, dynamic>>{};
      for (final note in newNoteMaps) {
        final id = note['id'] as String? ?? '';
        if (id.isNotEmpty) newNoteMap[id] = note;
      }

      // Update existing notes with fresh interaction counts etc.
      for (final note in currentNotes) {
        final id = note['id'] as String? ?? '';
        if (newNoteMap.containsKey(id)) {
          updatedNotes.add(newNoteMap[id]!);
        } else {
          updatedNotes.add(note);
        }
      }

      // Add truly new notes at appropriate positions (sorted by time)
      if (trulyNewNotes.isNotEmpty) {
        updatedNotes.addAll(trulyNewNotes);
        updatedNotes.sort((a, b) {
          final aTime =
              a['repostCreatedAt'] as int? ?? a['created_at'] as int? ?? 0;
          final bTime =
              b['repostCreatedAt'] as int? ?? b['created_at'] as int? ?? 0;
          return bTime.compareTo(aTime);
        });
      }

      emit(currentState.copyWith(notes: updatedNotes));
    }

    if (newNoteMaps.isNotEmpty) {
      _loadProfilesForNotes(newNoteMaps, emit);
    }
  }

  @override
  Future<void> close() {
    _profileSubscription?.cancel();
    _notesSubscription?.cancel();
    return super.close();
  }
}

class _ProfileNotesUpdated extends ProfileEvent {
  final List<FeedNote> notes;
  const _ProfileNotesUpdated(this.notes);

  @override
  List<Object?> get props => [notes];
}
