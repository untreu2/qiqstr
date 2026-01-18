import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/feed_loader_service.dart';
import 'feed_event.dart' as feed_event;
import 'feed_state.dart';

class FeedBloc extends Bloc<feed_event.FeedEvent, FeedState> {
  final NoteRepository _noteRepository;
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final FeedLoaderService _feedLoader;

  static const int _pageSize = 100;
  bool _isLoadingFeed = false;
  bool _isSubscribedToUserNotes = false;
  String? _currentUserHex;
  final List<StreamSubscription> _subscriptions = [];

  FeedBloc({
    required NoteRepository noteRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required FeedLoaderService feedLoader,
  })  : _noteRepository = noteRepository,
        _authRepository = authRepository,
        _userRepository = userRepository,
        _feedLoader = feedLoader,
        super(const FeedInitial()) {
    on<feed_event.FeedInitialized>(_onFeedInitialized);
    on<feed_event.FeedRefreshed>(_onFeedRefreshed);
    on<feed_event.FeedLoadMoreRequested>(_onFeedLoadMoreRequested);
    on<feed_event.FeedViewModeChanged>(_onFeedViewModeChanged);
    on<feed_event.FeedSortModeChanged>(_onFeedSortModeChanged);
    on<feed_event.FeedHashtagChanged>(_onFeedHashtagChanged);
    on<feed_event.FeedUserProfileUpdated>(_onFeedUserProfileUpdated);
    on<feed_event.FeedNoteDeleted>(_onFeedNoteDeleted);
  }

  Future<void> _onFeedInitialized(
    feed_event.FeedInitialized event,
    Emitter<FeedState> emit,
  ) async {
    emit(const FeedLoading());

    final currentUserHex = _authRepository.npubToHex(event.npub);
    if (currentUserHex == null) {
      emit(const FeedError('Could not convert npub to hex'));
      return;
    }

    _currentUserHex = currentUserHex;

    final currentState = state is FeedLoaded
        ? (state as FeedLoaded)
        : FeedLoaded(
            notes: const [],
            profiles: const {},
            currentUserNpub: event.npub,
            hashtag: event.hashtag,
          );

    emit(currentState);

    await _loadFeed(emit, event.npub, event.hashtag, skipCache: false);
    await _loadCurrentUserProfile(emit, event.npub);

    _subscribeToDeletions(emit);
    _subscribeToUserNotes(emit, event.npub, event.hashtag);
    _subscribeToCurrentUserStream(emit, event.npub);
  }

  Future<void> _onFeedRefreshed(
    feed_event.FeedRefreshed event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;

    final currentState = state as FeedLoaded;
    if (_isLoadingFeed) return;

    await _loadFeed(emit, currentState.currentUserNpub, currentState.hashtag, skipCache: false);
    await _loadCurrentUserProfile(emit, currentState.currentUserNpub);
  }

  Future<void> _onFeedLoadMoreRequested(
    feed_event.FeedLoadMoreRequested event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;

    final currentState = state as FeedLoaded;
    if (_isLoadingFeed || currentState.isLoadingMore || !currentState.canLoadMore) return;

    emit(currentState.copyWith(isLoadingMore: true));

    final currentNotes = currentState.notes;
    if (currentNotes.isEmpty) {
      emit(currentState.copyWith(isLoadingMore: false));
      return;
    }

    final oldestNote = currentNotes.reduce((a, b) {
      final aIsRepost = a['isRepost'] as bool? ?? false;
      final aRepostTimestamp = a['repostTimestamp'] as DateTime?;
      final aTimestamp = a['timestamp'] as DateTime? ?? DateTime(2000);
      final aTime = aIsRepost ? (aRepostTimestamp ?? aTimestamp) : aTimestamp;

      final bIsRepost = b['isRepost'] as bool? ?? false;
      final bRepostTimestamp = b['repostTimestamp'] as DateTime?;
      final bTimestamp = b['timestamp'] as DateTime? ?? DateTime(2000);
      final bTime = bIsRepost ? (bRepostTimestamp ?? bTimestamp) : bTimestamp;

      return aTime.isBefore(bTime) ? a : b;
    });

    final oldestIsRepost = oldestNote['isRepost'] as bool? ?? false;
    final oldestRepostTimestamp = oldestNote['repostTimestamp'] as DateTime?;
    final oldestTimestamp = oldestNote['timestamp'] as DateTime? ?? DateTime(2000);
    final oldestTime = oldestIsRepost ? (oldestRepostTimestamp ?? oldestTimestamp) : oldestTimestamp;
    final until = oldestTime.subtract(const Duration(milliseconds: 100));

    final feedType = currentState.hashtag != null ? FeedType.hashtag : FeedType.feed;
    final params = FeedLoadParams(
      type: feedType,
      currentUserNpub: currentState.currentUserNpub,
      hashtag: currentState.hashtag,
      limit: _pageSize,
      until: until,
      skipCache: true,
    );

    final result = await _feedLoader.loadFeed(params);

    if (result.isSuccess && result.notes.isNotEmpty) {
      final currentIds = currentNotes.map((n) => n['id'] as String? ?? '').where((id) => id.isNotEmpty).toSet();
      final uniqueNewNotes = result.notes.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentIds.contains(noteId);
      }).toList();

