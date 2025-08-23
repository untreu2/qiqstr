import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

  final Set<String> _cachedUrls = {};
  final Set<String> _failedUrls = {};

  static const int _maxCachedUrls = 1000;
  static const int _maxFailedUrls = 200;

  void cacheMediaUrls(List<String> urls, {int priority = 1}) {
    final newUrls = urls.where((url) => !_cachedUrls.contains(url) && !_failedUrls.contains(url) && _isValidMediaUrl(url)).toList();

    if (newUrls.isEmpty) return;

    for (final url in newUrls) {
      _cacheSingleUrl(url);
    }

    _performSimpleCleanup();
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
      final imageStream = imageProvider.resolve(const ImageConfiguration());

      bool completed = false;
      late ImageStreamListener listener;

      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (!completed) {
            completed = true;
            _cachedUrls.add(url);
            imageStream.removeListener(listener);
          }
        },
        onError: (exception, stackTrace) {
          if (!completed) {
            completed = true;
            _failedUrls.add(url);
            imageStream.removeListener(listener);
          }
        },
      );

      imageStream.addListener(listener);
    } catch (e) {
      _failedUrls.add(url);
    }
  }

  void _performSimpleCleanup() {
    if (_cachedUrls.length > _maxCachedUrls) {
      final removeCount = _cachedUrls.length - _maxCachedUrls;
      final urlsToRemove = _cachedUrls.take(removeCount).toList();
      _cachedUrls.removeAll(urlsToRemove);
    }

    if (_failedUrls.length > _maxFailedUrls) {
      final removeCount = _failedUrls.length - _maxFailedUrls;
      final urlsToRemove = _failedUrls.take(removeCount).toList();
      _failedUrls.removeAll(urlsToRemove);
    }
  }

  bool _isValidMediaUrl(String url) {
    if (url.isEmpty || url.length > 2000) return false;

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

  void preloadCriticalImages(List<String> urls) {
    cacheMediaUrls(urls);
  }

  void clearFailedUrls() {
    _failedUrls.clear();
  }

  Map<String, dynamic> getCacheStats() {
    return {
      'cachedUrls': _cachedUrls.length,
      'failedUrls': _failedUrls.length,
      'status': 'simplified',
    };
  }

  void clearCache({bool clearFailed = true}) {
    _cachedUrls.clear();
    if (clearFailed) _failedUrls.clear();
  }

  void handleMemoryPressure() {
    if (_cachedUrls.length > 100) {
      final removeCount = (_cachedUrls.length * 0.3).round();
      final urlsToRemove = _cachedUrls.take(removeCount).toList();
      _cachedUrls.removeAll(urlsToRemove);
    }
    if (_failedUrls.length > 50) {
      _failedUrls.clear();
    }
  }

  Map<String, int> getMemoryUsage() {
    return {
      'cachedUrls': _cachedUrls.length,
      'failedUrls': _failedUrls.length,
      'totalUrls': _cachedUrls.length + _failedUrls.length,
    };
  }

  void retryFailedUrls() {
    final failedUrls = List<String>.from(_failedUrls);
    _failedUrls.clear();
    cacheMediaUrls(failedUrls);
  }

  bool isCached(String url) {
    return _cachedUrls.contains(url);
  }

  bool hasFailed(String url) {
    return _failedUrls.contains(url);
  }

  void dispose() {
    clearCache();
  }
}
