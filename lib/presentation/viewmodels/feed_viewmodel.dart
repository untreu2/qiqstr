import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';

/// ViewModel for the feed screen
/// Handles feed loading, real-time updates, and user interactions
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

  // State
  UIState<List<NoteModel>> _feedState = const InitialState();
  UIState<List<NoteModel>> get feedState => _feedState;

  UIState<String> _currentUserState = const InitialState();
  UIState<String> get currentUserState => _currentUserState;

  // Profiles state for batch user loading
  final Map<String, UserModel> _profiles = {};
  Map<String, UserModel> get profiles => Map.unmodifiable(_profiles);

  // Stream controller for profile updates
  final StreamController<Map<String, UserModel>> _profilesController = StreamController<Map<String, UserModel>>.broadcast();
  Stream<Map<String, UserModel>> get profilesStream => _profilesController.stream;

  NoteViewMode _viewMode = NoteViewMode.list;
  NoteViewMode get viewMode => _viewMode;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  String _currentUserNpub = '';
  String get currentUserNpub => _currentUserNpub;

  bool _isInitialized = false;
  bool _isLoadingFeed = false;

  // Commands - using nullable fields to prevent late initialization errors
  RefreshFeedCommand? _refreshFeedCommand;
  LoadMoreFeedCommand? _loadMoreFeedCommand;
  ChangeViewModeCommand? _changeViewModeCommand;

  // Getters for commands
  RefreshFeedCommand get refreshFeedCommand => _refreshFeedCommand ??= RefreshFeedCommand(this);
  LoadMoreFeedCommand get loadMoreFeedCommand => _loadMoreFeedCommand ??= LoadMoreFeedCommand(this);
  ChangeViewModeCommand get changeViewModeCommand => _changeViewModeCommand ??= ChangeViewModeCommand(this);

  @override
  void initialize() {
    super.initialize();

    // Register commands lazily
    registerCommand('refreshFeed', refreshFeedCommand);
    registerCommand('loadMoreFeed', loadMoreFeedCommand);
    registerCommand('changeViewMode', changeViewModeCommand);

    // Load current user after commands are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentUser();
    });
  }

  /// Initialize with specific user
  void initializeWithUser(String npub) {
    if (_isInitialized && _currentUserNpub == npub) {
      debugPrint('⏭️ [FeedViewModel] Already initialized for $npub, skipping');
      return;
    }

    debugPrint('[FeedViewModel] Initializing with user: $npub');
    _currentUserNpub = npub;
    _isInitialized = true;

    // Only do initial load, don't start real-time until it succeeds
    _loadFeed();
  }

  /// Load current authenticated user
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

  /// Load feed notes according to NIP-02 follow list
  Future<void> _loadFeed() async {
    if (_currentUserNpub.isEmpty) {
      debugPrint(' [FeedViewModel] Cannot load feed - no current user npub');
      return;
    }

    if (_isLoadingFeed) {
      debugPrint('⏭️ [FeedViewModel] Already loading feed, skipping');
      return;
    }

    _isLoadingFeed = true;
    debugPrint('[FeedViewModel] Loading feed for user: $_currentUserNpub');

    await executeOperation('loadFeed', () async {
      _feedState = const LoadingState();
      safeNotifyListeners();

      debugPrint(' [FeedViewModel] Requesting feed notes from repository...');

      // Get follow list first, then fetch notes from followed users
      final result = await _noteRepository.getFeedNotesFromFollowList(
        currentUserNpub: _currentUserNpub,
        limit: 50,
      );

      await result.fold(
        (notes) async {
          debugPrint(' [FeedViewModel] Repository returned ${notes.length} notes');

          if (notes.isEmpty) {
            debugPrint('[FeedViewModel] Empty feed - user may not be following anyone');
            _feedState = const LoadedState(<NoteModel>[]);
          } else {
            debugPrint(' [FeedViewModel] Setting loaded state with ${notes.length} real notes');
            _feedState = LoadedState(notes);

            // Load user profiles for all note authors
            await _loadUserProfilesForNotes(notes);
          }

          // Start real-time updates AFTER successful load
          _subscribeToRealTimeUpdates();
        },
        (error) async {
          debugPrint(' [FeedViewModel] Error loading feed: $error');
          _feedState = ErrorState(error);
        },
      );

      _isLoadingFeed = false;
      safeNotifyListeners();
    });
  }

  /// Refresh feed
  Future<void> refreshFeed() async {
    await _loadFeed();
  }

  /// Load more notes for pagination
  Future<void> loadMoreNotes() async {
    if (_isLoadingMore || _feedState is! LoadedState<List<NoteModel>>) return;

    _isLoadingMore = true;
    safeNotifyListeners();

    try {
      final currentNotes = (_feedState as LoadedState<List<NoteModel>>).data;
      final oldestNote = currentNotes.isNotEmpty ? currentNotes.last : null;

      final result = await _noteRepository.getFeedNotesFromFollowList(
        currentUserNpub: _currentUserNpub,
        limit: 25,
        until: oldestNote?.timestamp,
      );

      result.fold(
        (newNotes) {
          if (newNotes.isNotEmpty) {
            final allNotes = [...currentNotes, ...newNotes];
            _feedState = LoadedState(allNotes);

            // Load user profiles for new notes asynchronously
            _loadUserProfilesForNotes(newNotes);

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

  /// Change view mode (list/grid)
  void changeViewMode(NoteViewMode mode) {
    if (_viewMode != mode) {
      _viewMode = mode;
      safeNotifyListeners();
    }
  }

  /// Subscribe to real-time updates
  void _subscribeToRealTimeUpdates() {
    debugPrint('[FeedViewModel] Setting up real-time updates for user: $_currentUserNpub');

    // DON'T call startRealTimeFeed() as it causes duplicate loading
    // Just subscribe to existing stream updates
    addSubscription(
      _noteRepository.realTimeNotesStream.listen((notes) {
        debugPrint(' [FeedViewModel] Received stream update: ${notes.length} notes');

        if (!isDisposed && _feedState.isLoaded) {
          // Only update if we already have a successful state
          // Don't override successful loads with empty streams
          if (notes.isNotEmpty) {
            debugPrint(' [FeedViewModel] Updating feed state with ${notes.length} stream notes');
            _feedState = LoadedState(notes);
            safeNotifyListeners();
          } else {
            debugPrint('[FeedViewModel] Ignoring empty stream update to preserve loaded state');
          }
        } else {
          debugPrint(' [FeedViewModel] Not updating - disposed: $isDisposed, feedState: ${_feedState.runtimeType}');
        }
      }),
    );
  }

  /// Get current feed notes
  List<NoteModel> get currentNotes {
    return _feedState.data ?? [];
  }

  /// Check if we can load more notes
  bool get canLoadMore => _feedState.isLoaded && !_isLoadingMore && currentNotes.isNotEmpty;

  /// Check if feed is empty
  bool get isEmpty => _feedState.isEmpty;

  /// Check if feed is loading
  bool get isFeedLoading => _feedState.isLoading;

  /// Get error message if any
  String? get errorMessage => _feedState.error;

  /// Load user profiles for given notes
  Future<void> _loadUserProfilesForNotes(List<NoteModel> notes) async {
    try {
      debugPrint('[FeedViewModel] Loading user profiles for ${notes.length} notes');

      // Extract unique author IDs
      final Set<String> authorIds = {};
      for (final note in notes) {
        authorIds.add(note.author);
        if (note.repostedBy != null) {
          authorIds.add(note.repostedBy!);
        }
      }

      debugPrint('[FeedViewModel] Found ${authorIds.length} unique authors to load');

      // Load profiles in batches to avoid overwhelming the network
      final futures = <Future<void>>[];

      for (final authorId in authorIds) {
        // Skip if already cached
        if (_profiles.containsKey(authorId)) {
          continue;
        }

        // Add to batch loading
        futures.add(_loadSingleUserProfile(authorId));
      }

      // Wait for all profiles to load (with reasonable timeout)
      if (futures.isNotEmpty) {
        await Future.wait(futures).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('[FeedViewModel] Profile loading timed out, continuing with partial data');
            return [];
          },
        );
      }

      // Notify listeners about profile updates
      _profilesController.add(Map.from(_profiles));

      debugPrint('[FeedViewModel] Loaded ${_profiles.length} total user profiles');
    } catch (e) {
      debugPrint('[FeedViewModel] Error loading user profiles: $e');
      // Don't fail the entire feed load for profile errors
    }
  }

  /// Load a single user profile
  Future<void> _loadSingleUserProfile(String authorId) async {
    try {
      final result = await _userRepository.getUserProfile(authorId);
      result.fold(
        (user) {
          _profiles[authorId] = user;
          debugPrint('[FeedViewModel] Loaded profile for ${user.name} (${authorId.substring(0, 8)}...)');
        },
        (error) {
          debugPrint('[FeedViewModel] Failed to load profile for ${authorId.substring(0, 8)}...: $error');
          // Create a fallback user
          _profiles[authorId] = UserModel(
            pubkeyHex: authorId,
            name: authorId.length > 8 ? authorId.substring(0, 8) : authorId,
            about: '',
            profileImage: '',
            banner: '',
            website: '',
            nip05: '',
            lud16: '',
            updatedAt: DateTime.now(),
            nip05Verified: false,
          );
        },
      );
    } catch (e) {
      debugPrint('[FeedViewModel] Exception loading profile for ${authorId.substring(0, 8)}...: $e');
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

/// Commands for FeedViewModel
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

/// Note view modes
enum NoteViewMode {
  list, // List view
  grid, // Grid view
}
