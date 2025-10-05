import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../screens/profile_page.dart';
import '../screens/settings_page.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/theme_manager.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../core/di/app_di.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/user_repository.dart';

class SidebarWidget extends StatefulWidget {
  const SidebarWidget({super.key});

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  late UserRepository _userRepository;
  UserModel? _currentUser;
  StreamSubscription<UserModel>? _userStreamSubscription;

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

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        final colors = themeManager.colors;

        return Drawer(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
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
                      _UserProfileHeader(user: _currentUser!, colors: colors),
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

  const _UserProfileHeader({required this.user, required this.colors});

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
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
                        size: 32,
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
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(user: user),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const Spacer(),
                        const SizedBox(height: 10),
                        _buildModernSidebarItem(
                          context: context,
                          colors: colors,
                          icon: CarbonIcons.settings,
                          label: 'Settings',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 150),
                      ],
                    ),
                  ),
                ),
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
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          if (icon != null)
            Icon(
              icon,
              size: 24,
              color: iconColor ?? colors.textPrimary,
            )
          else if (svgAsset != null)
            SvgPicture.asset(
              svgAsset,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                iconColor ?? colors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              color: textColor ?? colors.textPrimary,
              fontSize: 18,
                  fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
