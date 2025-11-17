import 'dart:async';
import 'package:flutter/foundation.dart';

class AsyncHelper {
  static Future<T?> executeWithTimeout<T>(
    Future<T> future, {
    required Duration timeout,
    T? Function()? onTimeout,
    String? debugPrefix,
  }) async {
    try {
      return await future.timeout(
        timeout,
        onTimeout: () {
          if (debugPrefix != null) {
            debugPrint('[$debugPrefix] Operation timed out after ${timeout.inSeconds}s');
          }
          final result = onTimeout?.call();
          if (result != null) {
            return result;
          }
          throw TimeoutException('Operation timed out after ${timeout.inSeconds}s');
        },
      );
    } on TimeoutException {
      return onTimeout?.call();
    } catch (e) {
      if (debugPrefix != null) {
        debugPrint('[$debugPrefix] Error: $e');
      }
      return null;
    }
  }

  static Future<void> executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
    bool Function(dynamic error)? shouldRetry,
    void Function(int attempt, dynamic error)? onRetry,
    String? debugPrefix,
  }) async {
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        await operation();
        return;
      } catch (e) {
        attempt++;

        if (shouldRetry != null && !shouldRetry(e)) {
          rethrow;
        }

        if (attempt >= maxRetries) {
          if (debugPrefix != null) {
            debugPrint('[$debugPrefix] Failed after $maxRetries attempts: $e');
          }
          rethrow;
        }

        onRetry?.call(attempt, e);

        if (debugPrefix != null) {
          debugPrint('[$debugPrefix] Retry attempt $attempt/$maxRetries after ${delay.inMilliseconds}ms');
        }

        await Future.delayed(delay);
      }
    }
  }

  static Future<List<T>> executeParallel<T>(
    List<Future<T>> futures, {
    bool failFast = false,
    T? Function(dynamic error)? onError,
  }) async {
    if (failFast) {
      return await Future.wait(futures);
    }

    final results = await Future.wait(
      futures.map((future) => future.catchError((error) {
        if (onError != null) {
          final result = onError(error);
          if (result != null) {
            return result;
          }
        }
        throw error;
      })),
      eagerError: false,
    );

    return results.whereType<T>().toList();
  }

  static void debounce(
    VoidCallback callback, {
    required Duration duration,
    Timer? existingTimer,
  }) {
    existingTimer?.cancel();
    Timer(duration, callback);
  }

  static Timer debounceWithTimer(
    VoidCallback callback, {
    required Duration duration,
    Timer? existingTimer,
  }) {
    existingTimer?.cancel();
    return Timer(duration, callback);
  }
}

