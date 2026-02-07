import 'dart:async';
import '../../domain/entities/article.dart';
import '../../models/event_model.dart';
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
    final articlesData = await db.getCachedArticles(limit: limit);
    final events = <EventModel>[];

    for (final data in articlesData) {
      final eventId = data['id'] as String?;
      if (eventId != null) {
        final event = await db.getEventModel(eventId);
        if (event != null) {
          events.add(event);
        }
      }
    }

    return await _hydrateArticles(events);
  }

  @override
  Future<Article?> getArticle(String articleId) async {
    final event = await db.getEventModel(articleId);
    if (event == null) return null;

    final profile = await db.getUserProfile(event.pubkey);

    return mapper.toArticle(
      event,
      authorName: profile?['name'] ?? profile?['display_name'],
      authorImage: profile?['profileImage'],
    );
  }

  @override
  Future<void> saveArticles(List<Map<String, dynamic>> articles) async {
    await db.saveArticles(articles);
  }

  Future<List<Article>> _hydrateArticles(List<EventModel> events) async {
    if (events.isEmpty) return [];

    final pubkeys = events.map((e) => e.pubkey).toSet().toList();
    final profiles = await db.getUserProfiles(pubkeys);

    return events.map((event) {
      final profile = profiles[event.pubkey];

      return mapper.toArticle(
        event,
        authorName: profile?['name'] ?? profile?['display_name'],
        authorImage: profile?['profileImage'],
      );
    }).toList();
  }
}
