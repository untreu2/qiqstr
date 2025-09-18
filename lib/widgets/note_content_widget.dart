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

enum NoteContentSize { small, big }

class NoteContentWidget extends StatefulWidget {
  final Map<String, dynamic> parsedContent;
  final DataService dataService;
  final void Function(String mentionId) onNavigateToMentionProfile;
  final void Function(String noteId)? onShowMoreTap;
  final NoteContentSize size;

  const NoteContentWidget({
    super.key,
    required this.parsedContent,
    required this.dataService,
    required this.onNavigateToMentionProfile,
    this.onShowMoreTap,
    this.size = NoteContentSize.small,
  });

  @override
  State<NoteContentWidget> createState() => _NoteContentWidgetState();
}

class _NoteContentWidgetState extends State<NoteContentWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Future<Map<String, String>> _mentionsFuture;
  late final List<dynamic> _textParts;
  late final List<String> _mediaUrls;
  late final List<String> _linkUrls;
  late final List<String> _quoteIds;

  @override
  void initState() {
    super.initState();
    _processParsedContent();
    _mentionsFuture = _resolveMentions();
  }

  void _processParsedContent() {
    _textParts = (widget.parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    _mediaUrls = (widget.parsedContent['mediaUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    _linkUrls = (widget.parsedContent['linkUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    _quoteIds = (widget.parsedContent['quoteIds'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  @override
  void didUpdateWidget(NoteContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const DeepCollectionEquality().equals(widget.parsedContent, oldWidget.parsedContent)) {
      _processParsedContent();
      setState(() {
        _mentionsFuture = _resolveMentions();
      });
    }
  }

  Future<Map<String, String>> _resolveMentions() {
    final mentionIds = _textParts.where((p) => p['type'] == 'mention').map((p) => p['id'] as String).toList();
    return widget.dataService.resolveMentions(mentionIds);
  }

  double get _fontSize => widget.size == NoteContentSize.big ? 18.0 : 16.0;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_textParts.isNotEmpty)
            RepaintBoundary(
              child: FutureBuilder<Map<String, String>>(
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
            ),
          if (_mediaUrls.isNotEmpty)
            RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MediaPreviewWidget(mediaUrls: _mediaUrls),
              ),
            ),
          if (_linkUrls.isNotEmpty && _mediaUrls.isEmpty)
            RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _linkUrls.map((u) => LinkPreviewWidget(url: u)).toList(),
                ),
              ),
            ),
          if (_quoteIds.isNotEmpty)
            RepaintBoundary(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _quoteIds
                    .map((q) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: QuoteWidget(bech32: q, dataService: widget.dataService),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
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

class _RichTextContentState extends State<_RichTextContent> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static final _globalTextScaleFactor = WidgetsBinding.instance.platformDispatcher.textScaleFactor;
  static final Map<String, TextStyle> _textStyleCache = <String, TextStyle>{};
  static final Map<String, TapGestureRecognizer> _recognizerCache = <String, TapGestureRecognizer>{};

  late double _currentFontSize;
  late List<InlineSpan> _spans;
  late Map<String, dynamic> _cachedContent;
  late Map<String, String> _cachedMentions;
  @override
  void initState() {
    super.initState();
    _currentFontSize = widget.fontSize * _globalTextScaleFactor;
    _cachedContent = Map.from(widget.parsedContent);
    _cachedMentions = Map.from(widget.mentions);
    _spans = _buildSpans();
  }

  @override
  void didUpdateWidget(_RichTextContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const DeepCollectionEquality().equals(widget.parsedContent, _cachedContent) ||
        !const DeepCollectionEquality().equals(widget.mentions, _cachedMentions) ||
        widget.fontSize != oldWidget.fontSize) {
      _currentFontSize = widget.fontSize * _globalTextScaleFactor;
      _cachedContent.clear();
      _cachedContent.addAll(widget.parsedContent);
      _cachedMentions.clear();
      _cachedMentions.addAll(widget.mentions);
      _spans = _buildSpans();
    }
  }

  TextStyle _getCachedTextStyle(String key, Color color, {FontWeight? fontWeight}) {
    final cacheKey = '$key-$color-$fontWeight-$_currentFontSize';
    return _textStyleCache.putIfAbsent(
        cacheKey,
        () => TextStyle(
              fontSize: _currentFontSize,
              color: color,
              fontWeight: fontWeight,
            ));
  }

  TapGestureRecognizer _getCachedRecognizer(String key, VoidCallback onTap) {
    return _recognizerCache.putIfAbsent(key, () => TapGestureRecognizer()..onTap = onTap);
  }

  Future<void> _onOpenLink(LinkableElement link) async {
    final url = Uri.parse(link.url);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch ${link.url}')),
        );
      }
    }
  }

  void _onHashtagTap(String hashtag) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Designing: Hashtags for $hashtag')),
    );
  }

  List<InlineSpan> _buildSpans() {
    final parts = (_cachedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final spans = <InlineSpan>[];
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
              style: _getCachedTextStyle('text', colors.textPrimary),
            ));
          }

          final urlMatch = m.group(1);
          final hashtagMatch = m.group(2);

          if (urlMatch != null) {
            spans.add(TextSpan(
              text: urlMatch,
              style: _getCachedTextStyle('url', colors.accent),
              recognizer: _getCachedRecognizer('url_$urlMatch', () => _onOpenLink(LinkableElement(urlMatch, urlMatch))),
            ));
          } else if (hashtagMatch != null) {
            spans.add(TextSpan(
              text: hashtagMatch,
              style: _getCachedTextStyle('hashtag', colors.accent),
              recognizer: _getCachedRecognizer('hashtag_$hashtagMatch', () => _onHashtagTap(hashtagMatch)),
            ));
          }
          last = m.end;
        }

        if (last < text.length) {
          spans.add(TextSpan(
            text: text.substring(last),
            style: _getCachedTextStyle('text', colors.textPrimary),
          ));
        }
      } else if (p['type'] == 'mention') {
        final id = p['id'] as String;
        final displayName = _cachedMentions[id] ?? '${id.substring(0, 8)}...';
        spans.add(TextSpan(
          text: '@$displayName',
          style: _getCachedTextStyle('mention', colors.accent, fontWeight: FontWeight.w500),
          recognizer: _getCachedRecognizer('mention_$id', () => widget.onNavigateToMentionProfile(id)),
        ));
      } else if (p['type'] == 'show_more') {
        final noteId = p['noteId'] as String;
        spans.add(TextSpan(
          text: p['text'] as String,
          style: _getCachedTextStyle('show_more', colors.accent, fontWeight: FontWeight.w500),
          recognizer: _getCachedRecognizer('show_more_$noteId', () => widget.onShowMoreTap?.call(noteId)),
        ));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RepaintBoundary(
      child: RichText(
        text: TextSpan(children: _spans),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      ),
    );
  }
}
