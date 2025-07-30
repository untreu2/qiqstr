import 'dart:async';
import 'dart:collection';
import 'dart:math';
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
    _startPerformanceMonitoring();
  }

  final Set<String> _cachedUrls = {};
  final Set<String> _failedUrls = {};
  final Queue<MediaCacheItem> _priorityQueue = Queue();
  final Queue<MediaCacheItem> _normalQueue = Queue();

  // Adaptive configuration
  int _maxConcurrentTasks = 6;
  int _maxBatchSize = 20;
  bool _isRunning = false;
  Timer? _batchTimer;
  Timer? _performanceTimer;
  Timer? _cleanupTimer;

  // Enhanced cache statistics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _failedAttempts = 0;
  int _totalRequests = 0;
  final List<Duration> _processingTimes = [];

  // Memory management
  static const int _maxCachedUrls = 5000;
  static const int _maxFailedUrls = 1000;

  void _startPerformanceMonitoring() {
    _performanceTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _adjustPerformanceSettings();
      _cleanupOldEntries();
    });

    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _performMemoryCleanup();
    });
  }

  void _adjustPerformanceSettings() {
    if (_processingTimes.isNotEmpty) {
      final avgTime = _processingTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds) / _processingTimes.length;

      // Adjust concurrent tasks based on performance
      if (avgTime > 1000) {
        _maxConcurrentTasks = max(3, _maxConcurrentTasks - 1);
      } else if (avgTime < 200) {
        _maxConcurrentTasks = min(10, _maxConcurrentTasks + 1);
      }

      // Adjust batch size
      if (avgTime > 500) {
        _maxBatchSize = max(10, _maxBatchSize - 2);
      } else if (avgTime < 100) {
        _maxBatchSize = min(30, _maxBatchSize + 2);
      }
    }

    // Keep only recent measurements
    if (_processingTimes.length > 20) {
      _processingTimes.removeRange(0, _processingTimes.length - 20);
    }
  }

  void _cleanupOldEntries() {
    // Remove old failed URLs to allow retry
    if (_failedUrls.length > _maxFailedUrls) {
      final urlsToRemove = _failedUrls.take(_failedUrls.length - _maxFailedUrls);
      _failedUrls.removeAll(urlsToRemove);
    }
  }

  void _performMemoryCleanup() {
    if (_cachedUrls.length > _maxCachedUrls) {
      final urlsToRemove = _cachedUrls.take(_cachedUrls.length - _maxCachedUrls);
      _cachedUrls.removeAll(urlsToRemove);
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
    final stopwatch = Stopwatch()..start();
    final futures = <Future<void>>[];

    for (int i = 0; i < batch.length; i += _maxConcurrentTasks) {
      final endIndex = (i + _maxConcurrentTasks > batch.length) ? batch.length : i + _maxConcurrentTasks;
      final subBatch = batch.sublist(i, endIndex);

      final subFutures = subBatch.map((item) => _cacheSingleUrl(item.url));
      futures.addAll(subFutures);

      if (futures.length >= _maxConcurrentTasks) {
        await Future.wait(futures, eagerError: false);
        futures.clear();

        // Adaptive delay based on performance
        final delay = stopwatch.elapsedMilliseconds > 500 ? 20 : 5;
        await Future.delayed(Duration(milliseconds: delay));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures, eagerError: false);
    }

    stopwatch.stop();
    _processingTimes.add(stopwatch.elapsed);
  }

  Future<void> _cacheSingleUrl(String url) async {
    _totalRequests++;

    try {
      if (_cachedUrls.contains(url) || _failedUrls.contains(url)) {
        _cacheHits++;
        return;
      }

      if (!_isValidMediaUrl(url)) {
        _failedUrls.add(url);
        _failedAttempts++;
        return;
      }

      final imageProvider = CachedNetworkImageProvider(url);
      final completer = Completer<void>();

      // Adaptive timeout based on URL type
      final timeout = _getTimeoutForUrl(url);
      final timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          _failedUrls.add(url);
          _failedAttempts++;
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
            _cacheHits++;
            completer.complete();
          }
        },
        onError: (exception, stackTrace) {
          timeoutTimer.cancel();
          if (!completer.isCompleted) {
            _failedUrls.add(url);
            _failedAttempts++;
            completer.complete();
          }
        },
      );

      imageStream.addListener(listener);

      await completer.future;
      imageStream.removeListener(listener);
    } catch (e) {
      _failedUrls.add(url);
      _failedAttempts++;
    }
  }

  Duration _getTimeoutForUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.gif')) {
      return const Duration(seconds: 15); // GIFs can be larger
    } else if (lower.endsWith('.svg')) {
      return const Duration(seconds: 5); // SVGs are usually small
    }
    return const Duration(seconds: 10); // Default timeout
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

  // Enhanced cache statistics
  Map<String, dynamic> getCacheStats() {
    final hitRate = _totalRequests > 0 ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2) : '0.00';

    final avgProcessingTime =
        _processingTimes.isNotEmpty ? _processingTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds) / _processingTimes.length : 0.0;

    return {
      'cachedUrls': _cachedUrls.length,
      'failedUrls': _failedUrls.length,
      'queueSize': _priorityQueue.length + _normalQueue.length,
      'priorityQueueSize': _priorityQueue.length,
      'normalQueueSize': _normalQueue.length,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'failedAttempts': _failedAttempts,
      'totalRequests': _totalRequests,
      'hitRate': '$hitRate%',
      'isProcessing': _isRunning,
      'maxConcurrentTasks': _maxConcurrentTasks,
      'maxBatchSize': _maxBatchSize,
      'avgProcessingTimeMs': avgProcessingTime.round(),
      'memoryUsage': {
        'cachedUrls': _cachedUrls.length,
        'maxCachedUrls': _maxCachedUrls,
        'failedUrls': _failedUrls.length,
        'maxFailedUrls': _maxFailedUrls,
      },
    };
  }

  // Enhanced cache clearing with selective options
  void clearCache({bool clearFailed = true, bool clearStats = true}) {
    _cachedUrls.clear();
    if (clearFailed) _failedUrls.clear();
    _priorityQueue.clear();
    _normalQueue.clear();
    _batchTimer?.cancel();
    _isRunning = false;

    if (clearStats) {
      _cacheHits = 0;
      _cacheMisses = 0;
      _failedAttempts = 0;
      _totalRequests = 0;
      _processingTimes.clear();
    }
  }

  // Cleanup method for proper disposal
  void dispose() {
    _performanceTimer?.cancel();
    _cleanupTimer?.cancel();
    clearCache();
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
