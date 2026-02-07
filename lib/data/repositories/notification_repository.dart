import 'dart:async';
import '../../domain/entities/notification_item.dart';
import '../../models/event_model.dart';
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
        .watchNotifications(userPubkey, limit: limit)
        .asyncMap((events) async {
      return await _hydrateNotifications(events);
    });
  }

  @override
  Future<List<NotificationItem>> getNotifications(String userPubkey,
      {int limit = 100}) async {
    final events = await db.getCachedNotifications(userPubkey, limit: limit);
    return await _hydrateNotifications(events);
  }

  @override
  Future<void> saveNotifications(
      String userPubkey, List<Map<String, dynamic>> notifications) async {
    await db.saveNotifications(userPubkey, notifications);
  }

  Future<List<NotificationItem>> _hydrateNotifications(
      List<EventModel> events) async {
    if (events.isEmpty) return [];

    final pubkeys = events.map((e) => e.pubkey).toSet().toList();
    final profiles = await db.getUserProfiles(pubkeys);

    return events.map((event) {
      final profile = profiles[event.pubkey];

      return mapper.toNotificationItem(
        event,
        fromName: profile?['name'] ?? profile?['display_name'],
        fromImage: profile?['profileImage'],
      );
    }).toList();
  }
}
