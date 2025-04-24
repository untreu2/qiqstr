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
  final DateTime timestamp;

  @HiveField(4)
  final bool isRepost;

  @HiveField(5)
  final String? repostedBy;

  @HiveField(6)
  final DateTime? repostTimestamp;

  @HiveField(7)
  String? rawWs;

  @HiveField(8)
  int reactionCount;

  @HiveField(9)
  int replyCount;

  @HiveField(10)
  int repostCount;

  NoteModel({
    required this.id,
    required this.content,
    required this.author,
    required this.timestamp,
    this.isRepost = false,
    this.repostedBy,
    this.repostTimestamp,
    this.rawWs,
    this.reactionCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'],
      content: json['content'],
      author: json['author'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] * 1000),
      isRepost: json['isRepost'] ?? false,
      repostedBy: json['repostedBy'],
      repostTimestamp: json['repostTimestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['repostTimestamp'] * 1000)
          : null,
      rawWs: json['rawWs'],
      reactionCount: json['reactionCount'] ?? 0,
      replyCount: json['replyCount'] ?? 0,
      repostCount: json['repostCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'author': author,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'isRepost': isRepost,
      'repostedBy': repostedBy,
      'repostTimestamp': repostTimestamp!.millisecondsSinceEpoch ~/ 1000,
      'rawWs': rawWs,
      'reactionCount': reactionCount,
      'replyCount': replyCount,
      'repostCount': repostCount,
    };
  }
}
