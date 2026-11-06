import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entities/notification_item.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../services/encrypted_mute_service.dart';
import '../services/rust_database_service.dart';

class NotificationRepository {
  final RustDatabaseService _events;

  NotificationRepository({required RustDatabaseService events})
      : _events = events;

  List<String> get _mutedPubkeys => EncryptedMuteService.instance.mutedPubkeys;
  List<String> get _mutedWords => EncryptedMuteService.instance.mutedWords;

  Stream<List<NotificationItem>> watchNotifications(String userPubkey,
      {int limit = 200}) {
    return _events.onNotificationChange
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) => getNotifications(userPubkey, limit: limit));
  }

  Future<List<NotificationItem>> getNotifications(String userPubkey,
      {int limit = 200}) async {
    try {
      final json = await rust_db.dbGetHydratedNotifications(
        userPubkeyHex: userPubkey,
        limit: limit,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map((m) => NotificationItem.fromMap(m))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('[NotificationRepository] getNotifications error: $e');
      }
      return [];
    }
  }

  Future<List<NotificationItem>> getNotificationsBefore(
    String userPubkey, {
    required int beforeTimestamp,
    int limit = 100,
  }) async {
    if (beforeTimestamp <= 0) return [];
    try {
      final json = await rust_db.dbGetHydratedNotificationsBefore(
        userPubkeyHex: userPubkey,
        beforeTimestamp: BigInt.from(beforeTimestamp),
        limit: limit,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map((m) => NotificationItem.fromMap(m))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('[NotificationRepository] getNotificationsBefore error: $e');
      }
      return [];
    }
  }

  Future<int?> getOldestLocalNotificationTimestamp(String userPubkey) async {
    try {
      final ts =
          await rust_db.dbGetOldestNotificationTimestamp(userPubkeyHex: userPubkey);
      if (ts == null) return null;
      final asInt = ts.toInt();
      return asInt == 0 ? null : asInt;
    } catch (e) {
      if (kDebugMode) {
        print('[NotificationRepository] getOldestLocalNotificationTimestamp error: $e');
      }
      return null;
    }
  }

  Future<void> save(
      String userPubkey, List<Map<String, dynamic>> notifications) async {
    if (notifications.isEmpty) return;
    try {
      await rust_db.dbSaveEvents(eventsJson: jsonEncode(notifications));
      _events.notifyNotificationChange();
    } catch (e) {
      if (kDebugMode) print('[NotificationRepository] save error: $e');
    }
  }
}
