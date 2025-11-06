import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/user_model.dart';
import '../../services/nostr_service.dart';
import '../../services/relay_service.dart';

enum FetchPriority {
  urgent,
  high,
  normal,
  low,
}

class UserFetchRequest {
  final String pubkeyHex;
  final FetchPriority priority;
  final DateTime requestedAt;
  final Completer<UserModel?> completer;

  UserFetchRequest({
    required this.pubkeyHex,
    required this.priority,
    required this.completer,
  }) : requestedAt = DateTime.now();

  int get priorityValue {
    switch (priority) {
      case FetchPriority.urgent:
        return 3;
      case FetchPriority.high:
        return 2;
      case FetchPriority.normal:
        return 1;
      case FetchPriority.low:
        return 0;
    }
  }
}

class UserBatchFetcher {
  static UserBatchFetcher? _instance;
  static UserBatchFetcher get instance => _instance ??= UserBatchFetcher._internal();

  UserBatchFetcher._internal() {
    _startBatchProcessor();
  }

  final WebSocketManager _relayManager = WebSocketManager.instance;

  static const int maxBatchSize = 50;
  static const Duration batchTimeout = Duration(milliseconds: 300);
  static const Duration requestTimeout = Duration(seconds: 5);
  static const int maxConcurrentBatches = 3;

  final PriorityQueue<UserFetchRequest> _requestQueue = PriorityQueue<UserFetchRequest>(
    (a, b) => b.priorityValue.compareTo(a.priorityValue),
  );

  final Set<String> _queuedPubkeys = {};

  Timer? _batchTimer;
  int _activeBatches = 0;
  bool _isProcessing = false;

  int _totalRequests = 0;
  int _batchesSent = 0;
  int _successfulFetches = 0;
  int _failedFetches = 0;

  Future<UserModel?> fetchUser(String pubkeyHex, {FetchPriority priority = FetchPriority.normal}) async {
    _totalRequests++;

    if (_queuedPubkeys.contains(pubkeyHex)) {
      debugPrint('[UserBatchFetcher] Request for $pubkeyHex already queued, waiting...');
      final existingRequest = _requestQueue._queue.firstWhere(
        (req) => req.pubkeyHex == pubkeyHex,
        orElse: () => UserFetchRequest(
          pubkeyHex: pubkeyHex,
          priority: priority,
          completer: Completer<UserModel?>(),
        ),
      );
      return await existingRequest.completer.future;
    }

    final completer = Completer<UserModel?>();
    final request = UserFetchRequest(
      pubkeyHex: pubkeyHex,
      priority: priority,
      completer: completer,
    );

    _requestQueue.add(request);
    _queuedPubkeys.add(pubkeyHex);

    debugPrint('[UserBatchFetcher] Queued fetch for $pubkeyHex (priority: $priority, queue size: ${_requestQueue.length})');

    if (priority == FetchPriority.urgent || _requestQueue.length >= maxBatchSize) {
      _triggerImmediateBatch();
    }

    return await completer.future;
  }

  Future<Map<String, UserModel?>> fetchUsers(
    List<String> pubkeyHexList, {
    FetchPriority priority = FetchPriority.normal,
  }) async {
    final futures = <String, Future<UserModel?>>{};

    for (final pubkeyHex in pubkeyHexList) {
      futures[pubkeyHex] = fetchUser(pubkeyHex, priority: priority);
    }

    final results = <String, UserModel?>{};
    for (final entry in futures.entries) {
      try {
        results[entry.key] = await entry.value;
      } catch (e) {
        debugPrint('[UserBatchFetcher] Error fetching user ${entry.key}: $e');
        results[entry.key] = null;
      }
    }

    return results;
  }

  void _startBatchProcessor() {
    _batchTimer?.cancel();
    _batchTimer = Timer.periodic(batchTimeout, (_) {
      _processBatch();
    });
  }

  void _triggerImmediateBatch() {
    _batchTimer?.cancel();
    _processBatch();
    _startBatchProcessor();
  }

  Future<void> _processBatch() async {
    if (_isProcessing || _requestQueue.length == 0) return;
    if (_activeBatches >= maxConcurrentBatches) {
      debugPrint('[UserBatchFetcher] Max concurrent batches reached, waiting...');
      return;
    }

    _isProcessing = true;

    try {
      final batchRequests = <UserFetchRequest>[];
      final pubkeysToFetch = <String>[];

      while (batchRequests.length < maxBatchSize && _requestQueue.length > 0) {
        final request = _requestQueue.removeFirst();
        batchRequests.add(request);
        pubkeysToFetch.add(request.pubkeyHex);
        _queuedPubkeys.remove(request.pubkeyHex);
      }

      if (batchRequests.isEmpty) {
        _isProcessing = false;
        return;
      }

      debugPrint('[UserBatchFetcher] Processing batch of ${batchRequests.length} users');
      _batchesSent++;
      _activeBatches++;

      final results = await _fetchProfilesFromRelays(pubkeysToFetch);

      for (final request in batchRequests) {
        final user = results[request.pubkeyHex];
        if (user != null) {
          _successfulFetches++;
          request.completer.complete(user);
        } else {
          _failedFetches++;
          request.completer.complete(null);
        }
      }

      _activeBatches--;
    } catch (e) {
      debugPrint('[UserBatchFetcher] Error processing batch: $e');
      _activeBatches--;
    } finally {
      _isProcessing = false;
    }
  }

