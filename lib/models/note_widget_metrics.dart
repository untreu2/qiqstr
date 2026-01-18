class NoteWidgetMetrics {
  final String noteId;
  final double estimatedHeight;
  final bool shouldTruncate;
  final Map<String, dynamic>? truncatedContent;
  final Map<String, dynamic> parsedContent;
  final bool hasMedia;
  final bool hasVideo;
  final bool hasImages;
  final bool hasQuotes;
  final bool hasLinks;
  final int mediaCount;
  final int imageCount;
  final int videoCount;
  final int linkCount;
  final int quoteCount;
  final double? mediaAspectRatio;
  final double textHeight;
  final double mediaHeight;
  final double quoteHeight;
  final double linkHeight;
  final double interactionBarHeight;
  final double headerHeight;
  final bool isExpandedMode;

  NoteWidgetMetrics({
    required this.noteId,
    required this.estimatedHeight,
    required this.shouldTruncate,
    this.truncatedContent,
    required this.parsedContent,
    required this.hasMedia,
    required this.hasVideo,
    required this.hasImages,
    required this.hasQuotes,
    required this.hasLinks,
    required this.mediaCount,
    required this.imageCount,
    required this.videoCount,
    required this.linkCount,
    required this.quoteCount,
    this.mediaAspectRatio,
    required this.textHeight,
    required this.mediaHeight,
    required this.quoteHeight,
    required this.linkHeight,
    required this.interactionBarHeight,
    required this.headerHeight,
    required this.isExpandedMode,
  });
}
