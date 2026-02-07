class Article {
  final String id;
  final String pubkey;
  final String title;
  final String content;
  final String? image;
  final String? summary;
  final String dTag;
  final int publishedAt;
  final int createdAt;
  final List<String> hashtags;
  final String? authorName;
  final String? authorImage;

  const Article({
    required this.id,
    required this.pubkey,
    required this.title,
    required this.content,
    this.image,
    this.summary,
    required this.dTag,
    required this.publishedAt,
    required this.createdAt,
    this.hashtags = const [],
    this.authorName,
    this.authorImage,
  });

  Article copyWith({
    String? id,
    String? pubkey,
    String? title,
    String? content,
    String? image,
    String? summary,
    String? dTag,
    int? publishedAt,
    int? createdAt,
    List<String>? hashtags,
    String? authorName,
    String? authorImage,
  }) {
    return Article(
      id: id ?? this.id,
      pubkey: pubkey ?? this.pubkey,
      title: title ?? this.title,
      content: content ?? this.content,
      image: image ?? this.image,
      summary: summary ?? this.summary,
      dTag: dTag ?? this.dTag,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt ?? this.createdAt,
      hashtags: hashtags ?? this.hashtags,
      authorName: authorName ?? this.authorName,
      authorImage: authorImage ?? this.authorImage,
    );
  }

  DateTime get publishedAtDateTime {
    return DateTime.fromMillisecondsSinceEpoch(publishedAt * 1000);
  }

  DateTime get createdAtDateTime {
    return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pubkey': pubkey,
      'title': title,
      'content': content,
      if (image != null) 'image': image,
      if (summary != null) 'summary': summary,
      'dTag': dTag,
      'publishedAt': publishedAt,
      'created_at': createdAt,
      'tTags': hashtags,
      if (authorName != null) 'author': authorName,
      if (authorImage != null) 'authorImage': authorImage,
    };
  }
}
