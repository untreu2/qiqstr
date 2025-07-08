import 'package:flutter/material.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/utils/logout.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../colors.dart';

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
        color: AppColors.background,
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
                              color: AppColors.textPrimary,
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
                          svgAsset: 'assets/profile_button.svg',
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
                          svgAsset: 'assets/Logout_button.svg',
                          label: 'Logout',
                          iconColor: AppColors.error,
                          textColor: AppColors.error,
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
    required String svgAsset,
    required String label,
    required VoidCallback onTap,
    Color iconColor = AppColors.iconPrimary,
    Color textColor = AppColors.textPrimary,
  }) {
    return ListTile(
      leading: SvgPicture.asset(
        svgAsset,
        width: 20,
        height: 20,
        color: iconColor,
      ),
      title: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 18),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hoverColor: AppColors.hoverTransparent,
      onTap: onTap,
    );
  }
}
