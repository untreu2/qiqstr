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
    final storage = FlutterSecureStorage();
    final storedNpub = await storage.read(key: 'npub');
    if (mounted) {
      setState(() => npub = storedNpub);

      // If we have npub but no user, create a fallback user
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
                      const SizedBox(height: 70),
                      // Enhanced user profile section
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar and name row
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 32,
                                  backgroundColor: colors.avatarPlaceholder,
                                  backgroundImage:
                                      currentUser.profileImage.isNotEmpty ? CachedNetworkImageProvider(currentUser.profileImage) : null,
                                  child: currentUser.profileImage.isEmpty ? Icon(Icons.person, color: colors.iconPrimary, size: 32) : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentUser.name.isNotEmpty ? currentUser.name : 'Anonymous',
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          height: 1.1,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (currentUser.nip05.isNotEmpty && currentUser.nip05.contains('@'))
                                        Text(
                                          '@${currentUser.nip05.split('@').last}',
                                          style: TextStyle(
                                            color: colors.accent,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // About section
                            if (currentUser.about.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                currentUser.about,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],

                            // Lightning address
                            if (currentUser.lud16.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                currentUser.lud16,
                                style: TextStyle(
                                  color: colors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            _buildSidebarItem(
                              colors: colors,
                              svgAsset: 'assets/profile_button.svg',
                              label: 'Profile',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProfilePage(user: currentUser),
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
      },
    );
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
              size: 20,
              color: iconColor ?? colors.iconPrimary,
            )
          : SvgPicture.asset(
              svgAsset!,
              width: 20,
              height: 20,
              color: iconColor ?? colors.iconPrimary,
            ),
      title: Text(
        label,
        style: TextStyle(color: textColor ?? colors.textPrimary, fontSize: 18),
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
            size: 20,
          ),
          title: Text(
            themeManager.isDarkMode ? 'Dark Mode' : 'Light Mode',
            style: TextStyle(color: colors.textPrimary, fontSize: 18),
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
        );
      },
    );
  }
}
