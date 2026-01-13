import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/services/feed_loader_service.dart';
import '../../models/user_model.dart';
import '../../models/note_model.dart';

class ProfileViewModel extends BaseViewModel with CommandMixin {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final NoteRepository _noteRepository;
  final FeedLoaderService _feedLoader;

  ProfileViewModel({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required NoteRepository noteRepository,
    required FeedLoaderService feedLoader,
  })  : _userRepository = userRepository,
        _authRepository = authRepository,
        _noteRepository = noteRepository,
        _feedLoader = feedLoader;

  UIState<UserModel> _profileState = const InitialState();
  UIState<UserModel> get profileState => _profileState;

  UIState<List<UserModel>> _followingListState = const InitialState();
  UIState<List<UserModel>> get followingListState => _followingListState;

  UIState<List<NoteModel>> _profileNotesState = const InitialState();
  UIState<List<NoteModel>> get profileNotesState => _profileNotesState;

  final Map<String, UserModel> _profiles = {};
  Map<String, UserModel> get profiles => Map.unmodifiable(_profiles);

  final StreamController<Map<String, UserModel>> _profilesController = StreamController<Map<String, UserModel>>.broadcast();
  Stream<Map<String, UserModel>> get profilesStream => _profilesController.stream;

  bool _isCurrentUser = false;
  bool get isCurrentUser => _isCurrentUser;

  bool _isFollowing = false;
  bool get isFollowing => _isFollowing;

  String _currentProfileNpub = '';
  String get currentProfileNpub => _currentProfileNpub;

  String _currentUserNpub = '';
  String get currentUserNpub => _currentUserNpub;

  bool _isSubscribedToProfileNotes = false;

  static const int _pageSize = 30;
  int get currentLimit => _pageSize;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  LoadProfileCommand? _loadProfileCommand;
  UpdateProfileCommand? _updateProfileCommand;
  ToggleFollowCommand? _toggleFollowCommand;
  LoadFollowingListCommand? _loadFollowingListCommand;
  LoadProfileNotesCommand? _loadProfileNotesCommand;
  LoadMoreProfileNotesCommand? _loadMoreProfileNotesCommand;

  LoadProfileCommand get loadProfileCommand => _loadProfileCommand ??= LoadProfileCommand(this);
  UpdateProfileCommand get updateProfileCommand => _updateProfileCommand ??= UpdateProfileCommand(this);
  ToggleFollowCommand get toggleFollowCommand => _toggleFollowCommand ??= ToggleFollowCommand(this);
  LoadFollowingListCommand get loadFollowingListCommand => _loadFollowingListCommand ??= LoadFollowingListCommand(this);
  LoadProfileNotesCommand get loadProfileNotesCommand => _loadProfileNotesCommand ??= LoadProfileNotesCommand(this);
  LoadMoreProfileNotesCommand get loadMoreProfileNotesCommand => _loadMoreProfileNotesCommand ??= LoadMoreProfileNotesCommand(this);

  @override
  void initialize() {
    super.initialize();

    registerCommand('loadProfile', loadProfileCommand);
    registerCommand('updateProfile', updateProfileCommand);
    registerCommand('toggleFollow', toggleFollowCommand);
    registerCommand('loadFollowingList', loadFollowingListCommand);
    registerCommand('loadProfileNotes', loadProfileNotesCommand);
    registerCommand('loadMoreProfileNotes', loadMoreProfileNotesCommand);

    _subscribeToUserUpdates();
  }

  void initializeWithUser(String npub) {
    _currentProfileNpub = npub;
    _checkIfCurrentUser();

    loadProfileCommand.execute(npub);
    _profileNotesState = const LoadingState();
    safeNotifyListeners();
    loadProfileNotes(npub);
    _subscribeToProfileNotes();
  }

  Future<void> loadProfile(String npub) async {
    await executeOperation('loadProfile', () async {
      _profileState = const LoadingState();
      safeNotifyListeners();

      final result = await _userRepository.getUserProfile(npub);

      result.fold(
        (user) {
          _profileState = LoadedState(user);
          _isFollowing = false;
          _currentProfileNpub = npub;
        },
        (error) => _profileState = ErrorState(error),
      );

      safeNotifyListeners();
    });
  }

