import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_onSearchChanged);
  }

  void _loadUsers() async {
    final box = await Hive.openBox<UserModel>('users');
    final users = box.values.toList();
    setState(() {
      _allUsers = users;
      _filteredUsers = users;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() => _filteredUsers = _allUsers);
      return;
    }
    final filtered = _allUsers.where((user) {
      return user.name.toLowerCase().contains(query) ||
          user.nip05.toLowerCase().contains(query) ||
          user.npub.toLowerCase().contains(query);
    }).toList();

    filtered.sort(
        (a, b) => _searchScore(a, query).compareTo(_searchScore(b, query)));

    setState(() {
      _filteredUsers = filtered;
    });
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text(
                'Search users',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "There are ${_allUsers.length} users cached on your device.",
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white60,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search users...',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildUserTile(UserModel user) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: user.profileImage.isNotEmpty
            ? CachedNetworkImageProvider(user.profileImage)
            : null,
        backgroundColor: Colors.grey.shade800,
      ),
      title: Text(user.name, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        user.about,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(user: user),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildSearchInput(),
          Expanded(
            child: _filteredUsers.isEmpty
                ? const Center(
                    child: Text(
                      'No users found.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) =>
                        _buildUserTile(_filteredUsers[index]),
                    separatorBuilder: (_, __) => const Divider(
                      color: Colors.white12,
                      height: 1,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
