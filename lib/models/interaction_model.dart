import 'package:hive/hive.dart';

part 'interaction_model.g.dart';

@HiveType(typeId: 1)
class InteractionModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final int kind;

  @HiveField(2)
  final String targetNoteId;

  @HiveField(3)
  final String author;

  @HiveField(4)
  final String content;

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  final DateTime fetchedAt;

  InteractionModel({
    required this.id,
    required this.kind,
    required this.targetNoteId,
    required this.author,
    required this.content,
    required this.timestamp,
    required this.fetchedAt,
  });

  factory InteractionModel.fromEvent(Map<String, dynamic> eventData) {
    final int kind = eventData['kind'] as int;
    String? targetNoteId;
    for (var tag in eventData['tags']) {
      if (tag is List && tag.length >= 2 && tag[0] == 'e') {
        targetNoteId = tag[1] as String;
        break;
      }
    }
    if (targetNoteId == null) {
      throw Exception('targetNoteId not found for interaction.');
    }
    return InteractionModel(
      id: eventData['id'] as String,
      kind: kind,
      targetNoteId: targetNoteId,
      author: eventData['pubkey'] as String,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (eventData['created_at'] as int) * 1000),
      fetchedAt: DateTime.now(),
    );
  }

  factory InteractionModel.fromJson(Map<String, dynamic> json) {
    return InteractionModel(
      id: json['id'],
      kind: json['kind'],
      targetNoteId: json['targetNoteId'],
      author: json['author'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      fetchedAt: DateTime.parse(json['fetchedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'targetNoteId': targetNoteId,
      'author': author,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }
}
