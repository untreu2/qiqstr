import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import 'package:qiqstr/widgets/quote_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/theme_manager.dart';

enum NoteContentType { small, big }

class NoteContentWidget extends StatelessWidget {
  final Map<String, dynamic> parsedContent;
  final DataService dataService;
  final void Function(String mentionId) onNavigateToMentionProfile;
  final void Function(String noteId)? onShowMoreTap;
  final NoteContentType type;

  double get _fontSize {
    switch (type) {
      case NoteContentType.small:
        return 15.0;
      case NoteContentType.big:
        return 17.0;
    }
  }

  const NoteContentWidget({
    Key? key,
    required this.parsedContent,
    required this.dataService,
    required this.onNavigateToMentionProfile,
    this.onShowMoreTap,
    this.type = NoteContentType.small,
  }) : super(key: key);

  Future<void> _onOpenLink(BuildContext context, LinkableElement link) async {
    final url = Uri.parse(link.url);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch ${link.url}')),
        );
      }
    }
  }

  void _onHashtagTap(BuildContext context, String hashtag) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Designing: Hashtags for $hashtag')),
    );
  }

  Widget _buildRichTextContent(
    BuildContext context,
    Map<String, String> mentions,
  ) {
    final parts = (parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final spans = <InlineSpan>[];
    final currentFontSize = _fontSize * textScaleFactor;
    final colors = context.colors;

    for (var p in parts) {
      if (p['type'] == 'text') {
        final text = p['text'] as String;
        final regex = RegExp(r'(https?:\/\/[^\s]+)|(#\w+)');
        final matches = regex.allMatches(text);
        var last = 0;

        for (final m in matches) {
          if (m.start > last) {
            spans.add(TextSpan(
              text: text.substring(last, m.start),
              style: TextStyle(fontSize: currentFontSize, color: colors.textPrimary),
            ));
          }

          final urlMatch = m.group(1);
          final hashtagMatch = m.group(2);

          if (urlMatch != null) {
            spans.add(TextSpan(
              text: urlMatch,
              style: TextStyle(color: colors.accent, fontSize: currentFontSize),
              recognizer: TapGestureRecognizer()..onTap = () => _onOpenLink(context, LinkableElement(urlMatch, urlMatch)),
            ));
          } else if (hashtagMatch != null) {
            spans.add(TextSpan(
              text: hashtagMatch,
              style: TextStyle(color: colors.accent, fontSize: currentFontSize),
              recognizer: TapGestureRecognizer()..onTap = () => _onHashtagTap(context, hashtagMatch),
            ));
          }
          last = m.end;
        }

        if (last < text.length) {
          spans.add(TextSpan(
            text: text.substring(last),
            style: TextStyle(fontSize: currentFontSize, color: colors.textPrimary),
          ));
        }
      } else if (p['type'] == 'mention') {
        final display_name = mentions[p['id']] ?? '${(p['id'] as String).substring(0, 8)}...';
        spans.add(TextSpan(
          text: '@$display_name',
          style: TextStyle(color: colors.accent, fontSize: currentFontSize, fontWeight: FontWeight.w500),
          recognizer: TapGestureRecognizer()..onTap = () => onNavigateToMentionProfile(p['id'] as String),
        ));
      } else if (p['type'] == 'show_more') {
        spans.add(TextSpan(
          text: p['text'] as String,
          style: TextStyle(
            color: colors.accent,
            fontSize: currentFontSize,
            fontWeight: FontWeight.w500,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => onShowMoreTap?.call(p['noteId'] as String),
        ));
      }
    }
    return RichText(
      text: TextSpan(children: spans),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      strutStyle: StrutStyle(
        fontSize: currentFontSize,
        height: 1.4,
        forceStrutHeight: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textParts = (parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final mediaUrls = (parsedContent['mediaUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    final linkUrls = (parsedContent['linkUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    final quoteIds = (parsedContent['quoteIds'] as List<dynamic>?)?.cast<String>() ?? [];

    final mentionIds = textParts.where((p) => p['type'] == 'mention').map((p) => p['id'] as String).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (textParts.isNotEmpty)
          FutureBuilder<Map<String, String>>(
            future: dataService.resolveMentions(mentionIds),
            builder: (context, snapshot) {
              final mentionsMap = snapshot.data ?? {};
              return _buildRichTextContent(context, mentionsMap);
            },
          ),
        if (mediaUrls.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MediaPreviewWidget(mediaUrls: mediaUrls),
          ),
        if (linkUrls.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: linkUrls.map((u) => LinkPreviewWidget(url: u)).toList(),
            ),
          ),
        if (quoteIds.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: quoteIds
                .map((q) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: QuoteWidget(bech32: q, dataService: dataService),
                    ))
                .toList(),
          ),
      ],
    );
  }
}
