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
import '../../data/services/nostr_data_service.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';

class FeedViewModel extends BaseViewModel with CommandMixin {
  final NoteRepository _noteRepository;
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final NostrDataService _nostrDataService;

  FeedViewModel({
    required NoteRepository noteRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required NostrDataService nostrDataService,
  })  : _noteRepository = noteRepository,
        _authRepository = authRepository,
        _userRepository = userRepository,
        _nostrDataService = nostrDataService;

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
  int get pendingNotesCount => 0;

  int _currentLimit = 50;
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
      return;
    }

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
            _loadFeedWithFollowListWait();
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

  Future<void> _loadFeedWithFollowListWait() async {
    if (_currentUserNpub.isEmpty && !isHashtagMode) {
      return;
    }

    if (_isLoadingFeed) {
      return;
    }

    _isLoadingFeed = true;

    try {
      if (isHashtagMode) {
        await _loadHashtagFeed();
      } else {
        await _loadUserFeed();
      }
    } catch (e) {
      debugPrint('[FeedViewModel] Error in feed loading: $e');
      _feedState = ErrorState('Failed to load feed: $e');
      safeNotifyListeners();
    } finally {
      _isLoadingFeed = false;
    }
  }

  Future<void> _loadFeed() async {
    await _loadFeedWithFollowListWait();
  }

  Future<void> _loadUserFeed() async {
    await executeOperation('loadFeed', () async {
      _feedState = const LoadingState();
      safeNotifyListeners();

      _nostrDataService.setContext('feed');

      final result = await _noteRepository.getFeedNotesFromFollowList(
        currentUserNpub: _currentUserNpub,
        limit: _currentLimit,
      );

      await result.fold(
        (notes) async {
          if (notes.isEmpty) {
            _feedState = const LoadedState(<NoteModel>[]);
          } else {
            final sortedNotes = _sortNotes(notes);
            _feedState = LoadedState(sortedNotes);

            await _loadUserProfilesForNotes(sortedNotes);
          }

          _subscribeToRealTimeUpdates();
        },
        (error) async {
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

      _nostrDataService.setContext('hashtag');

      final result = await _noteRepository.getHashtagNotes(
        hashtag: _hashtag!,
        limit: _currentLimit,
      );

      await result.fold(
        (notes) async {
          if (notes.isEmpty) {
            _feedState = const LoadedState(<NoteModel>[]);
          } else {
            final sortedNotes = _sortNotes(notes);
            _feedState = LoadedState(sortedNotes);

            await _loadUserProfilesForNotes(sortedNotes);
          }
        },
        (error) async {
          _feedState = ErrorState(error);
        },
      );

      safeNotifyListeners();
    });
  }

  Future<void> refreshFeed() async {
    _isLoadingFeed = false;
    await _loadFeedWithFollowListWait();
  }

  Future<void> loadMoreNotes() async {
    if (_isLoadingMore || _feedState is! LoadedState<List<NoteModel>>) return;

    _isLoadingMore = true;
    safeNotifyListeners();

    try {
      _currentLimit += 50;

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

  Timer? _updateDebounceTimer;
  static const Duration _updateDebounceDelay = Duration(milliseconds: 250);

  void _subscribeToRealTimeUpdates() {
    if (isHashtagMode) {
      return;
    }

    addSubscription(
      _noteRepository.realTimeNotesStream.listen((notes) {
        if (!isDisposed && _feedState.isLoaded && notes.isNotEmpty) {
          _updateDebounceTimer?.cancel();
          _updateDebounceTimer = Timer(_updateDebounceDelay, () {
            _processRealTimeNotes(notes);
          });
        }
      }),
    );
  }

  void _processRealTimeNotes(List<NoteModel> notes) {
    if (isDisposed) return;

    final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;

    if (currentNotes.isEmpty) {
      _feedState = LoadedState(notes);
      _loadUserProfilesForNotes(notes);
      safeNotifyListeners();
      return;
    }

    final latestCurrentNote = currentNotes.first;
    final newerNotes = notes
        .where((note) => note.timestamp.isAfter(latestCurrentNote.timestamp) && !currentNotes.any((existing) => existing.id == note.id))
        .toList();

    if (newerNotes.isEmpty) return;

    final userNotes = newerNotes.where((note) => note.author == _currentUserNpub).toList();
    final otherNotes = newerNotes.where((note) => note.author != _currentUserNpub).toList();

    bool shouldUpdate = false;

    if (userNotes.isNotEmpty) {
      final allNotes = [...userNotes, ...currentNotes];
      final sortedNotes = _sortNotes(allNotes);
      _feedState = LoadedState(sortedNotes);
      _loadUserProfilesForNotes(userNotes);
      shouldUpdate = true;
    }

    if (otherNotes.isNotEmpty) {
      final newPendingNotes = otherNotes.where((note) => !_pendingNotes.any((n) => n.id == note.id)).toList();

      if (newPendingNotes.isNotEmpty) {
        _pendingNotes.addAll(newPendingNotes);
        _pendingNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (_pendingNotes.length > 50) {
          _pendingNotes.removeRange(50, _pendingNotes.length);
        }
      }
    }

    if (shouldUpdate) {
      safeNotifyListeners();
    }
  }

  List<NoteModel> get currentNotes {
    return _feedState.data ?? [];
  }

  bool get canLoadMore => _feedState.isLoaded && !_isLoadingMore;

  bool get isEmpty => _feedState.isEmpty;

  bool get isFeedLoading => _feedState.isLoading;

  String? get errorMessage => _feedState.error;

  Future<void> _loadUserProfilesForNotes(List<NoteModel> notes) async {
    if (notes.isEmpty) return;

    try {
      final Set<String> authorIds = {};
      for (final note in notes) {
        authorIds.add(note.author);
        if (note.repostedBy != null) {
          authorIds.add(note.repostedBy!);
        }
      }

      final missingAuthorIds = authorIds.where((id) {
        final cachedProfile = _profiles[id];
        return cachedProfile == null || cachedProfile.profileImage.isEmpty;
      }).toList();

      if (missingAuthorIds.isEmpty) {
        return;
      }

      const int batchSize = 15;
      final profileUpdates = <String, UserModel>{};
      bool hasUpdates = false;

      for (int i = 0; i < missingAuthorIds.length; i += batchSize) {
        final batch = missingAuthorIds.skip(i).take(batchSize).toList();

        try {
          final results = await _userRepository.getUserProfiles(
            batch,
            priority: FetchPriority.high,
          );

          for (final entry in results.entries) {
            entry.value.fold(
              (user) {
                if (!_profiles.containsKey(entry.key) || _profiles[entry.key]!.profileImage.isEmpty) {
                  profileUpdates[entry.key] = user;
                  hasUpdates = true;
                }
              },
              (error) {
                if (!_profiles.containsKey(entry.key)) {
                  profileUpdates[entry.key] = UserModel(
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
                }
              },
            );
          }
        } catch (e) {
          continue;
        }

        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (hasUpdates) {
        _profiles.addAll(profileUpdates);
        _profilesController.add(Map.from(_profiles));
      }
    } catch (e) {
      // Handle silently
    }
  }

  @override
  void onRetry() {
    _loadFeed();
  }

  @override
  void dispose() {
    _updateDebounceTimer?.cancel();
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
