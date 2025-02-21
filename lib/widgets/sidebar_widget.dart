import 'package:flutter/material.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/utils/logout.dart';

class SidebarWidget extends StatelessWidget {
  final UserModel? user;

  const SidebarWidget({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: user == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.black,
                  child: UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(color: Colors.black),
                    accountName: Text(
                      user!.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    accountEmail: Text(
                      user!.nip05.isNotEmpty ? user!.nip05 : '',
                      style: const TextStyle(color: Colors.white),
                    ),
                    currentAccountPicture: CircleAvatar(
                      backgroundImage: user!.profileImage.isNotEmpty
                          ? NetworkImage(user!.profileImage)
                          : const AssetImage('assets/default_profile.png')
                              as ImageProvider,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.white),
                  title: const Text('Profile',
                      style: TextStyle(color: Colors.white)),
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
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Logout',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Logout.performLogout(context);
                  },
                ),
              ],
            ),
    );
  }
}
