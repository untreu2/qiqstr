import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../theme/theme_manager.dart';

class ArticleWidget extends StatefulWidget {
  final Map<String, dynamic> article;
  final String currentUserHex;
  final Map<String, Map<String, dynamic>> profiles;

  const ArticleWidget({
    super.key,
    required this.article,
    required this.currentUserHex,
    required this.profiles,
  });

  @override
  State<ArticleWidget> createState() => _ArticleWidgetState();
}

class _ArticleWidgetState extends State<ArticleWidget> {
  late final String _articleId;
  late final String _authorPubkey;
  late final String _title;
  late final String _summary;
  late final String _imageUrl;
  late final DateTime _timestamp;
  late final String _authorName;
  late final String _authorImage;

  Map<String, dynamic>? _authorUser;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _precomputeData();
    _loadAuthorProfile();
  }

  void _precomputeData() {
    _articleId = widget.article['id'] as String? ?? '';
    _authorPubkey = widget.article['pubkey'] as String? ?? '';
    _title = widget.article['title'] as String? ?? 'Untitled';
    _summary = widget.article['summary'] as String? ?? '';
    _imageUrl = widget.article['image'] as String? ?? '';

    final createdAt = widget.article['created_at'];
    if (createdAt is int) {
      _timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    } else {
      _timestamp = widget.article['timestamp'] as DateTime? ?? DateTime.now();
    }

    _authorName = widget.article['author'] as String? ?? '';
    _authorImage = widget.article['authorImage'] as String? ?? '';

    _authorUser = widget.profiles[_authorPubkey];
  }

  Future<void> _loadAuthorProfile() async {
    if (_authorUser != null || _authorName.isNotEmpty) return;

    final profileRepo = AppDI.get<ProfileRepository>();
    final profile = await profileRepo.getProfile(_authorPubkey);
    if (profile != null && mounted && !_isDisposed) {
      setState(() {
        _authorUser = {
          'pubkeyHex': profile.pubkey,
          'name': profile.name ?? '',
          'about': profile.about ?? '',
          'profileImage': profile.picture ?? '',
          'banner': profile.banner ?? '',
          'website': profile.website ?? '',
          'nip05': profile.nip05 ?? '',
          'lud16': profile.lud16 ?? '',
          'updatedAt': DateTime.now(),
          'nip05Verified': false,
        };
      });
    }
  }

  @override
  void didUpdateWidget(ArticleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profiles != widget.profiles) {
      final newAuthor = widget.profiles[_authorPubkey];
      if (newAuthor != null && _authorUser != newAuthor) {
        setState(() {
          _authorUser = newAuthor;
        });
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  String _formatTimestamp(DateTime timestamp) {
    final d = DateTime.now().difference(timestamp);
    if (d.inSeconds < 5) return 'now';
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
    if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
    return '${(d.inDays / 365).floor()}y';
  }

  void _navigateToArticle() {
    if (!mounted || _isDisposed) return;

    final currentLocation = GoRouterState.of(context).matchedLocation;
    final articleId = Uri.encodeComponent(_articleId);

    if (currentLocation.startsWith('/home/feed')) {
      context.push('/home/feed/article?articleId=$articleId');
    } else {
      context.push('/article?articleId=$articleId');
    }
  }

  void _navigateToProfile() {
    if (!mounted || _isDisposed) return;

    final userNpub = _authorUser?['npub'] as String? ?? '';
    final userPubkeyHex = _authorPubkey;
    final currentLocation = GoRouterState.of(context).matchedLocation;

    if (currentLocation.startsWith('/home/feed')) {
      context.push(
          '/home/feed/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
    } else {
      context.push(
          '/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final authorNameFromUser = _authorUser?['name'] as String? ??
        _authorUser?['display_name'] as String? ??
        '';
    final authorImageFromUser = _authorUser?['profileImage'] as String? ??
        _authorUser?['picture'] as String? ??
        '';

    final authorName =
        _authorName.isNotEmpty ? _authorName : authorNameFromUser;
    final authorImage =
        _authorImage.isNotEmpty ? _authorImage : authorImageFromUser;

    final displayName = authorName.isNotEmpty
        ? authorName
        : (_authorPubkey.length > 8
            ? '${_authorPubkey.substring(0, 8)}...'
            : _authorPubkey);

    return GestureDetector(
      onTap: _navigateToArticle,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.textSecondary.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: CachedNetworkImage(
                  imageUrl: _imageUrl,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 180,
                    color: colors.overlayLight,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: colors.accent,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 180,
                    color: colors.overlayLight,
                    child: Icon(
                      Icons.image_not_supported,
                      color: colors.textSecondary,
                      size: 48,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _summary,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _navigateToProfile,
                    child: Row(
                      children: [
                        ClipOval(
                          child: authorImage.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: authorImage,
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    width: 28,
                                    height: 28,
                                    color: colors.overlayLight,
                                    child: Icon(
                                      Icons.person,
                                      size: 16,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    width: 28,
                                    height: 28,
                                    color: colors.overlayLight,
                                    child: Icon(
                                      Icons.person,
                                      size: 16,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 28,
                                  height: 28,
                                  color: colors.overlayLight,
                                  child: Icon(
                                    Icons.person,
                                    size: 16,
                                    color: colors.textSecondary,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatTimestamp(_timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
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

class ArticleListWidget extends StatelessWidget {
  final List<Map<String, dynamic>> articles;
  final String currentUserHex;
  final Map<String, Map<String, dynamic>> profiles;
  final bool isLoading;
  final bool canLoadMore;
  final VoidCallback? onLoadMore;
  final VoidCallback? onEmptyRefresh;
  final ScrollController? scrollController;

  const ArticleListWidget({
    super.key,
    required this.articles,
    required this.currentUserHex,
    required this.profiles,
    this.isLoading = false,
    this.canLoadMore = true,
    this.onLoadMore,
    this.onEmptyRefresh,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (articles.isEmpty && !isLoading) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 64,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No articles found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Check back later for new long-form content',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onEmptyRefresh != null) ...[
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: onEmptyRefresh,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Refresh',
                        style: TextStyle(
                          color: colors.background,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == articles.length) {
            if (isLoading) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: CircularProgressIndicator(
                    color: colors.accent,
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            if (canLoadMore && onLoadMore != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onLoadMore!();
              });
            }
            return const SizedBox(height: 100);
          }

          final article = articles[index];
          return ArticleWidget(
            article: article,
            currentUserHex: currentUserHex,
            profiles: profiles,
          );
        },
        childCount: articles.length + 1,
      ),
    );
  }
}
