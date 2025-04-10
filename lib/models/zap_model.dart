import 'package:hive/hive.dart';

part 'zap_model.g.dart';

@HiveType(typeId: 5)
class ZapModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String targetEventId;

  @HiveField(2)
  final String sender;

  @HiveField(3)
  final String recipient;

  @HiveField(4)
  final String bolt11;

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  final DateTime fetchedAt;

  @HiveField(7)
  final int amount;

  @HiveField(8)
  final String memo;

  ZapModel({
    required this.id,
    required this.targetEventId,
    required this.sender,
    required this.recipient,
    required this.bolt11,
    required this.timestamp,
    required this.fetchedAt,
    required this.amount,
    required this.memo,
  });

  factory ZapModel.fromEvent(
    Map<String, dynamic> eventData, {
    required int amount,
    required String memo,
  }) {
    String? targetEventId;
    String? recipient;
    String? bolt11;

    for (var tag in eventData['tags']) {
      if (tag is List && tag.length >= 2) {
        if (tag[0] == 'e') targetEventId = tag[1];
        if (tag[0] == 'p') recipient = tag[1];
        if (tag[0] == 'bolt11') bolt11 = tag[1];
      }
    }

    if (targetEventId == null || recipient == null || bolt11 == null) {
      throw Exception('Missing required zap fields.');
    }

    return ZapModel(
      id: eventData['id'],
      targetEventId: targetEventId,
      sender: eventData['pubkey'],
      recipient: recipient,
      bolt11: bolt11,
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000),
      fetchedAt: DateTime.now(),
      amount: amount,
      memo: memo,
    );
  }

  factory ZapModel.fromJson(Map<String, dynamic> json) {
    return ZapModel(
      id: json['id'],
      targetEventId: json['targetEventId'],
      sender: json['sender'],
      recipient: json['recipient'],
      bolt11: json['bolt11'],
      timestamp: DateTime.parse(json['timestamp']),
      fetchedAt: DateTime.parse(json['fetchedAt']),
      amount: json['amount'],
      memo: json['memo'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'targetEventId': targetEventId,
      'sender': sender,
      'recipient': recipient,
      'bolt11': bolt11,
      'timestamp': timestamp.toIso8601String(),
      'fetchedAt': fetchedAt.toIso8601String(),
      'amount': amount,
      'memo': memo,
    };
  }
}
