import 'dart:convert';
import 'package:qiqstr/models/zap_model.dart';
import '../services/time_service.dart';

class NotificationModel {
  final String id;
  final String targetEventId;
  final String author;
  final String type;
  final String content;
  final DateTime timestamp;
  final DateTime fetchedAt;
  bool isRead;
  final int amount;

  NotificationModel({
    required this.id,
    required this.targetEventId,
    required this.author,
    required this.type,
    required this.content,
    required this.timestamp,
    required this.fetchedAt,
    this.isRead = false,
    this.amount = 0,
  });

  factory NotificationModel.fromEvent(Map<String, dynamic> eventData, String type) {
    String? targetEventId;
    final String eventItselfId = eventData['id'] as String;
    final List tags = (eventData['tags'] as List).cast<List>();

    for (var tag in tags) {
      if (tag.length >= 2 && tag[0] == 'e') {
        targetEventId = tag[1];
        break;
      }
    }

    if (type == "mention" && targetEventId == null) {
      targetEventId = eventItselfId;
    }

    targetEventId ??= eventItselfId;

    int zapAmount = 0;
    String actualAuthor = eventData['pubkey'] as String;

    if (type == 'zap') {
      String getTagValue(String key) => tags.firstWhere((t) => t.isNotEmpty && t[0] == key, orElse: () => [key, ''])[1];

      final bolt11 = getTagValue('bolt11');
      final descriptionJson = getTagValue('description');

      zapAmount = parseAmountFromBolt11(bolt11);

      try {
        final decoded = jsonDecode(descriptionJson);
        if (decoded is Map<String, dynamic> && decoded.containsKey('pubkey')) {
          actualAuthor = decoded['pubkey'];
        }
      } catch (_) {}
    }

    return NotificationModel(
      id: eventItselfId,
      targetEventId: targetEventId,
      author: actualAuthor,
      type: type,
      content: eventData['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000),
      fetchedAt: DateTime.now(),
      isRead: false,
      amount: zapAmount,
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'],
      targetEventId: json['targetEventId'],
      author: json['author'],
      type: json['type'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      fetchedAt: DateTime.parse(json['fetchedAt']),
      isRead: json['isRead'] ?? false,
      amount: json['amount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'targetEventId': targetEventId,
      'author': author,
      'type': type,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'fetchedAt': fetchedAt.toIso8601String(),
      'isRead': isRead,
      'amount': amount,
    };
  }
}
