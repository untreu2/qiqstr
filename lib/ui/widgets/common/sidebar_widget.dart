import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/sidebar/sidebar_bloc.dart';
import '../../../presentation/blocs/sidebar/sidebar_event.dart';
import '../../../presentation/blocs/sidebar/sidebar_state.dart';

class SidebarWidget extends StatefulWidget {
  const SidebarWidget({super.key});

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  late final SidebarBloc _sidebarBloc;

  @override
  void initState() {
    super.initState();
    _sidebarBloc = AppDI.get<SidebarBloc>();
    _sidebarBloc.add(const SidebarInitialized());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SidebarBloc>.value(
      value: _sidebarBloc,
      child: BlocBuilder<SidebarBloc, SidebarState>(
        builder: (context, state) {
          final colors = context.colors;

          return Container(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: const BorderRadius.only(
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
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        () {
                          final name = user['name'] as String? ?? '';
                          return name.isNotEmpty ? name : 'Anonymous';
                        }(),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
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
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFollowerInfo(context),
        ],
      ),
    );
  }

  Widget _buildFollowerInfo(BuildContext context) {
    if (isLoadingCounts) {
      return const Padding(
        padding: EdgeInsets.only(top: 4.0),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
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
            ' followers',
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
            ' following',
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final Map<String, dynamic> user;
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
            child: Column(
              children: [
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
                              onTap: () {
                                final userNpub = user['npub'] as String? ?? '';
                                final userPubkeyHex =
                                    user['pubkeyHex'] as String? ?? '';
                                final currentLocation =
                                    GoRouterState.of(context).matchedLocation;
                                if (currentLocation.startsWith('/home/feed')) {
                                  context.push(
                                      '/home/feed/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
                                } else if (currentLocation
                                    .startsWith('/home/notifications')) {
                                  context.push(
                                      '/home/notifications/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
                                } else {
                                  context.push(
                                      '/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
                                }
                              },
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildModernSidebarItem(
                    context: context,
                    colors: colors,
                    icon: CarbonIcons.settings,
                    label: 'Settings',
                    onTap: () => context.push('/settings'),
                  ),
                ),
                const SizedBox(height: 150),
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
