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
      {int limit = 100}) {
    return _events.onChange
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) => getNotifications(userPubkey, limit: limit));
  }

  Future<List<NotificationItem>> getNotifications(String userPubkey,
      {int limit = 100}) async {
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

  Future<void> save(
      String userPubkey, List<Map<String, dynamic>> notifications) async {
    if (notifications.isEmpty) return;
    try {
      await rust_db.dbSaveEvents(eventsJson: jsonEncode(notifications));
      _events.notifyChange();
    } catch (e) {
      if (kDebugMode) print('[NotificationRepository] save error: $e');
    }
  }
}
