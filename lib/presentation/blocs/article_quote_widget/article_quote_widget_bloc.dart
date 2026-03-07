import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import 'article_quote_widget_event.dart';
import 'article_quote_widget_state.dart';

class ArticleQuoteWidgetBloc
    extends Bloc<ArticleQuoteWidgetEvent, ArticleQuoteWidgetState> {
  final ArticleRepository _articleRepository;
  final SyncService _syncService;

  ArticleQuoteWidgetBloc({
    required ArticleRepository articleRepository,
    required SyncService syncService,
  })  : _articleRepository = articleRepository,
        _syncService = syncService,
        super(const ArticleQuoteWidgetInitial()) {
    on<ArticleQuoteWidgetLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    ArticleQuoteWidgetLoadRequested event,
    Emitter<ArticleQuoteWidgetState> emit,
  ) async {
    emit(const ArticleQuoteWidgetLoading());

    final decoded = _decodeNaddr(event.naddr);
    if (decoded == null) {
      emit(const ArticleQuoteWidgetError());
      return;
    }

    final kind = decoded['kind'] as int?;
    final pubkey = decoded['pubkey'] as String?;
    final identifier = decoded['identifier'] as String?;

    if ((kind != null && kind != 30023) ||
        (pubkey == null && identifier == null)) {
      emit(const ArticleQuoteWidgetError());
      return;
    }

    try {
      var article = pubkey != null && identifier != null
          ? await _articleRepository.getArticleByNaddr(
              pubkeyHex: pubkey,
              identifier: identifier,
            )
          : null;

      if (article == null && pubkey != null) {
        await _syncService.syncArticles(
            authors: [pubkey], limit: 20).timeout(const Duration(seconds: 8));
        if (isClosed) return;

        if (identifier != null) {
          article = await _articleRepository.getArticleByNaddr(
            pubkeyHex: pubkey,
            identifier: identifier,
          );
        }
      }

      if (isClosed) return;

      if (article != null) {
        emit(ArticleQuoteWidgetLoaded(article: article));
      } else {
        emit(const ArticleQuoteWidgetError());
      }
    } catch (_) {
      if (!isClosed) emit(const ArticleQuoteWidgetError());
    }
  }

  Map<String, dynamic>? _decodeNaddr(String naddr) {
    try {
      final clean = naddr.startsWith('nostr:') ? naddr.substring(6) : naddr;
      final result = decodeTlvBech32Full(clean);
      final identifier = result['identifier'] as String?;
      final pubkey = result['pubkey'] as String?;
      final kindValue = result['kind'];
      int? kind;
      if (kindValue is int) {
        kind = kindValue;
      } else if (kindValue is String) {
        kind = int.tryParse(kindValue);
      }
      return {'kind': kind, 'pubkey': pubkey, 'identifier': identifier};
    } catch (_) {
      return null;
    }
  }
}