  Future<Map<String, UserModel>> _fetchProfilesFromRelays(List<String> pubkeyHexList) async {
    final results = <String, UserModel>{};

    try {
      final filter = NostrService.createProfileFilter(
        authors: pubkeyHexList,
        limit: pubkeyHexList.length,
      );

      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);

      final completer = Completer<Map<String, UserModel>>();
      final receivedProfiles = <String, UserModel>{};

      void handleEvent(dynamic event, String relayUrl) {
        try {
          if (completer.isCompleted) return;

          final decoded = jsonDecode(event);
          if (decoded is List && decoded.length >= 3 && decoded[0] == 'EVENT') {
            final eventData = decoded[2];
            if (eventData['kind'] == 0) {
              final pubkey = eventData['pubkey'] as String?;
              if (pubkey != null && pubkeyHexList.contains(pubkey)) {
                final content = eventData['content'] as String?;
                if (content != null) {
                  try {
                    final parsedContent = jsonDecode(content);
                    final profileData = <String, String>{};

                    parsedContent.forEach((key, value) {
                      final keyStr = key.toString();
                      if (keyStr == 'picture') {
                        profileData['profileImage'] = value?.toString() ?? '';
                      } else {
                        profileData[keyStr] = value?.toString() ?? '';
                      }
                    });

                    final user = UserModel.fromCachedProfile(pubkey, profileData);
                    receivedProfiles[pubkey] = user;

                    if (receivedProfiles.length == pubkeyHexList.length) {
                      if (!completer.isCompleted) {
                        completer.complete(receivedProfiles);
                      }
                    }
                  } catch (e) {
                    debugPrint('[UserBatchFetcher] Error parsing profile: $e');
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[UserBatchFetcher] Error processing event: $e');
        }
      }

      final serviceId = 'user_batch_fetcher_${DateTime.now().millisecondsSinceEpoch}';
      _relayManager.connectRelays(
        [],
        onEvent: handleEvent,
        serviceId: serviceId,
      );

      await _relayManager.broadcast(serializedRequest);

      Timer(requestTimeout, () {
        if (!completer.isCompleted) {
          debugPrint('[UserBatchFetcher] Batch fetch timeout, returning ${receivedProfiles.length}/${pubkeyHexList.length} profiles');
          completer.complete(receivedProfiles);
        }
      });

      final finalResults = await completer.future;

      _relayManager.unregisterService(serviceId);

      _updateRelayPerformance(finalResults.length, pubkeyHexList.length);

      return finalResults;
    } catch (e) {
      debugPrint('[UserBatchFetcher] Error fetching profiles from relays: $e');
      return results;
    }
  }

  void _updateRelayPerformance(int successCount, int totalCount) {
    final successRate = totalCount > 0 ? (successCount / totalCount * 100).round() : 0;
    debugPrint('[UserBatchFetcher] Batch success rate: $successRate% ($successCount/$totalCount)');
  }

  Map<String, dynamic> getStats() {
    final successRate = _totalRequests > 0 ? (_successfulFetches / _totalRequests * 100).toStringAsFixed(1) : '0.0';

    return {
      'totalRequests': _totalRequests,
      'batchesSent': _batchesSent,
      'successfulFetches': _successfulFetches,
      'failedFetches': _failedFetches,
      'successRate': '$successRate%',
      'queueSize': _requestQueue.length,
      'activeBatches': _activeBatches,
      'avgBatchSize': _batchesSent > 0 ? (_totalRequests / _batchesSent).toStringAsFixed(1) : '0.0',
    };
  }

  void printStats() {
    final stats = getStats();
    debugPrint('=== UserBatchFetcher Statistics ===');
    stats.forEach((key, value) {
      debugPrint('  $key: $value');
    });
    debugPrint('====================================');
  }

  void clear() {
    _requestQueue.clear();
    _queuedPubkeys.clear();
    _totalRequests = 0;
    _batchesSent = 0;
    _successfulFetches = 0;
    _failedFetches = 0;
  }

  void dispose() {
    _batchTimer?.cancel();
    _requestQueue.clear();
    _queuedPubkeys.clear();
  }
}

class PriorityQueue<T> {
  final List<T> _queue = [];
  final int Function(T, T) _comparator;

  PriorityQueue(this._comparator);

  bool _needsSort = false;

  void add(T item) {
    _queue.add(item);
    _needsSort = true;
  }

  T removeFirst() {
    if (_needsSort) {
      _queue.sort(_comparator);
      _needsSort = false;
    }
    return _queue.removeAt(0);
  }

  bool get isEmpty => _queue.isEmpty;
  int get length => _queue.length;

  void clear() {
    _queue.clear();
    _needsSort = false;
  }
}
