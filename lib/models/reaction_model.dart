import 'package:hive/hive.dart';

part 'reaction_model.g.dart';

@HiveType(typeId: 1)
class ReactionModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String targetEventId;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final String content;

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  final DateTime fetchedAt;

  ReactionModel({
    required this.id,
    required this.targetEventId,
    required this.author,
    required this.content,
    required this.timestamp,
    required this.fetchedAt,
  });

  factory ReactionModel.fromEvent(Map<String, dynamic> eventData) {
    String? targetEventId;
    for (var tag in eventData['tags']) {
      if (tag.length >= 2 && tag[0] == 'e') {
        targetEventId = tag[1] as String;
        break;
      }
    }
    if (targetEventId == null) {
      throw Exception('targetEventId not found for reaction.');
    }
    return ReactionModel(
      id: eventData['id'] as String,
      targetEventId: targetEventId,
      author: eventData['pubkey'] as String,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000),
      fetchedAt: DateTime.now(),
    );
  }

  factory ReactionModel.fromJson(Map<String, dynamic> json) {
    return ReactionModel(
      id: json['id'],
      targetEventId: json['targetEventId'],
      author: json['author'],
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
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }
}
