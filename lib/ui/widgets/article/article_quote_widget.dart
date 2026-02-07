import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';

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
      final articles = await articleRepo.getArticles(limit: 50);

      for (final article in articles) {
        final articleDTag = article.dTag ?? '';
        final articlePubkey = article.pubkey;
        final articleDTagHex = _stringToHex(articleDTag);
        final dTagMatch = dTag == null || articleDTagHex == dTag;
        final pubkeyMatch = pubkey == null || articlePubkey == pubkey;

        if (dTagMatch && pubkeyMatch) {
          setState(() {
            _article = {
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
            _isLoading = false;
          });
          _loadAuthorProfile(articlePubkey);
          return;
        }
      }
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
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

  Map<String, dynamic>? _processArticleEvent(Map<String, dynamic> eventData) {
    try {
      final id = eventData['id'] as String? ?? '';
      final pubkey = eventData['pubkey'] as String? ?? '';
      final content = eventData['content'] as String? ?? '';
      final createdAt = eventData['created_at'] as int? ?? 0;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      final authService = AppDI.get<AuthService>();
      final authorNpub = authService.hexToNpub(pubkey) ?? pubkey;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      String? title;
      String? image;
      String? summary;
      String? dTag;

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          final tagName = tag[0] as String?;
          if (tagName == 'title' && tag.length > 1) {
            title = tag[1] as String?;
          } else if (tagName == 'image' && tag.length > 1) {
            image = tag[1] as String?;
          } else if (tagName == 'summary' && tag.length > 1) {
            summary = tag[1] as String?;
          } else if (tagName == 'd' && tag.length > 1) {
            dTag = tag[1] as String?;
          }
        }
      }

      return {
        'id': id,
        'dTag': dTag ?? id,
        'content': content,
        'author': authorNpub,
        'pubkey': pubkey,
        'timestamp': timestamp,
        'title': title ?? '',
        'image': image ?? '',
        'summary': summary ?? '',
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
    } catch (e) {}
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
