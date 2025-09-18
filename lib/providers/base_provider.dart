import 'dart:async';
import 'package:flutter/foundation.dart';

abstract class BaseProvider extends ChangeNotifier {
  bool _isDisposed = false;
  final List<Timer> _timers = [];
  final List<StreamSubscription> _subscriptions = [];

  bool get isDisposed => _isDisposed;

  void registerTimer(Timer timer) {
    if (!_isDisposed) {
      _timers.add(timer);
    }
  }

  void registerSubscription(StreamSubscription subscription) {
    if (!_isDisposed) {
      _subscriptions.add(subscription);
    }
  }

  Timer createPeriodicTimer(Duration duration, void Function(Timer) callback) {
    final timer = Timer.periodic(duration, callback);
    registerTimer(timer);
    return timer;
  }

  Timer createTimer(Duration duration, void Function() callback) {
    final timer = Timer(duration, callback);
    registerTimer(timer);
    return timer;
  }

  void safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void handleError(String operation, dynamic error, [StackTrace? stackTrace]) {
    debugPrint('[$runtimeType] Error in $operation: $error');
    if (stackTrace != null && kDebugMode) {
      debugPrint('Stack trace: $stackTrace');
    }
  }

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

    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();

    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    _notificationTimer?.cancel();

    super.dispose();
  }
}

mixin CacheMixin<T> {
  T? _cachedData;
  int _lastDataVersion = -1;

  T getCachedData(int currentVersion, T Function() computeData) {
    if (_cachedData == null || _lastDataVersion != currentVersion) {
      _cachedData = computeData();
      _lastDataVersion = currentVersion;
    }
    return _cachedData!;
  }

  void invalidateCache() {
    _cachedData = null;
  }

  void clearCache() {
    _cachedData = null;
    _lastDataVersion = -1;
  }
}

class BatchOperationHelper {
  static const int defaultBatchSize = 50;

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

      if (end < items.length) {
        await Future.delayed(delay);
      }
    }
  }
}
