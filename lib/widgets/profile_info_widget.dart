import 'package:flutter/material.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProfileInfoWidget extends StatelessWidget {
  final UserModel user;

  const ProfileInfoWidget({super.key, required this.user});

  Future<void> _onOpen(LinkableElement link) async {
    final uri = Uri.parse(link.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final websiteUrl = user.website.isNotEmpty &&
            !(user.website.startsWith("http://") ||
                user.website.startsWith("https://"))
        ? "https://${user.website}"
        : user.website;

    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedNetworkImage(
            imageUrl: user.banner,
            width: screenWidth,
            height: 160,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              height: 160,
              width: screenWidth,
              color: Colors.grey[700],
            ),
            errorWidget: (context, url, error) => Container(
              height: 160,
              width: screenWidth,
              color: Colors.black,
              child: const Icon(Icons.error, color: Colors.red),
            ),
          ),
          Container(
            transform: Matrix4.translationValues(0, -40, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: user.profileImage.isNotEmpty
                        ? CachedNetworkImageProvider(user.profileImage)
                        : null,
                    backgroundColor:
                        user.profileImage.isEmpty ? Colors.grey : null,
                    child: user.profileImage.isEmpty
                        ? const Icon(Icons.person,
                            size: 40, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                user.nip05.contains('@')
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: user.name.isNotEmpty
                                  ? user.name
                                  : user.nip05.split('@').first,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            TextSpan(
                              text: '@${user.nip05.split('@').last}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFBB86FC),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        user.name.isNotEmpty ? user.name : 'Anonymous',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                const SizedBox(height: 12),
                if (user.lud16.isNotEmpty)
                  Text(
                    user.lud16,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber[600],
                    ),
                  ),
                if (user.about.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      user.about,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                if (user.website.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 1),
                    child: Row(
                      children: [
                        const Icon(Icons.link, color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Linkify(
                            onOpen: _onOpen,
                            text: websiteUrl,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.amber,
                            ),
                            linkStyle: const TextStyle(
                              fontSize: 13,
                              color: Colors.amber,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
