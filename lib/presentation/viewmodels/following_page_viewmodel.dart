import '../../core/base/base_view_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../models/user_model.dart';

class FollowingPageViewModel extends BaseViewModel {
  final UserRepository _userRepository;
  final String userNpub;

  FollowingPageViewModel({
    required UserRepository userRepository,
    required this.userNpub,
  }) : _userRepository = userRepository {
    _loadFollowingUsers();
  }

  List<UserModel> _followingUsers = [];
  List<UserModel> get followingUsers => _followingUsers;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  final Map<String, UserModel> _loadedUsers = {};
  Map<String, UserModel> get loadedUsers => Map.unmodifiable(_loadedUsers);

  Future<void> _loadFollowingUsers() async {
    await executeOperation('loadFollowingUsers', () async {
      _isLoading = true;
      _error = null;
      safeNotifyListeners();

      final result = await _userRepository.getFollowingListForUser(userNpub);

      result.fold(
        (users) async {
          if (!isDisposed) {
            _followingUsers = users;
            safeNotifyListeners();

            await _loadUserProfilesBatch(users);

            if (!isDisposed) {
              _isLoading = false;
              safeNotifyListeners();
            }
          }
        },
        (error) {
          if (!isDisposed) {
            _error = error;
            _isLoading = false;
            _followingUsers = [];
            safeNotifyListeners();
          }
        },
      );
    }, showLoading: false);
  }

  Future<void> _loadUserProfilesBatch(List<UserModel> users) async {
    final npubsToLoad = users
        .where((user) => !_loadedUsers.containsKey(user.npub))
        .map((user) => user.npub)
        .toList();

    if (npubsToLoad.isEmpty) return;

    try {
      final results = await _userRepository.getUserProfiles(npubsToLoad, priority: FetchPriority.high);

      if (!isDisposed) {
        for (final result in results.values) {
          result.fold(
            (user) {
              _loadedUsers[user.npub] = user;
            },
            (error) {
              // Skip failed results
            },
          );
        }
        safeNotifyListeners();
      }
    } catch (e) {
      if (!isDisposed) {
        safeNotifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    _loadedUsers.clear();
    await _loadFollowingUsers();
  }
}
