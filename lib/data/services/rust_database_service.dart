import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../../src/rust/api/relay.dart' as rust_relay;

class RustDatabaseService {
  static final RustDatabaseService _instance = RustDatabaseService._internal();
  static RustDatabaseService get instance => _instance;

  RustDatabaseService._internal();

  bool _initialized = false;
  bool get isInitialized => _initialized;
  String? _ownPubkeyHex;

  final _changeController = StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;

  void notifyChange() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  Future<void> initialize({String? ownPubkeyHex}) async {
    _initialized = true;
    _ownPubkeyHex = ownPubkeyHex;
    autoCleanupIfNeeded();
  }

  void updateOwnPubkey(String pubkeyHex) {
    _ownPubkeyHex = pubkeyHex;
  }

  Future<void> close() async {}

  Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final json = await rust_db.dbGetDatabaseStats();
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) print('[RustDB] getDatabaseStats error: $e');
      return {};
    }
  }

  Future<int> getDatabaseSizeMB() async {
    try {
      final size = await rust_relay.getDatabaseSizeMb();
      return size.toInt();
    } catch (e) {
      if (kDebugMode) print('[RustDB] getDatabaseSizeMB error: $e');
      return 0;
    }
  }

  Future<void> wipeDatabase() async {
    try {
      await rust_db.dbWipeDirectory();
      notifyChange();
    } catch (e) {
      if (kDebugMode) print('[RustDB] wipeDatabase error: $e');
      try {
        await rust_db.dbWipe();
      } catch (e2) {
        if (kDebugMode) print('[RustDB] fallback wipe error: $e2');
      }
    }
  }

  Future<int> cleanupOldEvents({int daysToKeep = 30}) async {
    try {
      final count = await rust_db.dbCleanupOldEvents(daysToKeep: daysToKeep);
      notifyChange();
      return count;
    } catch (e) {
      if (kDebugMode) print('[RustDB] cleanupOldEvents error: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>> smartCleanup({
    required String ownPubkeyHex,
    int interactionDays = 7,
    int noteDays = 14,
  }) async {
    try {
      final json = await rust_db.dbSmartCleanup(
        ownPubkeyHex: ownPubkeyHex,
        interactionDays: interactionDays,
        noteDays: noteDays,
      );
      final result = jsonDecode(json) as Map<String, dynamic>;
      notifyChange();
      return result;
    } catch (e) {
      if (kDebugMode) print('[RustDB] smartCleanup error: $e');
      return {'totalDeleted': 0};
    }
  }

  Future<void> autoCleanupIfNeeded() async {
    try {
      final sizeMb = await getDatabaseSizeMB();
      if (sizeMb > 1500) {
        await wipeDatabase();
      } else if (sizeMb > 500) {
        if (_ownPubkeyHex != null) {
          await smartCleanup(
            ownPubkeyHex: _ownPubkeyHex!,
            interactionDays: 5,
            noteDays: 7,
          );
        } else {
          await cleanupOldEvents(daysToKeep: 7);
        }
      } else if (sizeMb > 200) {
        if (_ownPubkeyHex != null) {
          await smartCleanup(
            ownPubkeyHex: _ownPubkeyHex!,
            interactionDays: 7,
            noteDays: 7,
          );
        } else {
          await cleanupOldEvents(daysToKeep: 7);
        }
      }
    } catch (e) {
      if (kDebugMode) print('[RustDB] autoCleanupIfNeeded error: $e');
    }
  }
}
