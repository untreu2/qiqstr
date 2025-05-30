import 'package:flutter/material.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/utils/logout.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:carbon_icons/carbon_icons.dart';

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
      setState(() => npub = storedNpub);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.black,
        child: widget.user == null || npub == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const SizedBox(height: 70),
                  Padding(
                    padding: const EdgeInsets.all(16),
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
                          child: Text(
                            widget.user!.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
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
                          iconData: CarbonIcons.user_avatar,
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
                          iconData: CarbonIcons.logout,
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
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData iconData,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
    Color textColor = Colors.white,
  }) {
    return ListTile(
      leading: Icon(
        iconData,
        size: 22,
        color: iconColor,
      ),
      title: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 18),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hoverColor: Colors.white.withOpacity(0.05),
      onTap: onTap,
    );
  }
}
