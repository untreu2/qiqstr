import 'package:hive/hive.dart';

part 'note_model.g.dart';

@HiveType(typeId: 0)
class NoteModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final bool isRepost;

  @HiveField(5)
  final String? repostedBy;

  @HiveField(6)
  final DateTime? repostTimestamp;

  @HiveField(7)
  int repostCount;

  @HiveField(8)
  final String? rawWs;

  @HiveField(9)
  int reactionCount;

  @HiveField(10)
  int replyCount;

  @HiveField(11)
  Map<String, dynamic>? parsedContent;

  @HiveField(12)
  bool hasMedia;

  @HiveField(13)
  double? estimatedHeight;

  @HiveField(14)
  bool isVideo;

  @HiveField(15)
  String? videoUrl;

  @HiveField(16)
  int zapAmount;

  @HiveField(17)
  final bool isReply;

  @HiveField(18)
  final String? parentId;

  @HiveField(19)
  final String? rootId;

  @HiveField(20)
  List<String> replyIds;

  // This field stores the parsed content in memory only, not in Hive
  // Fields without @HiveField annotations are automatically ignored by Hive
  Map<String, dynamic>? _parsedContentCache;

  NoteModel({
    required this.id,
    required this.content,
    required this.author,
    required this.timestamp,
    this.isRepost = false,
    this.repostedBy,
    this.repostTimestamp,
    this.repostCount = 0,
    this.rawWs,
    this.reactionCount = 0,
    this.replyCount = 0,
    this.parsedContent,
    this.hasMedia = false,
    this.estimatedHeight,
    this.isVideo = false,
    this.videoUrl,
    this.zapAmount = 0,
    this.isReply = false,
    this.parentId,
    this.rootId,
    List<String>? replyIds,
  }) : replyIds = replyIds ?? [];

  // Lazy parsing getter - parses content only when first accessed
  Map<String, dynamic> get parsedContentLazy {
    // If _parsedContentCache is null, parse the content and cache it
    _parsedContentCache ??= _parseInternal();
    return _parsedContentCache!;
  }

  // Helper getter for checking if note has media using lazy parsing
  bool get hasMediaLazy => (parsedContentLazy['mediaUrls'] as List).isNotEmpty;

  // Internal parsing method - moved from DataService.parseContent
  Map<String, dynamic> _parseInternal() {
    final RegExp mediaRegExp = RegExp(
      r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4|mov))',
      caseSensitive: false,
    );
    final mediaMatches = mediaRegExp.allMatches(content);
    final List<String> mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();

    final RegExp linkRegExp = RegExp(r'(https?:\/\/\S+)', caseSensitive: false);
    final linkMatches = linkRegExp.allMatches(content);
    final List<String> linkUrls = linkMatches
        .map((m) => m.group(0)!)
        .where((u) => !mediaUrls.contains(u) && !u.toLowerCase().endsWith('.mp4') && !u.toLowerCase().endsWith('.mov'))
        .toList();

    final RegExp quoteRegExp = RegExp(
      r'(?:nostr:)?(note1[0-9a-z]+|nevent1[0-9a-z]+)',
      caseSensitive: false,
    );
    final quoteMatches = quoteRegExp.allMatches(content);
    final List<String> quoteIds = quoteMatches.map((m) => m.group(1)!).toList();

    String cleanedText = content;
    for (final m in [...mediaMatches, ...quoteMatches]) {
      cleanedText = cleanedText.replaceFirst(m.group(0)!, '');
    }
    cleanedText = cleanedText.trim();

    final RegExp mentionRegExp = RegExp(
      r'nostr:(npub1[0-9a-z]+|nprofile1[0-9a-z]+)',
      caseSensitive: false,
    );
    final mentionMatches = mentionRegExp.allMatches(cleanedText);

    final List<Map<String, dynamic>> textParts = [];
    int lastEnd = 0;
    for (final m in mentionMatches) {
      if (m.start > lastEnd) {
        textParts.add({
          'type': 'text',
          'text': cleanedText.substring(lastEnd, m.start),
        });
      }

      final id = m.group(1)!;
      textParts.add({'type': 'mention', 'id': id});
      lastEnd = m.end;
    }

    if (lastEnd < cleanedText.length) {
      textParts.add({
        'type': 'text',
        'text': cleanedText.substring(lastEnd),
      });
    }

    return {
      'mediaUrls': mediaUrls,
      'linkUrls': linkUrls,
      'quoteIds': quoteIds,
      'textParts': textParts,
    };
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is NoteModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
      content: json['content'] as String,
      author: json['author'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as int) * 1000,
      ),
      isRepost: json['isRepost'] as bool? ?? false,
      repostedBy: json['repostedBy'] as String?,
      repostTimestamp: json['repostTimestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['repostTimestamp'] as int) * 1000,
            )
          : null,
      repostCount: json['repostCount'] as int? ?? 0,
      rawWs: json['rawWs'] as String?,
      reactionCount: json['reactionCount'] as int? ?? 0,
      replyCount: json['replyCount'] as int? ?? 0,
      parsedContent: json['parsedContent'] != null ? Map<String, dynamic>.from(json['parsedContent']) : null,
      hasMedia: json['hasMedia'] as bool? ?? false,
      estimatedHeight: (json['estimatedHeight'] as num?)?.toDouble(),
      isVideo: json['isVideo'] as bool? ?? false,
      videoUrl: json['videoUrl'] as String?,
      zapAmount: json['zapAmount'] as int? ?? 0,
      isReply: json['isReply'] as bool? ?? false,
      parentId: json['parentId'] as String?,
      rootId: json['rootId'] as String?,
      replyIds: json['replyIds'] != null ? List<String>.from(json['replyIds']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'author': author,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'isRepost': isRepost,
      'repostedBy': repostedBy,
      'repostTimestamp': repostTimestamp!.millisecondsSinceEpoch ~/ 1000,
      'repostCount': repostCount,
      'rawWs': rawWs,
      'reactionCount': reactionCount,
      'replyCount': replyCount,
      'parsedContent': parsedContent,
      'hasMedia': hasMedia,
      'estimatedHeight': estimatedHeight,
      'isVideo': isVideo,
      'videoUrl': videoUrl,
      'zapAmount': zapAmount,
      'isReply': isReply,
      'parentId': parentId,
      'rootId': rootId,
      'replyIds': replyIds,
    };
  }
}
