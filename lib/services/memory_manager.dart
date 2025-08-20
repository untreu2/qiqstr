import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'hive_manager.dart';
import 'media_service.dart';
import 'cache_service.dart';

class MemoryManager {
  static MemoryManager? _instance;
  static MemoryManager get instance => _instance ??= MemoryManager._internal();

  MemoryManager._internal() {
    _startMemoryMonitoring();
  }

  Timer? _monitoringTimer;
  Timer? _cleanupTimer;

  // Memory thresholds (in MB) - Much more conservative for social media app
  static const double _warningThreshold = 300.0; // Increased from 150MB
  static const double _criticalThreshold = 400.0; // Increased from 200MB
  static const double _emergencyThreshold = 500.0; // Increased from 250MB

  // Monitoring intervals - Less frequent to avoid disrupting UX
  static const Duration _monitoringInterval = Duration(minutes: 5); // Increased from 2 minutes
  static const Duration _cleanupInterval = Duration(minutes: 15); // Increased from 5 minutes

  // Memory state
  MemoryPressureLevel _currentPressureLevel = MemoryPressureLevel.normal;
  double _lastKnownMemoryUsage = 0.0;
  int _consecutiveHighMemoryReadings = 0;

  // Callbacks for memory pressure events
  final List<VoidCallback> _memoryPressureCallbacks = [];

