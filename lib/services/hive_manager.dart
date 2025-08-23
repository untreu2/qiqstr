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

class HiveManager {
  static HiveManager? _instance;
  static HiveManager get instance => _instance ??= HiveManager._internal();

  HiveManager._internal() {}

  final Map<String, List<_BatchOperation>> _batchQueues = {};
  final Map<String, Timer> _batchTimers = {};
  final Duration _batchDelay = const Duration(milliseconds: 100);
  final int _maxBatchSize = 50;

  final Map<String, Box> _openBoxes = {};
  final Set<String> _pendingBoxes = {};

  Timer? _cleanupTimer;
  Timer? _compactionTimer;

  static const Duration _defaultMaxAge = Duration(days: 7);
  static const Duration _cleanupInterval = Duration(hours: 2);
  static const Duration _compactionInterval = Duration(hours: 6);
  static const int _maxBoxSize = 10000;

  bool _isInitialized = false;

  void _startAutomaticCleanup() {
    if (_cleanupTimer != null) return;

    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performAutomaticCleanup();
    });

    _compactionTimer = Timer.periodic(_compactionInterval, (_) {
      _performAutomaticCompaction();
    });
  }

  void _ensureCleanupStarted() {
    if (_cleanupTimer == null && _openBoxes.isNotEmpty) {
      Future.delayed(const Duration(minutes: 5), () {
        _startAutomaticCleanup();
      });
    }
  }

  Future<void> _performAutomaticCleanup() async {
    try {
      final boxNames = _openBoxes.keys.toList();

      for (final boxName in boxNames) {
        if (_isCriticalBox(boxName)) continue;

        await cleanupOldData(boxName, _defaultMaxAge);

        final box = _openBoxes[boxName];
        if (box != null && box.length > _maxBoxSize) {
          await _cleanupLargeBox(boxName, box);
        }
      }

      debugPrint('[HiveManager] Automatic cleanup completed for ${boxNames.length} boxes');
    } catch (e) {
      debugPrint('[HiveManager] Automatic cleanup error: $e');
    }
  }

  Future<void> _performAutomaticCompaction() async {
    try {
      final boxNames = _openBoxes.keys.toList();

      for (final boxName in boxNames) {
        final box = _openBoxes[boxName];
        if (box != null && box.length > 1000) {
          await compactBox(boxName);

          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      debugPrint('[HiveManager] Automatic compaction completed');
    } catch (e) {
      debugPrint('[HiveManager] Automatic compaction error: $e');
    }
  }

  bool _isCriticalBox(String boxName) {
    return boxName.contains('users') || boxName.contains('followingBox') || boxName.contains('settings');
  }

  Future<void> _cleanupLargeBox(String boxName, Box box) async {
    try {
      final keysToRemove = <String>[];
      final allKeys = box.keys.toList();
      final removeCount = (allKeys.length * 0.2).round();

      final sortedKeys = <MapEntry<dynamic, DateTime>>[];

      for (final key in allKeys) {
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

        if (timestamp != null) {
          sortedKeys.add(MapEntry(key, timestamp));
        }
      }

      if (sortedKeys.isNotEmpty) {
        sortedKeys.sort((a, b) => a.value.compareTo(b.value));
        keysToRemove.addAll(sortedKeys.take(removeCount).map((e) => e.key.toString()));
      } else {
        keysToRemove.addAll(allKeys.take(removeCount).map((k) => k.toString()));
      }

      if (keysToRemove.isNotEmpty) {
        await batchDelete(boxName, keysToRemove);
        debugPrint('[HiveManager] Cleaned up ${keysToRemove.length} entries from large box: $boxName');
      }
    } catch (e) {
      debugPrint('[HiveManager] Error cleaning up large box $boxName: $e');
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Hive.initFlutter();
      _isInitialized = true;
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

      _ensureCleanupStarted();

      debugPrint('[HiveManager] Opened box: $boxName');
      return box;
    } catch (e) {
      _pendingBoxes.remove(boxName);
      debugPrint('[HiveManager] Error opening box $boxName: $e');
      rethrow;
    }
  }

  Future<void> batchPut<T>(String boxName, Map<String, T> items) async {
    if (items.isEmpty) return;

    _queueBatchOperation(boxName, _BatchOperation.putAll(items));
  }

  Future<void> batchDelete(String boxName, List<String> keys) async {
    if (keys.isEmpty) return;

    _queueBatchOperation(boxName, _BatchOperation.deleteAll(keys));
  }

  void _queueBatchOperation(String boxName, _BatchOperation operation) {
    _batchQueues.putIfAbsent(boxName, () => []);
    _batchQueues[boxName]!.add(operation);

    _batchTimers[boxName]?.cancel();

    if (_batchQueues[boxName]!.length >= _maxBatchSize) {
      _executeBatch(boxName);
    } else {
      _batchTimers[boxName] = Timer(_batchDelay, () => _executeBatch(boxName));
    }
  }

  Future<void> _executeBatch(String boxName) async {
    final operations = _batchQueues[boxName];
    if (operations == null || operations.isEmpty) return;

    _batchQueues[boxName] = [];
    _batchTimers[boxName]?.cancel();

    try {
      final box = await getBox(boxName);

      final putOperations = <String, dynamic>{};
      final deleteKeys = <String>[];

      for (final op in operations) {
        if (op.type == _BatchOperationType.putAll) {
          putOperations.addAll(op.data as Map<String, dynamic>);
        } else if (op.type == _BatchOperationType.deleteAll) {
          deleteKeys.addAll(op.data as List<String>);
        }
      }

      if (putOperations.isNotEmpty) {
        await box.putAll(putOperations);
      }

      if (deleteKeys.isNotEmpty) {
        await box.deleteAll(deleteKeys);
      }

      debugPrint('[HiveManager] Executed batch for $boxName: ${putOperations.length} puts, ${deleteKeys.length} deletes');
    } catch (e) {
      debugPrint('[HiveManager] Batch execution error for $boxName: $e');
    }
  }

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

  Future<void> flushAllBatches() async {
    final futures = _batchQueues.keys.map((boxName) => _executeBatch(boxName));
    await Future.wait(futures);
  }

  Map<String, dynamic> getStats() {
    return {
      'openBoxes': _openBoxes.length,
      'pendingBoxes': _pendingBoxes.length,
      'queuedBatches': _batchQueues.values.fold<int>(0, (sum, queue) => sum + queue.length),
      'activeBatchTimers': _batchTimers.length,
      'isInitialized': _isInitialized,
    };
  }

  Future<void> cleanupAllBoxes({Duration? maxAge}) async {
    final age = maxAge ?? _defaultMaxAge;
    final boxNames = _openBoxes.keys.toList();

    for (final boxName in boxNames) {
      if (!_isCriticalBox(boxName)) {
        await cleanupOldData(boxName, age);
      }
    }
  }

  Future<void> compactAllBoxes() async {
    final boxNames = _openBoxes.keys.toList();

    for (final boxName in boxNames) {
      await compactBox(boxName);

      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> handleMemoryPressure() async {
    try {
      await cleanupAllBoxes(maxAge: const Duration(days: 3));

      await compactAllBoxes();

      await _closeNonEssentialBoxes();

      debugPrint('[HiveManager] Memory pressure handling completed');
    } catch (e) {
      debugPrint('[HiveManager] Memory pressure handling error: $e');
    }
  }

  Future<void> _closeNonEssentialBoxes() async {
    final boxesToClose = <String>[];

    for (final boxName in _openBoxes.keys) {
      if (!_isCriticalBox(boxName)) {
        boxesToClose.add(boxName);
      }
    }

    for (final boxName in boxesToClose) {
      try {
        final box = _openBoxes[boxName];
        if (box != null) {
          await box.close();
          _openBoxes.remove(boxName);
        }
      } catch (e) {
        debugPrint('[HiveManager] Error closing box $boxName: $e');
      }
    }

    if (boxesToClose.isNotEmpty) {
      debugPrint('[HiveManager] Closed ${boxesToClose.length} non-essential boxes');
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
      'queuedBatches': _batchQueues.values.fold<int>(0, (sum, queue) => sum + queue.length),
    };
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _compactionTimer?.cancel();

    await flushAllBatches();

    for (final timer in _batchTimers.values) {
      timer.cancel();
    }
    _batchTimers.clear();

    for (final box in _openBoxes.values) {
      await box.close();
    }
    _openBoxes.clear();
    _pendingBoxes.clear();

    debugPrint('[HiveManager] Disposed successfully');
  }
}

enum _BatchOperationType { putAll, deleteAll }

class _BatchOperation {
  final _BatchOperationType type;
  final dynamic data;

  _BatchOperation._(this.type, this.data);

  factory _BatchOperation.putAll(Map<String, dynamic> items) {
    return _BatchOperation._(_BatchOperationType.putAll, items);
  }

  factory _BatchOperation.deleteAll(List<String> keys) {
    return _BatchOperation._(_BatchOperationType.deleteAll, keys);
  }
}
