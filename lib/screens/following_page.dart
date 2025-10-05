import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_model.dart';
import '../screens/profile_page.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';
import '../widgets/back_button_widget.dart';

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

      final result = await _userRepository.getFollowingListForUser(widget.user.npub);

      if (mounted) {
        result.fold(
          (users) {
            debugPrint('[FollowingPage] Successfully loaded ${users.length} basic following users');
            setState(() {
              _followingUsers = users;
              _isLoading = false;
            });

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

  void _preloadUserProfiles() {
    for (final user in _followingUsers) {
      _loadUserProfile(user.npub);
    }
  }

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

              final index = _followingUsers.indexWhere((u) => u.npub == npub);
              if (index != -1) {
                _followingUsers[index] = user;
              }
            });
          },
          (error) {
            debugPrint('[FollowingPage] Error loading profile for $npub: $error');
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
    final double topPadding = MediaQuery.of(context).padding.top;
    
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 0),
      child: Text(
        'Following',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildUserTile(BuildContext context, UserModel user) {
    final isLoading = _loadingStates[user.npub] == true;
    final loadedUser = _loadedUsers[user.npub] ?? user;

    String displayName;
    if (isLoading) {
      displayName = '${user.npub.substring(0, 16)}... (Loading)';
    } else if (loadedUser.name.isNotEmpty) {
      displayName = loadedUser.name.length > 25 ? '${loadedUser.name.substring(0, 25)}...' : loadedUser.name;
    } else {
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
    if (_error != null) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(context),
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error!,
                      style: TextStyle(color: context.colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
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
            ),
          ],
        ),
      );
    }

    if (_followingUsers.isEmpty && !_isLoading) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(context),
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
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
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFollowingUsers,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeader(context),
          ),
          if (_followingUsers.isEmpty && _isLoading) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ] else ...[
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index.isOdd) {
                    return Divider(
                      color: context.colors.border,
                      height: 1,
                    );
                  }
                  final userIndex = index ~/ 2;
                  return _buildUserTile(context, _followingUsers[userIndex]);
                },
                childCount: _followingUsers.length * 2 - 1,
              ),
            ),
          ],
          const SliverToBoxAdapter(
            child: SizedBox(height: 24),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              _buildContent(context),
              const BackButtonWidget.floating(),
            ],
          ),
        );
      },
    );
  }
}
