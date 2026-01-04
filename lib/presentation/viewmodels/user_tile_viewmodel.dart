import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../models/user_model.dart';

class UserTileViewModel extends BaseViewModel {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final UserModel user;

  UserTileViewModel({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required this.user,
  })  : _userRepository = userRepository,
        _authRepository = authRepository {
    _checkFollowStatus();
    _setupFollowingListListener();
  }

  bool? _isFollowing;
  bool? get isFollowing => _isFollowing;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void _setupFollowingListListener() async {
    final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
    if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
      return;
    }

    addSubscription(
      _userRepository.followingListStream.listen(
        (followingList) {
          if (isDisposed) return;

          final targetUserHex = user.pubkeyHex;
          final isFollowing = followingList.any((u) => u.pubkeyHex == targetUserHex);

          if (_isFollowing != isFollowing) {
            _isFollowing = isFollowing;
            _isLoading = false;
            safeNotifyListeners();
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

  Future<void> _checkFollowStatus() async {
    await executeOperation('checkFollowStatus', () async {
      final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
      if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
        return;
      }

      final followStatusResult = await _userRepository.isFollowing(user.pubkeyHex);

      followStatusResult.fold(
        (isFollowing) {
          if (!isDisposed) {
            _isFollowing = isFollowing;
            safeNotifyListeners();
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

  Future<void> toggleFollow() async {
    if (_isLoading || isDisposed) return;

    _isLoading = true;
    safeNotifyListeners();

    await executeOperation('toggleFollow', () async {
      final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
      if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
        return;
      }

      if (_isFollowing == true) {
        final result = await _userRepository.unfollowUser(user.pubkeyHex);
        result.fold(
          (_) {
            if (!isDisposed) {
              _isFollowing = false;
            }
          },
          (error) {
            if (!isDisposed) {
              _isFollowing = true;
            }
          },
        );
      } else {
        final result = await _userRepository.followUser(user.pubkeyHex);
        result.fold(
          (_) {
            if (!isDisposed) {
              _isFollowing = true;
            }
          },
          (error) {
            if (!isDisposed) {
              _isFollowing = false;
            }
          },
        );
      }
    }, showLoading: false);

    if (!isDisposed) {
      _isLoading = false;
      safeNotifyListeners();
    }
  }
}
