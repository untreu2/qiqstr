import 'package:isar/isar.dart';

part 'note_count_model_isar.g.dart';

@collection
class NoteCountModelIsar {
  Id id = Isar.autoIncrement;

  @Index(unique: true, type: IndexType.hash)
  late String noteId;

  late int reactionCount;
  late int replyCount;
  late int repostCount;
  late int zapAmount;
  late DateTime updatedAt;
  late DateTime cachedAt;

  static NoteCountModelIsar create({
    required String noteId,
    required int reactionCount,
    required int replyCount,
    required int repostCount,
    required int zapAmount,
  }) {
    return NoteCountModelIsar()
      ..noteId = noteId
      ..reactionCount = reactionCount
      ..replyCount = replyCount
      ..repostCount = repostCount
      ..zapAmount = zapAmount
      ..updatedAt = DateTime.now()
      ..cachedAt = DateTime.now();
  }

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(cachedAt) > ttl;
  }

  NoteCountModelIsar copyWith({
    String? noteId,
    int? reactionCount,
    int? replyCount,
    int? repostCount,
    int? zapAmount,
    DateTime? updatedAt,
    DateTime? cachedAt,
  }) {
    return NoteCountModelIsar()
      ..noteId = noteId ?? this.noteId
      ..reactionCount = reactionCount ?? this.reactionCount
      ..replyCount = replyCount ?? this.replyCount
      ..repostCount = repostCount ?? this.repostCount
      ..zapAmount = zapAmount ?? this.zapAmount
      ..updatedAt = updatedAt ?? this.updatedAt
      ..cachedAt = cachedAt ?? this.cachedAt;
  }
}

