import 'package:hive/hive.dart';

part 'reply_model.g.dart';

@HiveType(typeId: 2)
class ReplyModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String author;

  @HiveField(2)
  final String content;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final String parentEventId;

  @HiveField(5)
  final DateTime fetchedAt;

  @HiveField(6)
  final String rootEventId;

  @HiveField(7)
  int depth;

  @HiveField(8)
  int reactionCount;

  @HiveField(9)
  int replyCount;

  @HiveField(10)
  int repostCount;

  ReplyModel({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
    required this.parentEventId,
    required this.fetchedAt,
    required this.rootEventId,
    required this.depth,
    this.reactionCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
  });

  factory ReplyModel.fromEvent(Map<String, dynamic> eventData) {
    String? parentId;
    String? rootId;

    final tags = eventData['tags'] as List<dynamic>;

    for (var tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
        if (tag.length >= 4 && tag[3] == 'root') {
          rootId = tag[1] as String;
        } else {
          parentId ??= tag[1] as String;
        }
      }
    }

    if (parentId == null) {
      throw Exception('parentEventId not found in event tags.');
    }

    rootId ??= parentId;

    int depth = (rootId == parentId) ? 1 : 0;

    return ReplyModel(
      id: eventData['id'],
      author: eventData['pubkey'],
      content: eventData['content'],
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000),
      parentEventId: parentId,
      rootEventId: rootId,
      depth: depth,
      fetchedAt: DateTime.now(),
    );
  }

  factory ReplyModel.fromJson(Map<String, dynamic> json) {
    return ReplyModel(
      id: json['id'],
      author: json['author'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      parentEventId: json['parentEventId'],
      fetchedAt: DateTime.parse(json['fetchedAt']),
      rootEventId: json['rootEventId'],
      depth: json['depth'],
      reactionCount: json['reactionCount'] ?? 0,
      replyCount: json['replyCount'] ?? 0,
      repostCount: json['repostCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author': author,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'parentEventId': parentEventId,
      'fetchedAt': fetchedAt.toIso8601String(),
      'rootEventId': rootEventId,
      'depth': depth,
      'reactionCount': reactionCount,
      'replyCount': replyCount,
      'repostCount': repostCount,
    };
  }
}
