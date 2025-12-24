import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../models/user_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/theme_manager.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';

class SidebarWidget extends StatefulWidget {
  const SidebarWidget({super.key});

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  late UserRepository _userRepository;
  UserModel? _currentUser;
  StreamSubscription<UserModel>? _userStreamSubscription;
  int _followingCount = 0;
  int _followerCount = 0;
  bool _isLoadingCounts = true;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _loadInitialUser();
    _setupUserStreamListener();
  }

  @override
  void dispose() {
    _userStreamSubscription?.cancel();
    super.dispose();
  }

  void _setupUserStreamListener() {
    _userStreamSubscription = _userRepository.currentUserStream.listen(
      (updatedUser) {
        debugPrint('[SidebarWidget] Received updated user data from stream: ${updatedUser.name}');
        if (mounted) {
          setState(() {
            _currentUser = updatedUser;
          });
          _loadFollowerCounts();
        }
      },
      onError: (error) {
        debugPrint('[SidebarWidget] Error in user stream: $error');
      },
    );
  }

  Future<void> _loadInitialUser() async {
    try {
      final authRepository = AppDI.get<AuthRepository>();

      final npubResult = await authRepository.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        return;
      }

      final userResult = await _userRepository.getUserProfile(npubResult.data!);
      userResult.fold(
        (user) {
          if (mounted) {
            setState(() {
              _currentUser = user;
            });
            _loadFollowerCounts();
          }
        },
        (error) {
          debugPrint('[SidebarWidget] Error loading initial user: $error');
        },
      );
    } catch (e) {
      debugPrint('[SidebarWidget] Error getting current user: $e');
    }
  }

  Future<void> _loadFollowerCounts() async {
    if (_currentUser == null) return;

    try {
      final followingResult = await _userRepository.getFollowingListForUser(_currentUser!.pubkeyHex);

      followingResult.fold(
        (followingUsers) {
          if (mounted) {
            setState(() {
              _followingCount = followingUsers.length;
            });
          }
        },
        (error) {
          debugPrint('[SidebarWidget] Error loading following count: $error');
          if (mounted) {
            setState(() {
              _followingCount = 0;
            });
          }
        },
      );

      final nostrDataService = AppDI.get<DataService>();
      final followerCount = await nostrDataService.fetchFollowerCount(_currentUser!.pubkeyHex);
      if (mounted) {
        setState(() {
          _followerCount = followerCount;
          _isLoadingCounts = false;
        });
        
        // Update follower count in Isar if it's not 0
        if (followerCount > 0) {
          await _userRepository.updateUserFollowerCount(_currentUser!.pubkeyHex, followerCount);
        }
      }
    } catch (e) {
      debugPrint('[SidebarWidget] Error loading follower counts: $e');
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
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        final colors = themeManager.colors;

        return Drawer(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Container(
            color: colors.background,
            child: _currentUser == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: colors.accent),
                        const SizedBox(height: 16),
                        Text(
                          'Loading profile...',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 68, 20, 0),
                        child: _UserProfileHeader(
                          user: _currentUser!,
                          colors: colors,
                          followerCount: _followerCount,
                          followingCount: _followingCount,
                          isLoadingCounts: _isLoadingCounts,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SidebarContent(user: _currentUser!, colors: colors),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _UserProfileHeader extends StatelessWidget {
  final UserModel user;
  final AppThemeColors colors;
  final int followerCount;
  final int followingCount;
  final bool isLoadingCounts;

  const _UserProfileHeader({
    required this.user,
    required this.colors,
    required this.followerCount,
    required this.followingCount,
    required this.isLoadingCounts,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.avatarPlaceholder,
                  image: user.profileImage.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(user.profileImage),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: user.profileImage.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 28,
                        color: colors.textSecondary,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name.isNotEmpty ? user.name : 'Anonymous',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user.nip05.isNotEmpty && user.nip05Verified) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.verified,
                        size: 20,
                        color: colors.accent,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFollowerInfo(context),
        ],
      ),
    );
  }

  Widget _buildFollowerInfo(BuildContext context) {
    if (isLoadingCounts) {
      return const Padding(
        padding: EdgeInsets.only(top: 4.0),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        children: [
          Text(
            '$followerCount',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          Text(
            ' followers',
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
          Text(
            ' • ',
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
          Text(
            '$followingCount',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          Text(
            ' following',
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final UserModel user;
  final AppThemeColors colors;

  const _SidebarContent({required this.user, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Expanded(
            child: Column(
              children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildModernSidebarItem(
                        context: context,
                        colors: colors,
                        svgAsset: 'assets/profile_button.svg',
                        label: 'Profile',
                        onTap: () {
                          final currentLocation = GoRouterState.of(context).matchedLocation;
                          if (currentLocation.startsWith('/home/feed')) {
                            context.push('/home/feed/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
                          } else if (currentLocation.startsWith('/home/notifications')) {
                            context.push('/home/notifications/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
                          } else if (currentLocation.startsWith('/home/dm')) {
                            context.push('/home/dm/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
                          } else {
                            context.push('/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
                          }
                        },
                      ),
                    ]),
                  ),
                ),
                    ],
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildModernSidebarItem(
                          context: context,
                          colors: colors,
                          icon: CarbonIcons.settings,
                          label: 'Settings',
                          onTap: () => context.push('/settings'),
                  ),
                ),
                const SizedBox(height: 150),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildModernSidebarItem({
  required BuildContext context,
  required AppThemeColors colors,
  String? svgAsset,
  IconData? icon,
  required String label,
  required VoidCallback onTap,
  Color? iconColor,
  Color? textColor,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: colors.overlayLight,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        children: [
          if (icon != null)
            Icon(
              icon,
              size: 22,
              color: iconColor ?? colors.textPrimary,
            )
          else if (svgAsset != null)
            SvgPicture.asset(
              svgAsset,
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                iconColor ?? colors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor ?? colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
