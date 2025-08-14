import 'package:flutter/foundation.dart';
import '../services/media_service.dart';

class MediaProvider extends ChangeNotifier {
  static MediaProvider? _instance;
  static MediaProvider get instance => _instance ??= MediaProvider._internal();

  MediaProvider._internal() {
    _mediaService = MediaService();
  }

  late final MediaService _mediaService;
  bool _isInitialized = true; // MediaService initializes itself
  String? _errorMessage;

  // Processing state
  bool _isProcessing = false;
  int _queueSize = 0;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;
  int get queueSize => _queueSize;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    // MediaService is already initialized in constructor
    _errorMessage = null;
    notifyListeners();
  }

  // Cache media URLs with different priorities
  void cacheMediaUrls(List<String> urls, {int priority = 1}) {
    try {
      _mediaService.cacheMediaUrls(urls, priority: priority);
      _updateQueueSize();
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to cache media URLs: $e';
      debugPrint('[MediaProvider] Cache error: $e');
      notifyListeners();
    }
  }

  // Preload critical images with high priority
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

  // Cache images from note content
  void cacheImagesFromNotes(List<Map<String, dynamic>> notes) {
    final imageUrls = <String>[];

    for (final note in notes) {
      final content = note['content'] as String? ?? '';
      final images = _extractImageUrls(content);
      imageUrls.addAll(images);
    }

    if (imageUrls.isNotEmpty) {
      cacheMediaUrls(imageUrls, priority: 2);
    }
  }

  // Cache profile images with high priority
  void cacheProfileImages(List<String> profileImageUrls) {
    final validUrls = profileImageUrls.where((url) => url.isNotEmpty).toList();
    if (validUrls.isNotEmpty) {
      cacheMediaUrls(validUrls, priority: 3);
    }
  }

  // Extract image URLs from text content
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

  // Check if URL is cached
  bool isCached(String url) {
    return _mediaService.isCached(url);
  }

  // Check if URL failed to cache
  bool hasFailed(String url) {
    return _mediaService.hasFailed(url);
  }

  // Retry failed URLs
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

  // Clear failed URLs to allow retry
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

  // Update queue size from service
  void _updateQueueSize() {
    final stats = _mediaService.getCacheStats();
    _queueSize = stats['queueSize'] as int? ?? 0;
    _isProcessing = stats['isProcessing'] as bool? ?? false;
  }

  // Performance optimization methods
  void optimizeForLowMemory() {
    try {
      // Clear some cache to free memory
      _mediaService.clearCache(clearFailed: false);
    } catch (e) {
      _errorMessage = 'Failed to optimize for low memory: $e';
      debugPrint('[MediaProvider] Low memory optimization error: $e');
      notifyListeners();
    }
  }

  void optimizeForSlowNetwork() {
    // This would adjust MediaService settings if it had such methods
    // For now, we can just reduce the queue processing
    debugPrint('[MediaProvider] Optimizing for slow network');
  }

  // Cache management
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

  // Batch operations for better performance
  void batchCacheOperations(List<Map<String, dynamic>> operations) {
    try {
      for (final operation in operations) {
        final type = operation['type'] as String;
        final urls = operation['urls'] as List<String>;
        final priority = operation['priority'] as int? ?? 1;

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
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to perform batch operations: $e';
      debugPrint('[MediaProvider] Batch operation error: $e');
      notifyListeners();
    }
  }

  // Smart caching based on content type
  void smartCacheFromContent(Map<String, dynamic> content) {
    final contentType = content['type'] as String? ?? 'unknown';
    final urls = content['urls'] as List<String>? ?? [];

    if (urls.isEmpty) return;

    int priority = 1;
    switch (contentType) {
      case 'profile':
        priority = 3; // High priority for profile images
        break;
      case 'note':
        priority = 2; // Medium priority for note images
        break;
      case 'background':
        priority = 1; // Low priority for background images
        break;
    }

    cacheMediaUrls(urls, priority: priority);
  }

  // Memory management methods
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

  // Check if under memory pressure
  bool isUnderMemoryPressure() {
    final stats = getCacheStats();
    final memoryUsage = stats['memoryUsage'] as Map<String, dynamic>?;
    return memoryUsage?['memoryPressure'] as bool? ?? false;
  }

  // Get cache statistics
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

  @override
  void dispose() {
    _mediaService.dispose();
    super.dispose();
  }
}
