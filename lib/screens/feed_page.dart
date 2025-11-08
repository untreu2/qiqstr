import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/widgets/note_list_widget.dart' as widgets;
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/widgets/back_button_widget.dart';
import '../widgets/common_buttons.dart';
import '../theme/theme_manager.dart';
import '../models/note_model.dart';
import '../core/ui/ui_state_builder.dart';
import '../core/di/app_di.dart';
import '../presentation/providers/viewmodel_provider.dart';
import '../presentation/viewmodels/feed_viewmodel.dart';

class FeedPage extends StatefulWidget {
  final String npub;
  final String? hashtag;
  const FeedPage({super.key, required this.npub, this.hashtag});

  @override
  FeedPageState createState() => FeedPageState();
}

class FeedPageState extends State<FeedPage> {
  late ScrollController _scrollController;
  bool _showAppBar = true;
  bool isFirstOpen = false;

  final ValueNotifier<List<NoteModel>> _notesNotifier = ValueNotifier([]);
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstOpen();
    });
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      
      final offset = _scrollController.offset;
      final direction = _scrollController.position.userScrollDirection;
      
      bool shouldShow;
      
      if (offset < 50) {
        shouldShow = true;
      } else if (direction == ScrollDirection.forward) {
        shouldShow = true;
      } else if (direction == ScrollDirection.reverse) {
        shouldShow = false;
      } else {
        shouldShow = _showAppBar;
      }
      
      if (_showAppBar != shouldShow) {
        setState(() {
          _showAppBar = shouldShow;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _notesNotifier.dispose();
    super.dispose();
  }

  Future<void> _checkFirstOpen() async {
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final alreadyOpened = prefs.getBool('feed_page_opened') ?? false;
        if (!alreadyOpened) {
          if (mounted) {
            setState(() {
              isFirstOpen = true;
            });
          }
          await prefs.setBool('feed_page_opened', true);
        }
      } catch (e) {
        debugPrint('[FeedPage] Error checking first open: $e');
      }
    });
  }

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    if (mounted) {
      setState(() {
        _showAppBar = true;
      });
    }
  }


  Widget _buildHeader(BuildContext context, double topPadding, FeedViewModel viewModel) {
    final colors = context.colors;
    final isHashtagMode = widget.hashtag != null;

    return Container(
      width: double.infinity,
      color: colors.background.withValues(alpha: 0.8),
      padding: EdgeInsets.fromLTRB(16, topPadding + 4, 16, 8),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
                      children: [
                        if (!isHashtagMode)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () => Scaffold.of(context).openDrawer(),
                              child: viewModel.currentUser != null
                                  ? Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colors.avatarPlaceholder,
                                        image: viewModel.currentUser!.profileImage.isNotEmpty == true
                                            ? DecorationImage(
                                                image: CachedNetworkImageProvider(viewModel.currentUser!.profileImage),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: viewModel.currentUser!.profileImage.isEmpty != false
                                          ? Icon(
                                              Icons.person,
                                              size: 20,
                                              color: colors.textSecondary,
                                            )
                                          : null,
                                    )
                                  : Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colors.avatarPlaceholder,
                                      ),
                                      child: CircularProgressIndicator(
                                        color: colors.accent,
                                        strokeWidth: 2,
                                      ),
                                    ),
                            ),
                          ),
                if (isHashtagMode)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BackButtonWidget.floating(),
                  ),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    },
                    child: isHashtagMode
                        ? Text(
                            '#${widget.hashtag}',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : SvgPicture.asset(
                            'assets/main_icon_white.svg',
                            width: 30,
                            height: 30,
                            colorFilter: ColorFilter.mode(colors.textPrimary, BlendMode.srcIn),
                          ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isHashtagMode) ...[
                        GestureDetector(
                          onTap: () => viewModel.toggleSortMode(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            constraints: const BoxConstraints(minHeight: 40),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.buttonPrimary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  viewModel.sortMode == FeedSortMode.mostInteracted ? Icons.trending_up : Icons.access_time,
                                  size: 18,
                                  color: colors.buttonText,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  viewModel.sortMode == FeedSortMode.mostInteracted ? 'Popular' : 'Latest',
                                  style: TextStyle(
                                    color: colors.buttonText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = topPadding + 55;
    final colors = context.colors;
    final isHashtagMode = widget.hashtag != null;

    return ViewModelBuilder<FeedViewModel>(
      create: () => AppDI.get<FeedViewModel>(),
      onModelReady: (viewModel) {
        viewModel.initializeWithUser(widget.npub, hashtag: widget.hashtag);
      },
      builder: (context, viewModel) {
        return Scaffold(
          backgroundColor: colors.background,
          drawer: !isHashtagMode ? const SidebarWidget() : null,
          body: Stack(
            children: [
              UIStateBuilder<List<NoteModel>>(
                state: viewModel.feedState,
                builder: (context, notes) {
                  return RefreshIndicator(
                    onRefresh: viewModel.refreshFeed,
                    child: CustomScrollView(
                      key: const PageStorageKey<String>('feed_scroll'),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      cacheExtent: 600,
                      slivers: [
                        if (!isHashtagMode)
                          SliverPersistentHeader(
                            floating: true,
                            delegate: _PinnedHeaderDelegate(
                              height: headerHeight,
                              child: AnimatedOpacity(
                                opacity: _showAppBar ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                child: _buildHeader(context, topPadding, viewModel),
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: SizedBox(height: isHashtagMode ? topPadding + 85 : 8),
                        ),
                        Builder(
                          builder: (context) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_notesNotifier.value != notes) {
                                _notesNotifier.value = notes;
                              }
                            });

                            return widgets.NoteListWidget(
                              notes: notes,
                              currentUserNpub: viewModel.currentUserNpub,
                              notesNotifier: _notesNotifier,
                              profiles: viewModel.profiles,
                              isLoading: viewModel.isLoadingMore,
                              canLoadMore: viewModel.canLoadMore,
                              onLoadMore: viewModel.loadMoreNotes,
                              scrollController: _scrollController,
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: colors.accent,
                  ),
                ),
                error: (message) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        message,
                        style: TextStyle(color: colors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'Retry',
                        onPressed: () {
                          final viewModel = context.read<FeedViewModel>();
                          viewModel.refreshFeed();
                        },
                      ),
                    ],
                  ),
                ),
                empty: (message) => Center(
                  child: Text(
                    message ?? 'Your feed is empty',
                    style: TextStyle(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (isHashtagMode) ...[
                BackButtonWidget.floating(),
                Positioned(
                  top: topPadding + 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: colors.buttonPrimary,
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: Text(
                          '#${widget.hashtag}',
                          style: TextStyle(
                            color: colors.buttonText,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _PinnedHeaderDelegate({required this.child, required this.height});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: height, child: child);
  }

  @override
  double get maxExtent => height;
  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) => height != oldDelegate.height || child != oldDelegate.child;
}
