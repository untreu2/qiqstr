import 'package:flutter/foundation.dart';
import 'dart:collection';

class ContentCacheProvider extends ChangeNotifier {
  static ContentCacheProvider? _instance;
  static ContentCacheProvider get instance => _instance ??= ContentCacheProvider._internal();

  ContentCacheProvider._internal();

  // MEMORY OPTIMIZATION: Reduced cache sizes and aggressive cleanup
  final Map<String, Map<String, dynamic>> _parsedContentCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Duration _cacheTTL = const Duration(minutes: 30); // Reduced from 1 hour
  final int _maxCacheSize = 200; // Reduced from 1000

  // LRU tracking
  final LinkedHashMap<String, int> _accessOrder = LinkedHashMap();
  int _accessCounter = 0;

  // Image dimension cache with limits
  final Map<String, Map<String, double>> _imageDimensionsCache = {};
  final int _maxImageCacheSize = 500; // NEW: Limit image cache

  // Link preview cache with limits
  final Map<String, Map<String, dynamic>> _linkPreviewCache = {};
  final int _maxLinkCacheSize = 100; // NEW: Limit link preview cache

  // Memory cleanup tracking
  DateTime _lastImageCleanup = DateTime.now();
  DateTime _lastLinkCleanup = DateTime.now();

  bool get isInitialized => true;

  // Parsed content methods
  Map<String, dynamic>? getParsedContent(String contentHash) {
    final now = DateTime.now();

    if (_parsedContentCache.containsKey(contentHash)) {
      final timestamp = _cacheTimestamps[contentHash];
      if (timestamp != null && now.difference(timestamp) < _cacheTTL) {
        _updateAccessOrder(contentHash);
        return _parsedContentCache[contentHash];
      } else {
        // Expired, remove from cache
        _removeParsedContent(contentHash);
      }
    }

    return null;
  }

  void cacheParsedContent(String contentHash, Map<String, dynamic> parsedContent) {
    _ensureCacheSpace();

    _parsedContentCache[contentHash] = Map<String, dynamic>.from(parsedContent);
    _cacheTimestamps[contentHash] = DateTime.now();
    _updateAccessOrder(contentHash);

    // Debug print removed to save memory
  }

  void _removeParsedContent(String contentHash) {
    _parsedContentCache.remove(contentHash);
    _cacheTimestamps.remove(contentHash);
    _accessOrder.remove(contentHash);
  }

  void _updateAccessOrder(String key) {
    _accessOrder.remove(key);
    _accessOrder[key] = ++_accessCounter;
  }

  void _ensureCacheSpace() {
    if (_parsedContentCache.length >= _maxCacheSize) {
      // MEMORY OPTIMIZATION: More aggressive cleanup (remove 50% instead of 25%)
      final sortedKeys = _accessOrder.keys.toList()..sort((a, b) => _accessOrder[a]!.compareTo(_accessOrder[b]!));

      final keysToRemove = sortedKeys.take(_maxCacheSize ~/ 2).toList();
      for (final key in keysToRemove) {
        _removeParsedContent(key);
      }

      // Debug print removed to save memory
    }
  }

  // Image dimensions cache
  Map<String, double>? getImageDimensions(String imageUrl) {
    return _imageDimensionsCache[imageUrl];
  }

  void cacheImageDimensions(String imageUrl, double width, double height) {
    // MEMORY OPTIMIZATION: Cleanup old image cache entries
    _cleanupImageCache();

    _imageDimensionsCache[imageUrl] = {
      'width': width,
      'height': height,
      'aspectRatio': width / height,
    };
  }

  void _cleanupImageCache() {
    final now = DateTime.now();
    if (now.difference(_lastImageCleanup).inMinutes < 10) return; // Cleanup every 10 minutes

    _lastImageCleanup = now;

    if (_imageDimensionsCache.length > _maxImageCacheSize) {
      // Remove oldest 30% of entries
      final keysToRemove = _imageDimensionsCache.keys.take(_imageDimensionsCache.length ~/ 3).toList();
      for (final key in keysToRemove) {
        _imageDimensionsCache.remove(key);
      }
      // Debug print removed to save memory
    }
  }

  // Link preview cache
  Map<String, dynamic>? getLinkPreview(String url) {
    return _linkPreviewCache[url];
  }

  void cacheLinkPreview(String url, Map<String, dynamic> preview) {
    // MEMORY OPTIMIZATION: Cleanup old link preview cache
    _cleanupLinkCache();

    _linkPreviewCache[url] = Map<String, dynamic>.from(preview);
  }

  void _cleanupLinkCache() {
    final now = DateTime.now();
    if (now.difference(_lastLinkCleanup).inMinutes < 15) return; // Cleanup every 15 minutes

    _lastLinkCleanup = now;

    if (_linkPreviewCache.length > _maxLinkCacheSize) {
      // Remove oldest 40% of entries
      final keysToRemove = _linkPreviewCache.keys.take(_linkPreviewCache.length * 2 ~/ 5).toList();
      for (final key in keysToRemove) {
        _linkPreviewCache.remove(key);
      }
      // Debug print removed to save memory
    }
  }

  // Utility methods
  String generateContentHash(String content) {
    return content.hashCode.toString();
  }

  void clearExpiredEntries() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) >= _cacheTTL) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _removeParsedContent(key);
    }

    if (expiredKeys.isNotEmpty) {
      debugPrint('[ContentCache] Removed ${expiredKeys.length} expired entries');
    }
  }

  void clearCache() {
    _parsedContentCache.clear();
    _cacheTimestamps.clear();
    _accessOrder.clear();
    _imageDimensionsCache.clear();
    _linkPreviewCache.clear();
    _accessCounter = 0;
    debugPrint('[ContentCache] Cache cleared');
  }

  // MEMORY OPTIMIZATION: Removed all statistics to save memory

  @override
  void dispose() {
    clearCache();
    super.dispose();
  }
}
