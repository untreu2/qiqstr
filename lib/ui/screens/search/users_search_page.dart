import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../../models/user_model.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../presentation/viewmodels/user_search_viewmodel.dart';
import '../../../presentation/viewmodels/user_tile_viewmodel.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/dialogs/unfollow_user_dialog.dart';

class UserSearchPage extends StatefulWidget {
  final Function(UserModel)? onUserSelected;
  final BuildContext? parentContext;

  const UserSearchPage({
    super.key,
    this.onUserSelected,
    this.parentContext,
  });

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  late final UserSearchViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = UserSearchViewModel(
      userRepository: AppDI.get(),
    );
    _viewModel.addListener(_onViewModelChanged);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _viewModel.searchUsers(query);
  }



  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _searchController.text = clipboardData.text!;
    }
  }

  Widget _buildSearchResults(BuildContext context) {
    if (_viewModel.isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: context.colors.primary),
            const SizedBox(height: 16),
            Text(
              'Searching for users...',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_viewModel.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: context.colors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Search Error',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _viewModel.error!,
              style: TextStyle(color: context.colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Retry',
              onPressed: () => _viewModel.searchUsers(_searchController.text.trim()),
              backgroundColor: context.colors.accent,
              foregroundColor: context.colors.background,
            ),
          ],
        ),
      );
    }

    if (_viewModel.filteredUsers.isEmpty && _searchController.text.trim().isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: context.colors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with a different term.',
              style: TextStyle(color: context.colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_viewModel.filteredUsers.isNotEmpty) {
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _viewModel.filteredUsers.length,
        itemBuilder: (context, index) {
          final user = _viewModel.filteredUsers[index];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUserItem(context, user),
              if (index < _viewModel.filteredUsers.length - 1) const _UserSeparator(),
            ],
          );
        },
      );
    }

    return _buildRandomUsersBubbleGrid(context);
  }

  Widget _buildRandomUsersBubbleGrid(BuildContext context) {
    if (_viewModel.isLoadingRandom) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: context.colors.primary),
            const SizedBox(height: 16),
            Text(
              'Loading users...',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_viewModel.randomUsers.isEmpty) {
      return Center(
        child: Text(
          'No users to discover yet',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _viewModel.randomUsers.length,
      itemBuilder: (context, index) {
        final user = _viewModel.randomUsers[index];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildUserItem(context, user),
            if (index < _viewModel.randomUsers.length - 1) const _UserSeparator(),
          ],
        );
      },
    );
  }

  Widget _buildUserItem(BuildContext context, UserModel user) {
    return _UserItemWidget(
      user: user,
      onUserSelected: widget.onUserSelected,
      parentContext: widget.parentContext,
    );
  }


  Widget _buildCancelButton() {
    return Semantics(
      label: 'Close dialog',
      button: true,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.close,
            size: 20,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
                decoration: BoxDecoration(
              color: context.colors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
                    ),
                ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _buildCancelButton(),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomInputField(
                    controller: _searchController,
                    autofocus: true,
                    hintText: 'Search by name or npub...',
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: _pasteFromClipboard,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.background,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.content_paste,
                            color: context.colors.textPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildSearchResults(context),
          ),
        ],
      ),
    );
  }
}

class _UserItemWidget extends StatefulWidget {
  final UserModel user;
  final Function(UserModel)? onUserSelected;
  final BuildContext? parentContext;

  const _UserItemWidget({
    required this.user,
    this.onUserSelected,
    this.parentContext,
  });

  @override
  State<_UserItemWidget> createState() => _UserItemWidgetState();
}

class _UserItemWidgetState extends State<_UserItemWidget> {
  late final UserTileViewModel _viewModel;
  String? _currentUserNpub;

  @override
  void initState() {
    super.initState();
    _viewModel = UserTileViewModel(
      userRepository: AppDI.get(),
      authRepository: AppDI.get(),
      user: widget.user,
    );
    _viewModel.addListener(_onViewModelChanged);
    _loadCurrentUserNpub();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadCurrentUserNpub() async {
    final authRepository = AppDI.get<AuthRepository>();
    final result = await authRepository.getCurrentUserNpub();
    result.fold(
      (npub) {
        if (mounted) {
          setState(() {
            _currentUserNpub = npub;
          });
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _currentUserNpub = null;
          });
        }
      },
    );
  }

  Future<void> _toggleFollow() async {
    if (_viewModel.isFollowing == true) {
      final userName = widget.user.name.isNotEmpty
          ? widget.user.name
          : (widget.user.nip05.isNotEmpty ? widget.user.nip05.split('@').first : 'this user');

      showUnfollowUserDialog(
        context: context,
        userName: userName,
        onConfirm: () => _viewModel.toggleFollow(),
      );
      return;
    }

    _viewModel.toggleFollow().catchError((error) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to follow user: $error');
      }
    });
  }

  Widget _buildFollowButton(BuildContext context) {
    final isFollowing = _viewModel.isFollowing ?? false;
    return GestureDetector(
      onTap: _viewModel.isLoading ? null : _toggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFollowing ? context.colors.overlayLight : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(40),
        ),
        child: _viewModel.isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isFollowing ? context.colors.textPrimary : context.colors.background,
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFollowing ? CarbonIcons.user_admin : CarbonIcons.user_follow,
                    size: 16,
                    color: isFollowing ? context.colors.textPrimary : context.colors.background,
                  ),
                  const SizedBox(width: 6),
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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<UserTileViewModel>.value(
      value: _viewModel,
      child: Consumer<UserTileViewModel>(
        builder: (context, viewModel, child) {
          final isCurrentUser = _currentUserNpub == widget.user.pubkeyHex || _currentUserNpub == widget.user.npub;

          return GestureDetector(
          onTap: () {
            if (widget.onUserSelected != null) {
              widget.onUserSelected!(widget.user);
              Navigator.of(context, rootNavigator: true).pop();
            } else {
              Navigator.of(context, rootNavigator: true).pop();
              final navContext = widget.parentContext;
              if (navContext != null && navContext.mounted) {
                Future.microtask(() {
                  try {
                    final router = GoRouter.of(navContext);
                    final currentLocation = router.routerDelegate.currentConfiguration.uri.path;
                    if (currentLocation.startsWith('/home/feed')) {
                      navContext.push('/home/feed/profile?npub=${Uri.encodeComponent(widget.user.npub)}&pubkeyHex=${Uri.encodeComponent(widget.user.pubkeyHex)}');
                    } else if (currentLocation.startsWith('/home/notifications')) {
                      navContext.push('/home/notifications/profile?npub=${Uri.encodeComponent(widget.user.npub)}&pubkeyHex=${Uri.encodeComponent(widget.user.pubkeyHex)}');
                    } else if (currentLocation.startsWith('/home/dm')) {
                      navContext.push('/home/dm/profile?npub=${Uri.encodeComponent(widget.user.npub)}&pubkeyHex=${Uri.encodeComponent(widget.user.pubkeyHex)}');
                    } else {
                      navContext.push('/profile?npub=${Uri.encodeComponent(widget.user.npub)}&pubkeyHex=${Uri.encodeComponent(widget.user.pubkeyHex)}');
                    }
                  } catch (e) {
                    debugPrint('[UserItemWidget] Navigation error: $e');
                  }
                });
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildAvatar(context, widget.user.profileImage),
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
                    ],
                  ),
                ),
                if (!isCurrentUser && viewModel.isFollowing != null) ...[
                  const SizedBox(width: 10),
                  _buildFollowButton(context),
                ],
              ],
            ),
          ),
        );
        },
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, String imageUrl) {
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
