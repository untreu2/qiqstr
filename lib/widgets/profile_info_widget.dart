import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../theme/theme_manager.dart';
import '../models/user_model.dart';
import '../models/following_model.dart';
import '../screens/edit_profile.dart';
import '../services/data_service.dart';
import '../providers/user_provider.dart';
import 'mini_link_preview_widget.dart';
import 'photo_viewer_widget.dart';

class ProfileInfoWidget extends StatefulWidget {
  final UserModel user;
  final DataService? sharedDataService;

  const ProfileInfoWidget({
    super.key,
    required this.user,
    this.sharedDataService,
  });

  @override
  State<ProfileInfoWidget> createState() => _ProfileInfoWidgetState();
}

class _ProfileInfoWidgetState extends State<ProfileInfoWidget> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool? _isFollowing;
  String? _currentUserNpub;
  late Box<FollowingModel> _followingBox;
  DataService? _dataService;

  bool _copiedToClipboard = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();

    // Use shared DataService if available
    if (widget.sharedDataService != null) {
      _dataService = widget.sharedDataService;
    }

    // Defer all heavy operations with progressive loading
    _startProgressiveInitialization();
  }

  @override
  void didUpdateWidget(ProfileInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update DataService if it becomes available
    if (widget.sharedDataService != null && _dataService == null) {
      _dataService = widget.sharedDataService;
    }
  }

  void _startProgressiveInitialization() {
    // Phase 1: Basic setup (immediate)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initBasicData();
      }
    });

    // Phase 2: Follow status (after 100ms)
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _initFollowStatusAsync();
      }
    });

    // Phase 3: Load user into UserProvider (after 200ms)
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        UserProvider.instance.loadUser(widget.user.npub);
      }
    });
  }

  void _initBasicData() {
    // Set up basic state without heavy operations
    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initFollowStatusAsync() async {
    try {
      _currentUserNpub = await _secureStorage.read(key: 'npub');
      if (_currentUserNpub == null || _currentUserNpub == widget.user.npub) return;

      _followingBox = await Hive.openBox<FollowingModel>('followingBox');
      final model = _followingBox.get('following_$_currentUserNpub');
      final isFollowing = model?.pubkeys.contains(widget.user.npub) ?? false;

      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
        });
      }

      // Don't create new DataService - only use shared one from profile page
      if (_dataService == null) {
        print('[ProfileInfoWidget] No shared DataService available for follow status operations');
      }
    } catch (e) {
      print('[ProfileInfoWidget] Follow status init error: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_currentUserNpub == null || _dataService == null) return;

    setState(() {
      _isFollowing = !_isFollowing!;
    });

    try {
      if (_isFollowing!) {
        await _dataService!.sendFollow(widget.user.npub);
      } else {
        await _dataService!.sendUnfollow(widget.user.npub);
      }
    } catch (e) {
      setState(() {
        _isFollowing = !_isFollowing!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserProvider.instance,
      builder: (context, _) {
        // Get user from UserProvider, fallback to widget.user
        final user = UserProvider.instance.getUser(widget.user.npub) ?? widget.user;
        final npubBech32 = encodeBasicBech32(user.npub, "npub");
        final screenWidth = MediaQuery.of(context).size.width;
        final websiteUrl = user.website.isNotEmpty && !(user.website.startsWith("http://") || user.website.startsWith("https://"))
            ? "https://${user.website}"
            : user.website;

        return Container(
          color: context.colors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Optimized banner loading
              _buildOptimizedBanner(context, user, screenWidth),
              // Main profile content
              Container(
                transform: Matrix4.translationValues(0, -30, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar and action buttons row
                    _buildAvatarAndActionsRow(context, user),
                    const SizedBox(height: 12),

                    // Name and verification
                    _buildNameRow(context, user),
                    const SizedBox(height: 12),

                    // NPUB copy button
                    _buildNpubCopyButton(context, npubBech32),
                    const SizedBox(height: 6),

                    // Lightning address
                    if (user.lud16.isNotEmpty) Text(user.lud16, style: TextStyle(fontSize: 13, color: context.colors.accent)),

                    // About section
                    if (user.about.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(user.about, style: TextStyle(fontSize: 14, color: context.colors.secondary)),
                      ),

                    // Website preview (only load if initialized to avoid blocking)
                    if (user.website.isNotEmpty && _isInitialized)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: MiniLinkPreviewWidget(url: websiteUrl),
                      ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatar(UserModel user) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.background, width: 3),
      ),
      child: CircleAvatar(
        radius: 40,
        backgroundColor: context.colors.surfaceTransparent,
        child: user.profileImage.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: user.profileImage,
                imageBuilder: (context, imageProvider) {
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: imageProvider,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
                placeholder: (context, url) => Icon(
                  Icons.person,
                  size: 48,
                  color: context.colors.textSecondary,
                ),
                errorWidget: (context, url, error) => Icon(
                  Icons.person,
                  size: 48,
                  color: context.colors.textSecondary,
                ),
              )
            : Icon(
                Icons.person,
                size: 48,
                color: context.colors.textSecondary,
              ),
      ),
    );
  }

  Widget _buildNameRow(BuildContext context, UserModel user) {
    return Row(
      children: [
        Flexible(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 24),
              children: [
                TextSpan(
                  text: user.name.isNotEmpty ? user.name : user.nip05.split('@').first,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                  ),
                ),
                if (user.nip05.isNotEmpty && user.nip05.contains('@')) const TextSpan(text: '\u200A'),
                if (user.nip05.isNotEmpty && user.nip05.contains('@'))
                  TextSpan(
                    text: '@${user.nip05.split('@').last}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.colors.accent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptimizedBanner(BuildContext context, UserModel user, double screenWidth) {
    return GestureDetector(
      onTap: () {
        if (user.banner.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PhotoViewerWidget(imageUrls: [user.banner]),
            ),
          );
        }
      },
      child: user.banner.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: user.banner,
              width: screenWidth,
              height: 130,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                height: 130,
                width: screenWidth,
                color: context.colors.grey700,
              ),
              errorWidget: (_, __, ___) => Container(
                height: 130,
                width: screenWidth,
                color: context.colors.background,
              ),
            )
          : Container(
              height: 130,
              width: screenWidth,
              color: context.colors.background,
            ),
    );
  }

  Widget _buildAvatarAndActionsRow(BuildContext context, UserModel user) {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            if (user.profileImage.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoViewerWidget(imageUrls: [user.profileImage]),
                ),
              );
            }
          },
          child: _buildAvatar(user),
        ),
        const Spacer(),
        if (_currentUserNpub != null)
          Padding(
            padding: const EdgeInsets.only(top: 35.0),
            child: (widget.user.npub == _currentUserNpub)
                ? _buildEditProfileButton(context)
                : (_isFollowing != null)
                    ? _buildFollowButton(context)
                    : const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _buildEditProfileButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const EditOwnProfilePage(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.borderAccent),
        ),
        child: Text(
          'Edit profile',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context) {
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.borderAccent),
        ),
        child: Text(
          _isFollowing! ? 'Following' : 'Follow',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildNpubCopyButton(BuildContext context, String npubBech32) {
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: npubBech32));
        setState(() => _copiedToClipboard = true);
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) setState(() => _copiedToClipboard = false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.borderAccent),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: Row(
            key: ValueKey(_copiedToClipboard),
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.copy, size: 14, color: context.colors.textTertiary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _copiedToClipboard ? 'Copied to clipboard' : npubBech32,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
