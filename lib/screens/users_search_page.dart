import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_model.dart';
import '../screens/profile_page.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _filteredUsers = [];
  List<UserModel> _randomUsers = [];
  bool _isSearching = false;
  bool _isLoadingRandom = false;
  bool _isExpandingNetwork = false;
  String? _error;

  late final UserRepository _userRepository;
  bool _hasLoadedFollowing = false;
  bool _hasTriedNetworkExpansion = false;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _searchController.addListener(_onSearchChanged);
    _loadCurrentUserFollowing();
    _loadRandomUsers();

    _startImmediateNetworkExpansion();
  }

  void _startImmediateNetworkExpansion() {
    unawaited(Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_hasTriedNetworkExpansion) {
        debugPrint('[UserSearchPage] Starting immediate network expansion on page load...');
        _expandUserNetwork();
      }
    }));
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _hasTriedNetworkExpansion = false;
    _searchUsers(query);
  }

  Future<void> _loadCurrentUserFollowing() async {
    if (_hasLoadedFollowing) return;

    unawaited(_loadFollowingInBackground());
  }

  Future<void> _loadFollowingInBackground() async {
    try {
      debugPrint('[UserSearchPage] Loading current user following list in background...');

      final followingResult = await _userRepository.getFollowingList();
      if (followingResult.isSuccess && followingResult.data != null) {
        final followingUsers = followingResult.data!;
        debugPrint('[UserSearchPage] Found ${followingUsers.length} users in following list');

        _cacheUsersInParallel(followingUsers);

        _hasLoadedFollowing = true;
        debugPrint('[UserSearchPage] Background loading started for ${followingUsers.length} following users');
      }
    } catch (e) {
      debugPrint('[UserSearchPage] Error loading current user following: $e');
    }
  }

  void _cacheUsersInParallel(List<UserModel> users) {
    unawaited(Future.microtask(() async {
      try {
        const batchSize = 250;
        final List<String> userNpubs = users.map((u) => u.pubkeyHex).toList();

        final uncachedUsers = <String>[];
        for (final npub in userNpubs) {
          final cached = await _userRepository.getCachedUser(npub);
          if (cached == null) {
            uncachedUsers.add(npub);
          }
        }

        if (uncachedUsers.isEmpty) {
          debugPrint('[UserSearchPage] All ${userNpubs.length} users already cached');
          return;
        }

        debugPrint('[UserSearchPage] Caching ${uncachedUsers.length} new users out of ${userNpubs.length} total');

        final futures = <Future>[];
        for (int i = 0; i < uncachedUsers.length; i += batchSize) {
          final batch = uncachedUsers.skip(i).take(batchSize).toList();
          futures.add(_processBatch(batch));
        }

        await Future.wait(futures);
        debugPrint('[UserSearchPage] Background caching completed for ${uncachedUsers.length} new users');
      } catch (e) {
        debugPrint('[UserSearchPage] Error in background caching: $e');
      }
    }));
  }

  Future<void> _processBatch(List<String> batch) async {
    try {
      final profileResults = await _userRepository.getUserProfiles(batch);

      final cacheFutures = <Future>[];
      for (final entry in profileResults.entries) {
        if (entry.value.isSuccess) {
          cacheFutures.add(_userRepository.cacheUser(entry.value.data!));
        }
      }

      await Future.wait(cacheFutures);
    } catch (e) {
      debugPrint('[UserSearchPage] Error processing batch: $e');
    }
  }

  Future<void> _expandUserNetwork() async {
    if (_isExpandingNetwork || _hasTriedNetworkExpansion) return;

    setState(() {
      _isExpandingNetwork = true;
    });

    unawaited(_runNetworkExpansion());
  }

  Future<void> _runNetworkExpansion() async {
    try {
      debugPrint('[UserSearchPage] Starting fast parallel network expansion...');

      final followingResult = await _userRepository.getFollowingList();
      if (followingResult.isError || followingResult.data == null) {
        if (mounted) {
          setState(() {
            _isExpandingNetwork = false;
          });
        }
        return;
      }

      final currentUserFollowing = followingResult.data!;
      debugPrint('[UserSearchPage] Expanding network for ${currentUserFollowing.length} users');

      const chunkSize = 5;
      final chunks = <List<UserModel>>[];

      for (int i = 0; i < currentUserFollowing.length; i += chunkSize) {
        chunks.add(currentUserFollowing.skip(i).take(chunkSize).toList());
      }

      final allFriendsFutures = chunks.take(10).map((chunk) => _processFollowingChunk(chunk));
      final results = await Future.wait(allFriendsFutures);

      final allFriendsOfFriends = <String>{};
      for (final friends in results) {
        allFriendsOfFriends.addAll(friends);
      }

      debugPrint('[UserSearchPage] Found ${allFriendsOfFriends.length} total friends-of-friends');

      if (allFriendsOfFriends.isNotEmpty) {
        _cacheDiscoveredUsers(allFriendsOfFriends.toList());
      }

      _hasTriedNetworkExpansion = true;
    } catch (e) {
      debugPrint('[UserSearchPage] Error in network expansion: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isExpandingNetwork = false;
        });
      }
    }
  }

  Future<Set<String>> _processFollowingChunk(List<UserModel> chunk) async {
    final friends = <String>{};

    final futures = chunk.map((user) async {
      try {
        final userFollowingResult = await _userRepository.getFollowingListForUser(user.pubkeyHex);
        if (userFollowingResult.isSuccess && userFollowingResult.data != null) {
          return userFollowingResult.data!.map((u) => u.pubkeyHex).toSet();
        }
      } catch (e) {
        debugPrint('[UserSearchPage] Error processing ${user.name}: $e');
      }
      return <String>{};
    });

    final results = await Future.wait(futures);
    for (final userFriends in results) {
      friends.addAll(userFriends);
    }

    return friends;
  }

  void _cacheDiscoveredUsers(List<String> userIds) {
    unawaited(Future.microtask(() async {
      try {
        final uncachedUsers = <String>[];
        for (final userId in userIds) {
          final cached = await _userRepository.getCachedUser(userId);
          if (cached == null) {
            uncachedUsers.add(userId);
          }
        }

        if (uncachedUsers.isEmpty) {
          debugPrint('[UserSearchPage] All ${userIds.length} discovered users already cached');
          return;
        }

        debugPrint('[UserSearchPage] Found ${uncachedUsers.length} new users to cache out of ${userIds.length} discovered');

        const batchSize = 250;
        final futures = <Future>[];

        for (int i = 0; i < uncachedUsers.length; i += batchSize) {
          final batch = uncachedUsers.skip(i).take(batchSize).toList();
          futures.add(_processBatch(batch));
        }

        await Future.wait(futures);
        debugPrint('[UserSearchPage] Cached ${uncachedUsers.length} new discovered users');
      } catch (e) {
        debugPrint('[UserSearchPage] Error caching discovered users: $e');
      }
    }));
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
      final searchFuture = _userRepository.searchUsers(query);
      final result = await searchFuture.timeout(
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

          if (users.isEmpty && query.isNotEmpty) {
            debugPrint('[UserSearchPage] No results for "$query", will retry after network expansion...');

            Timer(const Duration(seconds: 1), () {
              if (mounted && query == _searchController.text.trim()) {
                _retrySearchAfterExpansion(query);
              }
            });
          }
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

  void _retrySearchAfterExpansion(String originalQuery) {
    _userRepository.searchUsers(originalQuery).then((result) {
      if (mounted && originalQuery == _searchController.text.trim()) {
        result.fold(
          (retryUsers) {
            if (retryUsers.isNotEmpty) {
              setState(() {
                _filteredUsers = retryUsers;
              });
              debugPrint('[UserSearchPage] Found ${retryUsers.length} users after network expansion');
            }
          },
          (error) => debugPrint('[UserSearchPage] Retry search failed: $error'),
        );
      }
    });
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Text(
        'Search',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _searchController.text = clipboardData.text!;
    }
  }

  Widget _buildUserTile(BuildContext context, UserModel user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePage(user: user),
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
                backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
                backgroundColor: Colors.grey.shade800,
                child: user.profileImage.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 26,
                        color: context.colors.textSecondary,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user.nip05.isNotEmpty && user.nip05Verified) ...[
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
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    if (_isSearching || _isExpandingNetwork) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: context.colors.primary),
            const SizedBox(height: 16),
            Text(
              _isExpandingNetwork ? 'Expanding social network...' : 'Searching for users...',
              style: TextStyle(color: context.colors.textSecondary),
            ),
            if (_isExpandingNetwork) ...[
              const SizedBox(height: 8),
              Text(
                'Looking through friends of friends',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
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
            ElevatedButton(
              onPressed: () => _searchUsers(_searchController.text.trim()),
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
              _hasTriedNetworkExpansion
                  ? 'User not found in your network.\nTry searching with a different term.'
                  : 'Try searching with a different term.',
              style: TextStyle(color: context.colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (_hasTriedNetworkExpansion) ...[
              const SizedBox(height: 8),
              Text(
                'Searched through your social network',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (_filteredUsers.isNotEmpty) {
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _filteredUsers.length,
        itemBuilder: (context, index) => _buildUserTile(context, _filteredUsers[index]),
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
      itemBuilder: (context, index) => _buildUserTile(context, _randomUsers[index]),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: _buildSearchResults(context),
                  ),
                  SizedBox(height: 80),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(context).padding.bottom + 12,
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: context.colors.buttonText),
                    decoration: InputDecoration(
                      hintText: 'Search by name or npub...',
                      hintStyle: TextStyle(color: context.colors.buttonText.withValues(alpha: 0.6)),
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
                      filled: true,
                      fillColor: context.colors.buttonPrimary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(40),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
