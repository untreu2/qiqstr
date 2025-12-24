import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:qiqstr/ui/widgets/note/note_list_widget.dart' as widgets;
import 'package:qiqstr/ui/widgets/common/back_button_widget.dart';
import 'package:qiqstr/ui/widgets/common/sidebar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../theme/theme_manager.dart';
import '../../../models/note_model.dart';
import '../../../core/ui/ui_state_builder.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/providers/viewmodel_provider.dart';
import '../../../presentation/viewmodels/feed_viewmodel.dart';
import '../../../data/services/relay_service.dart';
import '../search/users_search_page.dart';

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
  Timer? _relayCountTimer;
  final ValueNotifier<int> _connectedRelaysCount = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _updateRelayCount();
    _relayCountTimer = Timer.periodic(const Duration(seconds: 2), (_) => _updateRelayCount());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstOpen();
    });
  }

  void _updateRelayCount() {
    if (!mounted) return;
    try {
      final manager = WebSocketManager.instance;
      final count = manager.activeSockets.length;
      if (_connectedRelaysCount.value != count) {
        _connectedRelaysCount.value = count;
      }
    } catch (e) {
      debugPrint('[FeedPage] Error updating relay count: $e');
    }
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
    _relayCountTimer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _notesNotifier.dispose();
    _connectedRelaysCount.dispose();
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

  void _showSearchPopup(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (dialogContext) => UserSearchPage(parentContext: context),
    );
  }

  Widget _buildHeader(BuildContext context, double topPadding, FeedViewModel viewModel) {
    final colors = context.colors;
    final isHashtagMode = widget.hashtag != null;

    return Container(
      width: double.infinity,
      color: colors.background.withValues(alpha: 0.8),
      padding: EdgeInsets.fromLTRB(16, topPadding + 4, 16, 0),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: !isHashtagMode
                ? Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Scaffold.of(context).openDrawer();
                        },
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _showSearchPopup(context);
                          },
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: colors.overlayLight,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  CarbonIcons.search,
                                  size: 18,
                                  color: colors.textPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Search...',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        CarbonIcons.explore,
                        size: 26,
                        color: colors.textPrimary,
                      ),
                    ],
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
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
                          child: SvgPicture.asset(
                            'assets/main_icon_white.svg',
                            width: 30,
                            height: 30,
                            colorFilter: ColorFilter.mode(colors.textPrimary, BlendMode.srcIn),
                          ),
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
          drawer: const SidebarWidget(),
          body: Stack(
            children: [
              UIStateBuilder<List<NoteModel>>(
                state: viewModel.feedState,
                builder: (context, notes) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_notesNotifier.value != notes) {
                      _notesNotifier.value = notes;
                    }
                  });
                  
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
                          child: SizedBox(height: isHashtagMode ? topPadding + 70 : 4),
                        ),
                        widgets.NoteListWidget(
                          notes: notes,
                          currentUserNpub: viewModel.currentUserNpub,
                          notesNotifier: _notesNotifier,
                          profiles: viewModel.profiles,
                          isLoading: viewModel.isLoadingMore,
                          canLoadMore: viewModel.canLoadMore,
                          onLoadMore: viewModel.loadMoreNotes,
                          scrollController: _scrollController,
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
                          color: colors.textPrimary,
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: Text(
                          '#${widget.hashtag}',
                          style: TextStyle(
                            color: colors.background,
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