  void _startMemoryMonitoring() {
    // Monitor memory usage
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _checkMemoryUsage();
    });

    // Periodic cleanup
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performScheduledCleanup();
    });

    // Listen to system memory warnings
    _setupSystemMemoryWarnings();
  }

  void _setupSystemMemoryWarnings() {
    try {
      // Listen to system memory pressure events
      SystemChannels.lifecycle.setMessageHandler((message) async {
        if (message == AppLifecycleState.paused.toString()) {
          // App is going to background, good time for cleanup
          await _performBackgroundCleanup();
        }
        return null;
      });
    } catch (e) {
      debugPrint('[MemoryManager] Could not setup system memory warnings: $e');
    }
  }

  Future<void> _checkMemoryUsage() async {
    try {
      final memoryUsage = await _getMemoryUsage();
      _lastKnownMemoryUsage = memoryUsage;

      final previousLevel = _currentPressureLevel;
      _currentPressureLevel = _calculatePressureLevel(memoryUsage);

      // Track consecutive high memory readings
      if (_currentPressureLevel.index >= MemoryPressureLevel.warning.index) {
        _consecutiveHighMemoryReadings++;
      } else {
        _consecutiveHighMemoryReadings = 0;
      }

      // Handle pressure level changes
      if (_currentPressureLevel != previousLevel) {
        await _handlePressureLevelChange(previousLevel, _currentPressureLevel);
      }

      // Emergency cleanup if memory is consistently high - but be conservative
      if (_consecutiveHighMemoryReadings >= 5) {
        // Increased from 3 to 5
        await _performEmergencyCleanup();
        _consecutiveHighMemoryReadings = 0;
      }
    } catch (e) {
      debugPrint('[MemoryManager] Memory check error: $e');
    }
  }

  Future<double> _getMemoryUsage() async {
    try {
      // Get memory usage from ProcessInfo (iOS/Android)
      final info = ProcessInfo.currentRss;
      return info / (1024 * 1024); // Convert to MB
    } catch (e) {
      // Fallback estimation based on cache sizes
      return _estimateMemoryUsage();
    }
  }

  double _estimateMemoryUsage() {
    try {
      // Estimate memory usage based on cache sizes
      double estimated = 50.0; // Base app memory

      // Add Hive memory usage estimation
      final hiveStats = HiveManager.instance.getMemoryStats();
      final totalEntries = hiveStats['totalEntries'] as int? ?? 0;
      estimated += (totalEntries * 0.001); // Rough estimation: 1KB per entry

      // Add media cache estimation
      final mediaService = MediaService();
      final mediaStats = mediaService.getCacheStats();
      final cachedUrls = mediaStats['cachedUrls'] as int? ?? 0;
      estimated += (cachedUrls * 0.1); // Rough estimation: 100KB per cached image

      return estimated;
    } catch (e) {
      return 100.0; // Conservative fallback
    }
  }

  MemoryPressureLevel _calculatePressureLevel(double memoryUsage) {
    if (memoryUsage >= _emergencyThreshold) {
      return MemoryPressureLevel.emergency;
    } else if (memoryUsage >= _criticalThreshold) {
      return MemoryPressureLevel.critical;
    } else if (memoryUsage >= _warningThreshold) {
      return MemoryPressureLevel.warning;
    } else {
      return MemoryPressureLevel.normal;
    }
  }

  Future<void> _handlePressureLevelChange(MemoryPressureLevel previous, MemoryPressureLevel current) async {
    debugPrint('[MemoryManager] Memory pressure changed: ${previous.name} -> ${current.name}');

    switch (current) {
      case MemoryPressureLevel.warning:
        await _performLightCleanup();
        break;
      case MemoryPressureLevel.critical:
        await _performMediumCleanup();
        break;
      case MemoryPressureLevel.emergency:
        await _performEmergencyCleanup();
        break;
      case MemoryPressureLevel.normal:
        // Memory pressure relieved
        break;
    }

    // Notify callbacks
    for (final callback in _memoryPressureCallbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('[MemoryManager] Callback error: $e');
      }
    }
  }

  Future<void> _performScheduledCleanup() async {
    if (_currentPressureLevel == MemoryPressureLevel.normal) {
      // Only perform light maintenance cleanup when memory is normal
      await _performMaintenanceCleanup();
    }
  }

  Future<void> _performMaintenanceCleanup() async {
    try {
      // Light cleanup for maintenance
      final cacheService = CacheService();
      await cacheService.optimizeMemoryUsage();

      debugPrint('[MemoryManager] Maintenance cleanup completed');
    } catch (e) {
      debugPrint('[MemoryManager] Maintenance cleanup error: $e');
    }
  }

  Future<void> _performLightCleanup() async {
    try {
      // ONLY clear failed/expired media cache - preserve UI data
      final mediaService = MediaService();
      mediaService.clearCache(clearFailed: true); // Only clear failed items

      // Gentle optimization without clearing critical data
      final cacheService = CacheService();
      await cacheService.optimizeMemoryUsage();

      debugPrint('[MemoryManager] Light cleanup completed (non-aggressive)');
    } catch (e) {
      debugPrint('[MemoryManager] Light cleanup error: $e');
    }
  }

  Future<void> _performMediumCleanup() async {
    try {
      // Conservative cleanup - preserve UI interactions data
      await _performLightCleanup();

      // Only compact Hive boxes, don't clear them
      final hiveManager = HiveManager.instance;
      await hiveManager.compactAllBoxes();

      // DO NOT clear memory cache - this removes reactions/interactions!
      // Instead, only optimize without clearing critical UI data
      final cacheService = CacheService();
      await cacheService.optimizeMemoryUsage();

      debugPrint('[MemoryManager] Medium cleanup completed (preserving UI data)');
    } catch (e) {
      debugPrint('[MemoryManager] Medium cleanup error: $e');
    }
  }

  Future<void> _performEmergencyCleanup() async {
    try {
      // Even in emergency, protect critical UI data
      await _performMediumCleanup();

      // Handle memory pressure in services but preserve UI interactions
      final hiveManager = HiveManager.instance;
      await hiveManager.handleMemoryPressure();

      final mediaService = MediaService();
      mediaService.handleMemoryPressure();

      // Log warning instead of aggressive cleanup
      debugPrint('[MemoryManager] Emergency cleanup - preserving UI interactions data');

      // Force garbage collection only in debug
      if (!kReleaseMode) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      debugPrint('[MemoryManager] Emergency cleanup completed (UI data preserved)');
    } catch (e) {
      debugPrint('[MemoryManager] Emergency cleanup error: $e');
    }
  }

  Future<void> _performBackgroundCleanup() async {
    try {
      // App is going to background - ONLY light cleanup to preserve state
      await _performLightCleanup();

      debugPrint('[MemoryManager] Background cleanup completed (light only)');
    } catch (e) {
      debugPrint('[MemoryManager] Background cleanup error: $e');
    }
  }

  // Public API
  void addMemoryPressureCallback(VoidCallback callback) {
    _memoryPressureCallbacks.add(callback);
  }

  void removeMemoryPressureCallback(VoidCallback callback) {
    _memoryPressureCallbacks.remove(callback);
  }

  MemoryPressureLevel get currentPressureLevel => _currentPressureLevel;

  double get lastKnownMemoryUsage => _lastKnownMemoryUsage;

  bool get isUnderMemoryPressure => _currentPressureLevel.index >= MemoryPressureLevel.warning.index;

  Map<String, dynamic> getMemoryStats() {
    return {
      'currentPressureLevel': _currentPressureLevel.name,
      'lastKnownMemoryUsage': _lastKnownMemoryUsage,
      'consecutiveHighReadings': _consecutiveHighMemoryReadings,
      'thresholds': {
        'warning': _warningThreshold,
        'critical': _criticalThreshold,
        'emergency': _emergencyThreshold,
      },
      'isUnderPressure': isUnderMemoryPressure,
    };
  }

  // Manual cleanup methods
  Future<void> forceCleanup({MemoryPressureLevel level = MemoryPressureLevel.warning}) async {
    switch (level) {
      case MemoryPressureLevel.normal:
        await _performMaintenanceCleanup();
        break;
      case MemoryPressureLevel.warning:
        await _performLightCleanup();
        break;
      case MemoryPressureLevel.critical:
        await _performMediumCleanup();
        break;
      case MemoryPressureLevel.emergency:
        await _performEmergencyCleanup();
        break;
    }
  }

  void dispose() {
    _monitoringTimer?.cancel();
    _cleanupTimer?.cancel();
    _memoryPressureCallbacks.clear();
    debugPrint('[MemoryManager] Disposed');
  }
}

enum MemoryPressureLevel {
  normal,
  warning,
  critical,
  emergency,
}

extension MemoryPressureLevelExtension on MemoryPressureLevel {
  String get name {
    switch (this) {
      case MemoryPressureLevel.normal:
        return 'normal';
      case MemoryPressureLevel.warning:
        return 'warning';
      case MemoryPressureLevel.critical:
        return 'critical';
      case MemoryPressureLevel.emergency:
        return 'emergency';
    }
  }
}
