import 'package:flutter/foundation.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../models/user_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/nostr_data_service.dart';
import '../../constants/suggestions.dart';

/// ViewModel for suggested follows functionality
class SuggestedFollowsViewModel extends BaseViewModel with CommandMixin {
  final UserRepository _userRepository;
  final NostrDataService _nostrDataService;

  SuggestedFollowsViewModel({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required NostrDataService nostrDataService,
  })  : _userRepository = userRepository,
        _nostrDataService = nostrDataService;

  // State
  UIState<List<UserModel>> _suggestedUsersState = const UIState.initial();
  UIState<List<UserModel>> get suggestedUsersState => _suggestedUsersState;

  final Set<String> _selectedUsers = {};
  Set<String> get selectedUsers => Set.unmodifiable(_selectedUsers);

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  @override
  void initialize() {
    super.initialize();

    // Register commands
    registerCommand('loadSuggestedUsers', SimpleCommand(_loadSuggestedUsers));
    registerCommand('followSelectedUsers', SimpleCommand(_followSelectedUsers));
    registerCommand('skipToHome', SimpleCommand(_skipToHome));

    // Load users immediately
    loadSuggestedUsers();
  }

  /// Public command methods
  void loadSuggestedUsers() => executeCommand('loadSuggestedUsers');
  void followSelectedUsers() => executeCommand('followSelectedUsers');
  void skipToHome() => executeCommand('skipToHome');

  void toggleUserSelection(String npub) {
    if (_selectedUsers.contains(npub)) {
      _selectedUsers.remove(npub);
    } else {
      _selectedUsers.add(npub);
    }
    safeNotifyListeners();
  }

  /// Load suggested users from constants list and fetch their profiles from relays
  Future<void> _loadSuggestedUsers() async {
    _suggestedUsersState = const UIState.loading();
    safeNotifyListeners();

    try {
      debugPrint('[SuggestedFollowsViewModel] Loading suggested users from constants...');

      final List<UserModel> users = [];

      // Load users from constants/suggestions.dart
      for (final pubkeyHex in suggestedUsers) {
        try {
          // Convert hex pubkey to npub
          final npub = _nostrDataService.authService.hexToNpub(pubkeyHex);
          if (npub != null) {
            debugPrint('[SuggestedFollowsViewModel] Fetching profile for: $npub');

            final result = await _userRepository.getUserProfile(npub);
            result.fold(
              (user) {
                users.add(user);
                debugPrint('[SuggestedFollowsViewModel] Added user: ${user.name} (${user.npub})');
              },
              (error) {
                debugPrint('[SuggestedFollowsViewModel] Failed to get profile for $npub: $error');
                // Create a fallback user with basic info if profile fetch fails
                final fallbackUser = UserModel(
                  pubkeyHex: npub,
                  name: 'Nostr User',
                  about: 'A Nostr user',
                  profileImage: '',
                  nip05: '',
                  banner: '',
                  lud16: '',
                  website: '',
                  updatedAt: DateTime.now(),
                );
                users.add(fallbackUser);
              },
            );
          } else {
            debugPrint('[SuggestedFollowsViewModel] Failed to convert hex to npub: $pubkeyHex');
          }

          // Small delay between profile fetches to not overwhelm relays
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          debugPrint('[SuggestedFollowsViewModel] Error loading user $pubkeyHex: $e');
        }
      }

      // Select all users by default
      _selectedUsers.clear();
      _selectedUsers.addAll(users.map((user) => user.npub));

      debugPrint('[SuggestedFollowsViewModel] Loaded ${users.length} suggested users successfully');
      _suggestedUsersState = UIState.loaded(users);
      safeNotifyListeners();
    } catch (e) {
      debugPrint('[SuggestedFollowsViewModel] Error loading suggested users: $e');
      _suggestedUsersState = UIState.error('Failed to load suggested users: $e');
      safeNotifyListeners();
    }
  }

  /// Follow selected users and navigate to home
  Future<void> _followSelectedUsers() async {
    if (_isProcessing) return;

    _isProcessing = true;
    safeNotifyListeners();

    debugPrint('[SuggestedFollowsViewModel] Following ${_selectedUsers.length} selected users...');

    // Follow selected users one by one
    int successCount = 0;
    for (String npub in _selectedUsers) {
      try {
        final result = await _userRepository.followUser(npub);
        result.fold(
          (success) {
            successCount++;
            debugPrint('[SuggestedFollowsViewModel] Successfully followed user: $npub');
          },
          (error) => debugPrint('[SuggestedFollowsViewModel] Failed to follow user $npub: $error'),
        );

        // Small delay between follow operations to not overwhelm relays
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('[SuggestedFollowsViewModel] Error following user $npub: $e');
      }
    }

    debugPrint('[SuggestedFollowsViewModel] Follow operation completed: $successCount/${_selectedUsers.length} users followed');

    _isProcessing = false;
    safeNotifyListeners();
  }

  /// Skip following and go to home
  Future<void> _skipToHome() async {
    if (_isProcessing) return;

    _isProcessing = true;
    safeNotifyListeners();

    // Clear selections
    _selectedUsers.clear();

    _isProcessing = false;
    safeNotifyListeners();
  }
}
