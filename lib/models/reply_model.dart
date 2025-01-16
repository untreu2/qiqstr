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
  final String authorName;

  @HiveField(6)
  final String authorProfileImage;

  @HiveField(7)
  final DateTime fetchedAt;

  ReplyModel({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
    required this.parentEventId,
    required this.authorName,
    required this.authorProfileImage,
    required this.fetchedAt,
  });

  factory ReplyModel.fromEvent(Map<String, dynamic> eventData, Map<String, String> profile) {
    String? parentEventId;
    for (var tag in eventData['tags']) {
      if (tag.length >= 2 && tag[0] == 'e') {
        parentEventId = tag[1] as String;
        break;
      }
    }

    if (parentEventId == null || parentEventId.isEmpty) {
      throw Exception('parentEventId not found for reply.');
    }

    return ReplyModel(
      id: eventData['id'] as String,
      author: eventData['pubkey'] as String,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (eventData['created_at'] as int) * 1000,
      ),
      parentEventId: parentEventId,
      authorName: profile['name'] ?? 'Anonymous',
      authorProfileImage: profile['profileImage'] ?? '',
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
      authorName: json['authorName'],
      authorProfileImage: json['authorProfileImage'],
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
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }
}
