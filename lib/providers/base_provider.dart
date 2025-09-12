import 'dart:async';
import 'package:flutter/foundation.dart';

/// Base provider class with common optimization patterns
abstract class BaseProvider extends ChangeNotifier {
  bool _isDisposed = false;
  final List<Timer> _timers = [];
  final List<StreamSubscription> _subscriptions = [];

  bool get isDisposed => _isDisposed;

  /// Register a timer for automatic cleanup
  void registerTimer(Timer timer) {
    if (!_isDisposed) {
      _timers.add(timer);
    }
  }

  /// Register a stream subscription for automatic cleanup
  void registerSubscription(StreamSubscription subscription) {
    if (!_isDisposed) {
      _subscriptions.add(subscription);
    }
  }

  /// Create a periodic timer with automatic registration
  Timer createPeriodicTimer(Duration duration, void Function(Timer) callback) {
    final timer = Timer.periodic(duration, callback);
    registerTimer(timer);
    return timer;
  }

  /// Create a single-shot timer with automatic registration
  Timer createTimer(Duration duration, void Function() callback) {
    final timer = Timer(duration, callback);
    registerTimer(timer);
    return timer;
  }

  /// Safe notifyListeners that checks if disposed
  void safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Handle errors with consistent logging
  void handleError(String operation, dynamic error, [StackTrace? stackTrace]) {
    debugPrint('[$runtimeType] Error in $operation: $error');
    if (stackTrace != null && kDebugMode) {
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Debounced notification helper
  Timer? _notificationTimer;
  void debouncedNotify([Duration delay = const Duration(milliseconds: 16)]) {
    _notificationTimer?.cancel();
    _notificationTimer = Timer(delay, () {
      if (!_isDisposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Cancel all timers
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();

    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Cancel notification timer
    _notificationTimer?.cancel();

    super.dispose();
  }
}

/// Mixin for providers that need caching functionality
mixin CacheMixin<T> {
  T? _cachedData;
  int _cacheVersion = 0;
  int _lastDataVersion = -1;

  /// Get cached data or compute if needed
  T getCachedData(int currentVersion, T Function() computeData) {
    if (_cachedData == null || _lastDataVersion != currentVersion) {
      _cachedData = computeData();
      _lastDataVersion = currentVersion;
    }
    return _cachedData!;
  }

  /// Invalidate cache
  void invalidateCache() {
    _cachedData = null;
    _cacheVersion++;
  }

  /// Clear cache
  void clearCache() {
    _cachedData = null;
    _lastDataVersion = -1;
  }
}

/// Helper for batch operations
class BatchOperationHelper {
  static const int defaultBatchSize = 50;

  /// Process items in batches to avoid blocking the UI
  static Future<void> processBatch<T>(
    List<T> items,
    Future<void> Function(List<T>) processor, {
    int batchSize = defaultBatchSize,
    Duration delay = const Duration(microseconds: 100),
  }) async {
    for (int i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      final batch = items.sublist(i, end);

      await processor(batch);

      // Small delay to prevent blocking the UI
      if (end < items.length) {
        await Future.delayed(delay);
      }
    }
  }
}
