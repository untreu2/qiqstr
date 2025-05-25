import 'package:hive/hive.dart';

part 'notification_model.g.dart';

@HiveType(typeId: 12)
class NotificationModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String targetEventId;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final String type;

  @HiveField(4)
  final String content;

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  final DateTime fetchedAt;

  NotificationModel({
    required this.id,
    required this.targetEventId,
    required this.author,
    required this.type,
    required this.content,
    required this.timestamp,
    required this.fetchedAt,
  });

  factory NotificationModel.fromEvent(Map<String, dynamic> eventData, String type) {
    String? targetEventId;
    for (var tag in eventData['tags']) {
      if (tag.length >= 2 && tag[0] == 'e') {
        targetEventId = tag[1] as String;
        break;
      }
    }
    if (targetEventId == null) {
      throw Exception('targetEventId not found for $type.');
    }

    return NotificationModel(
      id: eventData['id'] as String,
      targetEventId: targetEventId,
      author: eventData['pubkey'] as String,
      type: type,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000),
      fetchedAt: DateTime.now(),
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'],
      targetEventId: json['targetEventId'],
      author: json['author'],
      type: json['type'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      fetchedAt: DateTime.parse(json['fetchedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'targetEventId': targetEventId,
      'author': author,
      'type': type,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }
}
