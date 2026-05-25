import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
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
  final Map<String, int> _streamRefCounts = {};
  final Map<String, InteractionCounts> _cache = {};
  static const int _maxCacheSize = 2000;

  final Set<String> _localReactions = {};
  final Set<String> _localReposts = {};
  final Set<String> _localZaps = {};

  final Map<String, DateTime> _lastUserActionAt = {};
  static const Duration _userActionTtl = Duration(seconds: 30);

  final Set<String> _relayFetchedAt = <String>{};
  final Map<String, DateTime> _relayFetchTimestamps = {};
  static const Duration _relayFetchCooldown = Duration(minutes: 5);

  String? _currentUserHex;
  StreamSubscription<void>? _dbChangeSubscription;
  Timer? _refreshDebounceTimer;

  final Set<String> _pendingBatch = {};
  Timer? _batchTimer;
  bool _batchLoading = false;
  static const Duration _batchDelay = Duration(milliseconds: 10);
  static const int _batchSize = 50;

  final Set<String> _pendingRelayBatch = <String>{};
  Timer? _relayBatchTimer;
  bool _relayBatchLoading = false;
  static const Duration _relayBatchDelay = Duration(milliseconds: 300);
  static const int _relayBatchSize = 40;

  void setCurrentUser(String? userHex) {
    if (_currentUserHex != null &&
        userHex != null &&
        _currentUserHex != userHex) {
      _cache.clear();
      _localReactions.clear();
      _localReposts.clear();
      _localZaps.clear();
      _lastUserActionAt.clear();
      _relayFetchedAt.clear();
      _relayFetchTimestamps.clear();
    }
    _currentUserHex = userHex;
  }

  Stream<InteractionCounts> streamInteractions(String noteId,
      {InteractionCounts? initialCounts}) {
    final hasStream = _streams.containsKey(noteId);
    if (!hasStream) {
      _streams[noteId] = StreamController<InteractionCounts>.broadcast();
      _streamRefCounts[noteId] = 1;
    } else {
      _streamRefCounts[noteId] = (_streamRefCounts[noteId] ?? 0) + 1;
    }

    if (initialCounts != null && !_isEmptyCounts(initialCounts)) {
      final merged = _adoptFresh(noteId, initialCounts);
      _cache[noteId] = merged;
      Future.microtask(() => _emit(noteId, merged));
    } else if (_cache.containsKey(noteId)) {
      final cached = _cache[noteId]!;
      Future.microtask(() => _emit(noteId, cached));
    }

    final current = _cache[noteId];
    if (current == null || _isEmptyCounts(current)) {
      _scheduleBatchLoad(noteId);
      _scheduleRelayBatchLoad(noteId);
    } else if (!_relayFetchedAt.contains(noteId)) {
      _scheduleRelayBatchLoad(noteId);
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

  InteractionCounts _adoptFresh(String noteId, InteractionCounts fresh) {
    final existing = _cache[noteId];
    final userActive = _hasRecentUserAction(noteId);

    final reactions = existing == null
        ? fresh.reactions
        : (userActive
            ? existing.reactions
            : math.max(fresh.reactions, existing.reactions));
    final reposts = existing == null
        ? fresh.reposts
        : (userActive
            ? existing.reposts
            : math.max(fresh.reposts, existing.reposts));
    final replies = existing == null
        ? fresh.replies
        : (userActive
            ? existing.replies
            : math.max(fresh.replies, existing.replies));
    final zapAmount = existing == null
        ? fresh.zapAmount
        : (userActive
            ? existing.zapAmount
            : math.max(fresh.zapAmount, existing.zapAmount));

    return InteractionCounts(
      reactions: reactions,
      reposts: reposts,
      replies: replies,
      zapAmount: zapAmount,
      hasReacted: _localReactions.contains(noteId) ||
          fresh.hasReacted ||
          (existing?.hasReacted ?? false),
      hasReposted: _localReposts.contains(noteId) ||
          fresh.hasReposted ||
          (existing?.hasReposted ?? false),
      hasZapped: _localZaps.contains(noteId) ||
          fresh.hasZapped ||
          (existing?.hasZapped ?? false),
    );
  }

  bool _hasRecentUserAction(String noteId) {
    final t = _lastUserActionAt[noteId];
    if (t == null) return false;
    if (DateTime.now().difference(t) > _userActionTtl) {
      _lastUserActionAt.remove(noteId);
      return false;
    }
    return true;
  }

  void _touchUserAction(String noteId) {
    _lastUserActionAt[noteId] = DateTime.now();
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
    bool authoritative = false,
  }) {
    final existing = _cache[noteId];

    if (!authoritative && existing != null && _hasRecentUserAction(noteId)) {
      _emit(noteId, existing);
      return;
    }

    final mergedReactions = existing == null
        ? newReactions
        : math.max(newReactions, existing.reactions);
    final mergedReposts = existing == null
        ? newReposts
        : math.max(newReposts, existing.reposts);
    final mergedReplies = existing == null
        ? newReplies
        : math.max(newReplies, existing.replies);
    final mergedZaps = existing == null
        ? newZaps
        : math.max(newZaps, existing.zapAmount);

    final counts = InteractionCounts(
      reactions: mergedReactions,
      reposts: mergedReposts,
      replies: mergedReplies,
      zapAmount: mergedZaps,
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
    } catch (e) {
      if (kDebugMode) debugPrint('[InteractionService] $e');
    }
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
    _cache[noteId] = _adoptFresh(noteId, counts);
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

      final now = DateTime.now();
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
        _relayFetchedAt.add(noteId);
        _relayFetchTimestamps[noteId] = now;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[InteractionService] $e');
    }
  }

  void _scheduleRelayBatchLoad(String noteId) {
    final last = _relayFetchTimestamps[noteId];
    if (last != null &&
        DateTime.now().difference(last) < _relayFetchCooldown) {
      return;
    }
    _pendingRelayBatch.add(noteId);
    _relayBatchTimer?.cancel();
    _relayBatchTimer = Timer(_relayBatchDelay, _flushRelayBatch);
  }

  Future<void> _flushRelayBatch() async {
    if (_relayBatchLoading || _pendingRelayBatch.isEmpty) return;
    _relayBatchLoading = true;

    final batch = _pendingRelayBatch.toList();
    _pendingRelayBatch.clear();

    for (var i = 0; i < batch.length; i += _relayBatchSize) {
      final chunk = batch.skip(i).take(_relayBatchSize).toList();
      try {
        await fetchCountsFromRelays(chunk);
      } catch (_) {}
    }

    _relayBatchLoading = false;

    if (_pendingRelayBatch.isNotEmpty) {
      _flushRelayBatch();
    }
  }

  void markReacted(String noteId) {
    _localReactions.add(noteId);
    _touchUserAction(noteId);
    _updateCache(
        noteId,
        (c) => c.copyWith(
              hasReacted: true,
              reactions: c.reactions + 1,
            ));
  }

  void markUnreacted(String noteId) {
    _localReactions.remove(noteId);
    _touchUserAction(noteId);
    _updateCache(
        noteId,
        (c) => c.copyWith(
              hasReacted: false,
              reactions: c.reactions > 0 ? c.reactions - 1 : 0,
            ));
  }

  void markReposted(String noteId) {
    _localReposts.add(noteId);
    _touchUserAction(noteId);
    _updateCache(
        noteId,
        (c) => c.copyWith(
              hasReposted: true,
              reposts: c.reposts + 1,
            ));
  }

  void markUnreposted(String noteId) {
    _localReposts.remove(noteId);
    _touchUserAction(noteId);
    _updateCache(
        noteId,
        (c) => c.copyWith(
              hasReposted: false,
              reposts: c.reposts > 0 ? c.reposts - 1 : 0,
            ));
  }

  void markZapped(String noteId, int amount) {
    _localZaps.add(noteId);
    _touchUserAction(noteId);
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
    final overflow = _cache.length - _maxCacheSize;
    final candidates = _cache.keys
        .where((k) => !_streams.containsKey(k))
        .take(overflow)
        .toList();
    for (final key in candidates) {
      _cache.remove(key);
      _relayFetchedAt.remove(key);
      _relayFetchTimestamps.remove(key);
      _lastUserActionAt.remove(key);
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
    final remaining = (_streamRefCounts[noteId] ?? 1) - 1;
    if (remaining <= 0) {
      _streams[noteId]?.close();
      _streams.remove(noteId);
      _streamRefCounts.remove(noteId);
    } else {
      _streamRefCounts[noteId] = remaining;
    }
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
    _relayBatchTimer?.cancel();
    _relayBatchTimer = null;
    for (final controller in _streams.values) {
      controller.close();
    }
    _streams.clear();
    _streamRefCounts.clear();
    _cache.clear();
    _localReactions.clear();
    _localReposts.clear();
    _localZaps.clear();
    _lastUserActionAt.clear();
    _relayFetchedAt.clear();
    _relayFetchTimestamps.clear();
    _pendingRelayBatch.clear();
  }
}
