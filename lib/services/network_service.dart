import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:nostr/nostr.dart';
import 'package:crypto/crypto.dart';
import '../constants/relays.dart';
import 'relay_service.dart';
import 'nostr_service.dart';

class NetworkService {
  final WebSocketManager _socketManager;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  bool _isClosed = false;

  // Connection pooling and management
  final Map<String, http.Client> _httpClients = {};
  final Map<String, DateTime> _clientLastUsed = {};
  Timer? _clientCleanupTimer;

  // Request batching and throttling
  final Map<String, Timer> _requestTimers = {};

  // Performance metrics
  int _totalRequests = 0;
  int _successfulRequests = 0;
  int _failedRequests = 0;
  final List<Duration> _requestTimes = [];

  // Rate limiting
  final Map<String, List<DateTime>> _requestHistory = {};
  static const int _maxRequestsPerMinute = 60;

  NetworkService({required List<String> relayUrls}) : _socketManager = WebSocketManager(relayUrls: relayUrls) {
    _startClientManagement();
  }

  void _startClientManagement() {
    _clientCleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupIdleClients();
    });
  }

  void _cleanupIdleClients() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    for (final entry in _clientLastUsed.entries) {
      if (now.difference(entry.value) > const Duration(minutes: 10)) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _httpClients[key]?.close();
      _httpClients.remove(key);
      _clientLastUsed.remove(key);
    }
  }

  http.Client _getHttpClient(String baseUrl) {
    _clientLastUsed[baseUrl] = DateTime.now();

    if (!_httpClients.containsKey(baseUrl)) {
      _httpClients[baseUrl] = http.Client();
    }

    return _httpClients[baseUrl]!;
  }

  bool _isRateLimited(String endpoint) {
    final now = DateTime.now();
    final history = _requestHistory[endpoint] ?? [];

    // Remove requests older than 1 minute
    history.removeWhere((time) => now.difference(time) > const Duration(minutes: 1));
    _requestHistory[endpoint] = history;

    return history.length >= _maxRequestsPerMinute;
  }

  void _recordRequest(String endpoint) {
    _requestHistory.putIfAbsent(endpoint, () => []);
    _requestHistory[endpoint]!.add(DateTime.now());
  }

  Future<void> initializeConnections(List<String> targetNpubs) async {
    await _socketManager.connectRelays(
      targetNpubs,
      onEvent: (event, relayUrl) => _handleEvent(event, targetNpubs),
      onDisconnected: (relayUrl) => _socketManager.reconnectRelay(relayUrl, targetNpubs),
    );
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {
    // This would be handled by the main DataService
    // Just a placeholder for the network layer
  }

  Future<void> broadcastRequest(String serializedRequest) async {
    final stopwatch = Stopwatch()..start();
    _totalRequests++;

    try {
      await _socketManager.broadcast(serializedRequest);
      _successfulRequests++;
    } catch (e) {
      _failedRequests++;
      rethrow;
    } finally {
      stopwatch.stop();
      _requestTimes.add(stopwatch.elapsed);

      // Keep only recent measurements
      if (_requestTimes.length > 100) {
        _requestTimes.removeAt(0);
      }
    }
  }

  Future<void> safeBroadcast(String message) async {
    try {
      await broadcastRequest(message);
    } catch (e) {
      print('[NetworkService ERROR] Broadcast failed: $e');
    }
  }

  // INSTANT BROADCASTING FOR USER INTERACTIONS
  // Bypass all queuing and delays for user-initiated actions
  Future<void> instantBroadcast(String message) async {
    final stopwatch = Stopwatch()..start();
    _totalRequests++;

    try {
      await _socketManager.executeOnActiveSockets((ws) {
        ws.add(message);
      });
      _successfulRequests++;
      print('[NetworkService] Instant broadcast completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      _failedRequests++;
      print('[NetworkService ERROR] Instant broadcast failed: $e');
      rethrow;
    } finally {
      stopwatch.stop();
      _requestTimes.add(stopwatch.elapsed);

      // Keep only recent measurements
      if (_requestTimes.length > 100) {
        _requestTimes.removeAt(0);
      }
    }
  }

  Future<void> instantBroadcastUserReaction(String targetEventId, String reactionContent) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = NostrService.createReactionEvent(
        targetEventId: targetEventId,
        content: reactionContent,
        privateKey: privateKey,
      );

      // Use instant broadcast instead of regular broadcast
      await instantBroadcast(NostrService.serializeEvent(event));
    } catch (e) {
      print('[NetworkService ERROR] Error sending instant reaction: $e');
      rethrow;
    }
  }

  // Instant broadcast for user replies
  Future<void> instantBroadcastUserReply(String parentEventId, String replyContent, String parentAuthor) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final tags = NostrService.createReplyTags(
        rootId: parentEventId,
        parentAuthor: parentAuthor,
        relayUrls: relaySetMainSockets,
      );

      final event = NostrService.createReplyEvent(
        content: replyContent,
        privateKey: privateKey,
        tags: tags,
      );

      // Use instant broadcast instead of regular broadcast
      await instantBroadcast(NostrService.serializeEvent(event));
    } catch (e) {
      print('[NetworkService ERROR] Error sending instant reply: $e');
      rethrow;
    }
  }

  // Instant broadcast for user reposts
  Future<void> instantBroadcastUserRepost(String noteId, String noteAuthor, String? rawContent) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final content = rawContent ??
          jsonEncode({
            'id': noteId,
            'pubkey': noteAuthor,
            'kind': 1,
            'tags': [],
          });

      final event = NostrService.createRepostEvent(
        noteId: noteId,
        noteAuthor: noteAuthor,
        content: content,
        privateKey: privateKey,
      );

      // Use instant broadcast instead of regular broadcast
      await instantBroadcast(NostrService.serializeEvent(event));
    } catch (e) {
      print('[NetworkService ERROR] Error sending instant repost: $e');
      rethrow;
    }
  }

  // Instant broadcast for user notes
  Future<void> instantBroadcastUserNote(String noteContent) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = NostrService.createNoteEvent(
        content: noteContent,
        privateKey: privateKey,
      );

      // Use instant broadcast instead of regular broadcast
      await instantBroadcast(NostrService.serializeEvent(event));
    } catch (e) {
      print('[NetworkService ERROR] Error sending instant note: $e');
      rethrow;
    }
  }

  // Batched broadcast for multiple messages
  Future<void> batchBroadcast(List<String> messages, {Duration delay = const Duration(milliseconds: 10)}) async {
    if (messages.isEmpty) return;

    for (int i = 0; i < messages.length; i++) {
      await safeBroadcast(messages[i]);

      // Add delay between messages to prevent overwhelming
      if (i < messages.length - 1 && delay.inMilliseconds > 0) {
        await Future.delayed(delay);
      }
    }
  }

  String createRequest(String filterJson) => NostrService.serializeRequest(NostrService.createRequest(NostrService.createNotesFilter()));

  Future<void> shareNote(String noteContent, String npub) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = NostrService.createNoteEvent(
        content: noteContent,
        privateKey: privateKey,
      );

      await _socketManager.broadcast(NostrService.serializeEvent(event));
    } catch (e) {
      print('[NetworkService ERROR] Error sharing note: $e');
      rethrow;
    }
  }

  Future<void> sendReaction(String targetEventId, String reactionContent) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = NostrService.createReactionEvent(
        targetEventId: targetEventId,
        content: reactionContent,
        privateKey: privateKey,
      );

      await _socketManager.broadcast(NostrService.serializeEvent(event));
    } catch (e) {
      print('[NetworkService ERROR] Error sending reaction: $e');
      rethrow;
    }
  }

  Future<void> sendReply(String parentEventId, String replyContent, String parentAuthor) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final tags = NostrService.createReplyTags(
        rootId: parentEventId,
        parentAuthor: parentAuthor,
        relayUrls: relaySetMainSockets,
      );

      final event = NostrService.createReplyEvent(
        content: replyContent,
        privateKey: privateKey,
        tags: tags,
      );

      await _socketManager.broadcast(NostrService.serializeEvent(event));
    } catch (e) {
      print('[NetworkService ERROR] Error sending reply: $e');
      rethrow;
    }
  }

  Future<void> sendRepost(String noteId, String noteAuthor, String? rawContent) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final content = rawContent ??
          jsonEncode({
            'id': noteId,
            'pubkey': noteAuthor,
            'kind': 1,
            'tags': [],
          });

      final event = NostrService.createRepostEvent(
        noteId: noteId,
        noteAuthor: noteAuthor,
        content: content,
        privateKey: privateKey,
      );

      await _socketManager.broadcast(NostrService.serializeEvent(event));
    } catch (e) {
      print('[NetworkService ERROR] Error sending repost: $e');
      rethrow;
    }
  }

  Future<String> sendZap({
    required String recipientPubkey,
    required String lud16,
    required int amountSats,
    String? noteId,
    String content = '',
  }) async {
    // Rate limiting check
    if (_isRateLimited('zap')) {
      throw Exception('Rate limit exceeded for zap requests');
    }
    _recordRequest('zap');

    final privateKey = await _secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    if (!lud16.contains('@')) {
      throw Exception('Invalid lud16 format.');
    }

    final parts = lud16.split('@');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      throw Exception('Invalid lud16 format.');
    }

    final display_name = parts[0];
    final domain = parts[1];

    // Enhanced LNURL fetch with retry logic
    final uri = Uri.parse('https://$domain/.well-known/lnurlp/$display_name');
    final client = _getHttpClient(domain);

    http.Response? response;
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      try {
        response = await client.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) break;

        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(Duration(seconds: pow(2, attempts).toInt()));
        }
      } catch (e) {
        attempts++;
        if (attempts >= maxAttempts) {
          throw Exception('LNURL fetch failed after $maxAttempts attempts: $e');
        }
        await Future.delayed(Duration(seconds: pow(2, attempts).toInt()));
      }
    }

    if (response == null || response.statusCode != 200) {
      throw Exception('LNURL fetch failed with status: ${response?.statusCode ?? 'unknown'}');
    }

    final lnurlJson = jsonDecode(response.body);
    if (lnurlJson['allowsNostr'] != true || lnurlJson['nostrPubkey'] == null) {
      throw Exception('Recipient does not support zaps.');
    }

    final callback = lnurlJson['callback'];
    if (callback == null || callback.isEmpty) {
      throw Exception('Zap callback is missing.');
    }

    final amountMillisats = (amountSats * 1000).toString();
    final relays = relaySetMainSockets;

    final tags = NostrService.createZapRequestTags(
      relays: relays.map((e) => e.toString()).toList(),
      amountMillisats: amountMillisats,
      recipientPubkey: recipientPubkey,
      noteId: noteId,
    );

    final zapRequest = NostrService.createZapRequestEvent(
      tags: tags,
      content: content,
      privateKey: privateKey,
    );

    final encodedZap = Uri.encodeComponent(jsonEncode(NostrService.eventToJson(zapRequest)));
    final zapUrl = Uri.parse('$callback?amount=$amountMillisats&nostr=$encodedZap');

    // Enhanced invoice request with retry
    attempts = 0;
    while (attempts < maxAttempts) {
      try {
        final invoiceResponse = await client.get(zapUrl).timeout(const Duration(seconds: 15));
        if (invoiceResponse.statusCode == 200) {
          final invoiceJson = jsonDecode(invoiceResponse.body);
          final invoice = invoiceJson['pr'];
          if (invoice == null || invoice.toString().isEmpty) {
            throw Exception('Invoice not returned by zap server.');
          }
          return invoice;
        }

        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(Duration(seconds: pow(2, attempts).toInt()));
        }
      } catch (e) {
        attempts++;
        if (attempts >= maxAttempts) {
          throw Exception('Zap callback failed after $maxAttempts attempts: $e');
        }
        await Future.delayed(Duration(seconds: pow(2, attempts).toInt()));
      }
    }

    throw Exception('Zap callback failed after $maxAttempts attempts');
  }

  Future<String> uploadMedia(String filePath, String blossomUrl) async {
    final privateKey = await _secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileBytes = await file.readAsBytes();
    final sha256Hash = sha256.convert(fileBytes).toString();

    String mimeType = 'application/octet-stream';
    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      mimeType = 'image/jpeg';
    } else if (lowerPath.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (lowerPath.endsWith('.gif')) {
      mimeType = 'image/gif';
    } else if (lowerPath.endsWith('.mp4')) {
      mimeType = 'video/mp4';
    }

    final expiration = DateTime.now().add(Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;

    final authEvent = Event.from(
      kind: 24242,
      content: 'Upload ${file.uri.pathSegments.last}',
      tags: [
        ['t', 'upload'],
        ['x', sha256Hash],
        ['expiration', expiration.toString()],
      ],
      privkey: privateKey,
    );

    final encodedAuth = base64.encode(utf8.encode(jsonEncode(authEvent.toJson())));
    final authHeader = 'Nostr $encodedAuth';

    final cleanedUrl = blossomUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanedUrl/upload');

    final httpClient = HttpClient();
    final request = await httpClient.putUrl(uri);

    request.headers.set(HttpHeaders.authorizationHeader, authHeader);
    request.headers.set(HttpHeaders.contentTypeHeader, mimeType);
    request.headers.set(HttpHeaders.contentLengthHeader, fileBytes.length);

    request.add(fileBytes);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('Upload failed with status ${response.statusCode}: $responseBody');
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is Map && decoded.containsKey('url')) {
      return decoded['url'];
    }

    throw Exception('Upload succeeded but response does not contain a valid URL.');
  }

  String generateUUID() => NostrService.generateUUID();

  int get connectedRelaysCount => _socketManager.activeSockets.length;

  // Enhanced statistics
  Map<String, dynamic> getNetworkStats() {
    final successRate = _totalRequests > 0 ? (_successfulRequests / _totalRequests * 100).toStringAsFixed(2) : '0.00';

    final avgRequestTime =
        _requestTimes.isNotEmpty ? _requestTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds) / _requestTimes.length : 0.0;

    return {
      'totalRequests': _totalRequests,
      'successfulRequests': _successfulRequests,
      'failedRequests': _failedRequests,
      'successRate': '$successRate%',
      'avgRequestTimeMs': avgRequestTime.round(),
      'connectedRelays': connectedRelaysCount,
      'activeHttpClients': _httpClients.length,
      'rateLimitStatus': {
        for (final entry in _requestHistory.entries) entry.key: '${entry.value.length}/$_maxRequestsPerMinute per minute',
      },
    };
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;

    // Cancel timers
    _clientCleanupTimer?.cancel();
    for (final timer in _requestTimers.values) {
      timer.cancel();
    }

    // Close HTTP clients
    for (final client in _httpClients.values) {
      client.close();
    }
    _httpClients.clear();

    // Close WebSocket connections
    await _socketManager.closeConnections();
  }
}
