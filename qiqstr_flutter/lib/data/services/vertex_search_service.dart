import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../constants/relays.dart';
import '../../domain/entities/user_profile.dart';

class VertexSearchService {
  static VertexSearchService? _instance;
  static VertexSearchService get instance {
    _instance ??= VertexSearchService._internal();
    return _instance!;
  }

  VertexSearchService._internal();

  Future<List<UserProfile>> searchProfiles(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    final subId = 'vs_${DateTime.now().millisecondsSinceEpoch}';
    final reqMessage = jsonEncode([
      'REQ',
      subId,
      {'kinds': [0], 'search': query.trim(), 'limit': limit},
    ]);
    final closeMessage = jsonEncode(['CLOSE', subId]);

    WebSocket? ws;
    final results = <UserProfile>[];
    final seenPubkeys = <String>{};

    try {
      ws = await WebSocket.connect(vertexRelayUrl)
          .timeout(const Duration(seconds: 8));

      ws.add(reqMessage);

      await for (final raw in ws.timeout(
        const Duration(seconds: 10),
        onTimeout: (sink) => sink.close(),
      )) {
        if (raw is! String) continue;
        List<dynamic> decoded;
        try {
          decoded = jsonDecode(raw) as List<dynamic>;
        } catch (_) {
          continue;
        }
        if (decoded.isEmpty) continue;

        final msgType = decoded[0] as String?;

        if (msgType == 'EOSE') break;

        if (msgType == 'EVENT' && decoded.length >= 3) {
          final event = decoded[2] as Map<String, dynamic>?;
          if (event == null) continue;

          final kind = event['kind'] as int?;
          if (kind != 0) continue;

          final pubkey = event['pubkey'] as String? ?? '';
          if (pubkey.isEmpty || seenPubkeys.contains(pubkey)) continue;
          seenPubkeys.add(pubkey);

          final contentRaw = event['content'] as String? ?? '';
          Map<String, dynamic> meta;
          try {
            meta = jsonDecode(contentRaw) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }

          results.add(UserProfile(
            pubkey: pubkey,
            name: meta['name'] as String?,
            displayName: meta['display_name'] as String?,
            about: meta['about'] as String?,
            picture: meta['picture'] as String?,
            banner: meta['banner'] as String?,
            nip05: meta['nip05'] as String?,
            lud16: meta['lud16'] as String?,
            website: meta['website'] as String?,
            location: meta['location'] as String?,
          ));

          if (results.length >= limit) break;
        }
      }
    } catch (_) {
    } finally {
      try {
        ws?.add(closeMessage);
      } catch (_) {}
      try {
        await ws?.close();
      } catch (_) {}
    }

    return results;
  }
}
