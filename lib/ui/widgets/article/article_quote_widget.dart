import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/article_quote_widget/article_quote_widget_bloc.dart';
import '../../../presentation/blocs/article_quote_widget/article_quote_widget_event.dart';
import '../../../presentation/blocs/article_quote_widget/article_quote_widget_state.dart';
import '../../../domain/entities/article.dart';
import '../../theme/theme_manager.dart';
import '../../../l10n/app_localizations.dart';

class ArticleQuoteWidget extends StatelessWidget {
  final String naddr;

  const ArticleQuoteWidget({
    super.key,
    required this.naddr,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppDI.get<ArticleQuoteWidgetBloc>()
        ..add(ArticleQuoteWidgetLoadRequested(naddr: naddr)),
      child: BlocBuilder<ArticleQuoteWidgetBloc, ArticleQuoteWidgetState>(
        builder: (context, state) {
          if (state is ArticleQuoteWidgetLoaded) {
            return _ArticleQuoteCard(article: state.article, naddr: naddr);
          }
          if (state is ArticleQuoteWidgetError) {
            return _ArticleQuoteError();
          }
          return _ArticleQuoteLoading();
        },
      ),
    );
  }
}

class _ArticleQuoteLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ArticleQuoteError extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.article_outlined, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            l10n.articleNotFound,
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ArticleQuoteCard extends StatelessWidget {
  final Article article;
  final String naddr;

  const _ArticleQuoteCard({required this.article, required this.naddr});

  void _navigate(BuildContext context) {
    final articleId = article.id;
    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push(
          '/home/feed/article?articleId=${Uri.encodeComponent(articleId)}');
    } else {
      context.push('/article?articleId=${Uri.encodeComponent(articleId)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    final title =
        article.title.isNotEmpty ? article.title : l10n.untitledArticle;
    final summary = article.summary ?? '';
    final imageUrl = article.image ?? '';
    final authorName = article.authorName ?? '';
    final authorImage = article.authorImage ?? '';
    final pubkey = article.pubkey;
    final displayName = authorName.isNotEmpty
        ? authorName
        : (pubkey.length > 8 ? '${pubkey.substring(0, 8)}...' : pubkey);

    return GestureDetector(
      onTap: () => _navigate(context),
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 0),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: 120,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 120,
                    color: colors.overlayLight,
                  ),
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.article_outlined,
                          size: 14, color: colors.accent),
                      const SizedBox(width: 6),
                      Text(
                        l10n.article,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.accent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: colors.overlayLight,
                        backgroundImage: authorImage.isNotEmpty
                            ? CachedNetworkImageProvider(authorImage)
                            : null,
                        child: authorImage.isEmpty
                            ? Icon(Icons.person,
                                size: 12, color: colors.textSecondary)
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
