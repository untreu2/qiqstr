import 'dart:async';
import 'package:isar/isar.dart';
import '../../models/event_model.dart';
import 'isar_database_service.dart';

class InteractionCounts {
  final int reactions;
  final int reposts;
  final int replies;
  final int zapAmount;
  final bool hasReacted;
  final bool hasReposted;
  final bool hasZapped;

  const InteractionCounts({
    this.reactions = 0,
    this.reposts = 0,
    this.replies = 0,
    this.zapAmount = 0,
    this.hasReacted = false,
    this.hasReposted = false,
    this.hasZapped = false,
  });

  InteractionCounts copyWith({
    int? reactions,
    int? reposts,
    int? replies,
    int? zapAmount,
    bool? hasReacted,
    bool? hasReposted,
    bool? hasZapped,
  }) {
    return InteractionCounts(
      reactions: reactions ?? this.reactions,
      reposts: reposts ?? this.reposts,
      replies: replies ?? this.replies,
      zapAmount: zapAmount ?? this.zapAmount,
      hasReacted: hasReacted ?? this.hasReacted,
      hasReposted: hasReposted ?? this.hasReposted,
      hasZapped: hasZapped ?? this.hasZapped,
    );
  }
}

class InteractionService {
  static InteractionService? _instance;
  static InteractionService get instance =>
      _instance ??= InteractionService._internal();

  InteractionService._internal();

  final IsarDatabaseService _db = IsarDatabaseService.instance;
  final Map<String, StreamController<InteractionCounts>> _streams = {};
  final Map<String, InteractionCounts> _cache = {};
  static const int _maxCacheSize = 500;

  final Set<String> _localReactions = {};
  final Set<String> _localReposts = {};

  String? _currentUserHex;
  StreamSubscription? _collectionWatcher;
  Timer? _refreshDebounce;
  bool _watcherInitialized = false;

  void setCurrentUser(String? userHex) {
    _currentUserHex = userHex;
  }

