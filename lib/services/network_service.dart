import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:nostr/nostr.dart';
import 'package:crypto/crypto.dart';
import '../constants/relays.dart';
import 'relay_service.dart';
import 'nostr_service.dart';

class NetworkService {
  static NetworkService? _instance;
  static NetworkService get instance => _instance ??= NetworkService._internal();

  NetworkService._internal() : _socketManager = WebSocketManager.instance;

  final WebSocketManager _socketManager;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _isClosed = false;

  Future<void> initializeConnections(List<String> targetNpubs) async {
    Future.microtask(() async {
      await _socketManager.connectRelays(
        targetNpubs,
        onEvent: (event, relayUrl) => _handleEvent(event, targetNpubs),
        onDisconnected: (relayUrl) => _socketManager.reconnectRelay(relayUrl, targetNpubs),
      );
    });
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {}

  Future<void> broadcast(String message) async {
    if (_isClosed) return;
    try {
      await _socketManager.broadcast(message);
    } catch (e) {
      print('[NetworkService ERROR] Broadcast failed');
      rethrow;
    }
  }

  Future<void> sendReaction(String targetEventId, String reactionContent) async {
    if (_isClosed) return;

    Future.microtask(() async {
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

        await broadcast(NostrService.serializeEvent(event));
      } catch (e) {
        print('[NetworkService ERROR] Error sending reaction');
        rethrow;
      }
    });
  }

  Future<void> sendReply(String parentEventId, String replyContent, String parentAuthor) async {
    if (_isClosed) return;

    Future.microtask(() async {
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

        await broadcast(NostrService.serializeEvent(event));
      } catch (e) {
        print('[NetworkService ERROR] Error sending reply');
        rethrow;
      }
    });
  }

  Future<void> sendRepost(String noteId, String noteAuthor, String? rawContent) async {
    if (_isClosed) return;

    Future.microtask(() async {
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

        await broadcast(NostrService.serializeEvent(event));
      } catch (e) {
        print('[NetworkService ERROR] Error sending repost');
        rethrow;
      }
    });
  }

  Future<void> sendNote(String noteContent) async {
    if (_isClosed) return;

    Future.microtask(() async {
      try {
        final privateKey = await _secureStorage.read(key: 'privateKey');
        if (privateKey == null || privateKey.isEmpty) {
          throw Exception('Private key not found.');
        }

        final event = NostrService.createNoteEvent(
          content: noteContent,
          privateKey: privateKey,
        );

        await broadcast(NostrService.serializeEvent(event));
      } catch (e) {
        print('[NetworkService ERROR] Error sending note');
        rethrow;
      }
    });
  }

  Future<String> sendZap({
    required String recipientPubkey,
    required String lud16,
    required int amountSats,
    String? noteId,
    String content = '',
  }) async {
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

    final uri = Uri.parse('https://$domain/.well-known/lnurlp/$display_name');
    final client = http.Client();

    try {
      final response = await client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('LNURL fetch failed with status: ${response.statusCode}');
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

      final invoiceResponse = await client.get(zapUrl).timeout(const Duration(seconds: 15));
      if (invoiceResponse.statusCode != 200) {
        throw Exception('Zap callback failed with status: ${invoiceResponse.statusCode}');
      }

      final invoiceJson = jsonDecode(invoiceResponse.body);
      final invoice = invoiceJson['pr'];
      if (invoice == null || invoice.toString().isEmpty) {
        throw Exception('Invoice not returned by zap server.');
      }
      return invoice;
    } finally {
      client.close();
    }
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

  Map<String, dynamic> getNetworkStats() {
    return {
      'connectedRelays': connectedRelaysCount,
      'status': 'simplified',
    };
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;
    await _socketManager.closeConnections();
  }

  Future<void> broadcastRequest(String serializedRequest) => broadcast(serializedRequest);
  Future<void> safeBroadcast(String message) => broadcast(message);
  Future<void> priorityBroadcast(String message) => broadcast(message);
  Future<void> shareNote(String noteContent, String npub) => sendNote(noteContent);
  Future<void> broadcastUserNote(String noteContent) => sendNote(noteContent);
  Future<void> broadcastUserReaction(String targetEventId, String reactionContent) => sendReaction(targetEventId, reactionContent);
  Future<void> broadcastUserReply(String parentEventId, String replyContent, String parentAuthor) =>
      sendReply(parentEventId, replyContent, parentAuthor);
  Future<void> broadcastUserRepost(String noteId, String noteAuthor, String? rawContent) => sendRepost(noteId, noteAuthor, rawContent);
  String createRequest(String filterJson) => NostrService.serializeRequest(NostrService.createRequest(NostrService.createNotesFilter()));
}
