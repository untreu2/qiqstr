class RepostModel {
  final String id;
  final String originalNoteId;
  final String repostedBy;
  final DateTime repostTimestamp;

  RepostModel({
    required this.id,
    required this.originalNoteId,
    required this.repostedBy,
    required this.repostTimestamp,
  });

  factory RepostModel.fromEvent(Map<String, dynamic> eventData, String originalNoteId) {
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
