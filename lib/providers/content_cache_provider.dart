import 'package:flutter/foundation.dart';
import 'dart:collection';

class ContentCacheProvider extends ChangeNotifier {
  static ContentCacheProvider? _instance;
  static ContentCacheProvider get instance => _instance ??= ContentCacheProvider._internal();

  ContentCacheProvider._internal();

  final Map<String, Map<String, dynamic>> _parsedContentCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Duration _cacheTTL = const Duration(minutes: 15);
  final int _maxCacheSize = 150;

  final LinkedHashMap<String, int> _accessOrder = LinkedHashMap();
  int _accessCounter = 0;

  final Map<String, Map<String, double>> _imageDimensionsCache = {};
  final int _maxImageCacheSize = 300;

  final Map<String, Map<String, dynamic>> _linkPreviewCache = {};
  final int _maxLinkCacheSize = 50;

  DateTime _lastImageCleanup = DateTime.now();
  DateTime _lastLinkCleanup = DateTime.now();
  DateTime _lastGeneralCleanup = DateTime.now();

  bool get isInitialized => true;

  Map<String, dynamic>? getParsedContent(String contentHash) {
    _performPeriodicCleanup();

    final now = DateTime.now();

    if (_parsedContentCache.containsKey(contentHash)) {
      final timestamp = _cacheTimestamps[contentHash];
      if (timestamp != null && now.difference(timestamp) < _cacheTTL) {
        _updateAccessOrder(contentHash);
        return _parsedContentCache[contentHash];
      } else {
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
      final sortedKeys = _accessOrder.keys.toList()..sort((a, b) => _accessOrder[a]!.compareTo(_accessOrder[b]!));

      final keysToRemove = sortedKeys.take((_maxCacheSize * 0.6).round()).toList();
      for (final key in keysToRemove) {
        _removeParsedContent(key);
      }

      if (_accessCounter > 100000) {
        _accessCounter = 0;
        final entries = _accessOrder.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
        _accessOrder.clear();
        for (var i = 0; i < entries.length; i++) {
          _accessOrder[entries[i].key] = i;
        }
        _accessCounter = entries.length;
      }
    }
  }

  Map<String, double>? getImageDimensions(String imageUrl) {
    return _imageDimensionsCache[imageUrl];
  }

  void cacheImageDimensions(String imageUrl, double width, double height) {
    _cleanupImageCache();

    _imageDimensionsCache[imageUrl] = {
      'width': width,
      'height': height,
      'aspectRatio': width / height,
    };
  }

  void _cleanupImageCache() {
    final now = DateTime.now();
    if (now.difference(_lastImageCleanup).inMinutes < 5) return;

    _lastImageCleanup = now;

    if (_imageDimensionsCache.length > _maxImageCacheSize) {
      final keysToRemove = _imageDimensionsCache.keys.take(_imageDimensionsCache.length ~/ 2).toList();
      for (final key in keysToRemove) {
        _imageDimensionsCache.remove(key);
      }
    }
  }

  Map<String, dynamic>? getLinkPreview(String url) {
    return _linkPreviewCache[url];
  }

  void cacheLinkPreview(String url, Map<String, dynamic> preview) {
    _cleanupLinkCache();

    _linkPreviewCache[url] = Map<String, dynamic>.from(preview);
  }

  void _cleanupLinkCache() {
    final now = DateTime.now();
    if (now.difference(_lastLinkCleanup).inMinutes < 10) return;

    _lastLinkCleanup = now;

    if (_linkPreviewCache.length > _maxLinkCacheSize) {
      final keysToRemove = _linkPreviewCache.keys.take(_linkPreviewCache.length ~/ 2).toList();
      for (final key in keysToRemove) {
        _linkPreviewCache.remove(key);
      }
    }
  }

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

  void _performPeriodicCleanup() {
    final now = DateTime.now();
    if (now.difference(_lastGeneralCleanup).inMinutes < 2) return;

    _lastGeneralCleanup = now;

    clearExpiredEntries();

    _cleanupImageCache();
    _cleanupLinkCache();

    if (_getTotalCacheSize() > 1000) {
      _performAggressiveCleanup();
    }
  }

  int _getTotalCacheSize() {
    return _parsedContentCache.length + _imageDimensionsCache.length + _linkPreviewCache.length;
  }

  void _performAggressiveCleanup() {
    final sortedKeys = _accessOrder.keys.toList()..sort((a, b) => _accessOrder[a]!.compareTo(_accessOrder[b]!));
    final keysToRemove = sortedKeys.take((_parsedContentCache.length * 0.7).round()).toList();

    for (final key in keysToRemove) {
      _removeParsedContent(key);
    }

    final imageKeysToRemove = _imageDimensionsCache.keys.take((_imageDimensionsCache.length * 0.7).round()).toList();
    for (final key in imageKeysToRemove) {
      _imageDimensionsCache.remove(key);
    }

    final linkKeysToRemove = _linkPreviewCache.keys.take((_linkPreviewCache.length * 0.7).round()).toList();
    for (final key in linkKeysToRemove) {
      _linkPreviewCache.remove(key);
    }

    debugPrint('[ContentCache] Aggressive cleanup performed - Total size: ${_getTotalCacheSize()}');
  }

  Map<String, int> getMemoryStats() {
    return {
      'parsedContentCache': _parsedContentCache.length,
      'imageDimensionsCache': _imageDimensionsCache.length,
      'linkPreviewCache': _linkPreviewCache.length,
      'totalCacheSize': _getTotalCacheSize(),
    };
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

  @override
  void dispose() {
    clearCache();
    super.dispose();
  }
}
