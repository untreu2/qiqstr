import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../presentation/blocs/user_tile/user_tile_bloc.dart';
import '../../../presentation/blocs/user_tile/user_tile_event.dart';
import '../../../presentation/blocs/user_tile/user_tile_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/dialogs/unfollow_user_dialog.dart';

class UserTile extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool showFollowButton;
  final bool isSelected;
  final bool showSelectionIndicator;
  final VoidCallback? onTap;
  final Widget? trailing;

  const UserTile({
    super.key,
    required this.user,
    this.showFollowButton = true,
    this.isSelected = false,
    this.showSelectionIndicator = false,
    this.onTap,
    this.trailing,
  });

  @override
  State<UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<UserTile> {
  Future<void> _toggleFollow(UserTileBloc bloc, UserTileLoaded state) async {
    if (state.isFollowing == true) {
      final userName = () {
        final name = widget.user['name'] as String? ?? '';
        if (name.isNotEmpty) {
          return name;
        }
        final nip05 = widget.user['nip05'] as String? ?? '';
        return nip05.isNotEmpty ? nip05.split('@').first : 'this user';
      }();

      showUnfollowUserDialog(
        context: context,
        userName: userName,
        onConfirm: () {
          bloc.add(const UserTileFollowToggled());
        },
      );
      return;
    }

    bloc.add(const UserTileFollowToggled());
  }


  @override
  Widget build(BuildContext context) {
    return BlocProvider<UserTileBloc>(
      create: (context) {
        final userNpub = widget.user['npub'] as String? ?? '';
        final bloc = UserTileBloc(
          userRepository: AppDI.get(),
          authRepository: AppDI.get(),
          userNpub: userNpub,
        );
        bloc.add(UserTileInitialized(userNpub: userNpub));
        return bloc;
      },
      child: BlocBuilder<UserTileBloc, UserTileState>(
        builder: (context, state) {
          return FutureBuilder(
            future: AppDI.get<AuthRepository>().getCurrentUserNpub(),
            builder: (context, snapshot) {
              final currentUserNpub = snapshot.data?.fold((data) => data, (error) => null);
              final userPubkeyHex = widget.user['pubkeyHex'] as String? ?? '';
              final userNpub = widget.user['npub'] as String? ?? '';
              final isCurrentUser = currentUserNpub == userPubkeyHex || currentUserNpub == userNpub;
              final loadedState = state is UserTileLoaded ? state : const UserTileLoaded();
              final userProfileImage = widget.user['profileImage'] as String? ?? '';
              final userName = widget.user['name'] as String? ?? '';
              final userNip05 = widget.user['nip05'] as String? ?? '';
              final userNip05Verified = widget.user['nip05Verified'] as bool? ?? false;

              return RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: GestureDetector(
                    onTap: widget.onTap ?? () {
                      context.push('/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: context.colors.overlayLight,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Row(
                        children: [
                          _UserAvatar(
                            imageUrl: userProfileImage,
                            colors: context.colors,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: widget.trailing != null ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          userName.length > 25 ? '${userName.substring(0, 25)}...' : userName,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: context.colors.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (userNip05.isNotEmpty && userNip05Verified) ...[
                                        const SizedBox(width: 3),
                                        Icon(
                                          Icons.verified,
                                          size: 14,
                                          color: context.colors.accent,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (widget.trailing != null) ...[
                                  Flexible(
                                    child: widget.trailing!,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (widget.showSelectionIndicator) ...[
                            const SizedBox(width: 10),
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.isSelected ? context.colors.accent : Colors.transparent,
                                border: Border.all(
                                  color: widget.isSelected ? context.colors.accent : context.colors.border,
                                  width: 2,
                                ),
                              ),
                              child: widget.isSelected
                                  ? Icon(
                                      Icons.check,
                                      color: context.colors.background,
                                      size: 14,
                                    )
                                  : null,
                            ),
                          ],
                          if (widget.showFollowButton && !isCurrentUser && loadedState.isFollowing != null && !widget.showSelectionIndicator) ...[
                            const SizedBox(width: 10),
                            Builder(
                              builder: (context) {
                                final followBgColor = context.colors.textPrimary;
                                final followIconColor = context.colors.background;
                                final unfollowBgColor = context.colors.background;
                                final unfollowIconColor = context.colors.textPrimary;
                                final bloc = context.read<UserTileBloc>();

                                return GestureDetector(
                                  onTap: loadedState.isLoading ? null : () => _toggleFollow(bloc, loadedState),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: loadedState.isFollowing == true ? unfollowBgColor : followBgColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: loadedState.isLoading
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                loadedState.isFollowing == true ? unfollowIconColor : followIconColor,
                                              ),
                                            ),
                                          )
                                        : Icon(
                                            loadedState.isFollowing == true ? CarbonIcons.user_admin : CarbonIcons.user_follow,
                                            size: 18,
                                            color: loadedState.isFollowing == true ? unfollowIconColor : followIconColor,
                                          ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final String imageUrl;
  final dynamic colors;

  const _UserAvatar({
    required this.imageUrl,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return RepaintBoundary(
        child: CircleAvatar(
          radius: 20,
          backgroundColor: Colors.grey.shade800,
          child: Icon(
            Icons.person,
            size: 22,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 40,
          height: 40,
          color: Colors.transparent,
          child: CachedNetworkImage(
            key: ValueKey('user_avatar_${imageUrl.hashCode}'),
            imageUrl: imageUrl,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            memCacheWidth: 160,
            placeholder: (context, url) => Container(
              color: Colors.grey.shade800,
              child: Icon(
                Icons.person,
                size: 22,
                color: colors.textSecondary,
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey.shade800,
              child: Icon(
                Icons.person,
                size: 22,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
