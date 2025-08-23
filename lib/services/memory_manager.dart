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

  MemoryManager._internal() {}

  Timer? _monitoringTimer;
  Timer? _cleanupTimer;

  static const double _warningThreshold = 500.0;
  static const double _criticalThreshold = 1000.0;
  static const double _emergencyThreshold = 2000.0;

  static const Duration _monitoringInterval = Duration(minutes: 5);
  static const Duration _cleanupInterval = Duration(minutes: 15);

  MemoryPressureLevel _currentPressureLevel = MemoryPressureLevel.normal;
  double _lastKnownMemoryUsage = 0.0;
  int _consecutiveHighMemoryReadings = 0;

  final List<VoidCallback> _memoryPressureCallbacks = [];

  void _startMemoryMonitoring() {
    if (_monitoringTimer != null) return;

    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _checkMemoryUsage();
    });

    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performScheduledCleanup();
    });

    _setupSystemMemoryWarnings();
  }

  void _ensureInitialized() {
    if (_monitoringTimer == null) {
      Future.delayed(const Duration(seconds: 10), () {
        _startMemoryMonitoring();
      });
    }
  }

  void _setupSystemMemoryWarnings() {
    try {
      SystemChannels.lifecycle.setMessageHandler((message) async {
        if (message == AppLifecycleState.paused.toString()) {
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

      if (_currentPressureLevel.index >= MemoryPressureLevel.warning.index) {
        _consecutiveHighMemoryReadings++;
      } else {
        _consecutiveHighMemoryReadings = 0;
      }

      if (_currentPressureLevel != previousLevel) {
        await _handlePressureLevelChange(previousLevel, _currentPressureLevel);
      }

      if (_consecutiveHighMemoryReadings >= 5) {
        await _performEmergencyCleanup();
        _consecutiveHighMemoryReadings = 0;
      }
    } catch (e) {
      debugPrint('[MemoryManager] Memory check error: $e');
    }
  }

  Future<double> _getMemoryUsage() async {
    try {
      final info = ProcessInfo.currentRss;
      return info / (1024 * 1024);
    } catch (e) {
      return _estimateMemoryUsage();
    }
  }

  double _estimateMemoryUsage() {
    try {
      double estimated = 50.0;

      final hiveStats = HiveManager.instance.getMemoryStats();
      final totalEntries = hiveStats['totalEntries'] as int? ?? 0;
      estimated += (totalEntries * 0.001);

      final mediaService = MediaService();
      final mediaStats = mediaService.getCacheStats();
      final cachedUrls = mediaStats['cachedUrls'] as int? ?? 0;
      estimated += (cachedUrls * 0.1);

      return estimated;
    } catch (e) {
      return 100.0;
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
        break;
    }

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
      await _performMaintenanceCleanup();
    }
  }

  Future<void> _performMaintenanceCleanup() async {
    try {
      final cacheService = CacheService();
      await cacheService.optimizeMemoryUsage();

      debugPrint('[MemoryManager] Maintenance cleanup completed');
    } catch (e) {
      debugPrint('[MemoryManager] Maintenance cleanup error: $e');
    }
  }

  Future<void> _performLightCleanup() async {
    try {
      final mediaService = MediaService();
      mediaService.clearCache(clearFailed: true);

      final cacheService = CacheService();
      await cacheService.optimizeMemoryUsage();

      debugPrint('[MemoryManager] Light cleanup completed (non-aggressive)');
    } catch (e) {
      debugPrint('[MemoryManager] Light cleanup error: $e');
    }
  }

  Future<void> _performMediumCleanup() async {
    try {
      await _performLightCleanup();

      final hiveManager = HiveManager.instance;
      await hiveManager.compactAllBoxes();

      final cacheService = CacheService();
      await cacheService.optimizeMemoryUsage();

      debugPrint('[MemoryManager] Medium cleanup completed (preserving UI data)');
    } catch (e) {
      debugPrint('[MemoryManager] Medium cleanup error: $e');
    }
  }

  Future<void> _performEmergencyCleanup() async {
    try {
      await _performMediumCleanup();

      final hiveManager = HiveManager.instance;
      await hiveManager.handleMemoryPressure();

      final mediaService = MediaService();
      mediaService.handleMemoryPressure();

      debugPrint('[MemoryManager] Emergency cleanup - preserving UI interactions data');

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
      await _performLightCleanup();

      debugPrint('[MemoryManager] Background cleanup completed (light only)');
    } catch (e) {
      debugPrint('[MemoryManager] Background cleanup error: $e');
    }
  }

  void addMemoryPressureCallback(VoidCallback callback) {
    _ensureInitialized();
    _memoryPressureCallbacks.add(callback);
  }

  void removeMemoryPressureCallback(VoidCallback callback) {
    _memoryPressureCallbacks.remove(callback);
  }

  MemoryPressureLevel get currentPressureLevel => _currentPressureLevel;

  double get lastKnownMemoryUsage => _lastKnownMemoryUsage;

  bool get isUnderMemoryPressure {
    _ensureInitialized();
    return _currentPressureLevel.index >= MemoryPressureLevel.warning.index;
  }

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
