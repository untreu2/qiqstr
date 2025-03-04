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
  final String rawWs;

  NoteModel({
    required this.id,
    required this.content,
    required this.author,
    required this.timestamp,
    this.isRepost = false,
    this.repostedBy,
    this.repostTimestamp,
    required this.rawWs,
  });

  NoteModel copyWith({
    String? id,
    String? content,
    String? author,
    DateTime? timestamp,
    bool? isRepost,
    String? repostedBy,
    DateTime? repostTimestamp,
    String? rawWs,
  }) {
    return NoteModel(
      id: id ?? this.id,
      content: content ?? this.content,
      author: author ?? this.author,
      timestamp: timestamp ?? this.timestamp,
      isRepost: isRepost ?? this.isRepost,
      repostedBy: repostedBy ?? this.repostedBy,
      repostTimestamp: repostTimestamp ?? this.repostTimestamp,
      rawWs: rawWs ?? this.rawWs,
    );
  }

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
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
      rawWs: json['rawWs'] as String,
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
      'repostTimestamp': repostTimestamp != null
          ? repostTimestamp!.millisecondsSinceEpoch ~/ 1000
          : null,
      'rawWs': rawWs,
    };
  }
}
