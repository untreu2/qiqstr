import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/entities/feed_note.dart';
import '../../../data/services/follow_set_service.dart';
import '../../../data/services/interaction_service.dart';
import 'feed_event.dart' as feed_event;
import 'feed_state.dart';

class FeedBloc extends Bloc<feed_event.FeedEvent, FeedState> {
  final FeedRepository _feedRepository;
  final FollowingRepository _followingRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final FollowSetService _followSetService;

  static const int _pageSize = 50;
  String? _currentUserHex;
  StreamSubscription<List<FeedNote>>? _feedSubscription;
  int _currentLimit = 50;
  FeedSortMode _currentSortMode = FeedSortMode.latest;
  List<FeedNote> _bufferedNotes = [];
  bool _acceptNextUpdate = false;
  int _latestDisplayedTimestamp = 0;
  bool _profileLoadInProgress = false;

  FeedBloc({
    required FeedRepository feedRepository,
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required FollowSetService followSetService,
  })  : _feedRepository = feedRepository,
        _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _followSetService = followSetService,
        super(const FeedInitial()) {
    on<feed_event.FeedInitialized>(_onFeedInitialized);
    on<feed_event.FeedRefreshed>(_onFeedRefreshed);
    on<feed_event.FeedLoadMoreRequested>(
      _onFeedLoadMoreRequested,
      transformer: droppable(),
    );
    on<feed_event.FeedViewModeChanged>(_onFeedViewModeChanged);
    on<feed_event.FeedSortModeChanged>(_onFeedSortModeChanged);
    on<feed_event.FeedHashtagChanged>(_onFeedHashtagChanged);
    on<feed_event.FeedUserProfileUpdated>(_onFeedUserProfileUpdated);
    on<feed_event.FeedNoteDeleted>(_onFeedNoteDeleted);
    on<feed_event.FeedProfilesLoaded>(_onFeedProfilesLoaded);
    on<feed_event.FeedNotesUpdated>(
      _onFeedNotesUpdated,
      transformer: restartable(),
    );
    on<feed_event.FeedNewNotesAccepted>(_onFeedNewNotesAccepted);
    on<feed_event.FeedListChanged>(_onFeedListChanged);
    on<feed_event.FeedSyncCompleted>(_onFeedSyncCompleted);
  }

  Future<void> _onFeedInitialized(
    feed_event.FeedInitialized event,
    Emitter<FeedState> emit,
  ) async {
    if (event.userHex.isEmpty) return;

    if (state is FeedLoaded) {
      final current = state as FeedLoaded;
      if (current.currentUserHex == event.userHex &&
          current.hashtag == event.hashtag) {
        return;
      }
    }

    _currentUserHex = event.userHex;

    final initialProfiles = <String, Map<String, dynamic>>{};
    final cachedCurrentUser =
        await _profileRepository.getProfile(event.userHex);
    if (cachedCurrentUser != null) {
      initialProfiles[event.userHex] = cachedCurrentUser.toMap();
    }

    emit(FeedLoaded(
      notes: const [],
      profiles: initialProfiles,
      currentUserHex: event.userHex,
      hashtag: event.hashtag,
      sortMode: FeedSortMode.latest,
      viewMode: NoteViewMode.list,
      isSyncing: true,
    ));

    if (event.hashtag != null) {
      _syncHashtagInBackground(event.hashtag!, emit);
    } else {
      _syncInBackground(event.userHex, emit);
    }
  }

  void _watch(
    Stream<List<FeedNote>> Function() source,
    void Function() retry,
  ) {
    _feedSubscription?.cancel();
    _feedSubscription = source().listen(
      (notes) {
        if (!isClosed) add(feed_event.FeedNotesUpdated(notes));
      },
      onError: (_) {
        if (!isClosed) {
          Future.delayed(const Duration(seconds: 2), () {
            if (!isClosed) retry();
          });
        }
      },
      onDone: () {
        if (!isClosed) {
          Future.delayed(const Duration(seconds: 2), () {
            if (!isClosed) retry();
          });
        }
      },
    );
  }

