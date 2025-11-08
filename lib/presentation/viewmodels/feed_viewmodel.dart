import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../core/base/result.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/note_repository_compat.dart';
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

  FeedViewModel({
    required NoteRepository noteRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required NostrDataService nostrDataService,
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

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

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

      await result.fold(
        (npub) async {
          if (npub != null && npub.isNotEmpty) {
            _currentUserNpub = npub;
            _currentUserState = LoadedState(npub);
            
            final userResult = await _userRepository.getCurrentUser();
            userResult.fold(
              (user) {
                _currentUser = user;
                _profiles[user.npub] = user;
                _profilesController.add(Map.from(_profiles));
              },
              (error) {
                debugPrint('[FeedViewModel] Error loading current user profile: $error');
              },
            );
            
            _subscribeToCurrentUserStream();
            _loadFeed();
            _subscribeToRealTimeUpdates();
          } else {
            _currentUserState = const ErrorState('User not authenticated');
          }
        },
        (error) async {
          _currentUserState = ErrorState(error);
        },
      );

      safeNotifyListeners();
    }, showLoading: false);
  }

  void _subscribeToCurrentUserStream() {
    addSubscription(
      _userRepository.currentUserStream.listen((updatedUser) {
        if (isDisposed) return;

        final hasChanges = _currentUser == null ||
            _currentUser!.npub != updatedUser.npub ||
            _currentUser!.profileImage != updatedUser.profileImage ||
            _currentUser!.name != updatedUser.name;

        if (!hasChanges) {
          return;
        }

        _currentUser = updatedUser;
        _profiles[updatedUser.npub] = updatedUser;
        _profilesController.add(Map.from(_profiles));
        safeNotifyListeners();
      }),
    );
  }

  Future<void> _loadFeed() async {
    if (_currentUserNpub.isEmpty && !isHashtagMode) {
      return;
    }

    if (_isLoadingFeed) {
      return;
    }

    _isLoadingFeed = true;

    try {
      
      if (!isHashtagMode) {
        try {
          final cachedNotes = _noteRepository.currentNotes;
          if (cachedNotes.isNotEmpty) {
            debugPrint('[FeedViewModel] Found ${cachedNotes.length} cached notes, showing immediately');
            final sortedNotes = _sortNotes(List.from(cachedNotes));
            _feedState = LoadedState(sortedNotes);
            safeNotifyListeners();
            
            
            _loadUserProfilesForNotes(sortedNotes).catchError((_) {});
            
            
            _subscribeToRealTimeUpdates();
          }
        } catch (e) {
          debugPrint('[FeedViewModel] Error checking cached notes: $e');
        }
      }

      if (isHashtagMode) {
        await _loadHashtagFeed();
      } else {
        await _loadUserFeed();
      }
    } catch (e) {
      debugPrint('[FeedViewModel] Error in _loadFeed: $e');
      
      if (_feedState is LoadingState) {
        _feedState = ErrorState('Failed to load feed: ${e.toString()}');
        safeNotifyListeners();
      }
    } finally {
      _isLoadingFeed = false;
    }
  }

  Future<void> _loadUserFeed() async {
    await executeOperation('loadFeed', () async {
      
      if (_feedState is! LoadedState<List<NoteModel>> || (_feedState as LoadedState<List<NoteModel>>).data.isEmpty) {
        _feedState = const LoadingState();
        safeNotifyListeners();
      }


      try {
        Result<List<NoteModel>> result;
        try {
          result = await _noteRepository.getFeedNotesFromFollowList(
            currentUserNpub: _currentUserNpub,
            limit: _currentLimit,
          ).timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint('[FeedViewModel] Feed load timeout after 8s');
              
              final cachedNotes = _noteRepository.currentNotes;
              if (cachedNotes.isNotEmpty) {
                return Future.value(Result.success(cachedNotes));
              }
              return Future.value(const Result.success(<NoteModel>[]));
            },
          );
        } on TimeoutException {
          debugPrint('[FeedViewModel] Feed load timeout after 8s');
          
          final cachedNotes = _noteRepository.currentNotes;
          if (cachedNotes.isNotEmpty) {
            result = Result.success(cachedNotes);
          } else {
            result = const Result.success(<NoteModel>[]);
          }
        }

        await result.fold(
          (notes) async {
            if (notes.isEmpty) {
              
              if (_feedState is! LoadedState<List<NoteModel>> || (_feedState as LoadedState<List<NoteModel>>).data.isEmpty) {
                _feedState = const LoadedState(<NoteModel>[]);
              }
            } else {
              final sortedNotes = _sortNotes(notes);
              _feedState = LoadedState(sortedNotes);

              await _loadUserProfilesForNotes(sortedNotes);
            }

            _subscribeToRealTimeUpdates();
          },
          (error) async {
            
            if (_feedState is! LoadedState<List<NoteModel>> || (_feedState as LoadedState<List<NoteModel>>).data.isEmpty) {
              _feedState = ErrorState(error);
            } else {
              debugPrint('[FeedViewModel] Feed load error but showing cached notes: $error');
            }
          },
        );

        safeNotifyListeners();
      } catch (e) {
        debugPrint('[FeedViewModel] Exception in _loadUserFeed: $e');
        
        if (_feedState is! LoadedState<List<NoteModel>> || (_feedState as LoadedState<List<NoteModel>>).data.isEmpty) {
          _feedState = ErrorState('Failed to load feed: ${e.toString()}');
          safeNotifyListeners();
        }
      }
    });
  }

  Future<void> _loadHashtagFeed() async {
    await executeOperation('loadHashtagFeed', () async {
      _feedState = const LoadingState();
      safeNotifyListeners();


      try {
        
        Result<List<NoteModel>> result;
        try {
          result = await _noteRepository.getHashtagNotes(
            hashtag: _hashtag!,
            limit: _currentLimit,
          ).timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint('[FeedViewModel] Hashtag feed load timeout after 8s');
              return Future.value(const Result.success(<NoteModel>[]));
            },
          );
        } on TimeoutException {
          debugPrint('[FeedViewModel] Hashtag feed load timeout after 8s');
          result = const Result.success(<NoteModel>[]);
        }

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
      } catch (e) {
        debugPrint('[FeedViewModel] Exception in _loadHashtagFeed: $e');
        _feedState = ErrorState('Failed to load hashtag feed: ${e.toString()}');
        safeNotifyListeners();
      }
    });
  }

  Future<void> refreshFeed() async {
    _currentLimit = 50;
    
    if (_currentUserNpub.isEmpty && !isHashtagMode) {
      return;
    }

    if (_isLoadingFeed) {
      return;
    }

    _isLoadingFeed = true;

    try {
      
      final currentNotes = _feedState is LoadedState<List<NoteModel>> 
          ? (_feedState as LoadedState<List<NoteModel>>).data 
          : <NoteModel>[];

      if (isHashtagMode) {
        _feedState = const LoadingState();
        safeNotifyListeners();
        await _loadHashtagFeed();
      } else {
        
        if (currentNotes.isEmpty) {
          _feedState = const LoadingState();
          safeNotifyListeners();
        }
        
        await _loadUserFeed();
      }
    } catch (e) {
      debugPrint('[FeedViewModel] Error in refreshFeed: $e');
      
      final currentNotes = _feedState is LoadedState<List<NoteModel>> 
          ? (_feedState as LoadedState<List<NoteModel>>).data 
          : <NoteModel>[];
      if (currentNotes.isNotEmpty) {
        _feedState = LoadedState(currentNotes);
      } else {
        _feedState = ErrorState('Failed to refresh feed: ${e.toString()}');
      }
      safeNotifyListeners();
    } finally {
      _isLoadingFeed = false;
    }
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

  int _lastNoteCount = 0;

  void _subscribeToRealTimeUpdates() {
    final stream = isHashtagMode 
        ? _noteRepository.notesStream 
        : _noteRepository.realTimeNotesStream;

    addSubscription(
      stream.listen((notes) {
        if (!isDisposed && _feedState.isLoaded) {
          if (notes.length == _lastNoteCount) {
            debugPrint('[FeedViewModel] Note count unchanged ($_lastNoteCount), skipping update');
            return;
          }
          
          
          final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;
          
          if (currentNotes.isEmpty) {
            if (notes.isNotEmpty) {
              _feedState = LoadedState(notes);
              _loadUserProfilesForNotes(notes);
              safeNotifyListeners();
            }
            return;
          }

          final noteIds = notes.map((n) => n.id).toSet();
          final currentNoteIds = currentNotes.map((n) => n.id).toSet();
          
          final removedNoteIds = currentNoteIds.difference(noteIds);
          final updatedNotes = notes.where((n) => currentNoteIds.contains(n.id)).toList();
          final newerNotes = notes.where((n) => !currentNoteIds.contains(n.id)).toList();

          final hasRemovals = removedNoteIds.isNotEmpty;
          final hasUpdates = updatedNotes.isNotEmpty;
          final hasNewNotes = newerNotes.isNotEmpty;

          if (hasRemovals) {
            final filteredNotes = currentNotes.where((n) => !removedNoteIds.contains(n.id)).toList();
            
            for (final updatedNote in updatedNotes) {
              final index = filteredNotes.indexWhere((n) => n.id == updatedNote.id);
              if (index != -1) {
                filteredNotes[index] = updatedNote;
              }
            }

            if (newerNotes.isNotEmpty) {
              final latestTimestamp = filteredNotes.isNotEmpty ? filteredNotes.first.timestamp : DateTime.now();
              final timestampNewerNotes = newerNotes.where((n) => n.timestamp.isAfter(latestTimestamp)).toList();
              
              if (timestampNewerNotes.isNotEmpty) {
                final userNotes = timestampNewerNotes.where((n) => n.author == _currentUserNpub).toList();
                if (userNotes.isNotEmpty) {
                  filteredNotes.addAll(userNotes);
                }
              }
            }

            final sortedNotes = _sortNotes(filteredNotes);
            _feedState = LoadedState(sortedNotes);
            _lastNoteCount = sortedNotes.length;
            safeNotifyListeners();
            return;
          }

          if (hasUpdates || hasNewNotes) {
            _lastNoteCount = notes.length;

            final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;
            final latestTimestamp = currentNotes.first.timestamp;
            final newerNotes = <NoteModel>[];
            for (final note in notes) {
              if (note.timestamp.isAfter(latestTimestamp)) {
                newerNotes.add(note);
              }
            }

            if (newerNotes.isEmpty) return;

            final userNotes = <NoteModel>[];
            final otherNotes = <NoteModel>[];
            final pendingSet = <String>{};

            for (final note in newerNotes) {
              if (note.author == _currentUserNpub) {
                userNotes.add(note);
              } else {
                otherNotes.add(note);
              }
            }

            if (userNotes.isNotEmpty) {
              final allNotes = [...userNotes, ...currentNotes];
              final sortedNotes = _sortNotes(allNotes);
              _feedState = LoadedState(sortedNotes);
              _lastNoteCount = sortedNotes.length;
              _loadUserProfilesForNotes(userNotes);
            }

            if (otherNotes.isNotEmpty) {
              for (final note in _pendingNotes) {
                pendingSet.add(note.id);
              }
              for (final note in otherNotes) {
                if (!pendingSet.contains(note.id)) {
                  _pendingNotes.add(note);
                  pendingSet.add(note.id);
                }
              }
              _pendingNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            }

            safeNotifyListeners();
          }
        }
      }),
    );
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

      final results = await _userRepository.getUserProfiles(
        missingAuthorIds,
        priority: FetchPriority.high,
      );

      for (final entry in results.entries) {
        entry.value.fold(
          (user) {
            _profiles[entry.key] = user;
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
            }
          },
        );
      }

      _profilesController.add(Map.from(_profiles));
    } catch (e) {
      debugPrint('[FeedViewModel] Error loading user profiles: $e');
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
