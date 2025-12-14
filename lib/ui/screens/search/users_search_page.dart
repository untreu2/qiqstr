import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../../models/user_model.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../screens/profile/profile_page.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/dialogs/unfollow_user_dialog.dart';

class UserSearchPage extends StatefulWidget {
  final Function(UserModel)? onUserSelected;

  const UserSearchPage({
    super.key,
    this.onUserSelected,
  });

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _filteredUsers = [];
  List<UserModel> _randomUsers = [];
  bool _isSearching = false;
  bool _isLoadingRandom = false;
  String? _error;

  late final UserRepository _userRepository;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _searchController.addListener(_onSearchChanged);
    _loadRandomUsers();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _searchUsers(query);
  }


  Future<void> _loadRandomUsers() async {
    setState(() {
      _isLoadingRandom = true;
    });

    try {
      final isarService = _userRepository.isarService;

      if (!isarService.isInitialized) {
        await isarService.waitForInitialization();
      }

      final randomIsarProfiles = await isarService.getRandomUsersWithImages(limit: 50);

      final userModels = randomIsarProfiles.map((isarProfile) {
        final profileData = isarProfile.toProfileData();
        return UserModel.fromCachedProfile(
          isarProfile.pubkeyHex,
          profileData,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _randomUsers = userModels;
          _isLoadingRandom = false;
        });
      }
    } catch (e) {
      debugPrint('[UserSearchPage] Error loading random users: $e');
      if (mounted) {
        setState(() {
          _isLoadingRandom = false;
        });
      }
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredUsers = [];
        _isSearching = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final result = await _userRepository.searchUsers(query).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Search timed out', const Duration(seconds: 5)),
      );

      if (!mounted) return;

      result.fold(
        (users) {
          setState(() {
            _filteredUsers = users;
            _isSearching = false;
          });
          debugPrint('[UserSearchPage] Found ${users.length} users from cache');
        },
        (error) {
          debugPrint('[UserSearchPage] Search error: $error');
          setState(() {
            _error = 'Search failed. Please try again.';
            _isSearching = false;
            _filteredUsers = [];
          });
        },
      );
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'Search timed out. Please try again.';
          _isSearching = false;
          _filteredUsers = [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search failed: $e';
          _isSearching = false;
          _filteredUsers = [];
        });
      }
    }
  }



  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _searchController.text = clipboardData.text!;
    }
  }

  Widget _buildSearchResults(BuildContext context) {
    if (_isSearching) {
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

    if (_error != null) {
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
              _error!,
              style: TextStyle(color: context.colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Retry',
              onPressed: () => _searchUsers(_searchController.text.trim()),
              backgroundColor: context.colors.accent,
              foregroundColor: context.colors.background,
            ),
          ],
        ),
      );
    }

    if (_filteredUsers.isEmpty && _searchController.text.trim().isNotEmpty) {
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

    if (_filteredUsers.isNotEmpty) {
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _filteredUsers.length,
        itemBuilder: (context, index) {
          final user = _filteredUsers[index];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUserItem(context, user),
              if (index < _filteredUsers.length - 1) const _UserSeparator(),
            ],
          );
        },
      );
    }

    return _buildRandomUsersBubbleGrid(context);
  }

  Widget _buildRandomUsersBubbleGrid(BuildContext context) {
    if (_isLoadingRandom) {
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

    if (_randomUsers.isEmpty) {
      return Center(
        child: Text(
          'No users to discover yet',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _randomUsers.length,
      itemBuilder: (context, index) {
        final user = _randomUsers[index];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildUserItem(context, user),
            if (index < _randomUsers.length - 1) const _UserSeparator(),
          ],
        );
      },
    );
  }

  Widget _buildUserItem(BuildContext context, UserModel user) {
    return _UserItemWidget(
      user: user,
      onUserSelected: widget.onUserSelected,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildCloseButton() {
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
                _buildCloseButton(),
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

  const _UserItemWidget({
    required this.user,
    this.onUserSelected,
  });

  @override
  State<_UserItemWidget> createState() => _UserItemWidgetState();
}

class _UserItemWidgetState extends State<_UserItemWidget> {
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
        debugPrint('[UserItemWidget] Error in following list stream: $error');
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

  Widget _buildFollowButton(BuildContext context) {
    final isFollowing = _isFollowing!;
    return GestureDetector(
      onTap: _isLoading ? null : _toggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFollowing ? context.colors.overlayLight : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(40),
        ),
        child: _isLoading
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
    return FutureBuilder(
      future: _authRepository.getCurrentUserNpub(),
      builder: (context, snapshot) {
        final currentUserNpub = snapshot.data?.fold((data) => data, (error) => null);
        final isCurrentUser = currentUserNpub == widget.user.pubkeyHex || currentUserNpub == widget.user.npub;

        return GestureDetector(
          onTap: () {
            if (widget.onUserSelected != null) {
              widget.onUserSelected!(widget.user);
              Navigator.of(context).pop();
            } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(user: widget.user),
              ),
            );
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
                if (!isCurrentUser && _isFollowing != null) ...[
                  const SizedBox(width: 10),
                  _buildFollowButton(context),
                ],
              ],
            ),
          ),
        );
      },
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
