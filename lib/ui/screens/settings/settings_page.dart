import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../../utils/logout.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/dialogs/logout_dialog.dart';

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
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildSettingsSection(context, themeManager),
                    const SizedBox(height: 150),
                  ],
                ),
              ),
              const BackButtonWidget.floating(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      child: const TitleWidget(
        title: 'Settings',
        fontSize: 32,
        subtitle: "Manage your app preferences.",
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
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
            icon: CarbonIcons.network_3,
            onTap: () => context.push('/relays'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: 'Your Data on Relays',
            subtitle: '',
            icon: CarbonIcons.data_connected,
            onTap: () => context.push('/event-manager'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: 'Keys',
            subtitle: '',
            icon: CarbonIcons.password,
            onTap: () => context.push('/keys'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: 'Display',
            subtitle: '',
            icon: CarbonIcons.view,
            onTap: () => context.push('/display'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: 'Payments',
            subtitle: '',
            icon: CarbonIcons.flash,
            onTap: () => context.push('/payments'),
          ),
          const SizedBox(height: 8),
          _buildLogoutItem(context),
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

  Widget _buildLogoutItem(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showLogoutDialog(
          context: context,
          onConfirm: () => Logout.performLogout(context),
        );
      },
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