      if (uniqueNewNotes.isNotEmpty) {
        final updatedNotes = [...currentNotes, ...uniqueNewNotes];
        final sortedNotes = _feedLoader.sortNotes(updatedNotes, currentState.sortMode);

        emit(currentState.copyWith(
          notes: sortedNotes,
          isLoadingMore: false,
        ));

        _feedLoader.loadProfilesAndInteractionsForNotes(
          uniqueNewNotes,
          Map.from(currentState.profiles),
          (profiles) {
            if (state is FeedLoaded) {
              final updatedState = state as FeedLoaded;
              emit(updatedState.copyWith(profiles: profiles));
            }
          },
        );
      } else {
        emit(currentState.copyWith(isLoadingMore: false));
      }
    } else {
      emit(currentState.copyWith(isLoadingMore: false));
    }
  }

  void _onFeedViewModeChanged(
    feed_event.FeedViewModeChanged event,
    Emitter<FeedState> emit,
  ) {
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      final viewMode = event.mode == feed_event.NoteViewMode.list ? NoteViewMode.list : NoteViewMode.grid;
      emit(currentState.copyWith(viewMode: viewMode));
    }
  }

  void _onFeedSortModeChanged(
    feed_event.FeedSortModeChanged event,
    Emitter<FeedState> emit,
  ) {
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      final sortedNotes = _feedLoader.sortNotes(List.from(currentState.notes), event.mode);
      emit(currentState.copyWith(notes: sortedNotes, sortMode: event.mode));
    }
  }

  Future<void> _onFeedHashtagChanged(
    feed_event.FeedHashtagChanged event,
    Emitter<FeedState> emit,
  ) async {
    if (state is! FeedLoaded) return;

    final currentState = state as FeedLoaded;
    emit(currentState.copyWith(hashtag: event.hashtag));

    await _loadFeed(emit, currentState.currentUserNpub, event.hashtag, skipCache: false);
  }

  void _onFeedUserProfileUpdated(
    feed_event.FeedUserProfileUpdated event,
    Emitter<FeedState> emit,
  ) {
    if (state is FeedLoaded) {
      final currentState = state as FeedLoaded;
      final updatedProfiles = Map<String, Map<String, dynamic>>.from(currentState.profiles);
      final existingProfile = updatedProfiles[event.userId];
      final existingImage = existingProfile?['profileImage'] as String? ?? '';
      if (!updatedProfiles.containsKey(event.userId) || existingImage.isEmpty) {
        updatedProfiles[event.userId] = event.user;
        emit(currentState.copyWith(profiles: updatedProfiles));
      }
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
      if (updatedNotes.length != currentState.notes.length) {
        emit(currentState.copyWith(notes: updatedNotes));
      }
    }
  }

  Future<void> _loadFeed(
    Emitter<FeedState> emit,
    String npub,
    String? hashtag, {
    bool skipCache = false,
  }) async {
    if (_isLoadingFeed) return;

    _isLoadingFeed = true;

    try {
      final feedType = hashtag != null ? FeedType.hashtag : FeedType.feed;
      final params = FeedLoadParams(
        type: feedType,
        currentUserNpub: npub,
        hashtag: hashtag,
        limit: _pageSize,
        skipCache: skipCache,
      );

      final currentState = state is FeedLoaded ? (state as FeedLoaded) : null;
      if (currentState == null || currentState.notes.isEmpty) {
        emit(const FeedLoading());
      }

      final result = await _feedLoader.loadFeed(params);

      if (result.isSuccess) {
        if (result.notes.isEmpty) {
          final existingState = state is FeedLoaded ? (state as FeedLoaded) : null;
          if (existingState == null || existingState.notes.isEmpty) {
            emit(FeedLoaded(
              notes: const [],
              profiles: const {},
              currentUserNpub: npub,
              hashtag: hashtag,
            ));
          }
        } else {
          final sortedNotes = _feedLoader.sortNotes(result.notes, FeedSortMode.latest);
          final existingState = state is FeedLoaded ? (state as FeedLoaded) : null;
          final sortMode = existingState?.sortMode ?? FeedSortMode.latest;

          final finalSortedNotes = sortMode != FeedSortMode.latest ? _feedLoader.sortNotes(sortedNotes, sortMode) : sortedNotes;

          final currentNotes = existingState?.notes ?? [];
          final mergedNotes = currentNotes.isEmpty || skipCache
              ? finalSortedNotes
              : _feedLoader.mergeNotesWithUpdates(
                  currentNotes,
                  finalSortedNotes,
                  sortMode,
                );

          final finalNotes = mergedNotes.length >= currentNotes.length ? mergedNotes : currentNotes;

          emit(FeedLoaded(
            notes: finalNotes,
            profiles: existingState?.profiles ?? const {},
            currentUserNpub: npub,
            hashtag: hashtag,
            sortMode: sortMode,
            viewMode: existingState?.viewMode ?? NoteViewMode.list,
          ));

          _feedLoader.loadProfilesAndInteractionsForNotes(
            finalNotes,
            existingState?.profiles ?? const {},
            (profiles) {
              if (state is FeedLoaded) {
                final updatedState = state as FeedLoaded;
                emit(updatedState.copyWith(profiles: profiles));
              }
            },
          );
        }
      } else {
        final existingState = state is FeedLoaded ? (state as FeedLoaded) : null;
        if (existingState == null || existingState.notes.isEmpty) {
          emit(FeedError(result.error ?? 'Failed to load feed'));
        }
      }
    } catch (e) {
      final existingState = state is FeedLoaded ? (state as FeedLoaded) : null;
      if (existingState == null || existingState.notes.isEmpty) {
        emit(FeedError('Failed to load feed: ${e.toString()}'));
      }
    } finally {
      _isLoadingFeed = false;
    }
  }

  Future<void> _loadCurrentUserProfile(Emitter<FeedState> emit, String npub) async {
    if (state is! FeedLoaded) return;

    final currentState = state as FeedLoaded;
    if (currentState.profiles.containsKey(npub)) {
      final existingUser = currentState.profiles[npub];
      final existingImage = existingUser?['profileImage'] as String? ?? '';
      if (existingUser != null && existingImage.isNotEmpty) {
        return;
      }
    }

    final userResult = await _userRepository.getUserProfile(npub);
    userResult.fold(
      (user) {
        if (state is FeedLoaded) {
          final updatedState = state as FeedLoaded;
          final updatedProfiles = Map<String, Map<String, dynamic>>.from(updatedState.profiles);
          updatedProfiles[npub] = user;
          emit(updatedState.copyWith(profiles: updatedProfiles));
        }
      },
      (error) {},
    );
  }

  void _subscribeToDeletions(Emitter<FeedState> emit) {
    _subscriptions.add(
      _noteRepository.nostrDataService.noteDeletedStream.listen((deletedNoteId) {
        add(feed_event.FeedNoteDeleted(deletedNoteId));
      }),
    );
  }

  void _subscribeToUserNotes(
    Emitter<FeedState> emit,
    String npub,
    String? hashtag,
  ) {
    if (_isSubscribedToUserNotes || _currentUserHex == null) return;

    _isSubscribedToUserNotes = true;

    _subscriptions.add(
      _noteRepository.notesStream.listen((allNotes) {
        if (state is! FeedLoaded) return;

        final currentState = state as FeedLoaded;
        final currentNoteIds = currentState.notes.map((n) => n['id'] as String? ?? '').where((id) => id.isNotEmpty).toSet();

        final userNewNotes = allNotes.where((note) {
          final noteAuthor = note['author'] as String? ?? '';
          final noteAuthorHex = _authRepository.npubToHex(noteAuthor);
          final isUserNote = noteAuthorHex != null && noteAuthorHex == _currentUserHex;

          final isRepost = note['isRepost'] as bool? ?? false;
          final repostedBy = note['repostedBy'] as String?;
          final isUserRepost = isRepost && repostedBy != null && repostedBy.isNotEmpty;
          String? repostedByHex;
          if (isUserRepost) {
            final repostedByValue = repostedBy;
            repostedByHex = repostedByValue.length == 64 ? repostedByValue : _authRepository.npubToHex(repostedByValue);
            repostedByHex = repostedByHex ?? repostedByValue;
          }
          final isUserRepostMatch = isUserRepost && repostedByHex == _currentUserHex;

          final noteId = note['id'] as String? ?? '';
          final isNew = noteId.isNotEmpty && !currentNoteIds.contains(noteId);

          final tTags = note['tTags'] as List<dynamic>? ?? [];
          final tTagsList = tTags.map((tag) => tag.toString().toLowerCase()).toList();
          final matchesFeed = hashtag == null || tTagsList.contains(hashtag.toLowerCase());

          return (isUserNote || isUserRepostMatch) && isNew && matchesFeed;
        }).toList();

        if (userNewNotes.isNotEmpty) {
          final updatedNotes = [...userNewNotes, ...currentState.notes];

          final seenIds = <String>{};
          final deduplicatedNotes = <Map<String, dynamic>>[];
          for (final note in updatedNotes) {
            final noteId = note['id'] as String? ?? '';
            if (noteId.isNotEmpty && !seenIds.contains(noteId)) {
              seenIds.add(noteId);
              deduplicatedNotes.add(note);
            }
          }

          add(feed_event.FeedRefreshed());
        }
      }),
    );

    _subscriptions.add(
      _noteRepository.realTimeNotesStream.listen((allNotes) {
        if (state is! FeedLoaded) return;

        final currentState = state as FeedLoaded;
        final currentNoteIds = currentState.notes.map((n) => n['id'] as String? ?? '').where((id) => id.isNotEmpty).toSet();

        final userNewNotes = allNotes.where((note) {
          final noteAuthor = note['author'] as String? ?? '';
          final noteAuthorHex = _authRepository.npubToHex(noteAuthor);
          final isUserNote = noteAuthorHex != null && noteAuthorHex == _currentUserHex;

          final isRepost = note['isRepost'] as bool? ?? false;
          final repostedBy = note['repostedBy'] as String?;
          final isUserRepost = isRepost && repostedBy != null && repostedBy.isNotEmpty;
          String? repostedByHex;
          if (isUserRepost) {
            final repostedByValue = repostedBy;
            repostedByHex = repostedByValue.length == 64 ? repostedByValue : _authRepository.npubToHex(repostedByValue);
            repostedByHex = repostedByHex ?? repostedByValue;
          }
          final isUserRepostMatch = isUserRepost && repostedByHex == _currentUserHex;

          final noteId = note['id'] as String? ?? '';
          final isNew = noteId.isNotEmpty && !currentNoteIds.contains(noteId);

          final tTags = note['tTags'] as List<dynamic>? ?? [];
          final tTagsList = tTags.map((tag) => tag.toString().toLowerCase()).toList();
          final matchesFeed = hashtag == null || tTagsList.contains(hashtag.toLowerCase());

          return (isUserNote || isUserRepostMatch) && isNew && matchesFeed;
        }).toList();

        if (userNewNotes.isNotEmpty) {
          final updatedNotes = [...userNewNotes, ...currentState.notes];

          final seenIds = <String>{};
          final deduplicatedNotes = <Map<String, dynamic>>[];
          for (final note in updatedNotes) {
            final noteId = note['id'] as String? ?? '';
            if (noteId.isNotEmpty && !seenIds.contains(noteId)) {
              seenIds.add(noteId);
              deduplicatedNotes.add(note);
            }
          }

          add(feed_event.FeedRefreshed());
        }
      }),
    );
  }

  void _subscribeToCurrentUserStream(Emitter<FeedState> emit, String npub) {
    _subscriptions.add(
      _userRepository.currentUserStream.listen((updatedUser) {
        if (state is FeedLoaded) {
          final currentState = state as FeedLoaded;
          final updatedProfiles = Map<String, Map<String, dynamic>>.from(currentState.profiles);
          final userNpub = updatedUser['npub'] as String? ?? npub;
          updatedProfiles[userNpub] = updatedUser;
          emit(currentState.copyWith(profiles: updatedProfiles));
        }
      }),
    );
  }

  @override
  Future<void> close() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
