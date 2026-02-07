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
