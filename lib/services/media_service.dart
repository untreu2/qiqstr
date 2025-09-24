import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/note_model.dart';
import 'time_service.dart';

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
  }) : lastAccessed = lastAccessed ?? timeService.now;

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

  static const int _maxCachedUrls = 1000;
  static const Duration _cacheExpiry = Duration(days: 3);
  static const Duration _failedRetryInterval = Duration(hours: 12);

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('media_cache_v2');

      if (cachedData != null) {
        final Map<String, dynamic> cacheMap = jsonDecode(cachedData);
        final now = timeService.now;

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
      }

      _isInitialized = true;

      _schedulePeriodicCleanup();
    } catch (e) {
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

    final now = timeService.now;

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
          lastAccessed: timeService.now,
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
              cachedAt: timeService.now,
              isSuccessful: true,
            );
            imageStream.removeListener(listener);
          }
        },
        onError: (exception, stackTrace) {
          if (!completed) {
            completed = true;
            _mediaCache[url] = CachedMediaInfo(
              url: url,
              cachedAt: timeService.now,
              isSuccessful: false,
            );
            imageStream.removeListener(listener);
          }
        },
      );

      imageStream.addListener(listener);

      await Future.delayed(const Duration(seconds: 10));

      if (!completed) {
        imageStream.removeListener(listener);
        _mediaCache[url] = CachedMediaInfo(
          url: url,
          cachedAt: timeService.now,
          isSuccessful: false,
        );
      }
    } catch (e) {
      _mediaCache[url] = CachedMediaInfo(
        url: url,
        cachedAt: timeService.now,
        isSuccessful: false,
      );
    } finally {
      _currentlyLoading.remove(url);
    }
  }

  void _performIntelligentCleanup() {
    Future.microtask(() async {
      final now = timeService.now;
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
      }

      for (final url in failedToRemove) {
        _mediaCache.remove(url);
      }

      if (failedToRemove.isNotEmpty) {}

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
    } catch (e) {}
  }

  void _schedulePeriodicCleanup() {
    Future.delayed(const Duration(hours: 2), () {
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
      final targetSize = (_maxCachedUrls * 0.4).round();
      const failedTargetSize = 30;

      if (_mediaCache.length > targetSize) {
        final now = DateTime.now();
        final entries = _mediaCache.entries.toList();

        final successfulEntries = entries.where((e) => e.value.isSuccessful).toList();
        final failedEntries = entries.where((e) => !e.value.isSuccessful).toList();

        failedEntries.sort((a, b) => a.value.cachedAt.compareTo(b.value.cachedAt));
        final failedRemoveCount = (failedEntries.length - failedTargetSize).clamp(0, failedEntries.length);
        for (int i = 0; i < failedRemoveCount; i++) {
          _mediaCache.remove(failedEntries[i].key);
        }

        successfulEntries.sort((a, b) {
          final aScore = a.value.accessCount * 0.6 +
              (now.difference(a.value.lastAccessed).inHours < 1 ? 50 : 0) +
              (now.difference(a.value.lastAccessed).inHours < 24 ? 20 : 0);
          final bScore = b.value.accessCount * 0.6 +
              (now.difference(b.value.lastAccessed).inHours < 1 ? 50 : 0) +
              (now.difference(b.value.lastAccessed).inHours < 24 ? 20 : 0);
          return aScore.compareTo(bScore);
        });

        final successfulRemoveCount = (successfulEntries.length - targetSize).clamp(0, successfulEntries.length);
        for (int i = 0; i < successfulRemoveCount; i++) {
          _mediaCache.remove(successfulEntries[i].key);
        }

        await _saveCacheToPersistentStorage();
      }
    });
  }

  void clearCache({bool clearFailed = true}) {
    if (clearFailed) {
      _mediaCache.clear();
    } else {
      _mediaCache.removeWhere((key, value) => !value.isSuccessful);
    }

    _currentlyLoading.clear();

    Future.microtask(() => _saveCacheToPersistentStorage());
  }

  Future<void> dispose() async {
    await _saveCacheToPersistentStorage();
    _mediaCache.clear();
    _currentlyLoading.clear();
    _isInitialized = false;
  }
}
