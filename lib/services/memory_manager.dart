import 'dart:async';
import 'media_service.dart';
import 'cache_service.dart';
import 'time_service.dart';

class MemoryManager {
  static MemoryManager? _instance;
  static MemoryManager get instance => _instance ??= MemoryManager._internal();

  MemoryManager._internal();

  Future<void> cleanupMemory() async {
    Timer(const Duration(milliseconds: 100), () async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        mediaService.clearCache(clearFailed: true);
        await Future.delayed(const Duration(milliseconds: 100));

        cacheService.handleMemoryPressure();
        await Future.delayed(const Duration(milliseconds: 100));

        await cacheService.optimizeMemoryUsage();
        await Future.delayed(const Duration(milliseconds: 100));

        await _performDeepCleanup();
      } catch (e) {}
    });
  }

  Future<void> _performDeepCleanup() async {
    try {
      final cacheService = CacheService.instance;
      await cacheService.clearMemoryCache();
    } catch (e) {}
  }

  Future<void> prepareForProfileTransition() async {
    Future.microtask(() async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        Future.microtask(() => mediaService.handleMemoryPressure());
        Future.microtask(() => cacheService.handleMemoryPressure());

        await Future.delayed(const Duration(milliseconds: 25));
        Future.microtask(() => cacheService.cleanupExpiredCache(const Duration(minutes: 5)));

        await Future.delayed(const Duration(milliseconds: 50));
        Future.microtask(() => cacheService.optimizeForProfileTransition());
      } catch (e) {}
    });
  }

  void handleMemoryPressure() {
    Timer(const Duration(milliseconds: 50), () async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        mediaService.handleMemoryPressure();
        await Future.delayed(const Duration(milliseconds: 50));

        cacheService.handleMemoryPressure();
        await Future.delayed(const Duration(milliseconds: 50));

        await cacheService.optimizeMemoryUsage();
        await Future.delayed(const Duration(milliseconds: 100));

        await _performDeepCleanup();
      } catch (e) {}
    });
  }

  void optimizeForProfileView() {
    Future.microtask(() async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        mediaService.handleMemoryPressure();

        await cacheService.optimizeMemoryUsage();
      } catch (e) {}
    });
  }

  Map<String, dynamic> getMemoryStats() {
    final cacheService = CacheService.instance;
    final cacheStats = cacheService.getCacheStats();

    return {
      'status': 'optimized',
      'lastCleanup': timeService.now.toString(),
      'cacheEntries': cacheStats['totalEntries'],
      'maxCacheEntries': cacheStats['maxEntries'],
      'memoryPressure': cacheStats['totalEntries'] > (cacheStats['maxEntries'] * 0.8) ? 'high' : 'normal',
    };
  }

  void startProactiveManagement() {
    Timer.periodic(const Duration(minutes: 15), (timer) {
      final stats = getMemoryStats();
      if (stats['memoryPressure'] == 'high') {
        handleMemoryPressure();
      }
    });
  }

  void emergencyCleanup() {
    Future.microtask(() async {
      try {
        final mediaService = MediaService();
        final cacheService = CacheService.instance;

        await Future.wait([
          Future.microtask(() => mediaService.clearCache(clearFailed: true)),
          Future.microtask(() => cacheService.clearMemoryCache()),
        ], eagerError: false);
      } catch (e) {}
    });
  }
}
