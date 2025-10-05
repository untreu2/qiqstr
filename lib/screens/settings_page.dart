import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_manager.dart';
import '../widgets/back_button_widget.dart';
import '../screens/relay_page.dart';
import '../screens/keys_page.dart';
import '../screens/nwc_settings_page.dart';
import '../utils/logout.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 16),
                        _buildSettingsSection(context, themeManager),
                      ],
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      children: [
                        const Spacer(),
                        const SizedBox(height: 100),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildLogoutItem(context),
                        ),
                        const SizedBox(height: 150),
                      ],
                    ),
                  ),
                ],
              ),
              const BackButtonWidget.floating(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Manage your app preferences.",
            style: TextStyle(
              fontSize: 15,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, ThemeManager themeManager) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildSettingsItem(
            context: context,
            title: 'Relays',
            subtitle: '',
            svgAsset: 'assets/relay_1.svg',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RelayPage(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: 'Keys',
            subtitle: '',
            icon: CarbonIcons.password,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const KeysPage(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: 'Wallet',
            subtitle: '',
            icon: CarbonIcons.wallet,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NwcSettingsPage(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildThemeToggleItem(context, themeManager),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    required BuildContext context,
    required String title,
    required String subtitle,
    String? svgAsset,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 22,
                color: context.colors.textPrimary,
              )
            else if (svgAsset != null)
              SvgPicture.asset(
                svgAsset,
                width: 22,
                height: 22,
                colorFilter: ColorFilter.mode(
                  context.colors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeToggleItem(BuildContext context, ThemeManager themeManager) {
    return GestureDetector(
      onTap: () => themeManager.toggleTheme(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          children: [
            Icon(
              themeManager.isDarkMode ? CarbonIcons.asleep : CarbonIcons.light,
              size: 22,
              color: context.colors.textPrimary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                themeManager.isDarkMode ? 'Dark Mode' : 'Light Mode',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: themeManager.isDarkMode,
              onChanged: (value) => themeManager.toggleTheme(),
              activeThumbColor: context.colors.accent,
              inactiveThumbColor: context.colors.textSecondary,
              inactiveTrackColor: context.colors.border,
              activeTrackColor: context.colors.accent.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutItem(BuildContext context) {
    return GestureDetector(
      onTap: () => Logout.performLogout(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: context.colors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/signout_button.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                context.colors.error,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Logout',
              style: TextStyle(
                color: context.colors.error,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

