import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import 'package:qiqstr/widgets/quote_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/theme_manager.dart';

enum NoteContentType { small, big }

class NoteContentWidget extends StatefulWidget {
  final Map<String, dynamic> parsedContent;
  final DataService dataService;
  final void Function(String mentionId) onNavigateToMentionProfile;
  final void Function(String noteId)? onShowMoreTap;
  final NoteContentType type;

  const NoteContentWidget({
    super.key,
    required this.parsedContent,
    required this.dataService,
    required this.onNavigateToMentionProfile,
    this.onShowMoreTap,
    this.type = NoteContentType.small,
  });

  @override
  State<NoteContentWidget> createState() => _NoteContentWidgetState();
}

class _NoteContentWidgetState extends State<NoteContentWidget> {
  late final Future<Map<String, String>> _mentionsFuture;

  @override
  void initState() {
    super.initState();
    _mentionsFuture = _resolveMentions();
  }

  @override
  void didUpdateWidget(NoteContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const DeepCollectionEquality().equals(widget.parsedContent, oldWidget.parsedContent)) {
      setState(() {
        _mentionsFuture = _resolveMentions();
      });
    }
  }

  Future<Map<String, String>> _resolveMentions() {
    final mentionIds = (widget.parsedContent['textParts'] as List<dynamic>? ?? [])
        .where((p) => p['type'] == 'mention')
        .map((p) => p['id'] as String)
        .toList();
    return widget.dataService.resolveMentions(mentionIds);
  }

  double get _fontSize {
    switch (widget.type) {
      case NoteContentType.small:
        return 16.0;
      case NoteContentType.big:
        return 18.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textParts = (widget.parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final mediaUrls = (widget.parsedContent['mediaUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    final linkUrls = (widget.parsedContent['linkUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    final quoteIds = (widget.parsedContent['quoteIds'] as List<dynamic>?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (textParts.isNotEmpty)
          FutureBuilder<Map<String, String>>(
            future: _mentionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }
              final mentionsMap = snapshot.data ?? {};
              return _RichTextContent(
                parsedContent: widget.parsedContent,
                mentions: mentionsMap,
                fontSize: _fontSize,
                onNavigateToMentionProfile: widget.onNavigateToMentionProfile,
                onShowMoreTap: widget.onShowMoreTap,
              );
            },
          ),
        if (mediaUrls.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MediaPreviewWidget(mediaUrls: mediaUrls),
          ),
        if (linkUrls.isNotEmpty && mediaUrls.isEmpty)
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
                      child: QuoteWidget(bech32: q, dataService: widget.dataService),
                    ))
                .toList(),
          ),
      ],
    );
  }
}

class _RichTextContent extends StatefulWidget {
  final Map<String, dynamic> parsedContent;
  final Map<String, String> mentions;
  final double fontSize;
  final void Function(String mentionId) onNavigateToMentionProfile;
  final void Function(String noteId)? onShowMoreTap;

  const _RichTextContent({
    required this.parsedContent,
    required this.mentions,
    required this.fontSize,
    required this.onNavigateToMentionProfile,
    this.onShowMoreTap,
  });

  @override
  State<_RichTextContent> createState() => _RichTextContentState();
}

class _RichTextContentState extends State<_RichTextContent> {
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

  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _spans = [];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spans = _buildSpans();
  }

  @override
  void didUpdateWidget(_RichTextContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const DeepCollectionEquality().equals(widget.parsedContent, oldWidget.parsedContent) ||
        !const DeepCollectionEquality().equals(widget.mentions, oldWidget.mentions) ||
        widget.fontSize != oldWidget.fontSize) {
      _spans = _buildSpans();
    }
  }

  List<InlineSpan> _buildSpans() {
    final parts = (widget.parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final spans = <InlineSpan>[];
    final currentFontSize = widget.fontSize * textScaleFactor;
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
        final displayName = widget.mentions[p['id']] ?? '${(p['id'] as String).substring(0, 8)}...';
        spans.add(TextSpan(
          text: '@$displayName',
          style: TextStyle(color: colors.accent, fontSize: currentFontSize, fontWeight: FontWeight.w500),
          recognizer: TapGestureRecognizer()..onTap = () => widget.onNavigateToMentionProfile(p['id'] as String),
        ));
      } else if (p['type'] == 'show_more') {
        spans.add(TextSpan(
          text: p['text'] as String,
          style: TextStyle(
            color: colors.accent,
            fontSize: currentFontSize,
            fontWeight: FontWeight.w500,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => widget.onShowMoreTap?.call(p['noteId'] as String),
        ));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(children: _spans),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
  }
}
