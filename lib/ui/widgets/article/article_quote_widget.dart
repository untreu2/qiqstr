import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';


class ArticleQuoteWidget extends StatefulWidget {
  final String naddr;

  const ArticleQuoteWidget({
    super.key,
    required this.naddr,
  });

  @override
  State<ArticleQuoteWidget> createState() => _ArticleQuoteWidgetState();
}

class _ArticleQuoteWidgetState extends State<ArticleQuoteWidget> {
  Map<String, dynamic>? _article;
  Map<String, dynamic>? _author;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  String _stringToHex(String input) {
    return input.codeUnits
        .map((c) => c.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _loadArticle() async {
    try {
      final decoded = _decodeNaddr(widget.naddr);
      if (decoded == null) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
        return;
      }

      final kind = decoded['kind'] as int?;
      final pubkey = decoded['pubkey'] as String?;
      final dTag = decoded['dTag'] as String?;

      if (kind != null && kind != 30023) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
        return;
      }

      if (pubkey == null && dTag == null) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
        return;
      }

      final articleRepo = AppDI.get<ArticleRepository>();
      var articles = await articleRepo.getArticles(limit: 50);

      Map<String, dynamic>? foundArticle;
      for (final article in articles) {
        final articleDTag = article.dTag;
        final articlePubkey = article.pubkey;
        final articleDTagHex = _stringToHex(articleDTag);
        
        bool matches = false;
        if (pubkey != null && dTag != null) {
          matches = articlePubkey == pubkey && articleDTagHex == dTag;
        } else if (pubkey != null) {
          matches = articlePubkey == pubkey;
        } else if (dTag != null) {
          matches = articleDTagHex == dTag;
        }

        if (matches) {
          foundArticle = {
            'id': article.id,
            'dTag': article.dTag,
            'title': article.title,
            'summary': article.summary,
            'image': article.image,
            'content': article.content,
            'pubkey': article.pubkey,
            'author': article.authorName,
            'authorImage': article.authorImage,
            'timestamp': article.createdAt,
          };
          break;
        }
      }

      if (foundArticle == null && pubkey != null) {
        final syncService = AppDI.get<SyncService>();
        await syncService.syncArticles(authors: [pubkey], limit: 10);
        
        await Future.delayed(const Duration(milliseconds: 500));
        articles = await articleRepo.getArticles(limit: 50);
        
        for (final article in articles) {
          final articleDTag = article.dTag;
          final articlePubkey = article.pubkey;
          final articleDTagHex = _stringToHex(articleDTag);
          
          bool matches = false;
          if (dTag != null) {
            matches = articlePubkey == pubkey && articleDTagHex == dTag;
          } else {
            matches = articlePubkey == pubkey;
          }

          if (matches) {
            foundArticle = {
              'id': article.id,
              'dTag': article.dTag,
              'title': article.title,
              'summary': article.summary,
              'image': article.image,
              'content': article.content,
              'pubkey': article.pubkey,
              'author': article.authorName,
              'authorImage': article.authorImage,
              'timestamp': article.createdAt,
            };
            break;
          }
        }
      }

      if (foundArticle != null) {
        setState(() {
          _article = foundArticle;
          _isLoading = false;
        });
        _loadAuthorProfile(foundArticle['pubkey'] as String);
      } else {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _decodeNaddr(String naddr) {
    try {
      final cleanNaddr =
          naddr.startsWith('nostr:') ? naddr.substring(6) : naddr;

      final result = decodeTlvBech32Full(cleanNaddr);
      final dTagHex = result['identifier'] as String?;
      final pubkey = result['pubkey'] as String?;
      final kindValue = result['kind'];
      int? kind;
      if (kindValue is int) {
        kind = kindValue;
      } else if (kindValue is String) {
        kind = int.tryParse(kindValue);
      }

      return {
        'kind': kind,
        'pubkey': pubkey,
        'dTag': dTagHex,
      };
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadAuthorProfile(String pubkeyHex) async {
    try {
      final profileRepo = AppDI.get<ProfileRepository>();
      final profile = await profileRepo.getProfile(pubkeyHex);
      if (profile != null && mounted) {
        setState(() {
          _author = {
            'pubkeyHex': profile.pubkey,
            'name': profile.name ?? '',
            'about': profile.about ?? '',
            'profileImage': profile.picture ?? '',
            'banner': profile.banner ?? '',
            'website': profile.website ?? '',
            'nip05': profile.nip05 ?? '',
            'lud16': profile.lud16 ?? '',
          };
        });
      }
    } catch (_) {}
  }

  void _navigateToArticle() {
    if (_article == null) return;

    final articleId = _article!['id'] as String? ?? '';
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

    if (_isLoading) {
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

    if (_hasError || _article == null) {
      return const SizedBox.shrink();
    }

    final title = _article!['title'] as String? ?? 'Untitled Article';
    final summary = _article!['summary'] as String? ?? '';
    final imageUrl = _article!['image'] as String? ?? '';
    final authorName = _author?['name'] as String? ?? '';
    final authorImage = _author?['profileImage'] as String? ?? '';
    final authorId = _article!['author'] as String? ?? '';
    final displayName = authorName.isNotEmpty
        ? authorName
        : (authorId.length > 8 ? '${authorId.substring(0, 8)}...' : authorId);

    return GestureDetector(
      onTap: _navigateToArticle,
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
                      Icon(
                        Icons.article_outlined,
                        size: 14,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Article',
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
                            ? Icon(
                                Icons.person,
                                size: 12,
                                color: colors.textSecondary,
                              )
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
