import '../utils/string_optimizer.dart';

class NoteModel {
  final String id;
  final String content;
  final String author;
  final DateTime timestamp;
  final bool isRepost;
  final String? repostedBy;
  final DateTime? repostTimestamp;
  int repostCount;
  final String? rawWs;
  int reactionCount;
  int replyCount;
  bool hasMedia;
  double? estimatedHeight;
  bool isVideo;
  String? videoUrl;
  int zapAmount;
  final bool isReply;
  final String? parentId;
  final String? rootId;
  List<String> replyIds;
  List<Map<String, String>> eTags;
  List<Map<String, String>> pTags;
  String? replyMarker;

  static final Map<String, Map<String, dynamic>> _globalParseCache = {};
  static const int _maxCacheSize = 500;

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
    this.hasMedia = false,
    this.estimatedHeight,
    this.isVideo = false,
    this.videoUrl,
    this.zapAmount = 0,
    this.isReply = false,
    this.parentId,
    this.rootId,
    List<String>? replyIds,
    List<Map<String, String>>? eTags,
    List<Map<String, String>>? pTags,
    this.replyMarker,
  })  : replyIds = replyIds ?? [],
        eTags = eTags ?? [],
        pTags = pTags ?? [];

  Map<String, dynamic> get parsedContentLazy {
    if (_globalParseCache.containsKey(id)) {
      return _globalParseCache[id]!;
    }

    final parsed = _parseInternal();

    if (_globalParseCache.length >= _maxCacheSize) {
      final keysToRemove = _globalParseCache.keys.take(_maxCacheSize ~/ 5).toList();
      for (final key in keysToRemove) {
        _globalParseCache.remove(key);
      }
    }

    _globalParseCache[id] = parsed;
    return parsed;
  }

  static void clearParseCache() {
    _globalParseCache.clear();
  }

  bool get hasMediaLazy => (parsedContentLazy['mediaUrls'] as List).isNotEmpty;

  Map<String, dynamic> _parseInternal() {
    return stringOptimizer.parseContentOptimized(content);
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
      hasMedia: json['hasMedia'] as bool? ?? false,
      estimatedHeight: (json['estimatedHeight'] as num?)?.toDouble(),
      isVideo: json['isVideo'] as bool? ?? false,
      videoUrl: json['videoUrl'] as String?,
      zapAmount: json['zapAmount'] as int? ?? 0,
      isReply: json['isReply'] as bool? ?? false,
      parentId: json['parentId'] as String?,
      rootId: json['rootId'] as String?,
      replyIds: json['replyIds'] != null ? List<String>.from(json['replyIds']) : null,
      eTags: json['eTags'] != null ? List<Map<String, String>>.from(json['eTags'].map((tag) => Map<String, String>.from(tag))) : null,
      pTags: json['pTags'] != null ? List<Map<String, String>>.from(json['pTags'].map((tag) => Map<String, String>.from(tag))) : null,
      replyMarker: json['replyMarker'] as String?,
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
      'repostTimestamp': repostTimestamp?.millisecondsSinceEpoch == null ? null : repostTimestamp!.millisecondsSinceEpoch ~/ 1000,
      'repostCount': repostCount,
      'rawWs': rawWs,
      'reactionCount': reactionCount,
      'replyCount': replyCount,
      'hasMedia': hasMedia,
      'estimatedHeight': estimatedHeight,
      'isVideo': isVideo,
      'videoUrl': videoUrl,
      'zapAmount': zapAmount,
      'isReply': isReply,
      'parentId': parentId,
      'rootId': rootId,
      'replyIds': replyIds,
      'eTags': eTags,
      'pTags': pTags,
      'replyMarker': replyMarker,
    };
  }
}
