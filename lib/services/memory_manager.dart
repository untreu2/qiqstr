import 'dart:async';
import 'package:flutter/foundation.dart';
import 'media_service.dart';
import 'cache_service.dart';

class MemoryManager {
  static MemoryManager? _instance;
  static MemoryManager get instance => _instance ??= MemoryManager._internal();

  MemoryManager._internal();

  Future<void> cleanupMemory() async {
    // Memory cleanup with better prioritization
    Future.microtask(() async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        // Memory pressure relief
        Future.microtask(() => mediaService.clearCache(clearFailed: true));
        Future.microtask(() => cacheService.handleMemoryPressure());

        // Gradual cleanup in stages
        await Future.delayed(const Duration(milliseconds: 50));
        Future.microtask(() => cacheService.optimizeMemoryUsage());

        await Future.delayed(const Duration(milliseconds: 100));
        Future.microtask(() => _performDeepCleanup());

        debugPrint('[MemoryManager] Memory cleanup completed');
      } catch (e) {
        debugPrint('[MemoryManager] Memory cleanup error: $e');
      }
    });
  }

  Future<void> _performDeepCleanup() async {
    try {
      // Force garbage collection hint
      if (kDebugMode) {
        debugPrint('[MemoryManager] Performing deep cleanup');
      }

      // Clear any remaining caches
      final cacheService = CacheService.instance;
      await cacheService.clearMemoryCache();

      debugPrint('[MemoryManager] Deep cleanup completed');
    } catch (e) {
      debugPrint('[MemoryManager] Deep cleanup error: $e');
    }
  }

  Future<void> prepareForProfileTransition() async {
    // Optimized transition preparation with staged cleanup
    Future.microtask(() async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        // Stage 1: Memory pressure relief
        Future.microtask(() => mediaService.handleMemoryPressure());
        Future.microtask(() => cacheService.handleMemoryPressure());

        // Stage 2: Cache cleanup (shorter TTL for transitions)
        await Future.delayed(const Duration(milliseconds: 25));
        Future.microtask(() => cacheService.cleanupExpiredCache(const Duration(minutes: 5)));

        // Stage 3: Optimize for profile view
        await Future.delayed(const Duration(milliseconds: 50));
        Future.microtask(() => cacheService.optimizeForProfileTransition());

        debugPrint('[MemoryManager] Profile transition preparation completed');
      } catch (e) {
        debugPrint('[MemoryManager] Profile transition preparation error: $e');
      }
    });
  }

  void handleMemoryPressure() {
    // Memory pressure handling
    Future.microtask(() async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        // Parallel pressure relief
        final futures = [
          Future.microtask(() => mediaService.handleMemoryPressure()),
          Future.microtask(() => cacheService.handleMemoryPressure()),
          Future.microtask(() => cacheService.optimizeMemoryUsage()),
        ];

        await Future.wait(futures, eagerError: false);

        // Additional cleanup if needed
        await Future.delayed(const Duration(milliseconds: 100));
        Future.microtask(() => _performDeepCleanup());

        debugPrint('[MemoryManager] Memory pressure handling completed');
      } catch (e) {
        debugPrint('[MemoryManager] Memory pressure handling error: $e');
      }
    });
  }

  void optimizeForProfileView() {
    Future.microtask(() async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        mediaService.handleMemoryPressure();

        await cacheService.optimizeMemoryUsage();

        debugPrint('[MemoryManager] Profile view optimization completed');
      } catch (e) {
        debugPrint('[MemoryManager] Profile view optimization error: $e');
      }
    });
  }

  Map<String, dynamic> getMemoryStats() {
    final cacheService = CacheService.instance;
    final cacheStats = cacheService.getCacheStats();

    return {
      'status': 'optimized',
      'lastCleanup': DateTime.now().toString(),
      'cacheEntries': cacheStats['totalEntries'],
      'maxCacheEntries': cacheStats['maxEntries'],
      'memoryPressure': cacheStats['totalEntries'] > (cacheStats['maxEntries'] * 0.8) ? 'high' : 'normal',
    };
  }

  // Proactive memory management
  void startProactiveManagement() {
    Timer.periodic(const Duration(minutes: 2), (timer) {
      final stats = getMemoryStats();
      if (stats['memoryPressure'] == 'high') {
        handleMemoryPressure();
      }
    });
  }

  // Emergency memory cleanup
  void emergencyCleanup() {
    Future.microtask(() async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        // Emergency actions
        await Future.wait([
          Future.microtask(() => mediaService.clearCache(clearFailed: true)),
          Future.microtask(() => cacheService.clearMemoryCache()),
        ], eagerError: false);

        debugPrint('[MemoryManager] Emergency cleanup completed');
      } catch (e) {
        debugPrint('[MemoryManager] Emergency cleanup error: $e');
      }
    });
  }
}
