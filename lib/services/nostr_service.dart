import 'dart:convert';
import 'dart:collection';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class NostrService {
  static final Map<String, Nip01Event> _eventCache = {};
  static final Map<String, Filter> _filterCache = {};
  static final Map<String, String> _requestCache = {};
  static const int _maxCacheSize = 1000;

  static int _eventsCreated = 0;
  static int _filtersCreated = 0;
  static int _requestsCreated = 0;
  static int _cacheHits = 0;
  static int _cacheMisses = 0;

  static final Queue<Map<String, dynamic>> _batchQueue = Queue();
  static bool _isBatchProcessing = false;

  static Nip01Event createNoteEvent({
    required String content,
    required String privateKey,
    List<List<String>>? tags,
  }) {
    final cacheKey = _generateEventCacheKey(1, content, privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 1,
      tags: tags ?? [],
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createReactionEvent({
    required String targetEventId,
    required String content,
    required String privateKey,
  }) {
    final tags = [
      ['e', targetEventId]
    ];
    final cacheKey = _generateEventCacheKey(7, content, privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 7,
      tags: tags,
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createReplyEvent({
    required String content,
    required String privateKey,
    required List<List<String>> tags,
  }) {
    final cacheKey = _generateEventCacheKey(1, content, privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 1,
      tags: tags,
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createRepostEvent({
    required String noteId,
    required String noteAuthor,
    required String content,
    required String privateKey,
  }) {
    final tags = [
      ['e', noteId],
      ['p', noteAuthor],
    ];

    final cacheKey = _generateEventCacheKey(6, content, privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 6,
      tags: tags,
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createDeletionEvent({
    required List<String> eventIds,
    required String privateKey,
    String? reason,
  }) {
    final tags = eventIds.map((id) => ['e', id]).toList();
    final content = reason ?? '';

    final cacheKey = _generateEventCacheKey(5, content, privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 5,
      tags: tags,
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createProfileEvent({
    required Map<String, dynamic> profileContent,
    required String privateKey,
  }) {
    final content = jsonEncode(profileContent);
    final cacheKey = _generateEventCacheKey(0, content, privateKey, []);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 0,
      tags: [],
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createFollowEvent({
    required List<String> followingPubkeys,
    required String privateKey,
  }) {
    final tags = followingPubkeys.map((pubkey) => ['p', pubkey, '']).toList();
    final cacheKey = _generateEventCacheKey(3, "", privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 3,
      tags: tags,
      content: "",
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createMuteEvent({
    required List<String> mutedPubkeys,
    required String privateKey,
  }) {
    final tags = mutedPubkeys.map((pubkey) => ['p', pubkey]).toList();
    final cacheKey = _generateEventCacheKey(10000, "", privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 10000,
      tags: tags,
      content: "",
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createZapRequestEvent({
    required List<List<String>> tags,
    required String content,
    required String privateKey,
  }) {
    final cacheKey = _generateEventCacheKey(9734, content, privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 9734,
      tags: tags,
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createQuoteEvent({
    required String content,
    required String quotedEventId,
    String? quotedEventPubkey,
    String? relayUrl,
    required String privateKey,
    List<List<String>>? additionalTags,
  }) {
    final List<List<String>> tags = [];

    if (quotedEventPubkey != null) {
      tags.add(['q', quotedEventId, relayUrl ?? '', quotedEventPubkey]);
    } else {
      tags.add(['q', quotedEventId, relayUrl ?? '']);
    }

    if (quotedEventPubkey != null) {
      tags.add(['p', quotedEventPubkey]);
    }

    if (additionalTags != null) {
      tags.addAll(additionalTags);
    }

    final cacheKey = _generateEventCacheKey(1, content, privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 1,
      tags: tags,
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Nip01Event createBlossomAuthEvent({
    required String content,
    required String sha256Hash,
    required int expiration,
    required String privateKey,
  }) {
    final tags = [
      ['t', 'upload'],
      ['x', sha256Hash],
      ['expiration', expiration.toString()],
    ];

    final cacheKey = _generateEventCacheKey(24242, content, privateKey, tags);

    if (_eventCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _eventCache[cacheKey]!;
    }

    _cacheMisses++;
    _eventsCreated++;

    final publicKey = Bip340.getPublicKey(privateKey);
    final event = Nip01Event(
      pubKey: publicKey,
      kind: 24242,
      tags: tags,
      content: content,
    );
    event.sig = Bip340.sign(event.id, privateKey);

    _addToEventCache(cacheKey, event);
    return event;
  }

  static Filter createNotesFilter({
    List<String>? authors,
    List<int>? kinds,
    int? limit,
    int? since,
    int? until,
  }) {
    final cacheKey = _generateFilterCacheKey('notes', {
      'authors': authors,
      'kinds': kinds ?? [1, 6],
      'limit': limit,
      'since': since,
      'until': until,
    });

    if (_filterCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _filterCache[cacheKey]!;
    }

    _cacheMisses++;
    _filtersCreated++;

    final filter = Filter(
      authors: authors,
      kinds: kinds ?? [1, 6],
      limit: limit,
      since: since,
      until: until,
    );

    _addToFilterCache(cacheKey, filter);
    return filter;
  }

  static Filter createProfileFilter({
    required List<String> authors,
    int? limit,
  }) {
    return Filter(
      authors: authors,
      kinds: [0],
      limit: limit,
    );
  }


  static Filter createFollowingFilter({
    required List<String> authors,
    int? limit,
  }) {
    return Filter(
      authors: authors,
      kinds: [3],
      limit: limit,
    );
  }

  static Filter createMuteFilter({
    required List<String> authors,
    int? limit,
  }) {
    return Filter(
      authors: authors,
      kinds: [10000],
      limit: limit,
    );
  }

  static Filter createNotificationFilter({
    required List<String> pubkeys,
    List<int>? kinds,
    int? since,
    int? limit,
  }) {
    return Filter(
      pTags: pubkeys,
      kinds: kinds ?? [1, 6, 7, 9735],
      since: since,
      limit: limit,
    );
  }

  static Filter createEventByIdFilter({
    required List<String> eventIds,
  }) {
    return Filter(
      ids: eventIds,
    );
  }

  static Filter createCombinedInteractionFilter({
    required List<String> eventIds,
    int? limit,
  }) {
    return Filter(
      kinds: [7, 1, 6, 9735],
      eTags: eventIds,
      limit: limit,
    );
  }

  static String createRequest(Filter filter) {
    final uuid = generateUUID();
    final cacheKey = 'single_${filter.hashCode}';

    if (_requestCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _requestCache[cacheKey]!;
    }

    _cacheMisses++;
    _requestsCreated++;

    final request = jsonEncode(['REQ', uuid, filter.toJson()]);
    _addToRequestCache(cacheKey, request);
    return request;
  }

  static String createMultiFilterRequest(List<Filter> filters) {
    final uuid = generateUUID();
    final cacheKey = 'multi_${filters.map((f) => f.hashCode).join('_')}';

    if (_requestCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _requestCache[cacheKey]!;
    }

    _cacheMisses++;
    _requestsCreated++;

    final filterList = filters.map((f) => f.toJson()).toList();
    final request = jsonEncode(['REQ', uuid, ...filterList]);
    _addToRequestCache(cacheKey, request);
    return request;
  }

  static String generateUUID() {
    return const Uuid().v4().replaceAll('-', '');
  }

  static String serializeEvent(Nip01Event event) => jsonEncode(['EVENT', event.toJson()]);

  static String serializeRequest(String request) => request;


  static String serializeCountRequest(String subscriptionId, Filter filter) {
    final filterMap = filter.toJson();
    return jsonEncode(['COUNT', subscriptionId, filterMap]);
  }

  static Map<String, dynamic> eventToJson(Nip01Event event) => event.toJson();

  static List<List<String>> createZapRequestTags({
    required List<String> relays,
    required String amountMillisats,
    required String recipientPubkey,
    String? lnurlBech32,
    String? noteId,
  }) {
    final List<List<String>> tags = [
      ['relays', ...relays],
      ['amount', amountMillisats],
      ['p', recipientPubkey],
    ];

    if (lnurlBech32 != null && lnurlBech32.isNotEmpty) {
      tags.add(['lnurl', lnurlBech32]);
    }

    if (noteId != null && noteId.isNotEmpty) {
      tags.add(['e', noteId]);
    }

    return tags;
  }

  static List<List<String>> createReplyTags({
    required String rootId,
    String? replyId,
    required String parentAuthor,
    required List<String> relayUrls,
  }) {
    List<List<String>> tags = [];

    if (replyId != null && replyId != rootId) {
      tags.add(['e', rootId, '', 'root', parentAuthor]);
      tags.add(['e', replyId, '', 'reply', parentAuthor]);
    } else {
      tags.add(['e', rootId, '', 'root', parentAuthor]);
    }

    tags.add(['p', parentAuthor]);

    return tags;
  }

  static String calculateSha256Hash(List<int> fileBytes) {
    return sha256.convert(fileBytes).toString();
  }

  static String detectMimeType(String filePath) {
    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      return 'image/jpeg';
    } else if (lowerPath.endsWith('.png')) {
      return 'image/png';
    } else if (lowerPath.endsWith('.gif')) {
      return 'image/gif';
    } else if (lowerPath.endsWith('.mp4')) {
      return 'video/mp4';
    }
    return 'application/octet-stream';
  }

  static void addToBatch(String operation, Map<String, dynamic> params) {
    _batchQueue.add({
      'operation': operation,
      'params': params,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (_batchQueue.length >= 10) {
      processBatch();
    }
  }

  static List<dynamic> processBatch() {
    if (_isBatchProcessing || _batchQueue.isEmpty) return [];

    _isBatchProcessing = true;
    final results = <dynamic>[];

    try {
      while (_batchQueue.isNotEmpty && results.length < 20) {
        final item = _batchQueue.removeFirst();
        final operation = item['operation'] as String;
        final params = item['params'] as Map<String, dynamic>;

        switch (operation) {
          case 'createNoteEvent':
            results.add(createNoteEvent(
              content: params['content'],
              privateKey: params['privateKey'],
              tags: params['tags'],
            ));
            break;
          case 'createReactionEvent':
            results.add(createReactionEvent(
              targetEventId: params['targetEventId'],
              content: params['content'],
              privateKey: params['privateKey'],
            ));
            break;
          case 'createFilter':
            results.add(createNotesFilter(
              authors: params['authors'],
              kinds: params['kinds'],
              limit: params['limit'],
              since: params['since'],
              until: params['until'],
            ));
            break;
        }
      }
    } finally {
      _isBatchProcessing = false;
    }

    return results;
  }

  static String _generateEventCacheKey(int kind, String content, String privateKey, List<List<String>>? tags) {
    final tagsStr = tags?.map((tag) => tag.join(':')).join('|') ?? '';

    final publicKey = Bip340.getPublicKey(privateKey);
    final publicKeyHash = publicKey.hashCode;
    return 'event_${kind}_${content.hashCode}_${publicKeyHash}_${tagsStr.hashCode}';
  }

  static String _generateFilterCacheKey(String type, Map<String, dynamic> params) {
    return 'filter_${type}_${params.hashCode}';
  }

  static void _addToEventCache(String key, Nip01Event event) {
    if (_eventCache.length >= _maxCacheSize) {
      _evictOldestCacheEntry(_eventCache);
    }
    _eventCache[key] = event;
  }

  static void _addToFilterCache(String key, Filter filter) {
    if (_filterCache.length >= _maxCacheSize) {
      _evictOldestCacheEntry(_filterCache);
    }
    _filterCache[key] = filter;
  }

  static void _addToRequestCache(String key, String request) {
    if (_requestCache.length >= _maxCacheSize) {
      _evictOldestCacheEntry(_requestCache);
    }
    _requestCache[key] = request;
  }

  static void _evictOldestCacheEntry(Map<String, dynamic> cache) {
    if (cache.isNotEmpty) {
      final firstKey = cache.keys.first;
      cache.remove(firstKey);
    }
  }

  static Map<String, dynamic> getNostrStats() {
    final hitRate = _cacheHits + _cacheMisses > 0 ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1) : '0.0';

    return {
      'eventsCreated': _eventsCreated,
      'filtersCreated': _filtersCreated,
      'requestsCreated': _requestsCreated,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': '$hitRate%',
      'eventCacheSize': _eventCache.length,
      'filterCacheSize': _filterCache.length,
      'requestCacheSize': _requestCache.length,
      'batchQueueSize': _batchQueue.length,
      'isBatchProcessing': _isBatchProcessing,
    };
  }

  static void clearEventCache() {
    _eventCache.clear();
  }

  static void clearFilterCache() {
    _filterCache.clear();
  }

  static void clearRequestCache() {
    _requestCache.clear();
  }

  static void clearAllCaches() {
    clearEventCache();
    clearFilterCache();
    clearRequestCache();
    _batchQueue.clear();
  }

  static List<Nip01Event> createMultipleNoteEvents(List<Map<String, dynamic>> eventData) {
    return eventData
        .map((data) => createNoteEvent(
              content: data['content'],
              privateKey: data['privateKey'],
              tags: data['tags'],
            ))
        .toList();
  }

  static List<Filter> createMultipleFilters(List<Map<String, dynamic>> filterData) {
    return filterData
        .map((data) => createNotesFilter(
              authors: data['authors'],
              kinds: data['kinds'],
              limit: data['limit'],
              since: data['since'],
              until: data['until'],
            ))
        .toList();
  }

  static void preWarmCache() {
    createNotesFilter(kinds: [1, 6], limit: 50);
    createProfileFilter(authors: [], limit: 100);
    createCombinedInteractionFilter(eventIds: [], limit: 100);
    createNotificationFilter(pubkeys: [], limit: 50);
  }
}
