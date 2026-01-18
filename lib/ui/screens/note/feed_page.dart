import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:qiqstr/ui/widgets/note/note_list_widget.dart' as widgets;
import 'package:qiqstr/ui/widgets/common/back_button_widget.dart';
import 'package:qiqstr/ui/widgets/common/sidebar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/feed/feed_bloc.dart';
import '../../../presentation/blocs/feed/feed_event.dart';
import '../../../presentation/blocs/feed/feed_state.dart';
import '../../../data/services/relay_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  final ValueNotifier<List<Map<String, dynamic>>> _notesNotifier = ValueNotifier([]);
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

  Widget _buildHeader(BuildContext context, double topPadding, Map<String, dynamic>? user) {
    final colors = context.colors;
    final isHashtagMode = widget.hashtag != null;
    final userProfileImage = user?['profileImage'] as String? ?? '';

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
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
                        child: user != null
                            ? Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.avatarPlaceholder,
                                  image: userProfileImage.isNotEmpty
                                      ? DecorationImage(
                                          image: CachedNetworkImageProvider(userProfileImage),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: userProfileImage.isEmpty
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
                      GestureDetector(
                        onTap: () {
                          final currentLocation = GoRouterState.of(context).matchedLocation;
                          if (currentLocation.startsWith('/home/feed')) {
                            context.push('/home/feed/explore');
                          } else if (currentLocation.startsWith('/home/notifications')) {
                            context.push('/home/notifications/explore');
                          } else if (currentLocation.startsWith('/home/dm')) {
                            context.push('/home/dm/explore');
                          } else {
                            context.push('/explore');
                          }
                        },
                        child: Icon(
                          CarbonIcons.explore,
                          size: 26,
                          color: colors.textPrimary,
                        ),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = topPadding + 55;
    final colors = context.colors;
    final isHashtagMode = widget.hashtag != null;

    return BlocProvider<FeedBloc>(
      create: (context) {
        final bloc = AppDI.get<FeedBloc>();
        bloc.add(FeedInitialized(npub: widget.npub, hashtag: widget.hashtag));
        return bloc;
      },
      child: BlocBuilder<FeedBloc, FeedState>(
        builder: (context, feedState) {
          return Scaffold(
            backgroundColor: colors.background,
            drawer: const SidebarWidget(),
            body: Stack(
              children: [
                _buildFeedContent(context, feedState, topPadding, headerHeight, isHashtagMode, colors),
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
      ),
    );
  }

  Widget _buildFeedContent(
    BuildContext context,
    FeedState feedState,
    double topPadding,
    double headerHeight,
    bool isHashtagMode,
    AppThemeColors colors,
  ) {
    return switch (feedState) {
      FeedInitial() => Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
      FeedLoading() => Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
      FeedLoaded(:final notes, :final profiles, :final currentUserNpub, :final isLoadingMore, :final canLoadMore) => Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_notesNotifier.value != notes) {
                _notesNotifier.value = notes;
              }
            });

            final user = profiles[currentUserNpub];

            return RefreshIndicator(
              onRefresh: () async {
                context.read<FeedBloc>().add(const FeedRefreshed());
              },
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
                          child: _buildHeader(context, topPadding, user),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: isHashtagMode ? topPadding + 70 : 4),
                  ),
                  widgets.NoteListWidget(
                    notes: notes,
                    currentUserNpub: currentUserNpub,
                    notesNotifier: _notesNotifier,
                    profiles: profiles,
                    isLoading: isLoadingMore,
                    canLoadMore: canLoadMore,
                    onLoadMore: () {
                      context.read<FeedBloc>().add(const FeedLoadMoreRequested());
                    },
                    onEmptyRefresh: () {
                      context.read<FeedBloc>().add(const FeedRefreshed());
                    },
                    scrollController: _scrollController,
                  ),
                ],
              ),
            );
          },
        ),
      FeedError(:final message) => Center(
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
                  context.read<FeedBloc>().add(const FeedRefreshed());
                },
              ),
            ],
          ),
        ),
      FeedEmpty() => Center(
          child: Text(
            'Your feed is empty',
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
