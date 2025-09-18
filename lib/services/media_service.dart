import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/note_model.dart';

class CachedMediaInfo {
  final String url;
  final DateTime cachedAt;
  final bool isSuccessful;
  final int accessCount;
  final DateTime lastAccessed;

  CachedMediaInfo({
    required this.url,
    required this.cachedAt,
    required this.isSuccessful,
    this.accessCount = 1,
    DateTime? lastAccessed,
  }) : lastAccessed = lastAccessed ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'url': url,
        'cachedAt': cachedAt.millisecondsSinceEpoch,
        'isSuccessful': isSuccessful,
        'accessCount': accessCount,
        'lastAccessed': lastAccessed.millisecondsSinceEpoch,
      };

  factory CachedMediaInfo.fromJson(Map<String, dynamic> json) => CachedMediaInfo(
        url: json['url'],
        cachedAt: DateTime.fromMillisecondsSinceEpoch(json['cachedAt']),
        isSuccessful: json['isSuccessful'],
        accessCount: json['accessCount'] ?? 1,
        lastAccessed: DateTime.fromMillisecondsSinceEpoch(json['lastAccessed']),
      );

  CachedMediaInfo copyWith({
    int? accessCount,
    DateTime? lastAccessed,
  }) =>
      CachedMediaInfo(
        url: url,
        cachedAt: cachedAt,
        isSuccessful: isSuccessful,
        accessCount: accessCount ?? this.accessCount,
        lastAccessed: lastAccessed ?? this.lastAccessed,
      );
}

