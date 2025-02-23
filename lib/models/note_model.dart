import 'package:hive/hive.dart';

part 'note_model.g.dart';

@HiveType(typeId: 0)
class NoteModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String uniqueId;

  @HiveField(2)
  final String content;

  @HiveField(3)
  final String author;

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  final bool isRepost;

  @HiveField(6)
  final String? repostedBy;

  @HiveField(7)
  final DateTime? repostTimestamp;

  @HiveField(8)
  int repostCount;

  @HiveField(9)
  final String? rawWs;

  NoteModel({
    required this.id,
    required this.uniqueId,
    required this.content,
    required this.author,
    required this.timestamp,
    this.isRepost = false,
    this.repostedBy,
    this.repostTimestamp,
    this.repostCount = 0,
    this.rawWs,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
      uniqueId: json['uniqueId'] as String? ?? json['id'] as String,
      content: json['content'] as String,
      author: json['author'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (json['timestamp'] as int) * 1000),
      isRepost: json['isRepost'] as bool? ?? false,
      repostedBy: json['repostedBy'] as String?,
      repostTimestamp: json['repostTimestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['repostTimestamp'] as int) * 1000)
          : null,
      repostCount: json['repostCount'] as int? ?? 0,
      rawWs: json['rawWs'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uniqueId': uniqueId,
      'content': content,
      'author': author,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'isRepost': isRepost,
      'repostedBy': repostedBy,
      'repostTimestamp': repostTimestamp != null
          ? repostTimestamp!.millisecondsSinceEpoch ~/ 1000
          : null,
      'repostCount': repostCount,
      'rawWs': rawWs,
    };
  }
}
