import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/theme_manager.dart';
import '../widgets/common_buttons.dart';
import '../models/user_model.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';
import '../widgets/user_tile_widget.dart';
import '../widgets/title_widget.dart';

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


  Widget _buildHeader(BuildContext context) {
    return const TitleWidget(title: 'Search');
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
        itemBuilder: (context, index) => UserTile(
          key: ValueKey(_filteredUsers[index].pubkeyHex),
          user: _filteredUsers[index],
        ),
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
      itemBuilder: (context, index) => UserTile(
        key: ValueKey(_randomUsers[index].pubkeyHex),
        user: _randomUsers[index],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RepaintBoundary(child: _buildHeader(context)),
              Expanded(
                child: _buildSearchResults(context),
              ),
              const SizedBox(height: 80),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RepaintBoundary(
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
          ),
        ],
      ),
    );
  }
}
