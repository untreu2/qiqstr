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
  static const int _watchLimit = 50;
  String? _currentUserHex;
  Map<String, dynamic>? _currentUserProfile;
  StreamSubscription<FeedUpdate>? _feedSubscription;
  FeedSortMode _currentSortMode = FeedSortMode.latest;

  List<FeedNote> _topPageNotes = const [];
  List<FeedNote> _olderNotes = const [];

  bool _acceptNextUpdate = false;
  int _latestDisplayedTimestamp = 0;
  bool _profileLoadInProgress = false;
  bool _canLoadMoreOlder = true;

  Timer? _interactionSyncDebounce;
  final Set<String> _syncedInteractionNoteIds = <String>{};
  static const Duration _interactionSyncDebounceDelay =
      Duration(milliseconds: 800);
  static const int _interactionSyncMaxBatch = 60;

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
    _resetAccumulators();

    final initialProfiles = <String, Map<String, dynamic>>{};
    final cachedCurrentUser =
        await _profileRepository.getProfile(event.userHex);
    if (cachedCurrentUser != null) {
      _currentUserProfile = cachedCurrentUser.toMap();
      initialProfiles[event.userHex] = _currentUserProfile!;
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
      _syncHashtagInBackground(event.hashtag!);
    } else {
      _syncInBackground(event.userHex);
    }
  }

  void _resetAccumulators() {
    _topPageNotes = const [];
    _olderNotes = const [];
    _canLoadMoreOlder = true;
    _latestDisplayedTimestamp = 0;
    _acceptNextUpdate = false;
  }

  void _watchStream(
    Stream<FeedUpdate> Function() source,
    void Function() retry,
  ) {
    _feedSubscription?.cancel();
    _feedSubscription = source().listen(
      (update) {
        if (!isClosed) add(feed_event.FeedNotesUpdated(update));
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

  void _watchFeed(String userHex, {String? sortMode}) => _watchStream(
        () => _feedRepository.watchFeed(
          userHex,
          limit: _watchLimit,
          sortMode: sortMode ?? _sortModeKey(_currentSortMode),
        ),
        () => _watchFeed(userHex, sortMode: sortMode),
      );

  static String _sortModeKey(FeedSortMode mode) =>
      mode == FeedSortMode.mostInteracted ? 'most_interacted' : 'latest';

  void _watchHashtagFeed(String hashtag) => _watchStream(
        () => _feedRepository.watchHashtag(hashtag, limit: _watchLimit),
        () => _watchHashtagFeed(hashtag),
      );

  void _watchListFeed(List<String> pubkeys) => _watchStream(
        () => _feedRepository.watchFeed(
          _currentUserHex ?? '',
          authors: pubkeys,
          limit: _watchLimit,
        ),
        () => _watchListFeed(pubkeys),
      );

  void _syncHashtagInBackground(String hashtag) {
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

  Map<String, Map<String, dynamic>> _withCurrentUserProfile(
    Map<String, Map<String, dynamic>> profiles,
  ) {
    final hex = _currentUserHex;
    final profile = _currentUserProfile;
    if (hex == null || profile == null || profiles.containsKey(hex)) {
      return profiles;
    }
    return {...profiles, hex: profile};
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
    return _withCurrentUserProfile(merged);
  }

  void _onFeedNotesUpdated(
    feed_event.FeedNotesUpdated event,
    Emitter<FeedState> emit,
  ) {
    FeedLoaded currentState;
    if (state is FeedLoaded) {
      currentState = state as FeedLoaded;
    } else if (state is FeedEmpty && _currentUserHex != null) {
      currentState = FeedLoaded(
        notes: const [],
        profiles: _withCurrentUserProfile(const {}),
        currentUserHex: _currentUserHex!,
      );
    } else {
      return;
    }

    final update = event.update;
    switch (update) {
      case FeedSnapshot(notes: final snap):
        _topPageNotes =
            _currentSortMode == FeedSortMode.latest ? _sortedByTime(snap) : snap;
        break;
      case FeedDelta(changed: final changed, removed: final removed):
        _applyDelta(changed, removed);
        break;
      case FeedErrorUpdate(message: final message):
        if (currentState.notes.isEmpty) {
          emit(FeedError(message));
        }
        return;
    }

    final combined = _combinedNotes();
    InteractionService.instance.populateFromNotes(combined);
    _scheduleInteractionSync(combined);

    final seededProfiles =
        _buildProfilesFromNotes(combined, currentState.profiles);
    final canLoadMore =
        _canLoadMoreOlder && (combined.length >= _watchLimit);

    if (currentState.notes.isEmpty || _acceptNextUpdate) {
      _acceptNextUpdate = false;
      _latestDisplayedTimestamp = _getLatestTimestamp(combined);
      emit(currentState.copyWith(
        notes: combined,
        profiles: seededProfiles,
        canLoadMore: canLoadMore,
        pendingNotesCount: 0,
      ));
      _loadProfilesForNotes(combined);
      _prefetchEmbeddedContent(combined);
      return;
    }

    int othersCount = 0;
    bool hasOwnNew = false;
    for (final n in combined) {
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
      final displayedIds = currentState.notes.map((n) => n.id).toSet();
      final visibleNotes = combined.where((n) {
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
      _latestDisplayedTimestamp = _getLatestTimestamp(combined);
      emit(currentState.copyWith(
        notes: combined,
        profiles: seededProfiles,
        canLoadMore: canLoadMore,
        pendingNotesCount: 0,
      ));
    } else {
      emit(currentState.copyWith(
        notes: combined,
        profiles: seededProfiles,
        canLoadMore: canLoadMore,
        pendingNotesCount: 0,
      ));
    }
    _loadProfilesForNotes(combined);
    _prefetchEmbeddedContent(combined);
  }

  List<FeedNote> _combinedNotes() {
    if (_olderNotes.isEmpty) return _topPageNotes;
    if (_topPageNotes.isEmpty) return _olderNotes;
    final topIds = <String>{for (final n in _topPageNotes) n.id};
    final older = _olderNotes.where((n) => !topIds.contains(n.id));
    return [..._topPageNotes, ...older];
  }

  void _applyDelta(List<FeedNote> changed, List<String> removed) {
    if (removed.isNotEmpty) {
      final removeSet = removed.toSet();
      _topPageNotes =
          _topPageNotes.where((n) => !removeSet.contains(n.id)).toList();
      _olderNotes =
          _olderNotes.where((n) => !removeSet.contains(n.id)).toList();
    }
    if (changed.isEmpty) return;

    final byId = <String, FeedNote>{for (final n in changed) n.id: n};

    var topUpdated = false;
    final newTop = [
      for (final n in _topPageNotes)
        if (byId.containsKey(n.id))
          (topUpdated = true, byId.remove(n.id)!).$2
        else
          n,
    ];

    var olderUpdated = false;
    final newOlder = [
      for (final n in _olderNotes)
        if (byId.containsKey(n.id))
          (olderUpdated = true, byId.remove(n.id)!).$2
        else
          n,
    ];

    final brandNew = byId.values.toList();
    if (brandNew.isNotEmpty) {
      newTop.addAll(brandNew);
      topUpdated = true;
    }

    if (topUpdated) {
      newTop.sort((a, b) => (b.repostCreatedAt ?? b.createdAt)
          .compareTo(a.repostCreatedAt ?? a.createdAt));
      _topPageNotes = newTop;
    }
    if (olderUpdated) {
      _olderNotes = newOlder;
    }
  }

  void _onFeedNewNotesAccepted(
    feed_event.FeedNewNotesAccepted event,
    Emitter<FeedState> emit,
  ) {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    final combined = _combinedNotes();
    if (combined.isNotEmpty) {
      _latestDisplayedTimestamp = _getLatestTimestamp(combined);
      emit(currentState.copyWith(
        notes: combined,
        pendingNotesCount: 0,
      ));
    } else {
      emit(currentState.copyWith(pendingNotesCount: 0));
    }
  }

  List<FeedNote> _sortedByTime(List<FeedNote> notes) {
    final sorted = List<FeedNote>.from(notes);
    sorted.sort((a, b) => (b.repostCreatedAt ?? b.createdAt)
        .compareTo(a.repostCreatedAt ?? a.createdAt));
    return sorted;
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

  void _syncInBackground(String userHex) {
    _watchFeed(userHex);

    Future.wait([
      _syncService.syncProfile(userHex),
      _syncService.syncFollowingList(userHex),
      _syncService.syncMuteList(userHex),
      _syncService.syncFeed(userHex),
    ])
        .timeout(
      const Duration(seconds: 15),
      onTimeout: () => [],
    )
        .then((_) async {
      if (isClosed) return;

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
    _resetAccumulators();
    _acceptNextUpdate = true;

    final currentState = state;
    final FeedLoaded baseState = currentState is FeedLoaded
        ? currentState.copyWith(isSyncing: true, pendingNotesCount: 0)
        : FeedLoaded(
            notes: const [],
            profiles: _withCurrentUserProfile(const {}),
            currentUserHex: _currentUserHex!,
            sortMode: _currentSortMode,
            isSyncing: true,
          );
    emit(baseState);

    if (baseState.hashtag != null) {
      _syncHashtagInBackground(baseState.hashtag!);
    } else if (baseState.activeListId != null) {
      final listPubkeys =
          _followSetService.pubkeysForList(baseState.activeListId!);
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

  Future<void> _onFeedLoadMoreRequested(
    feed_event.FeedLoadMoreRequested event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    if (!currentState.canLoadMore || !_canLoadMoreOlder) return;
    if (_currentUserHex == null && currentState.hashtag == null) return;

    emit(currentState.copyWith(isLoadingMore: true, pendingNotesCount: 0));

    try {
      final currentCombined = _combinedNotes();
      final newLimit = currentCombined.length + _pageSize;

      List<FeedNote> page;
      if (currentState.hashtag != null) {
        page = await _feedRepository.getHashtag(
          currentState.hashtag!,
          limit: newLimit,
        );
      } else if (currentState.activeListId != null) {
        final listPubkeys =
            _followSetService.pubkeysForList(currentState.activeListId!);
        if (listPubkeys == null || listPubkeys.isEmpty) {
          emit(currentState.copyWith(isLoadingMore: false));
          return;
        }
        page = await _feedRepository.getFeed(
          _currentUserHex ?? '',
          authors: listPubkeys,
          limit: newLimit,
        );
      } else {
        page = await _feedRepository.getFeed(
          _currentUserHex!,
          limit: newLimit,
        );
      }

      if (isClosed) return;

      final knownIds = <String>{
        for (final n in _topPageNotes) n.id,
        for (final n in _olderNotes) n.id,
      };
      final additions =
          page.where((n) => !knownIds.contains(n.id)).toList();

      if (additions.isEmpty) {
        _canLoadMoreOlder = false;
        emit(currentState.copyWith(
          isLoadingMore: false,
          canLoadMore: false,
        ));
        return;
      }

      _olderNotes = [..._olderNotes, ...additions];
      _olderNotes = _sortedByTime(_olderNotes);

      if (additions.length < _pageSize) {
        _canLoadMoreOlder = false;
      }

      InteractionService.instance.populateFromNotes(additions);
      _loadProfilesForNotes(additions);
      _prefetchEmbeddedContent(additions);

      final combined = _combinedNotes();
      final seededProfiles =
          _buildProfilesFromNotes(combined, currentState.profiles);

      emit(currentState.copyWith(
        notes: combined,
        profiles: seededProfiles,
        isLoadingMore: false,
        canLoadMore: _canLoadMoreOlder,
      ));
    } catch (_) {
      if (state is FeedLoaded) {
        emit((state as FeedLoaded).copyWith(isLoadingMore: false));
      }
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
    _resetAccumulators();
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
    _resetAccumulators();

    if (event.hashtag != null) {
      emit(currentState.copyWith(
          hashtag: event.hashtag,
          notes: const [],
          isSyncing: true,
          pendingNotesCount: 0));
      _watchHashtagFeed(event.hashtag!);
      _syncHashtagInBackground(event.hashtag!);
    } else {
      emit(currentState.copyWith(
          hashtag: null,
          notes: const [],
          isSyncing: true,
          pendingNotesCount: 0));
      if (_currentUserHex != null) {
        _watchFeed(_currentUserHex!);
        _syncInBackground(_currentUserHex!);
      }
    }
  }

  void _onFeedUserProfileUpdated(
    feed_event.FeedUserProfileUpdated event,
    Emitter<FeedState> emit,
  ) {
    if (event.userId == _currentUserHex) {
      _currentUserProfile = event.user;
    }
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
      _topPageNotes =
          _topPageNotes.where((n) => n.id != event.noteId).toList();
      _olderNotes = _olderNotes.where((n) => n.id != event.noteId).toList();
      emit(currentState.copyWith(notes: _combinedNotes()));
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

  Future<void> _onFeedListChanged(
    feed_event.FeedListChanged event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    _feedSubscription?.cancel();
    _resetAccumulators();
    _acceptNextUpdate = true;

    if (event.pubkeys == null || event.pubkeys!.isEmpty) {
      emit(currentState.copyWith(
        notes: const [],
        isSyncing: true,
        pendingNotesCount: 0,
        clearActiveList: true,
      ));
      if (_currentUserHex != null) {
        _syncInBackground(_currentUserHex!);
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
      emit((state as FeedLoaded).copyWith(isSyncing: false));
    }
  }

  @override
  Future<void> close() {
    _feedSubscription?.cancel();
    _interactionSyncDebounce?.cancel();
    return super.close();
  }

  void _scheduleInteractionSync(List<FeedNote> notes) {
    if (notes.isEmpty) return;
    final candidates = <String>[];
    for (final n in notes) {
      final id = n.isRepost && (n.repostEventId?.isNotEmpty ?? false)
          ? n.repostEventId!
          : n.id;
      if (id.isEmpty) continue;
      if (_syncedInteractionNoteIds.contains(id)) continue;
      candidates.add(id);
      if (candidates.length >= _interactionSyncMaxBatch) break;
    }
    if (candidates.isEmpty) return;

    _interactionSyncDebounce?.cancel();
    _interactionSyncDebounce = Timer(_interactionSyncDebounceDelay, () {
      if (isClosed) return;
      _syncedInteractionNoteIds.addAll(candidates);
      _syncService
          .syncInteractionsForNotes(candidates)
          .catchError((_) {});
    });
  }
}
