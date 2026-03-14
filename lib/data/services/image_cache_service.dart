import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/image_cache.dart' as rust_img;

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._();
  static ImageCacheService get instance => _instance;
  ImageCacheService._();

  bool _initialized = false;
  String? _cacheDir;

  Future<void> initialize() async {
    if (_initialized) return;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/img_cache');
    _cacheDir = dir.path;
    await rust_img.initImageCache(cacheDir: _cacheDir!);
    _initialized = true;
    _scheduleEviction();
  }

  void _scheduleEviction() {
    Future.delayed(const Duration(minutes: 5), () async {
      try {
        await rust_img.evictImageCache(
          maxAgeSecs: BigInt.from(const Duration(days: 7).inSeconds),
        );
      } catch (_) {}
    });
  }

  Future<String?> resolve(String url) async {
    if (!_initialized || url.isEmpty) return null;
    try {
      final cached = await rust_img.getCachedImagePath(url: url);
      if (cached != null && cached.isNotEmpty) return cached;
      final path = await rust_img.fetchAndCacheImage(url: url);
      return path.isNotEmpty ? path : null;
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageCache] resolve error: $e');
      return null;
    }
  }

  Future<void> prefetch(List<String> urls) async {
    if (!_initialized || urls.isEmpty) return;
    final unique = urls.where((u) => u.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return;
    try {
      await rust_img.prefetchImages(urls: unique);
    } catch (_) {}
  }

  Future<double> cacheSizeMb() async {
    try {
      return await rust_img.getImageCacheSizeMb();
    } catch (_) {
      return 0;
    }
  }

  Future<int> evict({int maxAgeDays = 7}) async {
    try {
      final count = await rust_img.evictImageCache(
        maxAgeSecs: BigInt.from(Duration(days: maxAgeDays).inSeconds),
      );
      return count;
    } catch (_) {
      return 0;
    }
  }
}
