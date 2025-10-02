import 'dart:async';

class TimeService {
  static final TimeService _instance = TimeService._internal();
  factory TimeService() => _instance;
  TimeService._internal();

  static TimeService get instance => _instance;

  static const Duration _cacheInterval = Duration(milliseconds: 1000);
  static const Duration _preciseInterval = Duration(milliseconds: 250);
  static const Duration _ultraFastInterval = Duration(milliseconds: 50);

  DateTime? _cachedNow;
  DateTime? _preciseCachedNow;
  DateTime? _ultraFastCachedNow;
  Timer? _cacheTimer;
  Timer? _preciseTimer;
  Timer? _ultraFastTimer;

  static final Map<int, String> _relativeTimeCache = <int, String>{};
  static final Map<int, DateTime> _timestampCache = <int, DateTime>{};

  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _ultraFastHits = 0;

  DateTime get ultraFastNow {
    if (_ultraFastCachedNow == null || _shouldRefreshUltraFastCache()) {
      _refreshUltraFastCache();
    } else {
      _ultraFastHits++;
    }
    return _ultraFastCachedNow!;
  }

  DateTime get now {
    if (_cachedNow == null || _shouldRefreshCache()) {
      _refreshCache();
      _cacheMisses++;
    } else {
      _cacheHits++;
    }
    return _cachedNow!;
  }

  DateTime get preciseNow {
    if (_preciseCachedNow == null || _shouldRefreshPreciseCache()) {
      _refreshPreciseCache();
    }
    return _preciseCachedNow!;
  }

  DateTime get realTimeNow => DateTime.now();

  int get millisecondsSinceEpoch => ultraFastNow.millisecondsSinceEpoch;

  int get secondsSinceEpoch => now.millisecondsSinceEpoch ~/ 1000;

  Duration difference(DateTime other) => now.difference(other);

  DateTime subtract(Duration duration) {
    final key = duration.inMilliseconds;
    return _timestampCache.putIfAbsent(key, () => now.subtract(duration));
  }

  DateTime add(Duration duration) {
    final key = -duration.inMilliseconds;
    return _timestampCache.putIfAbsent(key, () => now.add(duration));
  }

  bool _shouldRefreshCache() {
    if (_cachedNow == null) return true;
    return DateTime.now().difference(_cachedNow!).abs() > _cacheInterval;
  }

  bool _shouldRefreshPreciseCache() {
    if (_preciseCachedNow == null) return true;
    return DateTime.now().difference(_preciseCachedNow!).abs() > _preciseInterval;
  }

  bool _shouldRefreshUltraFastCache() {
    if (_ultraFastCachedNow == null) return true;
    return DateTime.now().difference(_ultraFastCachedNow!).abs() > _ultraFastInterval;
  }

  void _refreshCache() {
    final currentTime = DateTime.now();
    _cachedNow = currentTime;
    _preciseCachedNow = currentTime;
    _ultraFastCachedNow = currentTime;
  }

  void _refreshPreciseCache() {
    final currentTime = DateTime.now();
    _preciseCachedNow = currentTime;
    _ultraFastCachedNow = currentTime;
  }

  void _refreshUltraFastCache() {
    _ultraFastCachedNow = DateTime.now();
  }

  void startPeriodicRefresh() {
    _cacheTimer?.cancel();
    _preciseTimer?.cancel();
    _ultraFastTimer?.cancel();

    _cacheTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshCache());
    _preciseTimer = Timer.periodic(const Duration(milliseconds: 750), (_) => _refreshPreciseCache());
    _ultraFastTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _refreshUltraFastCache());
  }

  void stopPeriodicRefresh() {
    _cacheTimer?.cancel();
    _preciseTimer?.cancel();
    _ultraFastTimer?.cancel();
    _cacheTimer = null;
    _preciseTimer = null;
    _ultraFastTimer = null;
  }

  void refreshCache() {
    _refreshCache();
    _refreshPreciseCache();
    _refreshUltraFastCache();

    if (_timestampCache.length > 50) {
      _timestampCache.clear();
    }
    if (_relativeTimeCache.length > 200) {
      _relativeTimeCache.clear();
    }
  }

  Map<String, dynamic> getStats() {
    final total = _cacheHits + _cacheMisses;
    return {
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'ultraFastHits': _ultraFastHits,
      'hitRatio': total > 0 ? (_cacheHits / total * 100).toStringAsFixed(2) : '0.00',
      'totalRequests': total,
      'relativeTimeCacheSize': _relativeTimeCache.length,
      'timestampCacheSize': _timestampCache.length,
    };
  }

  void resetStats() {
    _cacheHits = 0;
    _cacheMisses = 0;
    _ultraFastHits = 0;
  }

  void dispose() {
    stopPeriodicRefresh();
    _cachedNow = null;
    _preciseCachedNow = null;
    _ultraFastCachedNow = null;
    _relativeTimeCache.clear();
    _timestampCache.clear();
  }
}

final timeService = TimeService.instance;

class TimeUtils {
  static final Map<int, String> _relativeTimeCache = {};
  static String formatRelativeTime(DateTime timestamp) {
    final key = timestamp.millisecondsSinceEpoch ~/ 60000;
    if (_relativeTimeCache.containsKey(key)) {
      return _relativeTimeCache[key]!;
    }

    final d = timeService.difference(timestamp);
    String result;

    if (d.inSeconds < 5) {
      result = 'now';
    } else if (d.inSeconds < 60) {
      result = '${d.inSeconds}s';
    } else if (d.inMinutes < 60) {
      result = '${d.inMinutes}m';
    } else if (d.inHours < 24) {
      result = '${d.inHours}h';
    } else if (d.inDays < 7) {
      result = '${d.inDays}d';
    } else if (d.inDays < 30) {
      result = '${d.inDays ~/ 7}w';
    } else if (d.inDays < 365) {
      result = '${d.inDays ~/ 30}mo';
    } else {
      result = '${d.inDays ~/ 365}y';
    }

    if (_relativeTimeCache.length > 1000) {
      _relativeTimeCache.clear();
    }
    _relativeTimeCache[key] = result;
    return result;
  }

  static String formatCompactRelativeTime(DateTime timestamp) {
    final d = timeService.difference(timestamp);

    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  static bool isExpired(DateTime timestamp, Duration ttl) {
    return timeService.difference(timestamp) > ttl;
  }

  static Duration? timeUntilExpiry(DateTime timestamp, Duration ttl) {
    final elapsed = timeService.difference(timestamp);
    final remaining = ttl - elapsed;
    return remaining.isNegative ? null : remaining;
  }

  static int _lastTimestamp = 0;
  static int _counter = 0;
  static String generateTimeBasedId([String? prefix]) {
    final timestamp = timeService.millisecondsSinceEpoch;
    if (timestamp == _lastTimestamp) {
      _counter++;
    } else {
      _lastTimestamp = timestamp;
      _counter = 0;
    }
    final id = timestamp + _counter;
    return prefix != null ? '${prefix}_$id' : id.toString();
  }

  static DateTime futureTime(Duration duration) {
    return timeService.add(duration);
  }

  static DateTime pastTime(Duration duration) {
    return timeService.subtract(duration);
  }

  static int toUnixTimestamp(DateTime? dateTime) {
    return (dateTime ?? timeService.now).millisecondsSinceEpoch ~/ 1000;
  }

  static DateTime fromUnixTimestamp(int unixTimestamp) {
    return DateTime.fromMillisecondsSinceEpoch(unixTimestamp * 1000);
  }
}
