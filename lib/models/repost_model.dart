import 'package:hive/hive.dart';
part 'repost_model.g.dart';

@HiveType(typeId: 3)
class RepostModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String originalNoteId;

  @HiveField(2)
  final String repostedBy;

  @HiveField(3)
  final DateTime repostTimestamp;

  RepostModel({
    required this.id,
    required this.originalNoteId,
    required this.repostedBy,
    required this.repostTimestamp,
  });

  factory RepostModel.fromEvent(
      Map<String, dynamic> eventData, String originalNoteId) {
    return RepostModel(
      id: eventData['id'] as String,
      originalNoteId: originalNoteId,
      repostedBy: eventData['pubkey'] as String,
      repostTimestamp: DateTime.fromMillisecondsSinceEpoch(
        (eventData['created_at'] as int) * 1000,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalNoteId': originalNoteId,
      'repostedBy': repostedBy,
      'repostTimestamp': repostTimestamp.millisecondsSinceEpoch ~/ 1000,
    };
  }
}
