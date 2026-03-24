import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/events.dart' as rust_events;

class NostrService {
  static final Map<String, Map<String, dynamic>> _filterCache = {};
  static final Map<String, String> _requestCache = {};
  static const int _maxCacheSize = 1000;

  static int _filtersCreated = 0;
  static int _requestsCreated = 0;
  static int _cacheHits = 0;
  static int _cacheMisses = 0;

  static final Queue<Map<String, dynamic>> _batchQueue = Queue();
  static bool _isBatchProcessing = false;

  static Future<Map<String, dynamic>> createNoteEvent({
    required String content,
    List<List<String>>? tags,
  }) async {
    final json = await rust_events.signEventWithSigner(
      kind: 1,
      content: content,
      tags: tags ?? [],
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createReactionEvent({
    required String targetEventId,
    required String targetAuthor,
    required String content,
    String? relayUrl,
    int targetKind = 1,
  }) async {
    final tags = <List<String>>[
      ['e', targetEventId, relayUrl ?? ''],
      ['p', targetAuthor],
      ['k', targetKind.toString()],
    ];
    final json = await rust_events.signEventWithSigner(
      kind: 7,
      content: content,
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createReplyEvent({
    required String content,
    required List<List<String>> tags,
  }) async {
    final json = await rust_events.signEventWithSigner(
      kind: 1,
      content: content,
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createRepostEvent({
    required String noteId,
    required String noteAuthor,
    required String content,
    String? relayUrl,
  }) async {
    final tags = <List<String>>[
      ['e', noteId, relayUrl ?? ''],
      ['p', noteAuthor],
    ];
    final json = await rust_events.signEventWithSigner(
      kind: 6,
      content: content,
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createDeletionEvent({
    required List<String> eventIds,
    String? reason,
  }) async {
    final tags = eventIds.map((id) => ['e', id]).toList();
    final json = await rust_events.signEventWithSigner(
      kind: 5,
      content: reason ?? '',
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createProfileEvent({
    required Map<String, dynamic> profileContent,
  }) async {
    final json = await rust_events.signEventWithSigner(
      kind: 0,
      content: jsonEncode(profileContent),
      tags: [],
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createFollowEvent({
    required List<String> followingPubkeys,
  }) async {
    final tags = followingPubkeys.map((pk) => ['p', pk, '']).toList();
    final json = await rust_events.signEventWithSigner(
      kind: 3,
      content: '',
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createMuteEvent({
    required String encryptedContent,
  }) async {
    final json = await rust_events.signEventWithSigner(
      kind: 10000,
      content: encryptedContent,
      tags: [],
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createReportEvent({
    required String reportedPubkey,
    required String reportType,
    String content = '',
  }) async {
    final tags = <List<String>>[
      ['p', reportedPubkey, reportType],
    ];
    final json = await rust_events.signEventWithSigner(
      kind: 1984,
      content: content,
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createZapRequestEvent({
    required List<List<String>> tags,
    required String content,
  }) async {
    final json = await rust_events.signEventWithSigner(
      kind: 9734,
      content: content,
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createQuoteEvent({
    required String content,
    required String quotedEventId,
    String? quotedEventPubkey,
    String? relayUrl,
    List<List<String>>? additionalTags,
  }) async {
    final tags = <List<String>>[];
    if (quotedEventPubkey != null) {
      tags.add(['q', quotedEventId, relayUrl ?? '', quotedEventPubkey]);
      tags.add(['p', quotedEventPubkey]);
    } else {
      tags.add(['q', quotedEventId, relayUrl ?? '']);
    }
    if (additionalTags != null) tags.addAll(additionalTags);

    final json = await rust_events.signEventWithSigner(
      kind: 1,
      content: content,
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createBlossomAuthEvent({
    required String content,
    required String sha256Hash,
    required int expiration,
  }) async {
    final tags = <List<String>>[
      ['t', 'upload'],
      ['x', sha256Hash],
      ['expiration', expiration.toString()],
    ];
    final json = await rust_events.signEventWithSigner(
      kind: 24242,
      content: content,
      tags: tags,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Map<String, dynamic> createNotesFilter({
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

    final filter = <String, dynamic>{};
    if (authors != null && authors.isNotEmpty) filter['authors'] = authors;
    filter['kinds'] = kinds ?? [1, 6];
    if (limit != null) filter['limit'] = limit;
    if (since != null) filter['since'] = since;
    if (until != null) filter['until'] = until;

    _addToFilterCache(cacheKey, filter);
    return filter;
  }

  static Map<String, dynamic> createProfileFilter({
    required List<String> authors,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      'kinds': [0],
    };
    if (authors.isNotEmpty) filter['authors'] = authors;
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createFollowingFilter({
    required List<String> authors,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      'kinds': [3],
    };
    if (authors.isNotEmpty) filter['authors'] = authors;
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createMuteFilter({
    required List<String> authors,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      'kinds': [10000],
    };
    if (authors.isNotEmpty) filter['authors'] = authors;
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createBookmarkFilter({
    required List<String> authors,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      'kinds': [30001],
      '#d': ['bookmark'],
    };
    if (authors.isNotEmpty) filter['authors'] = authors;
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createPinnedNotesFilter({
    required List<String> authors,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      'kinds': [10001],
    };
    if (authors.isNotEmpty) filter['authors'] = authors;
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createFollowSetsFilter({
    required List<String> authors,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      'kinds': [30000],
    };
    if (authors.isNotEmpty) filter['authors'] = authors;
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createNotificationFilter({
    required List<String> pubkeys,
    List<int>? kinds,
    int? since,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      '#p': pubkeys,
      'kinds': kinds ?? [1, 6, 7, 9735],
    };
    if (since != null) filter['since'] = since;
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createEventByIdFilter({
    required List<String> eventIds,
  }) {
    return <String, dynamic>{
      'ids': eventIds,
    };
  }

  static Map<String, dynamic> createCombinedInteractionFilter({
    required List<String> eventIds,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      'kinds': [7, 1, 5, 6, 9735],
      '#e': eventIds,
    };
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createThreadRepliesFilter({
    required String rootNoteId,
    int? limit,
  }) {
    return <String, dynamic>{
      'kinds': [1],
      '#e': [rootNoteId],
      'limit': limit ?? 100,
    };
  }

  static Map<String, dynamic> createInteractionFilter({
    required List<int> kinds,
    required List<String> eventIds,
    int? limit,
    int? since,
  }) {
    final filter = <String, dynamic>{
      'kinds': kinds,
      '#e': eventIds,
    };
    if (limit != null) filter['limit'] = limit;
    if (since != null) filter['since'] = since;
    return filter;
  }

  static Map<String, dynamic> createQuoteFilter({
    required List<int> kinds,
    required List<String> quotedEventIds,
    int? limit,
  }) {
    final filter = <String, dynamic>{
      'kinds': kinds,
      '#q': quotedEventIds,
    };
    if (limit != null) filter['limit'] = limit;
    return filter;
  }

  static Map<String, dynamic> createArticlesFilter({
    List<String>? authors,
    int? limit,
    int? since,
    int? until,
  }) {
    final filter = <String, dynamic>{
      'kinds': [30023],
    };
    if (authors != null && authors.isNotEmpty) filter['authors'] = authors;
    if (limit != null) filter['limit'] = limit;
    if (since != null) filter['since'] = since;
    if (until != null) filter['until'] = until;
    return filter;
  }

  static Map<String, dynamic> createHashtagFilter({
    required String hashtag,
    List<int>? kinds,
    int? limit,
    int? since,
    int? until,
  }) {
    final filter = <String, dynamic>{
      'kinds': kinds ?? [1],
      '#t': [hashtag.toLowerCase()],
      'limit': limit ?? 100,
    };
    if (since != null) filter['since'] = since;
    if (until != null) filter['until'] = until;
    return filter;
  }

  static String createRequest(Map<String, dynamic> filter) {
    final uuid = generateUUID();
    final cacheKey = 'single_${filter.hashCode}';

    if (_requestCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _requestCache[cacheKey]!;
    }

    _cacheMisses++;
    _requestsCreated++;

    final request = jsonEncode(['REQ', uuid, filter]);
    _addToRequestCache(cacheKey, request);
    return request;
  }

  static String createMultiFilterRequest(List<Map<String, dynamic>> filters) {
    final uuid = generateUUID();
    final cacheKey = 'multi_${filters.map((f) => f.hashCode).join('_')}';

    if (_requestCache.containsKey(cacheKey)) {
      _cacheHits++;
      return _requestCache[cacheKey]!;
    }

    _cacheMisses++;
    _requestsCreated++;

    final request = jsonEncode(['REQ', uuid, ...filters]);
    _addToRequestCache(cacheKey, request);
    return request;
  }

  static String generateUUID() {
    return const Uuid().v4().replaceAll('-', '');
  }

  static String serializeEvent(Map<String, dynamic> event) =>
      jsonEncode(['EVENT', event]);

  static String serializeRequest(String request) => request;

  static String serializeCountRequest(
      String subscriptionId, Map<String, dynamic> filter) {
    return jsonEncode(['COUNT', subscriptionId, filter]);
  }

  static Map<String, dynamic> eventToJson(Map<String, dynamic> event) => event;

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
    required String rootAuthor,
    String? replyAuthor,
    List<String> relayUrls = const [],
  }) {
    List<List<String>> tags = [];

    if (replyId != null && replyId != rootId) {
      tags.add(['e', rootId, '', 'root']);
      tags.add(['e', replyId, '', 'reply']);
      tags.add(['p', rootAuthor]);
      if (replyAuthor != null && replyAuthor != rootAuthor) {
        tags.add(['p', replyAuthor]);
      }
    } else {
      tags.add(['e', rootId, '', 'root']);
      tags.add(['p', rootAuthor]);
    }

    for (final url in relayUrls) {
      tags.add(['r', url]);
    }

    return tags;
  }

  static String calculateSha256Hash(List<int> fileBytes) {
    return rust_crypto.sha256Hash(data: fileBytes);
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

  static Future<List<dynamic>> processBatch() async {
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
            results.add(await createNoteEvent(
              content: params['content'],
              tags: params['tags'],
            ));
            break;
          case 'createReactionEvent':
            results.add(await createReactionEvent(
              targetEventId: params['targetEventId'],
              targetAuthor: params['targetAuthor'],
              content: params['content'],
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

  static String _generateFilterCacheKey(
      String type, Map<String, dynamic> params) {
    return 'filter_${type}_${params.hashCode}';
  }

  static void _addToFilterCache(String key, Map<String, dynamic> filter) {
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
    final hitRate = _cacheHits + _cacheMisses > 0
        ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1)
        : '0.0';

    return {
      'filtersCreated': _filtersCreated,
      'requestsCreated': _requestsCreated,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': '$hitRate%',
      'filterCacheSize': _filterCache.length,
      'requestCacheSize': _requestCache.length,
      'batchQueueSize': _batchQueue.length,
      'isBatchProcessing': _isBatchProcessing,
    };
  }

  static void clearFilterCache() {
    _filterCache.clear();
  }

  static void clearRequestCache() {
    _requestCache.clear();
  }

  static void clearAllCaches() {
    clearFilterCache();
    clearRequestCache();
    _batchQueue.clear();
  }

  static Future<List<Map<String, dynamic>>> createMultipleNoteEvents(
      List<Map<String, dynamic>> eventData) async {
    final results = <Map<String, dynamic>>[];
    for (final data in eventData) {
      results.add(await createNoteEvent(
        content: data['content'],
        tags: data['tags'],
      ));
    }
    return results;
  }

  static List<Map<String, dynamic>> createMultipleFilters(
      List<Map<String, dynamic>> filterData) {
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

  static Future<String> sendMedia({
    required String filePath,
    required String blossomUrl,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileBytes = await file.readAsBytes();
    final hash = calculateSha256Hash(fileBytes);
    final mimeType = detectMimeType(filePath);
    final expiration = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 600;

    final authEventJson = await rust_events.signEventWithSigner(
      kind: 24242,
      content: 'Upload $filePath',
      tags: [
        ['t', 'upload'],
        ['x', hash],
        ['expiration', expiration.toString()],
      ],
    );

    final authBase64 = base64Encode(utf8.encode(authEventJson));
    final cleanedUrl = blossomUrl.replaceAll(RegExp(r'/+$'), '');

    final httpClient = HttpClient();
    try {
      final request = await httpClient.putUrl(Uri.parse('$cleanedUrl/upload'));
      request.headers.set('Authorization', 'Nostr $authBase64');
      request.headers.set('Content-Type', mimeType);
      request.add(fileBytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final responseData = jsonDecode(responseBody) as Map<String, dynamic>;
        final url = responseData['url'] as String? ?? '';
        final sha256 = responseData['sha256'] as String? ?? '';
        return url.isNotEmpty ? url : sha256;
      } else {
        throw Exception(
            'Upload failed with status ${response.statusCode}: $responseBody');
      }
    } finally {
      httpClient.close();
    }
  }
}
