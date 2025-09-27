import 'dart:convert';

class ZapModel {
  String id;
  String sender;
  String recipient;
  String targetEventId;
  DateTime timestamp;
  String bolt11;
  String? comment;
  int amount;

  ZapModel({
    required this.id,
    required this.sender,
    required this.recipient,
    required this.targetEventId,
    required this.timestamp,
    required this.bolt11,
    this.comment,
    required this.amount,
  });

  factory ZapModel.fromEvent(Map<String, dynamic> event) {
    final tags = (event['tags'] as List).cast<List>();

    String getTagValue(String key) => tags.firstWhere((t) => t.isNotEmpty && t[0] == key, orElse: () => [key, ''])[1];

    final p = getTagValue('p');
    final e = getTagValue('e');
    final bolt11 = getTagValue('bolt11');
    final descriptionJson = getTagValue('description');

    String? comment;
    String sender = '';

    try {
      final decoded = jsonDecode(descriptionJson);
      comment = decoded['content'];
      sender = decoded['pubkey'] ?? '';
    } catch (_) {
      sender = getTagValue('P').isNotEmpty ? getTagValue('P') : event['pubkey'] ?? '';
    }

    final amount = parseAmountFromBolt11(bolt11);

    return ZapModel(
      id: event['id'],
      sender: sender,
      recipient: p,
      targetEventId: e,
      timestamp: DateTime.fromMillisecondsSinceEpoch(event['created_at'] * 1000),
      bolt11: bolt11,
      comment: comment,
      amount: amount,
    );
  }
}

int parseAmountFromBolt11(String bolt11) {
  final match = RegExp(r'^lnbc(\d+)([munp]?)', caseSensitive: false).firstMatch(bolt11);
  if (match == null) return 0;

  final number = int.tryParse(match.group(1) ?? '') ?? 0;
  final unit = match.group(2)?.toLowerCase();

  switch (unit) {
    case 'm':
      return number * 100000;
    case 'u':
      return number * 100;
    case 'n':
      return (number * 0.1).round();
    case 'p':
      return (number * 0.001).round();
    default:
      return number * 1000;
  }
}
