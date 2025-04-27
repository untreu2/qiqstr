import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
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
  Color? _domainColor;

  @override
  void initState() {
    super.initState();
    _verifyIfNeeded();
    _generatePalette();
  }

  Future<void> _verifyIfNeeded() async {
    final nip05 = widget.user.nip05;
    final pubkey = widget.user.npub;
    if (nip05.contains('@')) {
      final result = await _verifyNip05(nip05, pubkey);
      setState(() => _isVerified = result);
    }
  }

  Future<void> _generatePalette() async {
    if (widget.user.profileImage.isEmpty) return;
    final imageProvider = CachedNetworkImageProvider(widget.user.profileImage);
    final palette = await PaletteGenerator.fromImageProvider(imageProvider);
    final dominantColor = palette.dominantColor?.color;
    if (dominantColor != null) {
      setState(() {
        _domainColor = _lighten(dominantColor, 0.5);
      });
    }
  }

  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final hslLight =
        hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return hslLight.toColor();
  }

  Future<bool> _verifyNip05(String nip05, String expectedPubkey) async {
    try {
      final parts = nip05.split('@');
      final url = 'https://${parts[1]}/.well-known/nostr.json?name=${parts[0]}';
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return false;
      final jsonResponse =
          jsonDecode(await response.transform(utf8.decoder).join());
      return (jsonResponse['names']?[parts[0]]?.toString().toLowerCase() ??
              '') ==
          expectedPubkey.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  Future<void> _onOpen(LinkableElement link) async {
    final uri = Uri.parse(link.url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final screenWidth = MediaQuery.of(context).size.width;
    final websiteUrl = user.website.isNotEmpty &&
            !user.website.startsWith(RegExp(r'https?://'))
        ? "https://${user.website}"
        : user.website;

    return Container(
      color: Colors.black,
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CachedNetworkImage(
                imageUrl: user.banner,
                width: screenWidth,
                height: 180,
                fit: BoxFit.cover,
                placeholder: (context, _) => Container(
                  width: screenWidth,
                  height: 180,
                  color: Colors.grey[800],
                ),
                errorWidget: (context, _, __) => Container(
                  width: screenWidth,
                  height: 180,
                  color: Colors.black,
                  child: const Icon(Icons.broken_image, color: Colors.red),
                ),
              ),
              Positioned(
                bottom: -56,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: user.profileImage.isNotEmpty
                        ? CachedNetworkImageProvider(user.profileImage)
                        : null,
                    backgroundColor: Colors.grey,
                    child: user.profileImage.isEmpty
                        ? const Icon(Icons.person,
                            size: 52, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 64),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNameRow(user),
                const SizedBox(height: 8),
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
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      user.about,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.5,
                      ),
                    ),
                  ),
                if (user.website.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.link, color: Colors.amber, size: 16),
                        const SizedBox(width: 6),
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
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameRow(UserModel user) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
                if (user.nip05.isNotEmpty) const TextSpan(text: ' '),
                _buildDomainPart(user),
              ],
            ),
          ),
        ),
      ],
    );
  }

  InlineSpan _buildDomainPart(UserModel user) {
    if (user.nip05.isEmpty) return const TextSpan();
    final domain = '@${user.nip05.split('@').last}';

    return TextSpan(
      text: domain,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: _domainColor ?? const Color(0xFFBB86FC),
        decoration: _isVerified == false ? TextDecoration.lineThrough : null,
      ),
    );
  }
}
