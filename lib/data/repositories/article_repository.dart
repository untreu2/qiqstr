import 'dart:async';
import '../../domain/entities/article.dart';
import '../services/encrypted_mute_service.dart';
import 'base_repository.dart';

abstract class ArticleRepository {
  Stream<List<Article>> watchArticles({int limit = 50});
  Future<List<Article>> getArticles({int limit = 50});
  Future<Article?> getArticle(String articleId);
  Future<void> saveArticles(List<Map<String, dynamic>> articles);
}

class ArticleRepositoryImpl extends BaseRepository
    implements ArticleRepository {
  ArticleRepositoryImpl({
    required super.db,
    required super.mapper,
  });

  @override
  Stream<List<Article>> watchArticles({int limit = 50}) {
    return db.watchArticles(limit: limit).asyncMap((events) async {
      return await _hydrateArticles(events);
    });
  }

  @override
  Future<List<Article>> getArticles({int limit = 50}) async {
    final events = await db.getCachedArticles(limit: limit);
    return await _hydrateArticles(events);
  }

  @override
  Future<Article?> getArticle(String articleId) async {
    final event = await db.getEventModel(articleId);
    if (event == null) return null;

    final pubkey = event['pubkey'] as String? ?? '';
    final profile = await db.getUserProfile(pubkey);

    return mapper.toArticle(
      event,
      authorName: profile?['name'] ?? profile?['display_name'],
      authorImage: profile?['picture'],
    );
  }

  @override
  Future<void> saveArticles(List<Map<String, dynamic>> articles) async {
    await db.saveArticles(articles);
  }

  Future<List<Article>> _hydrateArticles(
      List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return [];

    final muteService = EncryptedMuteService.instance;
    final filteredEvents = events
        .where((event) => !muteService.shouldFilterEvent(event))
        .toList();

    if (filteredEvents.isEmpty) return [];

    final pubkeys = filteredEvents
        .map((e) => e['pubkey'] as String? ?? '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();
    final profiles = await db.getUserProfiles(pubkeys);

    return filteredEvents.map((event) {
      final pubkey = event['pubkey'] as String? ?? '';
      final profile = profiles[pubkey];

      return mapper.toArticle(
        event,
        authorName: profile?['name'] ?? profile?['display_name'],
        authorImage: profile?['picture'],
      );
    }).toList();
  }
}
