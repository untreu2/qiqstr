import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/article/article_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/article/article_bloc.dart';
import '../../../presentation/blocs/article/article_event.dart';
import '../../../presentation/blocs/article/article_state.dart';
import '../../../data/services/auth_service.dart';
import '../../../l10n/app_localizations.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);
  Timer? _scrollDebounceTimer;
  String? _currentUserHex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
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

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showTitleBubble.value != shouldShow) {
        _showTitleBubble.value = shouldShow;
      }
    }
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _scrollController.dispose();
    _showTitleBubble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

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
                CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  cacheExtent: 600,
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                          height: MediaQuery.of(context).padding.top + 60),
                    ),
                    SliverToBoxAdapter(
                      child: TitleWidget(
                        title: l10n.reads,
                        fontSize: 32,
                        subtitle: l10n.readsSubtitle,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 16),
                    ),
                    _buildContent(context, articleState, colors, l10n),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 150),
                    ),
                  ],
                ),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  showShareButton: false,
                  centerBubble: Text(
                    l10n.reads,
                    style: TextStyle(
                      color: colors.background,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  centerBubbleVisibility: _showTitleBubble,
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
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ArticleState articleState,
    AppThemeColors colors,
    AppLocalizations l10n,
  ) {
    return switch (articleState) {
      ArticleInitial() || ArticleLoading() => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
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
                    l10n.loadingArticles,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ArticleLoaded(
        :final filteredArticles,
        :final profiles,
        :final currentUserHex,
        :final isLoadingMore,
        :final canLoadMore
      ) =>
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
      ArticleError(:final message) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    CarbonIcons.warning,
                    size: 48,
                    color: colors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.somethingWentWrong,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: l10n.retryText,
                    onPressed: () {
                      context
                          .read<ArticleBloc>()
                          .add(const ArticleRefreshed());
                    },
                    backgroundColor: colors.accent,
                    foregroundColor: colors.background,
                  ),
                ],
              ),
            ),
          ),
        ),
      ArticleEmpty() => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CarbonIcons.document,
                    size: 48,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noArticlesYet,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.longFormContentDescription,
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      _ => const SliverToBoxAdapter(child: SizedBox()),
    };
  }
}
