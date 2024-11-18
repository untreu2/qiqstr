class ReactionModel {
  final String reactionId;
  final String content;
  final String reactorPubKey;
  final String authorName;
  final String authorProfileImage;
  final DateTime timestamp;

  ReactionModel({
    required this.reactionId,
    required this.content,
    required this.reactorPubKey,
    required this.timestamp,
    this.authorName = 'Anonymous',
    this.authorProfileImage = '',
  });

  factory ReactionModel.fromEvent(Map<String, dynamic> eventData, Map<String, String> profile) {
    return ReactionModel(
      reactionId: eventData['id'],
      content: eventData['content'] ?? '+',
      reactorPubKey: eventData['pubkey'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000),
      authorName: profile['name'] ?? 'Anonymous',
      authorProfileImage: profile['profileImage'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reactionId': reactionId,
      'content': content,
      'reactorPubKey': reactorPubKey,
      'timestamp': timestamp.toIso8601String(),
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
    };
  }
}
