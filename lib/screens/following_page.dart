import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:auto_size_text/auto_size_text.dart';

class FollowingListPage extends StatefulWidget {
  final String display_name;
  final String npub;

  const FollowingListPage({
    super.key,
    required this.display_name,
    required this.npub,
  });

  @override
  State<FollowingListPage> createState() => _FollowingListPageState();
}

class _FollowingListPageState extends State<FollowingListPage> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _allFollowings = [];
  List<UserModel> _filteredFollowings = [];

  @override
  void initState() {
    super.initState();
    _loadFollowings();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadFollowings() async {
    final dataService =
        DataService(npub: widget.npub, dataType: DataType.profile);
    await dataService.initialize();
    final followingNpubs = await dataService.getFollowingList(widget.npub);

    final box = await Hive.openBox<UserModel>('users');
    final allUsers = box.values.toList();

    final followings =
        allUsers.where((user) => followingNpubs.contains(user.npub)).toList();

    setState(() {
      _allFollowings = followings;
      _filteredFollowings = followings;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() => _filteredFollowings = _allFollowings);
      return;
    }

    final filtered = _allFollowings.where((user) {
      return user.name.toLowerCase().contains(query) ||
          user.nip05.toLowerCase().contains(query) ||
          user.npub.toLowerCase().contains(query);
    }).toList();

    filtered.sort(
        (a, b) => _searchScore(a, query).compareTo(_searchScore(b, query)));

    setState(() {
      _filteredFollowings = filtered;
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

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AutoSizeText(
                  "${widget.display_name}'s Following",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
          hintText: 'Search following...',
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
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: user.profileImage.isNotEmpty
            ? CachedNetworkImageProvider(user.profileImage)
            : null,
        backgroundColor: Colors.grey.shade800,
      ),
      title: Text(user.name, style: TextStyle(color: context.colors.textPrimary)),
      subtitle: Text(
        user.about,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textSecondary),
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
                child: _filteredFollowings.isEmpty
                    ? Center(
                        child: Text(
                          'No followings found.',
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _filteredFollowings.length,
                        itemBuilder: (context, index) =>
                            _buildUserTile(context, _filteredFollowings[index]),
                        separatorBuilder: (_, __) => Divider(
                          color: context.colors.border,
                          height: 1,
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
