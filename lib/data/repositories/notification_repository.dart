import 'dart:async';
import '../../domain/entities/notification_item.dart';
import 'base_repository.dart';

abstract class NotificationRepository {
  Stream<List<NotificationItem>> watchNotifications(String userPubkey,
      {int limit = 100});
  Future<List<NotificationItem>> getNotifications(String userPubkey,
      {int limit = 100});
  Future<void> saveNotifications(
      String userPubkey, List<Map<String, dynamic>> notifications);
}

class NotificationRepositoryImpl extends BaseRepository
    implements NotificationRepository {
  NotificationRepositoryImpl({
    required super.db,
    required super.mapper,
  });

  @override
  Stream<List<NotificationItem>> watchNotifications(String userPubkey,
      {int limit = 100}) {
    return db
        .watchHydratedNotifications(userPubkey, limit: limit)
        .map((maps) =>
            maps.map((m) => NotificationItem.fromMap(m)).toList());
  }

  @override
  Future<List<NotificationItem>> getNotifications(String userPubkey,
      {int limit = 100}) async {
    final maps =
        await db.getHydratedNotifications(userPubkey, limit: limit);
    return maps.map((m) => NotificationItem.fromMap(m)).toList();
  }

  @override
  Future<void> saveNotifications(
      String userPubkey, List<Map<String, dynamic>> notifications) async {
    await db.saveNotifications(userPubkey, notifications);
  }
}
