class NoteModel {
  final String id;
  final String content;
  final String author;
  final String authorName;
  final String authorProfileImage;
  final DateTime timestamp;

  NoteModel({
    required this.id,
    required this.content,
    required this.author,
    required this.authorName,
    required this.authorProfileImage,
    required this.timestamp,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
      content: json['content'] as String,
      author: json['author'] as String,
      authorName: json['authorName'] as String? ?? 'Anonymous',
      authorProfileImage: json['authorProfileImage'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as int) * 1000),
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
    };
  }
}
