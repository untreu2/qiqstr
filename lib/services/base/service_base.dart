import 'dart:async';

import 'package:flutter/foundation.dart';

abstract class ServiceBase {
  bool get isInitialized;
  bool get isClosed;

  Future<void> initialize();
  Future<void> close();
}

abstract class LifecycleService implements ServiceBase {
  bool _isInitialized = false;
  bool _isClosed = false;
  final List<StreamSubscription> _subscriptions = [];
  final List<Timer> _timers = [];

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> initialize() async {
    if (_isInitialized || _isClosed) return;

    try {
      await onInitialize();
      _isInitialized = true;
    } catch (e) {
      await onInitializeError(e);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      await Future.wait([
        ..._subscriptions.map((sub) => sub.cancel()),
        Future.wait(_timers.map((timer) async {
          timer.cancel();
        })),
      ]);

      _subscriptions.clear();
      _timers.clear();

      await onClose();
    } catch (e) {
      await onCloseError(e);
    }
  }

  Future<void> onInitialize();

  Future<void> onClose();

  Future<void> onInitializeError(Object error) async {
    if (kDebugMode) {
      print('[$runtimeType] Initialization error: $error');
    }
  }

  Future<void> onCloseError(Object error) async {
    if (kDebugMode) {
      print('[$runtimeType] Close error: $error');
    }
  }

  void addSubscription(StreamSubscription subscription) {
    if (!_isClosed) {
      _subscriptions.add(subscription);
    }
  }

  void addTimer(Timer timer) {
    if (!_isClosed) {
      _timers.add(timer);
    }
  }

  void ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('Service $runtimeType is not initialized');
    }
    if (_isClosed) {
      throw StateError('Service $runtimeType is closed');
    }
  }
}

mixin BatchProcessingMixin<T> {
  final List<T> _batchQueue = [];
  Timer? _batchTimer;
  bool _isProcessing = false;

  int get maxBatchSize => 50;
  Duration get batchTimeout => const Duration(milliseconds: 100);

  void addToBatch(T item) {
    if (_batchQueue.length >= maxBatchSize) {
      _flushBatch();
    } else {
      _batchQueue.add(item);
      _scheduleBatchFlush();
    }
  }

  void _scheduleBatchFlush() {
    _batchTimer?.cancel();
    _batchTimer = Timer(batchTimeout, _flushBatch);
  }

  void _flushBatch() {
    if (_isProcessing || _batchQueue.isEmpty) return;

    _isProcessing = true;
    _batchTimer?.cancel();

    final batch = List<T>.from(_batchQueue);
    _batchQueue.clear();

    Future.microtask(() async {
      try {
        await processBatch(batch);
      } finally {
        _isProcessing = false;

        if (_batchQueue.isNotEmpty) {
          _scheduleBatchFlush();
        }
      }
    });
  }

  Future<void> processBatch(List<T> batch);

  void clearBatch() {
    _batchTimer?.cancel();
    _batchQueue.clear();
    _isProcessing = false;
  }
}

mixin CachingMixin<K, V> {
  final Map<K, V> _cache = {};
  final Map<K, DateTime> _cacheTimestamps = {};

  Duration get cacheTTL => const Duration(minutes: 30);
  int get maxCacheSize => 1000;

  V? getCached(K key) {
    final cached = _cache[key];
    final timestamp = _cacheTimestamps[key];

    if (cached != null && timestamp != null) {
      if (DateTime.now().difference(timestamp) < cacheTTL) {
        return cached;
      } else {
        _cache.remove(key);
        _cacheTimestamps.remove(key);
      }
    }

    return null;
  }

  void putCache(K key, V value) {
    _cache[key] = value;
    _cacheTimestamps[key] = DateTime.now();

    if (_cache.length > maxCacheSize) {
      _cleanupCache();
    }
  }

  void removeFromCache(K key) {
    _cache.remove(key);
    _cacheTimestamps.remove(key);
  }

  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  void _cleanupCache() {
    final now = DateTime.now();
    final expiredKeys = <K>[];

    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > cacheTTL) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }

    if (_cache.length > maxCacheSize) {
      final sortedEntries = _cacheTimestamps.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

      final toRemove = sortedEntries.take(_cache.length - maxCacheSize);
      for (final entry in toRemove) {
        _cache.remove(entry.key);
        _cacheTimestamps.remove(entry.key);
      }
    }
  }

  Map<String, dynamic> getCacheStats() {
    return {
      'size': _cache.length,
      'maxSize': maxCacheSize,
      'ttl': cacheTTL.inMinutes,
    };
  }
}

mixin RetryMixin {
  Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration delay = const Duration(seconds: 1),
    bool Function(Object error)? shouldRetry,
  }) async {
    Object? lastError;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;

        if (attempt == maxAttempts || (shouldRetry != null && !shouldRetry(error))) {
          rethrow;
        }

        await Future.delayed(delay * attempt);
      }
    }

    throw lastError!;
  }
}

mixin PerformanceMonitoringMixin {
  final Map<String, List<Duration>> _operationTimes = {};
  final Map<String, int> _operationCounts = {};

  Future<T> measureOperation<T>(
    String operationName,
    Future<T> Function() operation,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await operation();
      return result;
    } finally {
      stopwatch.stop();
      _recordOperation(operationName, stopwatch.elapsed);
    }
  }

  void _recordOperation(String operationName, Duration duration) {
    _operationTimes.putIfAbsent(operationName, () => []);
    _operationCounts.putIfAbsent(operationName, () => 0);

    _operationTimes[operationName]!.add(duration);
    _operationCounts[operationName] = _operationCounts[operationName]! + 1;

    if (_operationTimes[operationName]!.length > 100) {
      _operationTimes[operationName]!.removeAt(0);
    }
  }

  Map<String, dynamic> getPerformanceStats() {
    final stats = <String, dynamic>{};

    for (final operation in _operationTimes.keys) {
      final times = _operationTimes[operation]!;
      final count = _operationCounts[operation]!;

      if (times.isNotEmpty) {
        final totalMs = times.fold<int>(0, (sum, duration) => sum + duration.inMilliseconds);
        final avgMs = totalMs / times.length;
        final minMs = times.map((d) => d.inMilliseconds).reduce((a, b) => a < b ? a : b);
        final maxMs = times.map((d) => d.inMilliseconds).reduce((a, b) => a > b ? a : b);

        stats[operation] = {
          'count': count,
          'avgMs': avgMs.round(),
          'minMs': minMs,
          'maxMs': maxMs,
          'totalMs': totalMs,
        };
      }
    }

    return stats;
  }

  void clearPerformanceStats() {
    _operationTimes.clear();
    _operationCounts.clear();
  }
}
