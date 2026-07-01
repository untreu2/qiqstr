import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/auth_service.dart';
import '../../../presentation/blocs/sidebar/sidebar_bloc.dart';
import '../../../presentation/blocs/sidebar/sidebar_event.dart';
import '../../../presentation/blocs/sidebar/sidebar_state.dart';
import '../../../l10n/app_localizations.dart';
import '../dialogs/switch_account_dialog.dart';

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
        GoRouter.of(
          context,
        ).go('/home/feed?npub=${Uri.encodeComponent(newNpub)}');
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
                      _SidebarContent(
                        user: state.currentUser,
                        colors: colors,
                        onSwitchAccountTap: () {
                          showSwitchAccountDialog(
                            context: context,
                            currentNpub:
                                state.currentUser['npub'] as String? ?? '',
                            accounts: state.storedAccounts,
                            accountProfileImages: state.accountProfileImages,
                            isSwitching: _isSwitching,
                            onSwitchAccount: (npub) =>
                                _handleAccountSwitch(context, npub),
                            onAddAccount: () {
                              Navigator.of(context).pop();
                              context.push('/welcome?addAccount=true');
                            },
                          );
                        },
                      ),
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
              _buildAvatar(),
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
                          PhosphorIcon(PhosphorIcons.sealCheck(), size: 20, color: colors.accent),
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

  Widget _buildAvatar() {
    const size = 56.0;
    final profileImage = user['picture'] as String? ?? '';

    final fallback = PhosphorIcon(
      PhosphorIcons.user(),
      size: 28,
      color: colors.textSecondary,
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.avatarPlaceholder,
      ),
      clipBehavior: Clip.antiAlias,
      child: profileImage.isEmpty
          ? Center(child: fallback)
          : CachedNetworkImage(
              imageUrl: profileImage,
              width: size,
              height: size,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              memCacheWidth: (size * 3).toInt(),
              maxHeightDiskCache: (size * 3).toInt(),
              maxWidthDiskCache: (size * 3).toInt(),
              placeholder: (context, url) => Center(child: fallback),
              errorWidget: (context, url, error) => Center(child: fallback),
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
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        Text(
          ' • ',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
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
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final Map<String, dynamic> user;
  final AppThemeColors colors;
  final VoidCallback onSwitchAccountTap;

  const _SidebarContent({
    required this.user,
    required this.colors,
    required this.onSwitchAccountTap,
  });

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
              icon: PhosphorIcons.user(),
              label: l10n.profile,
              onTap: () {
                final userNpub = user['npub'] as String? ?? '';
                final userPubkeyHex = user['pubkey'] as String? ?? '';
                final currentLocation = GoRouterState.of(
                  context,
                ).matchedLocation;
                if (currentLocation.startsWith('/home/feed')) {
                  context.push(
                    '/home/feed/profile?npub=${Uri.encodeComponent(userNpub)}&pubkey=${Uri.encodeComponent(userPubkeyHex)}',
                  );
                } else if (currentLocation.startsWith('/home/notifications')) {
                  context.push(
                    '/home/notifications/profile?npub=${Uri.encodeComponent(userNpub)}&pubkey=${Uri.encodeComponent(userPubkeyHex)}',
                  );
                } else {
                  context.push(
                    '/profile?npub=${Uri.encodeComponent(userNpub)}&pubkey=${Uri.encodeComponent(userPubkeyHex)}',
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildModernSidebarItem(
              context: context,
              colors: colors,
              icon: PhosphorIcons.file(),
              label: l10n.reads,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/home/feed/explore');
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildModernSidebarItem(
              context: context,
              colors: colors,
              icon: PhosphorIcons.listBullets(),
              label: l10n.listsTitle,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/follow-sets');
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildModernSidebarItem(
              context: context,
              colors: colors,
              icon: PhosphorIcons.bookmarkSimple(),
              label: l10n.bookmarks,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/bookmarks');
              },
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildModernSidebarItem(
              context: context,
              colors: colors,
              icon: PhosphorIcons.users(),
              label: l10n.switchAccount,
              onTap: onSwitchAccountTap,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 106),
            child: _buildModernSidebarItem(
              context: context,
              colors: colors,
              icon: PhosphorIcons.gear(),
              label: l10n.settings,
              onTap: () => context.push('/settings'),
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
  PhosphorIconData? icon,
  required String label,
  required VoidCallback onTap,
  Color? iconColor,
  Color? textColor,
  double? iconSize,
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
            PhosphorIcon(
              icon,
              size: iconSize ?? 22,
              color: iconColor ?? colors.textPrimary,
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
