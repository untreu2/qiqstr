import 'dart:async';
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
import '../screens/following_page.dart';
import 'photo_viewer_widget.dart';
import 'profile_image_widget.dart';
import 'package:url_launcher/url_launcher.dart';

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

  int _followingCount = 0;
  bool _isLoadingCounts = true;
  bool? _doesUserFollowMe;

  String? _userHexKey;

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

    final parsedBioContent = tempNote.parsedContentLazy;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: NoteContentWidget(
        parsedContent: parsedBioContent,
        dataService: _dataService!,
        onNavigateToMentionProfile: _navigateToProfile,
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    if (widget.sharedDataService != null) {
      _dataService = widget.sharedDataService;
    }

    _userHexKey = _convertToHex(widget.user.npub);

    _startProgressiveInitialization();
  }

  @override
  void didUpdateWidget(ProfileInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.sharedDataService != null && _dataService == null) {
      _dataService = widget.sharedDataService;
    }
  }

  void _startProgressiveInitialization() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initBasicData();
      }
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _initFollowStatusAsync();
      }
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _loadFollowerCounts();
      }
    });

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        UserProvider.instance.loadUser(widget.user.npub);
      }
    });
  }

  void _initBasicData() {
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

      if (mounted) {
        setState(() {});
      }

      if (_currentUserNpub == null || _userHexKey == null) return;

      String? currentUserHex = _convertToHex(_currentUserNpub!);
      if (currentUserHex == _userHexKey) return;

      _followingBox = await Hive.openBox<FollowingModel>('followingBox');
      final model = _followingBox.get('following_$currentUserHex');

      final isFollowing = model?.pubkeys.contains(_userHexKey!) ?? false;

      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
        });
      }

      if (_dataService == null) {
        print('[ProfileInfoWidget] No shared DataService available for follow status operations');
      }
    } catch (e) {
      print('[ProfileInfoWidget] Follow status init error: $e');
    }
  }

  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  String? _convertToHex(String npub) {
    try {
      if (npub.startsWith('npub1')) {
        return decodeBasicBech32(npub, 'npub');
      } else if (_isValidHex(npub)) {
        return npub;
      }
    } catch (e) {
      print('[ProfileInfoWidget] Error converting npub to hex: $e');
    }
    return npub;
  }

  Future<void> _toggleFollow() async {
    if (_currentUserNpub == null || _dataService == null || _userHexKey == null) return;

    setState(() {
      _isFollowing = !_isFollowing!;
    });

    try {
      print('[ProfileInfoWidget] Toggle follow for hex: $_userHexKey');
      print('[ProfileInfoWidget] Current follow state: $_isFollowing');

      if (_isFollowing!) {
        await _dataService!.sendFollow(_userHexKey!);
        print('[ProfileInfoWidget] Sent follow request');
      } else {
        await _dataService!.sendUnfollow(_userHexKey!);
        print('[ProfileInfoWidget] Sent unfollow request');
      }
    } catch (e) {
      print('[ProfileInfoWidget] Follow toggle error: $e');
      setState(() {
        _isFollowing = !_isFollowing!;
      });
    }
  }

  Future<void> _loadFollowerCounts() async {
    if (_dataService == null) return;

    try {
      final dataServiceNpub = _dataService!.npub;
      final followingCount = await _dataService!.getFollowingCount(dataServiceNpub);

      bool? doesUserFollowMe;
      if (_currentUserNpub != null && _currentUserNpub != dataServiceNpub) {
        print('[ProfileInfoWidget] Checking if $dataServiceNpub follows $_currentUserNpub');
        doesUserFollowMe = await _dataService!.isUserFollowing(dataServiceNpub, _currentUserNpub!);
        print('[ProfileInfoWidget] Result: $doesUserFollowMe');
      }

      if (mounted) {
        setState(() {
          _followingCount = followingCount;
          _doesUserFollowMe = doesUserFollowMe;
          _isLoadingCounts = false;
        });
      }
    } catch (e) {
      print('[ProfileInfoWidget] Error loading following count: $e');
      if (mounted) {
        setState(() {
          _isLoadingCounts = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserProvider.instance,
      builder: (context, _) {
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
              _buildOptimizedBanner(context, user, screenWidth),
              Container(
                transform: Matrix4.translationValues(0, -30, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatarAndActionsRow(context, user),
                    _buildNameRow(context, user),
                    const SizedBox(height: 1),
                    _buildNpubCopyButton(context, npubBech32),
                    if (user.about.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildBioContent(user),
                      const SizedBox(height: 6),
                    ],
                    if (user.website.isNotEmpty && _isInitialized) ...[
                      const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
                    _buildFollowerInfo(context),
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
    return ProfileImageHelper.large(
      imageUrl: user.profileImage,
      npub: user.npub,
      backgroundColor: context.colors.surfaceTransparent,
      borderWidth: 3,
      borderColor: context.colors.background,
      onTap: user.profileImage.isNotEmpty
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoViewerWidget(imageUrls: [user.profileImage]),
                ),
              );
            }
          : null,
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
                const SizedBox(width: 6),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'This user is verified by $domain',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        backgroundColor: context.colors.surface,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
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
              key: ValueKey('banner_image_${user.npub}_${user.banner.hashCode}'),
              imageUrl: user.banner,
              width: screenWidth,
              height: 130,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              memCacheHeight: 260,
              maxHeightDiskCache: 400,
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
    print('[ProfileInfoWidget] Current user npub: $_currentUserNpub');
    print('[ProfileInfoWidget] Viewing user npub: ${widget.user.npub}');
    print('[ProfileInfoWidget] Are they equal: ${widget.user.npub == _currentUserNpub}');
    print('[ProfileInfoWidget] IsFollowing: $_isFollowing');

    final isOwnProfile = _isCurrentUserProfile();
    print('[ProfileInfoWidget] Is own profile: $isOwnProfile');

    return Row(
      children: [
        _buildAvatar(user),
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

  bool _isCurrentUserProfile() {
    if (_currentUserNpub == null || _userHexKey == null) return false;

    String? currentUserHex = _convertToHex(_currentUserNpub!);
    return currentUserHex == _userHexKey;
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
    final isFollowing = _isFollowing!;
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        width: 100,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFollowing ? context.colors.overlayLight : context.colors.buttonPrimary,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.borderAccent),
        ),
        child: Text(
          isFollowing ? 'Following' : 'Follow',
          style: TextStyle(
            color: isFollowing ? context.colors.textPrimary : context.colors.background,
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

  Widget _buildFollowerInfo(BuildContext context) {
    if (_isLoadingCounts) {
      return const Padding(
        padding: EdgeInsets.only(top: 12.0),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowingPage(
                    user: widget.user,
                    dataService: _dataService,
                  ),
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_followingCount',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
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
          if (_doesUserFollowMe == true && _currentUserNpub != null && _currentUserNpub != widget.user.npub) ...[
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
      ),
    );
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
        print('[ProfileInfoWidget] Error converting hex to npub: $e');
        return identifier;
      }
    }

    return identifier;
  }
}
