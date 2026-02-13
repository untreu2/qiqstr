import 'package:flutter/foundation.dart';
import '../../services/nostr_service.dart';
import '../../services/relay_service.dart';
import '../../services/auth_service.dart';
import '../../services/encrypted_mute_service.dart';
import '../../services/encrypted_bookmark_service.dart';

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
    return NostrService.createNoteEvent(
      content: content,
      privateKey: privateKey,
      tags: tags,
    );
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
    final relayUrl = relays.isNotEmpty ? relays.first : null;

    final tags = NostrService.createReplyTags(
      rootId: rootId,
      replyId: replyToId,
      rootAuthor: rootAuthor,
      replyAuthor: replyAuthor,
      relayUrl: relayUrl,
    );

    return NostrService.createReplyEvent(
      content: content,
      privateKey: privateKey,
      tags: tags,
    );
  }

  Future<Map<String, dynamic>> createQuote({
    required String content,
    required String quotedNoteId,
    String? quotedAuthor,
  }) async {
    final privateKey = await _getPrivateKey();
    return NostrService.createQuoteEvent(
      content: content,
      quotedEventId: quotedNoteId,
      quotedEventPubkey: quotedAuthor,
      privateKey: privateKey,
    );
  }

  Future<Map<String, dynamic>> createReaction({
    required String targetEventId,
    required String targetAuthor,
    String content = '+',
  }) async {
    final privateKey = await _getPrivateKey();
    final relays = await RustRelayService.instance.getRelayList();
    final relayUrl = relays.isNotEmpty ? relays.first : null;

    return NostrService.createReactionEvent(
      targetEventId: targetEventId,
      targetAuthor: targetAuthor,
      content: content,
      privateKey: privateKey,
      relayUrl: relayUrl,
    );
  }

  Future<Map<String, dynamic>> createRepost({
    required String noteId,
    required String noteAuthor,
    required String originalContent,
  }) async {
    final privateKey = await _getPrivateKey();
    final relays = await RustRelayService.instance.getRelayList();
    final relayUrl = relays.isNotEmpty ? relays.first : null;

    return NostrService.createRepostEvent(
      noteId: noteId,
      noteAuthor: noteAuthor,
      content: originalContent,
      privateKey: privateKey,
      relayUrl: relayUrl,
    );
  }

  Future<Map<String, dynamic>> createDeletion({
    required List<String> eventIds,
    String? reason,
  }) async {
    final privateKey = await _getPrivateKey();
    return NostrService.createDeletionEvent(
      eventIds: eventIds,
      privateKey: privateKey,
      reason: reason,
    );
  }

  Future<Map<String, dynamic>> createFollow({
    required List<String> followingPubkeys,
  }) async {
    final privateKey = await _getPrivateKey();
    return NostrService.createFollowEvent(
      followingPubkeys: followingPubkeys,
      privateKey: privateKey,
    );
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

  Future<Map<String, dynamic>> createProfileUpdate({
    required Map<String, dynamic> profileContent,
  }) async {
    final privateKey = await _getPrivateKey();
    return NostrService.createProfileEvent(
      profileContent: profileContent,
      privateKey: privateKey,
    );
  }

  Future<bool> broadcast(Map<String, dynamic> event) async {
    try {
      return await RustRelayService.instance.broadcastEvent(event);
    } catch (e) {
      if (kDebugMode) {
        print('[EventPublisher] Broadcast error: $e');
      }
      return false;
    }
  }

  Future<bool> broadcastRawEvent(Map<String, dynamic> event) async {
    try {
      return await RustRelayService.instance.broadcastEvent(event);
    } catch (e) {
      if (kDebugMode) {
        print('[EventPublisher] Broadcast raw event error: $e');
      }
      return false;
    }
  }

  Future<String?> uploadMedia(String filePath,
      {String blossomUrl = 'https://blossom.primal.net'}) async {
    try {
      final privateKey = await _getPrivateKey();
      final url = await NostrService.sendMedia(
        filePath: filePath,
        blossomUrl: blossomUrl,
        privateKey: privateKey,
      );
      return url;
    } catch (e) {
      if (kDebugMode) {
        print('[EventPublisher] Upload media error: $e');
      }
      return null;
    }
  }
}
