import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';

class FeedViewModel extends BaseViewModel with CommandMixin {
  final NoteRepository _noteRepository;
  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  FeedViewModel({
    required NoteRepository noteRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
  })  : _noteRepository = noteRepository,
        _authRepository = authRepository,
        _userRepository = userRepository;

  UIState<List<NoteModel>> _feedState = const InitialState();
  UIState<List<NoteModel>> get feedState => _feedState;

  UIState<String> _currentUserState = const InitialState();
  UIState<String> get currentUserState => _currentUserState;

  final Map<String, UserModel> _profiles = {};
  Map<String, UserModel> get profiles => Map.unmodifiable(_profiles);

  final StreamController<Map<String, UserModel>> _profilesController = StreamController<Map<String, UserModel>>.broadcast();
  Stream<Map<String, UserModel>> get profilesStream => _profilesController.stream;

  NoteViewMode _viewMode = NoteViewMode.list;
  NoteViewMode get viewMode => _viewMode;

  FeedSortMode _sortMode = FeedSortMode.latest;
  FeedSortMode get sortMode => _sortMode;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  String _currentUserNpub = '';
  String get currentUserNpub => _currentUserNpub;

  String? _hashtag;
  String? get hashtag => _hashtag;
  bool get isHashtagMode => _hashtag != null;

  bool _isInitialized = false;
  bool _isLoadingFeed = false;

  final List<NoteModel> _pendingNotes = [];
  int get pendingNotesCount => _pendingNotes.length;

  int _currentLimit = 200;
  int get currentLimit => _currentLimit;

  RefreshFeedCommand? _refreshFeedCommand;
  LoadMoreFeedCommand? _loadMoreFeedCommand;
  ChangeViewModeCommand? _changeViewModeCommand;

  RefreshFeedCommand get refreshFeedCommand => _refreshFeedCommand ??= RefreshFeedCommand(this);
  LoadMoreFeedCommand get loadMoreFeedCommand => _loadMoreFeedCommand ??= LoadMoreFeedCommand(this);
  ChangeViewModeCommand get changeViewModeCommand => _changeViewModeCommand ??= ChangeViewModeCommand(this);

