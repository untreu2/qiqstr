import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/user_model.dart';
import '../../theme/theme_manager.dart';
import '../../screens/profile/edit_profile.dart';
import '../../screens/profile/following_page.dart';
import '../media/photo_viewer_widget.dart';
import '../note/note_content_widget.dart';
import '../common/snackbar_widget.dart';
import '../dialogs/unfollow_user_dialog.dart';
import '../dialogs/mute_user_dialog.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';

class ProfileInfoWidget extends StatefulWidget {
  final UserModel user;
  final Function(String)? onNavigateToProfile;

  const ProfileInfoWidget({
    super.key,
    required this.user,
    this.onNavigateToProfile,
  });

  @override
  State<ProfileInfoWidget> createState() => _ProfileInfoWidgetState();
}

class _ProfileInfoWidgetState extends State<ProfileInfoWidget> {
  bool? _isFollowing;
  bool? _isMuted;
  String? _currentUserNpub;
  late AuthRepository _authRepository;
  late UserRepository _userRepository;

  bool _isInitialized = false;

  int _followingCount = 0;
  int _followerCount = 0;
  bool _isLoadingCounts = true;
  bool? _doesUserFollowMe;

  String? _userHexKey;

  final ValueNotifier<UserModel> _userNotifier = ValueNotifier(UserModel.create(
    pubkeyHex: '',
    name: '',
  ));

  bool _isLoadingProfile = false;
  StreamSubscription<UserModel>? _userStreamSubscription;

  Map<String, dynamic> _parseBioContent(String bioText) {
    if (bioText.isEmpty) {
      return {
        'textParts': <Map<String, dynamic>>[],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
      };
    }

    return {
      'textParts': [
        {
          'type': 'text',
          'text': bioText,
        }
      ],
      'mediaUrls': <String>[],
      'linkUrls': <String>[],
      'quoteIds': <String>[],
    };
  }

  Widget _buildBioContent(UserModel user) {
    if (user.about.isEmpty) {
      return const SizedBox.shrink();
    }

    final parsedContent = _parseBioContent(user.about);

    return NoteContentWidget(
      parsedContent: parsedContent,
      noteId: 'bio_${user.pubkeyHex}',
      onNavigateToMentionProfile: widget.onNavigateToProfile,
      size: NoteContentSize.small,
    );
  }

  @override
  void initState() {
    super.initState();
    _authRepository = AppDI.get<AuthRepository>();
    _userRepository = AppDI.get<UserRepository>();

    _userHexKey = _convertToHex(widget.user.pubkeyHex);
    _startProgressiveInitialization();
    _setupUserStreamListener();
  }

