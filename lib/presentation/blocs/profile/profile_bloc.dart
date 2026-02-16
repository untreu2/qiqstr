import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../data/services/pinned_notes_service.dart';
import '../../../data/services/rust_database_service.dart';
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
  final RustDatabaseService _db;

  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  bool _isLoadingMoreReplies = false;
  bool _isLoadingMoreLikes = false;
  bool _isLoadingMoreArticles = false;
  int _likesReactionsLimit = 0;
  int _articlesOffset = 0;
  String? _currentProfileHex;
  StreamSubscription? _profileSubscription;
  StreamSubscription<List<FeedNote>>? _notesSubscription;
  StreamSubscription<List<FeedNote>>? _repliesSubscription;
  StreamSubscription<List<FeedNote>>? _likesSubscription;
  StreamSubscription<List<String>>? _pinnedNotesSubscription;

  ProfileBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required FollowingRepository followingRepository,
    required ArticleRepository articleRepository,
    required SyncService syncService,
    required AuthService authService,
    RustDatabaseService? db,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _followingRepository = followingRepository,
        _articleRepository = articleRepository,
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
    on<ProfileRepliesLoaded>(_onProfileRepliesLoaded);
    on<ProfileLoadMoreRepliesRequested>(_onProfileLoadMoreRepliesRequested);
    on<_ProfileRepliesUpdated>(_onProfileRepliesUpdatedInternal);
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
      await Future.wait([
        _syncService.syncProfile(targetHex),
        _syncService.syncProfileNotes(targetHex, limit: _pageSize, force: true),
      ]);

      final notesFuture =
          _feedRepository.getProfileNotes(targetHex, limit: _pageSize);
      final repliesFuture =
          _feedRepository.getProfileReplies(targetHex, limit: _pageSize);
      final likesFuture =
          _feedRepository.getProfileLikes(targetHex, limit: _pageSize);

      final results =
          await Future.wait([notesFuture, repliesFuture, likesFuture]);
      final noteMaps = _feedNotesToMaps(results[0]);
      final replyMaps = _feedNotesToMaps(results[1]);
      final likeMaps = _feedNotesToMaps(results[2]);

      if (state is ProfileLoaded) {
        emit((state as ProfileLoaded).copyWith(
            notes: noteMaps, replies: replyMaps, likedNotes: likeMaps));
        final allNotes = [...noteMaps, ...replyMaps, ...likeMaps];
        if (allNotes.isNotEmpty) {
          _loadProfilesForNotes(allNotes, emit);
        }
      }

      _syncProfileReactionsInBackground(targetHex);
      _syncPinnedNotesInBackground(targetHex);
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
    _watchProfileReplies(event.pubkeyHex);
    _syncProfileNotesInBackground(event.pubkeyHex);

    add(ProfileArticlesRequested(event.pubkeyHex));
    add(ProfileLikesRequested(event.pubkeyHex));
    add(ProfilePinnedNotesRequested(event.pubkeyHex));
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
  ) {
    Future.microtask(() async {
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
          await _syncService.syncProfiles(missingPubkeys);
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

    if (currentNotes.isEmpty) {
      emit(currentState.copyWith(notes: newNoteMaps));
    } else {
      final currentIds = currentNotes
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final trulyNewNotes = newNoteMaps.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentIds.contains(noteId);
      }).toList();

      final updatedNotes = <Map<String, dynamic>>[];
      final newNoteMap = <String, Map<String, dynamic>>{};
      for (final note in newNoteMaps) {
        final id = note['id'] as String? ?? '';
        if (id.isNotEmpty) newNoteMap[id] = note;
      }

      for (final note in currentNotes) {
        final id = note['id'] as String? ?? '';
        if (newNoteMap.containsKey(id)) {
          updatedNotes.add(newNoteMap[id]!);
        } else {
          updatedNotes.add(note);
        }
      }

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

  Future<void> _onProfileRepliesLoaded(
    ProfileRepliesLoaded event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    if (event.pubkeyHex.isEmpty) return;

    _watchProfileReplies(event.pubkeyHex);
  }

  void _watchProfileReplies(String pubkeyHex) {
    _repliesSubscription?.cancel();
    _repliesSubscription =
        _feedRepository.watchProfileReplies(pubkeyHex).listen((replies) {
      if (isClosed) return;
      add(_ProfileRepliesUpdated(replies));
    });
  }

  void _onProfileRepliesUpdatedInternal(
    _ProfileRepliesUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is! ProfileLoaded) return;
    final currentState = state as ProfileLoaded;

    final newReplyMaps = _feedNotesToMaps(event.replies);
    final currentReplies = currentState.replies;

    if (currentReplies.isEmpty) {
      emit(currentState.copyWith(replies: newReplyMaps));
    } else {
      final currentIds = currentReplies
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final trulyNewReplies = newReplyMaps.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentIds.contains(noteId);
      }).toList();

      final updatedReplies = <Map<String, dynamic>>[];
      final newReplyMap = <String, Map<String, dynamic>>{};
      for (final reply in newReplyMaps) {
        final id = reply['id'] as String? ?? '';
        if (id.isNotEmpty) newReplyMap[id] = reply;
      }

      for (final reply in currentReplies) {
        final id = reply['id'] as String? ?? '';
        if (newReplyMap.containsKey(id)) {
          updatedReplies.add(newReplyMap[id]!);
        } else {
          updatedReplies.add(reply);
        }
      }

      if (trulyNewReplies.isNotEmpty) {
        updatedReplies.addAll(trulyNewReplies);
        updatedReplies.sort((a, b) {
          final aTime =
              a['repostCreatedAt'] as int? ?? a['created_at'] as int? ?? 0;
          final bTime =
              b['repostCreatedAt'] as int? ?? b['created_at'] as int? ?? 0;
          return bTime.compareTo(aTime);
        });
      }

      emit(currentState.copyWith(replies: updatedReplies));
    }

    if (newReplyMaps.isNotEmpty) {
      _loadProfilesForNotes(newReplyMaps, emit);
    }
  }

  Future<void> _onProfileLoadMoreRepliesRequested(
    ProfileLoadMoreRepliesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    if (_isLoadingMoreReplies || !currentState.canLoadMoreReplies) return;

    final currentReplies = currentState.replies;
    if (currentReplies.isEmpty) return;

    _isLoadingMoreReplies = true;
    emit(currentState.copyWith(isLoadingMoreReplies: true));

    try {
      final targetHex = currentState.currentProfileHex;

      final moreReplies = await _feedRepository.getProfileReplies(
        targetHex,
        limit: _pageSize + currentReplies.length,
      );
      final moreReplyMaps = _feedNotesToMaps(moreReplies);

      if (moreReplyMaps.length > currentReplies.length) {
        final currentIds = currentReplies
            .map((n) => n['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        final uniqueNewReplies = moreReplyMaps.where((n) {
          final noteId = n['id'] as String? ?? '';
          return noteId.isNotEmpty && !currentIds.contains(noteId);
        }).toList();

        if (uniqueNewReplies.isNotEmpty) {
          final allReplies = [...currentReplies, ...uniqueNewReplies];
          emit(currentState.copyWith(
              replies: allReplies, isLoadingMoreReplies: false));
          _loadProfilesForNotes(uniqueNewReplies, emit);
        } else {
          emit(currentState.copyWith(isLoadingMoreReplies: false));
        }
      } else {
        emit(currentState.copyWith(isLoadingMoreReplies: false));
      }
    } catch (e) {
      emit(currentState.copyWith(isLoadingMoreReplies: false));
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
      final articles = await _articleRepository.getArticlesByAuthor(
        event.pubkeyHex,
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
        .watchProfileLikes(pubkeyHex, limit: _likesReactionsLimit)
        .listen((likes) {
      if (isClosed) return;
      add(_ProfileLikesUpdated(likes));
    });
  }

  void _syncProfileReactionsInBackground(String pubkeyHex) {
    Future.microtask(() async {
      try {
        await _syncService.syncProfileReactions(pubkeyHex);
      } catch (_) {}
    });
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

      final moreLikes = await _feedRepository.getProfileLikes(
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

      final articles = await _articleRepository.getArticlesByAuthor(
        targetHex,
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

  void _reloadPinnedNotesFromIds(List<String> pinnedIds) {
    Future.microtask(() async {
      if (isClosed || state is! ProfileLoaded) return;
      final notes = await _fetchNotesByIds(pinnedIds);
      if (!isClosed) {
        add(ProfilePinnedNotesUpdated(
          pinnedNoteIds: pinnedIds,
          pinnedNotes: notes,
        ));
      }
    });
  }

  Future<List<Map<String, dynamic>>> _fetchNotesByIds(
      List<String> noteIds) async {
    final notes = <Map<String, dynamic>>[];
    for (final noteId in noteIds) {
      final event = await _db.getEventModel(noteId);
      if (event != null) {
        notes.add(event);
      }
    }
    return notes;
  }

  void _syncPinnedNotesInBackground(String pubkeyHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncPinnedNotes(pubkeyHex);
        if (isClosed || state is! ProfileLoaded) return;

        final pinnedIds = await PinnedNotesService.instance
            .fetchPinnedNoteIdsForUser(pubkeyHex);

        final currentState = state as ProfileLoaded;
        final currentIds = currentState.pinnedNoteIds;
        if (_listEquals(pinnedIds, currentIds)) return;

        final pinnedNotes = await _fetchNotesByIds(pinnedIds);

        final missingIds = pinnedIds
            .where((id) => !pinnedNotes.any((n) => n['id'] == id))
            .toList();
        if (missingIds.isNotEmpty) {
          for (final id in missingIds) {
            await _syncService.syncNote(id);
            final event = await _db.getEventModel(id);
            if (event != null) pinnedNotes.add(event);
          }
        }

        if (!isClosed) {
          add(ProfilePinnedNotesUpdated(
            pinnedNoteIds: pinnedIds,
            pinnedNotes: pinnedNotes,
          ));
        }
      } catch (_) {}
    });
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
  Future<void> close() {
    _profileSubscription?.cancel();
    _notesSubscription?.cancel();
    _repliesSubscription?.cancel();
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
