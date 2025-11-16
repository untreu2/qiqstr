import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../../theme/theme_manager.dart';
import '../../../models/user_model.dart';
import '../../screens/profile/profile_page.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/dialogs/unfollow_user_dialog.dart';

class UserTile extends StatefulWidget {
  final UserModel user;
  final bool showFollowButton;

  const UserTile({
    super.key,
    required this.user,
    this.showFollowButton = true,
  });

  @override
  State<UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<UserTile> {
  bool? _isFollowing;
  bool _isLoading = false;
  late UserRepository _userRepository;
  late AuthRepository _authRepository;
  StreamSubscription<List<UserModel>>? _followingListSubscription;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _authRepository = AppDI.get<AuthRepository>();
    _checkFollowStatus();
    _setupFollowingListListener();
  }

  @override
  void dispose() {
    _followingListSubscription?.cancel();
    super.dispose();
  }

  void _setupFollowingListListener() async {
    final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
    if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
      return;
    }

    _followingListSubscription = _userRepository.followingListStream.listen(
      (followingList) {
        if (!mounted) return;

        final targetUserHex = widget.user.pubkeyHex;
        final isFollowing = followingList.any((user) => user.pubkeyHex == targetUserHex);

        if (mounted && _isFollowing != isFollowing) {
          setState(() {
            _isFollowing = isFollowing;
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        debugPrint('[UserTile] Error in following list stream: $error');
      },
    );
  }

  Future<void> _checkFollowStatus() async {
    try {
      final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
      if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
        return;
      }

      final followStatusResult = await _userRepository.isFollowing(widget.user.pubkeyHex);

      followStatusResult.fold(
        (isFollowing) {
          if (mounted) {
            setState(() {
              _isFollowing = isFollowing;
            });
          }
        },
        (error) {
          if (mounted) {
            setState(() {
              _isFollowing = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
    if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
      return;
    }

    if (_isFollowing == null || _isLoading) return;

    final originalFollowState = _isFollowing;

    if (originalFollowState == true) {
      final userName = widget.user.name.isNotEmpty
          ? widget.user.name
          : (widget.user.nip05.isNotEmpty ? widget.user.nip05.split('@').first : 'this user');

      showUnfollowUserDialog(
        context: context,
        userName: userName,
        onConfirm: () => _performUnfollow(),
      );
      return;
    }

    _performFollow();
  }

  Future<void> _performFollow() async {
    final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
    if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
      return;
    }

    if (_isFollowing == null || _isLoading) return;

    final originalFollowState = _isFollowing;

    setState(() {
      _isFollowing = !_isFollowing!;
      _isLoading = true;
    });

    try {
      final targetNpub = widget.user.pubkeyHex.startsWith('npub1') ? widget.user.pubkeyHex : _getNpubBech32(widget.user.pubkeyHex);

      final result = await _userRepository.followUser(targetNpub);

      result.fold(
        (_) {
          setState(() {
            _isLoading = false;
          });
        },
        (error) {
          if (mounted) {
            setState(() {
              _isFollowing = originalFollowState;
              _isLoading = false;
            });
            AppSnackbar.error(context, 'Failed to follow user: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = originalFollowState;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _performUnfollow() async {
    final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
    if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
      return;
    }

    if (_isFollowing == null || _isLoading) return;

    final originalFollowState = _isFollowing;

    setState(() {
      _isFollowing = !_isFollowing!;
      _isLoading = true;
    });

    try {
      final targetNpub = widget.user.pubkeyHex.startsWith('npub1') ? widget.user.pubkeyHex : _getNpubBech32(widget.user.pubkeyHex);

      final result = await _userRepository.unfollowUser(targetNpub);

      result.fold(
        (_) {
          setState(() {
            _isLoading = false;
          });
        },
        (error) {
          if (mounted) {
            setState(() {
              _isFollowing = originalFollowState;
              _isLoading = false;
            });
            AppSnackbar.error(context, 'Failed to unfollow user: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = originalFollowState;
          _isLoading = false;
        });
      }
    }
  }

  String _getNpubBech32(String identifier) {
    if (identifier.isEmpty) return '';

    if (identifier.startsWith('npub1')) {
      return identifier;
    }

    if (identifier.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(identifier)) {
      try {
        return encodeBasicBech32(identifier, "npub");
      } catch (e) {
        return identifier;
      }
    }

    return identifier;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _authRepository.getCurrentUserNpub(),
      builder: (context, snapshot) {
        final currentUserNpub = snapshot.data?.fold((data) => data, (error) => null);
        final isCurrentUser = currentUserNpub == widget.user.pubkeyHex || currentUserNpub == widget.user.npub;

        return RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(user: widget.user),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                decoration: BoxDecoration(
                  color: context.colors.overlayLight,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  children: [
                    _UserAvatar(
                      imageUrl: widget.user.profileImage,
                      colors: context.colors,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.user.name.length > 25 ? '${widget.user.name.substring(0, 25)}...' : widget.user.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.user.nip05.isNotEmpty && widget.user.nip05Verified) ...[
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
                    if (widget.showFollowButton && !isCurrentUser && _isFollowing != null) ...[
                      const SizedBox(width: 12),
                      Builder(
                        builder: (context) {
                          final followBgColor = context.colors.buttonPrimary;
                          final followIconColor = context.colors.buttonText;
                          final unfollowBgColor = context.colors.background;
                          final unfollowIconColor = context.colors.textPrimary;

                          return GestureDetector(
                            onTap: _isLoading ? null : _toggleFollow,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: _isFollowing == true ? unfollowBgColor : followBgColor,
                                shape: BoxShape.circle,
                              ),
                              child: _isLoading
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          _isFollowing == true ? unfollowIconColor : followIconColor,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      _isFollowing == true ? CarbonIcons.user_admin : CarbonIcons.user_follow,
                                      size: 21,
                                      color: _isFollowing == true ? unfollowIconColor : followIconColor,
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
          radius: 24,
          backgroundColor: Colors.grey.shade800,
          child: Icon(
            Icons.person,
            size: 26,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 48,
          height: 48,
          color: Colors.transparent,
          child: CachedNetworkImage(
            key: ValueKey('user_avatar_${imageUrl.hashCode}'),
            imageUrl: imageUrl,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            memCacheWidth: 180,
            placeholder: (context, url) => Container(
              color: Colors.grey.shade800,
              child: Icon(
                Icons.person,
                size: 26,
                color: colors.textSecondary,
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey.shade800,
              child: Icon(
                Icons.person,
                size: 26,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
