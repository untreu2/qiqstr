import 'dart:async';
import 'dart:convert';
import 'rust_database_service.dart';
import '../../domain/entities/feed_note.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../../src/rust/api/relay.dart' as rust_relay;

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
    _dbChangeSubscription = _db.onInteractionChange.listen((_) {
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
      if (_cache.containsKey(noteId)) {
        final cached = _cache[noteId]!;
        if (initialCounts != null && !_isEmptyCounts(initialCounts)) {
          final merged = _mergeCounts(cached, initialCounts);
          _cache[noteId] = merged;
          Future.microtask(() => _emit(noteId, merged));
        } else {
          Future.microtask(() => _emit(noteId, cached));
        }
        if (_isEmptyCounts(_cache[noteId]!)) {
          _scheduleBatchLoad(noteId);
        }
      } else if (initialCounts != null && !_isEmptyCounts(initialCounts)) {
        _cache[noteId] = initialCounts;
        Future.microtask(() => _emit(noteId, initialCounts));
        _scheduleBatchLoad(noteId);
      } else {
        _scheduleBatchLoad(noteId);
      }
    } else if (_cache.containsKey(noteId)) {
      final cached = _cache[noteId]!;
      if (initialCounts != null && !_isEmptyCounts(initialCounts)) {
        final merged = _mergeCounts(cached, initialCounts);
        _cache[noteId] = merged;
        Future.microtask(() => _emit(noteId, merged));
      } else {
        Future.microtask(() => _emit(noteId, cached));
      }
    } else if (initialCounts != null && !_isEmptyCounts(initialCounts)) {
      _cache[noteId] = initialCounts;
      Future.microtask(() => _emit(noteId, initialCounts));
      _scheduleBatchLoad(noteId);
    } else {
      _scheduleBatchLoad(noteId);
    }
    return _streams[noteId]!.stream;
  }

  bool _isEmptyCounts(InteractionCounts counts) {
    return counts.reactions == 0 &&
        counts.reposts == 0 &&
        counts.replies == 0 &&
        counts.zapAmount == 0 &&
        !counts.hasReacted &&
        !counts.hasReposted &&
        !counts.hasZapped;
  }

  InteractionCounts _mergeCounts(InteractionCounts a, InteractionCounts b) {
    return InteractionCounts(
      reactions: a.reactions > b.reactions ? a.reactions : b.reactions,
      reposts: a.reposts > b.reposts ? a.reposts : b.reposts,
      replies: a.replies > b.replies ? a.replies : b.replies,
      zapAmount: a.zapAmount > b.zapAmount ? a.zapAmount : b.zapAmount,
      hasReacted: a.hasReacted || b.hasReacted,
      hasReposted: a.hasReposted || b.hasReposted,
      hasZapped: a.hasZapped || b.hasZapped,
    );
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

  bool _differs(InteractionCounts a, InteractionCounts b) =>
      a.reactions != b.reactions ||
      a.reposts != b.reposts ||
      a.replies != b.replies ||
      a.zapAmount != b.zapAmount ||
      a.hasReacted != b.hasReacted ||
      a.hasReposted != b.hasReposted ||
      a.hasZapped != b.hasZapped;

  void _applyData(
    String noteId,
    Map<String, dynamic> d, {
    required int newReactions,
    required int newReposts,
    required int newReplies,
    required int newZaps,
  }) {
    final existing = _cache[noteId];
    final counts = InteractionCounts(
      reactions: existing != null && existing.reactions > newReactions
          ? existing.reactions
          : newReactions,
      reposts: existing != null && existing.reposts > newReposts
          ? existing.reposts
          : newReposts,
      replies: existing != null && existing.replies > newReplies
          ? existing.replies
          : newReplies,
      zapAmount: existing != null && existing.zapAmount > newZaps
          ? existing.zapAmount
          : newZaps,
      hasReacted: _localReactions.contains(noteId) ||
          (d['hasReacted'] == true) ||
          (existing?.hasReacted ?? false),
      hasReposted: _localReposts.contains(noteId) ||
          (d['hasReposted'] == true) ||
          (existing?.hasReposted ?? false),
      hasZapped: _localZaps.contains(noteId) ||
          (d['hasZapped'] == true) ||
          (existing?.hasZapped ?? false),
    );
    if (existing == null || _differs(existing, counts)) {
      _cache[noteId] = counts;
      _emit(noteId, counts);
    }
  }

  Future<void> _loadBatchFromDb(List<String> noteIds) async {
    if (_currentUserHex == null || noteIds.isEmpty) return;

    try {
      final json = await rust_db.dbGetBatchInteractionData(
        noteIds: noteIds,
        userPubkeyHex: _currentUserHex!,
      );
      final data = (jsonDecode(json) as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      );

      for (final noteId in noteIds) {
        final d = data[noteId];
        if (d == null) continue;
        _applyData(
          noteId,
          d,
          newReactions: (d['reactions'] as num?)?.toInt() ?? 0,
          newReposts: (d['reposts'] as num?)?.toInt() ?? 0,
          newReplies: (d['replies'] as num?)?.toInt() ?? 0,
          newZaps: (d['zaps'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
  }

  void populateFromNotes(List<FeedNote> notes) {
    for (final note in notes) {
      prePopulateCache(
        note.id,
        InteractionCounts(
          reactions: note.reactionCount,
          reposts: note.repostCount,
          replies: note.replyCount,
          zapAmount: note.zapCount,
          hasReacted: note.hasReacted,
          hasReposted: note.hasReposted,
          hasZapped: note.hasZapped,
        ),
      );
    }
  }

  void prePopulateCache(String noteId, InteractionCounts counts) {
    final existing = _cache[noteId];
    if (existing == null) {
      _cache[noteId] = counts;
    } else {
      _cache[noteId] = _mergeCounts(existing, counts);
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

  Future<void> fetchCountsFromRelays(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    try {
      final json = await rust_relay.fetchCountsFromRelays(
        noteIds: noteIds,
        userPubkeyHex: _currentUserHex,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      for (final noteId in noteIds) {
        final d = decoded[noteId];
        if (d == null) continue;
        _applyData(
          noteId,
          d,
          newReactions: (d['reactions'] as num?)?.toInt() ?? 0,
          newReposts: (d['reposts'] as num?)?.toInt() ?? 0,
          newReplies: (d['replies'] as num?)?.toInt() ?? 0,
          newZaps: (d['zaps'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
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
  bool hasZapped(String noteId) => _localZaps.contains(noteId);

  void disposeStream(String noteId) {
    _streams[noteId]?.close();
    _streams.remove(noteId);
  }

  void clearCache() {
    _cache.clear();
  }

  void _refreshActiveStreams() {
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 200), () {
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
