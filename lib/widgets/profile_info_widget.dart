import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_model.dart';
import '../theme/theme_manager.dart';
import '../screens/edit_profile.dart';
import '../screens/following_page.dart';
import '../widgets/photo_viewer_widget.dart';
import '../core/di/app_di.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/services/nostr_data_service.dart';

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
  String? _currentUserNpub;
  late AuthRepository _authRepository;
  late UserRepository _userRepository;

  bool _copiedToClipboard = false;
  bool _isInitialized = false;

  int _followingCount = 0;
  bool _isLoadingCounts = true;
  bool? _doesUserFollowMe;

  String? _userHexKey;

  // Add state management for user profile data like note_widget.dart
  final ValueNotifier<UserModel> _userNotifier = ValueNotifier(UserModel(
    pubkeyHex: '',
    name: '',
    about: '',
    profileImage: '',
    banner: '',
    website: '',
    nip05: '',
    lud16: '',
    updatedAt: DateTime.now(),
    nip05Verified: false,
  ));

  bool _isLoadingProfile = false;
  StreamSubscription<UserModel>? _userStreamSubscription;

  Widget _buildBioContent(UserModel user) {
    if (user.about.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Text(
        user.about,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 14,
        ),
      ),
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
    // Initialize with the provided user data immediately
    _userNotifier.value = widget.user;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initBasicData();
      }
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _loadUserProfileAsync(); // Load fresh profile data
      }
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _initFollowStatusAsync();
      }
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
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

      // Use UserRepository to load fresh user data (same as note_widget.dart)
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
          // Keep the original user data if fresh load fails
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Load user profile async error: $e');
    } finally {
      _isLoadingProfile = false;
    }
  }

  /// Setup listener for UserRepository stream to get real-time profile updates
  void _setupUserStreamListener() {
    _userStreamSubscription = _userRepository.currentUserStream.listen(
      (updatedUser) {
        // Only update if this is the same user being displayed
        if (updatedUser.pubkeyHex == widget.user.pubkeyHex || updatedUser.pubkeyHex == _userNotifier.value.pubkeyHex) {
          debugPrint('[ProfileInfoWidget] Received updated user data from stream: ${updatedUser.name}');
          if (mounted) {
            _userNotifier.value = updatedUser;
            // Refresh counts and other data that might have changed
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

      // Check if current user follows this profile user
      await _checkFollowStatus();

      // Check if this profile user follows the current user
      await _checkIfUserFollowsMe();
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Follow status init error: $e');
    }
  }

  Future<void> _checkFollowStatus() async {
    try {
      if (_currentUserNpub == null) return;

      // Use UserRepository.isFollowing method (cleaner MVVM approach)
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

  Future<void> _checkIfUserFollowsMe() async {
    try {
      if (_currentUserNpub == null) return;

      debugPrint('[ProfileInfoWidget] Checking if ${_userNotifier.value.pubkeyHex} follows $_currentUserNpub');

      // Get the profile user's following list to check if current user is in it
      final nostrDataService = AppDI.get<NostrDataService>();
      final followingResult = await nostrDataService.getFollowingList(_userNotifier.value.pubkeyHex);

      followingResult.fold(
        (followingHexList) {
          // Convert current user npub to hex for comparison
          final currentUserHex = _convertToHex(_currentUserNpub!);

          // Check if current user's hex is in the profile user's following list
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
    final operationName = originalFollowState == true ? 'UNFOLLOW' : 'FOLLOW';

    debugPrint('=== [ProfileInfoWidget] $operationName OPERATION START ===');
    debugPrint('[ProfileInfoWidget] Original follow state: $originalFollowState');
    debugPrint('[ProfileInfoWidget] Current user npub: $_currentUserNpub');
    debugPrint('[ProfileInfoWidget] Target user npub: ${_userNotifier.value.pubkeyHex}');
    debugPrint('[ProfileInfoWidget] Target user hex: $_userHexKey');

    // Optimistic UI update
    setState(() {
      _isFollowing = !_isFollowing!;
    });

    debugPrint('[ProfileInfoWidget] UI optimistically updated to: $_isFollowing');

    try {
      // Ensure we're using the correct format for follow operations
      final currentUser = _userNotifier.value;
      final targetNpub = currentUser.pubkeyHex.startsWith('npub1')
          ? currentUser.pubkeyHex
          : (_userHexKey != null && _userHexKey!.length == 64)
              ? _getNpubBech32(_userHexKey!)
              : currentUser.pubkeyHex;

      debugPrint('[ProfileInfoWidget] Using npub for operation: $targetNpub');

      final result =
          originalFollowState == true ? await _userRepository.unfollowUser(targetNpub) : await _userRepository.followUser(targetNpub);

      debugPrint('[ProfileInfoWidget] Repository operation completed');

      result.fold(
        (_) {
          debugPrint('[ProfileInfoWidget] Follow toggle successful');
          // Refresh follow status to ensure accuracy (increased delay for relay propagation)
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              _checkFollowStatus();
            }
          });
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Follow toggle error: $error');

          // Show error with correct operation name (based on ORIGINAL state)
          final operationName = originalFollowState == true ? 'unfollow' : 'follow';
          debugPrint('[ProfileInfoWidget] Operation that failed: $operationName');

          // Revert optimistic update
          setState(() {
            _isFollowing = originalFollowState;
          });

          // Show error to user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to $operationName user: $error'),
                backgroundColor: context.colors.error,
              ),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Follow toggle exception: $e');
      // Revert optimistic update
      setState(() {
        _isFollowing = originalFollowState;
      });
    }
  }

  Future<void> _loadFollowerCounts() async {
    try {
      // Get THIS profile user's following list (how many they follow)
      // Use NostrDataService directly for follow counts (read-only operation)
      final nostrDataService = AppDI.get<NostrDataService>();
      final followingResult = await nostrDataService.getFollowingList(_userNotifier.value.pubkeyHex);

      followingResult.fold(
        (followingHexList) {
          if (mounted) {
            setState(() {
              _followingCount = followingHexList.length;
              _isLoadingCounts = false;
            });
          }
        },
        (error) {
          debugPrint('[ProfileInfoWidget] Error loading following count: $error');
          if (mounted) {
            setState(() {
              _followingCount = 0;
              _isLoadingCounts = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('[ProfileInfoWidget] Error loading following count: $e');
      if (mounted) {
        setState(() {
          _followingCount = 0;
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
        final npubBech32 = _getNpubBech32(user.pubkeyHex);
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
                transform: Matrix4.translationValues(0, -30, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatarAndActionsRow(context, user),
                    _buildNameRow(context, user),
                    const SizedBox(height: 1),
                    _buildNpubCopyButton(context, npubBech32),
                    if (user.about.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildBioContent(user),
                      const SizedBox(height: 6),
                    ],
                    if (user.website.isNotEmpty && _isInitialized) ...[
                      const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
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

  // Static cache for avatar widgets (same as note_widget.dart)
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
                color: Colors.white,
                width: 4.0,
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
                const SizedBox(width: 6),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'This user is verified by $domain',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        backgroundColor: context.colors.surface,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildOptimizedBanner(BuildContext context, UserModel user, double screenWidth) {
    // Calculate 36:9 aspect ratio height
    final double bannerHeight = screenWidth * (5 / 10);

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
        if (_currentUserNpub != null)
          Padding(
            padding: const EdgeInsets.only(top: 35.0),
            child: isOwnProfile
                ? _buildEditProfileButton(context)
                : (_isFollowing != null)
                    ? _buildFollowButton(context)
                    : const SizedBox.shrink(),
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.borderAccent),
        ),
        child: Text(
          'Edit profile',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context) {
    final isFollowing = _isFollowing!;
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        width: 100,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFollowing ? context.colors.overlayLight : context.colors.buttonPrimary,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.borderAccent),
        ),
        child: Text(
          isFollowing ? 'Following' : 'Follow',
          style: TextStyle(
            color: isFollowing ? context.colors.textPrimary : context.colors.background,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildNpubCopyButton(BuildContext context, String npubBech32) {
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: npubBech32));
        setState(() => _copiedToClipboard = true);
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) setState(() => _copiedToClipboard = false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.borderAccent),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: Row(
            key: ValueKey(_copiedToClipboard),
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.copy, size: 14, color: context.colors.textTertiary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _copiedToClipboard ? 'Copied to clipboard' : npubBech32,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFollowerInfo(BuildContext context) {
    if (_isLoadingCounts) {
      return const Padding(
        padding: EdgeInsets.only(top: 12.0),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Row(
        children: [
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
                    fontWeight: FontWeight.bold,
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
      ),
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
