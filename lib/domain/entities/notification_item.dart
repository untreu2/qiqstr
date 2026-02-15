enum NotificationType {
  reply,
  mention,
  reaction,
  repost,
  zap,
}

class NotificationItem {
  final String id;
  final NotificationType type;
  final String fromPubkey;
  final String? targetNoteId;
  final String? content;
  final int createdAt;
  final String? fromName;
  final String? fromImage;
  final int? zapAmount;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.fromPubkey,
    this.targetNoteId,
    this.content,
    required this.createdAt,
    this.fromName,
    this.fromImage,
    this.zapAmount,
  });

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'mention';
    final type = switch (typeStr) {
      'reply' => NotificationType.reply,
      'reaction' => NotificationType.reaction,
      'repost' => NotificationType.repost,
      'zap' => NotificationType.zap,
      _ => NotificationType.mention,
    };

    return NotificationItem(
      id: map['id'] as String? ?? '',
      type: type,
      fromPubkey: map['fromPubkey'] as String? ?? '',
      targetNoteId: map['targetNoteId'] as String?,
      content: map['content'] as String?,
      createdAt: map['createdAt'] as int? ?? 0,
      fromName: map['fromName'] as String?,
      fromImage: map['fromImage'] as String?,
      zapAmount: map['zapAmount'] as int?,
    );
  }

  NotificationItem copyWith({
    String? id,
    NotificationType? type,
    String? fromPubkey,
    String? targetNoteId,
    String? content,
    int? createdAt,
    String? fromName,
    String? fromImage,
    int? zapAmount,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      type: type ?? this.type,
      fromPubkey: fromPubkey ?? this.fromPubkey,
      targetNoteId: targetNoteId ?? this.targetNoteId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      fromName: fromName ?? this.fromName,
      fromImage: fromImage ?? this.fromImage,
      zapAmount: zapAmount ?? this.zapAmount,
    );
  }

  DateTime get createdAtDateTime {
    return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
  }
}
