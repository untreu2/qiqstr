import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/user_model.dart';
import '../../theme/theme_manager.dart';
import '../media/photo_viewer_widget.dart';
import '../note/note_content_widget.dart';
import '../common/snackbar_widget.dart';
import '../dialogs/unfollow_user_dialog.dart';
import '../dialogs/mute_user_dialog.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/profile_info_viewmodel.dart';

class ProfileInfoWidget extends StatefulWidget {
  final UserModel user;
  final Function(String)? onNavigateToProfile;

  const ProfileInfoWidget({
    super.key,
    required this.user,
    this.onNavigateToProfile,
  });

  @override
  State<ProfileInfoWidget> createState() => _ProfileInfoWidgetState();
}

class _ProfileInfoWidgetState extends State<ProfileInfoWidget> {
  late final ProfileInfoViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ProfileInfoViewModel(
      authRepository: AppDI.get(),
      userRepository: AppDI.get(),
      dataService: AppDI.get(),
      userPubkeyHex: widget.user.pubkeyHex,
    );
    _viewModel.updateUser(widget.user);
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ProfileInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.pubkeyHex != widget.user.pubkeyHex) {
      _viewModel.updateUser(widget.user);
    } else if (oldWidget.user.name != widget.user.name ||
        oldWidget.user.profileImage != widget.user.profileImage ||
        oldWidget.user.about != widget.user.about) {
      _viewModel.updateUser(widget.user);
    }
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic> _parseBioContent(String bioText) {
    if (bioText.isEmpty) {
      return {
        'textParts': <Map<String, dynamic>>[],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
      };
    }

    return {
      'textParts': [
        {
          'type': 'text',
          'text': bioText,
        }
      ],
      'mediaUrls': <String>[],
      'linkUrls': <String>[],
      'quoteIds': <String>[],
    };
  }

  Widget _buildBioContent(UserModel user) {
    if (user.about.isEmpty) {
      return const SizedBox.shrink();
    }

    final parsedContent = _parseBioContent(user.about);

    return NoteContentWidget(
      parsedContent: parsedContent,
      noteId: 'bio_${user.pubkeyHex}',
      onNavigateToMentionProfile: widget.onNavigateToProfile,
      size: NoteContentSize.small,
    );
  }




  Future<void> _toggleFollow() async {
    final viewModel = Provider.of<ProfileInfoViewModel>(context, listen: false);
    if (viewModel.isFollowing == true) {
      final userName = viewModel.user.name.isNotEmpty
          ? viewModel.user.name
          : (viewModel.user.nip05.isNotEmpty ? viewModel.user.nip05.split('@').first : 'this user');

      showUnfollowUserDialog(
        context: context,
        userName: userName,
        onConfirm: () => viewModel.toggleFollow(),
      );
      return;
    }

    viewModel.toggleFollow().catchError((error) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to follow user: $error');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfileInfoViewModel>.value(
      value: _viewModel,
      child: Consumer<ProfileInfoViewModel>(
        builder: (context, viewModel, child) {
          final user = viewModel.user;
        final screenWidth = MediaQuery.of(context).size.width;
        final websiteUrl = user.website.isNotEmpty && !(user.website.startsWith("http://") || user.website.startsWith("https://"))
            ? "https://${user.website}"
            : user.website;

        return Container(
          color: context.colors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOptimizedBanner(context, user, screenWidth),
              Container(
                transform: Matrix4.translationValues(0, -16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatarAndActionsRow(context, user),
                    const SizedBox(height: 2),
                    _buildNameRow(context, user),
                    if (user.about.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _buildBioContent(user),
                      const SizedBox(height: 4),
                    ],
                    if (user.website.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () async {
                          final Uri url = Uri.parse(websiteUrl);
                          if (!await launchUrl(url)) {
                            throw Exception('Could not launch $url');
                          }
                        },
                        child: InkWell(
                          child: Text(
                            user.website,
                            style: const TextStyle(
                              decoration: TextDecoration.underline,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    _buildFollowerInfo(context),
                  ],
                ),
              ),
            ],
          ),
        );
        },
      ),
    );
  }

  static final Map<String, Widget> _avatarCache = <String, Widget>{};

  Widget _getCachedAvatar(String imageUrl, double radius, String cacheKey) {
    return _avatarCache.putIfAbsent(cacheKey, () {
      try {
        Widget avatarWidget;

        if (imageUrl.isEmpty) {
          avatarWidget = CircleAvatar(
            radius: radius,
            backgroundColor: context.colors.surfaceTransparent,
            child: Icon(
              Icons.person,
              size: radius,
              color: context.colors.textSecondary,
            ),
          );
        } else {
          avatarWidget = CircleAvatar(
            radius: radius,
            backgroundColor: context.colors.surfaceTransparent,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                memCacheWidth: (radius * 5).toInt(),
                maxHeightDiskCache: (radius * 5).toInt(),
                maxWidthDiskCache: (radius * 5).toInt(),
                placeholder: (context, url) => Icon(
                  Icons.person,
                  size: radius,
                  color: context.colors.textSecondary,
                ),
                errorWidget: (context, url, error) => Icon(
                  Icons.person,
                  size: radius,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          );
        }

        return avatarWidget;
      } catch (e) {
        debugPrint('[ProfileInfoWidget] Avatar cache error: $e');
        return CircleAvatar(
          radius: radius,
          backgroundColor: context.colors.surfaceTransparent,
          child: Icon(
            Icons.person,
            size: radius,
            color: context.colors.textSecondary,
          ),
        );
      }
    });
  }

  Widget _buildAvatar(UserModel user) {
    return Consumer<ProfileInfoViewModel>(
      builder: (context, viewModel, child) {
        final currentUser = viewModel.user;
        final avatarRadius = 40.0;
        final cacheKey = 'profile_large_${currentUser.pubkeyHex}_${currentUser.profileImage.hashCode}';

        Widget avatar = RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
              color: context.colors.background,
              width: 3,
            ),
            ),
            child: _getCachedAvatar(
              currentUser.profileImage,
              avatarRadius,
              cacheKey,
            ),
          ),
        );

        if (currentUser.profileImage.isNotEmpty) {
          return GestureDetector(
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => PhotoViewerWidget(imageUrls: [currentUser.profileImage]),
                ),
              );
            },
            child: avatar,
          );
        }

        return avatar;
      },
    );
  }

  Widget _buildNameRow(BuildContext context, UserModel user) {
    return Row(
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  user.name.isNotEmpty ? user.name : (user.nip05.isNotEmpty ? user.nip05.split('@').first : 'Anonymous'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (user.nip05.isNotEmpty && user.nip05Verified) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showVerificationTooltip(context, user.nip05),
                  child: Icon(
                    Icons.verified,
                    size: 22,
                    color: context.colors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showVerificationTooltip(BuildContext context, String nip05) {
    final domain = nip05.split('@').last;
    AppSnackbar.info(context, 'This user is verified by $domain');
  }

  Widget _buildOptimizedBanner(BuildContext context, UserModel user, double screenWidth) {
    final double bannerHeight = screenWidth * (3.5 / 10);

    return GestureDetector(
      onTap: () {
        if (user.banner.isNotEmpty) {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => PhotoViewerWidget(imageUrls: [user.banner]),
            ),
          );
        }
      },
      child: user.banner.isNotEmpty
          ? CachedNetworkImage(
              key: ValueKey('banner_image_${user.pubkeyHex}_${user.banner.hashCode}'),
              imageUrl: user.banner,
              width: screenWidth,
              height: bannerHeight,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              memCacheHeight: (bannerHeight * 2).round(),
              maxHeightDiskCache: (bannerHeight * 3).round(),
              placeholder: (_, __) => Container(
                height: bannerHeight,
                width: screenWidth,
                color: context.colors.grey700,
              ),
              errorWidget: (_, __, ___) => Container(
                height: bannerHeight,
                width: screenWidth,
                color: context.colors.background,
              ),
            )
          : Container(
              height: bannerHeight,
              width: screenWidth,
              color: context.colors.background,
            ),
    );
  }

  Widget _buildAvatarAndActionsRow(BuildContext context, UserModel user) {
    return Consumer<ProfileInfoViewModel>(
      builder: (context, viewModel, child) {
        final currentUserNpub = viewModel.currentUserNpub;
        final isOwnProfile = currentUserNpub != null && currentUserNpub == user.pubkeyHex;

        return Row(
          children: [
            _buildAvatar(user),
            const Spacer(),
            if (currentUserNpub != null && !isOwnProfile)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (viewModel.isMuted != null) ...[
                      _buildMuteButton(context),
                      const SizedBox(width: 8),
                    ],
                    if (viewModel.isFollowing != null)
                      _buildFollowButton(context),
                  ],
                ),
              )
            else if (currentUserNpub != null && isOwnProfile)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _buildEditProfileButton(context),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEditProfileButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.push('/edit-profile');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(
          'Edit profile',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleMute() async {
    final viewModel = Provider.of<ProfileInfoViewModel>(context, listen: false);
    if (viewModel.isMuted == true) {
      viewModel.toggleMute().catchError((error) {
        if (mounted) {
          AppSnackbar.error(context, 'Failed to unmute user: $error');
        }
      });
    } else {
      final userName = viewModel.user.name.isNotEmpty
          ? viewModel.user.name
          : (viewModel.user.nip05.isNotEmpty ? viewModel.user.nip05.split('@').first : 'this user');

      showMuteUserDialog(
        context: context,
        userName: userName,
        onConfirm: () => viewModel.toggleMute(),
      );
    }
  }

  Widget _buildMuteButton(BuildContext context) {
    final viewModel = Provider.of<ProfileInfoViewModel>(context, listen: false);
    final isMuted = viewModel.isMuted ?? false;
    return GestureDetector(
      onTap: _toggleMute,
      child: Container(
        padding: isMuted
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
            : const EdgeInsets.all(8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isMuted ? context.colors.textPrimary : context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
        ),
        child: isMuted
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CarbonIcons.notification_off,
                    size: 16,
                    color: context.colors.background,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Muted',
                    style: TextStyle(
                      color: context.colors.background,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Icon(
                CarbonIcons.notification,
                size: 20,
                color: context.colors.textPrimary,
              ),
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context) {
    final viewModel = Provider.of<ProfileInfoViewModel>(context, listen: false);
    final isFollowing = viewModel.isFollowing ?? false;
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFollowing ? context.colors.overlayLight : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFollowing ? CarbonIcons.user_admin : CarbonIcons.user_follow,
              size: 16,
              color: isFollowing ? context.colors.textPrimary : context.colors.background,
            ),
            const SizedBox(width: 8),
            Text(
              isFollowing ? 'Following' : 'Follow',
              style: TextStyle(
                color: isFollowing ? context.colors.textPrimary : context.colors.background,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      final formatted = (count / 1000000).toStringAsFixed(1);
      return formatted.endsWith('.0')
          ? '${formatted.substring(0, formatted.length - 2)}M'
          : '${formatted}M';
    } else if (count >= 1000) {
      final formatted = (count / 1000).toStringAsFixed(1);
      return formatted.endsWith('.0')
          ? '${formatted.substring(0, formatted.length - 2)}K'
          : '${formatted}K';
    }
    return count.toString();
  }

  Widget _buildFollowerInfo(BuildContext context) {
    final viewModel = Provider.of<ProfileInfoViewModel>(context);
    if (viewModel.isLoadingCounts) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Row(
      children: [
          GestureDetector(
            onTap: () {
              final currentLocation = GoRouterState.of(context).matchedLocation;
              if (currentLocation.startsWith('/home/feed')) {
                context.push('/home/feed/following', extra: viewModel.user);
              } else if (currentLocation.startsWith('/home/notifications')) {
                context.push('/home/notifications/following', extra: viewModel.user);
              } else if (currentLocation.startsWith('/home/dm')) {
                context.push('/home/dm/following', extra: viewModel.user);
              } else {
                context.push('/following', extra: viewModel.user);
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatCount(viewModel.followingCount),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                Text(
                  ' following',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            ' • ',
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatCount(viewModel.followerCount),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              Text(
                ' followers',
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          if (viewModel.doesUserFollowMe == true) ...[
            Text(
              ' • ',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
            Text(
              'Following you',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
          ],
      ],
    );
  }

}