  Future<void> updateProfile({
    String? name,
    String? about,
    String? profileImage,
    String? banner,
    String? website,
    String? nip05,
    String? lud16,
  }) async {
    if (!_isCurrentUser) {
      setError(AuthError(message: 'Cannot update profile of another user'));
      return;
    }

    await executeOperation('updateProfile', () async {
      _profileState = const LoadingState(LoadingType.backgroundRefresh);
      safeNotifyListeners();

      final result = await _userRepository.updateProfile(
        name: name,
        about: about,
        profileImage: profileImage,
        banner: banner,
        website: website,
        nip05: nip05,
        lud16: lud16,
      );

      result.fold(
        (updatedUser) {
          _profileState = LoadedState(updatedUser);
          _userRepository.invalidateUserCache(updatedUser.npub);
          _userRepository.cacheUser(updatedUser);
        },
        (error) => _profileState = ErrorState(error),
      );

      safeNotifyListeners();
    });
  }

  Future<void> toggleFollow() async {
    if (_isCurrentUser) {
      setError(ValidationError(message: 'Cannot follow yourself'));
      return;
    }

    await executeOperation('toggleFollow', () async {
      final wasFollowing = _isFollowing;

      _isFollowing = !_isFollowing;
      safeNotifyListeners();

      final result =
          wasFollowing ? await _userRepository.unfollowUser(_currentProfileNpub) : await _userRepository.followUser(_currentProfileNpub);

      result.fold(
        (_) {},
        (error) {
          _isFollowing = wasFollowing;
          setError(NetworkError(message: 'Failed to ${wasFollowing ? 'unfollow' : 'follow'} user: $error'));
          safeNotifyListeners();
        },
      );
    }, showLoading: false);
  }

  Future<void> loadFollowingList() async {
    await executeOperation('loadFollowingList', () async {
      _followingListState = const LoadingState();
      safeNotifyListeners();

      final result = await _userRepository.getFollowingList();

      result.fold(
        (users) {
          _followingListState = users.isEmpty ? const EmptyState('No following users yet') : LoadedState(users);
        },
        (error) => _followingListState = ErrorState(error),
      );

      safeNotifyListeners();
    });
  }

  Future<void> loadProfileNotes(String userNpub) async {
    await executeOperation('loadProfileNotes', () async {
      _profileNotesState = const LoadingState();
      safeNotifyListeners();

      try {
        final params = FeedLoadParams(
          type: FeedType.profile,
          targetUserNpub: userNpub,
          limit: _pageSize,
          skipCache: true,
        );

        final result = await _feedLoader.loadFeed(params);

        if (result.isSuccess) {
          if (result.notes.isNotEmpty) {
            _profileNotesState = LoadedState(result.notes);
            safeNotifyListeners();

            _feedLoader.loadProfilesAndInteractionsForNotes(
              result.notes,
              _profiles,
              (profiles) {
                _profilesController.add(Map.from(profiles));
              },
            );
          } else {
            _profileNotesState = const LoadingState();
            safeNotifyListeners();
          }
        } else {
          _profileNotesState = ErrorState(result.error ?? 'Failed to load notes');
        }
      } catch (e) {
        debugPrint('[ProfileViewModel] Exception loading profile notes: $e');
        _profileNotesState = ErrorState('Exception loading notes: $e');
      }

      safeNotifyListeners();
    });
  }

