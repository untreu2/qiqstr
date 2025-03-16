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
    } else {
      throw 'Could not launch ${link.url}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final websiteUrl = user.website.isNotEmpty &&
            !(user.website.startsWith("http://") ||
                user.website.startsWith("https://"))
        ? "https://${user.website}"
        : user.website;

    return SingleChildScrollView(
      child: Column(
        children: [
          user.banner.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: user.banner,
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: double.infinity,
                    height: 250,
                    color: Colors.grey,
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: double.infinity,
                    height: 250,
                    color: Colors.black,
                    child: const Icon(Icons.error, color: Colors.red),
                  ),
                )
              : Container(
                  width: double.infinity,
                  height: 250,
                  color: Colors.black,
                ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: user.profileImage.isNotEmpty
                      ? CachedNetworkImageProvider(user.profileImage)
                      : null,
                  backgroundColor:
                      user.profileImage.isEmpty ? Colors.grey : null,
                  child: user.profileImage.isEmpty
                      ? const Icon(Icons.person, size: 50, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  user.name.isNotEmpty ? user.name : 'Anonymous',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                if (user.nip05.isNotEmpty)
                  Text(
                    user.nip05,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                if (user.lud16.isNotEmpty)
                  Text(
                    user.lud16,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.amber[800],
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
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (user.website.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Linkify(
                            onOpen: _onOpen,
                            text: websiteUrl,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.amber,
                            ),
                            linkStyle: const TextStyle(
                              fontSize: 14,
                              color: Colors.amber,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
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
