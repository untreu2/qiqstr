import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/screens/profile_page.dart';

class FollowingPage extends StatefulWidget {
  final String npub;
  const FollowingPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FollowingPageState createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  UserModel? user;
  late DataService dataService;
  bool isLoading = true;
  String? errorMessage;
  List<UserModel> followingUsers = [];

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.Profile);
    _loadUserProfileAndFollowing();
  }

  Future<void> _loadUserProfileAndFollowing() async {
    try {
      await dataService.initialize();
      final profileData = await dataService.getCachedUserProfile(widget.npub);
      final fetchedFollowingNpubs =
          await dataService.getFollowingList(widget.npub);

      final futures = fetchedFollowingNpubs.map((npub) async {
        final profile = await dataService.getCachedUserProfile(npub);
        return UserModel.fromCachedProfile(npub, profile);
      }).toList();

      final fetchedUsers = await Future.wait(futures);

      setState(() {
        user = UserModel.fromCachedProfile(widget.npub, profileData);
        followingUsers = fetchedUsers;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred while loading following list.';
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  String _buildTitle() {
    if (user == null) return 'Following';
    final name = user!.name.isNotEmpty
        ? user!.name
        : (user!.nip05.isNotEmpty ? user!.nip05 : 'User');
    return "$name's Followings";
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildFollowingList() {
    if (followingUsers.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text(
            'No following yet.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final followedUser = followingUsers[index];

          return ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[700],
              backgroundImage: followedUser.profileImage.isNotEmpty
                  ? CachedNetworkImageProvider(followedUser.profileImage)
                  : null,
              child: followedUser.profileImage.isEmpty
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            title: Text(
              followedUser.name.isNotEmpty ? followedUser.name : 'Anonymous',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              followedUser.nip05.isNotEmpty
                  ? followedUser.nip05
                  : followedUser.npub,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfilePage(user: followedUser),
                ),
              );
            },
          );
        },
        childCount: followingUsers.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: SidebarWidget(user: user),
      body: SafeArea(
        bottom: false,
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : errorMessage != null
                ? Center(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                : CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          child: Text(
                            _buildTitle(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      _buildFollowingList(),
                    ],
                  ),
      ),
    );
  }
}
