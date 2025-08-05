import 'package:flutter/foundation.dart';
import 'dart:collection';

class ContentCacheProvider extends ChangeNotifier {
  static ContentCacheProvider? _instance;
  static ContentCacheProvider get instance => _instance ??= ContentCacheProvider._internal();

  ContentCacheProvider._internal();

  // Parsed content cache
  final Map<String, Map<String, dynamic>> _parsedContentCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Duration _cacheTTL = const Duration(hours: 1);
  final int _maxCacheSize = 1000;

  // LRU tracking
  final LinkedHashMap<String, int> _accessOrder = LinkedHashMap();
  int _accessCounter = 0;

  // Image dimension cache
  final Map<String, Map<String, double>> _imageDimensionsCache = {};

  // Link preview cache
  final Map<String, Map<String, dynamic>> _linkPreviewCache = {};

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

    debugPrint('[ContentCache] Cached parsed content for hash: ${contentHash.substring(0, 8)}...');
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
      // Remove oldest accessed items
      final sortedKeys = _accessOrder.keys.toList()..sort((a, b) => _accessOrder[a]!.compareTo(_accessOrder[b]!));

      final keysToRemove = sortedKeys.take(_maxCacheSize ~/ 4).toList();
      for (final key in keysToRemove) {
        _removeParsedContent(key);
      }

      debugPrint('[ContentCache] Cleaned up ${keysToRemove.length} old entries');
    }
  }

  // Image dimensions cache
  Map<String, double>? getImageDimensions(String imageUrl) {
    return _imageDimensionsCache[imageUrl];
  }

  void cacheImageDimensions(String imageUrl, double width, double height) {
    _imageDimensionsCache[imageUrl] = {
      'width': width,
      'height': height,
      'aspectRatio': width / height,
    };
  }

  // Link preview cache
  Map<String, dynamic>? getLinkPreview(String url) {
    return _linkPreviewCache[url];
  }

  void cacheLinkPreview(String url, Map<String, dynamic> preview) {
    _linkPreviewCache[url] = Map<String, dynamic>.from(preview);
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

  Map<String, dynamic> getStats() {
    return {
      'parsedContentEntries': _parsedContentCache.length,
      'imageDimensionsEntries': _imageDimensionsCache.length,
      'linkPreviewEntries': _linkPreviewCache.length,
      'maxCacheSize': _maxCacheSize,
      'cacheHitRate': _calculateHitRate(),
      'oldestEntry': _getOldestEntryAge(),
    };
  }

  double _calculateHitRate() {
    // This would need to be tracked with hit/miss counters
    return 0.0; // Placeholder
  }

  String _getOldestEntryAge() {
    if (_cacheTimestamps.isEmpty) return 'No entries';

    final oldest = _cacheTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b);
    final age = DateTime.now().difference(oldest);

    if (age.inMinutes < 60) return '${age.inMinutes}m';
    if (age.inHours < 24) return '${age.inHours}h';
    return '${age.inDays}d';
  }

  @override
  void dispose() {
    clearCache();
    super.dispose();
  }
}
