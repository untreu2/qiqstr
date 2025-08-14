import 'dart:async';
import 'dart:collection';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class MediaCacheItem {
  final String url;
  final int priority;
  final DateTime timestamp;

  MediaCacheItem(this.url, this.priority) : timestamp = DateTime.now();
}

class MediaService {
  static final MediaService _instance = MediaService._internal();

  factory MediaService() => _instance;

  MediaService._internal() {
    _startMemoryManagement();
  }

  final Set<String> _cachedUrls = {};
  final Set<String> _failedUrls = {};
  final Queue<MediaCacheItem> _priorityQueue = Queue();
  final Queue<MediaCacheItem> _normalQueue = Queue();

  // Optimized configuration
  int _maxConcurrentTasks = 4; // Reduced for better memory usage
  int _maxBatchSize = 15; // Reduced batch size
  bool _isRunning = false;
  Timer? _batchTimer;
  Timer? _cleanupTimer;

  // Memory management - reduced limits
  static const int _maxCachedUrls = 2000; // Reduced from 5000
  static const int _maxFailedUrls = 500; // Reduced from 1000
  static const int _memoryPressureThreshold = 1500; // New threshold

  void _startMemoryManagement() {
    // More frequent cleanup for better memory management
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _performMemoryCleanup();
    });
  }

  void _performMemoryCleanup() {
    final totalUrls = _cachedUrls.length + _failedUrls.length;

    // Aggressive cleanup when approaching limits
    if (totalUrls > _memoryPressureThreshold) {
      _aggressiveCleanup();
    } else {
      _standardCleanup();
    }
  }

  void _aggressiveCleanup() {
    // Remove 30% of cached URLs when under memory pressure
    if (_cachedUrls.length > 100) {
      final removeCount = (_cachedUrls.length * 0.3).round();
      final urlsToRemove = _cachedUrls.take(removeCount).toList();
      _cachedUrls.removeAll(urlsToRemove);
    }

    // Clear failed URLs more aggressively
    if (_failedUrls.length > 200) {
      final removeCount = (_failedUrls.length * 0.5).round();
      final urlsToRemove = _failedUrls.take(removeCount).toList();
      _failedUrls.removeAll(urlsToRemove);
    }
  }

  void _standardCleanup() {
    // Standard cleanup when within normal limits
    if (_cachedUrls.length > _maxCachedUrls) {
      final urlsToRemove = _cachedUrls.take(_cachedUrls.length - _maxCachedUrls);
      _cachedUrls.removeAll(urlsToRemove);
    }

    if (_failedUrls.length > _maxFailedUrls) {
      final urlsToRemove = _failedUrls.take(_failedUrls.length - _maxFailedUrls);
      _failedUrls.removeAll(urlsToRemove);
    }
  }

  void cacheMediaUrls(List<String> urls, {int priority = 1}) {
    final newUrls = urls.where((url) => !_cachedUrls.contains(url) && !_failedUrls.contains(url) && _isValidMediaUrl(url)).toList();

    if (newUrls.isEmpty) return;

    for (final url in newUrls) {
      final item = MediaCacheItem(url, priority);

      if (priority > 1) {
        _priorityQueue.add(item);
      } else {
        _normalQueue.add(item);
      }
    }

    _startProcessingQueue();
  }

  void _startProcessingQueue() {
    if (_isRunning) return;
    _isRunning = true;

    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 100), _processBatch);
  }

  Future<void> _processBatch() async {
    if (_priorityQueue.isEmpty && _normalQueue.isEmpty) {
      _isRunning = false;
      return;
    }

    final batch = <MediaCacheItem>[];

    // Process priority items first
    while (_priorityQueue.isNotEmpty && batch.length < _maxBatchSize) {
      batch.add(_priorityQueue.removeFirst());
    }

    // Fill remaining slots with normal priority items
    while (_normalQueue.isNotEmpty && batch.length < _maxBatchSize) {
      batch.add(_normalQueue.removeFirst());
    }

    if (batch.isNotEmpty) {
      await _processCacheBatch(batch);
    }

    // Continue processing if there are more items
    if (_priorityQueue.isNotEmpty || _normalQueue.isNotEmpty) {
      _batchTimer = Timer(const Duration(milliseconds: 50), _processBatch);
    } else {
      _isRunning = false;
    }
  }

  Future<void> _processCacheBatch(List<MediaCacheItem> batch) async {
    final futures = <Future<void>>[];

    for (int i = 0; i < batch.length; i += _maxConcurrentTasks) {
      final endIndex = (i + _maxConcurrentTasks > batch.length) ? batch.length : i + _maxConcurrentTasks;
      final subBatch = batch.sublist(i, endIndex);

      final subFutures = subBatch.map((item) => _cacheSingleUrl(item.url));
      futures.addAll(subFutures);

      if (futures.length >= _maxConcurrentTasks) {
        await Future.wait(futures, eagerError: false);
        futures.clear();

        // Fixed small delay for memory management
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures, eagerError: false);
    }
  }

  Future<void> _cacheSingleUrl(String url) async {
    try {
      if (_cachedUrls.contains(url) || _failedUrls.contains(url)) {
        return;
      }

      if (!_isValidMediaUrl(url)) {
        _failedUrls.add(url);
        return;
      }

      final imageProvider = CachedNetworkImageProvider(url);
      final completer = Completer<void>();

      // Shorter timeout for better memory management
      final timeout = _getTimeoutForUrl(url);
      final timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          _failedUrls.add(url);
          completer.complete();
        }
      });

      final imageStream = imageProvider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;

      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          timeoutTimer.cancel();
          if (!completer.isCompleted) {
            _cachedUrls.add(url);
            completer.complete();
          }
        },
        onError: (exception, stackTrace) {
          timeoutTimer.cancel();
          if (!completer.isCompleted) {
            _failedUrls.add(url);
            completer.complete();
          }
        },
      );

      imageStream.addListener(listener);

      await completer.future;
      imageStream.removeListener(listener);
    } catch (e) {
      _failedUrls.add(url);
    }
  }

  Duration _getTimeoutForUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.gif')) {
      return const Duration(seconds: 8); // Reduced timeout for GIFs
    } else if (lower.endsWith('.svg')) {
      return const Duration(seconds: 3); // Reduced timeout for SVGs
    }
    return const Duration(seconds: 6); // Reduced default timeout
  }

  bool _isValidMediaUrl(String url) {
    if (url.isEmpty || url.length > 2000) return false; // Reject very long URLs

    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) return false;
    } catch (e) {
      return false;
    }

    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg') ||
        lower.endsWith('.avif') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  // Preload critical images with high priority
  void preloadCriticalImages(List<String> urls) {
    cacheMediaUrls(urls, priority: 3);
  }

  // Clear failed URLs to retry them
  void clearFailedUrls() {
    _failedUrls.clear();
  }

  // Simplified cache statistics for memory efficiency
  Map<String, dynamic> getCacheStats() {
    return {
      'cachedUrls': _cachedUrls.length,
      'failedUrls': _failedUrls.length,
      'queueSize': _priorityQueue.length + _normalQueue.length,
      'priorityQueueSize': _priorityQueue.length,
      'normalQueueSize': _normalQueue.length,
      'isProcessing': _isRunning,
      'maxConcurrentTasks': _maxConcurrentTasks,
      'maxBatchSize': _maxBatchSize,
      'memoryUsage': {
        'cachedUrls': _cachedUrls.length,
        'maxCachedUrls': _maxCachedUrls,
        'failedUrls': _failedUrls.length,
        'maxFailedUrls': _maxFailedUrls,
        'memoryPressure': (_cachedUrls.length + _failedUrls.length) > _memoryPressureThreshold,
      },
    };
  }

  // Optimized cache clearing
  void clearCache({bool clearFailed = true}) {
    _cachedUrls.clear();
    if (clearFailed) _failedUrls.clear();
    _priorityQueue.clear();
    _normalQueue.clear();
    _batchTimer?.cancel();
    _isRunning = false;
  }

  // Memory-optimized disposal
  void dispose() {
    _cleanupTimer?.cancel();
    _batchTimer?.cancel();
    clearCache();
  }

  // Memory pressure handling
  void handleMemoryPressure() {
    _aggressiveCleanup();
  }

  // Get memory usage info
  Map<String, int> getMemoryUsage() {
    return {
      'cachedUrls': _cachedUrls.length,
      'failedUrls': _failedUrls.length,
      'totalUrls': _cachedUrls.length + _failedUrls.length,
      'queueSize': _priorityQueue.length + _normalQueue.length,
    };
  }

  // Force retry failed URLs
  void retryFailedUrls() {
    final failedUrls = List<String>.from(_failedUrls);
    _failedUrls.clear();

    for (final url in failedUrls) {
      cacheMediaUrls([url], priority: 1);
    }
  }

  // Check if URL is already cached
  bool isCached(String url) {
    return _cachedUrls.contains(url);
  }

  // Check if URL failed to cache
  bool hasFailed(String url) {
    return _failedUrls.contains(url);
  }
}
