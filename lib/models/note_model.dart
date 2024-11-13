class NoteModel {
  final String noteId;
  final String content;
  final String author;
  final String authorName;
  final String authorProfileImage;
  final DateTime timestamp;

  NoteModel({
    required this.noteId,
    required this.content,
    required this.author,
    required this.authorName,
    required this.authorProfileImage,
    required this.timestamp,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      noteId: json['noteId'],
      content: json['content'],
      author: json['author'],
      authorName: json['authorName'] ?? 'Anonymous',
      authorProfileImage: json['profileImage'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'noteId': noteId,
      'content': content,
      'author': author,
      'authorName': authorName,
      'profileImage': authorProfileImage,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
