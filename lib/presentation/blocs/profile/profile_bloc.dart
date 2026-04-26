import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../data/services/pinned_notes_service.dart';
import '../../../domain/entities/feed_note.dart';
import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final FeedRepository _feedRepository;
  final ProfileRepository _profileRepository;
  final FollowingRepository _followingRepository;
  final ArticleRepository _articleRepository;
  final SyncService _syncService;
  final AuthService _authService;

  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  bool _isLoadingMoreReplies = false;
  bool _isLoadingMoreLikes = false;
  bool _isLoadingMoreArticles = false;
  int _likesReactionsLimit = 0;
  int _articlesOffset = 0;
  String? _currentProfileHex;
  StreamSubscription? _profileSubscription;
  StreamSubscription? _notesAndRepliesSubscription;
  StreamSubscription<List<FeedNote>>? _likesSubscription;
  StreamSubscription<List<String>>? _pinnedNotesSubscription;
  StreamSubscription<int>? _syncSubscription;

  ProfileBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required FollowingRepository followingRepository,
    required ArticleRepository articleRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _followingRepository = followingRepository,
        _articleRepository = articleRepository,
        _syncService = syncService,
        _authService = authService,
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
    on<ProfileRepliesLoaded>(_onProfileRepliesLoaded);
    on<ProfileLoadMoreRepliesRequested>(_onProfileLoadMoreRepliesRequested);
    on<_ProfileRepliesUpdated>(_onProfileRepliesUpdatedInternal);
    on<_ProfileNotesAndRepliesUpdated>(_onProfileNotesAndRepliesUpdated);
    on<ProfileArticlesRequested>(_onProfileArticlesRequested);
    on<ProfileLikesRequested>(_onProfileLikesRequested);
    on<_ProfileLikesUpdated>(_onProfileLikesUpdatedInternal);
    on<ProfileLoadMoreLikesRequested>(_onProfileLoadMoreLikesRequested);
    on<ProfileLoadMoreArticlesRequested>(_onProfileLoadMoreArticlesRequested);
    on<ProfilePinnedNotesRequested>(_onProfilePinnedNotesRequested);
    on<ProfilePinnedNotesUpdated>(_onProfilePinnedNotesUpdated);
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

      final isCurrentUser =
          currentUserHex.isNotEmpty && currentUserHex == targetHex;

      final profileFuture = _profileRepository.getProfile(targetHex);
      final followingFuture =
          (!isCurrentUser && currentUserHex.isNotEmpty)
              ? _followingRepository.isFollowing(currentUserHex, targetHex)
              : Future.value(false);

      final results = await Future.wait([profileFuture, followingFuture]);
      final cachedProfile = results[0] as dynamic;
      final isFollowing = results[1] as bool;

      if (cachedProfile != null) {
        final userMap = cachedProfile.toMap();
        userMap['pubkey'] = targetHex;
        userMap['npub'] = _authService.hexToNpub(targetHex) ?? targetHex;

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
          'pubkey': targetHex,
          'npub': _authService.hexToNpub(targetHex) ?? targetHex,
          'name': targetHex.length > 8 ? targetHex.substring(0, 8) : targetHex,
          'about': '',
          'picture': '',
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
    _profileSubscription =
        _profileRepository.watchProfile(pubkey).listen((profile) {
      if (profile == null || isClosed) return;
      try {
        final userMap = profile.toMap();
        userMap['pubkey'] = pubkey;
        userMap['npub'] = _authService.hexToNpub(pubkey) ?? pubkey;
        add(ProfileUserUpdated(userMap));
      } catch (_) {}
    });
  }

  void _syncProfileInBackground(String targetHex, Emitter<ProfileState> emit) {
    _syncService
        .syncProfile(targetHex)
        .timeout(const Duration(seconds: 2), onTimeout: () {})
        .then((_) async {
      if (isClosed) return;
      final freshProfile = await _profileRepository.getProfile(targetHex);
      if (freshProfile != null && !isClosed && state is ProfileLoaded) {
        final userMap = freshProfile.toMap();
        userMap['pubkey'] = targetHex;
        userMap['npub'] = _authService.hexToNpub(targetHex) ?? targetHex;
        add(ProfileUserUpdated(userMap));
      }
    }).catchError((_) {}).whenComplete(() {
      if (!isClosed) add(const ProfileSyncCompleted());
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

    _syncSubscription?.cancel();
    emit(currentState.copyWith(isSyncing: true));

    try {
      await _syncService.syncProfile(targetHex);
    } catch (_) {}

    _syncSubscription = _syncService
        .streamProfileNotesProgress(targetHex, force: true)
        .listen(
      (_) {},
      onDone: () {
        if (isClosed) return;
        add(const ProfileSyncCompleted());
      },
      onError: (_) {
        if (isClosed) return;
        add(const ProfileSyncCompleted());
      },
    );

    _syncProfileReactionsInBackground(targetHex);
    _syncPinnedNotesInBackground(targetHex);
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
            await _followingRepository.getFollowing(currentUserHex);
        if (updatedFollows != null) {
          await _syncService.publishFollow(followingPubkeys: updatedFollows);
        }
      } else {
        await _followingRepository.follow(currentUserHex, targetHex);
        final updatedFollows =
            await _followingRepository.getFollowing(currentUserHex);
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
          await _followingRepository.getFollowing(currentUserHex);
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
          userMap['pubkey'] = pubkey;
          users.add(userMap);
        } else {
          users.add({'pubkey': pubkey, 'name': pubkey.substring(0, 8)});
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
    _isLoadingMore = false;
    _isLoadingMoreReplies = false;

    _syncProfileNotesInBackground(event.pubkeyHex);

    add(ProfileArticlesRequested(event.pubkeyHex));
    add(ProfileLikesRequested(event.pubkeyHex));
    add(ProfilePinnedNotesRequested(event.pubkeyHex));
  }

  void _syncProfileNotesInBackground(String pubkeyHex) {
    _syncSubscription?.cancel();

    _watchProfileNotesAndReplies(pubkeyHex);

    _syncSubscription = _syncService
        .streamProfileNotesProgress(pubkeyHex, force: true)
        .listen(
      (_) {},
      onDone: () {
        if (isClosed) return;
        add(const ProfileSyncCompleted());
        _loadAuthorProfilesForCurrentNotes();
      },
      onError: (_) {
        if (isClosed) return;
        add(const ProfileSyncCompleted());
      },
    );
  }

  void _loadAuthorProfilesForCurrentNotes() async {
    if (isClosed || state is! ProfileLoaded) return;
    try {
      final currentState = state as ProfileLoaded;
      if (currentState.currentProfileHex != _currentProfileHex) return;

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
  }

  Future<void> _onProfileSyncCompleted(
    ProfileSyncCompleted event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;
    final targetHex = currentState.currentProfileHex;

    if (targetHex != _currentProfileHex) {
      emit(currentState.copyWith(isSyncing: false));
      return;
    }

    try {
      final results = await Future.wait([
        _feedRepository.getNotes(targetHex, limit: _pageSize),
        _feedRepository.getUserReplies(targetHex, limit: _pageSize),
      ]);
      if (state is! ProfileLoaded ||
          (state as ProfileLoaded).currentProfileHex != targetHex) {
        return;
      }

      final freshState = state as ProfileLoaded;
      final noteMaps = _feedNotesToMaps(results[0]);
      final replyMaps = _feedNotesToMaps(results[1]);

      final existingNoteIds = freshState.notes
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final newNotes = noteMaps
          .where((n) => !existingNoteIds.contains(n['id'] as String? ?? ''))
          .toList();

      final existingReplyIds = freshState.replies
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final newReplies = replyMaps
          .where((n) => !existingReplyIds.contains(n['id'] as String? ?? ''))
          .toList();

      final updatedNotes = newNotes.isEmpty
          ? freshState.notes
          : _sortByTimestamp([...freshState.notes, ...newNotes]);
      final updatedReplies = newReplies.isEmpty
          ? freshState.replies
          : _sortByTimestamp([...freshState.replies, ...newReplies]);

      emit(freshState.copyWith(
        notes: updatedNotes,
        replies: updatedReplies,
        isSyncing: false,
        canLoadMore: true,
        canLoadMoreReplies: true,
      ));

      final allNew = [...newNotes, ...newReplies];
      if (allNew.isNotEmpty) {
        _loadProfilesForNotes(allNew, emit);
      }
    } catch (_) {
      if (state is ProfileLoaded) {
        emit((state as ProfileLoaded).copyWith(isSyncing: false));
      }
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

  int? _oldestNoteTimestamp(List<Map<String, dynamic>> notes) {
    int? oldest;
    for (final n in notes) {
      final ts = n['repostCreatedAt'] as int? ?? n['created_at'] as int? ?? 0;
      if (ts > 0 && (oldest == null || ts < oldest)) {
        oldest = ts;
      }
    }
    return oldest;
  }

  List<Map<String, dynamic>> _sortByTimestamp(
      List<Map<String, dynamic>> notes) {
    final sorted = [...notes];
    sorted.sort((a, b) {
      final aTime =
          a['repostCreatedAt'] as int? ?? a['created_at'] as int? ?? 0;
      final bTime =
          b['repostCreatedAt'] as int? ?? b['created_at'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  Future<void> _onProfileLoadMoreNotesRequested(
    ProfileLoadMoreNotesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    if (_isLoadingMore || !currentState.canLoadMore) return;

    final targetHex = currentState.currentProfileHex;
    if (targetHex != _currentProfileHex) return;

    final currentNotes = currentState.notes;
    if (currentNotes.isEmpty) return;

    final until = _oldestNoteTimestamp(currentNotes);
    if (until == null) return;

    _isLoadingMore = true;
    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final moreNotes = await _feedRepository.getNotes(
        targetHex,
        limit: _pageSize,
        untilTimestamp: until - 1,
      );

      if (state is! ProfileLoaded ||
          (state as ProfileLoaded).currentProfileHex != targetHex) {
        _isLoadingMore = false;
        return;
      }

      final freshState = state as ProfileLoaded;
      final moreNoteMaps = _feedNotesToMaps(moreNotes);

      final currentIds = freshState.notes
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final uniqueNewNotes = moreNoteMaps.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentIds.contains(noteId);
      }).toList();

      if (uniqueNewNotes.isNotEmpty) {
        final allNotes =
            _sortByTimestamp([...freshState.notes, ...uniqueNewNotes]);
        emit(freshState.copyWith(notes: allNotes, isLoadingMore: false));
        _loadProfilesForNotes(uniqueNewNotes, emit);
      } else {
        emit(freshState.copyWith(
          isLoadingMore: false,
          canLoadMore: false,
        ));
      }
    } catch (e) {
      if (state is ProfileLoaded) {
        emit((state as ProfileLoaded).copyWith(isLoadingMore: false));
      }
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
      final pubkeyHex = event.user['pubkey'] as String? ??
          event.user['pubkey'] as String? ??
          '';
      if (pubkeyHex.isNotEmpty) {
        updatedProfiles[pubkeyHex] = event.user;
        if (pubkeyHex == currentState.currentProfileHex) {
          emit(currentState.copyWith(
            user: event.user,
            profiles: updatedProfiles,
          ));
        } else {
          emit(currentState.copyWith(profiles: updatedProfiles));
        }
      }
    }
  }

  void _loadProfilesForNotes(
    List<Map<String, dynamic>> notes,
    Emitter<ProfileState> emit,
  ) async {
    if (isClosed || state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    final authorIds = <String>{};
    for (final n in notes) {
      final pubkey = n['pubkey'] as String? ?? '';
      if (pubkey.isNotEmpty && !currentState.profiles.containsKey(pubkey)) {
        authorIds.add(pubkey);
      }
      final repostedBy = n['repostedBy'] as String? ?? '';
      if (repostedBy.isNotEmpty &&
          !currentState.profiles.containsKey(repostedBy)) {
        authorIds.add(repostedBy);
      }
    }

    if (authorIds.isEmpty) return;

    try {
      final profiles =
          await _profileRepository.getProfiles(authorIds.toList());
      if (isClosed) return;

      final updatedProfiles = <String, Map<String, dynamic>>{};
      final missingPubkeys = <String>[];

      for (final pubkey in authorIds) {
        final profile = profiles[pubkey];
        if (profile != null) {
          updatedProfiles[pubkey] = profile.toMap();
        } else {
          missingPubkeys.add(pubkey);
        }
      }

      if (updatedProfiles.isNotEmpty && !isClosed) {
        add(ProfileProfilesLoaded(updatedProfiles));
      }

      if (missingPubkeys.isNotEmpty) {
        try {
          await _syncService
              .syncProfiles(missingPubkeys)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
        if (isClosed) return;

        final synced = await _profileRepository.getProfiles(missingPubkeys);
        if (isClosed) return;

        final syncedProfiles = <String, Map<String, dynamic>>{};
        for (final entry in synced.entries) {
          syncedProfiles[entry.key] = entry.value.toMap();
        }

        if (syncedProfiles.isNotEmpty && !isClosed) {
          add(ProfileProfilesLoaded(syncedProfiles));
        }
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _feedNotesToMaps(List<FeedNote> notes) {
    return notes.map((note) => note.toMap()).toList();
  }

  void _watchProfileNotesAndReplies(String pubkeyHex) {
    _notesAndRepliesSubscription?.cancel();
    _notesAndRepliesSubscription = _feedRepository
        .watchProfileNotesAndReplies(pubkeyHex,
            notesLimit: 200, repliesLimit: 200)
        .listen((data) {
      if (isClosed) return;
      add(_ProfileNotesAndRepliesUpdated(data.notes, data.replies));
    });
  }

  void _onProfileNotesUpdatedInternal(
    _ProfileNotesUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;

    if (currentState.currentProfileHex != _currentProfileHex) return;

    InteractionService.instance.populateFromNotes(event.notes);

    final incomingMaps = _feedNotesToMaps(event.notes);

    if (currentState.notes.isEmpty) {
      emit(currentState.copyWith(notes: incomingMaps, canLoadMore: true));
    } else {
      final existingIds = currentState.notes
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final appendOnly = incomingMaps
          .where((n) {
            final id = n['id'] as String? ?? '';
            return id.isNotEmpty && !existingIds.contains(id);
          })
          .toList();

      if (appendOnly.isEmpty) return;

      final updated = _sortByTimestamp([...currentState.notes, ...appendOnly]);
      emit(currentState.copyWith(notes: updated, canLoadMore: true));
    }

    if (incomingMaps.isNotEmpty) {
      _loadProfilesForNotes(incomingMaps, emit);
    }
  }

  Future<void> _onProfileRepliesLoaded(
    ProfileRepliesLoaded event,
    Emitter<ProfileState> emit,
  ) async {}


  void _onProfileRepliesUpdatedInternal(
    _ProfileRepliesUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;

    if (currentState.currentProfileHex != _currentProfileHex) return;

    final incomingMaps = _feedNotesToMaps(event.replies);

    if (currentState.replies.isEmpty) {
      emit(currentState.copyWith(
          replies: incomingMaps, canLoadMoreReplies: true));
    } else {
      final existingIds = currentState.replies
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final appendOnly = incomingMaps
          .where((n) {
            final id = n['id'] as String? ?? '';
            return id.isNotEmpty && !existingIds.contains(id);
          })
          .toList();

      if (appendOnly.isEmpty) return;

      final updated =
          _sortByTimestamp([...currentState.replies, ...appendOnly]);
      emit(currentState.copyWith(
          replies: updated, canLoadMoreReplies: true));
    }

    if (incomingMaps.isNotEmpty) {
      _loadProfilesForNotes(incomingMaps, emit);
    }
  }

  void _onProfileNotesAndRepliesUpdated(
    _ProfileNotesAndRepliesUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;
    if (currentState.currentProfileHex != _currentProfileHex) return;

    var updated = currentState;

    final incomingNotes = _feedNotesToMaps(event.notes);
    if (incomingNotes.isNotEmpty) {
      InteractionService.instance.populateFromNotes(event.notes);
      if (updated.notes.isEmpty) {
        updated = updated.copyWith(notes: incomingNotes, canLoadMore: true);
      } else {
        final existingIds = updated.notes
            .map((n) => n['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        final newNotes = incomingNotes
            .where((n) => !existingIds.contains(n['id'] as String? ?? ''))
            .toList();
        if (newNotes.isNotEmpty) {
          updated = updated.copyWith(
              notes: _sortByTimestamp([...updated.notes, ...newNotes]),
              canLoadMore: true);
        }
      }
    }

    final incomingReplies = _feedNotesToMaps(event.replies);
    if (incomingReplies.isNotEmpty) {
      if (updated.replies.isEmpty) {
        updated = updated.copyWith(
            replies: incomingReplies, canLoadMoreReplies: true);
      } else {
        final existingIds = updated.replies
            .map((n) => n['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        final newReplies = incomingReplies
            .where((n) => !existingIds.contains(n['id'] as String? ?? ''))
            .toList();
        if (newReplies.isNotEmpty) {
          updated = updated.copyWith(
              replies: _sortByTimestamp([...updated.replies, ...newReplies]),
              canLoadMoreReplies: true);
        }
      }
    }

    if (updated != currentState) {
      emit(updated);
    }

    final allIncoming = [...incomingNotes, ...incomingReplies];
    if (allIncoming.isNotEmpty) {
      _loadProfilesForNotes(allIncoming, emit);
    }
  }

  Future<void> _onProfileLoadMoreRepliesRequested(
    ProfileLoadMoreRepliesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    if (_isLoadingMoreReplies || !currentState.canLoadMoreReplies) return;

    final targetHex = currentState.currentProfileHex;
    if (targetHex != _currentProfileHex) return;

    final currentReplies = currentState.replies;
    if (currentReplies.isEmpty) return;

    final until = _oldestNoteTimestamp(currentReplies);
    if (until == null) return;

    _isLoadingMoreReplies = true;
    emit(currentState.copyWith(isLoadingMoreReplies: true));

    try {
      final moreReplies = await _feedRepository.getUserReplies(
        targetHex,
        limit: _pageSize,
        untilTimestamp: until - 1,
      );

      if (state is! ProfileLoaded ||
          (state as ProfileLoaded).currentProfileHex != targetHex) {
        _isLoadingMoreReplies = false;
        return;
      }

      final freshState = state as ProfileLoaded;
      final moreReplyMaps = _feedNotesToMaps(moreReplies);

      final currentIds = freshState.replies
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final uniqueNewReplies = moreReplyMaps.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentIds.contains(noteId);
      }).toList();

      if (uniqueNewReplies.isNotEmpty) {
        final allReplies =
            _sortByTimestamp([...freshState.replies, ...uniqueNewReplies]);
        emit(freshState.copyWith(
            replies: allReplies, isLoadingMoreReplies: false));
        _loadProfilesForNotes(uniqueNewReplies, emit);
      } else {
        emit(freshState.copyWith(
          isLoadingMoreReplies: false,
          canLoadMoreReplies: false,
        ));
      }
    } catch (e) {
      if (state is ProfileLoaded) {
        emit((state as ProfileLoaded).copyWith(isLoadingMoreReplies: false));
      }
    }

    _isLoadingMoreReplies = false;
  }

  Future<void> _onProfileArticlesRequested(
    ProfileArticlesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    _articlesOffset = _pageSize;

    try {
      final articles = await _articleRepository.getArticles(
        authors: [event.pubkeyHex],
        limit: _pageSize,
      );
      if (isClosed || state is! ProfileLoaded) return;

      final articleMaps = articles.map((a) => a.toMap()).toList();
      emit((state as ProfileLoaded).copyWith(
        articles: articleMaps,
        canLoadMoreArticles: articleMaps.length >= _pageSize,
      ));
    } catch (_) {}
  }

  Future<void> _onProfileLikesRequested(
    ProfileLikesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    if (event.pubkeyHex.isEmpty) return;

    _likesReactionsLimit = _pageSize * 3;
    _watchProfileLikes(event.pubkeyHex);
    _syncProfileReactionsInBackground(event.pubkeyHex);
  }

  void _watchProfileLikes(String pubkeyHex) {
    _likesSubscription?.cancel();
    _likesSubscription = _feedRepository
        .watchLikes(pubkeyHex, limit: _likesReactionsLimit)
        .listen((likes) {
      if (isClosed) return;
      add(_ProfileLikesUpdated(likes));
    });
  }

  void _syncProfileReactionsInBackground(String pubkeyHex) {
    _syncService.syncProfileReactions(pubkeyHex).catchError((_) {});
  }

  void _onProfileLikesUpdatedInternal(
    _ProfileLikesUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;

    final newLikeMaps = _feedNotesToMaps(event.likes);

    emit(currentState.copyWith(
      likedNotes: newLikeMaps,
      canLoadMoreLikes: newLikeMaps.length >= _pageSize,
    ));

    if (newLikeMaps.isNotEmpty) {
      _loadProfilesForNotes(newLikeMaps, emit);
    }
  }

  Future<void> _onProfileLoadMoreLikesRequested(
    ProfileLoadMoreLikesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;
    if (_isLoadingMoreLikes || !currentState.canLoadMoreLikes) return;

    _isLoadingMoreLikes = true;
    emit(currentState.copyWith(isLoadingMoreLikes: true));

    try {
      final targetHex = currentState.currentProfileHex;
      _likesReactionsLimit += _pageSize * 3;

      final moreLikes = await _feedRepository.getLikes(
        targetHex,
        limit: _likesReactionsLimit,
      );
      final moreLikeMaps = _feedNotesToMaps(moreLikes);

      final currentIds = currentState.likedNotes
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final uniqueNew = moreLikeMaps.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentIds.contains(noteId);
      }).toList();

      if (isClosed || state is! ProfileLoaded) return;

      if (uniqueNew.isNotEmpty) {
        final allLikes = [
          ...(state as ProfileLoaded).likedNotes,
          ...uniqueNew,
        ];
        emit((state as ProfileLoaded).copyWith(
          likedNotes: allLikes,
          isLoadingMoreLikes: false,
          canLoadMoreLikes: true,
        ));
        _loadProfilesForNotes(uniqueNew, emit);
      } else {
        emit((state as ProfileLoaded).copyWith(
          isLoadingMoreLikes: false,
          canLoadMoreLikes: false,
        ));
      }
    } catch (_) {
      if (state is ProfileLoaded) {
        emit((state as ProfileLoaded).copyWith(isLoadingMoreLikes: false));
      }
    }

    _isLoadingMoreLikes = false;
  }

  Future<void> _onProfileLoadMoreArticlesRequested(
    ProfileLoadMoreArticlesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;
    if (_isLoadingMoreArticles || !currentState.canLoadMoreArticles) return;

    _isLoadingMoreArticles = true;
    emit(currentState.copyWith(isLoadingMoreArticles: true));

    try {
      final targetHex = currentState.currentProfileHex;
      final newLimit = _articlesOffset + _pageSize;

      final articles = await _articleRepository.getArticles(
        authors: [targetHex],
        limit: newLimit,
      );
      if (isClosed || state is! ProfileLoaded) return;

      final articleMaps = articles.map((a) => a.toMap()).toList();
      final currentIds = currentState.articles
          .map((a) => a['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final newArticles = articleMaps.where((a) {
        final id = a['id'] as String? ?? '';
        return id.isNotEmpty && !currentIds.contains(id);
      }).toList();

      _articlesOffset = newLimit;
      final hasMore = articleMaps.length >= newLimit;

      if (newArticles.isNotEmpty) {
        final allArticles = [
          ...(state as ProfileLoaded).articles,
          ...newArticles,
        ];
        emit((state as ProfileLoaded).copyWith(
          articles: allArticles,
          isLoadingMoreArticles: false,
          canLoadMoreArticles: hasMore,
        ));
      } else {
        emit((state as ProfileLoaded).copyWith(
          isLoadingMoreArticles: false,
          canLoadMoreArticles: hasMore,
        ));
      }
    } catch (_) {
      if (state is ProfileLoaded) {
        emit((state as ProfileLoaded).copyWith(isLoadingMoreArticles: false));
      }
    }

    _isLoadingMoreArticles = false;
  }

  Future<void> _onProfilePinnedNotesRequested(
    ProfilePinnedNotesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    if (event.pubkeyHex.isEmpty) return;

    final currentState = state as ProfileLoaded;
    final isCurrentUser = currentState.isCurrentUser;

    final cachedIds = await PinnedNotesService.instance
        .fetchPinnedNoteIdsForUser(event.pubkeyHex);

    if (cachedIds.isNotEmpty) {
      final cachedNotes = await _fetchNotesByIds(cachedIds);
      if (!isClosed && state is ProfileLoaded) {
        emit((state as ProfileLoaded).copyWith(
          pinnedNoteIds: cachedIds,
          pinnedNotes: cachedNotes,
        ));
        if (cachedNotes.isNotEmpty) {
          _loadProfilesForNotes(cachedNotes, emit);
        }
      }
    }

    if (isCurrentUser) {
      _watchPinnedNotes();
    }

    _syncPinnedNotesInBackground(event.pubkeyHex);
  }

  void _watchPinnedNotes() {
    _pinnedNotesSubscription?.cancel();
    _pinnedNotesSubscription =
        PinnedNotesService.instance.pinnedNoteIdsStream.listen((pinnedIds) {
      if (isClosed) return;
      _reloadPinnedNotesFromIds(pinnedIds);
    });
  }

  void _reloadPinnedNotesFromIds(List<String> pinnedIds) async {
    if (isClosed || state is! ProfileLoaded) return;
    final notes = await _fetchNotesByIds(pinnedIds);
    if (!isClosed) {
      add(ProfilePinnedNotesUpdated(
        pinnedNoteIds: pinnedIds,
        pinnedNotes: notes,
      ));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNotesByIds(
      List<String> noteIds) async {
    final results = await Future.wait(
      noteIds.map((id) => _feedRepository.getNote(id)),
    );
    return results
        .where((n) => n != null)
        .map((n) => n!.toMap())
        .toList();
  }

  void _syncPinnedNotesInBackground(String pubkeyHex) async {
    if (isClosed) return;
    try {
      await _syncService.syncPinnedNotes(pubkeyHex);
      if (isClosed || state is! ProfileLoaded) return;

      final pinnedIds = await PinnedNotesService.instance
          .fetchPinnedNoteIdsForUser(pubkeyHex);

      final currentState = state as ProfileLoaded;
      final currentIds = currentState.pinnedNoteIds;
      if (listEquals(pinnedIds, currentIds)) return;

      final pinnedNotes = await _fetchNotesByIds(pinnedIds);

      final missingIds = pinnedIds
          .where((id) => !pinnedNotes.any((n) => n['id'] == id))
          .toList();
      if (missingIds.isNotEmpty) {
        final syncResults = await Future.wait(
          missingIds.map((id) async {
            await _syncService.syncNote(id);
            return _feedRepository.getNote(id);
          }),
        );
        for (final note in syncResults) {
          if (note != null) pinnedNotes.add(note.toMap());
        }
      }

      if (!isClosed) {
        add(ProfilePinnedNotesUpdated(
          pinnedNoteIds: pinnedIds,
          pinnedNotes: pinnedNotes,
        ));
      }
    } catch (_) {}
  }

  void _onProfilePinnedNotesUpdated(
    ProfilePinnedNotesUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;

    emit(currentState.copyWith(
      pinnedNoteIds: event.pinnedNoteIds,
      pinnedNotes: event.pinnedNotes,
    ));

    if (event.pinnedNotes.isNotEmpty) {
      _loadProfilesForNotes(event.pinnedNotes, emit);
    }
  }

  @override
  @override
  Future<void> close() {
    _syncSubscription?.cancel();
    _profileSubscription?.cancel();
    _notesAndRepliesSubscription?.cancel();
    _likesSubscription?.cancel();
    _pinnedNotesSubscription?.cancel();
    return super.close();
  }
}

class _ProfileLikesUpdated extends ProfileEvent {
  final List<FeedNote> likes;
  const _ProfileLikesUpdated(this.likes);

  @override
  List<Object?> get props => [likes];
}

class _ProfileNotesUpdated extends ProfileEvent {
  final List<FeedNote> notes;
  const _ProfileNotesUpdated(this.notes);

  @override
  List<Object?> get props => [notes];
}

class _ProfileRepliesUpdated extends ProfileEvent {
  final List<FeedNote> replies;
  const _ProfileRepliesUpdated(this.replies);

  @override
  List<Object?> get props => [replies];
}

class _ProfileNotesAndRepliesUpdated extends ProfileEvent {
  final List<FeedNote> notes;
  final List<FeedNote> replies;
  const _ProfileNotesAndRepliesUpdated(this.notes, this.replies);

  @override
  List<Object?> get props => [notes, replies];
}
