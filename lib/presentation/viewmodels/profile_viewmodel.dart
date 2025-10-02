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

/// ViewModel for profile-related screens
/// Handles user profile display, editing, and user interactions
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

  // State
  UIState<UserModel> _profileState = const InitialState();
  UIState<UserModel> get profileState => _profileState;

  UIState<List<UserModel>> _followingListState = const InitialState();
  UIState<List<UserModel>> get followingListState => _followingListState;

  // Profile notes state - shows THIS user's notes and reposts
  UIState<List<NoteModel>> _profileNotesState = const InitialState();
  UIState<List<NoteModel>> get profileNotesState => _profileNotesState;

  bool _isCurrentUser = false;
  bool get isCurrentUser => _isCurrentUser;

  bool _isFollowing = false;
  bool get isFollowing => _isFollowing;

  String _currentProfileNpub = '';
  String get currentProfileNpub => _currentProfileNpub;

  // Commands - using nullable fields to prevent late initialization errors
  LoadProfileCommand? _loadProfileCommand;
  UpdateProfileCommand? _updateProfileCommand;
  ToggleFollowCommand? _toggleFollowCommand;
  LoadFollowingListCommand? _loadFollowingListCommand;
  LoadProfileNotesCommand? _loadProfileNotesCommand;

  // Getters for commands
  LoadProfileCommand get loadProfileCommand => _loadProfileCommand ??= LoadProfileCommand(this);
  UpdateProfileCommand get updateProfileCommand => _updateProfileCommand ??= UpdateProfileCommand(this);
  ToggleFollowCommand get toggleFollowCommand => _toggleFollowCommand ??= ToggleFollowCommand(this);
  LoadFollowingListCommand get loadFollowingListCommand => _loadFollowingListCommand ??= LoadFollowingListCommand(this);
  LoadProfileNotesCommand get loadProfileNotesCommand => _loadProfileNotesCommand ??= LoadProfileNotesCommand(this);

  @override
  void initialize() {
    super.initialize();

    // Register commands lazily
    registerCommand('loadProfile', loadProfileCommand);
    registerCommand('updateProfile', updateProfileCommand);
    registerCommand('toggleFollow', toggleFollowCommand);
    registerCommand('loadFollowingList', loadFollowingListCommand);
    registerCommand('loadProfileNotes', loadProfileNotesCommand);

    _subscribeToUserUpdates();
  }

  /// Initialize with specific user npub
  void initializeWithUser(String npub) {
    _currentProfileNpub = npub;
    _checkIfCurrentUser();
    loadProfileCommand.execute(npub);
    // Also load this user's notes and reposts
    loadProfileNotes(npub);
  }

  /// Load user profile
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

  /// Update current user profile
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
          _userRepository.cacheUser(updatedUser);
        },
        (error) => _profileState = ErrorState(error),
      );

      safeNotifyListeners();
    });
  }

  /// Toggle follow/unfollow user
  Future<void> toggleFollow() async {
    if (_isCurrentUser) {
      setError(ValidationError(message: 'Cannot follow yourself'));
      return;
    }

    await executeOperation('toggleFollow', () async {
      final wasFollowing = _isFollowing;

      // Optimistic update
      _isFollowing = !_isFollowing;
      safeNotifyListeners();

      final result =
          wasFollowing ? await _userRepository.unfollowUser(_currentProfileNpub) : await _userRepository.followUser(_currentProfileNpub);

      result.fold(
        (_) {
          // Success - optimistic update was correct
        },
        (error) {
          // Revert optimistic update
          _isFollowing = wasFollowing;
          setError(NetworkError(message: 'Failed to ${wasFollowing ? 'unfollow' : 'follow'} user: $error'));
          safeNotifyListeners();
        },
      );
    }, showLoading: false);
  }

  /// Load following list for current user
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

  /// Load profile notes for specific user (their posts AND reposts)
  Future<void> loadProfileNotes(String userNpub) async {
    await executeOperation('loadProfileNotes', () async {
      _profileNotesState = const LoadingState();
      safeNotifyListeners();

      debugPrint('[ProfileViewModel] Loading profile notes for: $userNpub');

      try {
        // Get profile notes (user's own posts AND their reposts)
        final result = await _noteRepository.getProfileNotes(
          authorNpub: userNpub,
          limit: 50,
        );

        result.fold(
          (notes) {
            debugPrint('[ProfileViewModel] Loaded ${notes.length} profile notes');
            _profileNotesState = notes.isEmpty ? const EmptyState('No notes from this user yet') : LoadedState(notes);
          },
          (error) {
            debugPrint('[ProfileViewModel] Failed to load profile notes: $error');
            _profileNotesState = ErrorState('Failed to load notes: $error');
          },
        );
      } catch (e) {
        debugPrint('[ProfileViewModel] Exception loading profile notes: $e');
        _profileNotesState = ErrorState('Exception loading notes: $e');
      }

      safeNotifyListeners();
    });
  }

  /// Check if the profile belongs to current user
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

  /// Subscribe to user updates
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

  /// Get current profile user
  UserModel? get currentProfile {
    return _profileState.data;
  }

  /// Get following list
  List<UserModel> get followingList {
    return _followingListState.data ?? [];
  }

  /// Check if profile is loading
  bool get isProfileLoading => _profileState.isLoading;

  /// Check if following list is loading
  bool get isFollowingListLoading => _followingListState.isLoading;

  /// Get profile error message if any
  String? get profileErrorMessage => _profileState.error;

  /// Get following list error message if any
  String? get followingListErrorMessage => _followingListState.error;

  @override
  void onRetry() {
    if (_currentProfileNpub.isNotEmpty) {
      loadProfile(_currentProfileNpub);
      loadProfileNotes(_currentProfileNpub);
    }
  }
}

/// Commands for ProfileViewModel
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
