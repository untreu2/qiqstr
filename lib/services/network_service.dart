import 'dart:async';
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
  final WebSocketManager _socketManager;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  bool _isClosed = false;

  NetworkService({required List<String> relayUrls}) 
      : _socketManager = WebSocketManager(relayUrls: relayUrls);

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
    await _socketManager.broadcast(serializedRequest);
  }

  Future<void> safeBroadcast(String message) async {
    try {
      await _socketManager.broadcast(message);
    } catch (e) {
      print('[NetworkService ERROR] Broadcast failed: $e');
    }
  }

  String createRequest(String filterJson) =>
      NostrService.serializeRequest(NostrService.createRequest(NostrService.createNotesFilter()));

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

      final content = rawContent ?? jsonEncode({
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

    // Fetch LNURL data
    final uri = Uri.parse('https://$domain/.well-known/lnurlp/$display_name');
    final response = await http.get(uri);
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

    final invoiceResponse = await http.get(zapUrl);
    if (invoiceResponse.statusCode != 200) {
      throw Exception('Zap callback failed: ${invoiceResponse.body}');
    }

    final invoiceJson = jsonDecode(invoiceResponse.body);
    final invoice = invoiceJson['pr'];
    if (invoice == null || invoice.toString().isEmpty) {
      throw Exception('Invoice not returned by zap server.');
    }

    return invoice;
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

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;
    await _socketManager.closeConnections();
  }
}