import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../services/relay_service.dart';
import '../../services/auth_service.dart';
import '../../services/encrypted_mute_service.dart';
import '../../services/encrypted_bookmark_service.dart';
import '../../services/pinned_notes_service.dart';
import '../../services/follow_set_service.dart';
import '../../../src/rust/api/events.dart' as rust_events;
import '../../../src/rust/api/crypto.dart' as rust_crypto;

class EventPublisher {
  final AuthService _authService;

  EventPublisher({required AuthService authService})
      : _authService = authService;

  Future<String> _getPrivateKey() async {
    final result = await _authService.getCurrentUserPrivateKey();
    if (result.isError || result.data == null) {
      throw Exception('Not authenticated');
    }
    return result.data!;
  }

  Future<Map<String, dynamic>> createNote({
    required String content,
    List<List<String>>? tags,
  }) async {
    final privateKey = await _getPrivateKey();
    final json = rust_events.createNoteEvent(
      content: content,
      tags: tags ?? [],
      privateKeyHex: privateKey,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createReply({
    required String content,
    required String rootId,
    String? replyToId,
    required String rootAuthor,
    String? replyAuthor,
  }) async {
    final privateKey = await _getPrivateKey();
    final relays = await RustRelayService.instance.getRelayList();

    final tags = <List<String>>[
      if (replyToId != null && replyToId != rootId) ...[
        ['e', rootId, '', 'root'],
        ['e', replyToId, '', 'reply'],
        ['p', rootAuthor],
        if (replyAuthor != null && replyAuthor != rootAuthor)
          ['p', replyAuthor],
      ] else ...[
        ['e', rootId, '', 'root'],
        ['p', rootAuthor],
      ],
      for (final url in relays) ['r', url],
    ];

    final json = rust_events.createReplyEvent(
      content: content,
      tags: tags,
      privateKeyHex: privateKey,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createQuote({
    required String content,
    required String quotedNoteId,
    String? quotedAuthor,
  }) async {
    final privateKey = await _getPrivateKey();
    final json = rust_events.createQuoteEvent(
      content: content,
      quotedEventId: quotedNoteId,
      quotedEventPubkey: quotedAuthor,
      relayUrl: '',
      privateKeyHex: privateKey,
      additionalTags: [],
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createReaction({
    required String targetEventId,
    required String targetAuthor,
    String content = '+',
  }) async {
    final privateKey = await _getPrivateKey();
    final relays = await RustRelayService.instance.getRelayList();
    final relayUrl = relays.isNotEmpty ? relays.first : '';

    final json = rust_events.createReactionEvent(
      targetEventId: targetEventId,
      targetAuthor: targetAuthor,
      content: content,
      privateKeyHex: privateKey,
      relayUrl: relayUrl,
      targetKind: 1,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createRepost({
    required String noteId,
    required String noteAuthor,
    required String originalContent,
  }) async {
    final privateKey = await _getPrivateKey();
    final relays = await RustRelayService.instance.getRelayList();
    final relayUrl = relays.isNotEmpty ? relays.first : '';

    final json = rust_events.createRepostEvent(
      noteId: noteId,
      noteAuthor: noteAuthor,
      content: originalContent,
      privateKeyHex: privateKey,
      relayUrl: relayUrl,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createDeletion({
    required List<String> eventIds,
    String? reason,
  }) async {
    final privateKey = await _getPrivateKey();
    final json = rust_events.createDeletionEvent(
      eventIds: eventIds,
      reason: reason ?? '',
      privateKeyHex: privateKey,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createFollow({
    required List<String> followingPubkeys,
  }) async {
    final privateKey = await _getPrivateKey();
    final json = rust_events.createFollowEvent(
      followingPubkeys: followingPubkeys,
      privateKeyHex: privateKey,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createMute({
    required List<String> mutedPubkeys,
    required List<String> mutedWords,
  }) async {
    final privateKey = await _getPrivateKey();
    final authResult = await _authService.getCurrentUserPublicKeyHex();
    if (authResult.isError || authResult.data == null) {
      throw Exception('Not authenticated');
    }
    final publicKey = authResult.data!;

    return EncryptedMuteService.instance.createEncryptedMuteEvent(
      mutedPubkeys: mutedPubkeys,
      mutedWords: mutedWords,
      privateKeyHex: privateKey,
      publicKeyHex: publicKey,
    );
  }

  Future<Map<String, dynamic>> createBookmark({
    required List<String> bookmarkedEventIds,
  }) async {
    final privateKey = await _getPrivateKey();
    final authResult = await _authService.getCurrentUserPublicKeyHex();
    if (authResult.isError || authResult.data == null) {
      throw Exception('Not authenticated');
    }
    final publicKey = authResult.data!;

    return EncryptedBookmarkService.instance.createEncryptedBookmarkEvent(
      bookmarkedEventIds: bookmarkedEventIds,
      privateKeyHex: privateKey,
      publicKeyHex: publicKey,
    );
  }

  Future<Map<String, dynamic>> createPinnedNotes({
    required List<String> pinnedNoteIds,
  }) async {
    final privateKey = await _getPrivateKey();
    return PinnedNotesService.instance.createPinnedNotesEvent(
      pinnedNoteIds: pinnedNoteIds,
      privateKeyHex: privateKey,
    );
  }

  Future<Map<String, dynamic>> createFollowSet({
    required String dTag,
    required String title,
    required String description,
    required String image,
    required List<String> pubkeys,
  }) async {
    final privateKey = await _getPrivateKey();
    return FollowSetService.instance.createFollowSetEvent(
      dTag: dTag,
      title: title,
      description: description,
      image: image,
      pubkeys: pubkeys,
      privateKeyHex: privateKey,
    );
  }

  Future<Map<String, dynamic>> createReport({
    required String reportedPubkey,
    required String reportType,
    String content = '',
  }) async {
    final privateKey = await _getPrivateKey();
    final json = rust_events.createSignedEvent(
      kind: 1984,
      content: content,
      tags: [
        ['p', reportedPubkey, reportType],
      ],
      privateKeyHex: privateKey,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createProfileUpdate({
    required Map<String, dynamic> profileContent,
  }) async {
    final privateKey = await _getPrivateKey();
    final json = rust_events.createProfileEvent(
      profileJson: jsonEncode(profileContent),
      privateKeyHex: privateKey,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<bool> broadcast(Map<String, dynamic> event) async {
    try {
      return await RustRelayService.instance.broadcastEvent(event);
    } catch (e) {
      if (kDebugMode) print('[EventPublisher] Broadcast error: $e');
      return false;
    }
  }

  Future<bool> broadcastRawEvent(Map<String, dynamic> event) async {
    try {
      return await RustRelayService.instance.broadcastEvent(event);
    } catch (e) {
      if (kDebugMode) print('[EventPublisher] Broadcast raw event error: $e');
      return false;
    }
  }

  Future<String?> uploadMedia(String filePath,
      {String blossomUrl = 'https://blossom.primal.net'}) async {
    try {
      final privateKey = await _getPrivateKey();
      final file = File(filePath);
      if (!await file.exists()) throw Exception('File not found: $filePath');

      final fileBytes = await file.readAsBytes();
      final hash = rust_crypto.sha256Hash(data: fileBytes);

      final lowerPath = filePath.toLowerCase();
      final mimeType = lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')
          ? 'image/jpeg'
          : lowerPath.endsWith('.png')
              ? 'image/png'
              : lowerPath.endsWith('.gif')
                  ? 'image/gif'
                  : lowerPath.endsWith('.mp4')
                      ? 'video/mp4'
                      : 'application/octet-stream';

      final expiration = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 600;
      final authEventJson = rust_events.createBlossomAuthEvent(
        content: 'Upload $filePath',
        sha256Hash: hash,
        expiration: expiration,
        privateKeyHex: privateKey,
      );

      final authBase64 = base64Encode(utf8.encode(authEventJson));
      final cleanedUrl = blossomUrl.replaceAll(RegExp(r'/+$'), '');

      final httpClient = HttpClient();
      try {
        final request =
            await httpClient.putUrl(Uri.parse('$cleanedUrl/upload'));
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
    } catch (e) {
      if (kDebugMode) print('[EventPublisher] Upload media error: $e');
      return null;
    }
  }
}
