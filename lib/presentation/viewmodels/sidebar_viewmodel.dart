import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/data_service.dart';
import '../../models/user_model.dart';

class SidebarViewModel extends BaseViewModel {
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final DataService _dataService;

  SidebarViewModel({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required DataService dataService,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        _dataService = dataService {
    _loadInitialUser();
    _setupUserStreamListener();
  }

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  int _followingCount = 0;
  int get followingCount => _followingCount;

  int _followerCount = 0;
  int get followerCount => _followerCount;

  bool _isLoadingCounts = true;
  bool get isLoadingCounts => _isLoadingCounts;

  void _setupUserStreamListener() {
    addSubscription(
      _userRepository.currentUserStream.listen(
        (updatedUser) {
          if (isDisposed) return;

          final hasChanges = _currentUser == null ||
              _currentUser!.npub != updatedUser.npub ||
              _currentUser!.profileImage != updatedUser.profileImage ||
              _currentUser!.name != updatedUser.name;

          if (hasChanges) {
            _currentUser = updatedUser;
            safeNotifyListeners();
            _loadFollowerCounts();
          }
        },
        onError: (error) {
          if (!isDisposed) {
            safeNotifyListeners();
          }
        },
      ),
    );
  }

  Future<void> _loadInitialUser() async {
    await executeOperation('loadInitialUser', () async {
      final npubResult = await _authRepository.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        return;
      }

      final userResult = await _userRepository.getUserProfile(npubResult.data!);
      userResult.fold(
        (user) {
          if (!isDisposed) {
            _currentUser = user;
            safeNotifyListeners();
            _loadFollowerCounts();
          }
        },
        (error) {
          if (!isDisposed) {
            safeNotifyListeners();
          }
        },
      );
    }, showLoading: false);
  }

  Future<void> _loadFollowerCounts() async {
    if (_currentUser == null || isDisposed) return;

    try {
      final followingResult = await _userRepository.getFollowingListForUser(_currentUser!.pubkeyHex);

      followingResult.fold(
        (followingUsers) {
          if (!isDisposed) {
            _followingCount = followingUsers.length;
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            _followingCount = 0;
            safeNotifyListeners();
          }
        },
      );

      final followerCount = await _dataService.fetchFollowerCount(_currentUser!.pubkeyHex);
      if (!isDisposed) {
        _followerCount = followerCount;
        _isLoadingCounts = false;
        safeNotifyListeners();

        if (followerCount > 0) {
          await _userRepository.updateUserFollowerCount(_currentUser!.pubkeyHex, followerCount);
        }
      }
    } catch (e) {
      if (!isDisposed) {
        _followingCount = 0;
        _followerCount = 0;
        _isLoadingCounts = false;
        safeNotifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    await _loadInitialUser();
  }
}
