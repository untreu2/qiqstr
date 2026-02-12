import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/article/article_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/article/article_bloc.dart';
import '../../../presentation/blocs/article/article_event.dart';
import '../../../presentation/blocs/article/article_state.dart';
import '../../../data/services/auth_service.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  late ScrollController _scrollController;
  Timer? _scrollDebounceTimer;
  String? _currentUserHex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadCurrentUserHex();
  }

  Future<void> _loadCurrentUserHex() async {
    final authService = AppDI.get<AuthService>();
    final hex = authService.currentUserPubkeyHex;
    if (hex != null && mounted) {
      setState(() {
        _currentUserHex = hex;
      });
    }
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_currentUserHex == null) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2),
        ),
      );
    }

    return BlocProvider<ArticleBloc>(
      create: (context) {
        final bloc = AppDI.get<ArticleBloc>();
        bloc.add(ArticleInitialized(userHex: _currentUserHex!));
        return bloc;
      },
      child: BlocBuilder<ArticleBloc, ArticleState>(
        builder: (context, articleState) {
          return Scaffold(
            backgroundColor: colors.background,
            body: Stack(
              children: [
                _buildArticleContent(context, articleState, colors),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  centerBubble: Text(
                    'Reads',
                    style: TextStyle(
                      color: colors.background,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onCenterBubbleTap: () {
                    scrollToTop();
                  },
                  showShareButton: false,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildArticleContent(
    BuildContext context,
    ArticleState articleState,
    AppThemeColors colors,
  ) {
    final topPadding = MediaQuery.of(context).padding.top;

    return switch (articleState) {
      ArticleInitial() || ArticleLoading() => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: colors.textSecondary,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading articles...',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ArticleLoaded(
        :final filteredArticles,
        :final profiles,
        :final currentUserHex,
        :final isLoadingMore,
        :final canLoadMore
      ) =>
        RefreshIndicator(
          onRefresh: () async {
            context.read<ArticleBloc>().add(const ArticleRefreshed());
          },
          color: colors.textPrimary,
          child: CustomScrollView(
            key: const PageStorageKey<String>('explore_scroll'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            cacheExtent: 600,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: topPadding + 72),
              ),
              ArticleListWidget(
                articles: filteredArticles,
                currentUserHex: currentUserHex,
                profiles: profiles,
                isLoading: isLoadingMore,
                canLoadMore: canLoadMore,
                onLoadMore: () {
                  context
                      .read<ArticleBloc>()
                      .add(const ArticleLoadMoreRequested());
                },
                onEmptyRefresh: () {
                  context.read<ArticleBloc>().add(const ArticleRefreshed());
                },
                scrollController: _scrollController,
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
        ),
      ArticleError(:final message) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    context
                        .read<ArticleBloc>()
                        .add(const ArticleRefreshed());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colors.textPrimary,
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
          ),
        ),
      ArticleEmpty() => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 48,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No articles yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Long-form content from people you follow will appear here.',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      _ => Center(
          child: CircularProgressIndicator(
            color: colors.accent,
            strokeWidth: 2,
          ),
        ),
    };
  }
}
