import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/screens/relay_page.dart';
import 'package:qiqstr/utils/logout.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/theme_manager.dart';
import 'package:qiqstr/screens/keys_page.dart';
import 'package:carbon_icons/carbon_icons.dart';

class SidebarWidget extends StatefulWidget {
  final UserModel? user;

  const SidebarWidget({super.key, this.user});

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  String? npub;
  UserModel? _fallbackUser;

  @override
  void initState() {
    super.initState();
    _loadNpub();
  }

  Future<void> _loadNpub() async {
    const storage = FlutterSecureStorage();
    final storedNpub = await storage.read(key: 'npub');
    if (mounted) {
      setState(() => npub = storedNpub);

      if (storedNpub != null && widget.user == null) {
        _createFallbackUser(storedNpub);
      }
    }
  }

  void _createFallbackUser(String userNpub) {
    setState(() {
      _fallbackUser = UserModel(
        npub: userNpub,
        name: 'Loading...',
        about: '',
        nip05: '',
        banner: '',
        profileImage: '',
        lud16: '',
        website: '',
        updatedAt: DateTime.now(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        final colors = themeManager.colors;
        final currentUser = widget.user ?? _fallbackUser;

        return Drawer(
          child: Container(
            color: colors.background,
            child: currentUser == null || npub == null
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
                      _UserProfileHeader(user: currentUser, colors: colors),
                      _SidebarContent(user: currentUser, colors: colors),
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
          CircleAvatar(
            radius: 24,
            backgroundColor: colors.avatarPlaceholder,
            backgroundImage: user.profileImage.isNotEmpty
                ? CachedNetworkImageProvider(user.profileImage)
                : null,
            child: user.profileImage.isEmpty
                ? Icon(Icons.person, color: colors.iconPrimary, size: 24)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              user.name.isNotEmpty ? user.name : 'Anonymous',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
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
            if (user.about.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  user.about,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (user.nip05.isNotEmpty && user.nip05.contains('@')) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  user.nip05,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (user.lud16.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  user.lud16,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
            color: iconColor ?? colors.iconPrimary,
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
          activeColor: colors.accent,
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
