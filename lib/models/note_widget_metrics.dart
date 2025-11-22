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
    this.isExpandedMode = false,
  });

  NoteWidgetMetrics copyWith({
    String? noteId,
    double? estimatedHeight,
    bool? shouldTruncate,
    Map<String, dynamic>? truncatedContent,
    Map<String, dynamic>? parsedContent,
    bool? hasMedia,
    bool? hasVideo,
    bool? hasImages,
    bool? hasQuotes,
    bool? hasLinks,
    int? mediaCount,
    int? imageCount,
    int? videoCount,
    int? linkCount,
    int? quoteCount,
    double? mediaAspectRatio,
    double? textHeight,
    double? mediaHeight,
    double? quoteHeight,
    double? linkHeight,
    double? interactionBarHeight,
    double? headerHeight,
    bool? isExpandedMode,
  }) {
    return NoteWidgetMetrics(
      noteId: noteId ?? this.noteId,
      estimatedHeight: estimatedHeight ?? this.estimatedHeight,
      shouldTruncate: shouldTruncate ?? this.shouldTruncate,
      truncatedContent: truncatedContent ?? this.truncatedContent,
      parsedContent: parsedContent ?? this.parsedContent,
      hasMedia: hasMedia ?? this.hasMedia,
      hasVideo: hasVideo ?? this.hasVideo,
      hasImages: hasImages ?? this.hasImages,
      hasQuotes: hasQuotes ?? this.hasQuotes,
      hasLinks: hasLinks ?? this.hasLinks,
      mediaCount: mediaCount ?? this.mediaCount,
      imageCount: imageCount ?? this.imageCount,
      videoCount: videoCount ?? this.videoCount,
      linkCount: linkCount ?? this.linkCount,
      quoteCount: quoteCount ?? this.quoteCount,
      mediaAspectRatio: mediaAspectRatio ?? this.mediaAspectRatio,
      textHeight: textHeight ?? this.textHeight,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      quoteHeight: quoteHeight ?? this.quoteHeight,
      linkHeight: linkHeight ?? this.linkHeight,
      interactionBarHeight: interactionBarHeight ?? this.interactionBarHeight,
      headerHeight: headerHeight ?? this.headerHeight,
      isExpandedMode: isExpandedMode ?? this.isExpandedMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'noteId': noteId,
      'estimatedHeight': estimatedHeight,
      'shouldTruncate': shouldTruncate,
      'truncatedContent': truncatedContent,
      'hasMedia': hasMedia,
      'hasVideo': hasVideo,
      'hasImages': hasImages,
      'hasQuotes': hasQuotes,
      'hasLinks': hasLinks,
      'mediaCount': mediaCount,
      'imageCount': imageCount,
      'videoCount': videoCount,
      'linkCount': linkCount,
      'quoteCount': quoteCount,
      'mediaAspectRatio': mediaAspectRatio,
      'textHeight': textHeight,
      'mediaHeight': mediaHeight,
      'quoteHeight': quoteHeight,
      'linkHeight': linkHeight,
      'interactionBarHeight': interactionBarHeight,
      'headerHeight': headerHeight,
      'isExpandedMode': isExpandedMode,
    };
  }

  factory NoteWidgetMetrics.fromJson(Map<String, dynamic> json) {
    return NoteWidgetMetrics(
      noteId: json['noteId'] as String,
      estimatedHeight: (json['estimatedHeight'] as num).toDouble(),
      shouldTruncate: json['shouldTruncate'] as bool,
      truncatedContent: json['truncatedContent'] as Map<String, dynamic>?,
      parsedContent: json['parsedContent'] as Map<String, dynamic>,
      hasMedia: json['hasMedia'] as bool,
      hasVideo: json['hasVideo'] as bool,
      hasImages: json['hasImages'] as bool,
      hasQuotes: json['hasQuotes'] as bool,
      hasLinks: json['hasLinks'] as bool,
      mediaCount: json['mediaCount'] as int,
      imageCount: json['imageCount'] as int,
      videoCount: json['videoCount'] as int,
      linkCount: json['linkCount'] as int,
      quoteCount: json['quoteCount'] as int,
      mediaAspectRatio: (json['mediaAspectRatio'] as num?)?.toDouble(),
      textHeight: (json['textHeight'] as num).toDouble(),
      mediaHeight: (json['mediaHeight'] as num).toDouble(),
      quoteHeight: (json['quoteHeight'] as num).toDouble(),
      linkHeight: (json['linkHeight'] as num).toDouble(),
      interactionBarHeight: (json['interactionBarHeight'] as num).toDouble(),
      headerHeight: (json['headerHeight'] as num).toDouble(),
      isExpandedMode: json['isExpandedMode'] as bool? ?? false,
    );
  }
}

