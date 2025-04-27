import 'package:flutter/material.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/screens/following_page.dart';
import 'package:qiqstr/utils/logout.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SidebarWidget extends StatelessWidget {
  final UserModel? user;

  const SidebarWidget({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.black,
      child: user == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SafeArea(
                  bottom: false,
                  child: SizedBox.shrink(),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.white10, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: user!.profileImage.isNotEmpty
                            ? CachedNetworkImageProvider(user!.profileImage)
                            : const AssetImage('assets/default_profile.png')
                                as ImageProvider,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user!.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (user!.nip05.isNotEmpty)
                              Text(
                                '@${user!.nip05.split('@').last}',
                                style: const TextStyle(
                                  color: Color(0xFFBB86FC),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.white),
                  title: const Text(
                    'Profile',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(user: user!),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group, color: Colors.white),
                  title: const Text(
                    'Followings',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FollowingPage(npub: user!.npub),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.redAccent, fontSize: 15),
                  ),
                  onTap: () {
                    Logout.performLogout(context);
                  },
                ),
              ],
            ),
    );
  }
}
