import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/models/following_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:bounce/bounce.dart';
import 'package:hive/hive.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class FollowingPage extends StatefulWidget {
  final UserModel user;
  final DataService? dataService;

  const FollowingPage({
    super.key,
    required this.user,
    this.dataService,
  });

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  List<UserModel> _followingUsers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFollowingUsers();
  }

  Future<void> _loadFollowingUsers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      String targetNpub;
      if (widget.dataService != null) {
        targetNpub = widget.dataService!.npub;
      } else {
        String? userHexKey;
        try {
          if (widget.user.npub.startsWith('npub1')) {
            userHexKey = decodeBasicBech32(widget.user.npub, 'npub');
          } else if (_isValidHex(widget.user.npub)) {
            userHexKey = widget.user.npub;
          }
        } catch (e) {
          print('[FollowingPage] Error converting npub to hex: $e');
        }
        targetNpub = userHexKey ?? widget.user.npub;
      }

      final followingBox = await Hive.openBox<FollowingModel>('followingBox');
      final cachedFollowing = followingBox.get('following_$targetNpub');

      if (cachedFollowing == null || cachedFollowing.pubkeys.isEmpty) {
        setState(() {
          _followingUsers = [];
          _isLoading = false;
        });
        return;
      }

      final followingNpubs = cachedFollowing.pubkeys;
      print('[FollowingPage] Found ${followingNpubs.length} following for $targetNpub');

      final usersBox = await Hive.openBox<UserModel>('users');
      final List<UserModel> users = [];

      for (final npub in followingNpubs) {
        try {
          UserModel? user = usersBox.get(npub);

          if (user != null) {
            users.add(user);
          } else {
            users.add(UserModel(
              npub: npub,
              name: 'Unknown User',
              about: '',
              profileImage: '',
              nip05: '',
              banner: '',
              lud16: '',
              website: '',
              updatedAt: DateTime.now(),
            ));
          }
        } catch (e) {
          print('[FollowingPage] Error loading profile for $npub: $e');
          users.add(UserModel(
            npub: npub,
            name: 'Unknown User',
            about: '',
            profileImage: '',
            nip05: '',
            banner: '',
            lud16: '',
            website: '',
            updatedAt: DateTime.now(),
          ));
        }
      }

      users.sort((a, b) {
        final aName = a.name.isNotEmpty ? a.name : 'Unknown User';
        final bName = b.name.isNotEmpty ? b.name : 'Unknown User';
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });

      setState(() {
        _followingUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      print('[FollowingPage] Error: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Row(
        children: [
          Bounce(
            scaleFactor: 0.85,
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.border),
              ),
              child: Icon(
                Icons.arrow_back,
                color: context.colors.textPrimary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Following',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(BuildContext context, UserModel user) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(user: user),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
              backgroundColor: Colors.grey.shade800,
              child: user.profileImage.isEmpty
                  ? Icon(
                      Icons.person,
                      size: 32,
                      color: context.colors.textSecondary,
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          user.name.isNotEmpty ? (user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name) : 'Unknown User',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.nip05.isNotEmpty) ...[
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '• ${user.nip05}',
                              style: TextStyle(fontSize: 14, color: context.colors.secondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: context.colors.accent),
            const SizedBox(height: 16),
            Text(
              'Loading following list...',
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
              'Error loading following list',
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
            ElevatedButton(
              onPressed: _loadFollowingUsers,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.accent,
                foregroundColor: context.colors.background,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_followingUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: context.colors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No following found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This user is not following anyone yet.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _followingUsers.length,
      itemBuilder: (context, index) => _buildUserTile(context, _followingUsers[index]),
      separatorBuilder: (_, __) => Divider(
        color: context.colors.border,
        height: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              Expanded(
                child: _buildContent(context),
              ),
            ],
          ),
        );
      },
    );
  }
}
