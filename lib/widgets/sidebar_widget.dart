import 'package:flutter/material.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/screens/users_search_page.dart';
import 'package:qiqstr/utils/logout.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SidebarWidget extends StatefulWidget {
  final UserModel? user;

  const SidebarWidget({super.key, this.user});

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  String? npub;

  @override
  void initState() {
    super.initState();
    _loadNpub();
  }

  Future<void> _loadNpub() async {
    final storage = FlutterSecureStorage();
    final storedNpub = await storage.read(key: 'npub');
    if (mounted) {
      setState(() {
        npub = storedNpub;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.black,
      child: widget.user == null || npub == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 50),
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundImage: widget.user!.profileImage.isNotEmpty
                            ? CachedNetworkImageProvider(
                                widget.user!.profileImage)
                            : const AssetImage('assets/default_profile.png')
                                as ImageProvider,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user!.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.user!.nip05.isNotEmpty)
                              Text(
                                '@${widget.user!.nip05.split('@').last}',
                                style: const TextStyle(
                                  color: Color(0xFFECB200),
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      _buildSidebarItem(
                        icon: Icons.person,
                        label: 'Profile',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ProfilePage(user: widget.user!),
                          ),
                        ),
                      ),
                      _buildSidebarItem(
                        icon: Icons.search,
                        label: 'Search',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UserSearchPage(),
                          ),
                        ),
                      ),
                      _buildSidebarItem(
                        icon: Icons.logout,
                        label: 'Logout',
                        iconColor: Colors.redAccent,
                        textColor: Colors.redAccent,
                        onTap: () => Logout.performLogout(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
    Color textColor = Colors.white,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 16),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hoverColor: Colors.black26,
      onTap: onTap,
    );
  }
}
