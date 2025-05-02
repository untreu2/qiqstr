import 'dart:async';
import 'dart:collection';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/material.dart';

class MediaService {
  static final MediaService _instance = MediaService._internal();

  factory MediaService() => _instance;

  MediaService._internal();

  final Set<String> _cachedUrls = {};
  final int _maxConcurrentTasks = 4;
  final Queue<String> _queue = Queue();
  bool _isRunning = false;

  void cacheMediaUrls(List<String> urls) {
    for (final url in urls) {
      if (!_cachedUrls.contains(url)) {
        _cachedUrls.add(url);
        _queue.add(url);
      }
    }
    _startProcessingQueue();
  }

  void _startProcessingQueue() {
    if (_isRunning) return;
    _isRunning = true;

    Future.doWhile(() async {
      if (_queue.isEmpty) {
        _isRunning = false;
        return false;
      }

      final batch = <Future<void>>[];

      for (int i = 0; i < _maxConcurrentTasks && _queue.isNotEmpty; i++) {
        final url = _queue.removeFirst();
        batch.add(_cacheSingleUrl(url));
      }

      await Future.wait(batch);
      return _queue.isNotEmpty;
    });
  }

  Future<void> _cacheSingleUrl(String url) async {
    try {
      final lower = url.toLowerCase();

      if (lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.mkv')) {
        await DefaultCacheManager().getSingleFile(url);
        print('[MediaService] Cached video: $url');
      } else if (lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif')) {
        final imageProvider = CachedNetworkImageProvider(url);
        final completer = Completer<void>();

        final imageStream = imageProvider.resolve(ImageConfiguration());
        final listener = ImageStreamListener(
          (ImageInfo _, bool __) => completer.complete(),
          onError: (_, __) => completer.complete(),
        );

        imageStream.addListener(listener);
        await completer.future;
        imageStream.removeListener(listener);

        print('[MediaService] Cached image: $url');
      }
    } catch (e) {
      print('[MediaService] Error caching $url: $e');
    }
  }
}
