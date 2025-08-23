import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/zap_model.dart';

// Simplified Hive manager - removed over-engineered batch processing
class HiveManager {
  static HiveManager? _instance;
  static HiveManager get instance => _instance ??= HiveManager._internal();

  HiveManager._internal() {}

  final Map<String, Box> _openBoxes = {};
  final Set<String> _pendingBoxes = {};

  Timer? _cleanupTimer;
  static const Duration _cleanupInterval = Duration(hours: 6);
  static const int _maxBoxSize = 10000;

  bool _isInitialized = false;

  void _startBasicCleanup() {
    _cleanupTimer ??= Timer.periodic(_cleanupInterval, (_) {
      _performBasicCleanup();
    });
  }

  Future<void> _performBasicCleanup() async {
    try {
      final boxNames = _openBoxes.keys.toList();

      for (final boxName in boxNames) {
        final box = _openBoxes[boxName];
        if (box != null && box.length > _maxBoxSize) {
          // Simple cleanup - remove oldest 20% of entries
          final allKeys = box.keys.toList();
          final removeCount = (allKeys.length * 0.2).round();
          final keysToRemove = allKeys.take(removeCount);

          for (final key in keysToRemove) {
            await box.delete(key);
          }
          debugPrint('[HiveManager] Basic cleanup: removed $removeCount entries from $boxName');
        }
      }
    } catch (e) {
      debugPrint('[HiveManager] Basic cleanup error: $e');
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Hive.initFlutter();
      _isInitialized = true;
      _startBasicCleanup();
      debugPrint('[HiveManager] Initialized successfully');
    } catch (e) {
      debugPrint('[HiveManager] Initialization error: $e');
      rethrow;
    }
  }

  Future<Box<T>> getBox<T>(String boxName) async {
    if (_openBoxes.containsKey(boxName)) {
      return _openBoxes[boxName] as Box<T>;
    }

    if (_pendingBoxes.contains(boxName)) {
      while (_pendingBoxes.contains(boxName)) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return _openBoxes[boxName] as Box<T>;
    }

    _pendingBoxes.add(boxName);

    try {
      final box = await Hive.openBox<T>(boxName);
      _openBoxes[boxName] = box;
      _pendingBoxes.remove(boxName);

      debugPrint('[HiveManager] Opened box: $boxName');
      return box;
    } catch (e) {
      _pendingBoxes.remove(boxName);
      debugPrint('[HiveManager] Error opening box $boxName: $e');
      rethrow;
    }
  }

  // Simplified batch operations - direct execution
  Future<void> batchPut<T>(String boxName, Map<String, T> items) async {
    if (items.isEmpty) return;

    try {
      final box = await getBox(boxName);
      await box.putAll(items);
      debugPrint('[HiveManager] Put ${items.length} items to $boxName');
    } catch (e) {
      debugPrint('[HiveManager] Batch put error for $boxName: $e');
    }
  }

  Future<void> batchDelete(String boxName, List<String> keys) async {
    if (keys.isEmpty) return;

    try {
      final box = await getBox(boxName);
      await box.deleteAll(keys);
      debugPrint('[HiveManager] Deleted ${keys.length} items from $boxName');
    } catch (e) {
      debugPrint('[HiveManager] Batch delete error for $boxName: $e');
    }
  }

  // Simplified helper methods
  Future<List<T>> getRange<T>(String boxName, int start, int length) async {
    final box = await getBox<T>(boxName);
    final keys = box.keys.skip(start).take(length);
    return keys.map((key) => box.get(key)).whereType<T>().toList();
  }

  Future<List<T>> getWhere<T>(String boxName, bool Function(T) predicate) async {
    final box = await getBox<T>(boxName);
    return box.values.where(predicate).toList();
  }

  Future<Map<String, T>> getMultiple<T>(String boxName, List<String> keys) async {
    final box = await getBox<T>(boxName);
    final result = <String, T>{};

    for (final key in keys) {
      final value = box.get(key);
      if (value != null) {
        result[key] = value;
      }
    }

    return result;
  }

  Future<void> compactBox(String boxName) async {
    try {
      final box = await getBox(boxName);
      await box.compact();
      debugPrint('[HiveManager] Compacted box: $boxName');
    } catch (e) {
      debugPrint('[HiveManager] Error compacting box $boxName: $e');
    }
  }

  Future<void> clearBox(String boxName) async {
    try {
      final box = await getBox(boxName);
      await box.clear();
      debugPrint('[HiveManager] Cleared box: $boxName');
    } catch (e) {
      debugPrint('[HiveManager] Error clearing box $boxName: $e');
    }
  }

  // Simplified cleanup - just remove old entries
  Future<void> cleanupOldData(String boxName, Duration maxAge) async {
    try {
      final box = await getBox(boxName);
      final cutoffTime = DateTime.now().subtract(maxAge);
      final keysToDelete = <String>[];

      for (final key in box.keys) {
        final value = box.get(key);
        DateTime? timestamp;

        if (value is NoteModel) {
          timestamp = value.timestamp;
        } else if (value is ReactionModel) {
          timestamp = value.fetchedAt;
        } else if (value is ReplyModel) {
          timestamp = value.fetchedAt;
        } else if (value is RepostModel) {
          timestamp = value.repostTimestamp;
        } else if (value is ZapModel) {
          timestamp = value.timestamp;
        } else if (value is UserModel) {
          timestamp = value.updatedAt;
        }

        if (timestamp != null && timestamp.isBefore(cutoffTime)) {
          keysToDelete.add(key.toString());
        }
      }

      if (keysToDelete.isNotEmpty) {
        await batchDelete(boxName, keysToDelete);
        debugPrint('[HiveManager] Cleaned up ${keysToDelete.length} old entries from $boxName');
      }
    } catch (e) {
      debugPrint('[HiveManager] Error cleaning up $boxName: $e');
    }
  }

  // Simplified stats
  Map<String, dynamic> getStats() {
    return {
      'openBoxes': _openBoxes.length,
      'pendingBoxes': _pendingBoxes.length,
      'isInitialized': _isInitialized,
    };
  }

  // Simplified memory handling
  Future<void> handleMemoryPressure() async {
    try {
      await _performBasicCleanup();
      debugPrint('[HiveManager] Memory pressure handling completed');
    } catch (e) {
      debugPrint('[HiveManager] Memory pressure handling error: $e');
    }
  }

  Map<String, dynamic> getMemoryStats() {
    int totalEntries = 0;
    final boxStats = <String, int>{};

    for (final entry in _openBoxes.entries) {
      final boxName = entry.key;
      final box = entry.value;
      final entryCount = box.length;

      boxStats[boxName] = entryCount;
      totalEntries += entryCount;
    }

    return {
      'openBoxes': _openBoxes.length,
      'totalEntries': totalEntries,
      'boxStats': boxStats,
      'pendingBoxes': _pendingBoxes.length,
    };
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();

    for (final box in _openBoxes.values) {
      await box.close();
    }
    _openBoxes.clear();
    _pendingBoxes.clear();

    debugPrint('[HiveManager] Disposed successfully');
  }
}
