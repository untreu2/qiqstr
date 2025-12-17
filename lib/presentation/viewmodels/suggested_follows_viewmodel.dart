import 'package:flutter/foundation.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../models/user_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/data_service.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../constants/suggestions.dart';

class SuggestedFollowsViewModel extends BaseViewModel with CommandMixin {
  final UserRepository _userRepository;
  final DataService _nostrDataService;

  SuggestedFollowsViewModel({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required DataService nostrDataService,
  })  : _userRepository = userRepository,
        _nostrDataService = nostrDataService;

  UIState<List<UserModel>> _suggestedUsersState = const UIState.initial();
  UIState<List<UserModel>> get suggestedUsersState => _suggestedUsersState;

  final Set<String> _selectedUsers = {};
  Set<String> get selectedUsers => Set.unmodifiable(_selectedUsers);

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  @override
  void initialize() {
    super.initialize();

    registerCommand('loadSuggestedUsers', SimpleCommand(_loadSuggestedUsers));
    registerCommand('followSelectedUsers', SimpleCommand(_followSelectedUsers));
    registerCommand('skipToHome', SimpleCommand(_skipToHome));

    loadSuggestedUsers();
  }

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

  Future<void> _loadSuggestedUsers() async {
    _suggestedUsersState = const UIState.loading();
    safeNotifyListeners();

    try {
      debugPrint('[SuggestedFollowsViewModel] Loading ${suggestedUsers.length} suggested users with batch fetching...');

      final npubs = <String>[];
      for (final pubkeyHex in suggestedUsers) {
        final npub = _nostrDataService.authService.hexToNpub(pubkeyHex);
        if (npub != null) {
          npubs.add(npub);
        } else {
          debugPrint('[SuggestedFollowsViewModel] Failed to convert hex to npub: $pubkeyHex');
        }
      }

      debugPrint('[SuggestedFollowsViewModel] Batch fetching ${npubs.length} user profiles...');

      final results = await _userRepository.getUserProfiles(
        npubs,
        priority: FetchPriority.high,
      );

      final List<UserModel> users = [];
      for (final entry in results.entries) {
        entry.value.fold(
          (user) {
            users.add(user);
            debugPrint('[SuggestedFollowsViewModel] ✓ Loaded: ${user.name} (${user.npub.substring(0, 12)}...)');
          },
          (error) {
            debugPrint('[SuggestedFollowsViewModel] ✗ Failed to load ${entry.key}: $error');
            final fallbackUser = UserModel.create(
              pubkeyHex: entry.key,
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
      }

      _selectedUsers.clear();
      _selectedUsers.addAll(users.map((user) => user.npub));

      debugPrint('[SuggestedFollowsViewModel]  Loaded ${users.length} suggested users successfully');
      _suggestedUsersState = UIState.loaded(users);
      safeNotifyListeners();
    } catch (e) {
      debugPrint('[SuggestedFollowsViewModel]  Error loading suggested users: $e');
      _suggestedUsersState = UIState.error('Failed to load suggested users: $e');
      safeNotifyListeners();
    }
  }

  Future<void> _followSelectedUsers() async {
    if (_isProcessing) return;

    _isProcessing = true;
    safeNotifyListeners();

    debugPrint('[SuggestedFollowsViewModel] Following ${_selectedUsers.length} selected users...');

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

        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('[SuggestedFollowsViewModel] Error following user $npub: $e');
      }
    }

    debugPrint('[SuggestedFollowsViewModel] Follow operation completed: $successCount/${_selectedUsers.length} users followed');

    _isProcessing = false;
    safeNotifyListeners();
  }

  Future<void> _skipToHome() async {
    if (_isProcessing) return;

    _isProcessing = true;
    safeNotifyListeners();

    _selectedUsers.clear();

    _isProcessing = false;
    safeNotifyListeners();
  }
}