  void _ensureWatcher() {
    if (_watcherInitialized) return;
    _watcherInitialized = true;

    Future.microtask(() async {
      try {
        final db = await _db.isar;
        _collectionWatcher = db.eventModels
            .where()
            .anyOf(
                [7, 1, 6, 9735], (q, kind) => q.kindEqualToAnyCreatedAt(kind))
            .watchLazy(fireImmediately: false)
            .listen((_) {
              _scheduleRefresh();
            });
      } catch (_) {}
    });
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 500), () {
      _refreshActiveStreams();
    });
  }

  Future<void> _refreshActiveStreams() async {
    final activeNoteIds = _streams.keys.toList();
    if (activeNoteIds.isEmpty) return;

    final batchSize = 20;
    for (var i = 0; i < activeNoteIds.length; i += batchSize) {
      final batch = activeNoteIds.skip(i).take(batchSize).toList();
      await Future.wait(
        batch.map((noteId) {
          if (_streams.containsKey(noteId) && !_streams[noteId]!.isClosed) {
            return _loadFromDb(noteId);
          }
          return Future.value();
        }),
      );
    }
  }

  Stream<InteractionCounts> streamInteractions(String noteId,
      {InteractionCounts? initialCounts}) {
    _ensureWatcher();

    if (!_streams.containsKey(noteId)) {
      _streams[noteId] = StreamController<InteractionCounts>.broadcast();
      if (initialCounts != null && !_cache.containsKey(noteId)) {
        _cache[noteId] = initialCounts;
        Future.microtask(() => _emit(noteId, initialCounts));
      }
      _loadFromDb(noteId);
    } else if (_cache.containsKey(noteId)) {
      Future.microtask(() => _emit(noteId, _cache[noteId]!));
    } else if (initialCounts != null) {
      _cache[noteId] = initialCounts;
      Future.microtask(() => _emit(noteId, initialCounts));
      _loadFromDb(noteId);
    }
    return _streams[noteId]!.stream;
  }

  void prePopulateCache(String noteId, InteractionCounts counts) {
    if (!_cache.containsKey(noteId)) {
      _cache[noteId] = counts;
    }
  }

  Future<void> _loadFromDb(String noteId) async {
    bool hasReacted = _localReactions.contains(noteId);
    bool hasReposted = _localReposts.contains(noteId);

    final futures = <Future>[];

    futures.add(_db.getCachedInteractionCounts([noteId]));

    if (!hasReacted && _currentUserHex != null) {
      futures.add(_db.hasUserReacted(noteId, _currentUserHex!));
    }
    if (!hasReposted && _currentUserHex != null) {
      futures.add(_db.hasUserReposted(noteId, _currentUserHex!));
    }

    final results = await Future.wait(futures);

    final countsMap = results[0] as Map<String, Map<String, int>>;
    final dbCounts = countsMap[noteId] ?? {};

    int resultIndex = 1;
    if (!hasReacted && _currentUserHex != null) {
      hasReacted = results[resultIndex] as bool;
      if (hasReacted) _localReactions.add(noteId);
      resultIndex++;
    }
    if (!hasReposted && _currentUserHex != null) {
      hasReposted = results[resultIndex] as bool;
      if (hasReposted) _localReposts.add(noteId);
    }

    final counts = InteractionCounts(
      reactions: dbCounts['reactions'] ?? 0,
      reposts: dbCounts['reposts'] ?? 0,
      replies: dbCounts['replies'] ?? 0,
      zapAmount: dbCounts['zaps'] ?? 0,
      hasReacted: hasReacted,
      hasReposted: hasReposted,
      hasZapped: false,
    );

    final oldCounts = _cache[noteId];
    _cache[noteId] = counts;

    if (oldCounts == null ||
        oldCounts.reactions != counts.reactions ||
        oldCounts.reposts != counts.reposts ||
        oldCounts.replies != counts.replies ||
        oldCounts.zapAmount != counts.zapAmount ||
        oldCounts.hasReacted != counts.hasReacted ||
        oldCounts.hasReposted != counts.hasReposted) {
      _emit(noteId, counts);
    }
  }

  Future<void> refreshInteractions(String noteId) async {
    await _loadFromDb(noteId);
  }

  Future<void> refreshAllActive() async {
    await _refreshActiveStreams();
  }

  void markReacted(String noteId) {
    _localReactions.add(noteId);
    _updateCache(
        noteId,
        (c) => c.copyWith(
              hasReacted: true,
              reactions: c.reactions + 1,
            ));
  }

  void markReposted(String noteId) {
    _localReposts.add(noteId);
    _updateCache(
        noteId,
        (c) => c.copyWith(
              hasReposted: true,
              reposts: c.reposts + 1,
            ));
  }

  void markUnreposted(String noteId) {
    _localReposts.remove(noteId);
    _updateCache(
        noteId,
        (c) => c.copyWith(
              hasReposted: false,
              reposts: c.reposts > 0 ? c.reposts - 1 : 0,
            ));
  }

  void markZapped(String noteId, int amount) {
    _updateCache(
        noteId,
        (c) => c.copyWith(
              hasZapped: true,
              zapAmount: c.zapAmount + amount,
            ));
  }

  void _updateCache(
      String noteId, InteractionCounts Function(InteractionCounts) updater) {
    final current = _cache[noteId] ?? const InteractionCounts();
    final updated = updater(current);
    _cache[noteId] = updated;
    _emit(noteId, updated);
    _evictCacheIfNeeded();
  }

  void _evictCacheIfNeeded() {
    if (_cache.length <= _maxCacheSize) return;
    final keysToRemove = _cache.keys
        .where((k) => !_streams.containsKey(k))
        .take(_cache.length - _maxCacheSize)
        .toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }

  void _emit(String noteId, InteractionCounts counts) {
    final stream = _streams[noteId];
    if (stream != null && !stream.isClosed) {
      stream.add(counts);
    }
  }

  InteractionCounts? getCachedInteractions(String noteId) => _cache[noteId];
  bool hasReacted(String noteId) => _localReactions.contains(noteId);
  bool hasReposted(String noteId) => _localReposts.contains(noteId);

  void disposeStream(String noteId) {
    _streams[noteId]?.close();
    _streams.remove(noteId);
    _cache.remove(noteId);
  }

  void clearCache() {
    _cache.clear();
  }

  void dispose() {
    _refreshDebounce?.cancel();
    _collectionWatcher?.cancel();
    _watcherInitialized = false;
    for (final controller in _streams.values) {
      controller.close();
    }
    _streams.clear();
    _cache.clear();
    _localReactions.clear();
    _localReposts.clear();
  }
}
