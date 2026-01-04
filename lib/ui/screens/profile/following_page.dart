import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/theme_manager.dart';
import '../../../models/user_model.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/following_page_viewmodel.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';

class FollowingPage extends StatelessWidget {
  final UserModel user;

  const FollowingPage({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FollowingPageViewModel>(
      create: (_) => FollowingPageViewModel(
        userRepository: AppDI.get(),
        userNpub: user.npub,
      ),
      child: Consumer<FollowingPageViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: CustomScrollView(
              slivers: [
                _buildHeader(context),
                if (viewModel.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (viewModel.error != null)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Error: ${viewModel.error}',
                            style: TextStyle(color: context.colors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(
                            label: 'Retry',
                            onPressed: () => viewModel.refresh(),
                            backgroundColor: context.colors.accent,
                            foregroundColor: context.colors.background,
                          ),
                        ],
                      ),
                    ),
                  )
                else if (viewModel.followingUsers.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'No following users',
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final user = viewModel.followingUsers[index];
                        final loadedUser = viewModel.loadedUsers[user.npub] ?? user;
                        return _buildUserTile(context, viewModel, loadedUser, index);
                      },
                      childCount: viewModel.followingUsers.length,
                    ),
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
        useTopPadding: true,
      ),
    );
  }

  static Widget _buildUserTile(BuildContext context, FollowingPageViewModel viewModel, UserModel user, int index) {
    final loadedUser = viewModel.loadedUsers[user.npub] ?? user;

    final displayName = loadedUser.name.isNotEmpty
        ? (loadedUser.name.length > 25 ? '${loadedUser.name.substring(0, 25)}...' : loadedUser.name)
        : (user.npub.startsWith('npub1') ? '${user.npub.substring(0, 16)}...' : 'Unknown User');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            final currentLocation = GoRouterState.of(context).matchedLocation;
            if (currentLocation.startsWith('/home/feed')) {
              context.push('/home/feed/profile?npub=${Uri.encodeComponent(loadedUser.npub)}&pubkeyHex=${Uri.encodeComponent(loadedUser.pubkeyHex)}');
            } else if (currentLocation.startsWith('/home/notifications')) {
              context.push('/home/notifications/profile?npub=${Uri.encodeComponent(loadedUser.npub)}&pubkeyHex=${Uri.encodeComponent(loadedUser.pubkeyHex)}');
            } else if (currentLocation.startsWith('/home/dm')) {
              context.push('/home/dm/profile?npub=${Uri.encodeComponent(loadedUser.npub)}&pubkeyHex=${Uri.encodeComponent(loadedUser.pubkeyHex)}');
            } else {
              context.push('/profile?npub=${Uri.encodeComponent(loadedUser.npub)}&pubkeyHex=${Uri.encodeComponent(loadedUser.pubkeyHex)}');
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
                            if (loadedUser.nip05.isNotEmpty && loadedUser.nip05Verified) ...[
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
        if (index < viewModel.followingUsers.length - 1)
          const _UserSeparator(),
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
