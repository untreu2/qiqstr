import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/services/profile_service.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  List<UserModel> _randomUsers = [];
  bool _isSearchingNpub = false;
  UserModel? _npubSearchResult;
  String? _lastNpubQuery;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_onSearchChanged);
  }

  void _loadUsers() async {
    final box = await Hive.openBox<UserModel>('users');
    final users = box.values.toList();

    final shuffledUsers = users.toList()..shuffle();
    _randomUsers = shuffledUsers.take(10).toList();

    setState(() {
      _allUsers = users;
      _filteredUsers = _randomUsers;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = _randomUsers;
        _isSearchingNpub = false;
        _npubSearchResult = null;
        _lastNpubQuery = null;
      });
      return;
    }

    if (_isNpubFormat(query)) {
      _searchByNpub(query);
    } else {
      _searchLocalUsers(query);
    }
  }

  bool _isNpubFormat(String query) {
    return query.startsWith('npub1') && query.length > 10;
  }

  void _searchLocalUsers(String query) {
    final queryLower = query.toLowerCase();
    final filtered = _allUsers.where((user) {
      return user.name.toLowerCase().contains(queryLower) ||
          user.nip05.toLowerCase().contains(queryLower) ||
          user.npub.toLowerCase().contains(queryLower);
    }).toList();

    filtered.sort((a, b) => _searchScore(a, queryLower).compareTo(_searchScore(b, queryLower)));

    setState(() {
      _filteredUsers = filtered;
      _isSearchingNpub = false;
      _npubSearchResult = null;
      _lastNpubQuery = null;
    });
  }

  Future<void> _searchByNpub(String npubQuery) async {
    if (_lastNpubQuery == npubQuery && _npubSearchResult != null) {
      return;
    }

    setState(() {
      _isSearchingNpub = true;
      _lastNpubQuery = npubQuery;
      _npubSearchResult = null;
    });

    try {
      final existingUser = _allUsers.firstWhere(
        (user) => user.npub.toLowerCase() == npubQuery.toLowerCase(),
        orElse: () => UserModel(
          npub: '',
          name: '',
          about: '',
          profileImage: '',
          nip05: '',
          banner: '',
          lud16: '',
          website: '',
          updatedAt: DateTime.now(),
        ),
      );

      if (existingUser.npub.isNotEmpty) {
        setState(() {
          _filteredUsers = [existingUser];
          _isSearchingNpub = false;
          _npubSearchResult = existingUser;
        });
        return;
      }

      String? pubkeyHex;
      try {
        pubkeyHex = decodeBasicBech32(npubQuery, 'npub');
      } catch (e) {
        setState(() {
          _isSearchingNpub = false;
          _filteredUsers = [];
        });
        _showErrorSnackBar('Invalid npub format');
        return;
      }

      final profileService = ProfileService();
      final profileData = await profileService.getCachedUserProfile(pubkeyHex);

      if (profileData['name'] != 'Anonymous' || profileData['about']!.isNotEmpty) {
        final fetchedUser = UserModel.fromCachedProfile(npubQuery, profileData);

        final box = await Hive.openBox<UserModel>('users');
        await box.put(pubkeyHex, fetchedUser);

        _allUsers.add(fetchedUser);

        setState(() {
          _filteredUsers = [fetchedUser];
          _isSearchingNpub = false;
          _npubSearchResult = fetchedUser;
        });
      } else {
        setState(() {
          _isSearchingNpub = false;
          _filteredUsers = [];
        });
        _showErrorSnackBar('User not found');
      }
    } catch (e) {
      setState(() {
        _isSearchingNpub = false;
        _filteredUsers = [];
      });
      _showErrorSnackBar('Error fetching user: ${e.toString()}');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.colors.error.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  int _searchScore(UserModel user, String query) {
    final name = user.name.toLowerCase();
    final nip05 = user.nip05.toLowerCase();
    final npub = user.npub.toLowerCase();

    if (name == query) return 0;
    if (nip05 == query) return 1;
    if (npub == query) return 2;
    if (name.contains(query)) return 3;
    if (nip05.contains(query)) return 4;
    if (npub.contains(query)) return 5;

    return 6;
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Search users',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "There are ${_allUsers.length} users cached on your device.",
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: context.colors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search users by name or public key...',
          hintStyle: TextStyle(color: context.colors.textTertiary),
          prefixIcon: Icon(Icons.search, color: context.colors.textPrimary),
          filled: true,
          fillColor: context.colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
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
                          user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name,
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
                  if (user.about.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      user.about,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.colors.textSecondary,
                        height: 1.3,
                      ),
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

  Widget _buildSearchResults(BuildContext context) {
    if (_isSearchingNpub) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: context.colors.primary),
            const SizedBox(height: 16),
            Text(
              'Searching for user...',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_filteredUsers.isEmpty) {
      return Center(
        child: Text(
          'No users found.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) => _buildUserTile(context, _filteredUsers[index]),
      separatorBuilder: (_, __) => Divider(
        color: context.colors.border,
        height: 1,
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
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              _buildSearchInput(context),
              Expanded(
                child: _buildSearchResults(context),
              ),
            ],
          ),
        );
      },
    );
  }
}
