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

  MediaService._internal();

  final Set<String> _cachedUrls = {};
  final Set<String> _failedUrls = {};
  final Queue<MediaCacheItem> _priorityQueue = Queue();
  final Queue<MediaCacheItem> _normalQueue = Queue();
  
  final int _maxConcurrentTasks = 6;
  final int _maxBatchSize = 20;
  bool _isRunning = false;
  Timer? _batchTimer;
  
  // Cache statistics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _failedAttempts = 0;

  void cacheMediaUrls(List<String> urls, {int priority = 1}) {
    final newUrls = urls.where((url) =>
        !_cachedUrls.contains(url) &&
        !_failedUrls.contains(url) &&
        _isValidMediaUrl(url)
    ).toList();

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
      final endIndex = (i + _maxConcurrentTasks > batch.length)
          ? batch.length
          : i + _maxConcurrentTasks;
      final subBatch = batch.sublist(i, endIndex);
      
      final subFutures = subBatch.map((item) => _cacheSingleUrl(item.url));
      futures.addAll(subFutures);
      
      if (futures.length >= _maxConcurrentTasks) {
        await Future.wait(futures, eagerError: false);
        futures.clear();
        
        // Small delay to prevent overwhelming the system
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

      url.toLowerCase();
      if (!_isValidMediaUrl(url)) {
        return;
      }

      final imageProvider = CachedNetworkImageProvider(url);
      final completer = Completer<void>();
      
      // Set a timeout for caching
      final timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
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

  bool _isValidMediaUrl(String url) {
    if (url.isEmpty) return false;
    
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
           lower.endsWith('.jpeg') ||
           lower.endsWith('.png') ||
           lower.endsWith('.webp') ||
           lower.endsWith('.gif') ||
           lower.endsWith('.bmp') ||
           lower.endsWith('.svg');
  }

  // Preload critical images with high priority
  void preloadCriticalImages(List<String> urls) {
    cacheMediaUrls(urls, priority: 3);
  }

  // Clear failed URLs to retry them
  void clearFailedUrls() {
    _failedUrls.clear();
  }

  // Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cachedUrls': _cachedUrls.length,
      'failedUrls': _failedUrls.length,
      'queueSize': _priorityQueue.length + _normalQueue.length,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'failedAttempts': _failedAttempts,
      'isProcessing': _isRunning,
    };
  }

  // Clear all caches (for memory management)
  void clearCache() {
    _cachedUrls.clear();
    _failedUrls.clear();
    _priorityQueue.clear();
    _normalQueue.clear();
    _batchTimer?.cancel();
    _isRunning = false;
    
    // Reset statistics
    _cacheHits = 0;
    _cacheMisses = 0;
    _failedAttempts = 0;
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
