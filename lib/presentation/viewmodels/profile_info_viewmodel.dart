import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/data_service.dart';
import '../../models/user_model.dart';

class ProfileInfoViewModel extends BaseViewModel {
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final DataService _dataService;
  final String userPubkeyHex;

  ProfileInfoViewModel({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required DataService dataService,
    required this.userPubkeyHex,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        _dataService = dataService {
    _loadInitialData();
    _setupUserStreamListener();
  }

  UserModel _user = UserModel.create(pubkeyHex: '', name: '');
  UserModel get user => _user;

  bool? _isFollowing;
  bool? get isFollowing => _isFollowing;

  bool? _isMuted;
  bool? get isMuted => _isMuted;

  bool? _doesUserFollowMe;
  bool? get doesUserFollowMe => _doesUserFollowMe;

  int _followingCount = 0;
  int get followingCount => _followingCount;

  int _followerCount = 0;
  int get followerCount => _followerCount;

  bool _isLoadingCounts = true;
  bool get isLoadingCounts => _isLoadingCounts;

  bool _isLoadingProfile = false;
  bool get isLoadingProfile => _isLoadingProfile;

  String? _currentUserNpub;
  String? get currentUserNpub => _currentUserNpub;

  void _loadInitialData() {
    _loadUserProfile();
    _initFollowStatus().then((_) {
      _loadFollowerCounts();
    });
  }

  void _setupUserStreamListener() {
    addSubscription(
      _userRepository.currentUserStream.listen((updatedUser) {
        if (isDisposed) return;

        if (updatedUser.pubkeyHex == userPubkeyHex) {
          _user = updatedUser;
          safeNotifyListeners();
        }
      }),
    );
  }

  Future<void> _loadUserProfile() async {
    if (_isLoadingProfile || isDisposed) return;

    await executeOperation('loadUserProfile', () async {
      _isLoadingProfile = true;
      safeNotifyListeners();

      final userResult = await _userRepository.getUserProfile(userPubkeyHex);
      userResult.fold(
        (loadedUser) {
          if (!isDisposed) {
            _user = loadedUser;
          }
        },
        (error) {
          if (!isDisposed) {
            safeNotifyListeners();
          }
        },
      );
    }, showLoading: false);

    if (!isDisposed) {
      _isLoadingProfile = false;
      safeNotifyListeners();
    }
  }

  Future<void> _initFollowStatus() async {
    await executeOperation('initFollowStatus', () async {
      final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
      if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
        return;
      }

      _currentUserNpub = currentUserNpubResult.data;

      if (_currentUserNpub == null || userPubkeyHex == _currentUserNpub) {
        return;
      }

      final followStatusResult = await _userRepository.isFollowing(userPubkeyHex);
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

      final muteStatusResult = await _userRepository.isMuted(userPubkeyHex);
      muteStatusResult.fold(
        (isMuted) {
          if (!isDisposed) {
            _isMuted = isMuted;
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            safeNotifyListeners();
          }
        },
      );

      if (!isDisposed && _currentUserNpub != null && !_isLoadingCounts) {
        _refreshDoesUserFollowMe();
      }
    }, showLoading: false);
  }

  Future<void> _refreshDoesUserFollowMe() async {
    if (_currentUserNpub == null || userPubkeyHex == _currentUserNpub || isDisposed) {
      return;
    }

    try {
      final followingResult = await _userRepository.getFollowingListForUser(userPubkeyHex);
      followingResult.fold(
        (followingUsers) {
          if (!isDisposed) {
            _checkIfUserFollowsMe(followingUsers);
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            _doesUserFollowMe = false;
            safeNotifyListeners();
          }
        },
      );
    } catch (e) {
      if (!isDisposed) {
        _doesUserFollowMe = false;
        safeNotifyListeners();
      }
    }
  }

  void _checkIfUserFollowsMe(List<UserModel> followingUsers) {
    if (_currentUserNpub == null || userPubkeyHex == _currentUserNpub) {
      _doesUserFollowMe = false;
      return;
    }

    final currentUserNpub = _currentUserNpub!;
    
    String? currentUserHex;
    try {
      if (currentUserNpub.startsWith('npub1')) {
        currentUserHex = _authRepository.npubToHex(currentUserNpub);
      } else {
        currentUserHex = currentUserNpub;
      }
    } catch (e) {
      currentUserHex = currentUserNpub;
    }

    if (currentUserHex == null) {
      currentUserHex = currentUserNpub;
    }

    final currentUserNpubNormalized = currentUserNpub.toLowerCase();
    final currentUserHexNormalized = currentUserHex.toLowerCase();

    _doesUserFollowMe = followingUsers.any((user) {
      final userPubkey = user.pubkeyHex;
      final userPubkeyNormalized = userPubkey.toLowerCase();
      
      if (userPubkeyNormalized == currentUserNpubNormalized || 
          userPubkeyNormalized == currentUserHexNormalized) {
        return true;
      }

      String? userHex;
      try {
        if (userPubkey.startsWith('npub1')) {
          userHex = _authRepository.npubToHex(userPubkey);
        } else {
          userHex = userPubkey;
        }
      } catch (e) {
        userHex = userPubkey;
      }

      if (userHex == null) {
        userHex = userPubkey;
      }

      final userHexNormalized = userHex.toLowerCase();

      return userHexNormalized == currentUserHexNormalized || 
             userHexNormalized == currentUserNpubNormalized ||
             userPubkeyNormalized == currentUserHexNormalized;
    });
  }

  Future<void> _loadFollowerCounts() async {
    if (isDisposed) return;

    await executeOperation('loadFollowerCounts', () async {
      _isLoadingCounts = true;
      safeNotifyListeners();

      final followingResult = await _userRepository.getFollowingListForUser(userPubkeyHex);
      followingResult.fold(
        (followingUsers) {
          if (!isDisposed) {
            _followingCount = followingUsers.length;
            
            _checkIfUserFollowsMe(followingUsers);
            
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            _followingCount = 0;
            _doesUserFollowMe = false;
            safeNotifyListeners();
          }
        },
      );

      final followerCount = await _dataService.fetchFollowerCount(userPubkeyHex);
      if (!isDisposed) {
        _followerCount = followerCount;
        _isLoadingCounts = false;
        safeNotifyListeners();
      }
    }, showLoading: false);
  }

  Future<void> toggleFollow() async {
    if (isDisposed) return;

    await executeOperation('toggleFollow', () async {
      if (_isFollowing == true) {
        final result = await _userRepository.unfollowUser(userPubkeyHex);
        result.fold(
          (_) {
            if (!isDisposed) {
              _isFollowing = false;
              safeNotifyListeners();
            }
          },
          (error) {
            if (!isDisposed) {
              safeNotifyListeners();
            }
          },
        );
      } else {
        final result = await _userRepository.followUser(userPubkeyHex);
        result.fold(
          (_) {
            if (!isDisposed) {
              _isFollowing = true;
              safeNotifyListeners();
            }
          },
          (error) {
            if (!isDisposed) {
              safeNotifyListeners();
            }
          },
        );
      }
    }, showLoading: false);
  }

  Future<void> toggleMute() async {
    if (isDisposed) return;

    await executeOperation('toggleMute', () async {
      if (_isMuted == true) {
        final result = await _userRepository.unmuteUser(userPubkeyHex);
        result.fold(
          (_) {
            if (!isDisposed) {
              _isMuted = false;
              safeNotifyListeners();
            }
          },
          (error) {
            if (!isDisposed) {
              safeNotifyListeners();
            }
          },
        );
      } else {
        final result = await _userRepository.muteUser(userPubkeyHex);
        result.fold(
          (_) {
            if (!isDisposed) {
              _isMuted = true;
              safeNotifyListeners();
            }
          },
          (error) {
            if (!isDisposed) {
              safeNotifyListeners();
            }
          },
        );
      }
    }, showLoading: false);
  }

  void updateUser(UserModel newUser) {
    if (_user != newUser) {
      _user = newUser;
      safeNotifyListeners();
    }
  }
}
