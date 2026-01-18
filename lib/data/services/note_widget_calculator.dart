import 'dart:math' as math;
import '../../models/note_widget_metrics.dart';
import '../../utils/string_optimizer.dart';

class NoteWidgetCalculator {
  static final NoteWidgetCalculator instance = NoteWidgetCalculator._();
  NoteWidgetCalculator._();

  final Map<String, NoteWidgetMetrics> _metricsCache = {};
  static const int _maxCacheSize = 1000;

  static const double _defaultScreenWidth = 375.0;
  static const double _fontSize = 16.0;
  static const double _lineHeight = 1.2;
  static const double _charactersPerLine = 40.0;
  static const int _characterLimit = 280;
  static const double _paddingHorizontal = 24.0;
  static const double _paddingVertical = 8.0;
  static const double _avatarSize = 44.0;
  static const double _headerPadding = 8.0;
  static const double _interactionBarHeight = 32.0;
  static const double _mediaSpacing = 4.0;
  static const double _quoteHeight = 120.0;
  static const double _linkPreviewHeight = 100.0;
  static const double _miniLinkPreviewHeight = 60.0;
  static const double _videoAspectRatio = 16.0 / 9.0;
  static const double _imageAspectRatio = 4.0 / 3.0;

  NoteWidgetMetrics? getMetrics(String noteId) {
    return _metricsCache[noteId];
  }

  void cacheMetrics(NoteWidgetMetrics metrics) {
    if (_metricsCache.length >= _maxCacheSize) {
      final keysToRemove = _metricsCache.keys.take(_maxCacheSize ~/ 5).toList();
      for (final key in keysToRemove) {
        _metricsCache.remove(key);
      }
    }
    _metricsCache[metrics.noteId] = metrics;
  }

  void clearCache() {
    _metricsCache.clear();
  }

  static NoteWidgetMetrics calculateMetrics(
    Map<String, dynamic> note, {
    double screenWidth = _defaultScreenWidth,
    bool isExpandedMode = false,
  }) {
    final content = note['content'] as String? ?? '';
    final parsedContent = stringOptimizer.parseContentOptimized(content);
    final textParts = (parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final mediaUrls = (parsedContent['mediaUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    final linkUrls = (parsedContent['linkUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    final quoteIds = (parsedContent['quoteIds'] as List<dynamic>?)?.cast<String>() ?? [];

    final videoUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.mov');
    }).toList();

    final imageUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif');
    }).toList();

    final hasVideo = videoUrls.isNotEmpty;
    final hasImages = imageUrls.isNotEmpty;
    final hasMedia = mediaUrls.isNotEmpty;
    final hasLinks = linkUrls.isNotEmpty;
    final hasQuotes = quoteIds.isNotEmpty;

    final shouldTruncate = _calculateShouldTruncate(textParts);
    final truncatedContent = shouldTruncate ? _createTruncatedContent(textParts, parsedContent) : null;

    final textHeight = _calculateTextHeight(textParts, screenWidth, shouldTruncate, truncatedContent);
    final mediaHeight = _calculateMediaHeight(imageUrls, videoUrls, screenWidth);
    final quoteHeight = hasQuotes ? quoteIds.length * _quoteHeight : 0.0;
    final linkHeight = _calculateLinkHeight(linkUrls, hasMedia, screenWidth);
    final headerHeight = _calculateHeaderHeight(note, isExpandedMode);
    final interactionBarHeight = _interactionBarHeight;

    final estimatedHeight = headerHeight +
        textHeight +
        mediaHeight +
        quoteHeight +
        linkHeight +
        interactionBarHeight +
        _paddingVertical * 2;

    final mediaAspectRatio = _calculateMediaAspectRatio(imageUrls, videoUrls);

