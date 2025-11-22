import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/feed_loader_service.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';

export '../../data/services/feed_loader_service.dart' show FeedSortMode;

class FeedViewModel extends BaseViewModel with CommandMixin {
  final NoteRepository _noteRepository;
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final FeedLoaderService _feedLoader;

  FeedViewModel({
    required NoteRepository noteRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required FeedLoaderService feedLoader,
  })  : _noteRepository = noteRepository,
        _authRepository = authRepository,
        _userRepository = userRepository,
        _feedLoader = feedLoader {
    _subscribeToDeletions();
  }

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
  bool _isSubscribedToUserNotes = false;

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

    _feedState = const LoadingState();
    safeNotifyListeners();

    _loadFeed();
    _subscribeToUserNotes();
  }

  Future<void> _loadCurrentUser() async {
    await executeOperation('loadCurrentUser', () async {
      _currentUserState = const LoadingState();
      _feedState = const LoadingState();
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
            _subscribeToUserNotes();
          } else {
            _currentUserState = const ErrorState('User not authenticated');
            _feedState = const ErrorState('User not authenticated');
          }
        },
        (error) async {
          _currentUserState = ErrorState(error);
          _feedState = ErrorState(error);
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

  Future<void> _loadFeed({bool skipCache = false}) async {
    if (_currentUserNpub.isEmpty && !isHashtagMode) {
      return;
    }

    if (_isLoadingFeed) {
      return;
    }

    _isLoadingFeed = true;

    try {
      final feedType = isHashtagMode ? FeedType.hashtag : FeedType.feed;
      final params = FeedLoadParams(
        type: feedType,
        currentUserNpub: _currentUserNpub,
        hashtag: _hashtag,
        limit: _currentLimit,
        skipCache: skipCache,
      );

      if (_feedState is! LoadedState<List<NoteModel>> || (_feedState as LoadedState<List<NoteModel>>).data.isEmpty) {
        _feedState = const LoadingState();
        safeNotifyListeners();
      }

      final result = await _feedLoader.loadFeed(params);

      if (result.isSuccess) {
        if (result.notes.isEmpty) {
          if (_feedState is! LoadedState<List<NoteModel>> || (_feedState as LoadedState<List<NoteModel>>).data.isEmpty) {
            _feedState = const LoadedState(<NoteModel>[]);
          }
        } else {
          final sortedNotes = _feedLoader.sortNotes(result.notes, _sortMode);
          
          _feedState = LoadedState(sortedNotes);
          safeNotifyListeners();

          _feedLoader.preloadCachedUserProfilesSync(
            sortedNotes,
            _profiles,
            (profiles) {
              _profilesController.add(Map.from(profiles));
            },
          );

          Future.microtask(() async {
            await _feedLoader.preloadCachedUserProfiles(
              sortedNotes,
              _profiles,
              (profiles) {
                _profilesController.add(Map.from(profiles));
                safeNotifyListeners();
              },
            );

            _feedLoader.loadUserProfilesForNotes(
              sortedNotes,
              _profiles,
              (profiles) {
                _profilesController.add(Map.from(profiles));
                safeNotifyListeners();
              },
            ).catchError((e) {
              debugPrint('[FeedViewModel] Error loading user profiles in background: $e');
            });
          });
        }

        if (!isHashtagMode) {
          _subscribeToRealTimeUpdates();
        }
      } else {
        if (_feedState is! LoadedState<List<NoteModel>> || (_feedState as LoadedState<List<NoteModel>>).data.isEmpty) {
          _feedState = ErrorState(result.error ?? 'Failed to load feed');
        } else {
          debugPrint('[FeedViewModel] Feed load error but showing cached notes: ${result.error}');
        }
      }

      safeNotifyListeners();
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
      final currentNotes = _feedState is LoadedState<List<NoteModel>> ? (_feedState as LoadedState<List<NoteModel>>).data : <NoteModel>[];

      if (currentNotes.isEmpty) {
        _feedState = const LoadingState();
        safeNotifyListeners();
      }

      await _loadFeed(skipCache: true);
    } catch (e) {
      debugPrint('[FeedViewModel] Error in refreshFeed: $e');
      final currentNotes = _feedState is LoadedState<List<NoteModel>> ? (_feedState as LoadedState<List<NoteModel>>).data : <NoteModel>[];
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

      final feedType = isHashtagMode ? FeedType.hashtag : FeedType.feed;
      final params = FeedLoadParams(
        type: feedType,
        currentUserNpub: _currentUserNpub,
        hashtag: _hashtag,
        limit: _currentLimit,
      );

      final result = await _feedLoader.loadFeed(params);

      if (result.isSuccess && result.notes.isNotEmpty) {
        final sortedNotes = _feedLoader.sortNotes(result.notes, _sortMode);

        _feedState = LoadedState(sortedNotes);
        safeNotifyListeners();

        _feedLoader.preloadCachedUserProfilesSync(
          sortedNotes,
          _profiles,
          (profiles) {
            _profilesController.add(Map.from(profiles));
          },
        );

        Future.microtask(() async {
          await _feedLoader.preloadCachedUserProfiles(
            sortedNotes,
            _profiles,
            (profiles) {
              _profilesController.add(Map.from(profiles));
              safeNotifyListeners();
            },
          );

          _feedLoader.loadUserProfilesForNotes(
            sortedNotes,
            _profiles,
            (profiles) {
              _profilesController.add(Map.from(profiles));
              safeNotifyListeners();
            },
          ).catchError((e) {
            debugPrint('[FeedViewModel] Error loading user profiles: $e');
          });
        });
      } else if (result.error != null) {
        setError(NetworkError(message: 'Failed to load more notes: ${result.error}'));
      }
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
      final sortedNotes = _feedLoader.sortNotes(List.from(currentNotes), _sortMode);
      _feedState = LoadedState(sortedNotes);
    }

    safeNotifyListeners();
  }

  void setSortMode(FeedSortMode mode) async {
    if (_sortMode == mode) return;

    _sortMode = mode;

    List<NoteModel>? notesToSort;

    if (_feedState is LoadedState<List<NoteModel>>) {
      notesToSort = (_feedState as LoadedState<List<NoteModel>>).data;
    } else {
      final cachedNotes = _noteRepository.currentNotes;
      if (cachedNotes.isNotEmpty) {
        notesToSort = cachedNotes;
      }
    }

    if (notesToSort != null && notesToSort.isNotEmpty) {
      final sortedNotes = _feedLoader.sortNotes(List.from(notesToSort), _sortMode);
      _feedState = LoadedState(sortedNotes);
      safeNotifyListeners();
    } else {
      safeNotifyListeners();
      if (!_isLoadingFeed) {
        await _loadFeed();
      }
    }
  }

  void setHashtag(String? hashtag) async {
    if (_hashtag == hashtag) return;

    _hashtag = hashtag;
    _currentLimit = 50;

    _feedState = const LoadingState();
    safeNotifyListeners();

    await _loadFeed();
  }

  int _lastNoteCount = 0;

  void _subscribeToDeletions() {
    addSubscription(
      _noteRepository.nostrDataService.noteDeletedStream.listen((deletedNoteId) {
        if (_feedState is LoadedState<List<NoteModel>>) {
          final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;
          final updatedNotes = currentNotes.where((n) => n.id != deletedNoteId).toList();

          if (updatedNotes.length != currentNotes.length) {
            _feedState = LoadedState(updatedNotes);
            safeNotifyListeners();
          }
        }
      }),
    );
  }

  void _subscribeToUserNotes() {
    if (_currentUserNpub.isEmpty || _isSubscribedToUserNotes) return;
    
    _isSubscribedToUserNotes = true;

    final currentUserHex = _authRepository.npubToHex(_currentUserNpub);
    if (currentUserHex == null) {
      debugPrint('[FeedViewModel] Could not convert npub to hex: $_currentUserNpub');
      return;
    }

    addSubscription(
      _noteRepository.notesStream.listen((allNotes) {
        if (isDisposed || _feedState is! LoadedState<List<NoteModel>>) return;

        final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;
        final currentNoteIds = currentNotes.map((n) => n.id).toSet();

        final userNewNotes = allNotes.where((note) {
          final isUserNote = note.author == currentUserHex;
          
          final isUserRepost = note.isRepost && note.repostedBy != null;
          String? repostedByHex;
          if (isUserRepost) {
            repostedByHex = note.repostedBy!.length == 64 
                ? note.repostedBy 
                : _authRepository.npubToHex(note.repostedBy!);
            repostedByHex = repostedByHex ?? note.repostedBy;
          }
          final isUserRepostMatch = isUserRepost && repostedByHex == currentUserHex;
          
          final isNew = !currentNoteIds.contains(note.id);
          
          final matchesFeed = !isHashtagMode || 
                             (_hashtag != null && note.tTags.contains(_hashtag!.toLowerCase()));
          
          return (isUserNote || isUserRepostMatch) && isNew && matchesFeed;
        }).toList();

        if (userNewNotes.isNotEmpty) {
          final updatedNotes = [...userNewNotes, ...currentNotes];
          
          final seenIds = <String>{};
          final deduplicatedNotes = <NoteModel>[];
          for (final note in updatedNotes) {
            if (!seenIds.contains(note.id)) {
              seenIds.add(note.id);
              deduplicatedNotes.add(note);
            }
          }

          final sortedNotes = _feedLoader.sortNotes(deduplicatedNotes, _sortMode);
          
          _feedState = LoadedState(sortedNotes);
          safeNotifyListeners();

          _feedLoader.preloadCachedUserProfilesSync(
            userNewNotes,
            _profiles,
            (profiles) {
              _profilesController.add(Map.from(profiles));
            },
          );

          _feedLoader.preloadCachedUserProfiles(
            userNewNotes,
            _profiles,
            (profiles) {
              _profilesController.add(Map.from(profiles));
            },
          );

          _feedLoader.loadUserProfilesForNotes(
            userNewNotes,
            _profiles,
            (profiles) {
              _profilesController.add(Map.from(profiles));
            },
          ).catchError((e) {
            debugPrint('[FeedViewModel] Error loading user profiles for new notes: $e');
          });
        }
      }),
    );
  }

  void _subscribeToRealTimeUpdates() {
    final feedType = isHashtagMode ? FeedType.hashtag : FeedType.feed;
    final stream = _feedLoader.getNotesStream(feedType);

    addSubscription(
      stream.listen((notes) {
        if (!isDisposed && _feedState.isLoaded) {
          List<NoteModel> filteredNotes = notes;

          if (isHashtagMode && _hashtag != null) {
            final targetHashtag = _hashtag!.toLowerCase();
            filteredNotes = notes.where((note) {
              if (note.tTags.isNotEmpty) {
                return note.tTags.contains(targetHashtag);
              }

              final content = note.content.toLowerCase();
              final hashtagRegex = RegExp(r'#(\w+)');
              final matches = hashtagRegex.allMatches(content);

              for (final match in matches) {
                final extractedHashtag = match.group(1)?.toLowerCase();
                if (extractedHashtag == targetHashtag) {
                  return true;
                }
              }

              return false;
            }).toList();
          }

          if (filteredNotes.length == _lastNoteCount) {
            return;
          }

          final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;

          if (currentNotes.isEmpty) {
            if (filteredNotes.isNotEmpty) {
              _feedState = LoadedState(List<NoteModel>.from(filteredNotes));
              safeNotifyListeners();

              _feedLoader.preloadCachedUserProfilesSync(
                filteredNotes,
                _profiles,
                (profiles) {
                  _profilesController.add(Map.from(profiles));
                },
              );

              _feedLoader.preloadCachedUserProfiles(
                filteredNotes,
                _profiles,
                (profiles) {
                  _profilesController.add(Map.from(profiles));
                },
              );

              _feedLoader.loadUserProfilesForNotes(
                filteredNotes,
                _profiles,
                (profiles) {
                  _profilesController.add(Map.from(profiles));
                },
              ).catchError((e) {});
            }
            return;
          }

          final mergedNotes = _feedLoader.mergeNotesWithUpdates(
            currentNotes,
            filteredNotes,
            _sortMode,
          );

          if (mergedNotes != currentNotes) {
            _feedState = LoadedState(mergedNotes);
            _lastNoteCount = mergedNotes.length;
            safeNotifyListeners();

            final newNotes = mergedNotes.where((n) => !currentNotes.any((c) => c.id == n.id)).toList();
            if (newNotes.isNotEmpty) {
              _feedLoader.preloadCachedUserProfilesSync(
                newNotes,
                _profiles,
                (profiles) {
                  _profilesController.add(Map.from(profiles));
                },
              );

              _feedLoader.preloadCachedUserProfiles(
                newNotes,
                _profiles,
                (profiles) {
                  _profilesController.add(Map.from(profiles));
                },
              );

              _feedLoader.loadUserProfilesForNotes(
                newNotes,
                _profiles,
                (profiles) {
                  _profilesController.add(Map.from(profiles));
                },
              ).catchError((e) {});
            }
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

  void updateUserProfile(String userId, UserModel user) {
    if (!_profiles.containsKey(userId) || _profiles[userId]!.profileImage.isEmpty) {
      _profiles[userId] = user;
      _profilesController.add(Map.from(_profiles));
      safeNotifyListeners();
    }
  }

  void updateUserProfiles(Map<String, UserModel> users) {
    bool hasUpdates = false;
    for (final entry in users.entries) {
      if (!_profiles.containsKey(entry.key) || _profiles[entry.key]!.profileImage.isEmpty) {
        _profiles[entry.key] = entry.value;
        hasUpdates = true;
      }
    }
    if (hasUpdates) {
      _profilesController.add(Map.from(_profiles));
      safeNotifyListeners();
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