  void _watchFeed(String userHex, {int? limit, String? sortMode}) => _watch(
        () => _feedRepository.watchFeed(
          userHex,
          limit: limit ?? _currentLimit,
          sortMode: sortMode ?? _sortModeKey(_currentSortMode),
        ),
        () => _watchFeed(userHex, limit: limit, sortMode: sortMode),
      );

  static String _sortModeKey(FeedSortMode mode) =>
      mode == FeedSortMode.mostInteracted ? 'most_interacted' : 'latest';

  void _watchHashtagFeed(String hashtag, {int? limit}) => _watch(
        () => _feedRepository.watchHashtag(hashtag,
            limit: limit ?? _currentLimit),
        () => _watchHashtagFeed(hashtag, limit: limit),
      );

  void _syncHashtagInBackground(String hashtag, Emitter<FeedState>? emit) {
    _syncService
        .syncHashtag(hashtag)
        .then((_) {
          if (isClosed) return;
          _watchHashtagFeed(hashtag);
        })
        .catchError((_) {})
        .whenComplete(() {
          if (!isClosed && state is FeedLoaded) {
            add(feed_event.FeedSyncCompleted());
          }
        });
  }

  Map<String, Map<String, dynamic>> _buildProfilesFromNotes(
    List<FeedNote> notes,
    Map<String, Map<String, dynamic>> existing,
  ) {
    final merged = Map<String, Map<String, dynamic>>.from(existing);
    for (final n in notes) {
      if (n.pubkey.isNotEmpty && !merged.containsKey(n.pubkey)) {
        if ((n.authorName?.isNotEmpty ?? false) ||
            (n.authorImage?.isNotEmpty ?? false)) {
          merged[n.pubkey] = {
            'pubkey': n.pubkey,
            'name': n.authorName ?? '',
            'picture': n.authorImage ?? '',
            'nip05': n.authorNip05 ?? '',
          };
        }
      }
      final repostedBy = n.repostedBy;
      if (repostedBy != null &&
          repostedBy.isNotEmpty &&
          !merged.containsKey(repostedBy)) {
        final noteMap = n.toMap();
        final repostedByName = noteMap['repostedByName'] as String?;
        final repostedByImage = noteMap['repostedByImage'] as String?;
        if ((repostedByName?.isNotEmpty ?? false) ||
            (repostedByImage?.isNotEmpty ?? false)) {
          merged[repostedBy] = {
            'pubkey': repostedBy,
            'name': repostedByName ?? '',
            'picture': repostedByImage ?? '',
            'nip05': '',
          };
        }
      }
    }
    return merged;
  }

  void _onFeedNotesUpdated(
    feed_event.FeedNotesUpdated event,
    Emitter<FeedState> emit,
  ) {
    FeedLoaded currentState;
    if (state is FeedLoaded) {
      currentState = state as FeedLoaded;
    } else if (state is FeedEmpty &&
        event.notes.isNotEmpty &&
        _currentUserHex != null) {
      currentState = FeedLoaded(
        notes: const [],
        profiles: const {},
        currentUserHex: _currentUserHex!,
      );
    } else {
      return;
    }

    InteractionService.instance.populateFromNotes(event.notes);

    final sortedNotes = List<FeedNote>.from(event.notes);
    final canLoadMore = sortedNotes.length >= _currentLimit;
    final seededProfiles =
        _buildProfilesFromNotes(sortedNotes, currentState.profiles);

    if (currentState.notes.isEmpty || _acceptNextUpdate) {
      _acceptNextUpdate = false;
      _bufferedNotes = [];
      _latestDisplayedTimestamp = _getLatestTimestamp(sortedNotes);
      emit(currentState.copyWith(
        notes: sortedNotes,
        profiles: seededProfiles,
        canLoadMore: canLoadMore,
        pendingNotesCount: 0,
      ));
      _loadProfilesForNotes(sortedNotes);
      _prefetchEmbeddedContent(sortedNotes);
      return;
    }

    int othersCount = 0;
    bool hasOwnNew = false;
    for (final n in sortedNotes) {
      final noteTime = n.repostCreatedAt ?? n.createdAt;
      if (noteTime > _latestDisplayedTimestamp) {
        if (n.pubkey == _currentUserHex) {
          hasOwnNew = true;
        } else {
          othersCount++;
        }
      }
    }

    if (othersCount > 0) {
      _bufferedNotes = sortedNotes;
      final displayedIds = currentState.notes.map((n) => n.id).toSet();
      final visibleNotes = sortedNotes.where((n) {
        final noteTime = n.repostCreatedAt ?? n.createdAt;
        return noteTime <= _latestDisplayedTimestamp ||
            displayedIds.contains(n.id) ||
            n.pubkey == _currentUserHex;
      }).toList();
      emit(currentState.copyWith(
        notes: visibleNotes,
        profiles: seededProfiles,
        canLoadMore: canLoadMore,
        pendingNotesCount: othersCount,
      ));
    } else if (hasOwnNew) {
      _bufferedNotes = [];
      _latestDisplayedTimestamp = _getLatestTimestamp(sortedNotes);
      emit(currentState.copyWith(
        notes: sortedNotes,
        profiles: seededProfiles,
        canLoadMore: canLoadMore,
        pendingNotesCount: 0,
      ));
    } else {
      _bufferedNotes = [];
      emit(currentState.copyWith(
        notes: sortedNotes,
        profiles: seededProfiles,
        canLoadMore: canLoadMore,
        pendingNotesCount: 0,
      ));
    }
    _loadProfilesForNotes(sortedNotes);
    _prefetchEmbeddedContent(sortedNotes);
  }

