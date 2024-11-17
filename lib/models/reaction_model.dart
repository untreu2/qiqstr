class ReactionModel {
  final String reactionId;
  final String content;
  final String reactorPubKey;
  final DateTime timestamp;

  ReactionModel({
    required this.reactionId,
    required this.content,
    required this.reactorPubKey,
    required this.timestamp,
  });

  factory ReactionModel.fromEvent(Map<String, dynamic> eventData) {
    return ReactionModel(
      reactionId: eventData['id'],
      content: eventData['content'] ?? '+',
      reactorPubKey: eventData['pubkey'],
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reactionId': reactionId,
      'content': content,
      'reactorPubKey': reactorPubKey,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
