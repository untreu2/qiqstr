import 'package:hive/hive.dart';

part 'reaction_model.g.dart';

@HiveType(typeId: 1)
class ReactionModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String noteId;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final String content;

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  final String authorName;

  @HiveField(6)
  final String authorProfileImage;

  @HiveField(7)
  final DateTime fetchedAt;

  ReactionModel({
    required this.id,
    required this.noteId,
    required this.author,
    required this.content,
    required this.timestamp,
    required this.authorName,
    required this.authorProfileImage,
    required this.fetchedAt,
  });

  factory ReactionModel.fromEvent(Map<String, dynamic> eventData, Map<String, String> profile) {
    String? noteId;
    for (var tag in eventData['tags']) {
      if (tag.length >= 2 && tag[0] == 'e') {
        noteId = tag[1] as String;
        break;
      }
    }

    if (noteId == null) {
      throw Exception('NoteId not found for reaction.');
    }

    return ReactionModel(
      id: eventData['id'] as String,
      noteId: noteId,
      author: eventData['pubkey'] as String,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000),
      authorName: profile['name'] ?? 'Anonymous',
      authorProfileImage: profile['profileImage'] ?? '',
      fetchedAt: DateTime.now(),
    );
  }

  factory ReactionModel.fromJson(Map<String, dynamic> json) {
    return ReactionModel(
      id: json['id'],
      noteId: json['noteId'],
      author: json['author'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      authorName: json['authorName'],
      authorProfileImage: json['authorProfileImage'],
      fetchedAt: DateTime.parse(json['fetchedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'author': author,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }
}