class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

  final Map<String, CachedMediaInfo> _mediaCache = {};
  final Set<String> _currentlyLoading = {};

  static const int _maxCachedUrls = 2000;
  static const Duration _cacheExpiry = Duration(days: 7);
  static const Duration _failedRetryInterval = Duration(hours: 6);

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('media_cache_v2');

      if (cachedData != null) {
        final Map<String, dynamic> cacheMap = jsonDecode(cachedData);
        final now = DateTime.now();

        for (final entry in cacheMap.entries) {
          try {
            final mediaInfo = CachedMediaInfo.fromJson(entry.value);

            final maxAge = mediaInfo.isSuccessful ? _cacheExpiry : _failedRetryInterval;

            if (now.difference(mediaInfo.cachedAt) < maxAge) {
              _mediaCache[entry.key] = mediaInfo;
            }
          } catch (e) {
            continue;
          }
        }

        print('[MediaService] Loaded ${_mediaCache.length} cached media entries from storage');
      }

      _isInitialized = true;

      _schedulePeriodicCleanup();
    } catch (e) {
      print('[MediaService] Error initializing media cache: $e');
      _isInitialized = true;
    }
  }

  void cacheMediaFromNotes(List<NoteModel> notes, {int priority = 1}) {
    final mediaUrls = <String>[];

    for (final note in notes) {
      final parsedContent = note.parsedContentLazy;
      final mediaUrlsFromContent = parsedContent['mediaUrls'] as List<dynamic>? ?? [];

      for (final url in mediaUrlsFromContent) {
        if (url is String && _isValidMediaUrl(url)) {
          mediaUrls.add(url);
        }
      }
    }

    if (mediaUrls.isNotEmpty) {
      cacheMediaUrls(mediaUrls, priority: priority);
    }
  }

  void cacheMediaUrls(List<String> urls, {int priority = 1}) {
    if (!_isInitialized) {
      Future.microtask(() async {
        await initialize();
        cacheMediaUrls(urls, priority: priority);
      });
      return;
    }

    Future.microtask(() async {
      final newUrls = urls.where((url) => _isValidMediaUrl(url) && !_currentlyLoading.contains(url) && _shouldCacheUrl(url)).toList();

      if (newUrls.isEmpty) return;

      newUrls.sort((a, b) {
        final aInfo = _mediaCache[a];
        final bInfo = _mediaCache[b];

        if (aInfo == null && bInfo != null) return -1;
        if (aInfo != null && bInfo == null) return 1;

        if (aInfo != null && bInfo != null) {
          return bInfo.accessCount.compareTo(aInfo.accessCount);
        }

        return 0;
      });

      final batchSize = priority > 1 ? 8 : 4;
      for (int i = 0; i < newUrls.length; i += batchSize) {
        final end = (i + batchSize > newUrls.length) ? newUrls.length : i + batchSize;
        final batch = newUrls.sublist(i, end);

        await Future.wait(
          batch.map((url) => _cacheSingleUrl(url)),
          eagerError: false,
        );

        if (i + batchSize < newUrls.length) {
          await Future.delayed(Duration(milliseconds: priority > 1 ? 50 : 100));
        }
      }

      _performIntelligentCleanup();
    });
  }

  bool _shouldCacheUrl(String url) {
    final cached = _mediaCache[url];
    if (cached == null) return true;

    final now = DateTime.now();

    if (_currentlyLoading.contains(url)) return false;

    if (cached.isSuccessful) return false;

    return now.difference(cached.cachedAt) > _failedRetryInterval;
  }

  Future<void> _cacheSingleUrl(String url) async {
    if (_currentlyLoading.contains(url)) return;

    _currentlyLoading.add(url);

    try {
      final existing = _mediaCache[url];
      if (existing?.isSuccessful == true) {
        _mediaCache[url] = existing!.copyWith(
          accessCount: existing.accessCount + 1,
          lastAccessed: DateTime.now(),
        );
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
            _mediaCache[url] = CachedMediaInfo(
              url: url,
              cachedAt: DateTime.now(),
              isSuccessful: true,
            );
            imageStream.removeListener(listener);
            print('[MediaService] Successfully cached: $url');
          }
        },
        onError: (exception, stackTrace) {
          if (!completed) {
            completed = true;
            _mediaCache[url] = CachedMediaInfo(
              url: url,
              cachedAt: DateTime.now(),
              isSuccessful: false,
            );
            imageStream.removeListener(listener);
            print('[MediaService] Failed to cache: $url - $exception');
          }
        },
      );

      imageStream.addListener(listener);

      await Future.delayed(const Duration(seconds: 10));

      if (!completed) {
        imageStream.removeListener(listener);
        _mediaCache[url] = CachedMediaInfo(
          url: url,
          cachedAt: DateTime.now(),
          isSuccessful: false,
        );
      }
    } catch (e) {
      _mediaCache[url] = CachedMediaInfo(
        url: url,
        cachedAt: DateTime.now(),
        isSuccessful: false,
      );
      print('[MediaService] Exception caching $url: $e');
    } finally {
      _currentlyLoading.remove(url);
    }
  }

  void _performIntelligentCleanup() {
    Future.microtask(() async {
      final now = DateTime.now();
      final successfulEntries = <String, CachedMediaInfo>{};
      final failedEntries = <String, CachedMediaInfo>{};

      for (final entry in _mediaCache.entries) {
        if (entry.value.isSuccessful) {
          successfulEntries[entry.key] = entry.value;
        } else {
          failedEntries[entry.key] = entry.value;
        }
      }

      final failedToRemove = <String>[];
      for (final entry in failedEntries.entries) {
        if (now.difference(entry.value.cachedAt) > _failedRetryInterval) {
          failedToRemove.add(entry.key);
        }
      }

      if (successfulEntries.length > _maxCachedUrls) {
        final sortedSuccessful = successfulEntries.entries.toList()
          ..sort((a, b) {
            final accessCountCompare = a.value.accessCount.compareTo(b.value.accessCount);
            if (accessCountCompare != 0) return accessCountCompare;

            return a.value.lastAccessed.compareTo(b.value.lastAccessed);
          });

        final removeCount = successfulEntries.length - (_maxCachedUrls * 0.8).round();
        for (int i = 0; i < removeCount && i < sortedSuccessful.length; i++) {
          _mediaCache.remove(sortedSuccessful[i].key);
        }

        print('[MediaService] Cleaned up $removeCount old successful cache entries');
      }

      for (final url in failedToRemove) {
        _mediaCache.remove(url);
      }

      if (failedToRemove.isNotEmpty) {
        print('[MediaService] Cleaned up ${failedToRemove.length} expired failed cache entries');
      }

      await _saveCacheToPersistentStorage();
    });
  }

  Future<void> _saveCacheToPersistentStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheMap = <String, dynamic>{};

      for (final entry in _mediaCache.entries) {
        cacheMap[entry.key] = entry.value.toJson();
      }

      await prefs.setString('media_cache_v2', jsonEncode(cacheMap));
      print('[MediaService] Saved ${_mediaCache.length} cache entries to persistent storage');
    } catch (e) {
      print('[MediaService] Error saving cache to storage: $e');
    }
  }

  void _schedulePeriodicCleanup() {
    Future.delayed(const Duration(hours: 1), () {
      if (_isInitialized) {
        _performIntelligentCleanup();
        _schedulePeriodicCleanup();
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
        lower.endsWith('.heif') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  void preloadCriticalImages(List<String> urls) {
    cacheMediaUrls(urls, priority: 3);
  }

  void preloadVisibleNoteImages(List<NoteModel> visibleNotes) {
    cacheMediaFromNotes(visibleNotes, priority: 2);
  }

  void retryFailedUrls() {
    Future.microtask(() async {
      final failedUrls = <String>[];
      final now = DateTime.now();

      for (final entry in _mediaCache.entries) {
        if (!entry.value.isSuccessful && now.difference(entry.value.cachedAt) > _failedRetryInterval) {
          failedUrls.add(entry.key);
        }
      }

      for (final url in failedUrls) {
        _mediaCache.remove(url);
      }

      if (failedUrls.isNotEmpty) {
        print('[MediaService] Retrying ${failedUrls.length} failed URLs');
        cacheMediaUrls(failedUrls, priority: 1);
      }
    });
  }

  bool isCached(String url) {
    final cached = _mediaCache[url];
    return cached?.isSuccessful == true;
  }

  bool hasFailed(String url) {
    final cached = _mediaCache[url];
    return cached?.isSuccessful == false;
  }

  Map<String, dynamic> getCacheStats() {
    final successful = _mediaCache.values.where((v) => v.isSuccessful).length;
    final failed = _mediaCache.values.where((v) => !v.isSuccessful).length;

    return {
      'totalCached': _mediaCache.length,
      'successfulUrls': successful,
      'failedUrls': failed,
      'currentlyLoading': _currentlyLoading.length,
      'cacheHitRate': _mediaCache.isNotEmpty ? '${(successful / _mediaCache.length * 100).toStringAsFixed(1)}%' : '0%',
      'maxCachedUrls': _maxCachedUrls,
      'isInitialized': _isInitialized,
    };
  }

  Map<String, int> getMemoryUsage() {
    final successful = _mediaCache.values.where((v) => v.isSuccessful).length;
    final failed = _mediaCache.values.where((v) => !v.isSuccessful).length;

    return {
      'totalEntries': _mediaCache.length,
      'successfulUrls': successful,
      'failedUrls': failed,
      'currentlyLoading': _currentlyLoading.length,
    };
  }

  void handleMemoryPressure() {
    Future.microtask(() async {
      final initialSize = _mediaCache.length;

      final targetSize = (_maxCachedUrls * 0.6).round();

      if (_mediaCache.length > targetSize) {
        final entries = _mediaCache.entries.toList()
          ..sort((a, b) {
            final aScore = a.value.accessCount + (DateTime.now().difference(a.value.lastAccessed).inHours > 24 ? 0 : 1);
            final bScore = b.value.accessCount + (DateTime.now().difference(b.value.lastAccessed).inHours > 24 ? 0 : 1);
            return aScore.compareTo(bScore);
          });

        final removeCount = _mediaCache.length - targetSize;
        for (int i = 0; i < removeCount && i < entries.length; i++) {
          _mediaCache.remove(entries[i].key);
        }

        print('[MediaService] Memory pressure cleanup: removed ${removeCount} entries (${initialSize} -> ${_mediaCache.length})');

        await _saveCacheToPersistentStorage();
      }
    });
  }

  void clearCache({bool clearFailed = true}) {
    final initialSize = _mediaCache.length;

    if (clearFailed) {
      _mediaCache.clear();
    } else {
      _mediaCache.removeWhere((key, value) => !value.isSuccessful);
    }

    _currentlyLoading.clear();

    print('[MediaService] Cache cleared: ${initialSize} -> ${_mediaCache.length} entries');

    Future.microtask(() => _saveCacheToPersistentStorage());
  }

  Future<void> dispose() async {
    await _saveCacheToPersistentStorage();
    _mediaCache.clear();
    _currentlyLoading.clear();
    _isInitialized = false;
  }
}
