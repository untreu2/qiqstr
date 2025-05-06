import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/utils/verify_nip05.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileInfoWidget extends StatefulWidget {
  final UserModel user;

  const ProfileInfoWidget({super.key, required this.user});

  @override
  State<ProfileInfoWidget> createState() => _ProfileInfoWidgetState();
}

class _ProfileInfoWidgetState extends State<ProfileInfoWidget> {
  bool? _isVerified;

  @override
  void initState() {
    super.initState();
    _verifyIfNeeded();
  }

  Future<void> _verifyIfNeeded() async {
    final nip05 = widget.user.nip05;
    final pubkey = widget.user.npub;
    if (nip05.contains('@')) {
      final result = await verifyNip05(nip05, pubkey);
      setState(() {
        _isVerified = result;
      });
    }
  }

  Future<void> _onOpen(LinkableElement link) async {
    final uri = Uri.parse(link.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
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
            height: 130,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              height: 130,
              width: screenWidth,
              color: Colors.grey[700],
            ),
            errorWidget: (context, url, error) => Container(
              height: 130,
              width: screenWidth,
              color: Colors.black,
            ),
          ),
          Container(
            transform: Matrix4.translationValues(0, -30, 0),
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
                Row(
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          Flexible(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 24),
                                children: [
                                  TextSpan(
                                    text: user.name.isNotEmpty
                                        ? user.name
                                        : user.nip05.split('@').first,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (_isVerified == true &&
                                      user.nip05.contains('@'))
                                    const WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 6),
                                        child: Icon(
                                          Icons.verified,
                                          color: Color(0xFFECB200),
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  if (user.nip05.isNotEmpty &&
                                      user.nip05.contains('@'))
                                    TextSpan(
                                      text: '@${user.nip05.split('@').last}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFFECB200),
                                        decoration: _isVerified == false
                                            ? TextDecoration.lineThrough
                                            : null,
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
                const SizedBox(height: 12),
                if (user.lud16.isNotEmpty)
                  Text(
                    user.lud16,
                    style: TextStyle(fontSize: 13, color: Colors.amber[600]),
                  ),
                if (user.about.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      user.about,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ),
                if (user.website.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 1),
                    child: Row(
                      children: [
                        const Icon(Icons.link,
                            color: Color(0xFFECB200), size: 14),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Linkify(
                            onOpen: _onOpen,
                            text: websiteUrl,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFECB200),
                            ),
                            linkStyle: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFECB200),
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
