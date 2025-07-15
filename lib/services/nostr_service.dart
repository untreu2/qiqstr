import 'dart:convert';
import 'package:nostr/nostr.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

/// Service that encapsulates all nostr package functionality
/// This allows for easy replacement of the nostr package in the future
class NostrService {
  static final Uuid _uuid = Uuid();

  // Event creation methods
  static Event createNoteEvent({
    required String content,
    required String privateKey,
    List<List<String>>? tags,
  }) {
    return Event.from(
      kind: 1,
      tags: tags ?? [],
      content: content,
      privkey: privateKey,
    );
  }

  static Event createReactionEvent({
    required String targetEventId,
    required String content,
    required String privateKey,
  }) {
    return Event.from(
      kind: 7,
      tags: [['e', targetEventId]],
      content: content,
      privkey: privateKey,
    );
  }

  static Event createReplyEvent({
    required String content,
    required String privateKey,
    required List<List<String>> tags,
  }) {
    return Event.from(
      kind: 1,
      tags: tags,
      content: content,
      privkey: privateKey,
    );
  }

  static Event createRepostEvent({
    required String noteId,
    required String noteAuthor,
    required String content,
    required String privateKey,
  }) {
    final tags = [
      ['e', noteId],
      ['p', noteAuthor],
    ];

    return Event.from(
      kind: 6,
      tags: tags,
      content: content,
      privkey: privateKey,
    );
  }

  static Event createProfileEvent({
    required Map<String, dynamic> profileContent,
    required String privateKey,
  }) {
    return Event.from(
      kind: 0,
      tags: [],
      content: jsonEncode(profileContent),
      privkey: privateKey,
    );
  }

  static Event createFollowEvent({
    required List<String> followingPubkeys,
    required String privateKey,
  }) {
    final tags = followingPubkeys.map((pubkey) => ['p', pubkey, '']).toList();
    return Event.from(
      kind: 3,
      tags: tags,
      content: "",
      privkey: privateKey,
    );
  }

  static Event createZapRequestEvent({
    required List<List<String>> tags,
    required String content,
    required String privateKey,
  }) {
    return Event.from(
      kind: 9734,
      tags: tags,
      content: content,
      privkey: privateKey,
    );
  }

  static Event createMediaUploadAuthEvent({
    required String fileName,
    required String sha256Hash,
    required int expiration,
    required String privateKey,
  }) {
    return Event.from(
      kind: 24242,
      content: 'Upload $fileName',
      tags: [
        ['t', 'upload'],
        ['x', sha256Hash],
        ['expiration', expiration.toString()],
      ],
      privkey: privateKey,
    );
  }

  // Filter creation methods
  static Filter createNotesFilter({
    List<String>? authors,
    List<int>? kinds,
    int? limit,
    int? since,
    int? until,
  }) {
    return Filter(
      authors: authors,
      kinds: kinds ?? [1, 6],
      limit: limit,
      since: since,
      until: until,
    );
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

  static Filter createReactionFilter({
    required List<String> eventIds,
    int? limit,
    int? since,
  }) {
    return Filter(
      kinds: [7],
      e: eventIds,
      limit: limit,
      since: since,
    );
  }

  static Filter createReplyFilter({
    required List<String> eventIds,
    int? limit,
    int? since,
  }) {
    return Filter(
      kinds: [1],
      e: eventIds,
      limit: limit,
      since: since,
    );
  }

  static Filter createRepostFilter({
    required List<String> eventIds,
    int? limit,
    int? since,
  }) {
    return Filter(
      kinds: [6],
      e: eventIds,
      limit: limit,
      since: since,
    );
  }

  static Filter createZapFilter({
    required List<String> eventIds,
    int? limit,
    int? since,
  }) {
    return Filter(
      kinds: [9735],
      e: eventIds,
      limit: limit,
      since: since,
    );
  }

  static Filter createNotificationFilter({
    required List<String> pubkeys,
    List<int>? kinds,
    int? since,
    int? limit,
  }) {
    return Filter(
      p: pubkeys,
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
      e: eventIds,
      limit: limit,
    );
  }

  // Request creation methods
  static Request createRequest(Filter filter) {
    return Request(generateUUID(), [filter]);
  }

  static Request createMultiFilterRequest(List<Filter> filters) {
    return Request(generateUUID(), filters);
  }

  // Utility methods
  static String generateUUID() => _uuid.v4().replaceAll('-', '');

  static String serializeEvent(Event event) => event.serialize();

  static String serializeRequest(Request request) => request.serialize();

  static Map<String, dynamic> eventToJson(Event event) => event.toJson();

  // Media upload helper
  static String createBlossomAuthHeader({
    required Event authEvent,
  }) {
    final encodedAuth = base64.encode(utf8.encode(jsonEncode(authEvent.toJson())));
    return 'Nostr $encodedAuth';
  }

  // Zap request helpers
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

  // Reply tags helpers
  static List<List<String>> createReplyTags({
    required String rootId,
    String? replyId,
    required String parentAuthor,
    required List<String> relayUrls,
  }) {
    List<List<String>> tags = [];

    if (replyId != null && replyId != rootId) {
      tags.add(['e', rootId, '', 'root']);
      tags.add(['e', replyId, '', 'reply']);
    } else {
      tags.add(['e', rootId, '', 'root']);
    }

    tags.add(['p', parentAuthor, '', 'mention']);

    for (final relayUrl in relayUrls) {
      tags.add(['r', relayUrl]);
    }

    return tags;
  }

  // Hash calculation for media uploads
  static String calculateSha256Hash(List<int> fileBytes) {
    return sha256.convert(fileBytes).toString();
  }

  // MIME type detection
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
}