  void _onFeedNewNotesAccepted(
    feed_event.FeedNewNotesAccepted event,
    Emitter<FeedState> emit,
  ) {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    if (_bufferedNotes.isNotEmpty) {
      _latestDisplayedTimestamp = _getLatestTimestamp(_bufferedNotes);
      emit(currentState.copyWith(
        notes: _bufferedNotes,
        pendingNotesCount: 0,
      ));
      _bufferedNotes = [];
    } else {
      emit(currentState.copyWith(pendingNotesCount: 0));
    }
  }

  int _getLatestTimestamp(List<FeedNote> notes) {
    if (notes.isEmpty) return 0;
    int latest = 0;
    for (final n in notes) {
      final t = n.repostCreatedAt ?? n.createdAt;
      if (t > latest) latest = t;
    }
    return latest;
  }

  void _syncInBackground(String userHex, Emitter<FeedState>? emit) {
    _watchFeed(userHex);

    Future.wait([
      _syncService.syncProfile(userHex),
      _syncService.syncFollowingList(userHex),
      _syncService.syncMuteList(userHex),
      _syncService.syncFeed(userHex),
    ])
        .timeout(
      const Duration(seconds: 2),
      onTimeout: () => [],
    )
        .then((_) async {
      if (isClosed) return;

      _watchFeed(userHex);

      final ownProfile = await _profileRepository.getProfile(userHex);
      if (!isClosed && ownProfile != null) {
        add(feed_event.FeedUserProfileUpdated(userHex, ownProfile.toMap()));
      }

      if (!isClosed && state is FeedLoaded) {
        add(feed_event.FeedSyncCompleted());
      }

      try {
        final follows = await _followingRepository.getFollowing(userHex);
        if (follows != null && follows.isNotEmpty) {
          _syncService.syncProfiles(follows);
        }

        await Future.wait([
          _syncService.syncBookmarkList(userHex),
          _syncService.syncPinnedNotes(userHex),
        ]);

        await _syncService.startRealtimeSubscriptions(userHex);
        await _syncService.syncFollowsOfFollows(userHex);
      } catch (_) {}
    }).catchError((_) {});
  }

  Future<void> _onFeedRefreshed(
    feed_event.FeedRefreshed event,
    Emitter<FeedState> emit,
  ) async {
    if (_currentUserHex == null) return;
    _currentLimit = _pageSize;
    _acceptNextUpdate = true;

    final currentState = state;
    if (currentState is FeedLoaded) {
      final notesToShow =
          _bufferedNotes.isNotEmpty ? _bufferedNotes : currentState.notes;
      _bufferedNotes = [];
      emit(currentState.copyWith(
        notes: notesToShow,
        isSyncing: true,
        pendingNotesCount: 0,
      ));

      if (currentState.hashtag != null) {
        _syncHashtagInBackground(currentState.hashtag!, null);
      } else if (currentState.activeListId != null) {
        final listPubkeys =
            _followSetService.pubkeysForList(currentState.activeListId!);
        if (listPubkeys != null && listPubkeys.isNotEmpty) {
          _watchListFeed(listPubkeys);
          _syncService
              .syncListFeed(listPubkeys, force: true)
              .catchError((_) {})
              .whenComplete(() {
            if (!isClosed && state is FeedLoaded) {
              add(feed_event.FeedSyncCompleted());
            }
          });
        }
      } else {
        _watchFeed(_currentUserHex!);
        _syncService
            .syncFeed(_currentUserHex!, force: true)
            .catchError((_) {})
            .whenComplete(() {
          if (!isClosed && state is FeedLoaded) {
            add(feed_event.FeedSyncCompleted());
          }
        });
      }
    }
  }

