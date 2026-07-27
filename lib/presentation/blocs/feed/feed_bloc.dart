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
  bool _profileLoadPending = false;
  bool _canLoadMoreOlder = true;
  int _watchGeneration = 0;
  int _contextGeneration = 0;
  String? _currentHashtag;
  String? _activeListId;
  String? _activeListTitle;
  List<String>? _activeListPubkeys;

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
    if (event.userHex.length != 64) {
      emit(const FeedError('Invalid account public key'));
      return;
    }

    if (state is FeedLoaded) {
      final current = state as FeedLoaded;
      if (current.currentUserHex == event.userHex &&
          current.hashtag == event.hashtag) {
        return;
      }
    }

    _currentUserHex = event.userHex;
    _currentSortMode = FeedSortMode.latest;
    _currentHashtag = event.hashtag;
    _activeListId = null;
    _activeListTitle = null;
    _activeListPubkeys = null;
    _cancelFeedWatch();
    _resetAccumulators();
    _contextGeneration++;

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
      _watchHashtagFeed(event.hashtag!);
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
    _syncedInteractionNoteIds.clear();
    _interactionSyncDebounce?.cancel();
  }

  void _watchStream(Stream<FeedUpdate> Function() source) {
    final generation = ++_watchGeneration;
    _feedSubscription?.cancel();

    void subscribe() {
      if (isClosed || generation != _watchGeneration) return;
      _feedSubscription = source().listen(
        (update) {
          if (!isClosed && generation == _watchGeneration) {
            add(feed_event.FeedNotesUpdated(update, generation));
          }
        },
        onError: (_) => _scheduleWatchRetry(generation, subscribe),
        onDone: () => _scheduleWatchRetry(generation, subscribe),
      );
    }

    subscribe();
  }

  void _scheduleWatchRetry(int generation, void Function() subscribe) {
    Future.delayed(const Duration(seconds: 2), () {
      if (!isClosed && generation == _watchGeneration) subscribe();
    });
  }

  void _cancelFeedWatch() {
    _watchGeneration++;
    _feedSubscription?.cancel();
    _feedSubscription = null;
  }

  void _watchFeed(String userHex, {String? sortMode}) => _watchStream(
        () => _feedRepository.watchFeed(
          userHex,
          limit: _watchLimit,
          sortMode: sortMode ?? _sortModeKey(_currentSortMode),
        ),
      );

  static String _sortModeKey(FeedSortMode mode) =>
      mode == FeedSortMode.mostInteracted ? 'most_interacted' : 'latest';

  void _watchHashtagFeed(String hashtag) => _watchStream(
        () => _feedRepository.watchHashtag(hashtag, limit: _watchLimit),
      );

  void _watchListFeed(List<String> pubkeys) => _watchStream(
        () => _feedRepository.watchFeed(
          _currentUserHex ?? '',
          authors: pubkeys,
          limit: _watchLimit,
          sortMode: _sortModeKey(_currentSortMode),
        ),
      );

  void _syncHashtagInBackground(String hashtag) {
    final generation = _contextGeneration;
    _syncService.syncHashtag(hashtag).catchError((_) {}).whenComplete(() {
      if (!isClosed &&
          generation == _contextGeneration &&
          state is FeedLoaded) {
        add(feed_event.FeedSyncCompleted(generation));
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
    if (event.generation != _watchGeneration) return;

    FeedLoaded currentState;
    if (state is FeedLoaded) {
      currentState = state as FeedLoaded;
    } else if ((state is FeedEmpty || state is FeedError) &&
        _currentUserHex != null) {
      currentState = FeedLoaded(
        notes: const [],
        profiles: _withCurrentUserProfile(const {}),
        currentUserHex: _currentUserHex!,
        hashtag: _currentHashtag,
        activeListId: _activeListId,
        activeListTitle: _activeListTitle,
        sortMode: _currentSortMode,
        isSyncing: true,
      );
    } else {
      return;
    }

    final update = event.update;
    switch (update) {
      case FeedSnapshot(notes: final snap):
        _topPageNotes = _sortedForMode(_deduplicate(snap));
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
    final canLoadMore = _canLoadMoreOlder && (combined.length >= _watchLimit);

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
        final feedAuthor = n.isRepost ? n.repostedBy : n.pubkey;
        if (feedAuthor == _currentUserHex) {
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
        final feedAuthor = n.isRepost ? n.repostedBy : n.pubkey;
        return noteTime <= _latestDisplayedTimestamp ||
            displayedIds.contains(n.id) ||
            feedAuthor == _currentUserHex;
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
    if (_olderNotes.isEmpty) return _sortedForMode(_deduplicate(_topPageNotes));
    if (_topPageNotes.isEmpty) return _sortedForMode(_deduplicate(_olderNotes));
    final topIds = <String>{for (final n in _topPageNotes) n.id};
    final older = _olderNotes.where((n) => !topIds.contains(n.id));
    return _sortedForMode(_deduplicate([..._topPageNotes, ...older]));
  }

  List<FeedNote> _deduplicate(List<FeedNote> notes) {
    final byId = <String, FeedNote>{};
    for (final note in notes) {
      if (note.id.isEmpty) continue;
      final existing = byId[note.id];
      final noteTime = note.repostCreatedAt ?? note.createdAt;
      final existingTime = existing == null
          ? -1
          : (existing.repostCreatedAt ?? existing.createdAt);
      if (existing == null || noteTime > existingTime) {
        byId[note.id] = note;
      }
    }
    return byId.values.toList();
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
      _topPageNotes = _sortedForMode(_deduplicate(newTop));
    }
    if (olderUpdated) {
      _olderNotes = _sortedForMode(_deduplicate(newOlder));
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

  List<FeedNote> _sortedForMode(List<FeedNote> notes) {
    if (_currentSortMode == FeedSortMode.latest) {
      return _sortedByTime(notes);
    }
    final sorted = List<FeedNote>.from(notes);
    sorted.sort((a, b) {
      final aScore =
          a.reactionCount + a.repostCount + a.replyCount + a.zapCount;
      final bScore =
          b.reactionCount + b.repostCount + b.replyCount + b.zapCount;
      final byScore = bScore.compareTo(aScore);
      if (byScore != 0) return byScore;
      return (b.repostCreatedAt ?? b.createdAt)
          .compareTo(a.repostCreatedAt ?? a.createdAt);
    });
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
    final generation = _contextGeneration;
    _watchFeed(userHex);
    Future<void>(() async {
      try {
        await Future.wait([
          _syncService.syncProfile(userHex),
          _syncService.syncFollowingList(userHex),
          _syncService.syncMuteList(userHex),
          _syncService.syncFeed(userHex),
        ]).timeout(const Duration(seconds: 15));

        if (isClosed || generation != _contextGeneration) return;
        final ownProfile = await _profileRepository.getProfile(userHex);
        if (!isClosed &&
            generation == _contextGeneration &&
            ownProfile != null) {
          add(feed_event.FeedUserProfileUpdated(userHex, ownProfile.toMap()));
        }
      } catch (_) {
      } finally {
        if (!isClosed &&
            generation == _contextGeneration &&
            state is FeedLoaded) {
          add(feed_event.FeedSyncCompleted(generation));
        }
      }

      if (isClosed || generation != _contextGeneration) return;
      try {
        final follows = await _followingRepository.getFollowing(userHex);
        if (follows != null && follows.isNotEmpty) {
          _syncService.syncProfiles(follows);
        }
        await Future.wait([
          _syncService.syncBookmarkList(userHex),
          _syncService.syncPinnedNotes(userHex),
        ]);
        if (isClosed || generation != _contextGeneration) return;
        await _syncService.startRealtimeSubscriptions(userHex);
        await _syncService.syncFollowsOfFollows(userHex);
      } catch (_) {}
    });
  }

  Future<void> _onFeedRefreshed(
    feed_event.FeedRefreshed event,
    Emitter<FeedState> emit,
  ) async {
    if (_currentUserHex == null) return;
    _contextGeneration++;
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
            hashtag: _currentHashtag,
            activeListId: _activeListId,
            activeListTitle: _activeListTitle,
            isSyncing: true,
          );
    emit(baseState);

    final generation = _contextGeneration;
    if (_currentHashtag != null) {
      _watchHashtagFeed(_currentHashtag!);
      _syncHashtagInBackground(_currentHashtag!);
    } else if (_activeListId != null) {
      final listPubkeys = _activeListPubkeys ??
          _followSetService.pubkeysForList(_activeListId!);
      if (listPubkeys != null && listPubkeys.isNotEmpty) {
        _watchListFeed(listPubkeys);
        _syncService
            .syncListFeed(listPubkeys, force: true)
            .catchError((_) {})
            .whenComplete(() {
          if (!isClosed &&
              generation == _contextGeneration &&
              state is FeedLoaded) {
            add(feed_event.FeedSyncCompleted(generation));
          }
        });
      } else {
        add(feed_event.FeedSyncCompleted(generation));
      }
    } else {
      _watchFeed(_currentUserHex!);
      _syncService
          .syncFeed(_currentUserHex!, force: true)
          .catchError((_) {})
          .whenComplete(() {
        if (!isClosed &&
            generation == _contextGeneration &&
            state is FeedLoaded) {
          add(feed_event.FeedSyncCompleted(generation));
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
    final generation = _contextGeneration;

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
          sortMode: _sortModeKey(_currentSortMode),
        );
      } else {
        page = await _feedRepository.getFeed(
          _currentUserHex!,
          limit: newLimit,
          sortMode: _sortModeKey(_currentSortMode),
        );
      }

      if (isClosed || generation != _contextGeneration) return;

      final knownIds = <String>{
        for (final n in _topPageNotes) n.id,
        for (final n in _olderNotes) n.id,
      };
      final additions = page.where((n) => !knownIds.contains(n.id)).toList();

      if (additions.isEmpty) {
        _canLoadMoreOlder = false;
        emit(currentState.copyWith(
          isLoadingMore: false,
          canLoadMore: false,
        ));
        return;
      }

      _olderNotes = _sortedForMode(
        _deduplicate([..._olderNotes, ...additions]),
      );

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
      if (generation == _contextGeneration && state is FeedLoaded) {
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
    _contextGeneration++;
    _currentSortMode = event.mode;
    _resetAccumulators();
    _acceptNextUpdate = true;
    emit(currentState.copyWith(sortMode: event.mode));
    if (currentState.hashtag != null) {
      _watchHashtagFeed(currentState.hashtag!);
    } else if (currentState.activeListId != null) {
      final pubkeys =
          _followSetService.pubkeysForList(currentState.activeListId!);
      if (pubkeys != null && pubkeys.isNotEmpty) {
        _watchListFeed(pubkeys);
      }
    } else if (_currentUserHex != null) {
      _watchFeed(_currentUserHex!);
    }
  }

  Future<void> _onFeedHashtagChanged(
    feed_event.FeedHashtagChanged event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    _cancelFeedWatch();
    _contextGeneration++;
    _resetAccumulators();
    _currentHashtag = event.hashtag;
    _activeListId = null;
    _activeListTitle = null;
    _activeListPubkeys = null;

    if (event.hashtag != null) {
      emit(currentState.copyWith(
          hashtag: event.hashtag,
          notes: const [],
          isSyncing: true,
          pendingNotesCount: 0,
          clearActiveList: true));
      _watchHashtagFeed(event.hashtag!);
      _syncHashtagInBackground(event.hashtag!);
    } else {
      emit(currentState.copyWith(
          notes: const [],
          isSyncing: true,
          pendingNotesCount: 0,
          clearHashtag: true,
          clearActiveList: true));
      if (_currentUserHex != null) {
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
      _topPageNotes = _topPageNotes.where((n) => n.id != event.noteId).toList();
      _olderNotes = _olderNotes.where((n) => n.id != event.noteId).toList();
      emit(currentState.copyWith(notes: _combinedNotes()));
    }
  }

  void _onFeedProfilesLoaded(
    feed_event.FeedProfilesLoaded event,
    Emitter<FeedState> emit,
  ) {
    if (event.generation != _contextGeneration) return;
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      final updatedProfiles =
          Map<String, Map<String, dynamic>>.from(currentState.profiles);
      updatedProfiles.addAll(event.profiles);
      emit(currentState.copyWith(profiles: updatedProfiles));
    }
  }

  void _loadProfilesForNotes(List<FeedNote> notes) async {
    if (isClosed || state is! FeedLoaded) return;
    if (_profileLoadInProgress) {
      _profileLoadPending = true;
      return;
    }

    final currentState = state as FeedLoaded;
    final generation = _contextGeneration;
    final authorIds = <String>{};
    for (final n in notes) {
      if (n.pubkey.isNotEmpty && !currentState.profiles.containsKey(n.pubkey)) {
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
    _profileLoadPending = false;
    try {
      final profiles = await _profileRepository.getProfiles(authorIds.toList());
      if (isClosed || generation != _contextGeneration) return;

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
        if (isClosed || generation != _contextGeneration) return;

        final synced = await _profileRepository.getProfiles(missingPubkeys);
        if (isClosed || generation != _contextGeneration) return;

        for (final entry in synced.entries) {
          allProfiles[entry.key] = entry.value.toMap();
        }
      }

      if (allProfiles.isNotEmpty && !isClosed) {
        add(feed_event.FeedProfilesLoaded(allProfiles, generation));
      }
    } catch (_) {
    } finally {
      _profileLoadInProgress = false;
      if (_profileLoadPending && !isClosed && state is FeedLoaded) {
        _profileLoadPending = false;
        _loadProfilesForNotes(_combinedNotes());
      }
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

    _cancelFeedWatch();
    _contextGeneration++;
    _resetAccumulators();
    _acceptNextUpdate = true;
    _currentHashtag = null;
    _activeListId = event.listId;
    _activeListTitle = event.listTitle;
    _activeListPubkeys = event.pubkeys;

    if (event.pubkeys == null || event.pubkeys!.isEmpty) {
      _activeListId = null;
      _activeListTitle = null;
      _activeListPubkeys = null;
      emit(currentState.copyWith(
        notes: const [],
        isSyncing: true,
        pendingNotesCount: 0,
        clearHashtag: true,
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
        clearHashtag: true,
      ));

      _watchListFeed(event.pubkeys!);
      final generation = _contextGeneration;
      _syncService
          .syncListFeed(event.pubkeys!)
          .catchError((_) {})
          .whenComplete(() {
        if (!isClosed &&
            generation == _contextGeneration &&
            state is FeedLoaded) {
          add(feed_event.FeedSyncCompleted(generation));
        }
      });
    }
  }

  void _onFeedSyncCompleted(
    feed_event.FeedSyncCompleted event,
    Emitter<FeedState> emit,
  ) {
    if (event.generation != _contextGeneration) return;
    if (state is FeedLoaded) {
      emit((state as FeedLoaded).copyWith(isSyncing: false));
    }
  }

  @override
  Future<void> close() {
    _watchGeneration++;
    _feedSubscription?.cancel();
    _interactionSyncDebounce?.cancel();
    return super.close();
  }

  void _scheduleInteractionSync(List<FeedNote> notes) {
    if (notes.isEmpty) return;
    final candidates = <String>[];
    for (final n in notes) {
      final id = n.id;
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
      _syncService.syncInteractionsForNotes(candidates).catchError((_) {
        _syncedInteractionNoteIds.removeAll(candidates);
      });
    });
  }
}
