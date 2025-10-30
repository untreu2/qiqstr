import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/note_repository.dart';
import '../../models/user_model.dart';
import '../../models/note_model.dart';

class ProfileViewModel extends BaseViewModel with CommandMixin {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final NoteRepository _noteRepository;

  ProfileViewModel({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required NoteRepository noteRepository,
  })  : _userRepository = userRepository,
        _authRepository = authRepository,
        _noteRepository = noteRepository;

  UIState<UserModel> _profileState = const InitialState();
  UIState<UserModel> get profileState => _profileState;

  UIState<List<UserModel>> _followingListState = const InitialState();
  UIState<List<UserModel>> get followingListState => _followingListState;

  UIState<List<NoteModel>> _profileNotesState = const InitialState();
  UIState<List<NoteModel>> get profileNotesState => _profileNotesState;

  bool _isCurrentUser = false;
  bool get isCurrentUser => _isCurrentUser;

  bool _isFollowing = false;
  bool get isFollowing => _isFollowing;

  String _currentProfileNpub = '';
  String get currentProfileNpub => _currentProfileNpub;

  int _currentLimit = 200;
  int get currentLimit => _currentLimit;

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
    loadProfileNotes(npub);
  }

  Future<void> loadProfile(String npub) async {
    await executeOperation('loadProfile', () async {
      _profileState = const LoadingState();
      safeNotifyListeners();

      final result = await _userRepository.getUserProfile(npub);

      result.fold(
        (user) {
          _profileState = LoadedState(user);
          _isFollowing = user.nip05Verified; // This should be actual following status
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
        (_) {
        },
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

      debugPrint('[ProfileViewModel] PROFILE MODE: Loading notes for $userNpub (bypassing feed filters)');

      try {
        final result = await _noteRepository.getProfileNotes(
          authorNpub: userNpub,
          limit: _currentLimit,
        );

        result.fold(
          (notes) {
            debugPrint('[ProfileViewModel] PROFILE MODE: Loaded ${notes.length} profile notes');
            debugPrint(
                '[ProfileViewModel] PROFILE MODE: Notes breakdown - Posts: ${notes.where((n) => !n.isReply && !n.isRepost).length}, Replies: ${notes.where((n) => n.isReply && !n.isRepost).length}, Reposts: ${notes.where((n) => n.isRepost).length}');

            final filteredNotes = notes.where((note) {
              if (!note.isReply && !note.isRepost) {
                return true;
              }

              if (note.isRepost) {
                return true;
              }

              if (note.isReply && !note.isRepost) {
                return false;
              }

              return true;
            }).toList();

            debugPrint(
                '[ProfileViewModel] PROFILE MODE: After filtering - ${filteredNotes.length} notes (${notes.length - filteredNotes.length} standalone replies hidden)');
            debugPrint(
                '[ProfileViewModel] PROFILE MODE: Filtered breakdown - Posts: ${filteredNotes.where((n) => !n.isReply && !n.isRepost).length}, Reposts: ${filteredNotes.where((n) => n.isRepost).length}');

            _profileNotesState = filteredNotes.isEmpty ? const EmptyState('No notes from this user yet') : LoadedState(filteredNotes);
          },
          (error) {
            debugPrint('[ProfileViewModel] PROFILE MODE: Failed to load profile notes: $error');
            _profileNotesState = ErrorState('Failed to load notes: $error');
          },
        );
      } catch (e) {
        debugPrint('[ProfileViewModel] PROFILE MODE: Exception loading profile notes: $e');
        _profileNotesState = ErrorState('Exception loading notes: $e');
      }

      safeNotifyListeners();
    });
  }

  Future<void> loadMoreProfileNotes() async {
    if (_isLoadingMore || _profileNotesState is! LoadedState<List<NoteModel>>) return;

    _isLoadingMore = true;
    safeNotifyListeners();

    try {
      _currentLimit += 50;
      debugPrint('[ProfileViewModel] Loading more profile notes with new limit: $_currentLimit');

      final result = await _noteRepository.getProfileNotes(
        authorNpub: _currentProfileNpub,
        limit: _currentLimit,
      );

      result.fold(
        (notes) {
          if (notes.isNotEmpty) {
            final filteredNotes = notes.where((note) {
              if (!note.isReply && !note.isRepost) {
                return true;
              }

              if (note.isRepost) {
                return true;
              }

              if (note.isReply && !note.isRepost) {
                return false;
              }

              return true;
            }).toList();

            _profileNotesState = filteredNotes.isEmpty ? const EmptyState('No notes from this user yet') : LoadedState(filteredNotes);
            safeNotifyListeners();
          }
        },
        (error) {
          debugPrint('[ProfileViewModel] Error loading more profile notes: $error');
          _profileNotesState = ErrorState('Failed to load more notes: $error');
          safeNotifyListeners();
        },
      );
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
          _isCurrentUser = currentNpub == _currentProfileNpub;
          safeNotifyListeners();
        },
        (_) => _isCurrentUser = false,
      );
    } catch (e) {
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
