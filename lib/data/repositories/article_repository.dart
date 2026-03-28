import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entities/article.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../services/encrypted_mute_service.dart';
import '../services/rust_database_service.dart';

class ArticleRepository {
  final RustDatabaseService _events;

  ArticleRepository({required RustDatabaseService events}) : _events = events;

  List<String> get _mutedPubkeys => EncryptedMuteService.instance.mutedPubkeys;
  List<String> get _mutedWords => EncryptedMuteService.instance.mutedWords;

  Stream<List<Article>> watchArticles({List<String>? authors, int limit = 50}) {
    return _events.onChange
        .debounceTime(const Duration(milliseconds: 250))
        .startWith(null)
        .asyncMap((_) => getArticles(authors: authors, limit: limit));
  }

  Future<List<Article>> getArticles(
      {List<String>? authors, int limit = 50}) async {
    try {
      final json = await rust_db.dbGetHydratedArticles(
        authorsHex: authors,
        limit: limit,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map((m) => Article.fromMap(m))
          .toList();
    } catch (e) {
      if (kDebugMode) print('[ArticleRepository] getArticles error: $e');
      return [];
    }
  }

  Future<Article?> getArticle(String articleId) async {
    try {
      final json = await rust_db.dbGetHydratedArticle(eventId: articleId);
      if (json == null) return null;
      return Article.fromMap(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) print('[ArticleRepository] getArticle error: $e');
      return null;
    }
  }

  Future<Article?> getArticleByNaddr({
    required String pubkeyHex,
    required String identifier,
  }) async {
    try {
      final json = await rust_db.dbGetHydratedArticleByNaddr(
        pubkeyHex: pubkeyHex,
        dTag: identifier,
      );
      if (json == null) return null;
      return Article.fromMap(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) print('[ArticleRepository] getArticleByNaddr error: $e');
      return null;
    }
  }

  Future<void> save(List<Map<String, dynamic>> articles) async {
    if (articles.isEmpty) return;
    try {
      await rust_db.dbSaveEvents(eventsJson: jsonEncode(articles));
      _events.notifyChange();
    } catch (e) {
      if (kDebugMode) print('[ArticleRepository] save error: $e');
    }
  }
}
