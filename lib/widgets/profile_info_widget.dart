import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/widgets/note_content_widget.dart';
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

  void _navigateToProfile(String npub) {
    if (_dataService != null) {
      _dataService!.openUserProfile(context, npub);
    }
  }

  Widget _buildBioContent(UserModel user) {
    if (_dataService == null || user.about.isEmpty) {
      return const SizedBox.shrink();
    }

    final tempNote = NoteModel(
      id: 'bio_${user.npub}',
      author: user.npub,
      content: user.about,
      timestamp: DateTime.now(),
      isReply: false,
      isRepost: false,
    );

    // Content parsing is now handled lazily through note.parsedContentLazy
    final parsedBioContent = tempNote.parsedContentLazy;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: NoteContentWidget(
        parsedContent: parsedBioContent,
        dataService: _dataService!,
        onNavigateToMentionProfile: _navigateToProfile,
        type: NoteContentType.small,
      ),
    );
  }

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

      // Always set the current user npub, even if viewing own profile
      if (mounted) {
        setState(() {
          // This triggers a rebuild so the edit profile button can show
        });
      }

      // If viewing own profile or no current user, don't load following status
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
        final npubBech32 = _getNpubBech32(user.npub);
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
                    if (user.about.isNotEmpty) _buildBioContent(user),

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
    // Debug logging to help identify issues
    print('[ProfileInfoWidget] Current user npub: $_currentUserNpub');
    print('[ProfileInfoWidget] Viewing user npub: ${widget.user.npub}');
    print('[ProfileInfoWidget] Are they equal: ${widget.user.npub == _currentUserNpub}');
    print('[ProfileInfoWidget] IsFollowing: $_isFollowing');

    // Check if this is the current user's profile with robust npub comparison
    final isOwnProfile = _isCurrentUserProfile();
    print('[ProfileInfoWidget] Is own profile: $isOwnProfile');

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
            child: isOwnProfile
                ? _buildEditProfileButton(context)
                : (_isFollowing != null)
                    ? _buildFollowButton(context)
                    : const SizedBox.shrink(),
          ),
      ],
    );
  }

  // Helper method to check if viewing current user's profile
  bool _isCurrentUserProfile() {
    if (_currentUserNpub == null) return false;

    final currentUserNpub = _currentUserNpub!;
    final viewingUserNpub = widget.user.npub;

    // Direct comparison
    if (currentUserNpub == viewingUserNpub) return true;

    // Try comparing with format conversion
    try {
      // Convert both to hex format for comparison
      String currentUserHex = currentUserNpub;
      String viewingUserHex = viewingUserNpub;

      // Convert npub to hex if needed
      if (currentUserNpub.startsWith('npub1')) {
        currentUserHex = decodeBasicBech32(currentUserNpub, 'npub');
      }

      if (viewingUserNpub.startsWith('npub1')) {
        viewingUserHex = decodeBasicBech32(viewingUserNpub, 'npub');
      }

      // Compare hex formats
      if (currentUserHex == viewingUserHex) return true;

      // Convert both to npub format for comparison
      String currentUserNpubFormat = currentUserNpub;
      String viewingUserNpubFormat = viewingUserNpub;

      // Convert hex to npub if needed
      if (!currentUserNpub.startsWith('npub1') && currentUserNpub.length == 64) {
        currentUserNpubFormat = encodeBasicBech32(currentUserNpub, 'npub');
      }

      if (!viewingUserNpub.startsWith('npub1') && viewingUserNpub.length == 64) {
        viewingUserNpubFormat = encodeBasicBech32(viewingUserNpub, 'npub');
      }

      // Compare npub formats
      if (currentUserNpubFormat == viewingUserNpubFormat) return true;
    } catch (e) {
      print('[ProfileInfoWidget] Error comparing npub formats: $e');
    }

    return false;
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

  // Helper method to safely get npub bech32 format
  String _getNpubBech32(String identifier) {
    if (identifier.isEmpty) return '';

    // If already in npub format, return as is
    if (identifier.startsWith('npub1')) {
      return identifier;
    }

    // If hex format, convert to npub
    if (identifier.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(identifier)) {
      try {
        return encodeBasicBech32(identifier, "npub");
      } catch (e) {
        print('[ProfileInfoWidget] Error converting hex to npub: $e');
        return identifier; // Return original if conversion fails
      }
    }

    // Return original if format is unknown
    return identifier;
  }
}
