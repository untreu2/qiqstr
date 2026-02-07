import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../core/di/app_di.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/top_action_bar_widget.dart';

class ArticleDetailPage extends StatefulWidget {
  final String articleId;

  const ArticleDetailPage({super.key, required this.articleId});

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  Map<String, dynamic>? _article;
  Map<String, dynamic>? _authorUser;
  bool _isLoading = true;
  String? _error;

  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadArticle();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadArticle() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final articleRepo = AppDI.get<ArticleRepository>();
      final article = await articleRepo.getArticle(widget.articleId);

      if (article != null) {
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
            'authorName': article.authorName,
            'authorImage': article.authorImage,
            'created_at': article.createdAt,
            'publishedAt': article.publishedAt,
          };
          _isLoading = false;
        });

        if (article.authorName != null && article.authorName!.isNotEmpty) {
          setState(() {
            _authorUser = {
              'name': article.authorName,
              'profileImage': article.authorImage,
              'picture': article.authorImage,
            };
          });
        } else {
          _loadAuthorProfile();
        }
      } else {
        setState(() {
          _error = 'Article not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load article: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAuthorProfile() async {
    if (_article == null) return;

    final pubkey = _article!['pubkey'] as String? ?? '';
    if (pubkey.isEmpty) return;

    final profileRepo = AppDI.get<ProfileRepository>();
    final profile = await profileRepo.getProfile(pubkey);
    if (profile != null && mounted) {
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
        };
      });
    }
  }

  String _formatDate(DateTime timestamp) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year}';
  }

  void _navigateToProfile() {
    if (_article == null) return;

    final pubkey = _article!['pubkey'] as String? ?? '';
    final userNpub = _authorUser?['npub'] as String? ?? '';
    final currentLocation = GoRouterState.of(context).matchedLocation;

    if (currentLocation.startsWith('/home/feed')) {
      context.push(
          '/home/feed/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(pubkey)}');
    } else {
      context.push(
          '/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(pubkey)}');
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Could not launch URL: $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          if (_isLoading)
            _buildLoadingState(colors)
          else if (_error != null)
            _buildErrorState(colors)
          else if (_article != null)
            _buildArticleContent(colors),
          TopActionBarWidget(
            onBackPressed: () => context.pop(),
            centerBubble: Text(
              'Article',
              style: TextStyle(
                color: colors.background,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            onCenterBubbleTap: () {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(AppThemeColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: colors.accent),
          const SizedBox(height: 16),
          Text(
            'Loading article...',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(AppThemeColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: colors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load article',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error!,
              style: TextStyle(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _loadArticle,
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
                'Retry',
                style: TextStyle(
                  color: colors.background,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleContent(AppThemeColors colors) {
    final title = _article!['title'] as String? ?? 'Untitled';
    final content = _article!['content'] as String? ?? '';
    final imageUrl = _article!['image'] as String? ?? '';
    final summary = _article!['summary'] as String? ?? '';

    final createdAt = _article!['created_at'];
    final DateTime timestamp;
    if (createdAt is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    } else if (createdAt is DateTime) {
      timestamp = createdAt;
    } else {
      timestamp = DateTime.now();
    }

    final pubAt = _article!['publishedAt'];
    final DateTime publishedAt;
    if (pubAt is int) {
      publishedAt = DateTime.fromMillisecondsSinceEpoch(pubAt * 1000);
    } else if (pubAt is DateTime) {
      publishedAt = pubAt;
    } else {
      publishedAt = timestamp;
    }

    final authorNameFromArticle = _article!['author'] as String? ?? '';
    final authorImageFromArticle = _article!['authorImage'] as String? ?? '';
    final authorName = _authorUser?['name'] as String? ??
        _authorUser?['display_name'] as String? ??
        authorNameFromArticle;
    final authorImage = _authorUser?['profileImage'] as String? ??
        _authorUser?['picture'] as String? ??
        authorImageFromArticle;
    final pubkey = _article!['pubkey'] as String? ?? '';
    final displayName = authorName.isNotEmpty
        ? authorName
        : (pubkey.length > 8 ? '${pubkey.substring(0, 8)}...' : pubkey);

    final topPadding = MediaQuery.of(context).padding.top;

    return RefreshIndicator(
      onRefresh: _loadArticle,
      color: colors.textPrimary,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: topPadding + 80),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 200,
                          color: colors.overlayLight,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: colors.accent,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 200,
                          color: colors.overlayLight,
                          child: Icon(
                            Icons.image_not_supported,
                            color: colors.textSecondary,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    imageUrl.isEmpty ? 0 : 20,
                    20,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          summary,
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.textSecondary,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _navigateToProfile,
                        child: Row(
                          children: [
                            ClipOval(
                              child: authorImage.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: authorImage,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        width: 40,
                                        height: 40,
                                        color: colors.overlayLight,
                                        child: Icon(
                                          Icons.person,
                                          size: 20,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        width: 40,
                                        height: 40,
                                        color: colors.overlayLight,
                                        child: Icon(
                                          Icons.person,
                                          size: 20,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      width: 40,
                                      height: 40,
                                      color: colors.overlayLight,
                                      child: Icon(
                                        Icons.person,
                                        size: 20,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              _formatDate(publishedAt),
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        height: 1,
                        color: colors.divider.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 20),
                      MarkdownBody(
                        data: content,
                        selectable: true,
                        extensionSet: md.ExtensionSet(
                          md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                          <md.InlineSyntax>[
                            md.EmojiSyntax(),
                            ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                          ],
                        ),
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            fontSize: 16,
                            color: colors.textPrimary,
                            height: 1.7,
                          ),
                          h1: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                            height: 1.3,
                          ),
                          h2: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                            height: 1.3,
                          ),
                          h3: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            height: 1.3,
                          ),
                          h4: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            height: 1.3,
                          ),
                          h5: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            height: 1.3,
                          ),
                          h6: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            height: 1.3,
                          ),
                          em: TextStyle(
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                            color: colors.textPrimary,
                          ),
                          strong: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                          blockquote: TextStyle(
                            fontSize: 16,
                            color: colors.textSecondary,
                            fontStyle: FontStyle.italic,
                            height: 1.5,
                          ),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: colors.accent,
                                width: 4,
                              ),
                            ),
                          ),
                          blockquotePadding: const EdgeInsets.only(left: 16),
                          code: TextStyle(
                            fontSize: 14,
                            color: colors.textPrimary,
                            backgroundColor: colors.overlayLight,
                            fontFamily: 'monospace',
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: colors.overlayLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          codeblockPadding: const EdgeInsets.all(16),
                          a: TextStyle(
                            fontSize: 16,
                            color: colors.accent,
                            decoration: TextDecoration.underline,
                          ),
                          listBullet: TextStyle(
                            fontSize: 16,
                            color: colors.textPrimary,
                          ),
                          tableHead: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                          tableBody: TextStyle(
                            fontSize: 14,
                            color: colors.textPrimary,
                          ),
                          tableBorder: TableBorder.all(
                            color: colors.divider,
                            width: 1,
                          ),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: colors.divider,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        onTapLink: (text, href, title) {
                          if (href != null) {
                            _launchUrl(href);
                          }
                        },
                        imageBuilder: (uri, title, alt) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: uri.toString(),
                                fit: BoxFit.contain,
                                placeholder: (context, url) => Container(
                                  height: 150,
                                  color: colors.overlayLight,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: colors.accent,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  height: 100,
                                  color: colors.overlayLight,
                                  child: Icon(
                                    Icons.image_not_supported,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child:
                SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
          ),
        ],
      ),
    );
  }
}
