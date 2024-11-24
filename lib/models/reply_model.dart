class ReplyModel {
  final String id;
  final String author;
  final String content;
  final DateTime timestamp;
  final String parentId;
  final String authorName;
  final String authorProfileImage;

  ReplyModel({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
    required this.parentId,
    required this.authorName,
    required this.authorProfileImage,
  });

  factory ReplyModel.fromEvent(Map<String, dynamic> eventData, Map<String, String> profile) {
    String? parentId;
    for (var tag in eventData['tags']) {
      if (tag.length >= 2 && tag[0] == 'e') {
        parentId = tag[1] as String;
        break;
      }
    }

    return ReplyModel(
      id: eventData['id'] as String,
      author: eventData['pubkey'] as String,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000),
      parentId: parentId ?? '',
      authorName: profile['name'] ?? 'Anonymous',
      authorProfileImage: profile['profileImage'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author': author,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'parentId': parentId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
    };
  }

  factory ReplyModel.fromJson(Map<String, dynamic> json) {
    return ReplyModel(
      id: json['id'],
      author: json['author'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      parentId: json['parentId'],
      authorName: json['authorName'],
      authorProfileImage: json['authorProfileImage'],
    );
  }
}
