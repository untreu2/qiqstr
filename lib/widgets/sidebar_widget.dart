import 'package:flutter/material.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/utils/logout.dart';

class SidebarWidget extends StatelessWidget {
  final UserModel? user;

  const SidebarWidget({Key? key, this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: user == null
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.black,
                  child: UserAccountsDrawerHeader(
                    decoration: BoxDecoration(color: Colors.black),
                    accountName: Text(
                      user!.name,
                      style: TextStyle(color: Colors.white),
                    ),
                    accountEmail: Text(
                      user!.nip05.isNotEmpty ? user!.nip05 : '',
                      style: TextStyle(color: Colors.white),
                    ),
                    currentAccountPicture: CircleAvatar(
                      backgroundImage: user!.profileImage.isNotEmpty
                          ? NetworkImage(user!.profileImage)
                          : AssetImage('assets/default_profile.png') as ImageProvider,
                    ),
                  ),
                ),

                ListTile(
                  leading: Icon(Icons.person, color: Colors.white),
                  title: Text('Profile', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(npub: user!.npub),
                      ),
                    );
                  },
                ),

                ListTile(
                  leading: Icon(Icons.logout, color: Colors.redAccent),
                  title: Text('Logout', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Logout.performLogout(context);
                  },
                ),
              ],
            ),
    );
  }
}
