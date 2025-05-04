import 'package:hive/hive.dart';

part 'notification_model.g.dart';

@HiveType(typeId: 10)
class NotificationModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String type;

  @HiveField(2)
  String eventId;

  @HiveField(3)
  String actorNpub;

  @HiveField(4)
  List<String> targetEventIds;

  @HiveField(5)
  String? content;

  @HiveField(6)
  DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.type,
    required this.eventId,
    required this.actorNpub,
    required this.targetEventIds,
    required this.createdAt,
    this.content,
  });
}
