import 'package:flutter/foundation.dart';
import '../services/media_service.dart';

class MediaProvider extends ChangeNotifier {
  static MediaProvider? _instance;
  static MediaProvider get instance => _instance ??= MediaProvider._internal();

  MediaProvider._internal() {
    _mediaService = MediaService();
    _schedulePeriodicCleanup();
  }

  late final MediaService _mediaService;
  bool _isInitialized = true;
  String? _errorMessage;

  bool _isProcessing = false;
  int _queueSize = 0;
  DateTime _lastCleanup = DateTime.now();

  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;
  int get queueSize => _queueSize;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _errorMessage = null;
    notifyListeners();
  }

  void cacheMediaUrls(List<String> urls, {int priority = 1}) {
    try {
      final validUrls = urls.where((url) => url.isNotEmpty).toSet().toList();
      if (validUrls.isEmpty) return;

      _mediaService.cacheMediaUrls(validUrls, priority: priority);
      _updateQueueSize();
      _errorMessage = null;

      _scheduleNotification();
    } catch (e) {
      _errorMessage = 'Failed to cache media URLs: $e';
      debugPrint('[MediaProvider] Cache error: $e');
      notifyListeners();
    }
  }

  void preloadCriticalImages(List<String> urls) {
    try {
      _mediaService.preloadCriticalImages(urls);
      _updateQueueSize();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to preload critical images: $e';
      debugPrint('[MediaProvider] Preload error: $e');
      notifyListeners();
    }
  }

  void cacheImagesFromNotes(List<Map<String, dynamic>> notes) {
    final imageUrls = <String>{};

    for (final note in notes) {
      final content = note['content'] as String? ?? '';
      if (content.length > 10000) continue;

      final images = _extractImageUrls(content);
      imageUrls.addAll(images);

      if (imageUrls.length > 200) break;
    }

    if (imageUrls.isNotEmpty) {
      cacheMediaUrls(imageUrls.toList(), priority: 2);
    }
  }

  void cacheProfileImages(List<String> profileImageUrls) {
    final validUrls = profileImageUrls.where((url) => url.isNotEmpty).toList();
    if (validUrls.isNotEmpty) {
      cacheMediaUrls(validUrls, priority: 3);
    }
  }

  List<String> _extractImageUrls(String content) {
    final imageUrls = <String>[];
    final urlPattern = RegExp(r'https?://[^\s]+\.(jpg|jpeg|png|gif|webp|bmp|svg|avif|heic|heif)', caseSensitive: false);
    final matches = urlPattern.allMatches(content);

    for (final match in matches) {
      final url = match.group(0);
      if (url != null) {
        imageUrls.add(url);
      }
    }

    return imageUrls;
  }

  bool isCached(String url) {
    return _mediaService.isCached(url);
  }

  bool hasFailed(String url) {
    return _mediaService.hasFailed(url);
  }

  void retryFailedUrls() {
    try {
      _mediaService.retryFailedUrls();
      _updateQueueSize();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to retry failed URLs: $e';
      debugPrint('[MediaProvider] Retry error: $e');
      notifyListeners();
    }
  }

  void clearFailedUrls() {
    try {
      _mediaService.clearFailedUrls();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to clear failed URLs: $e';
      debugPrint('[MediaProvider] Clear failed error: $e');
      notifyListeners();
    }
  }

  void _updateQueueSize() {
    final stats = _mediaService.getCacheStats();
    _queueSize = stats['queueSize'] as int? ?? 0;
    _isProcessing = stats['isProcessing'] as bool? ?? false;
  }

  void optimizeForLowMemory() {
    try {
      _mediaService.clearCache(clearFailed: false);
      _performAggressiveCleanup();
    } catch (e) {
      _errorMessage = 'Failed to optimize for low memory: $e';
      debugPrint('[MediaProvider] Low memory optimization error: $e');
      notifyListeners();
    }
  }

  void _performAggressiveCleanup() {
    try {
      _mediaService.handleMemoryPressure();
      debugPrint('[MediaProvider] Aggressive cleanup performed');
    } catch (e) {
      debugPrint('[MediaProvider] Aggressive cleanup error: $e');
    }
  }

  void _schedulePeriodicCleanup() {
    Future.delayed(const Duration(minutes: 5), () {
      if (_isInitialized) {
        _performPeriodicCleanup();
        _schedulePeriodicCleanup();
      }
    });
  }

  void _performPeriodicCleanup() {
    final now = DateTime.now();
    if (now.difference(_lastCleanup).inMinutes < 3) return;

    _lastCleanup = now;

    try {
      final stats = getCacheStats();
      final memoryUsage = stats['memoryUsage'] as Map<String, dynamic>?;
      final isUnderPressure = memoryUsage?['memoryPressure'] as bool? ?? false;

      if (isUnderPressure || _queueSize > 100) {
        _performAggressiveCleanup();
      }
    } catch (e) {
      debugPrint('[MediaProvider] Periodic cleanup error: $e');
    }
  }

  bool _notificationScheduled = false;

  void _scheduleNotification() {
    if (_notificationScheduled) return;

    _notificationScheduled = true;
    Future.microtask(() {
      _notificationScheduled = false;
      notifyListeners();
    });
  }

  void optimizeForSlowNetwork() {
    debugPrint('[MediaProvider] Optimizing for slow network');
  }

  void clearCache({bool clearFailed = true}) {
    try {
      _mediaService.clearCache(clearFailed: clearFailed);
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to clear cache: $e';
      debugPrint('[MediaProvider] Clear cache error: $e');
      notifyListeners();
    }
  }

  void batchCacheOperations(List<Map<String, dynamic>> operations) {
    try {
      final limitedOps = operations.take(50).toList();

      for (final operation in limitedOps) {
        final type = operation['type'] as String;
        final urls = (operation['urls'] as List<String>).where((url) => url.isNotEmpty).toSet().toList();
        final priority = operation['priority'] as int? ?? 1;

        if (urls.isEmpty) continue;

        switch (type) {
          case 'cache':
            _mediaService.cacheMediaUrls(urls, priority: priority);
            break;
          case 'preload':
            _mediaService.preloadCriticalImages(urls);
            break;
        }
      }

      _updateQueueSize();
      _scheduleNotification();
    } catch (e) {
      _errorMessage = 'Failed to perform batch operations: $e';
      debugPrint('[MediaProvider] Batch operation error: $e');
      notifyListeners();
    }
  }

  void smartCacheFromContent(Map<String, dynamic> content) {
    final contentType = content['type'] as String? ?? 'unknown';
    final urls = content['urls'] as List<String>? ?? [];

    if (urls.isEmpty) return;

    int priority = 1;
    switch (contentType) {
      case 'profile':
        priority = 3;
        break;
      case 'note':
        priority = 2;
        break;
      case 'background':
        priority = 1;
        break;
    }

    cacheMediaUrls(urls, priority: priority);
  }

  void handleMemoryPressure() {
    try {
      _mediaService.handleMemoryPressure();
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to handle memory pressure: $e';
      debugPrint('[MediaProvider] Memory pressure handling error: $e');
      notifyListeners();
    }
  }

  Map<String, int> getMemoryUsage() {
    try {
      return _mediaService.getMemoryUsage();
    } catch (e) {
      debugPrint('[MediaProvider] Memory usage error: $e');
      return {
        'cachedUrls': 0,
        'failedUrls': 0,
        'totalUrls': 0,
        'queueSize': 0,
      };
    }
  }

  bool isUnderMemoryPressure() {
    final stats = getCacheStats();
    final memoryUsage = stats['memoryUsage'] as Map<String, dynamic>?;
    return memoryUsage?['memoryPressure'] as bool? ?? false;
  }

  Map<String, dynamic> getCacheStats() {
    try {
      return _mediaService.getCacheStats();
    } catch (e) {
      debugPrint('[MediaProvider] Cache stats error: $e');
      return {
        'cachedUrls': 0,
        'failedUrls': 0,
        'queueSize': 0,
        'isProcessing': false,
        'memoryUsage': {
          'memoryPressure': false,
        },
      };
    }
  }

  Map<String, dynamic> getDetailedStats() {
    try {
      final baseStats = getCacheStats();
      final memoryUsage = getMemoryUsage();

      return {
        ...baseStats,
        'detailedMemoryUsage': memoryUsage,
        'isUnderMemoryPressure': isUnderMemoryPressure(),
        'lastCleanup': _lastCleanup.toIso8601String(),
        'timeSinceLastCleanup': DateTime.now().difference(_lastCleanup).inMinutes,
      };
    } catch (e) {
      debugPrint('[MediaProvider] Detailed stats error: $e');
      return {
        'error': e.toString(),
        'cachedUrls': 0,
        'failedUrls': 0,
        'queueSize': _queueSize,
      };
    }
  }

  @override
  void dispose() {
    _isInitialized = false;
    _mediaService.dispose();
    super.dispose();
  }
}
