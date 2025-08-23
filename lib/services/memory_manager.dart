import 'package:flutter/foundation.dart';
import 'media_service.dart';
import 'cache_service.dart';

class MemoryManager {
  static MemoryManager? _instance;
  static MemoryManager get instance => _instance ??= MemoryManager._internal();

  MemoryManager._internal();

  Future<void> cleanupMemory() async {
    try {
      final mediaService = MediaService();
      mediaService.clearCache(clearFailed: true);

      final cacheService = CacheService();
      await cacheService.optimizeMemoryUsage();

      debugPrint('[MemoryManager] Memory cleanup completed');
    } catch (e) {
      debugPrint('[MemoryManager] Memory cleanup error: $e');
    }
  }

  void handleMemoryPressure() {
    cleanupMemory();
  }

  Map<String, dynamic> getMemoryStats() {
    return {
      'status': 'simplified',
      'lastCleanup': DateTime.now().toString(),
    };
  }
}
