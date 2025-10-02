import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_model.dart';
import '../screens/profile_page.dart';
import 'package:bounce/bounce.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';

class FollowingPage extends StatefulWidget {
  final UserModel user;

  const FollowingPage({
    super.key,
    required this.user,
  });

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  List<UserModel> _followingUsers = [];
  bool _isLoading = true;
  String? _error;

  // User profile loading states (like note_content_widget.dart)
  final Map<String, UserModel> _loadedUsers = {};
  final Map<String, bool> _loadingStates = {};

  late final UserRepository _userRepository;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _loadFollowingUsers();
  }

  Future<void> _loadFollowingUsers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      debugPrint('[FollowingPage] Loading following users for: ${widget.user.npub}');

      // Get the basic following list (just npub list)
      final result = await _userRepository.getFollowingListForUser(widget.user.npub);

      if (mounted) {
        result.fold(
          (users) {
            debugPrint('[FollowingPage] Successfully loaded ${users.length} basic following users');
            setState(() {
              _followingUsers = users;
              _isLoading = false;
            });

            // Preload individual user profiles (like note_content_widget.dart)
            _preloadUserProfiles();
          },
          (error) {
            debugPrint('[FollowingPage] Error loading following users: $error');
            setState(() {
              _error = error;
              _isLoading = false;
              _followingUsers = [];
            });
          },
        );
      }
    } catch (e) {
      debugPrint('[FollowingPage] Exception: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Preload user profiles for all following users (like note_content_widget.dart)
  void _preloadUserProfiles() {
    for (final user in _followingUsers) {
      _loadUserProfile(user.npub);
    }
  }

  /// Load individual user profile (like note_content_widget.dart _loadMentionUser)
  Future<void> _loadUserProfile(String npub) async {
    if (_loadingStates[npub] == true || _loadedUsers.containsKey(npub)) {
      return; // Already loading or loaded
    }

    _loadingStates[npub] = true;

    try {
      debugPrint('[FollowingPage] Loading profile for: $npub');
      final userResult = await _userRepository.getUserProfile(npub);

      if (mounted) {
        userResult.fold(
          (user) {
            debugPrint('[FollowingPage] Loaded profile for: ${user.name}');
            setState(() {
              _loadedUsers[npub] = user;
              _loadingStates[npub] = false;

              // Update the user in the following list
              final index = _followingUsers.indexWhere((u) => u.npub == npub);
              if (index != -1) {
                _followingUsers[index] = user;
              }
            });
          },
          (error) {
            debugPrint('[FollowingPage] Error loading profile for $npub: $error');
            // Create fallback user (like note_content_widget.dart)
            setState(() {
              _loadedUsers[npub] = UserModel(
                pubkeyHex: npub,
                name: npub.length > 8 ? npub.substring(0, 8) : npub,
                about: '',
                profileImage: '',
                banner: '',
                website: '',
                nip05: '',
                lud16: '',
                updatedAt: DateTime.now(),
                nip05Verified: false,
              );
              _loadingStates[npub] = false;
            });
          },
        );
      }
    } catch (e) {
      debugPrint('[FollowingPage] Exception loading profile for $npub: $e');
      if (mounted) {
        setState(() {
          _loadingStates[npub] = false;
        });
      }
    }
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
    // Check loading state for this specific user (like note_content_widget.dart)
    final isLoading = _loadingStates[user.npub] == true;
    final loadedUser = _loadedUsers[user.npub] ?? user;

    // Determine display name based on loaded data
    String displayName;
    if (isLoading) {
      displayName = '${user.npub.substring(0, 16)}... (Loading)';
    } else if (loadedUser.name.isNotEmpty) {
      // Use the actual loaded name regardless of length
      displayName = loadedUser.name.length > 25 ? '${loadedUser.name.substring(0, 25)}...' : loadedUser.name;
    } else {
      // Fallback to npub prefix if no name available
      displayName = user.npub.startsWith('npub1') ? '${user.npub.substring(0, 16)}...' : 'Unknown User';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(user: loadedUser),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: loadedUser.profileImage.isNotEmpty ? CachedNetworkImageProvider(loadedUser.profileImage) : null,
              backgroundColor: Colors.grey.shade800,
              child: loadedUser.profileImage.isEmpty
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
                          displayName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isLoading ? context.colors.textSecondary : context.colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (loadedUser.nip05.isNotEmpty) ...[
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '• ${loadedUser.nip05}',
                              style: TextStyle(fontSize: 14, color: context.colors.secondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Show loading indicator if this specific profile is loading (like note_content_widget.dart)
                  if (isLoading) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Loading profile...',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
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
