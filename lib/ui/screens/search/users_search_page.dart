import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../presentation/blocs/user_search/user_search_bloc.dart';
import '../../../presentation/blocs/user_search/user_search_event.dart';
import '../../../presentation/blocs/user_search/user_search_state.dart';
import '../../../presentation/blocs/user_tile/user_tile_bloc.dart';
import '../../../presentation/blocs/user_tile/user_tile_event.dart';
import '../../../presentation/blocs/user_tile/user_tile_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/dialogs/unfollow_user_dialog.dart';

class UserSearchPage extends StatefulWidget {
  final Function(Map<String, dynamic>)? onUserSelected;
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
  Timer? _debounceTimer;
  UserSearchBloc? _searchBloc;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _searchBloc == null) return;
      final query = _searchController.text.trim();
      _searchBloc!.add(UserSearchQueryChanged(query));
    });
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _searchController.text = clipboardData.text!;
    }
  }

  Widget _buildSearchResults(BuildContext context, UserSearchState state) {
    return switch (state) {
      UserSearchLoading() => Center(
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
        ),
      UserSearchError(:final message) => Center(
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
                message,
                style: TextStyle(color: context.colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Retry',
                onPressed: () {
                  context.read<UserSearchBloc>().add(
                      UserSearchQueryChanged(_searchController.text.trim()));
                },
                backgroundColor: context.colors.accent,
                foregroundColor: context.colors.background,
              ),
            ],
          ),
        ),
      UserSearchLoaded(
        :final filteredUsers,
        :final randomUsers,
        :final isSearching,
        :final isLoadingRandom
      ) =>
        isSearching
            ? Center(
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
              )
            : filteredUsers.isEmpty && _searchController.text.trim().isNotEmpty
                ? Center(
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
                  )
                : filteredUsers.isNotEmpty
                    ? ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildUserItem(context, user),
                              if (index < filteredUsers.length - 1)
                                const _UserSeparator(),
                            ],
                          );
                        },
                      )
                    : isLoadingRandom
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                    color: context.colors.primary),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading users...',
                                  style: TextStyle(
                                      color: context.colors.textSecondary),
                                ),
                              ],
                            ),
                          )
                        : randomUsers.isEmpty
                            ? Center(
                                child: Text(
                                  'No users to discover yet',
                                  style: TextStyle(
                                      color: context.colors.textSecondary),
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: randomUsers.length,
                                itemBuilder: (context, index) {
                                  final user = randomUsers[index];
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildUserItem(context, user),
                                      if (index < randomUsers.length - 1)
                                        const _UserSeparator(),
                                    ],
                                  );
                                },
                              ),
      _ => const SizedBox(),
    };
  }

  Widget _buildUserItem(BuildContext context, Map<String, dynamic> user) {
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
    return BlocProvider<UserSearchBloc>(
      create: (context) {
        final bloc = AppDI.get<UserSearchBloc>();
        bloc.add(const UserSearchInitialized());
        _searchBloc = bloc;
        _searchController.addListener(_onSearchChanged);
        return bloc;
      },
      child: BlocBuilder<UserSearchBloc, UserSearchState>(
        builder: (context, state) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
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
                  child: _buildSearchResults(context, state),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserItemWidget extends StatefulWidget {
  final Map<String, dynamic> user;
  final Function(Map<String, dynamic>)? onUserSelected;
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
  String? _currentUserHex;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserHex();
  }

  Future<void> _loadCurrentUserHex() async {
    final authService = AppDI.get<AuthService>();
    final hex = authService.currentUserPubkeyHex;
    if (mounted) {
      setState(() {
        _currentUserHex = hex;
      });
    }
  }

  Future<void> _toggleFollow(UserTileBloc bloc, UserTileLoaded state) async {
    if (state.isFollowing == true) {
      final userName = (widget.user['name'] as String? ?? '').isNotEmpty
          ? widget.user['name'] as String
          : ((widget.user['nip05'] as String? ?? '').isNotEmpty
              ? (widget.user['nip05'] as String).split('@').first
              : 'this user');

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

  Widget _buildFollowButton(
      BuildContext context, UserTileLoaded state, UserTileBloc bloc) {
    final isFollowing = state.isFollowing ?? false;
    return GestureDetector(
      onTap: state.isLoading ? null : () => _toggleFollow(bloc, state),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFollowing
              ? context.colors.overlayLight
              : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: state.isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isFollowing
                        ? context.colors.textPrimary
                        : context.colors.background,
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFollowing
                        ? CarbonIcons.user_admin
                        : CarbonIcons.user_follow,
                    size: 16,
                    color: isFollowing
                        ? context.colors.textPrimary
                        : context.colors.background,
                  ),
                  const SizedBox(width: 6),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<UserTileBloc>(
      create: (context) {
        final userNpub = widget.user['npub'] as String? ?? '';
        final bloc = UserTileBloc(
          followingRepository: AppDI.get<FollowingRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
          userNpub: userNpub,
        );
        if (userNpub.isNotEmpty) {
          bloc.add(UserTileInitialized(userNpub: userNpub));
        }
        return bloc;
      },
      child: BlocBuilder<UserTileBloc, UserTileState>(
        builder: (context, state) {
          final userPubkeyHex = widget.user['pubkeyHex'] as String? ??
              widget.user['pubkey'] as String? ??
              '';
          final isCurrentUser =
              _currentUserHex != null && _currentUserHex == userPubkeyHex;
          final loadedState =
              state is UserTileLoaded ? state : const UserTileLoaded();

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
                      final currentLocation =
                          router.routerDelegate.currentConfiguration.uri.path;
                      final userNpub = widget.user['npub'] as String? ?? '';
                      final userPubkeyHex =
                          widget.user['pubkeyHex'] as String? ?? '';
                      if (userNpub.isEmpty && userPubkeyHex.isEmpty) return;

                      final npubParam =
                          userNpub.isNotEmpty ? userNpub : userPubkeyHex;
                      final pubkeyHexParam =
                          userPubkeyHex.isNotEmpty ? userPubkeyHex : userNpub;

                      if (currentLocation.startsWith('/home/feed')) {
                        navContext.push(
                            '/home/feed/profile?npub=${Uri.encodeComponent(npubParam)}&pubkeyHex=${Uri.encodeComponent(pubkeyHexParam)}');
                      } else if (currentLocation
                          .startsWith('/home/notifications')) {
                        navContext.push(
                            '/home/notifications/profile?npub=${Uri.encodeComponent(npubParam)}&pubkeyHex=${Uri.encodeComponent(pubkeyHexParam)}');
                      } else {
                        navContext.push(
                            '/profile?npub=${Uri.encodeComponent(npubParam)}&pubkeyHex=${Uri.encodeComponent(pubkeyHexParam)}');
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
                  _buildAvatar(
                      context, widget.user['profileImage'] as String? ?? ''),
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
                                  () {
                                    final name =
                                        widget.user['name'] as String? ?? '';
                                    return name.length > 25
                                        ? '${name.substring(0, 25)}...'
                                        : name;
                                  }(),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: context.colors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if ((widget.user['nip05'] as String? ?? '')
                                      .isNotEmpty &&
                                  (widget.user['nip05Verified'] as bool? ??
                                      false)) ...[
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
                  if (!isCurrentUser && loadedState.isFollowing != null) ...[
                    const SizedBox(width: 10),
                    _buildFollowButton(
                        context, loadedState, context.read<UserTileBloc>()),
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