  Future<void> _onFeedLoadMoreRequested(
    feed_event.FeedLoadMoreRequested event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    if (!currentState.canLoadMore) return;

    _acceptNextUpdate = true;
    _bufferedNotes = [];
    emit(currentState.copyWith(isLoadingMore: true, pendingNotesCount: 0));

    try {
      _currentLimit += _pageSize;

      if (currentState.hashtag != null) {
        _watchHashtagFeed(currentState.hashtag!, limit: _currentLimit);
      } else if (currentState.activeListId != null) {
        final listPubkeys =
            _followSetService.pubkeysForList(currentState.activeListId!);
        if (listPubkeys != null && listPubkeys.isNotEmpty) {
          _watchListFeed(listPubkeys, limit: _currentLimit);
        }
      } else if (_currentUserHex != null) {
        _watchFeed(_currentUserHex!, limit: _currentLimit);
      }

      emit(currentState.copyWith(isLoadingMore: false));
    } catch (e) {
      emit(currentState.copyWith(isLoadingMore: false));
    }
  }

  void _onFeedViewModeChanged(
    feed_event.FeedViewModeChanged event,
    Emitter<FeedState> emit,
  ) {
    if (state is FeedLoaded) {
      emit((state as FeedLoaded).copyWith(viewMode: event.mode));
    }
  }

  void _onFeedSortModeChanged(
    feed_event.FeedSortModeChanged event,
    Emitter<FeedState> emit,
  ) {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;
    _currentSortMode = event.mode;
    _bufferedNotes = [];
    _acceptNextUpdate = true;
    emit(currentState.copyWith(sortMode: event.mode));
    if (_currentUserHex != null) {
      _watchFeed(_currentUserHex!);
    }
  }

  Future<void> _onFeedHashtagChanged(
    feed_event.FeedHashtagChanged event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    _feedSubscription?.cancel();
    _currentLimit = _pageSize;
    _bufferedNotes = [];

    if (event.hashtag != null) {
      emit(currentState.copyWith(
          hashtag: event.hashtag,
          notes: const [],
          isSyncing: true,
          pendingNotesCount: 0));
      _watchHashtagFeed(event.hashtag!);
      _syncHashtagInBackground(event.hashtag!, null);
    } else {
      emit(currentState.copyWith(
          hashtag: null,
          notes: const [],
          isSyncing: true,
          pendingNotesCount: 0));
      if (_currentUserHex != null) {
        _watchFeed(_currentUserHex!);
        _syncInBackground(_currentUserHex!, null);
      }
    }
  }

