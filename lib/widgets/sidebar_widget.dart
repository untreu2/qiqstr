import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../screens/profile_page.dart';
import '../screens/relay_page.dart';
import '../utils/logout.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/theme_manager.dart';
import '../screens/keys_page.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 16, 16),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
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
                    size: 30,
                    color: colors.textSecondary,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    user.name.isNotEmpty ? user.name : 'Anonymous',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (user.nip05.isNotEmpty && user.nip05Verified) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.verified,
                    size: 18,
                    color: colors.accent,
                  ),
                ],
              ],
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Divider(color: colors.border, indent: 16, endIndent: 16),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildSidebarItem(
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
                  _buildSidebarItem(
                    colors: colors,
                    svgAsset: 'assets/relay_1.svg',
                    label: 'Relays',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RelayPage(),
                      ),
                    ),
                  ),
                  _buildSidebarItem(
                    colors: colors,
                    icon: CarbonIcons.password,
                    label: 'Keys',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const KeysPage(),
                      ),
                    ),
                  ),
                  _buildThemeToggle(colors),
                  Divider(color: colors.border, indent: 16, endIndent: 16),
                  _buildSidebarItem(
                    colors: colors,
                    svgAsset: 'assets/signout_button.svg',
                    label: 'Logout',
                    iconColor: colors.error,
                    textColor: colors.error,
                    onTap: () => Logout.performLogout(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildSidebarItem({
  required AppThemeColors colors,
  String? svgAsset,
  IconData? icon,
  required String label,
  required VoidCallback onTap,
  Color? iconColor,
  Color? textColor,
}) {
  return ListTile(
    leading: icon != null
        ? Icon(
            icon,
            size: 22,
            color: iconColor ?? colors.iconPrimary,
          )
        : SvgPicture.asset(
            svgAsset!,
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(
              iconColor ?? colors.iconPrimary,
              BlendMode.srcIn,
            ),
          ),
    title: Text(
      label,
      style: TextStyle(color: textColor ?? colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w500),
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    hoverColor: colors.hoverTransparent,
    onTap: onTap,
  );
}

Widget _buildThemeToggle(AppThemeColors colors) {
  return Consumer<ThemeManager>(
    builder: (context, themeManager, child) {
      return ListTile(
        leading: Icon(
          themeManager.isDarkMode ? CarbonIcons.asleep : CarbonIcons.light,
          color: colors.iconPrimary,
          size: 22,
        ),
        title: Text(
          themeManager.isDarkMode ? 'Dark Mode' : 'Light Mode',
          style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w500),
        ),
        trailing: Switch(
          value: themeManager.isDarkMode,
          onChanged: (value) => themeManager.toggleTheme(),
          activeThumbColor: colors.accent,
          inactiveThumbColor: colors.textSecondary,
          inactiveTrackColor: colors.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        hoverColor: colors.hoverTransparent,
        onTap: () => themeManager.toggleTheme(),
      );
    },
  );
}
