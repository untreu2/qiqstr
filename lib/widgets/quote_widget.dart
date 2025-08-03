import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/screens/thread_page.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import 'package:qiqstr/widgets/note_content_widget.dart';

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

  void _navigateToMentionProfile(BuildContext context, String id) =>
      dataService.openUserProfile(context, id);

  Map<String, dynamic> _createTruncatedParsedContentWithShowMore(
      Map<String, dynamic> originalParsed, int characterLimit, NoteModel note) {
    final textParts =
        (originalParsed['textParts'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
    final truncatedParts = <Map<String, dynamic>>[];
    int currentLength = 0;

    for (var part in textParts) {
      if (part['type'] == 'text') {
        final text = part['text'] as String;
        if (currentLength + text.length <= characterLimit) {
          truncatedParts.add(part);
          currentLength += text.length;
        } else {
          final remainingChars = characterLimit - currentLength;
          if (remainingChars > 0) {
            truncatedParts.add({
              'type': 'text',
              'text': text.substring(0, remainingChars) + '... ',
            });
          }
          break;
        }
      } else if (part['type'] == 'mention') {
        if (currentLength + 8 <= characterLimit) {
          truncatedParts.add(part);
          currentLength += 8;
        } else {
          break;
        }
      }
    }

    truncatedParts.add({
      'type': 'show_more',
      'text': 'Show more...',
      'noteId': note.id,
    });

    return {
      'textParts': truncatedParts,
      'mediaUrls': originalParsed['mediaUrls'] ?? [],
      'linkUrls': originalParsed['linkUrls'] ?? [],
      'quoteIds': originalParsed['quoteIds'] ?? [],
    };
  }

  Widget _buildNoteContent(
      BuildContext context, Map<String, dynamic> parsed, NoteModel note) {
    final textParts =
        (parsed['textParts'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
    String fullText = '';

    for (var part in textParts) {
      if (part['type'] == 'text') {
        fullText += part['text'] as String;
      } else if (part['type'] == 'mention') {
        fullText += '@mention ';
      }
    }

    const int characterLimit = 140;

    if (fullText.length <= characterLimit) {
      return NoteContentWidget(
        parsedContent: parsed,
        dataService: dataService,
        onNavigateToMentionProfile: (id) => _navigateToMentionProfile(context, id),
      );
    }

    return NoteContentWidget(
      parsedContent:
          _createTruncatedParsedContentWithShowMore(parsed, characterLimit, note),
      dataService: dataService,
      onNavigateToMentionProfile: (id) => _navigateToMentionProfile(context, id),
      onShowMoreTap: (noteId) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ThreadPage(
            rootNoteId: noteId,
            dataService: dataService,
          ),
        ),
      ),
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
                backgroundImage:
                    img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                backgroundColor: img.isEmpty
                    ? context.colors.secondary
                    : context.colors.surfaceTransparent,
                child: img.isEmpty
                    ? Icon(Icons.person, size: 14, color: context.colors.textPrimary)
                    : null,
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
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.border, width: 1),
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
                    style: TextStyle(
                        fontSize: 15, color: context.colors.textPrimary),
                    child: _buildNoteContent(context, parsed, n),
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
