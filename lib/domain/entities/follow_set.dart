import 'package:equatable/equatable.dart';

class FollowSet extends Equatable {
  final String id;
  final String pubkey;
  final String dTag;
  final String title;
  final String description;
  final String image;
  final List<String> pubkeys;
  final int createdAt;

  const FollowSet({
    required this.id,
    required this.pubkey,
    required this.dTag,
    this.title = '',
    this.description = '',
    this.image = '',
    this.pubkeys = const [],
    required this.createdAt,
  });

  FollowSet copyWith({
    String? id,
    String? pubkey,
    String? dTag,
    String? title,
    String? description,
    String? image,
    List<String>? pubkeys,
    int? createdAt,
  }) {
    return FollowSet(
      id: id ?? this.id,
      pubkey: pubkey ?? this.pubkey,
      dTag: dTag ?? this.dTag,
      title: title ?? this.title,
      description: description ?? this.description,
      image: image ?? this.image,
      pubkeys: pubkeys ?? this.pubkeys,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pubkey': pubkey,
      'dTag': dTag,
      'title': title,
      'description': description,
      'image': image,
      'pubkeys': pubkeys,
      'createdAt': createdAt,
    };
  }

  factory FollowSet.fromEvent(Map<String, dynamic> event) {
    final tags = event['tags'] as List<dynamic>? ?? [];
    String dTag = '';
    String title = '';
    String description = '';
    String image = '';
    final pubkeys = <String>[];

    for (final tag in tags) {
      if (tag is! List || tag.isEmpty) continue;
      final tagName = tag[0] as String? ?? '';
      if (tag.length < 2) continue;
      final tagValue = tag[1] as String? ?? '';

      switch (tagName) {
        case 'd':
          dTag = tagValue;
        case 'title':
          title = tagValue;
        case 'description':
          description = tagValue;
        case 'image':
          image = tagValue;
        case 'p':
          if (tagValue.isNotEmpty) pubkeys.add(tagValue);
      }
    }

    return FollowSet(
      id: event['id'] as String? ?? '',
      pubkey: event['pubkey'] as String? ?? '',
      dTag: dTag,
      title: title,
      description: description,
      image: image,
      pubkeys: pubkeys,
      createdAt: event['created_at'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props =>
      [id, pubkey, dTag, title, description, image, pubkeys, createdAt];
}
