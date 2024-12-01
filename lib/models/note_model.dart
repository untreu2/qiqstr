import 'package:hive/hive.dart';

part 'note_model.g.dart';

@HiveType(typeId: 0)
class NoteModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final String author;

  @HiveField(3)
  final String authorName;

  @HiveField(4)
  final String authorProfileImage;

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  final bool isRepost;

  @HiveField(7)
  final String? repostedBy;

  @HiveField(8)
  final String? repostedByName;

  @HiveField(9)
  final String? repostedByProfileImage;

  NoteModel({
    required this.id,
    required this.content,
    required this.author,
    required this.authorName,
    required this.authorProfileImage,
    required this.timestamp,
    this.isRepost = false,
    this.repostedBy,
    this.repostedByName,
    this.repostedByProfileImage,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
      content: json['content'] as String,
      author: json['author'] as String,
      authorName: json['authorName'] as String? ?? 'Anonymous',
      authorProfileImage: json['authorProfileImage'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as int) * 1000),
      isRepost: json['isRepost'] as bool? ?? false,
      repostedBy: json['repostedBy'] as String?,
      repostedByName: json['repostedByName'] as String?,
      repostedByProfileImage: json['repostedByProfileImage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'author': author,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'isRepost': isRepost,
      'repostedBy': repostedBy,
      'repostedByName': repostedByName,
      'repostedByProfileImage': repostedByProfileImage,
    };
  }
}
