import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import '../../../utils/logout.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/dialogs/logout_dialog.dart';
import '../../widgets/dialogs/language_dialog.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../../presentation/blocs/theme/theme_state.dart';
import '../../../presentation/blocs/locale/locale_bloc.dart';
import '../../../presentation/blocs/locale/locale_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/common/top_action_bar_widget.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showTitleBubble.value != shouldShow) {
        _showTitleBubble.value = shouldShow;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showTitleBubble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<LocaleBloc, LocaleState>(
          builder: (context, localeState) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: Stack(
                children: [
                  CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(
                            height:
                                MediaQuery.of(context).padding.top + 60),
                      ),
                      SliverToBoxAdapter(
                        child: _buildHeader(context, l10n),
                      ),
                      SliverToBoxAdapter(
                        child: const SizedBox(height: 16),
                      ),
                      SliverToBoxAdapter(
                        child: _buildSettingsSection(context, l10n),
                      ),
                      SliverToBoxAdapter(
                        child: const SizedBox(height: 150),
                      ),
                    ],
                  ),
                  TopActionBarWidget(
                    onBackPressed: () => context.pop(),
                    showShareButton: false,
                    centerBubble: Text(
                      l10n.settings,
                      style: TextStyle(
                        color: context.colors.background,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    centerBubbleVisibility: _showTitleBubble,
                    onCenterBubbleTap: () {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    },
                  ),
                  _buildLanguageButton(context, l10n, localeState),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return TitleWidget(
      title: l10n.settings,
      fontSize: 32,
      subtitle: l10n.settingsSubtitle,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    );
  }

  Widget _buildLanguageButton(BuildContext context, AppLocalizations l10n, LocaleState localeState) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 14,
      right: 16,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.colors.textPrimary,
          borderRadius: BorderRadius.circular(22.0),
        ),
        child: GestureDetector(
          onTap: () => showLanguageDialog(
            context: context,
            currentLocale: localeState.locale,
          ),
          behavior: HitTestBehavior.opaque,
          child: Icon(
            CarbonIcons.language,
            color: context.colors.background,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildSettingsItem(
            context: context,
            title: l10n.relays,
            subtitle: '',
            icon: CarbonIcons.network_3,
            onTap: () => context.push('/relays'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: l10n.yourDataOnRelays,
            subtitle: '',
            icon: CarbonIcons.data_connected,
            onTap: () => context.push('/event-manager'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: l10n.databaseCache,
            subtitle: '',
            icon: CarbonIcons.data_base,
            onTap: () => context.push('/database'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: l10n.keys,
            subtitle: '',
            icon: CarbonIcons.password,
            onTap: () => context.push('/keys'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: l10n.display,
            subtitle: '',
            icon: CarbonIcons.view,
            onTap: () => context.push('/display'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: l10n.payments,
            subtitle: '',
            icon: CarbonIcons.flash,
            onTap: () => context.push('/payments'),
          ),
          const SizedBox(height: 8),
          _buildSettingsItem(
            context: context,
            title: l10n.muted,
            subtitle: '',
            icon: CarbonIcons.notification_off,
            onTap: () => context.push('/muted'),
          ),
          const SizedBox(height: 8),
          _buildLogoutItem(context, l10n),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(24),
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

  Widget _buildLogoutItem(BuildContext context, AppLocalizations l10n) {
    return GestureDetector(
      onTap: () {
        showLogoutDialog(
          context: context,
          onConfirm: () => Logout.performLogout(context),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
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
              l10n.logout,
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
