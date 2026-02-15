import 'dart:async';
import 'rust_database_service.dart';

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

  InteractionService._internal() {
    _dbChangeSubscription = _db.onChange.listen((_) {
      _refreshActiveStreams();
    });
  }

  final RustDatabaseService _db = RustDatabaseService.instance;
  final Map<String, StreamController<InteractionCounts>> _streams = {};
  final Map<String, InteractionCounts> _cache = {};
  static const int _maxCacheSize = 500;

  final Set<String> _localReactions = {};
  final Set<String> _localReposts = {};
  final Set<String> _localZaps = {};

  String? _currentUserHex;
  StreamSubscription<void>? _dbChangeSubscription;
  Timer? _refreshDebounceTimer;

  final Set<String> _pendingBatch = {};
  Timer? _batchTimer;
  bool _batchLoading = false;
  static const Duration _batchDelay = Duration(milliseconds: 10);
  static const int _batchSize = 50;

  void setCurrentUser(String? userHex) {
    _currentUserHex = userHex;
  }

  Stream<InteractionCounts> streamInteractions(String noteId,
      {InteractionCounts? initialCounts}) {

    if (!_streams.containsKey(noteId)) {
      _streams[noteId] = StreamController<InteractionCounts>.broadcast();
      if (initialCounts != null && !_cache.containsKey(noteId)) {
        _cache[noteId] = initialCounts;
        Future.microtask(() => _emit(noteId, initialCounts));
      }
      if (initialCounts == null || _isEmptyCounts(initialCounts)) {
        _scheduleBatchLoad(noteId);
      }
    } else if (_cache.containsKey(noteId)) {
      Future.microtask(() => _emit(noteId, _cache[noteId]!));
    } else if (initialCounts != null) {
      _cache[noteId] = initialCounts;
      Future.microtask(() => _emit(noteId, initialCounts));
      if (_isEmptyCounts(initialCounts)) {
        _scheduleBatchLoad(noteId);
      }
    }
    return _streams[noteId]!.stream;
  }

  bool _isEmptyCounts(InteractionCounts counts) {
    return counts.reactions == 0 &&
        counts.reposts == 0 &&
        counts.replies == 0 &&
        counts.zapAmount == 0;
  }

  void _scheduleBatchLoad(String noteId) {
    _pendingBatch.add(noteId);
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchDelay, _flushBatch);
  }

  Future<void> _flushBatch() async {
    if (_batchLoading || _pendingBatch.isEmpty) return;
    _batchLoading = true;

    final batch = _pendingBatch.toList();
    _pendingBatch.clear();

    for (var i = 0; i < batch.length; i += _batchSize) {
      final chunk = batch.skip(i).take(_batchSize).toList();
      await _loadBatchFromDb(chunk);
    }

    _batchLoading = false;

    if (_pendingBatch.isNotEmpty) {
      _flushBatch();
    }
  }

  Future<void> _loadBatchFromDb(List<String> noteIds) async {
    if (_currentUserHex == null || noteIds.isEmpty) return;

    try {
      final data =
          await _db.getBatchInteractionData(noteIds, _currentUserHex!);

      for (final noteId in noteIds) {
        final d = data[noteId];
        if (d == null) continue;

        final hasReacted =
            _localReactions.contains(noteId) || (d['hasReacted'] == true);
        final hasReposted =
            _localReposts.contains(noteId) || (d['hasReposted'] == true);
        final hasZapped =
            _localZaps.contains(noteId) || (d['hasZapped'] == true);

        if (hasReacted) _localReactions.add(noteId);
        if (hasReposted) _localReposts.add(noteId);

        final counts = InteractionCounts(
          reactions: (d['reactions'] as num?)?.toInt() ?? 0,
          reposts: (d['reposts'] as num?)?.toInt() ?? 0,
          replies: (d['replies'] as num?)?.toInt() ?? 0,
          zapAmount: (d['zaps'] as num?)?.toInt() ?? 0,
          hasReacted: hasReacted,
          hasReposted: hasReposted,
          hasZapped: hasZapped,
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
    } catch (_) {}
  }

  void prePopulateCache(String noteId, InteractionCounts counts) {
    if (!_cache.containsKey(noteId)) {
      _cache[noteId] = counts;
    }
  }

  Future<void> refreshInteractions(String noteId) async {
    if (_currentUserHex == null) return;
    await _loadBatchFromDb([noteId]);
  }

  Future<void> refreshAllActive() async {
    final activeNoteIds = _streams.keys.toList();
    if (activeNoteIds.isEmpty || _currentUserHex == null) return;
    await _loadBatchFromDb(activeNoteIds);
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
    _localZaps.add(noteId);
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

  void _refreshActiveStreams() {
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      final activeNoteIds = _streams.keys.toList();
      if (activeNoteIds.isEmpty || _currentUserHex == null) return;
      _loadBatchFromDb(activeNoteIds);
    });
  }

  void dispose() {
    _dbChangeSubscription?.cancel();
    _dbChangeSubscription = null;
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = null;
    _batchTimer?.cancel();
    _batchTimer = null;
    for (final controller in _streams.values) {
      controller.close();
    }
    _streams.clear();
    _cache.clear();
    _localReactions.clear();
    _localReposts.clear();
    _localZaps.clear();
  }
}
