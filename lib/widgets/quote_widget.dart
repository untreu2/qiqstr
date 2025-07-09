import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';

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

  Future<Map<String, String>> _fetchAllMentions(
      List<Map<String, dynamic>> mentionParts) async {
    final Map<String, String> results = {};
    for (final part in mentionParts) {
      final id = part['id'] as String;
      try {
        String? pubHex;
        if (id.startsWith('npub1')) {
          pubHex = decodeBasicBech32(id, 'npub');
        } else if (id.startsWith('nprofile1')) {
          pubHex = decodeTlvBech32Full(id, 'nprofile')['type_0_main'];
        }
        if (pubHex != null) {
          final data = await dataService.getCachedUserProfile(pubHex);
          final user = UserModel.fromCachedProfile(pubHex, data);
          if (user.name.isNotEmpty) {
            results[id] = user.name;
          }
        }
      } catch (_) {}
    }
    return results;
  }

  Widget _contentText(BuildContext context, Map<String, dynamic> parsed) {
    final parts = parsed['textParts'] as List<Map<String, dynamic>>;

    return FutureBuilder<Map<String, String>>(
      future: _fetchAllMentions(
          parts.where((p) => p['type'] == 'mention').toList()),
      builder: (context, snapshot) {
        final resolvedMentions = snapshot.data ?? {};
        List<InlineSpan> spans = [];

        for (var p in parts) {
          if (p['type'] == 'text') {
            final text = p['text'] as String;
            final regex = RegExp(r'(https?:\/\/[^\s]+)');
            final matches = regex.allMatches(text);

            int lastMatchEnd = 0;
            for (final match in matches) {
              if (match.start > lastMatchEnd) {
                spans.add(TextSpan(
                  text: text.substring(lastMatchEnd, match.start),
                  style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
                ));
              }
              final url = text.substring(match.start, match.end);
              spans.add(
                TextSpan(
                  text: url,
                  style: TextStyle(
                    color: context.colors.accent,
                    fontStyle: FontStyle.normal,
                    fontSize: 14,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _onOpen(LinkableElement(url, url)),
                ),
              );
              lastMatchEnd = match.end;
            }

            if (lastMatchEnd < text.length) {
              spans.add(TextSpan(
                text: text.substring(lastMatchEnd),
                style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
              ));
            }
          } else if (p['type'] == 'mention') {
            final mentionId = p['id'] as String;
            final display_name = resolvedMentions[mentionId] ?? '${mentionId.substring(0, 8)}…';
            spans.add(
              TextSpan(
                text: '@$display_name',
                style: TextStyle(
                  color: context.colors.accent,
                  fontSize: 14,
                  fontStyle: FontStyle.normal,
                ),
                recognizer: TapGestureRecognizer()..onTap = () => dataService.openUserProfile(context, mentionId),
              ),
            );
          }
        }

        return RichText(text: TextSpan(children: spans));
      },
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

  Widget _authorInfo(BuildContext context, String npub) {
    return FutureBuilder<Map<String, String>>(
      future: dataService.getCachedUserProfile(npub),
      builder: (_, snap) {
        String name = 'Anonymous', img = '';
        if (snap.hasData) {
          final u = UserModel.fromCachedProfile(npub, snap.data!);
          name = u.name;
          img = u.profileImage;
        }
        return GestureDetector(
          onTap: () => dataService.openUserProfile(context, npub),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                backgroundColor: img.isEmpty ? context.colors.secondary : context.colors.surfaceTransparent,
                child: img.isEmpty ? Icon(Icons.person, size: 14, color: context.colors.textPrimary) : null,
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NoteModel?>(
      future: _fetchNote(),
      builder: (_, snap) {
        if (!snap.hasData || snap.data == null) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.textPrimary, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: context.colors.textPrimary.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                'Event not found',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }

        final n = snap.data!;
        dataService.parseContentForNote(n);
        final parsed = n.parsedContent!;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.grey800, width: 1),
            boxShadow: [
              BoxShadow(
                color: context.colors.background.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _authorInfo(context, n.author),
                  const Spacer(),
                  Text(
                    _formatTimestamp(n.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              if ((parsed['textParts'] as List)
                  .where((p) =>
                      p['type'] == 'text' &&
                      (p['text'] as String).trim().isNotEmpty)
                  .isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: DefaultTextStyle(
                    style: TextStyle(fontSize: 15, color: context.colors.textPrimary),
                    child: _contentText(context, parsed),
                  ),
                ),
              if ((parsed['mediaUrls'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: MediaPreviewWidget(
                    mediaUrls: parsed['mediaUrls'] as List<String>,
                  ),
                ),
              if ((parsed['linkUrls'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
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