  Future<void> loadMoreProfileNotes() async {
    if (_isLoadingMore) return;
    if (_profileNotesState is! LoadedState<List<NoteModel>>) return;

    final currentNotes = (_profileNotesState as LoadedState<List<NoteModel>>).data;
    if (currentNotes.isEmpty) return;

    _isLoadingMore = true;
    safeNotifyListeners();

    try {
      final oldestNote = currentNotes.reduce((a, b) => a.timestamp.isBefore(b.timestamp) ? a : b);
      final until = oldestNote.timestamp.subtract(const Duration(milliseconds: 100));

      final params = FeedLoadParams(
        type: FeedType.profile,
        targetUserNpub: _currentProfileNpub,
        limit: _pageSize,
        until: until,
        skipCache: true,
      );

      final result = await _feedLoader.loadFeed(params);

      if (result.isSuccess && result.notes.isNotEmpty) {
        final currentIds = currentNotes.map((n) => n.id).toSet();
        final uniqueNewNotes = result.notes.where((n) => !currentIds.contains(n.id)).toList();

        if (uniqueNewNotes.isNotEmpty) {
          final allNotes = [...currentNotes, ...uniqueNewNotes];
          final allSeenIds = <String>{};
          final deduplicatedNotes = <NoteModel>[];

          for (final note in allNotes) {
            if (!allSeenIds.contains(note.id)) {
              allSeenIds.add(note.id);
              deduplicatedNotes.add(note);
            }
          }

          _profileNotesState = deduplicatedNotes.isEmpty ? const EmptyState('No notes from this user yet') : LoadedState(deduplicatedNotes);

          safeNotifyListeners();

          _feedLoader.loadProfilesAndInteractionsForNotes(
            uniqueNewNotes,
            _profiles,
            (profiles) {
              _profilesController.add(Map.from(profiles));
            },
          );
        }
      }
    } catch (e) {
      debugPrint('[ProfileViewModel] Exception in loadMoreProfileNotes: $e');
    } finally {
      _isLoadingMore = false;
      safeNotifyListeners();
    }
  }

  Future<void> _checkIfCurrentUser() async {
    try {
      final result = await _authRepository.getCurrentUserNpub();
      result.fold(
        (currentNpub) {
          _currentUserNpub = currentNpub ?? '';
          _isCurrentUser = currentNpub == _currentProfileNpub;
          safeNotifyListeners();
        },
        (_) {
          _currentUserNpub = '';
          _isCurrentUser = false;
        },
      );
    } catch (e) {
      _currentUserNpub = '';
      _isCurrentUser = false;
    }
  }

  void _subscribeToUserUpdates() {
    addSubscription(
      _userRepository.currentUserStream.listen((user) {
        if (!isDisposed && user.npub == _currentProfileNpub) {
          _profileState = LoadedState(user);
          safeNotifyListeners();
        }
      }),
    );
  }

  void _subscribeToProfileNotes() {
    if (_currentProfileNpub.isEmpty || _isSubscribedToProfileNotes) return;
    
    _isSubscribedToProfileNotes = true;

    final profileNpubHex = _authRepository.npubToHex(_currentProfileNpub);
    if (profileNpubHex == null) {
      debugPrint('[ProfileViewModel] Could not convert npub to hex: $_currentProfileNpub');
      return;
    }

    addSubscription(
      _noteRepository.notesStream.listen((allNotes) {
        if (isDisposed) return;

        final currentNotes = _profileNotesState.data ?? <NoteModel>[];
        final currentNoteIds = currentNotes.map((n) => n.id).toSet();

        final profileNpub = _currentProfileNpub;
        final profileNpubHexForFilter = _authRepository.npubToHex(profileNpub);
        if (profileNpubHexForFilter == null) return;

        final allProfileNotes = allNotes.where((note) {
          if (note.isRepost) {
            final repostedByHex = note.repostedBy != null 
                ? (note.repostedBy!.length == 64 
                    ? note.repostedBy 
                    : _authRepository.npubToHex(note.repostedBy!))
                : null;
            return repostedByHex == profileNpubHexForFilter;
          } else {
            if (note.isReply && !note.isRepost) {
              return false;
            }
            final noteAuthorHex = _authRepository.npubToHex(note.author);
            return noteAuthorHex == profileNpubHexForFilter;
          }
        }).toList();

        final newProfileNoteIds = allProfileNotes.map((n) => n.id).toSet();
        final existingNotesFromCache = currentNotes.where((note) => newProfileNoteIds.contains(note.id)).toList();
        final newNotesFromStream = allProfileNotes.where((note) => !currentNoteIds.contains(note.id)).toList();

        if (newNotesFromStream.isNotEmpty || (currentNotes.isNotEmpty && existingNotesFromCache.length != currentNotes.length)) {
          final updatedNotes = [...newNotesFromStream, ...existingNotesFromCache];
          
          final seenIds = <String>{};
          final deduplicatedNotes = <NoteModel>[];
          for (final note in updatedNotes) {
            if (!seenIds.contains(note.id)) {
              seenIds.add(note.id);
              deduplicatedNotes.add(note);
            }
          }

          deduplicatedNotes.sort((a, b) {
            final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
            final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
            return bTime.compareTo(aTime);
          });
          
          _profileNotesState = deduplicatedNotes.isEmpty ? const EmptyState('No notes from this user yet') : LoadedState(deduplicatedNotes);
          safeNotifyListeners();

          if (newNotesFromStream.isNotEmpty) {
            _feedLoader.loadProfilesAndInteractionsForNotes(
              newNotesFromStream,
              _profiles,
              (profiles) {
                _profilesController.add(Map.from(profiles));
              },
            );
          }
        } else if (currentNotes.isEmpty && allProfileNotes.isNotEmpty) {
          final seenIds = <String>{};
          final deduplicatedNotes = <NoteModel>[];
          for (final note in allProfileNotes) {
            if (!seenIds.contains(note.id)) {
              seenIds.add(note.id);
              deduplicatedNotes.add(note);
            }
          }

          deduplicatedNotes.sort((a, b) {
            final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
            final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
            return bTime.compareTo(aTime);
          });
          
          _profileNotesState = LoadedState(deduplicatedNotes);
          safeNotifyListeners();

          _feedLoader.loadProfilesAndInteractionsForNotes(
            deduplicatedNotes,
            _profiles,
            (profiles) {
              _profilesController.add(Map.from(profiles));
            },
          );
        }
      }),
    );
  }

