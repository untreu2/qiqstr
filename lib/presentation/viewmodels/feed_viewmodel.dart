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
import '../../data/services/mute_cache_service.dart';
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

    _feedState = const LoadingState();
    safeNotifyListeners();

    _loadFeed();
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
            _subscribeToRealTimeUpdates();
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

  Future<void> _ensureMuteListLoaded() async {
    try {
      final currentUserHex = _nostrDataService.authService.npubToHex(_currentUserNpub) ?? _currentUserNpub;
      final muteCacheService = MuteCacheService.instance;
      
      await muteCacheService.getOrFetch(currentUserHex, () async {
        final result = await _nostrDataService.getMuteList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });
    } catch (e) {
      debugPrint('[FeedViewModel] Error ensuring mute list loaded: $e');
    }
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
      if (!isHashtagMode && _currentUserNpub.isNotEmpty) {
        await _ensureMuteListLoaded();
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
              _preloadCachedUserProfilesForNotesSync(sortedNotes);
              await _preloadCachedUserProfilesForNotes(sortedNotes);
              _feedState = LoadedState(sortedNotes);
              safeNotifyListeners();

              _loadUserProfilesForNotes(sortedNotes).catchError((e) {
                debugPrint('[FeedViewModel] Error loading user profiles in background: $e');
              });
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
              _preloadCachedUserProfilesForNotesSync(sortedNotes);
              await _preloadCachedUserProfilesForNotes(sortedNotes);
              _feedState = LoadedState(sortedNotes);
              safeNotifyListeners();

              _loadUserProfilesForNotes(sortedNotes).catchError((e) {
                debugPrint('[FeedViewModel] Error loading user profiles in background: $e');
              });
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
            _preloadCachedUserProfilesForNotesSync(sortedNotes);
            _preloadCachedUserProfilesForNotes(sortedNotes).then((_) {
              _feedState = LoadedState(sortedNotes);
              safeNotifyListeners();
              _loadUserProfilesForNotes(sortedNotes).catchError((e) {
                debugPrint('[FeedViewModel] Error loading user profiles in background: $e');
              });
            }).catchError((e) {
              debugPrint('[FeedViewModel] Error preloading profiles: $e');
              _feedState = LoadedState(sortedNotes);
              safeNotifyListeners();
              _loadUserProfilesForNotes(sortedNotes).catchError((err) {
                debugPrint('[FeedViewModel] Error loading user profiles in background: $err');
              });
            });
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

  void setSortMode(FeedSortMode mode) async {
    if (_sortMode == mode) return;

    final previousMode = _sortMode;
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
      _feedState = const LoadingState();
      safeNotifyListeners();

      await Future.delayed(const Duration(seconds: 1));

      if (_sortMode == mode) {
        final sortedNotes = _sortNotes(List.from(notesToSort));
        _feedState = LoadedState(sortedNotes);
        safeNotifyListeners();
      } else {
        _sortMode = previousMode;
        safeNotifyListeners();
      }
    } else {
      safeNotifyListeners();
      if (!_isLoadingFeed) {
        await _loadFeed();
      }
    }
  }

  void setHashtag(String? hashtag) async {
    if (_hashtag == hashtag) return;

    final previousHashtag = _hashtag;
    _hashtag = hashtag;
    _currentLimit = 50;
    
    _feedState = const LoadingState();
    safeNotifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    if (_hashtag == hashtag) {
      if (_isLoadingFeed) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      if (_hashtag == hashtag) {
        await _loadFeed();
      } else {
        _hashtag = previousHashtag;
        safeNotifyListeners();
      }
    } else {
      _hashtag = previousHashtag;
      safeNotifyListeners();
    }
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
              _preloadCachedUserProfilesForNotesSync(List<NoteModel>.from(notes));
              _feedState = LoadedState(List<NoteModel>.from(notes));
              safeNotifyListeners();
              _preloadCachedUserProfilesForNotes(List<NoteModel>.from(notes)).then((_) {
                safeNotifyListeners();
              });
              _loadUserProfilesForNotes(List<NoteModel>.from(notes)).catchError((e) {
                debugPrint('[FeedViewModel] Error loading user profiles in background: $e');
              });
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
            final filteredCurrentNotes = List<NoteModel>.from(currentNotes.where((n) => !removedNoteIds.contains(n.id)));
            
            for (final updatedNote in updatedNotes) {
              final index = filteredCurrentNotes.indexWhere((n) => n.id == updatedNote.id);
              if (index != -1) {
                filteredCurrentNotes[index] = updatedNote;
              }
            }

            if (newerNotes.isNotEmpty) {
              final latestTimestamp = filteredCurrentNotes.isNotEmpty ? filteredCurrentNotes.first.timestamp : DateTime.now();
              final timestampNewerNotes = List<NoteModel>.from(newerNotes.where((n) => n.timestamp.isAfter(latestTimestamp)));
              
              if (timestampNewerNotes.isNotEmpty) {
                filteredCurrentNotes.addAll(timestampNewerNotes);
              }
            }

            final sortedNotes = _sortNotes(filteredCurrentNotes);
            _feedState = LoadedState(sortedNotes);
            _lastNoteCount = sortedNotes.length;
            safeNotifyListeners();
            return;
          }

          if (hasUpdates || hasNewNotes) {
            _lastNoteCount = notes.length;

            final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;
            final filteredCurrentNotes = List<NoteModel>.from(currentNotes);
            
            if (hasUpdates) {
              for (final updatedNote in updatedNotes) {
                final index = filteredCurrentNotes.indexWhere((n) => n.id == updatedNote.id);
                if (index != -1) {
                  filteredCurrentNotes[index] = updatedNote;
                }
              }
            }

            final latestTimestamp = filteredCurrentNotes.isNotEmpty ? filteredCurrentNotes.first.timestamp : DateTime.now();
            final newerNotes = <NoteModel>[];
            for (final note in notes) {
              if (note.timestamp.isAfter(latestTimestamp)) {
                newerNotes.add(note);
              }
            }

            if (newerNotes.isEmpty) {
              if (hasUpdates) {
                final sortedNotes = _sortNotes(filteredCurrentNotes);
                _feedState = LoadedState(sortedNotes);
                _lastNoteCount = sortedNotes.length;
                safeNotifyListeners();
              }
              return;
            }

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
              final allNotes = [...userNotes, ...filteredCurrentNotes];
              final sortedNotes = _sortNotes(allNotes);
              _preloadCachedUserProfilesForNotesSync(userNotes);
              _feedState = LoadedState(sortedNotes);
              _lastNoteCount = sortedNotes.length;
              _preloadCachedUserProfilesForNotes(userNotes).then((_) {
                safeNotifyListeners();
              });
              _loadUserProfilesForNotes(userNotes).catchError((e) {
                debugPrint('[FeedViewModel] Error loading user profiles in background: $e');
              });
            } else if (hasUpdates) {
              final sortedNotes = _sortNotes(filteredCurrentNotes);
              _feedState = LoadedState(sortedNotes);
              _lastNoteCount = sortedNotes.length;
              safeNotifyListeners();
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

  void _preloadCachedUserProfilesForNotesSync(List<NoteModel> notes) {
    try {
      final Set<String> authorIds = {};
      for (final note in notes) {
        authorIds.add(note.author);
        if (note.repostedBy != null) {
          authorIds.add(note.repostedBy!);
        }
      }

      bool hasUpdates = false;
      for (final authorId in authorIds) {
        if (!_profiles.containsKey(authorId)) {
          final cachedUser = _userRepository.getCachedUserSync(authorId);
          if (cachedUser != null) {
            _profiles[authorId] = cachedUser;
            hasUpdates = true;
          }
        }
      }

      if (hasUpdates) {
        _profilesController.add(Map.from(_profiles));
        safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('[FeedViewModel] Error preloading cached user profiles: $e');
    }
  }

  Future<void> _preloadCachedUserProfilesForNotes(List<NoteModel> notes) async {
    try {
      final Set<String> authorIds = {};
      for (final note in notes) {
        authorIds.add(note.author);
        if (note.repostedBy != null) {
          authorIds.add(note.repostedBy!);
        }
      }

      final missingAuthorIds = authorIds.where((id) => !_profiles.containsKey(id)).toList();
      if (missingAuthorIds.isEmpty) {
        return;
      }

      final cachedProfiles = await _userRepository.getUserProfiles(
        missingAuthorIds,
        priority: FetchPriority.urgent,
      );

      bool hasUpdates = false;
      for (final entry in cachedProfiles.entries) {
        entry.value.fold(
          (user) {
            _profiles[entry.key] = user;
            hasUpdates = true;
          },
          (_) {},
        );
      }

      if (hasUpdates) {
        _profilesController.add(Map.from(_profiles));
        safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('[FeedViewModel] Error preloading cached user profiles: $e');
    }
  }

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

      final cachedProfiles = await _userRepository.getUserProfiles(
        missingAuthorIds,
        priority: FetchPriority.urgent,
      );

      bool hasUpdates = false;
      for (final entry in cachedProfiles.entries) {
        entry.value.fold(
          (user) {
            if (!_profiles.containsKey(entry.key) || _profiles[entry.key]!.profileImage.isEmpty) {
              _profiles[entry.key] = user;
              hasUpdates = true;
            }
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
              hasUpdates = true;
            }
          },
        );
      }

      if (hasUpdates) {
        _profilesController.add(Map.from(_profiles));
        safeNotifyListeners();
      }
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
