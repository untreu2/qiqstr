import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import 'content_parser.dart';

class QuoteWidget extends StatelessWidget {
  final String bech32;
  final DataService dataService;

  const QuoteWidget({
    super.key,
    required this.bech32,
    required this.dataService,
  });

  String _formatTimestamp(DateTime ts) {
    final d = DateTime.now().difference(ts);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  Future<void> _onOpen(LinkableElement link) async {
    final url = Uri.parse(link.url);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Widget _authorInfo(String npub) {
    return FutureBuilder<Map<String, String>>(
      future: dataService.getCachedUserProfile(npub),
      builder: (_, snap) {
        String name = 'Anonymous', img = '';
        if (snap.hasData) {
          final u = UserModel.fromCachedProfile(npub, snap.data!);
          name = u.name;
          img = u.profileImage;
        }
        return Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundImage:
                  img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
              backgroundColor: img.isEmpty ? Colors.grey : Colors.transparent,
              child: img.isEmpty
                  ? const Icon(Icons.person, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 6),
            Text(name,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white)),
          ],
        );
      },
    );
  }

  Widget _contentText(Map<String, dynamic> parsed) {
    final parts = parsed['textParts'] as List<Map<String, dynamic>>;
    return Wrap(
      children: parts.map((p) {
        if (p['type'] == 'text') {
          return Linkify(
            text: p['text'] as String,
            onOpen: _onOpen,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
            linkStyle: const TextStyle(color: Colors.amberAccent),
          );
        }
        return Text('@${(p['id'] as String).substring(0, 8)}…',
            style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 14,
                fontStyle: FontStyle.italic));
      }).toList(),
    );
  }

  Future<NoteModel?> _fetchNote() async {
    String? hex;
    if (bech32.startsWith('note1')) {
      hex = decodeBasicBech32(bech32, 'note');
    } else if (bech32.startsWith('nevent1')) {
      hex = decodeTlvBech32Full(bech32, 'nevent')['type_0_main'];
    }
    if (hex == null) return null;
    return await dataService.getCachedNote(hex);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NoteModel?>(
      future: _fetchNote(),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final n = snap.data!;
        final parsed = parseContent(n.content);
        return Container(
          margin: const EdgeInsets.only(top: 6, left: 12, right: 12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: .5),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _authorInfo(n.author),
                  const Spacer(),
                  Text(_formatTimestamp(n.timestamp),
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 4),
              _contentText(parsed),
              if ((parsed['mediaUrls'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: MediaPreviewWidget(
                    mediaUrls: parsed['mediaUrls'] as List<String>,
                  ),
                ),
              if ((parsed['linkUrls'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    children: (parsed['linkUrls'] as List<String>)
                        .map((u) => LinkPreviewWidget(url: u))
                        .toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
