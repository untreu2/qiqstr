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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        user.banner.isNotEmpty
            ? ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16.0),
                ),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: user.banner,
                      width: double.infinity,
                      height: 200.0,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: double.infinity,
                        height: 200.0,
                        color: Colors.grey,
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: double.infinity,
                        height: 200.0,
                        color: Colors.black,
                        child: const Icon(Icons.error, color: Colors.red),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      height: 200.0,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.5),
                            Colors.transparent,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                width: double.infinity,
                height: 200.0,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16.0),
                  ),
                ),
              ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            color: Colors.black,
            elevation: 4.0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 40.0,
                    backgroundImage: user.profileImage.isNotEmpty
                        ? CachedNetworkImageProvider(user.profileImage)
                        : null,
                    backgroundColor:
                        user.profileImage.isEmpty ? Colors.grey : null,
                    child: user.profileImage.isEmpty
                        ? const Icon(
                            Icons.person,
                            size: 40.0,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name.isNotEmpty ? user.name : 'Anonymous',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20.0,
                          ),
                        ),
                        if (user.nip05.isNotEmpty)
                          Text(
                            user.nip05,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14.0,
                            ),
                          ),
                        if (user.lud16.isNotEmpty)
                          Text(
                            user.lud16,
                            style: TextStyle(
                              color: Colors.amber[800],
                              fontSize: 14.0,
                            ),
                          ),
                        if (user.about.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              user.about,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14.0,
                              ),
                            ),
                          ),
                        if (user.website.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.link,
                                    color: Colors.amber, size: 14.0),
                                const SizedBox(width: 4.0),
                                Expanded(
                                  child: Linkify(
                                    onOpen: _onOpen,
                                    text: websiteUrl,
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 14.0,
                                    ),
                                    linkStyle: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 14.0,
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
            ),
          ),
        ),
      ],
    );
  }
}
