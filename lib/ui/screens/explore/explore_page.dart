import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/article/article_widget.dart';
import '../../widgets/common/back_button_widget.dart';
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

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Reads',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_currentUserHex == null) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: CircularProgressIndicator(color: colors.accent),
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
                _buildArticleContent(
                  context,
                  articleState,
                  colors,
                ),
                const BackButtonWidget.floating(),
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
    return switch (articleState) {
      ArticleInitial() => Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
      ArticleLoading() => Center(
          child: CircularProgressIndicator(color: colors.accent),
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
                child: _buildHeader(context),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 4),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colors.error,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  context.read<ArticleBloc>().add(const ArticleRefreshed());
                },
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
        ),
      ArticleEmpty() => Center(
          child: Text(
            'No articles available',
            style: TextStyle(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      _ => Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
    };
  }
}
