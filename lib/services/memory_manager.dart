import 'package:flutter/foundation.dart';
import 'media_service.dart';
import 'cache_service.dart';

class MemoryManager {
  static MemoryManager? _instance;
  static MemoryManager get instance => _instance ??= MemoryManager._internal();

  MemoryManager._internal();

  Future<void> cleanupMemory() async {
    Future.microtask(() async {
      try {
        final mediaService = MediaService();

        Future.microtask(() => mediaService.clearCache(clearFailed: true));

        await Future.delayed(Duration.zero);

        final cacheService = CacheService.instance;
        await cacheService.optimizeMemoryUsage();

        debugPrint('[MemoryManager] Memory cleanup completed');
      } catch (e) {
        debugPrint('[MemoryManager] Memory cleanup error: $e');
      }
    });
  }

  Future<void> prepareForProfileTransition() async {
    Future.microtask(() async {
      try {
        final mediaService = MediaService();

        mediaService.handleMemoryPressure();

        final cacheService = CacheService.instance;

        await cacheService.handleMemoryPressure();

        cacheService.cleanupExpiredCache(const Duration(minutes: 15));

        debugPrint('[MemoryManager] Profile transition preparation completed');
      } catch (e) {
        debugPrint('[MemoryManager] Profile transition preparation error: $e');
      }
    });
  }

  void handleMemoryPressure() {
    Future.microtask(() async {
      try {
        final mediaService = MediaService();

        mediaService.handleMemoryPressure();

        await Future.delayed(Duration.zero);

        final cacheService = CacheService.instance;
        Future.microtask(() => cacheService.optimizeMemoryUsage());

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
    return {
      'status': 'simplified',
      'lastCleanup': DateTime.now().toString(),
    };
  }
}