  void _onFeedUserProfileUpdated(
    feed_event.FeedUserProfileUpdated event,
    Emitter<FeedState> emit,
  ) {
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      final updatedProfiles =
          Map<String, Map<String, dynamic>>.from(currentState.profiles);
      updatedProfiles[event.userId] = event.user;
      emit(currentState.copyWith(profiles: updatedProfiles));
    }
  }

  void _onFeedNoteDeleted(
    feed_event.FeedNoteDeleted event,
    Emitter<FeedState> emit,
  ) {
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      final updatedNotes =
          currentState.notes.where((n) => n.id != event.noteId).toList();
      emit(currentState.copyWith(notes: updatedNotes));
    }
  }

  void _onFeedProfilesLoaded(
    feed_event.FeedProfilesLoaded event,
    Emitter<FeedState> emit,
  ) {
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      final updatedProfiles =
          Map<String, Map<String, dynamic>>.from(currentState.profiles);
      updatedProfiles.addAll(event.profiles);
      emit(currentState.copyWith(profiles: updatedProfiles));
    }
  }

  void _loadProfilesForNotes(List<FeedNote> notes) async {
    if (isClosed || state is! FeedLoaded || _profileLoadInProgress) return;

    final currentState = state as FeedLoaded;
    final authorIds = <String>{};
    for (final n in notes) {
      if (n.pubkey.isNotEmpty &&
          !currentState.profiles.containsKey(n.pubkey)) {
        authorIds.add(n.pubkey);
      }
      final repostedBy = n.repostedBy;
      if (repostedBy != null &&
          repostedBy.isNotEmpty &&
          !currentState.profiles.containsKey(repostedBy)) {
        authorIds.add(repostedBy);
      }
    }

    if (authorIds.isEmpty) return;

    _profileLoadInProgress = true;
    try {
      final profiles = await _profileRepository.getProfiles(authorIds.toList());
      if (isClosed) return;

      final allProfiles = <String, Map<String, dynamic>>{};
      final missingPubkeys = <String>[];

      for (final pubkey in authorIds) {
        final profile = profiles[pubkey];
        if (profile != null) {
          allProfiles[pubkey] = profile.toMap();
        } else {
          missingPubkeys.add(pubkey);
        }
      }

      if (missingPubkeys.isNotEmpty) {
        try {
          await _syncService
              .syncProfiles(missingPubkeys)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
        if (isClosed) return;

        final synced = await _profileRepository.getProfiles(missingPubkeys);
        if (isClosed) return;

        for (final entry in synced.entries) {
          allProfiles[entry.key] = entry.value.toMap();
        }
      }

      if (allProfiles.isNotEmpty && !isClosed) {
        add(feed_event.FeedProfilesLoaded(allProfiles));
      }
    } catch (_) {
    } finally {
      _profileLoadInProgress = false;
    }
  }

  void _prefetchEmbeddedContent(List<FeedNote> notes) {
    if (isClosed) return;

    final contents =
        notes.map((n) => n.content).where((c) => c.isNotEmpty).toList();
    if (contents.isEmpty) return;

    final result = _feedRepository.extractEmbeddedIds(contents);
    if (result.quoteEventIds.isNotEmpty) {
      _syncService.prefetchQuotedNotes(result.quoteEventIds);
    }
    if (result.articleAuthorPubkeys.isNotEmpty) {
      _syncService.prefetchArticlesByAuthors(result.articleAuthorPubkeys);
    }
  }

  void _watchListFeed(List<String> pubkeys, {int? limit}) => _watch(
        () => _feedRepository.watchFeed(
          _currentUserHex ?? '',
          authors: pubkeys,
          limit: limit ?? _currentLimit,
        ),
        () => _watchListFeed(pubkeys, limit: limit),
      );

  Future<void> _onFeedListChanged(
    feed_event.FeedListChanged event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    _feedSubscription?.cancel();
    _currentLimit = _pageSize;
    _bufferedNotes = [];
    _acceptNextUpdate = true;

    if (event.pubkeys == null || event.pubkeys!.isEmpty) {
      emit(currentState.copyWith(
        notes: const [],
        isSyncing: true,
        pendingNotesCount: 0,
        clearActiveList: true,
      ));
      if (_currentUserHex != null) {
        _syncInBackground(_currentUserHex!, null);
      }
    } else {
      emit(currentState.copyWith(
        notes: const [],
        isSyncing: true,
        pendingNotesCount: 0,
        activeListId: event.listId,
        activeListTitle: event.listTitle,
      ));

      _syncService
          .syncListFeed(event.pubkeys!)
          .then((_) {
            if (!isClosed) _watchListFeed(event.pubkeys!);
          })
          .catchError((_) {})
          .whenComplete(() {
            if (!isClosed && state is FeedLoaded) {
              add(feed_event.FeedSyncCompleted());
            }
          });
    }
  }

  void _onFeedSyncCompleted(
    feed_event.FeedSyncCompleted event,
    Emitter<FeedState> emit,
  ) {
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      emit(currentState.copyWith(isSyncing: false));
    }
  }

  @override
  Future<void> close() {
    _feedSubscription?.cancel();
    return super.close();
  }
}
