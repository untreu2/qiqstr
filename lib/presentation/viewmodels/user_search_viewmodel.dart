import '../../core/base/base_view_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../models/user_model.dart';

class UserSearchViewModel extends BaseViewModel {
  final UserRepository _userRepository;

  UserSearchViewModel({
    required UserRepository userRepository,
  }) : _userRepository = userRepository {
    _loadRandomUsers();
  }

  List<UserModel> _filteredUsers = [];
  List<UserModel> get filteredUsers => _filteredUsers;

  List<UserModel> _randomUsers = [];
  List<UserModel> get randomUsers => _randomUsers;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  bool _isLoadingRandom = false;
  bool get isLoadingRandom => _isLoadingRandom;

  String? _error;
  String? get error => _error;

  Future<void> _loadRandomUsers() async {
    await executeOperation('loadRandomUsers', () async {
      _isLoadingRandom = true;
      safeNotifyListeners();

      final isarService = _userRepository.isarService;

      if (!isarService.isInitialized) {
        await isarService.waitForInitialization();
      }

      final randomIsarProfiles = await isarService.getRandomUsersWithImages(limit: 50);

      final userModels = randomIsarProfiles.map((isarProfile) {
        final profileData = isarProfile.toProfileData();
        return UserModel.fromCachedProfile(
          isarProfile.pubkeyHex,
          profileData,
        );
      }).toList();

      if (!isDisposed) {
        _randomUsers = userModels;
        _isLoadingRandom = false;
        safeNotifyListeners();
      }
    }, showLoading: false);
  }

  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _filteredUsers = [];
      _isSearching = false;
      _error = null;
      safeNotifyListeners();
      return;
    }

    await executeOperation('searchUsers', () async {
      _isSearching = true;
      _error = null;
      safeNotifyListeners();

      final result = await _userRepository.searchUsers(query);

      result.fold(
        (users) {
          if (!isDisposed) {
            _filteredUsers = users;
            _isSearching = false;
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            _error = error;
            _filteredUsers = [];
            _isSearching = false;
            safeNotifyListeners();
          }
        },
      );
    }, showLoading: false);
  }
}