  @override
  void initialize() {
    super.initialize();

    registerCommand('refreshFeed', refreshFeedCommand);
    registerCommand('loadMoreFeed', loadMoreFeedCommand);
    registerCommand('changeViewMode', changeViewModeCommand);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentUser();
    });
  }

  void initializeWithUser(String npub, {String? hashtag}) {
    if (_isInitialized && _currentUserNpub == npub && _hashtag == hashtag) {
      debugPrint('[FeedViewModel] Already initialized for $npub (hashtag: $hashtag), skipping');
      return;
    }

    debugPrint('[FeedViewModel] Initializing with user: $npub (hashtag: ${hashtag ?? "none"})');
    _currentUserNpub = npub;
    _hashtag = hashtag;
    _isInitialized = true;

    _loadFeed();
  }

  Future<void> _loadCurrentUser() async {
    await executeOperation('loadCurrentUser', () async {
      _currentUserState = const LoadingState();
      safeNotifyListeners();

      final result = await _authRepository.getCurrentUserNpub();

      result.fold(
        (npub) {
          if (npub != null && npub.isNotEmpty) {
            _currentUserNpub = npub;
            _currentUserState = LoadedState(npub);
            _loadFeed();
            _subscribeToRealTimeUpdates();
          } else {
            _currentUserState = const ErrorState('User not authenticated');
          }
        },
        (error) => _currentUserState = ErrorState(error),
      );

      safeNotifyListeners();
    }, showLoading: false);
  }

  Future<void> _loadFeed() async {
    if (_currentUserNpub.isEmpty && !isHashtagMode) {
      debugPrint(' [FeedViewModel] Cannot load feed - no current user npub');
      return;
    }

    if (_isLoadingFeed) {
      debugPrint('⏭ [FeedViewModel] Already loading feed, skipping');
      return;
    }

    _isLoadingFeed = true;

    if (isHashtagMode) {
      debugPrint('[FeedViewModel] Loading hashtag feed for: #$_hashtag');
      await _loadHashtagFeed();
    } else {
      debugPrint('[FeedViewModel] Loading feed for user: $_currentUserNpub');
      await _loadUserFeed();
    }

    _isLoadingFeed = false;
  }

  Future<void> _loadUserFeed() async {
    await executeOperation('loadFeed', () async {
      _feedState = const LoadingState();
      safeNotifyListeners();

      debugPrint('[FeedViewModel] Requesting feed notes from repository with limit: $_currentLimit');

      final result = await _noteRepository.getFeedNotesFromFollowList(
        currentUserNpub: _currentUserNpub,
        limit: _currentLimit,
      );

      await result.fold(
        (notes) async {
          debugPrint('[FeedViewModel] Repository returned ${notes.length} notes');

          if (notes.isEmpty) {
            debugPrint('[FeedViewModel] Empty feed - user may not be following anyone');
            _feedState = const LoadedState(<NoteModel>[]);
          } else {
            debugPrint('[FeedViewModel] Setting loaded state with ${notes.length} real notes');
            final sortedNotes = _sortNotes(notes);
            _feedState = LoadedState(sortedNotes);

            await _loadUserProfilesForNotes(sortedNotes);
          }

          _subscribeToRealTimeUpdates();
        },
        (error) async {
          debugPrint('[FeedViewModel] Error loading feed: $error');
          _feedState = ErrorState(error);
        },
      );

      safeNotifyListeners();
    });
  }

  Future<void> _loadHashtagFeed() async {
    await executeOperation('loadHashtagFeed', () async {
      _feedState = const LoadingState();
      safeNotifyListeners();

      debugPrint('[FeedViewModel] Requesting hashtag notes from repository for: #$_hashtag with limit: $_currentLimit');

      final result = await _noteRepository.getHashtagNotes(
        hashtag: _hashtag!,
        limit: _currentLimit,
      );

      await result.fold(
        (notes) async {
          debugPrint('[FeedViewModel] Repository returned ${notes.length} notes for #$_hashtag');

          if (notes.isEmpty) {
            debugPrint('[FeedViewModel] No notes found for hashtag: #$_hashtag');
            _feedState = const LoadedState(<NoteModel>[]);
          } else {
            debugPrint('[FeedViewModel] Setting loaded state with ${notes.length} hashtag notes');
            final sortedNotes = _sortNotes(notes);
            _feedState = LoadedState(sortedNotes);

            await _loadUserProfilesForNotes(sortedNotes);
          }
        },
        (error) async {
          debugPrint('[FeedViewModel] Error loading hashtag feed: $error');
          _feedState = ErrorState(error);
        },
      );

      safeNotifyListeners();
    });
  }

  Future<void> refreshFeed() async {
    await _loadFeed();
  }

  Future<void> loadMoreNotes() async {
    if (_isLoadingMore || _feedState is! LoadedState<List<NoteModel>>) return;

    _isLoadingMore = true;
    safeNotifyListeners();

    try {
      _currentLimit += 50;
      debugPrint('[FeedViewModel] Loading more notes with new limit: $_currentLimit');

      final result = isHashtagMode
          ? await _noteRepository.getHashtagNotes(
              hashtag: _hashtag!,
              limit: _currentLimit,
            )
          : await _noteRepository.getFeedNotesFromFollowList(
              currentUserNpub: _currentUserNpub,
              limit: _currentLimit,
            );

      result.fold(
        (notes) {
          if (notes.isNotEmpty) {
            final sortedNotes = _sortNotes(notes);
            _feedState = LoadedState(sortedNotes);
            _loadUserProfilesForNotes(notes);
            safeNotifyListeners();
          }
        },
        (error) => setError(NetworkError(message: 'Failed to load more notes: $error')),
      );
    } finally {
      _isLoadingMore = false;
      safeNotifyListeners();
    }
  }

  void changeViewMode(NoteViewMode mode) {
    if (_viewMode != mode) {
      _viewMode = mode;
      safeNotifyListeners();
    }
  }

  void toggleSortMode() {
    _sortMode = _sortMode == FeedSortMode.latest ? FeedSortMode.mostInteracted : FeedSortMode.latest;

    if (_feedState is LoadedState<List<NoteModel>>) {
      final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;
      final sortedNotes = _sortNotes(List.from(currentNotes));
      _feedState = LoadedState(sortedNotes);
    }

    safeNotifyListeners();
  }

  List<NoteModel> _sortNotes(List<NoteModel> notes) {
    if (_sortMode == FeedSortMode.mostInteracted) {
      notes.sort((a, b) {
        int scoreA = a.reactionCount + a.repostCount + a.replyCount + (a.zapAmount ~/ 1000);
        int scoreB = b.reactionCount + b.repostCount + b.replyCount + (b.zapAmount ~/ 1000);

        if (scoreA == scoreB) {
          return b.timestamp.compareTo(a.timestamp);
        }

        return scoreB.compareTo(scoreA);
      });
    } else {
      notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    return notes;
  }

  void _subscribeToRealTimeUpdates() {
    if (isHashtagMode) {
      debugPrint('[FeedViewModel] Skipping real-time updates in hashtag mode');
      return;
    }

    debugPrint('[FeedViewModel] Setting up real-time updates for user: $_currentUserNpub');

    addSubscription(
      _noteRepository.realTimeNotesStream.listen((notes) {
        debugPrint('[FeedViewModel] Received stream update: ${notes.length} notes');

        if (!isDisposed && _feedState.isLoaded) {
          if (notes.isNotEmpty) {
            final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;

            if (currentNotes.isEmpty) {
              debugPrint('[FeedViewModel] Feed is empty, adding ${notes.length} new notes directly');
              _feedState = LoadedState(notes);
              _loadUserProfilesForNotes(notes);
              safeNotifyListeners();
            } else {
              final latestCurrentNote = currentNotes.first;
              final newerNotes = notes.where((note) => note.timestamp.isAfter(latestCurrentNote.timestamp)).toList();

              if (newerNotes.isNotEmpty) {
                debugPrint('[FeedViewModel] Adding ${newerNotes.length} newer notes to pending list');

                for (final note in newerNotes) {
                  if (!_pendingNotes.any((n) => n.id == note.id)) {
                    _pendingNotes.add(note);
                  }
                }

                _pendingNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                safeNotifyListeners();
              }
            }
          } else {
            debugPrint('[FeedViewModel] Ignoring empty stream update to preserve loaded state');
          }
        } else {
          debugPrint('[FeedViewModel] Not updating - disposed: $isDisposed, feedState: ${_feedState.runtimeType}');
        }
      }),
    );
  }

  void addPendingNotesToFeed() {
    if (_pendingNotes.isEmpty || _feedState is! LoadedState<List<NoteModel>>) return;

    debugPrint('[FeedViewModel] Adding ${_pendingNotes.length} pending notes to feed');

    final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;

    final allNotes = [..._pendingNotes, ...currentNotes];

    final sortedNotes = _sortNotes(allNotes);

    _feedState = LoadedState(sortedNotes);

    _loadUserProfilesForNotes(_pendingNotes);

    _pendingNotes.clear();

    safeNotifyListeners();
  }

  List<NoteModel> get currentNotes {
    return _feedState.data ?? [];
  }

  bool get canLoadMore => _feedState.isLoaded && !_isLoadingMore;

  bool get isEmpty => _feedState.isEmpty;

  bool get isFeedLoading => _feedState.isLoading;

  String? get errorMessage => _feedState.error;

  Future<void> _loadUserProfilesForNotes(List<NoteModel> notes) async {
    try {
      debugPrint('[FeedViewModel] Loading user profiles for ${notes.length} notes');

      final Set<String> authorIds = {};
      for (final note in notes) {
        authorIds.add(note.author);
        if (note.repostedBy != null) {
          authorIds.add(note.repostedBy!);
        }
      }

      debugPrint('[FeedViewModel] Found ${authorIds.length} unique authors to load');

      final missingAuthorIds = authorIds.where((id) {
        final cachedProfile = _profiles[id];
        return cachedProfile == null || cachedProfile.profileImage.isEmpty;
      }).toList();

      if (missingAuthorIds.isEmpty) {
        debugPrint('[FeedViewModel] All profiles already cached with images');
        return;
      }

      debugPrint('[FeedViewModel] Batch fetching ${missingAuthorIds.length} profiles (including those with missing images)');

      final results = await _userRepository.getUserProfiles(
        missingAuthorIds,
        priority: FetchPriority.high,
      );

      for (final entry in results.entries) {
        entry.value.fold(
          (user) {
            _profiles[entry.key] = user;
            debugPrint('[FeedViewModel]  Loaded profile: ${user.name} (image: ${user.profileImage.isNotEmpty ? "✓" : "✗"})');
          },
          (error) {
            if (!_profiles.containsKey(entry.key)) {
              _profiles[entry.key] = UserModel(
                pubkeyHex: entry.key,
                name: entry.key.length > 8 ? entry.key.substring(0, 8) : entry.key,
                about: '',
                profileImage: '',
                banner: '',
                website: '',
                nip05: '',
                lud16: '',
                updatedAt: DateTime.now(),
                nip05Verified: false,
              );
              debugPrint('[FeedViewModel] ️ Created fallback profile for ${entry.key.substring(0, 8)}');
            }
          },
        );
      }

      _profilesController.add(Map.from(_profiles));

      debugPrint('[FeedViewModel]  Profile batch loading complete, total cached: ${_profiles.length}');
    } catch (e) {
      debugPrint('[FeedViewModel]  Error loading user profiles: $e');
    }
  }

  @override
  void onRetry() {
    _loadFeed();
  }

  @override
  void dispose() {
    _profilesController.close();
    super.dispose();
  }
}

class RefreshFeedCommand extends ParameterlessCommand {
  final FeedViewModel _viewModel;

  RefreshFeedCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.refreshFeed();
}

class LoadMoreFeedCommand extends ParameterlessCommand {
  final FeedViewModel _viewModel;

  LoadMoreFeedCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.loadMoreNotes();
}

class ChangeViewModeCommand extends ParameterizedCommand<NoteViewMode> {
  final FeedViewModel _viewModel;

  ChangeViewModeCommand(this._viewModel);

  @override
  Future<void> executeImpl(NoteViewMode mode) async {
    _viewModel.changeViewMode(mode);
  }
}

enum NoteViewMode {
  list,
  grid,
}

enum FeedSortMode {
  latest,
  mostInteracted,
}
