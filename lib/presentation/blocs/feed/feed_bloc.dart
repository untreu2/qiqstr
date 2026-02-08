import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/entities/feed_note.dart';
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
    on<feed_event.FeedSyncCompleted>(_onFeedSyncCompleted);
  }

  Future<void> _onFeedInitialized(
    feed_event.FeedInitialized event,
    Emitter<FeedState> emit,
  ) async {
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
      _watchHashtagFeed(event.hashtag!);
      _syncHashtagInBackground(event.hashtag!, emit);
    } else {
      _watchFeed(event.userHex);
      _syncInBackground(event.userHex, emit);
    }
  }

  void _watchFeed(String userHex, {int? limit}) {
    _feedSubscription?.cancel();
    _feedSubscription = _feedRepository
        .watchFeed(userHex, limit: limit ?? _currentLimit)
        .listen((notes) {
      if (isClosed) return;
      add(feed_event.FeedNotesUpdated(notes));
    });
  }

  void _watchHashtagFeed(String hashtag, {int? limit}) {
    _feedSubscription?.cancel();
    _feedSubscription = _feedRepository
        .watchHashtagFeed(hashtag, limit: limit ?? _currentLimit)
        .listen((notes) {
      if (isClosed) return;
      add(feed_event.FeedNotesUpdated(notes));
    });
  }

  void _syncHashtagInBackground(String hashtag, Emitter<FeedState>? emit) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncHashtag(hashtag);
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

    emit(currentState.copyWith(notes: sortedNotes));
    _loadProfilesForNotes(sortedNotes);
  }

  void _syncInBackground(String userHex, Emitter<FeedState>? emit) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncFollowingList(userHex);
        if (isClosed) return;
        _watchFeed(userHex);
        await _syncService.syncFeed(userHex);
        if (isClosed) return;
        await _syncService.startRealtimeSubscriptions(userHex);
      } catch (_) {}
      if (!isClosed && state is FeedLoaded) {
        add(feed_event.FeedSyncCompleted());
      }
    });
  }

  Future<void> _onFeedRefreshed(
    feed_event.FeedRefreshed event,
    Emitter<FeedState> emit,
  ) async {
    if (_currentUserHex == null) return;
    _currentLimit = _pageSize;

    final currentState = state;
    if (currentState is FeedLoaded && currentState.hashtag != null) {
      try {
        await _syncService.syncHashtag(currentState.hashtag!, force: true);
      } catch (_) {}
    } else {
      try {
        await _syncService.syncFeed(_currentUserHex!, force: true);
      } catch (_) {}
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
    emit(currentState.copyWith(isLoadingMore: true));

    try {
      _currentLimit += _pageSize;

      _feedSubscription?.cancel();

      if (currentState.hashtag != null) {
        _feedSubscription = _feedRepository
            .watchHashtagFeed(currentState.hashtag!, limit: _currentLimit)
            .listen((notes) {
          if (isClosed) return;
          add(feed_event.FeedNotesUpdated(notes));
        });
      } else if (_currentUserHex != null) {
        _feedSubscription = _feedRepository
            .watchFeed(_currentUserHex!, limit: _currentLimit)
            .listen((notes) {
          if (isClosed) return;
          add(feed_event.FeedNotesUpdated(notes));
        });
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

    if (event.hashtag != null) {
      emit(currentState.copyWith(
          hashtag: event.hashtag, notes: const [], isSyncing: true));
      _watchHashtagFeed(event.hashtag!);
      _syncHashtagInBackground(event.hashtag!, null);
    } else {
      emit(currentState.copyWith(
          hashtag: null, notes: const [], isSyncing: true));
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
      final authorIds = notes
          .map((n) => n['pubkey'] as String? ?? '')
          .where(
              (id) => id.isNotEmpty && !currentState.profiles.containsKey(id))
          .toSet()
          .toList();

      if (authorIds.isEmpty) return;

      try {
        final profiles = await _profileRepository.getProfiles(authorIds);
        if (isClosed) return;

        final updatedProfiles = <String, Map<String, dynamic>>{};
        for (final entry in profiles.entries) {
          updatedProfiles[entry.key] = entry.value.toMap();
        }

        if (updatedProfiles.isNotEmpty) {
          add(feed_event.FeedProfilesLoaded(updatedProfiles));
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
