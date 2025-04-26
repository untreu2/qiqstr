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
  final String? rootEventId;

  @HiveField(6)
  final DateTime fetchedAt;

  ReplyModel({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
    required this.parentEventId,
    this.rootEventId,
    required this.fetchedAt,
  });

  factory ReplyModel.fromEvent(Map<String, dynamic> eventData) {
    final tags = eventData['tags'] as List<dynamic>;

    final ids = _extractRootAndParentIds(tags);
    final parentId = ids['parent'] ?? ids['root'];
    final rootId = ids['root'];

    if (parentId == null || parentId.isEmpty) {
      throw Exception('parentEventId not found for reply.');
    }

    return ReplyModel(
      id: eventData['id'] as String,
      author: eventData['pubkey'] as String,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (eventData['created_at'] as int) * 1000,
      ),
      parentEventId: parentId,
      rootEventId: rootId,
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
      rootEventId: json['rootEventId'],
      fetchedAt: DateTime.parse(json['fetchedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author': author,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'parentEventId': parentEventId,
      'rootEventId': rootEventId,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }

  static Map<String, String?> _extractRootAndParentIds(List<dynamic> tags) {
    String? rootId;
    String? parentId;

    for (var tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
        if (tag.length > 3 && tag[3] == 'root') {
          rootId = tag[1] as String;
        } else if (tag.length > 3 && tag[3] == 'reply') {
          parentId = tag[1] as String;
        } else if (tag.length > 2 && (tag[2] == 'root' || tag[2] == 'reply')) {
          if (tag[2] == 'root') rootId = tag[1] as String;
          if (tag[2] == 'reply') parentId = tag[1] as String;
        } else if (parentId == null) {
          parentId = tag[1] as String;
        }
      }
    }

    return {
      'root': rootId,
      'parent': parentId,
    };
  }
}
