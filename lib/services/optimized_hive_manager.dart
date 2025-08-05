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

class OptimizedHiveManager {
  static OptimizedHiveManager? _instance;
  static OptimizedHiveManager get instance => _instance ??= OptimizedHiveManager._internal();

  OptimizedHiveManager._internal();

  // Batch operation queues
  final Map<String, List<_BatchOperation>> _batchQueues = {};
  final Map<String, Timer> _batchTimers = {};
  final Duration _batchDelay = const Duration(milliseconds: 100);
  final int _maxBatchSize = 50;

  // Connection pool
  final Map<String, Box> _openBoxes = {};
  final Set<String> _pendingBoxes = {};

  bool _isInitialized = false;

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
      // Wait for pending box to open
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

  // Batch operations
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

    // Cancel existing timer
    _batchTimers[boxName]?.cancel();

    // Start new timer or execute immediately if batch is full
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

      // Group operations by type for efficiency
      final putOperations = <String, dynamic>{};
      final deleteKeys = <String>[];

      for (final op in operations) {
        if (op.type == _BatchOperationType.putAll) {
          putOperations.addAll(op.data as Map<String, dynamic>);
        } else if (op.type == _BatchOperationType.deleteAll) {
          deleteKeys.addAll(op.data as List<String>);
        }
      }

      // Execute batch operations
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

  // Optimized queries
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

  // Cache management
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

  // Cleanup old data
  Future<void> cleanupOldData(String boxName, Duration maxAge) async {
    try {
      final box = await getBox(boxName);
      final cutoffTime = DateTime.now().subtract(maxAge);
      final keysToDelete = <String>[];

      for (final key in box.keys) {
        final value = box.get(key);
        DateTime? timestamp;

        // Extract timestamp based on model type
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

  // Force flush all pending batches
  Future<void> flushAllBatches() async {
    final futures = _batchQueues.keys.map((boxName) => _executeBatch(boxName));
    await Future.wait(futures);
  }

  // Statistics
  Map<String, dynamic> getStats() {
    return {
      'openBoxes': _openBoxes.length,
      'pendingBoxes': _pendingBoxes.length,
      'queuedBatches': _batchQueues.values.fold<int>(0, (sum, queue) => sum + queue.length),
      'activeBatchTimers': _batchTimers.length,
      'isInitialized': _isInitialized,
    };
  }

  Future<void> dispose() async {
    // Flush all pending batches
    await flushAllBatches();

    // Cancel all timers
    for (final timer in _batchTimers.values) {
      timer.cancel();
    }
    _batchTimers.clear();

    // Close all boxes
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
