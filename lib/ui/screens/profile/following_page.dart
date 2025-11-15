import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/user_model.dart';
import 'profile_page.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/user_batch_fetcher.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';

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

      final result = await _userRepository.getFollowingListForUser(widget.user.npub);

      if (mounted) {
        result.fold(
          (users) async {
            setState(() {
              _followingUsers = users;
            });

            await _loadUserProfilesBatch(users);

            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          (error) {
            setState(() {
              _error = error;
              _isLoading = false;
              _followingUsers = [];
            });
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserProfilesBatch(List<UserModel> users) async {
    final npubsToLoad = users
        .where((user) => !_loadingStates.containsKey(user.npub) && !_loadedUsers.containsKey(user.npub))
        .map((user) => user.npub)
        .toList();

    if (npubsToLoad.isEmpty) return;

    for (final npub in npubsToLoad) {
      _loadingStates[npub] = true;
    }

    try {
      final results = await _userRepository.getUserProfiles(npubsToLoad, priority: FetchPriority.high);

      if (mounted) {
        for (final entry in results.entries) {
          final npub = entry.key;
          entry.value.fold(
            (user) {
              _loadedUsers[npub] = user;
              _loadingStates[npub] = false;
              final index = _followingUsers.indexWhere((u) => u.npub == npub);
              if (index != -1) {
                _followingUsers[index] = user;
              }
            },
            (error) {
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
            },
          );
        }
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        for (final npub in npubsToLoad) {
          _loadingStates[npub] = false;
        }
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    return const TitleWidget(
      title: 'Following',
      useTopPadding: true,
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePage(user: loadedUser),
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
              CircleAvatar(
                radius: 24,
                backgroundImage: loadedUser.profileImage.isNotEmpty ? CachedNetworkImageProvider(loadedUser.profileImage) : null,
                backgroundColor: Colors.grey.shade800,
                child: loadedUser.profileImage.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 26,
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
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: isLoading ? context.colors.textSecondary : context.colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (loadedUser.nip05.isNotEmpty && loadedUser.nip05Verified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: context.colors.accent,
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
                  PrimaryButton(
                    label: 'Retry',
                    onPressed: _loadFollowingUsers,
                    backgroundColor: context.colors.accent,
                    foregroundColor: context.colors.background,
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
                  if (index < _followingUsers.length) {
                    return _buildUserTile(context, _followingUsers[index]);
                  }
                  return null;
                },
                childCount: _followingUsers.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
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
