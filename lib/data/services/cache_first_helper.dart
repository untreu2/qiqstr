import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/base/result.dart';

class CacheFirstHelper {
  static Future<T> getOrFetch<T>({
    required Future<T?> Function() getCached,
    required Future<T> Function() fetcher,
    required Future<void> Function(T) cachePut,
    String? cacheKey,
    Map<String, Completer<T>>? pendingRequests,
  }) async {
    final cached = await getCached();
    if (cached != null) {
      return cached;
    }

    if (pendingRequests != null && cacheKey != null) {
      if (pendingRequests.containsKey(cacheKey)) {
        debugPrint('[CacheFirstHelper] Deduplicating request for: $cacheKey');
        return await pendingRequests[cacheKey]!.future;
      }

      final completer = Completer<T>();
      pendingRequests[cacheKey] = completer;

      try {
        final result = await fetcher();
        await cachePut(result);
        completer.complete(result);
        return result;
      } catch (e) {
        completer.completeError(e);
        rethrow;
      } finally {
        pendingRequests.remove(cacheKey);
      }
    }

    final result = await fetcher();
    await cachePut(result);
    return result;
  }

  static Future<Result<T>> getCachedOrFetch<T>({
    required Future<T?> Function() getCached,
    required Future<Result<T>> Function() fetcher,
    required Future<void> Function(T) cachePut,
    String? cacheKey,
    Map<String, Completer<Result<T>>>? pendingRequests,
  }) async {
    final cached = await getCached();
    if (cached != null) {
      return Result.success(cached);
    }

    if (pendingRequests != null && cacheKey != null) {
      if (pendingRequests.containsKey(cacheKey)) {
        debugPrint('[CacheFirstHelper] Deduplicating request for: $cacheKey');
        return await pendingRequests[cacheKey]!.future;
      }

      final completer = Completer<Result<T>>();
      pendingRequests[cacheKey] = completer;

      try {
        final result = await fetcher();
        result.fold(
          (data) async => await cachePut(data),
          (_) {},
        );
        completer.complete(result);
        return result;
      } catch (e) {
        final errorResult = Result<T>.error(e.toString());
        completer.complete(errorResult);
        return errorResult;
      } finally {
        pendingRequests.remove(cacheKey);
      }
    }

    final result = await fetcher();
    result.fold(
      (data) async => await cachePut(data),
      (_) {},
    );
    return result;
  }
}

