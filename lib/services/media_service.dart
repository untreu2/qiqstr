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
    Future.microtask(() async {
      final newUrls = urls.where((url) => !_cachedUrls.contains(url) && !_failedUrls.contains(url) && _isValidMediaUrl(url)).toList();

      if (newUrls.isEmpty) return;

      const batchSize = 5;
      for (int i = 0; i < newUrls.length; i += batchSize) {
        final end = (i + batchSize > newUrls.length) ? newUrls.length : i + batchSize;
        final batch = newUrls.sublist(i, end);

        for (final url in batch) {
          _cacheSingleUrl(url);
        }

        await Future.delayed(Duration.zero);
      }

      _performSimpleCleanupAsync();
    });
  }

  Future<void> _cacheSingleUrl(String url) async {
    Future.microtask(() async {
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
    });
  }

  void _performSimpleCleanupAsync() {
    Future.microtask(() async {
      if (_cachedUrls.length > _maxCachedUrls) {
        final removeCount = _cachedUrls.length - _maxCachedUrls;
        final urlsToRemove = _cachedUrls.take(removeCount).toList();

        const batchSize = 50;
        for (int i = 0; i < urlsToRemove.length; i += batchSize) {
          final end = (i + batchSize > urlsToRemove.length) ? urlsToRemove.length : i + batchSize;
          final batch = urlsToRemove.sublist(i, end);
          _cachedUrls.removeAll(batch);

          await Future.delayed(Duration.zero);
        }
      }

      if (_failedUrls.length > _maxFailedUrls) {
        final removeCount = _failedUrls.length - _maxFailedUrls;
        final urlsToRemove = _failedUrls.take(removeCount).toList();

        const batchSize = 50;
        for (int i = 0; i < urlsToRemove.length; i += batchSize) {
          final end = (i + batchSize > urlsToRemove.length) ? urlsToRemove.length : i + batchSize;
          final batch = urlsToRemove.sublist(i, end);
          _failedUrls.removeAll(batch);

          await Future.delayed(Duration.zero);
        }
      }
    });
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
    Future.microtask(() => cacheMediaUrls(urls));
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
    Future.microtask(() async {
      if (_cachedUrls.length > 100) {
        final removeCount = (_cachedUrls.length * 0.3).round();
        final urlsToRemove = _cachedUrls.take(removeCount).toList();

        const batchSize = 25;
        for (int i = 0; i < urlsToRemove.length; i += batchSize) {
          final end = (i + batchSize > urlsToRemove.length) ? urlsToRemove.length : i + batchSize;
          final batch = urlsToRemove.sublist(i, end);
          _cachedUrls.removeAll(batch);

          await Future.delayed(Duration.zero);
        }
      }
      if (_failedUrls.length > 50) {
        _failedUrls.clear();
      }
    });
  }

  Map<String, int> getMemoryUsage() {
    return {
      'cachedUrls': _cachedUrls.length,
      'failedUrls': _failedUrls.length,
      'totalUrls': _cachedUrls.length + _failedUrls.length,
    };
  }

  void retryFailedUrls() {
    Future.microtask(() async {
      final failedUrls = List<String>.from(_failedUrls);
      _failedUrls.clear();

      const batchSize = 3;
      for (int i = 0; i < failedUrls.length; i += batchSize) {
        final end = (i + batchSize > failedUrls.length) ? failedUrls.length : i + batchSize;
        final batch = failedUrls.sublist(i, end);
        cacheMediaUrls(batch);

        await Future.delayed(Duration.zero);
      }
    });
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
