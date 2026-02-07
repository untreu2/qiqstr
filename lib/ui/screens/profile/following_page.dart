import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/auth_service.dart';
import '../../../presentation/blocs/following/following_bloc.dart';
import '../../../presentation/blocs/following/following_event.dart';
import '../../../presentation/blocs/following/following_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';

class FollowingPage extends StatefulWidget {
  final String pubkeyHex;

  const FollowingPage({
    super.key,
    required this.pubkeyHex,
  });

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showFollowingBubble = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showFollowingBubble.value != shouldShow) {
        _showFollowingBubble.value = shouldShow;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showFollowingBubble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FollowingBloc>(
      create: (context) {
        final bloc = AppDI.get<FollowingBloc>();
        final authService = AppDI.get<AuthService>();
        final npub =
            authService.hexToNpub(widget.pubkeyHex) ?? widget.pubkeyHex;
        bloc.add(FollowingLoadRequested(userNpub: npub));
        return bloc;
      },
      child: BlocBuilder<FollowingBloc, FollowingState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                          height: MediaQuery.of(context).padding.top + 60),
                    ),
                    _buildHeader(context),
                    if (state is FollowingLoading)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (state is FollowingError)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Error: ${state.message}',
                                style: TextStyle(
                                    color: context.colors.textSecondary),
                              ),
                              const SizedBox(height: 16),
                              PrimaryButton(
                                label: 'Retry',
                                onPressed: () {
                                  final authService = AppDI.get<AuthService>();
                                  final npub =
                                      authService.hexToNpub(widget.pubkeyHex) ??
                                          widget.pubkeyHex;
                                  context.read<FollowingBloc>().add(
                                      FollowingLoadRequested(userNpub: npub));
                                },
                                backgroundColor: context.colors.accent,
                                foregroundColor: context.colors.background,
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (state is FollowingLoaded)
                      state.followingUsers.isEmpty
                          ? SliverFillRemaining(
                              child: Center(
                                child: Text(
                                  'No following users',
                                  style: TextStyle(
                                      color: context.colors.textSecondary),
                                ),
                              ),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final user = state.followingUsers[index];
                                  final userNpub =
                                      user['npub'] as String? ?? '';
                                  final loadedUser =
                                      state.loadedUsers[userNpub] ?? user;
                                  return _buildUserTile(
                                      context, state, loadedUser, index);
                                },
                                childCount: state.followingUsers.length,
                              ),
                            )
                    else
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  centerBubble: Text(
                    'Following',
                    style: TextStyle(
                      color: context.colors.background,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  centerBubbleVisibility: _showFollowingBubble,
                  onCenterBubbleTap: () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  showShareButton: false,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const SliverToBoxAdapter(
      child: TitleWidget(
        title: 'Following',
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  static Widget _buildUserTile(
      BuildContext context, FollowingLoaded state, dynamic user, int index) {
    final loadedUser = state.loadedUsers[user.npub] ?? user;

    final displayName = loadedUser.name.isNotEmpty
        ? (loadedUser.name.length > 25
            ? '${loadedUser.name.substring(0, 25)}...'
            : loadedUser.name)
        : (user.npub.startsWith('npub1')
            ? '${user.npub.substring(0, 16)}...'
            : 'Unknown User');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            final currentLocation = GoRouterState.of(context).matchedLocation;
            if (currentLocation.startsWith('/home/feed')) {
              context.push(
                  '/home/feed/profile?npub=${Uri.encodeComponent(loadedUser.npub)}&pubkeyHex=${Uri.encodeComponent(loadedUser.pubkeyHex)}');
            } else if (currentLocation.startsWith('/home/notifications')) {
              context.push(
                  '/home/notifications/profile?npub=${Uri.encodeComponent(loadedUser.npub)}&pubkeyHex=${Uri.encodeComponent(loadedUser.pubkeyHex)}');
            } else {
              context.push(
                  '/profile?npub=${Uri.encodeComponent(loadedUser.npub)}&pubkeyHex=${Uri.encodeComponent(loadedUser.pubkeyHex)}');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildAvatar(context, loadedUser.profileImage),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (loadedUser.nip05.isNotEmpty &&
                                loadedUser.nip05Verified) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                size: 16,
                                color: context.colors.accent,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (index < state.followingUsers.length - 1) const _UserSeparator(),
      ],
    );
  }

  static Widget _buildAvatar(BuildContext context, String imageUrl) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey.shade800,
        child: Icon(
          Icons.person,
          size: 26,
          color: context.colors.textSecondary,
        ),
      );
    }

    return ClipOval(
      child: Container(
        width: 48,
        height: 48,
        color: Colors.transparent,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          memCacheWidth: 192,
          placeholder: (context, url) => Container(
            color: Colors.grey.shade800,
            child: Icon(
              Icons.person,
              size: 26,
              color: context.colors.textSecondary,
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade800,
            child: Icon(
              Icons.person,
              size: 26,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserSeparator extends StatelessWidget {
  const _UserSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: Center(
        child: Container(
          height: 0.5,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
