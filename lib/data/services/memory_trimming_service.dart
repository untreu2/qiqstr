import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../../core/di/app_di.dart';
import '../repositories/note_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/user_repository.dart';
import 'lifecycle_manager.dart';

class MemoryTrimmingService {
  static final MemoryTrimmingService _instance =
      MemoryTrimmingService._internal();
  factory MemoryTrimmingService() => _instance;
  MemoryTrimmingService._internal();

  bool _isTrimmingMemory = false;
  bool _isRunning = false;
  DateTime? _lastTrimTime;

  static const Duration trimmingInterval = Duration(minutes: 5);
  static const Duration noteRetentionPeriod = Duration(days: 7);
  static const Duration notificationRetentionPeriod = Duration(days: 14);
  static const int maxCachedUsers = 500;
  static const int maxCachedNotes = 150000;

  void startPeriodicTrimming() {
    if (_isRunning) return;

    _isRunning = true;

    Future.delayed(const Duration(seconds: 30), () {
      trimMemory();
    });

    _runTrimmingLoop();
    LifecycleManager().addOnResumeCallback(_onAppResumed);
  }

  Future<void> _runTrimmingLoop() async {
    while (_isRunning) {
      await Future.delayed(trimmingInterval);

      if (!_isRunning) break;

      if (!LifecycleManager().isAppInForeground) {
        debugPrint('[MemoryTrimming] Skipping trim - app in background');
        continue;
      }

      if (kDebugMode) {
        debugPrint('[MemoryTrimming] Starting periodic memory trim');
      }
      trimMemory();
    }
  }

  void _onAppResumed() {
    debugPrint('[MemoryTrimming] App resumed - running immediate trim');
    Future.delayed(const Duration(seconds: 2), () {
      trimMemory();
    });
  }

  void stopPeriodicTrimming() {
    _isRunning = false;
  }

  Future<void> trimMemory() async {
    if (_isTrimmingMemory) {
      debugPrint('[MemoryTrimming] Already trimming, skipping');
      return;
    }

    _isTrimmingMemory = true;
    final startTime = DateTime.now();

    try {
      debugPrint('[MemoryTrimming] Starting memory trim cycle');

      await _pruneOldCachedData();
      await _cleanupImageCache();
      await _pruneUserCache();
      await _pruneNotificationCache();

      _lastTrimTime = DateTime.now();
      final duration = _lastTrimTime!.difference(startTime);

      debugPrint(
          '[MemoryTrimming] Memory trim completed in ${duration.inMilliseconds}ms');
    } catch (e) {
      debugPrint('[MemoryTrimming] Error during memory trim: $e');
    } finally {
      _isTrimmingMemory = false;
    }
  }

  Future<void> _pruneOldCachedData() async {
    try {
      debugPrint(
          '[MemoryTrimming] Pruning old cached notes and limiting cache size');

      final noteRepository = AppDI.get<NoteRepository>();

      final pruneResult =
          await noteRepository.pruneOldNotes(noteRetentionPeriod);
      pruneResult.fold(
        (removedCount) {
          if (removedCount > 0) {
            debugPrint('[MemoryTrimming] Removed $removedCount old notes');
          }
        },
        (error) => debugPrint('[MemoryTrimming] Error pruning notes: $error'),
      );

      final limitResult =
          await noteRepository.pruneCacheToLimit(maxCachedNotes);
      limitResult.fold(
        (removedCount) {
          if (removedCount > 0) {
            debugPrint(
                '[MemoryTrimming] Removed $removedCount notes to stay under limit');
          }
        },
        (error) => debugPrint('[MemoryTrimming] Error limiting cache: $error'),
      );
    } catch (e) {
      debugPrint('[MemoryTrimming] Error pruning old data: $e');
    }
  }

  Future<void> _cleanupImageCache() async {
    try {
      debugPrint('[MemoryTrimming] Cleaning up image cache');

      final PaintingBinding binding = PaintingBinding.instance;
      final imageCache = binding.imageCache;

      final currentSize = imageCache.currentSizeBytes;
      final maxSize = imageCache.maximumSizeBytes;

      if (currentSize > (maxSize * 0.8)) {
        debugPrint(
            '[MemoryTrimming] Image cache is ${(currentSize / maxSize * 100).toStringAsFixed(1)}% full, clearing');
        imageCache.clear();
        imageCache.clearLiveImages();
      } else {
        debugPrint(
            '[MemoryTrimming] Image cache size: ${(currentSize / (1024 * 1024)).toStringAsFixed(2)}MB / ${(maxSize / (1024 * 1024)).toStringAsFixed(2)}MB');
      }
    } catch (e) {
      debugPrint('[MemoryTrimming] Error cleaning image cache: $e');
    }
  }

  Future<void> _pruneUserCache() async {
    try {
      final userRepository = AppDI.get<UserRepository>();
      final cacheSize = await userRepository.getCachedUserCount();
      debugPrint('[MemoryTrimming] User cache size: $cacheSize profiles');
    } catch (e) {
      debugPrint('[MemoryTrimming] Error checking user cache: $e');
    }
  }

  Future<void> _pruneNotificationCache() async {
    try {
      final cutoffTime = DateTime.now().subtract(notificationRetentionPeriod);
      debugPrint(
          '[MemoryTrimming] Pruning notifications older than $cutoffTime');

      final notificationRepository = AppDI.get<NotificationRepository>();
      final pruned = await notificationRepository
          .pruneOldNotifications(notificationRetentionPeriod);

      pruned.fold(
        (count) {
          if (count > 0) {
            debugPrint('[MemoryTrimming] Removed $count old notifications');
          }
        },
        (error) =>
            debugPrint('[MemoryTrimming] Error pruning notifications: $error'),
      );
    } catch (e) {
      debugPrint('[MemoryTrimming] Error pruning notifications: $e');
    }
  }

  void dispose() {
    stopPeriodicTrimming();
  }

  DateTime? get lastTrimTime => _lastTrimTime;
  bool get isTrimmingMemory => _isTrimmingMemory;
}
