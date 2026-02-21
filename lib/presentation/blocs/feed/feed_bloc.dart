import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/entities/feed_note.dart';
import '../../../data/services/follow_set_service.dart';
import 'feed_event.dart' as feed_event;
import 'feed_state.dart';

class FeedBloc extends Bloc<feed_event.FeedEvent, FeedState> {
  final FeedRepository _feedRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;

  static const int _pageSize = 50;
  String? _currentUserHex;
  StreamSubscription<List<FeedNote>>? _feedSubscription;
  bool _isLoadingMore = false;
  int _currentLimit = 50;
  List<Map<String, dynamic>> _bufferedNotes = [];
  bool _acceptNextUpdate = false;

  FeedBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        super(const FeedInitial()) {
    on<feed_event.FeedInitialized>(_onFeedInitialized);
    on<feed_event.FeedRefreshed>(_onFeedRefreshed);
    on<feed_event.FeedLoadMoreRequested>(_onFeedLoadMoreRequested);
    on<feed_event.FeedViewModeChanged>(_onFeedViewModeChanged);
    on<feed_event.FeedSortModeChanged>(_onFeedSortModeChanged);
    on<feed_event.FeedHashtagChanged>(_onFeedHashtagChanged);
    on<feed_event.FeedUserProfileUpdated>(_onFeedUserProfileUpdated);
    on<feed_event.FeedNoteDeleted>(_onFeedNoteDeleted);
    on<feed_event.FeedProfilesLoaded>(_onFeedProfilesLoaded);
    on<feed_event.FeedNotesUpdated>(_onFeedNotesUpdated);
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

  void _watchFeed(String userHex, {int? limit}) {
    _feedSubscription?.cancel();
    _feedSubscription = _feedRepository
        .watchFeed(userHex, limit: limit ?? _currentLimit)
        .listen(
      (notes) {
        if (isClosed) return;
        add(feed_event.FeedNotesUpdated(notes));
      },
      onError: (_) {
        if (isClosed) return;
        Future.delayed(const Duration(seconds: 2), () {
          if (!isClosed) _watchFeed(userHex, limit: limit);
        });
      },
      onDone: () {
        if (isClosed) return;
        Future.delayed(const Duration(seconds: 2), () {
          if (!isClosed) _watchFeed(userHex, limit: limit);
        });
      },
    );
  }

  void _watchHashtagFeed(String hashtag, {int? limit}) {
    _feedSubscription?.cancel();
    _feedSubscription = _feedRepository
        .watchHashtagFeed(hashtag, limit: limit ?? _currentLimit)
        .listen(
      (notes) {
        if (isClosed) return;
        add(feed_event.FeedNotesUpdated(notes));
      },
      onError: (_) {
        if (isClosed) return;
        Future.delayed(const Duration(seconds: 2), () {
          if (!isClosed) _watchHashtagFeed(hashtag, limit: limit);
        });
      },
      onDone: () {
        if (isClosed) return;
        Future.delayed(const Duration(seconds: 2), () {
          if (!isClosed) _watchHashtagFeed(hashtag, limit: limit);
        });
      },
    );
  }

  void _syncHashtagInBackground(String hashtag, Emitter<FeedState>? emit) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncHashtag(hashtag);
        if (isClosed) return;
        _watchHashtagFeed(hashtag);
      } catch (_) {}
      if (!isClosed && state is FeedLoaded) {
        add(feed_event.FeedSyncCompleted());
      }
    });
  }

  void _onFeedNotesUpdated(
    feed_event.FeedNotesUpdated event,
    Emitter<FeedState> emit,
  ) {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    final sortedNotes = _feedNotesToMaps(event.notes);
    _sortNotes(sortedNotes, currentState.sortMode);

    if (currentState.notes.isEmpty ||
        _acceptNextUpdate ||
        currentState.isSyncing) {
      _acceptNextUpdate = false;
      _bufferedNotes = [];
      emit(currentState.copyWith(notes: sortedNotes, pendingNotesCount: 0));
      _loadProfilesForNotes(sortedNotes);
      return;
    }

    final displayedIds = <String>{};
    for (final n in currentState.notes) {
      final id = n['id'] as String? ?? '';
      if (id.isNotEmpty) displayedIds.add(id);
    }

    int newCount = 0;
    for (final n in sortedNotes) {
      final id = n['id'] as String? ?? '';
      if (id.isNotEmpty && !displayedIds.contains(id)) newCount++;
    }

    if (newCount > 0) {
      _bufferedNotes = sortedNotes;
      emit(currentState.copyWith(pendingNotesCount: newCount));
    } else {
      _bufferedNotes = [];
      emit(currentState.copyWith(notes: sortedNotes, pendingNotesCount: 0));
    }
    _loadProfilesForNotes(sortedNotes);
  }

  void _onFeedNewNotesAccepted(
    feed_event.FeedNewNotesAccepted event,
    Emitter<FeedState> emit,
  ) {
    if (state is! FeedLoaded) return;
    final currentState = state as FeedLoaded;

    if (_bufferedNotes.isNotEmpty) {
      emit(currentState.copyWith(notes: _bufferedNotes, pendingNotesCount: 0));
      _bufferedNotes = [];
    } else {
      emit(currentState.copyWith(pendingNotesCount: 0));
    }
  }

  void _syncInBackground(String userHex, Emitter<FeedState>? emit) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await Future.wait([
          _syncService.syncProfile(userHex),
          _syncService.syncFollowingList(userHex),
          _syncService.syncMuteList(userHex),
        ]);
        if (isClosed) return;

        final ownProfile = await _profileRepository.getProfile(userHex);
        if (!isClosed && ownProfile != null) {
          add(feed_event.FeedUserProfileUpdated(userHex, ownProfile.toMap()));
        }

        final follows = await _feedRepository.getFollowingList(userHex);
        if (follows != null && follows.isNotEmpty) {
          _syncService.syncProfiles(follows);
        }

        await Future.wait([
          _syncService.syncBookmarkList(userHex),
          _syncService.syncPinnedNotes(userHex),
        ]);
        if (isClosed) return;

        await _syncService.syncFeed(userHex, force: true);
        if (isClosed) return;

        final currentState = state;
        if (currentState is FeedLoaded && currentState.activeListId == null) {
          _watchFeed(userHex);
        }

        await _syncService.startRealtimeSubscriptions(userHex);
      } catch (_) {}
      if (!isClosed && state is FeedLoaded) {
        add(feed_event.FeedSyncCompleted());
      }
      Future.microtask(() async {
        try {
          await _syncService.syncFollowsOfFollows(userHex);
        } catch (_) {}
      });
    });
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
        final service = _getFollowSetService();
        final listPubkeys = service?.pubkeysForList(currentState.activeListId!);
        if (listPubkeys != null && listPubkeys.isNotEmpty) {
          _watchListFeed(listPubkeys);
          Future.microtask(() async {
            if (isClosed) return;
            try {
              await _syncService.syncListFeed(listPubkeys, force: true);
            } catch (_) {}
            if (!isClosed && state is FeedLoaded) {
              add(feed_event.FeedSyncCompleted());
            }
          });
        }
      } else {
        _watchFeed(_currentUserHex!);
        Future.microtask(() async {
          if (isClosed) return;
          try {
            await _syncService.syncFeed(_currentUserHex!, force: true);
          } catch (_) {}
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

    if (_isLoadingMore || !currentState.canLoadMore) {
      return;
    }

    _isLoadingMore = true;
    _acceptNextUpdate = true;
    _bufferedNotes = [];
    emit(currentState.copyWith(isLoadingMore: true, pendingNotesCount: 0));

    try {
      _currentLimit += _pageSize;

      if (currentState.hashtag != null) {
        _watchHashtagFeed(currentState.hashtag!, limit: _currentLimit);
      } else if (currentState.activeListId != null) {
        final service = _getFollowSetService();
        final listPubkeys = service?.pubkeysForList(currentState.activeListId!);
        if (listPubkeys != null && listPubkeys.isNotEmpty) {
          _watchListFeed(listPubkeys, limit: _currentLimit);
        }
      } else if (_currentUserHex != null) {
        _watchFeed(_currentUserHex!, limit: _currentLimit);
      }

      emit(currentState.copyWith(isLoadingMore: false));
    } catch (e) {
      emit(currentState.copyWith(isLoadingMore: false));
    } finally {
      _isLoadingMore = false;
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
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      final sortedNotes = List<Map<String, dynamic>>.from(currentState.notes);
      _sortNotes(sortedNotes, event.mode);
      if (_bufferedNotes.isNotEmpty) {
        _sortNotes(_bufferedNotes, event.mode);
      }
      emit(currentState.copyWith(notes: sortedNotes, sortMode: event.mode));
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
      final updatedNotes = currentState.notes.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && noteId != event.noteId;
      }).toList();
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

  void _loadProfilesForNotes(List<Map<String, dynamic>> notes) {
    Future.microtask(() async {
      if (isClosed || state is! FeedLoaded) return;

      final currentState = state as FeedLoaded;
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

        if (updatedProfiles.isNotEmpty) {
          add(feed_event.FeedProfilesLoaded(updatedProfiles));
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

          if (syncedProfiles.isNotEmpty) {
            add(feed_event.FeedProfilesLoaded(syncedProfiles));
          }
        }
      } catch (_) {}
    });
  }

  List<Map<String, dynamic>> _feedNotesToMaps(List<FeedNote> notes) {
    return notes.map((note) => note.toMap()).toList();
  }

  void _sortNotes(List<Map<String, dynamic>> notes, FeedSortMode mode) {
    notes.sort((a, b) {
      final aTime =
          a['repostCreatedAt'] as int? ?? a['created_at'] as int? ?? 0;
      final bTime =
          b['repostCreatedAt'] as int? ?? b['created_at'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });
  }

  void _watchListFeed(List<String> pubkeys, {int? limit}) {
    _feedSubscription?.cancel();
    _feedSubscription = _feedRepository
        .watchListFeed(pubkeys, limit: limit ?? _currentLimit)
        .listen(
      (notes) {
        if (isClosed) return;
        add(feed_event.FeedNotesUpdated(notes));
      },
      onError: (_) {
        if (isClosed) return;
        Future.delayed(const Duration(seconds: 2), () {
          if (!isClosed) _watchListFeed(pubkeys, limit: limit);
        });
      },
      onDone: () {
        if (isClosed) return;
        Future.delayed(const Duration(seconds: 2), () {
          if (!isClosed) _watchListFeed(pubkeys, limit: limit);
        });
      },
    );
  }

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

      Future.microtask(() async {
        if (isClosed) return;
        try {
          await _syncService.syncListFeed(event.pubkeys!);
          if (!isClosed) _watchListFeed(event.pubkeys!);
        } catch (_) {}
        if (!isClosed && state is FeedLoaded) {
          add(feed_event.FeedSyncCompleted());
        }
      });
    }
  }

  FollowSetService? _getFollowSetService() {
    try {
      return FollowSetService.instance;
    } catch (_) {
      return null;
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