    final noteId = note['id'] as String? ?? '';
    return NoteWidgetMetrics(
      noteId: noteId,
      estimatedHeight: estimatedHeight,
      shouldTruncate: shouldTruncate,
      truncatedContent: truncatedContent,
      parsedContent: parsedContent,
      hasMedia: hasMedia,
      hasVideo: hasVideo,
      hasImages: hasImages,
      hasQuotes: hasQuotes,
      hasLinks: hasLinks,
      mediaCount: mediaUrls.length,
      imageCount: imageUrls.length,
      videoCount: videoUrls.length,
      linkCount: linkUrls.length,
      quoteCount: quoteIds.length,
      mediaAspectRatio: mediaAspectRatio,
      textHeight: textHeight,
      mediaHeight: mediaHeight,
      quoteHeight: quoteHeight,
      linkHeight: linkHeight,
      interactionBarHeight: interactionBarHeight,
      headerHeight: headerHeight,
      isExpandedMode: isExpandedMode,
    );
  }

  static bool _calculateShouldTruncate(List<Map<String, dynamic>> textParts) {
    int estimatedLength = 0;
    for (var part in textParts) {
      if (part['type'] == 'text') {
        estimatedLength += (part['text'] as String? ?? '').length;
      } else if (part['type'] == 'mention') {
        estimatedLength += 8;
      }
      if (estimatedLength > _characterLimit) {
        return true;
      }
    }
    return false;
  }

  static Map<String, dynamic> _createTruncatedContent(
    List<Map<String, dynamic>> textParts,
    Map<String, dynamic> parsedContent,
  ) {
    final truncatedParts = <Map<String, dynamic>>[];
    int currentLength = 0;

    for (var part in textParts) {
      if (part['type'] == 'text') {
        final text = part['text'] as String? ?? '';
        if (currentLength + text.length <= _characterLimit) {
          truncatedParts.add(part);
          currentLength += text.length;
        } else {
          final remainingChars = _characterLimit - currentLength;
          if (remainingChars > 0) {
            truncatedParts.add({
              'type': 'text',
              'text': '${text.substring(0, remainingChars)}... ',
            });
          }
          break;
        }
      } else if (part['type'] == 'mention') {
        if (currentLength + 8 <= _characterLimit) {
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
    });

    return {
      'textParts': truncatedParts,
      'mediaUrls': parsedContent['mediaUrls'] ?? [],
      'linkUrls': parsedContent['linkUrls'] ?? [],
      'quoteIds': parsedContent['quoteIds'] ?? [],
    };
  }

  static double _calculateTextHeight(
    List<Map<String, dynamic>> textParts,
    double screenWidth,
    bool shouldTruncate,
    Map<String, dynamic>? truncatedContent,
  ) {
    if (textParts.isEmpty) return 0.0;

    int totalCharacters = 0;
    if (shouldTruncate && truncatedContent != null) {
      final truncatedParts = (truncatedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      for (var part in truncatedParts) {
        if (part['type'] == 'text') {
          totalCharacters += (part['text'] as String? ?? '').length;
        } else if (part['type'] == 'mention') {
          totalCharacters += 8;
        }
      }
    } else {
      for (var part in textParts) {
        if (part['type'] == 'text') {
          totalCharacters += (part['text'] as String? ?? '').length;
        } else if (part['type'] == 'mention') {
          totalCharacters += 8;
        }
      }
    }

    final lines = (totalCharacters / _charactersPerLine).ceil();
    final height = lines * _fontSize * _lineHeight;

    return math.max(height, _fontSize * _lineHeight);
  }

  static double _calculateMediaHeight(
    List<String> imageUrls,
    List<String> videoUrls,
    double screenWidth,
  ) {
    if (imageUrls.isEmpty && videoUrls.isEmpty) return 0.0;

    final contentWidth = screenWidth - _paddingHorizontal * 2;
    final effectiveWidth = contentWidth;

    if (videoUrls.isNotEmpty) {
      return effectiveWidth / _videoAspectRatio;
    }

    if (imageUrls.length == 1) {
      return effectiveWidth / _imageAspectRatio;
    } else if (imageUrls.length == 2) {
      final halfWidth = (effectiveWidth - _mediaSpacing) / 2;
      return halfWidth / (3.0 / 4.0);
    } else if (imageUrls.length == 3) {
      final rightWidth = (effectiveWidth - _mediaSpacing) / 3;
      final rightHeight = rightWidth * 2 + _mediaSpacing;
      return rightHeight;
    } else {
      final gridItemSize = (effectiveWidth - _mediaSpacing) / 2;
      final rows = (imageUrls.length / 2).ceil();
      return (gridItemSize * rows) + (_mediaSpacing * (rows - 1));
    }
  }

  static double _calculateLinkHeight(
    List<String> linkUrls,
    bool hasMedia,
    double screenWidth,
  ) {
    if (linkUrls.isEmpty) return 0.0;

    if (hasMedia) {
      return linkUrls.length * _miniLinkPreviewHeight + (_mediaSpacing * (linkUrls.length - 1));
    } else {
      return linkUrls.length * _linkPreviewHeight + (_mediaSpacing * (linkUrls.length - 1));
    }
  }

  static double _calculateHeaderHeight(Map<String, dynamic> note, bool isExpandedMode) {
    double height = _headerPadding * 2;

    final isRepost = note['isRepost'] as bool? ?? false;
    final repostedBy = note['repostedBy'] as String?;
    if (isRepost && repostedBy != null && repostedBy.isNotEmpty) {
      height += 24.0;
    }

    final isReply = note['isReply'] as bool? ?? false;
    if (isReply) {
      height += 20.0;
    }

    if (isExpandedMode) {
      height += _avatarSize + 8.0;
    } else {
      height += _avatarSize;
    }

    return height;
  }

  static double? _calculateMediaAspectRatio(List<String> imageUrls, List<String> videoUrls) {
    if (videoUrls.isNotEmpty) {
      return _videoAspectRatio;
    }

    if (imageUrls.isNotEmpty) {
      if (imageUrls.length == 1) {
        return _imageAspectRatio;
      } else if (imageUrls.length == 2) {
        return 3.0 / 4.0;
      } else {
        return 1.0;
      }
    }

    return null;
  }

  static void updateNoteWithMetrics(Map<String, dynamic> note, NoteWidgetMetrics metrics) {
    note['estimatedHeight'] = metrics.estimatedHeight;
  }
}

