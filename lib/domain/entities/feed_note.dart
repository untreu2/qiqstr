class FeedNote {
  final String id;
  final String pubkey;
  final String content;
  final int createdAt;
  final List<List<String>> tags;
  final bool isRepost;
  final String? repostEventId;
  final String? repostedBy;
  final int? repostCreatedAt;
  final bool isReply;
  final String? rootId;
  final String? parentId;
  final String? authorName;
  final String? authorImage;
  final String? authorNip05;
  final int reactionCount;
  final int repostCount;
  final int replyCount;
  final int zapCount;

  const FeedNote({
    required this.id,
    required this.pubkey,
    required this.content,
    required this.createdAt,
    required this.tags,
    this.isRepost = false,
    this.repostEventId,
    this.repostedBy,
    this.repostCreatedAt,
    this.isReply = false,
    this.rootId,
    this.parentId,
    this.authorName,
    this.authorImage,
    this.authorNip05,
    this.reactionCount = 0,
    this.repostCount = 0,
    this.replyCount = 0,
    this.zapCount = 0,
  });

  factory FeedNote.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'] as List<dynamic>? ?? [];
    final tags = rawTags.map((tag) {
      if (tag is List) return tag.map((t) => t.toString()).toList();
      return <String>[];
    }).toList();

    return FeedNote(
      id: map['id'] as String? ?? '',
      pubkey: map['pubkey'] as String? ?? '',
      content: map['content'] as String? ?? '',
      createdAt: map['created_at'] as int? ?? 0,
      tags: tags,
      isRepost: map['isRepost'] as bool? ?? false,
      repostEventId: map['repostEventId'] as String?,
      repostedBy: map['repostedBy'] as String?,
      repostCreatedAt: map['repostCreatedAt'] as int?,
      isReply: map['isReply'] as bool? ?? false,
      rootId: map['rootId'] as String?,
      parentId: map['parentId'] as String?,
      authorName: map['authorName'] as String?,
      authorImage: map['authorImage'] as String?,
      authorNip05: map['authorNip05'] as String?,
      reactionCount: map['reactionCount'] as int? ?? 0,
      repostCount: map['repostCount'] as int? ?? 0,
      replyCount: map['replyCount'] as int? ?? 0,
      zapCount: map['zapCount'] as int? ?? 0,
    );
  }

  FeedNote copyWith({
    String? id,
    String? pubkey,
    String? content,
    int? createdAt,
    List<List<String>>? tags,
    bool? isRepost,
    String? repostEventId,
    String? repostedBy,
    int? repostCreatedAt,
    bool? isReply,
    String? rootId,
    String? parentId,
    String? authorName,
    String? authorImage,
    String? authorNip05,
    int? reactionCount,
    int? repostCount,
    int? replyCount,
    int? zapCount,
  }) {
    return FeedNote(
      id: id ?? this.id,
      pubkey: pubkey ?? this.pubkey,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      tags: tags ?? this.tags,
      isRepost: isRepost ?? this.isRepost,
      repostEventId: repostEventId ?? this.repostEventId,
      repostedBy: repostedBy ?? this.repostedBy,
      repostCreatedAt: repostCreatedAt ?? this.repostCreatedAt,
      isReply: isReply ?? this.isReply,
      rootId: rootId ?? this.rootId,
      parentId: parentId ?? this.parentId,
      authorName: authorName ?? this.authorName,
      authorImage: authorImage ?? this.authorImage,
      authorNip05: authorNip05 ?? this.authorNip05,
      reactionCount: reactionCount ?? this.reactionCount,
      repostCount: repostCount ?? this.repostCount,
      replyCount: replyCount ?? this.replyCount,
      zapCount: zapCount ?? this.zapCount,
    );
  }

  DateTime get createdAtDateTime {
    return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
  }

  String? getTagValue(String tagType, {int index = 1}) {
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == tagType && tag.length > index) {
        return tag[index];
      }
    }
    return null;
  }

  List<String> getTagValues(String tagType) {
    final result = <String>[];
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == tagType && tag.length > 1) {
        result.add(tag[1]);
      }
    }
    return result;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pubkey': pubkey,
      'author': pubkey,
      'content': content,
      'created_at': createdAt,
      'timestamp': createdAtDateTime,
      'tags': tags,
      'isRepost': isRepost,
      'repostEventId': repostEventId,
      'repostedBy': repostedBy,
      'repostCreatedAt': repostCreatedAt,
      'isReply': isReply,
      'rootId': rootId,
      'parentId': parentId,
      'authorName': authorName,
      'authorImage': authorImage,
      'authorNip05': authorNip05,
      'reactionCount': reactionCount,
      'repostCount': repostCount,
      'replyCount': replyCount,
      'zapCount': zapCount,
    };
  }
}
