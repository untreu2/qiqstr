import 'package:hive/hive.dart';

part 'reaction_model.g.dart';

@HiveType(typeId: 1)
class ReactionModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String author;

  @HiveField(2)
  final String content;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final String authorName;

  @HiveField(5)
  final String authorProfileImage;

  ReactionModel({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
    required this.authorName,
    required this.authorProfileImage,
  });

  factory ReactionModel.fromEvent(Map<String, dynamic> eventData, Map<String, String> profile) {
    return ReactionModel(
      id: eventData['id'] as String,
      author: eventData['pubkey'] as String,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000),
      authorName: profile['name'] ?? 'Anonymous',
      authorProfileImage: profile['profileImage'] ?? '',
    );
  }

  factory ReactionModel.fromJson(Map<String, dynamic> json) {
    return ReactionModel(
      id: json['id'],
      author: json['author'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      authorName: json['authorName'],
      authorProfileImage: json['authorProfileImage'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author': author,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
    };
  }
}
