import 'dart:async';
import '../../domain/entities/article.dart';
import 'base_repository.dart';

abstract class ArticleRepository {
  Stream<List<Article>> watchArticles({int limit = 50});
  Future<List<Article>> getArticles({int limit = 50});
  Future<List<Article>> getArticlesByAuthor(String pubkey, {int limit = 50});
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
    return db
        .watchHydratedArticles(limit: limit)
        .map((maps) => maps.map((m) => Article.fromMap(m)).toList());
  }

  @override
  Future<List<Article>> getArticles({int limit = 50}) async {
    final maps = await db.getHydratedArticles(limit: limit);
    return maps.map((m) => Article.fromMap(m)).toList();
  }

  @override
  Future<List<Article>> getArticlesByAuthor(String pubkey,
      {int limit = 50}) async {
    final maps =
        await db.getHydratedArticles(limit: limit, authors: [pubkey]);
    return maps.map((m) => Article.fromMap(m)).toList();
  }

  @override
  Future<Article?> getArticle(String articleId) async {
    final map = await db.getHydratedArticle(articleId);
    if (map == null) return null;
    return Article.fromMap(map);
  }

  @override
  Future<void> saveArticles(List<Map<String, dynamic>> articles) async {
    await db.saveArticles(articles);
  }
}
