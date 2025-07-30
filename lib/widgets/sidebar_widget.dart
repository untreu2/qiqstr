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

class SidebarWidget extends StatefulWidget {
  final UserModel? user;

  const SidebarWidget({super.key, this.user});

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  String? npub;

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
            child: widget.user == null || npub == null
                ? Center(child: CircularProgressIndicator(color: colors.loading))
                : Column(
                    children: [
                      const SizedBox(height: 70),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundImage: widget.user!.profileImage.isNotEmpty
                                  ? CachedNetworkImageProvider(widget.user!.profileImage)
                                  : const AssetImage('assets/default_profile.png') as ImageProvider,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                widget.user!.name,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                                  builder: (context) => ProfilePage(user: widget.user!),
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
                            _buildThemeToggle(colors),
                            _buildSidebarItem(
                              colors: colors,
                              svgAsset: 'assets/Logout_button.svg',
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
    required String svgAsset,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: SvgPicture.asset(
        svgAsset,
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
            themeManager.isDarkMode ? Icons.dark_mode : Icons.light_mode,
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
