import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:qiqstr/models/user_model.dart';
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
      final result = await _verifyNip05(nip05, pubkey);
      setState(() {
        _isVerified = result;
      });
    }
  }

  Future<bool> _verifyNip05(String nip05, String expectedPubkey) async {
    try {
      if (!nip05.contains('@')) return false;
      final parts = nip05.split('@');
      if (parts.length != 2) return false;
      final localPart = parts[0].toLowerCase();
      final domain = parts[1];
      final url = 'https://$domain/.well-known/nostr.json?name=$localPart';
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return false;
      final responseBody = await response.transform(utf8.decoder).join();
      final jsonResponse = jsonDecode(responseBody);
      if (jsonResponse['names'] == null) return false;
      final nameMapping = jsonResponse['names'];
      if (nameMapping[localPart] == null) return false;
      final returnedPubKey = nameMapping[localPart];
      return (returnedPubKey.toString().toLowerCase() ==
          expectedPubkey.toLowerCase());
    } catch (e) {
      print('Error verifying NIP-05 for $nip05: $e');
      return false;
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
                Row(
                  children: [
                    Flexible(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: user.name.isNotEmpty
                                  ? user.name
                                  : user.nip05.split('@').first,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (user.nip05.isNotEmpty &&
                                user.nip05.contains('@'))
                              const TextSpan(text: ' '),
                            _buildDomainPart(user),
                          ],
                        ),
                      ),
                    ),
                  ],
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

  InlineSpan _buildDomainPart(UserModel user) {
    if (user.nip05.isEmpty || !user.nip05.contains('@')) {
      return const TextSpan(text: '');
    }

    final domain = '@${user.nip05.split('@').last}';

    if (_isVerified == true) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Shimmer.fromColors(
          baseColor: const Color(0xFFBB86FC),
          highlightColor: Colors.white,
          child: Text(
            domain,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFFBB86FC),
            ),
          ),
        ),
      );
    } else {
      return TextSpan(
        text: domain,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: const Color(0xFFBB86FC),
          decoration: _isVerified == false ? TextDecoration.lineThrough : null,
        ),
      );
    }
  }
}
