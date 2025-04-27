import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/screens/profile_page.dart';

class FollowersPage extends StatefulWidget {
  final String npub;
  const FollowersPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FollowersPageState createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> {
  UserModel? user;
  late DataService dataService;
  bool isLoading = true;
  String? errorMessage;
  List<UserModel> followerUsers = [];

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.Profile);
    _loadUserProfileAndFollowers();
  }

  Future<void> _loadUserProfileAndFollowers() async {
    try {
      await dataService.initialize();
      final profileData = await dataService.getCachedUserProfile(widget.npub);
      final fetchedFollowerNpubs =
          await dataService.getGlobalFollowers(widget.npub);

      final futures = fetchedFollowerNpubs.map((npub) async {
        final profile = await dataService.getCachedUserProfile(npub);
        return UserModel.fromCachedProfile(npub, profile);
      }).toList();

      final fetchedUsers = await Future.wait(futures);

      setState(() {
        user = UserModel.fromCachedProfile(widget.npub, profileData);
        followerUsers = fetchedUsers;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred while loading followers.';
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  String _buildTitle() {
    if (user == null) return 'Followers';
    final name = user!.name.isNotEmpty
        ? user!.name
        : (user!.nip05.isNotEmpty ? user!.nip05 : 'User');
    return "$name's Followers";
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildFollowerList() {
    if (followerUsers.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text(
            'No followers yet.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final follower = followerUsers[index];

          return ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[700],
              backgroundImage: follower.profileImage.isNotEmpty
                  ? CachedNetworkImageProvider(follower.profileImage)
                  : null,
              child: follower.profileImage.isEmpty
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            title: Text(
              follower.name.isNotEmpty ? follower.name : 'Anonymous',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              follower.nip05.isNotEmpty ? follower.nip05 : follower.npub,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfilePage(user: follower),
                ),
              );
            },
          );
        },
        childCount: followerUsers.length,
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
                child: CircularProgressIndicator(color: Colors.white),
              )
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _buildTitle(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "${followerUsers.length} followers",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildFollowerList(),
                    ],
                  ),
      ),
    );
  }
}
