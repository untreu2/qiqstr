import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/theme_manager.dart';
import '../media/photo_viewer_widget.dart';
import '../note/note_content_widget.dart';
import '../common/snackbar_widget.dart';
import '../dialogs/unfollow_user_dialog.dart';
import '../dialogs/mute_user_dialog.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/profile_info/profile_info_bloc.dart';
import '../../../presentation/blocs/profile_info/profile_info_event.dart';
import '../../../presentation/blocs/profile_info/profile_info_state.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProfileInfoWidget extends StatefulWidget {
  final Map<String, dynamic> user;
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
  ProfileInfoBloc? _bloc;

  @override
  void didUpdateWidget(ProfileInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPubkeyHex = oldWidget.user['pubkeyHex'] as String? ?? '';
    final oldName = oldWidget.user['name'] as String? ?? '';
    final oldProfileImage = oldWidget.user['profileImage'] as String? ?? '';
    final oldAbout = oldWidget.user['about'] as String? ?? '';
    final newPubkeyHex = widget.user['pubkeyHex'] as String? ?? '';
    final newName = widget.user['name'] as String? ?? '';
    final newProfileImage = widget.user['profileImage'] as String? ?? '';
    final newAbout = widget.user['about'] as String? ?? '';
    if (oldPubkeyHex != newPubkeyHex ||
        oldName != newName ||
        oldProfileImage != newProfileImage ||
        oldAbout != newAbout) {
      _bloc?.add(ProfileInfoUserUpdated(user: widget.user));
    }
  }

  @override
  void dispose() {
    _bloc?.close();
    super.dispose();
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

  Widget _buildBioContent(Map<String, dynamic> user) {
    final about = user['about'] as String? ?? '';
    if (about.isEmpty) {
      return const SizedBox.shrink();
    }

    final parsedContent = _parseBioContent(about);
    final pubkeyHex = user['pubkeyHex'] as String? ?? '';

    return NoteContentWidget(
      parsedContent: parsedContent,
      noteId: 'bio_$pubkeyHex',
      onNavigateToMentionProfile: widget.onNavigateToProfile,
      size: NoteContentSize.small,
    );
  }

  Future<void> _toggleFollow(
      ProfileInfoLoaded state, ProfileInfoBloc bloc) async {
    if (state.isFollowing == true) {
      final userName = () {
        final name = state.user['name'] as String? ?? '';
        if (name.isNotEmpty) {
          return name;
        }
        final nip05 = state.user['nip05'] as String? ?? '';
        return nip05.isNotEmpty ? nip05.split('@').first : 'this user';
      }();

      showUnfollowUserDialog(
        context: context,
        userName: userName,
        onConfirm: () {
          bloc.add(const ProfileInfoFollowToggled());
        },
      );
      return;
    }

    bloc.add(const ProfileInfoFollowToggled());
  }

  @override
  Widget build(BuildContext context) {
    final userPubkeyHex = widget.user['pubkeyHex'] as String? ?? '';
    if (_bloc == null ||
        _bloc!.isClosed ||
        _bloc!.userPubkeyHex != userPubkeyHex) {
      _bloc?.close();
      _bloc = ProfileInfoBloc(
        authRepository: AppDI.get<AuthRepository>(),
        userRepository: AppDI.get<UserRepository>(),
        dataService: AppDI.get<DataService>(),
        userPubkeyHex: userPubkeyHex,
      );
      _bloc!.add(ProfileInfoUserUpdated(user: widget.user));
      _bloc!.add(ProfileInfoInitialized(userPubkeyHex: userPubkeyHex));
    }

    return BlocProvider<ProfileInfoBloc>.value(
      value: _bloc!,
      child: BlocBuilder<ProfileInfoBloc, ProfileInfoState>(
        builder: (context, state) {
          if (state is! ProfileInfoLoaded) {
            return Container(
              color: context.colors.background,
              child: const Center(child: CircularProgressIndicator()),
            );
          }

          final user = state.user;
          final screenWidth = MediaQuery.of(context).size.width;
          final website = user['website'] as String? ?? '';
          final websiteUrl = website.isNotEmpty &&
                  !(website.startsWith("http://") ||
                      website.startsWith("https://"))
              ? "https://$website"
              : website;

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
                      _buildAvatarAndActionsRow(context, state),
                      const SizedBox(height: 2),
                      _buildNameRow(context, user),
                      if ((user['about'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        _buildBioContent(user),
                        const SizedBox(height: 4),
                      ],
                      if (website.isNotEmpty) ...[
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
                              website,
                              style: const TextStyle(
                                decoration: TextDecoration.underline,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      _buildFollowerInfo(context, state),
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

  Widget _getCachedAvatar(
      BuildContext context, String imageUrl, double radius, String cacheKey) {
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

  Widget _buildAvatar(BuildContext context, Map<String, dynamic> user) {
    final avatarRadius = 40.0;
    final pubkeyHex = user['pubkeyHex'] as String? ?? '';
    final profileImage = user['profileImage'] as String? ?? '';
    final cacheKey = 'profile_large_${pubkeyHex}_${profileImage.hashCode}';

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
          context,
          profileImage,
          avatarRadius,
          cacheKey,
        ),
      ),
    );

    if (profileImage.isNotEmpty) {
      return GestureDetector(
        onTap: () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => PhotoViewerWidget(imageUrls: [profileImage]),
            ),
          );
        },
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildNameRow(BuildContext context, Map<String, dynamic> user) {
    final name = user['name'] as String? ?? '';
    final nip05 = user['nip05'] as String? ?? '';
    final nip05Verified = user['nip05Verified'] as bool? ?? false;
    return Row(
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name.isNotEmpty
                      ? name
                      : (nip05.isNotEmpty
                          ? nip05.split('@').first
                          : 'Anonymous'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (nip05.isNotEmpty && nip05Verified) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showVerificationTooltip(context, nip05),
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

  Widget _buildOptimizedBanner(
      BuildContext context, Map<String, dynamic> user, double screenWidth) {
    final double bannerHeight = screenWidth * (3.5 / 10);
    final banner = user['banner'] as String? ?? '';
    final pubkeyHex = user['pubkeyHex'] as String? ?? '';

    return GestureDetector(
      onTap: () {
        if (banner.isNotEmpty) {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => PhotoViewerWidget(imageUrls: [banner]),
            ),
          );
        }
      },
      child: banner.isNotEmpty
          ? CachedNetworkImage(
              key: ValueKey('banner_image_${pubkeyHex}_${banner.hashCode}'),
              imageUrl: banner,
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

  Widget _buildAvatarAndActionsRow(
      BuildContext context, ProfileInfoLoaded state) {
    final currentUserNpub = state.currentUserNpub;
    final authRepository = AppDI.get<AuthRepository>();
    final currentUserHex = currentUserNpub != null
        ? (authRepository.npubToHex(currentUserNpub) ?? currentUserNpub)
        : null;
    final userPubkeyHex = state.user['pubkeyHex'] as String? ?? '';
    final isOwnProfile = currentUserHex != null &&
        currentUserHex.toLowerCase() == userPubkeyHex.toLowerCase();

    return Row(
      children: [
        _buildAvatar(context, state.user),
        const Spacer(),
        if (currentUserNpub != null && !isOwnProfile)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.isMuted != null) ...[
                  _buildMuteButton(context, state),
                  const SizedBox(width: 8),
                ],
                if (state.isFollowing != null)
                  _buildFollowButton(context, state),
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
          borderRadius: BorderRadius.circular(16),
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

  Future<void> _toggleMute(
      ProfileInfoLoaded state, ProfileInfoBloc bloc) async {
    if (state.isMuted == true) {
      bloc.add(const ProfileInfoMuteToggled());
    } else {
      final userName = () {
        final name = state.user['name'] as String? ?? '';
        if (name.isNotEmpty) {
          return name;
        }
        final nip05 = state.user['nip05'] as String? ?? '';
        return nip05.isNotEmpty ? nip05.split('@').first : 'this user';
      }();

      showMuteUserDialog(
        context: context,
        userName: userName,
        onConfirm: () {
          bloc.add(const ProfileInfoMuteToggled());
        },
      );
    }
  }

  Widget _buildMuteButton(BuildContext context, ProfileInfoLoaded state) {
    final isMuted = state.isMuted ?? false;
    final bloc = context.read<ProfileInfoBloc>();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          debugPrint('Mute button tapped');
          _toggleMute(state, bloc);
        },
        borderRadius: BorderRadius.circular(isMuted ? 16 : 40),
        child: Ink(
          padding: isMuted
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              : const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isMuted
                ? context.colors.textPrimary
                : context.colors.overlayLight,
            borderRadius: BorderRadius.circular(isMuted ? 16 : 40),
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
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context, ProfileInfoLoaded state) {
    final isFollowing = state.isFollowing ?? false;
    final bloc = context.read<ProfileInfoBloc>();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          debugPrint('Follow button tapped');
          _toggleFollow(state, bloc);
        },
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isFollowing
                ? context.colors.overlayLight
                : context.colors.textPrimary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFollowing ? CarbonIcons.user_admin : CarbonIcons.user_follow,
                size: 16,
                color: isFollowing
                    ? context.colors.textPrimary
                    : context.colors.background,
              ),
              const SizedBox(width: 8),
              Text(
                isFollowing ? 'Following' : 'Follow',
                style: TextStyle(
                  color: isFollowing
                      ? context.colors.textPrimary
                      : context.colors.background,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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

  Widget _buildFollowerInfo(BuildContext context, ProfileInfoLoaded state) {
    if (state.isLoadingCounts) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final currentUserNpub = state.currentUserNpub;
    final authRepository = AppDI.get<AuthRepository>();
    final currentUserHex = currentUserNpub != null
        ? (authRepository.npubToHex(currentUserNpub) ?? currentUserNpub)
        : null;
    final userPubkeyHex = state.user['pubkeyHex'] as String? ?? '';
    final isOwnProfile = currentUserHex != null &&
        currentUserHex.toLowerCase() == userPubkeyHex.toLowerCase();

    return Row(
      children: [
        GestureDetector(
          onTap: () {
            final currentLocation = GoRouterState.of(context).matchedLocation;
            if (currentLocation.startsWith('/home/feed')) {
              context.push('/home/feed/following', extra: state.user);
            } else if (currentLocation.startsWith('/home/notifications')) {
              context.push('/home/notifications/following', extra: state.user);
            } else if (currentLocation.startsWith('/home/explore')) {
              context.push('/home/feed/following', extra: state.user);
            } else {
              context.push('/following', extra: state.user);
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatCount(state.followingCount),
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
              _formatCount(state.followerCount),
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
        if (state.doesUserFollowMe == true && !isOwnProfile) ...[
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