  @override
  void didUpdateWidget(ProfileInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  void _startProgressiveInitialization() {
    _userNotifier.value = widget.user;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initBasicData();
        _loadUserProfileAsync();
        _initFollowStatusAsync();
        _loadFollowerCounts();
      }
    });
  }

  void _initBasicData() {
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _loadUserProfileAsync() async {
    if (_isLoadingProfile || !mounted) return;

    try {
      _isLoadingProfile = true;
      debugPrint('[ProfileInfoWidget] Loading fresh profile data for: ${_userNotifier.value.pubkeyHex}');

      await _userRepository.invalidateUserCache(_userNotifier.value.pubkeyHex);
      final result = await _userRepository.getUserProfile(_userNotifier.value.pubkeyHex);

      result.fold(
        (updatedUser) {
          debugPrint('[ProfileInfoWidget] Fresh profile loaded: ${updatedUser.name}');
          if (mounted) {
            _userNotifier.value = updatedUser;
          }
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Failed to load fresh profile: $error');
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Load user profile async error: $e');
    } finally {
      _isLoadingProfile = false;
    }
  }

  void _setupUserStreamListener() {
    _userStreamSubscription = _userRepository.currentUserStream.listen(
      (updatedUser) {
        if (updatedUser.pubkeyHex == widget.user.pubkeyHex || updatedUser.pubkeyHex == _userNotifier.value.pubkeyHex) {
          debugPrint('[ProfileInfoWidget] Received updated user data from stream: ${updatedUser.name}');
          if (mounted) {
            _userNotifier.value = updatedUser;
            _loadFollowerCounts();
          }
        }
      },
      onError: (error) {
        debugPrint('[ProfileInfoWidget] Error in user stream: $error');
      },
    );
  }

  @override
  void dispose() {
    _userStreamSubscription?.cancel();
    _userNotifier.dispose();
    super.dispose();
  }

  Future<void> _initFollowStatusAsync() async {
    try {
      final result = await _authRepository.getCurrentUserNpub();
      result.fold(
        (npub) => _currentUserNpub = npub,
        (error) => _currentUserNpub = null,
      );

      if (mounted) {
        setState(() {});
      }

      if (_currentUserNpub == null || _userHexKey == null) return;

      String? currentUserHex = _convertToHex(_currentUserNpub!);
      if (currentUserHex == _userHexKey) return;

      await _checkFollowStatus();
      await _checkMuteStatus();

      await _checkIfUserFollowsMe();
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Follow status init error: $e');
    }
  }

  Future<void> _checkFollowStatus() async {
    try {
      if (_currentUserNpub == null) return;

      final followStatusResult = await _userRepository.isFollowing(_userNotifier.value.pubkeyHex);

      followStatusResult.fold(
        (isFollowing) {
          debugPrint('[ProfileInfoWidget] Follow check result: $isFollowing for ${_userNotifier.value.pubkeyHex}');

          if (mounted) {
            setState(() {
              _isFollowing = isFollowing;
            });
          }
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Error checking follow status: $error');
          if (mounted) {
            setState(() {
              _isFollowing = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Error checking follow status: $e');
    }
  }

  Future<void> _checkMuteStatus() async {
    try {
      if (_currentUserNpub == null) return;

      final muteStatusResult = await _userRepository.isMuted(_userNotifier.value.pubkeyHex);

      muteStatusResult.fold(
        (isMuted) {
          debugPrint('[ProfileInfoWidget] Mute check result: $isMuted for ${_userNotifier.value.pubkeyHex}');

          if (mounted) {
            setState(() {
              _isMuted = isMuted;
            });
          }
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Error checking mute status: $error');
          if (mounted) {
            setState(() {
              _isMuted = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Error checking mute status: $e');
    }
  }

  Future<void> _checkIfUserFollowsMe() async {
    try {
      if (_currentUserNpub == null) return;

      debugPrint('[ProfileInfoWidget] Checking if ${_userNotifier.value.pubkeyHex} follows $_currentUserNpub');

      final followingResult = await _userRepository.getFollowingListForUser(_userNotifier.value.pubkeyHex);

      followingResult.fold(
        (followingUsers) {
          final currentUserHex = _convertToHex(_currentUserNpub!);
          final followingHexList = followingUsers.map((u) => u.pubkeyHex).toList();

          final doesFollow = currentUserHex != null && followingHexList.contains(currentUserHex);

          debugPrint('[ProfileInfoWidget] Does ${_userNotifier.value.pubkeyHex} follow $_currentUserNpub? $doesFollow');
          debugPrint('[ProfileInfoWidget] Current user hex: $currentUserHex');
          debugPrint('[ProfileInfoWidget] Following list length: ${followingHexList.length}');

          if (mounted) {
            setState(() {
              _doesUserFollowMe = doesFollow;
            });
          }
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Error checking if user follows me: $error');
          if (mounted) {
            setState(() {
              _doesUserFollowMe = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Error checking if user follows me: $e');
      if (mounted) {
        setState(() {
          _doesUserFollowMe = false;
        });
      }
    }
  }

  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  String? _convertToHex(String npub) {
    try {
      if (npub.startsWith('npub1')) {
        return decodeBasicBech32(npub, 'npub');
      } else if (_isValidHex(npub)) {
        return npub;
      }
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Error converting npub to hex: $e');
    }
    return npub;
  }

  Future<void> _toggleFollow() async {
    if (_currentUserNpub == null || _userHexKey == null) {
      debugPrint('[ProfileInfoWidget] Toggle follow aborted - missing current user or hex key');
      return;
    }

    final originalFollowState = _isFollowing;

    if (originalFollowState == true) {
      final userName = _userNotifier.value.name.isNotEmpty
          ? _userNotifier.value.name
          : (_userNotifier.value.nip05.isNotEmpty
              ? _userNotifier.value.nip05.split('@').first
              : 'this user');

      showUnfollowUserDialog(
        context: context,
        userName: userName,
        onConfirm: () => _performUnfollow(),
      );
      return;
    }

    _performFollow();
  }

  Future<void> _performFollow() async {
    if (_currentUserNpub == null || _userHexKey == null) {
      return;
    }

    final originalFollowState = _isFollowing;

    debugPrint('=== [ProfileInfoWidget] FOLLOW OPERATION START ===');
    debugPrint('[ProfileInfoWidget] Original follow state: $originalFollowState');
    debugPrint('[ProfileInfoWidget] Current user npub: $_currentUserNpub');
    debugPrint('[ProfileInfoWidget] Target user npub: ${_userNotifier.value.pubkeyHex}');
    debugPrint('[ProfileInfoWidget] Target user hex: $_userHexKey');

    setState(() {
      _isFollowing = !_isFollowing!;
    });

    debugPrint('[ProfileInfoWidget] UI optimistically updated to: $_isFollowing');

    try {
      final currentUser = _userNotifier.value;
      final targetNpub = currentUser.pubkeyHex.startsWith('npub1')
          ? currentUser.pubkeyHex
          : (_userHexKey != null && _userHexKey!.length == 64)
              ? _getNpubBech32(_userHexKey!)
              : currentUser.pubkeyHex;

      debugPrint('[ProfileInfoWidget] Using npub for operation: $targetNpub');

      final result = await _userRepository.followUser(targetNpub);

      debugPrint('[ProfileInfoWidget] Repository operation completed');

      result.fold(
        (_) {
          debugPrint('[ProfileInfoWidget] Follow toggle successful');
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              _checkFollowStatus();
            }
          });
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Follow toggle error: $error');

          setState(() {
            _isFollowing = originalFollowState;
          });

          if (mounted) {
            AppSnackbar.error(context, 'Failed to follow user: $error');
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Follow toggle exception: $e');
      setState(() {
        _isFollowing = originalFollowState;
      });
    }
  }

  Future<void> _performUnfollow() async {
    if (_currentUserNpub == null || _userHexKey == null) {
      return;
    }

    final originalFollowState = _isFollowing;

    debugPrint('=== [ProfileInfoWidget] UNFOLLOW OPERATION START ===');
    debugPrint('[ProfileInfoWidget] Original follow state: $originalFollowState');
    debugPrint('[ProfileInfoWidget] Current user npub: $_currentUserNpub');
    debugPrint('[ProfileInfoWidget] Target user npub: ${_userNotifier.value.pubkeyHex}');
    debugPrint('[ProfileInfoWidget] Target user hex: $_userHexKey');

    setState(() {
      _isFollowing = !_isFollowing!;
    });

    debugPrint('[ProfileInfoWidget] UI optimistically updated to: $_isFollowing');

    try {
      final currentUser = _userNotifier.value;
      final targetNpub = currentUser.pubkeyHex.startsWith('npub1')
          ? currentUser.pubkeyHex
          : (_userHexKey != null && _userHexKey!.length == 64)
              ? _getNpubBech32(_userHexKey!)
              : currentUser.pubkeyHex;

      debugPrint('[ProfileInfoWidget] Using npub for operation: $targetNpub');

      final result = await _userRepository.unfollowUser(targetNpub);

      debugPrint('[ProfileInfoWidget] Repository operation completed');

      result.fold(
        (_) {
          debugPrint('[ProfileInfoWidget] Unfollow toggle successful');
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              _checkFollowStatus();
            }
          });
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Unfollow toggle error: $error');

          setState(() {
            _isFollowing = originalFollowState;
          });

          if (mounted) {
            AppSnackbar.error(context, 'Failed to unfollow user: $error');
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Unfollow toggle exception: $e');
      setState(() {
        _isFollowing = originalFollowState;
      });
    }
  }

  Future<void> _loadFollowerCounts() async {
    try {
      final followingResult = await _userRepository.getFollowingListForUser(_userNotifier.value.pubkeyHex);

      followingResult.fold(
        (followingUsers) {
          if (mounted) {
            setState(() {
              _followingCount = followingUsers.length;
            });
          }
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Error loading following count: $error');
          if (mounted) {
            setState(() {
              _followingCount = 0;
            });
          }
        },
      );

      final nostrDataService = AppDI.get<DataService>();
      final followerCount = await nostrDataService.fetchFollowerCount(_userNotifier.value.pubkeyHex);
      if (mounted) {
        setState(() {
          _followerCount = followerCount;
          _isLoadingCounts = false;
        });
        if (followerCount > 0) {
          await _userRepository.updateUserFollowerCount(_userNotifier.value.pubkeyHex, followerCount);
        }
      }
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Error loading follower counts: $e');
      if (mounted) {
        setState(() {
          _followingCount = 0;
          _followerCount = 0;
          _isLoadingCounts = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel>(
      valueListenable: _userNotifier,
      builder: (context, user, _) {
        final screenWidth = MediaQuery.of(context).size.width;
        final websiteUrl = user.website.isNotEmpty && !(user.website.startsWith("http://") || user.website.startsWith("https://"))
            ? "https://${user.website}"
            : user.website;

        return Container(
          color: context.colors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOptimizedBanner(context, user, screenWidth),
              Container(
                transform: Matrix4.translationValues(0, -16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatarAndActionsRow(context, user),
                    const SizedBox(height: 2),
                    _buildNameRow(context, user),
                    if (user.about.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _buildBioContent(user),
                      const SizedBox(height: 4),
                    ],
                    if (user.website.isNotEmpty && _isInitialized) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () async {
                          final Uri url = Uri.parse(websiteUrl);
                          if (!await launchUrl(url)) {
                            throw Exception('Could not launch $url');
                          }
                        },
                        child: InkWell(
                          child: Text(
                            user.website,
                            style: const TextStyle(
                              decoration: TextDecoration.underline,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    _buildFollowerInfo(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static final Map<String, Widget> _avatarCache = <String, Widget>{};

  Widget _getCachedAvatar(String imageUrl, double radius, String cacheKey) {
    return _avatarCache.putIfAbsent(cacheKey, () {
      try {
        Widget avatarWidget;

        if (imageUrl.isEmpty) {
          avatarWidget = CircleAvatar(
            radius: radius,
            backgroundColor: context.colors.surfaceTransparent,
            child: Icon(
              Icons.person,
              size: radius,
              color: context.colors.textSecondary,
            ),
          );
        } else {
          avatarWidget = CircleAvatar(
            radius: radius,
            backgroundColor: context.colors.surfaceTransparent,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                memCacheWidth: (radius * 5).toInt(),
                maxHeightDiskCache: (radius * 5).toInt(),
                maxWidthDiskCache: (radius * 5).toInt(),
                placeholder: (context, url) => Icon(
                  Icons.person,
                  size: radius,
                  color: context.colors.textSecondary,
                ),
                errorWidget: (context, url, error) => Icon(
                  Icons.person,
                  size: radius,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          );
        }

        return avatarWidget;
      } catch (e) {
        debugPrint('[ProfileInfoWidget] Avatar cache error: $e');
        return CircleAvatar(
          radius: radius,
          backgroundColor: context.colors.surfaceTransparent,
          child: Icon(
            Icons.person,
            size: radius,
            color: context.colors.textSecondary,
          ),
        );
      }
    });
  }

  Widget _buildAvatar(UserModel user) {
    return ValueListenableBuilder<UserModel>(
      valueListenable: _userNotifier,
      builder: (context, currentUser, _) {
        final avatarRadius = 40.0;
        final cacheKey = 'profile_large_${currentUser.pubkeyHex}_${currentUser.profileImage.hashCode}';

        Widget avatar = RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
              color: context.colors.background,
              width: 3,
            ),
            ),
            child: _getCachedAvatar(
              currentUser.profileImage,
              avatarRadius,
              cacheKey,
            ),
          ),
        );

        if (currentUser.profileImage.isNotEmpty) {
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoViewerWidget(imageUrls: [currentUser.profileImage]),
                ),
              );
            },
            child: avatar,
          );
        }

        return avatar;
      },
    );
  }

  Widget _buildNameRow(BuildContext context, UserModel user) {
    return Row(
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  user.name.isNotEmpty ? user.name : (user.nip05.isNotEmpty ? user.nip05.split('@').first : 'Anonymous'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (user.nip05.isNotEmpty && user.nip05Verified) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showVerificationTooltip(context, user.nip05),
                  child: Icon(
                    Icons.verified,
                    size: 22,
                    color: context.colors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showVerificationTooltip(BuildContext context, String nip05) {
    final domain = nip05.split('@').last;
    AppSnackbar.info(context, 'This user is verified by $domain');
  }

  Widget _buildOptimizedBanner(BuildContext context, UserModel user, double screenWidth) {
    final double bannerHeight = screenWidth * (3.5 / 10);

    return GestureDetector(
      onTap: () {
        if (user.banner.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PhotoViewerWidget(imageUrls: [user.banner]),
            ),
          );
        }
      },
      child: user.banner.isNotEmpty
          ? CachedNetworkImage(
              key: ValueKey('banner_image_${user.pubkeyHex}_${user.banner.hashCode}'),
              imageUrl: user.banner,
              width: screenWidth,
              height: bannerHeight,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              memCacheHeight: (bannerHeight * 2).round(),
              maxHeightDiskCache: (bannerHeight * 3).round(),
              placeholder: (_, __) => Container(
                height: bannerHeight,
                width: screenWidth,
                color: context.colors.grey700,
              ),
              errorWidget: (_, __, ___) => Container(
                height: bannerHeight,
                width: screenWidth,
                color: context.colors.background,
              ),
            )
          : Container(
              height: bannerHeight,
              width: screenWidth,
              color: context.colors.background,
            ),
    );
  }

  Widget _buildAvatarAndActionsRow(BuildContext context, UserModel user) {
    final isOwnProfile = _isCurrentUserProfile();

    return Row(
      children: [
        _buildAvatar(user),
        const Spacer(),
        if (_currentUserNpub != null && !isOwnProfile)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isMuted != null) ...[
                  _buildMuteButton(context),
                  const SizedBox(width: 8),
                ],
                if (_isFollowing != null)
                  _buildFollowButton(context),
              ],
            ),
          )
        else if (_currentUserNpub != null && isOwnProfile)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _buildEditProfileButton(context),
          ),
      ],
    );
  }

  bool _isCurrentUserProfile() {
    if (_currentUserNpub == null || _userHexKey == null) return false;

    String? currentUserHex = _convertToHex(_currentUserNpub!);
    return currentUserHex == _userHexKey;
  }

  Widget _buildEditProfileButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const EditOwnProfilePage(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(
          'Edit profile',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleMute() async {
    if (_currentUserNpub == null || _userHexKey == null) {
      debugPrint('[ProfileInfoWidget] Toggle mute aborted - missing current user or hex key');
      return;
    }

    final originalMuteState = _isMuted;
    final shouldMute = !(originalMuteState ?? false);

    if (shouldMute) {
      final userName = _userNotifier.value.name.isNotEmpty
          ? _userNotifier.value.name
          : (_userNotifier.value.nip05.isNotEmpty
              ? _userNotifier.value.nip05.split('@').first
              : 'this user');

      showMuteUserDialog(
        context: context,
        userName: userName,
        onConfirm: () => _performMute(),
      );
      return;
    }

    _performUnmute();
  }

  Future<void> _performMute() async {
    if (_currentUserNpub == null || _userHexKey == null) {
      return;
    }

    final originalMuteState = _isMuted;

    setState(() {
      _isMuted = true;
    });

    try {
      final currentUser = _userNotifier.value;
      final targetNpub = currentUser.pubkeyHex.startsWith('npub1')
          ? currentUser.pubkeyHex
          : (_userHexKey != null && _userHexKey!.length == 64)
              ? _getNpubBech32(_userHexKey!)
              : currentUser.pubkeyHex;

      final result = await _userRepository.muteUser(targetNpub);

      result.fold(
        (_) {
          debugPrint('[ProfileInfoWidget] Mute successful');
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              _checkMuteStatus();
            }
          });
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Mute error: $error');

          setState(() {
            _isMuted = originalMuteState;
          });

          if (mounted) {
            AppSnackbar.error(context, 'Failed to mute user: $error');
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Mute exception: $e');
      setState(() {
        _isMuted = originalMuteState;
      });
    }
  }

  Future<void> _performUnmute() async {
    if (_currentUserNpub == null || _userHexKey == null) {
      return;
    }

    final originalMuteState = _isMuted;

    setState(() {
      _isMuted = false;
    });

    try {
      final currentUser = _userNotifier.value;
      final targetNpub = currentUser.pubkeyHex.startsWith('npub1')
          ? currentUser.pubkeyHex
          : (_userHexKey != null && _userHexKey!.length == 64)
              ? _getNpubBech32(_userHexKey!)
              : currentUser.pubkeyHex;

      final result = await _userRepository.unmuteUser(targetNpub);

      result.fold(
        (_) {
          debugPrint('[ProfileInfoWidget] Unmute successful');
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              _checkMuteStatus();
            }
          });
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Unmute error: $error');

          setState(() {
            _isMuted = originalMuteState;
          });

          if (mounted) {
            AppSnackbar.error(context, 'Failed to unmute user: $error');
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Unmute exception: $e');
      setState(() {
        _isMuted = originalMuteState;
      });
    }
  }

  Widget _buildMuteButton(BuildContext context) {
    final isMuted = _isMuted!;
    return GestureDetector(
      onTap: _toggleMute,
      child: Container(
        padding: isMuted
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
            : const EdgeInsets.all(8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isMuted ? context.colors.textPrimary : context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
        ),
        child: isMuted
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CarbonIcons.notification_off,
                    size: 16,
                    color: context.colors.background,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Muted',
                    style: TextStyle(
                      color: context.colors.background,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Icon(
                CarbonIcons.notification,
                size: 20,
                color: context.colors.textPrimary,
              ),
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context) {
    final isFollowing = _isFollowing!;
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFollowing ? context.colors.overlayLight : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFollowing ? CarbonIcons.user_admin : CarbonIcons.user_follow,
              size: 16,
              color: isFollowing ? context.colors.textPrimary : context.colors.background,
            ),
            const SizedBox(width: 8),
            Text(
              isFollowing ? 'Following' : 'Follow',
              style: TextStyle(
                color: isFollowing ? context.colors.textPrimary : context.colors.background,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowerInfo(BuildContext context) {
    if (_isLoadingCounts) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Row(
      children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_followerCount',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              Text(
                ' followers',
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          Text(
            ' • ',
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowingPage(
                    user: _userNotifier.value,
                  ),
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_followingCount',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                Text(
                  ' following',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_doesUserFollowMe == true && _currentUserNpub != null && _currentUserNpub != _userNotifier.value.pubkeyHex) ...[
            Text(
              ' • ',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
            Text(
              'Following you',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
          ],
      ],
    );
  }

  String _getNpubBech32(String identifier) {
    if (identifier.isEmpty) return '';

    if (identifier.startsWith('npub1')) {
      return identifier;
    }

    if (identifier.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(identifier)) {
      try {
        return encodeBasicBech32(identifier, "npub");
      } catch (e) {
        debugPrint('[ProfileInfoWidget] Error converting hex to npub: $e');
        return identifier;
      }
    }

    return identifier;
  }
}