  UserModel? get currentProfile {
    return _profileState.data;
  }

  List<UserModel> get followingList {
    return _followingListState.data ?? [];
  }

  bool get isProfileLoading => _profileState.isLoading;

  bool get isFollowingListLoading => _followingListState.isLoading;

  String? get profileErrorMessage => _profileState.error;

  String? get followingListErrorMessage => _followingListState.error;

  List<NoteModel> get currentProfileNotes {
    return _profileNotesState.data ?? [];
  }

  bool get canLoadMoreProfileNotes => _profileNotesState.isLoaded && !_isLoadingMore;

  @override
  void onRetry() {
    if (_currentProfileNpub.isNotEmpty) {
      debugPrint('[ProfileViewModel] PROFILE MODE: Retrying profile and notes load for $_currentProfileNpub');
      loadProfile(_currentProfileNpub);
      loadProfileNotes(_currentProfileNpub);
    }
  }
}

class LoadProfileCommand extends ParameterizedCommand<String> {
  final ProfileViewModel _viewModel;

  LoadProfileCommand(this._viewModel);

  @override
  Future<void> executeImpl(String npub) => _viewModel.loadProfile(npub);
}

class UpdateProfileCommand extends ParameterizedCommand<Map<String, String?>> {
  final ProfileViewModel _viewModel;

  UpdateProfileCommand(this._viewModel);

  @override
  Future<void> executeImpl(Map<String, String?> updates) async {
    await _viewModel.updateProfile(
      name: updates['name'],
      about: updates['about'],
      profileImage: updates['profileImage'],
      banner: updates['banner'],
      website: updates['website'],
      nip05: updates['nip05'],
      lud16: updates['lud16'],
    );
  }
}

class ToggleFollowCommand extends ParameterlessCommand {
  final ProfileViewModel _viewModel;

  ToggleFollowCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.toggleFollow();
}

class LoadFollowingListCommand extends ParameterlessCommand {
  final ProfileViewModel _viewModel;

  LoadFollowingListCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.loadFollowingList();
}

class LoadProfileNotesCommand extends ParameterizedCommand<String> {
  final ProfileViewModel _viewModel;

  LoadProfileNotesCommand(this._viewModel);

  @override
  Future<void> executeImpl(String npub) => _viewModel.loadProfileNotes(npub);
}

class LoadMoreProfileNotesCommand extends ParameterlessCommand {
  final ProfileViewModel _viewModel;

  LoadMoreProfileNotesCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.loadMoreProfileNotes();
}
