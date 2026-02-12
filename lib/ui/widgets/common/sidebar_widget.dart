import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/auth_service.dart';
import '../../../presentation/blocs/sidebar/sidebar_bloc.dart';
import '../../../presentation/blocs/sidebar/sidebar_event.dart';
import '../../../presentation/blocs/sidebar/sidebar_state.dart';
import '../../../l10n/app_localizations.dart';

class SidebarWidget extends StatefulWidget {
  const SidebarWidget({super.key});

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  late final SidebarBloc _sidebarBloc;
  bool _isSwitching = false;

  @override
  void initState() {
    super.initState();
    _sidebarBloc = AppDI.get<SidebarBloc>();
    _sidebarBloc.add(const SidebarInitialized());
  }

  Future<void> _handleAccountSwitch(BuildContext context, String npub) async {
    if (_isSwitching) return;
    setState(() => _isSwitching = true);

    Navigator.of(context).pop();

    try {
      final result = await AuthService.instance.switchAccount(npub);
      if (result.isError) {
        if (mounted) setState(() => _isSwitching = false);
        return;
      }

      await AppDI.resetAndReinitialize();

      final newNpub = AuthService.instance.currentUserNpub ?? npub;

      if (context.mounted) {
        GoRouter.of(context).go(
          '/home/feed?npub=${Uri.encodeComponent(newNpub)}',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SidebarBloc>.value(
      value: _sidebarBloc,
      child: BlocBuilder<SidebarBloc, SidebarState>(
        builder: (context, state) {
          final colors = context.colors;

          return Drawer(
            backgroundColor: colors.background,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: state is SidebarLoaded
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 68, 20, 0),
                        child: _UserProfileHeader(
                          user: state.currentUser,
                          colors: colors,
                          followerCount: state.followerCount,
                          followingCount: state.followingCount,
                          isLoadingCounts: state.isLoadingCounts,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _AccountSwitcher(
                          currentNpub:
                              state.currentUser['npub'] as String? ?? '',
                          accounts: state.storedAccounts,
                          accountProfileImages: state.accountProfileImages,
                          colors: colors,
                          isSwitching: _isSwitching,
                          onSwitchAccount: (npub) =>
                              _handleAccountSwitch(context, npub),
                          onAddAccount: () {
                            Navigator.of(context).pop();
                            context.push('/login?addAccount=true');
                          },
                        ),
                      ),
                      _SidebarContent(user: state.currentUser, colors: colors),
                    ],
                  )
                : Center(
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
                  ),
          );
        },
      ),
    );
  }
}

class _UserProfileHeader extends StatelessWidget {
  final Map<String, dynamic> user;
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
                  image: () {
                    final profileImage = user['profileImage'] as String? ?? '';
                    return profileImage.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(profileImage),
                            fit: BoxFit.cover,
                          )
                        : null;
                  }(),
                ),
                child: () {
                  final profileImage = user['profileImage'] as String? ?? '';
                  return profileImage.isEmpty
                      ? Icon(
                          Icons.person,
                          size: 28,
                          color: colors.textSecondary,
                        )
                      : null;
                }(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            () {
                              final l10n = AppLocalizations.of(context)!;
                              final name = user['name'] as String? ?? '';
                              return name.isNotEmpty ? name : l10n.anonymous;
                            }(),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              height: 1.4,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (() {
                          final nip05 = user['nip05'] as String? ?? '';
                          final nip05Verified =
                              user['nip05Verified'] as bool? ?? false;
                          return nip05.isNotEmpty && nip05Verified;
                        }()) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified,
                            size: 20,
                            color: colors.accent,
                          ),
                        ],
                      ],
                    ),
                    _buildNpubInfo(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildFollowerInfo(context),
        ],
      ),
    );
  }

  Widget _buildNpubInfo() {
    final npub = user['npub'] as String? ?? '';
    if (npub.isEmpty) return const SizedBox.shrink();

    final displayNpub = npub.length > 16
        ? '${npub.substring(0, 10)}...${npub.substring(npub.length - 6)}'
        : npub;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        displayNpub,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: colors.textSecondary,
          letterSpacing: 0.3,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildFollowerInfo(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (isLoadingCounts) {
      return const Padding(
        padding: EdgeInsets.only(top: 0),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Row(
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
          ' ${l10n.followers}',
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
          ' ${l10n.followingCount}',
          style: TextStyle(
            fontSize: 14,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final Map<String, dynamic> user;
  final AppThemeColors colors;

  const _SidebarContent({required this.user, required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildModernSidebarItem(
              context: context,
              colors: colors,
              svgAsset: 'assets/profile_button.svg',
              label: l10n.profile,
              onTap: () {
                final userNpub = user['npub'] as String? ?? '';
                final userPubkeyHex = user['pubkeyHex'] as String? ?? '';
                final currentLocation =
                    GoRouterState.of(context).matchedLocation;
                if (currentLocation.startsWith('/home/feed')) {
                  context.push(
                      '/home/feed/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
                } else if (currentLocation.startsWith('/home/notifications')) {
                  context.push(
                      '/home/notifications/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
                } else {
                  context.push(
                      '/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
                }
              },
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 106),
            child: _buildModernSidebarItem(
              context: context,
              colors: colors,
              icon: CarbonIcons.settings,
              label: l10n.settings,
              onTap: () => context.push('/settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSwitcher extends StatefulWidget {
  final String currentNpub;
  final List<StoredAccount> accounts;
  final Map<String, String> accountProfileImages;
  final AppThemeColors colors;
  final bool isSwitching;
  final ValueChanged<String> onSwitchAccount;
  final VoidCallback onAddAccount;

  const _AccountSwitcher({
    required this.currentNpub,
    required this.accounts,
    required this.accountProfileImages,
    required this.colors,
    required this.isSwitching,
    required this.onSwitchAccount,
    required this.onAddAccount,
  });

  @override
  State<_AccountSwitcher> createState() => _AccountSwitcherState();
}

class _AccountSwitcherState extends State<_AccountSwitcher> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = widget.colors;
    final otherAccounts =
        widget.accounts.where((a) => a.npub != widget.currentNpub).toList();

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colors.overlayLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                if (widget.isSwitching)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textSecondary,
                    ),
                  )
                else
                  Icon(
                    CarbonIcons.user_multiple,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.switchAccount,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              decoration: BoxDecoration(
                color: colors.overlayLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  ...otherAccounts.map((account) {
                    final profileImage =
                        widget.accountProfileImages[account.npub];
                    final displayNpub = account.npub.length > 16
                        ? '${account.npub.substring(0, 10)}...${account.npub.substring(account.npub.length - 6)}'
                        : account.npub;
                    return GestureDetector(
                      onTap: () => widget.onSwitchAccount(account.npub),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.avatarPlaceholder,
                                image: profileImage != null &&
                                        profileImage.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(profileImage),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child:
                                  profileImage == null || profileImage.isEmpty
                                      ? Center(
                                          child: Icon(
                                            Icons.person,
                                            size: 16,
                                            color: colors.textSecondary,
                                          ),
                                        )
                                      : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                displayNpub,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  GestureDetector(
                    onTap: widget.onAddAccount,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            CarbonIcons.add,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.addAccount,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          crossFadeState:
              _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colors.overlayLight,
        borderRadius: BorderRadius.circular(24),
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
