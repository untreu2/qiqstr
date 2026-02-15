import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:qiqstr/ui/widgets/note/note_list_widget.dart' as widgets;
import 'package:qiqstr/ui/widgets/note/note_widget.dart';
import 'package:qiqstr/ui/widgets/common/back_button_widget.dart';
import 'package:qiqstr/ui/widgets/common/sidebar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../presentation/blocs/feed/feed_bloc.dart';
import '../../../presentation/blocs/feed/feed_event.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/feed/feed_state.dart';
import '../../../data/services/relay_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../presentation/blocs/user_search/user_search_bloc.dart';
import '../../../presentation/blocs/user_search/user_search_event.dart';
import '../../../presentation/blocs/user_search/user_search_state.dart';
import '../../../presentation/blocs/user_tile/user_tile_bloc.dart';
import '../../../presentation/blocs/user_tile/user_tile_event.dart';
import '../../../presentation/blocs/user_tile/user_tile_state.dart';
import '../../widgets/common/custom_input_field.dart';
import 'package:flutter/services.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../widgets/dialogs/unfollow_user_dialog.dart';
import '../../../data/services/favorite_lists_service.dart';
import '../../../data/services/follow_set_service.dart';

class FeedPage extends StatefulWidget {
  final String userHex;
  final String? hashtag;
  const FeedPage({super.key, required this.userHex, this.hashtag});

  @override
  FeedPageState createState() => FeedPageState();
}

class FeedPageState extends State<FeedPage> {
  late ScrollController _scrollController;
  late final FeedBloc _feedBloc;
  late final bool _isLocalBloc;
  bool _showAppBar = true;
  bool isFirstOpen = false;
  bool _isSearchMode = false;
  bool _scrollToTopOnNextBuild = false;
  double _lastScrollOffset = 0;

  final ValueNotifier<List<Map<String, dynamic>>> _notesNotifier =
      ValueNotifier([]);
  Timer? _relayCountTimer;
  Timer? _searchDebounceTimer;
  final ValueNotifier<int> _connectedRelaysCount = ValueNotifier(0);
  int _totalRelays = 0;
  int _connectedRelays = 0;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  UserSearchBloc? _searchBloc;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Map<String, dynamic>? _loggedInUserProfile;
  List<_FavoriteListInfo> _favoriteLists = [];
  String? _activeListId;
  Offset? _swipeStartPosition;
  final ScrollController _listSelectorController = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _searchController
        .addListener(() => _onSearchChanged(_searchController.text));

    if (widget.hashtag != null) {
      _feedBloc = FeedBloc(
        feedRepository: AppDI.get<FeedRepository>(),
        profileRepository: AppDI.get<ProfileRepository>(),
        syncService: AppDI.get<SyncService>(),
      );
      _isLocalBloc = true;
    } else {
      _feedBloc = AppDI.get<FeedBloc>();
      _isLocalBloc = false;
    }
    _feedBloc.add(
        FeedInitialized(userHex: widget.userHex, hashtag: widget.hashtag));

    _updateRelayCount();
    _relayCountTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateRelayCount());
    _loadLoggedInUserProfile();
    _loadFavoriteLists();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstOpen();
    });
  }

  Future<void> _loadLoggedInUserProfile() async {
    final authService = AppDI.get<AuthService>();
    final hex = authService.currentUserPubkeyHex;
    if (hex == null || hex.isEmpty) return;
    final profileRepo = AppDI.get<ProfileRepository>();
    final profile = await profileRepo.getProfile(hex);
    if (profile != null && mounted) {
      setState(() {
        _loggedInUserProfile = profile.toMap();
      });
    }
  }

  void _loadFavoriteLists() {
    _refreshFavoriteLists();
    setState(() {});
  }

  void _refreshFavoriteLists() {
    final favService = FavoriteListsService.instance;
    final setService = FollowSetService.instance;
    final ids = favService.favoriteIds;
    final lists = <_FavoriteListInfo>[];
    for (final id in ids) {
      final followSet = setService.getByListId(id);
      if (followSet != null) {
        lists.add(_FavoriteListInfo(
          listId: id,
          title: followSet.title.isNotEmpty ? followSet.title : followSet.dTag,
          pubkeys: followSet.pubkeys,
        ));
      }
    }
    _favoriteLists = lists;
  }

  void _onListSelected(String? listId, List<String>? pubkeys, String? title) {
    final feedBloc = AppDI.get<FeedBloc>();
    if (listId == null) {
      feedBloc.add(const FeedListChanged());
      setState(() => _activeListId = null);
    } else {
      feedBloc.add(FeedListChanged(
        pubkeys: pubkeys,
        listId: listId,
        listTitle: title,
      ));
      setState(() => _activeListId = listId);
    }
    _scrollToActiveTab(listId ?? '_all');
  }

  void _scrollToActiveTab(String tabId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _tabKeys[tabId];
      if (key == null || key.currentContext == null) return;
      if (!_listSelectorController.hasClients) return;

      final renderBox = key.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final scrollRenderBox = _listSelectorController
          .position.context.storageContext
          .findRenderObject() as RenderBox?;
      if (scrollRenderBox == null) return;

      final tabOffset =
          renderBox.localToGlobal(Offset.zero, ancestor: scrollRenderBox);
      final tabWidth = renderBox.size.width;
      final viewportWidth = _listSelectorController.position.viewportDimension;
      final currentScroll = _listSelectorController.offset;

      final tabLeft = tabOffset.dx + currentScroll;
      final tabCenter = tabLeft + tabWidth / 2;
      final targetScroll = (tabCenter - viewportWidth / 2).clamp(
        _listSelectorController.position.minScrollExtent,
        _listSelectorController.position.maxScrollExtent,
      );

      _listSelectorController.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleSwipe(Offset delta) {
    if (_favoriteLists.isEmpty) return;

    final dx = delta.dx;
    final dy = delta.dy;
    if (dx.abs() < 80 || dx.abs() < dy.abs() * 1.5) return;

    final totalPages = 1 + _favoriteLists.length;
    final currentIndex = _activeListId == null
        ? 0
        : _favoriteLists.indexWhere((l) => l.listId == _activeListId) + 1;

    if (dx < 0 && currentIndex < totalPages - 1) {
      final next = currentIndex + 1;
      final list = _favoriteLists[next - 1];
      _onListSelected(list.listId, list.pubkeys, list.title);
    } else if (dx > 0 && currentIndex > 0) {
      final prev = currentIndex - 1;
      if (prev == 0) {
        _onListSelected(null, null, null);
      } else {
        final list = _favoriteLists[prev - 1];
        _onListSelected(list.listId, list.pubkeys, list.title);
      }
    }
  }

  void _updateRelayCount() async {
    if (!mounted) return;
    try {
      final status = await RustRelayService.instance.getRelayStatus();
      if (!mounted) return;
      final summary = status['summary'] as Map<String, dynamic>? ?? {};
      final total = summary['totalRelays'] as int? ?? 0;
      final connected = summary['connectedRelays'] as int? ?? 0;
      if (mounted) {
        setState(() {
          _totalRelays = total;
          _connectedRelays = connected;
        });
        if (_connectedRelaysCount.value != connected) {
          _connectedRelaysCount.value = connected;
        }
      }
    } catch (e) {
      debugPrint('[FeedPage] Error updating relay count: $e');
    }
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    bool shouldShow;
    if (offset < 50) {
      shouldShow = true;
    } else if (delta < -2) {
      shouldShow = true;
    } else if (delta > 2) {
      shouldShow = false;
    } else {
      return;
    }

    if (_showAppBar != shouldShow) {
      _showAppBar = shouldShow;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _relayCountTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _listSelectorController.dispose();
    _notesNotifier.dispose();
    _connectedRelaysCount.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    if (_isLocalBloc) {
      _feedBloc.close();
    }
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

  void _enterSearchMode() {
    setState(() {
      _isSearchMode = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _exitSearchMode() {
    setState(() {
      _isSearchMode = false;
      _searchController.clear();
    });
    _searchFocusNode.unfocus();
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _searchBloc == null) return;
      _searchBloc!.add(UserSearchQueryChanged(query));
    });
  }

  Widget _buildHeader(
      BuildContext context, double topPadding, Map<String, dynamic>? user) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final isHashtagMode = widget.hashtag != null;
    final userProfileImage = user?['profileImage'] as String? ?? '';

    if (_isSearchMode) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            width: double.infinity,
            color: colors.background.withValues(alpha: 0.95),
            padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _exitSearchMode,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.overlayLight,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomInputField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        autofocus: true,
                        hintText: l10n.searchByNameOrNpub,
                        height: 48,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 0),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () async {
                        final clipboardData =
                            await Clipboard.getData('text/plain');
                        if (clipboardData != null &&
                            clipboardData.text != null) {
                          _searchController.text = clipboardData.text!;
                          _onSearchChanged(clipboardData.text!);
                        }
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.overlayLight,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.content_paste,
                          size: 20,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: double.infinity,
          color: colors.background.withValues(alpha: 0.8),
          padding: EdgeInsets.fromLTRB(16, topPadding + 4, 0, 0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  height: 40,
                  child: !isHashtagMode
                      ? Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                _scaffoldKey.currentState?.openDrawer();
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
                                                image:
                                                    CachedNetworkImageProvider(
                                                        userProfileImage),
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
                                onTap: _enterSearchMode,
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: colors.overlayLight,
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CarbonIcons.search,
                                        size: 18,
                                        color: colors.textPrimary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.searchDotDotDot,
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
                                context.push('/relays');
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CarbonIcons.network_3,
                                    size: 15,
                                    color: colors.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$_connectedRelays/$_totalRelays',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
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
                                  colorFilter: ColorFilter.mode(
                                      colors.textPrimary, BlendMode.srcIn),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (!_isSearchMode && !isHashtagMode && _favoriteLists.isNotEmpty)
                _buildListSelector(colors),
            ],
          ),
        ),
      ),
    );
  }

  GlobalKey _getTabKey(String id) {
    return _tabKeys.putIfAbsent(id, () => GlobalKey());
  }

  Widget _buildListSelector(AppThemeColors colors) {
    final tabs = <Widget>[
      _buildListTab(
        key: _getTabKey('_all'),
        colors: colors,
        label: AppLocalizations.of(context)!.all,
        isSelected: _activeListId == null,
        onTap: () => _onListSelected(null, null, null),
      ),
      ..._favoriteLists.map((list) => _buildListTab(
            key: _getTabKey(list.listId),
            colors: colors,
            label: list.title,
            isSelected: _activeListId == list.listId,
            onTap: () => _onListSelected(list.listId, list.pubkeys, list.title),
          )),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: SingleChildScrollView(
          controller: _listSelectorController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...tabs.expand((tab) => [tab, const SizedBox(width: 24)]).toList()
                ..removeLast(),
              const SizedBox(width: 24),
              _buildListTab(
                colors: colors,
                label: AppLocalizations.of(context)!.addAnotherFeed,
                isSelected: false,
                onTap: () => context.push('/follow-sets'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTab({
    GlobalKey? key,
    required AppThemeColors colors,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final displayLabel =
        label.length > 20 ? '${label.substring(0, 20)}...' : label;
    return GestureDetector(
      key: key,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              displayLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? colors.textPrimary : colors.textSecondary,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: isSelected ? 2 : 0,
              decoration: BoxDecoration(
                color: colors.textPrimary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    _refreshFavoriteLists();
    final bool hasListSelector =
        !_isSearchMode && widget.hashtag == null && _favoriteLists.isNotEmpty;
    final double headerHeight = _isSearchMode
        ? topPadding + 72
        : topPadding + 55 + (hasListSelector ? 36 : 0);
    final colors = context.colors;
    final isHashtagMode = widget.hashtag != null;

    return MultiBlocProvider(
      providers: [
        BlocProvider<FeedBloc>.value(
          value: _feedBloc,
        ),
        BlocProvider<UserSearchBloc>(
          create: (context) {
            final bloc = AppDI.get<UserSearchBloc>();
            _searchBloc = bloc;
            return bloc;
          },
        ),
      ],
      child: BlocBuilder<FeedBloc, FeedState>(
        builder: (context, feedState) {
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: colors.background,
            drawer: const SidebarWidget(),
            body: Stack(
              children: [
                _buildFeedContent(context, feedState, topPadding, headerHeight,
                    isHashtagMode, colors),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
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
                if (feedState is FeedLoaded &&
                    feedState.pendingNotesCount > 0 &&
                    !_isSearchMode)
                  _buildNewNotesButton(
                    context,
                    feedState.pendingNotesCount,
                    colors,
                  ),
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
      FeedLoaded(
        :final notes,
        :final profiles,
        :final currentUserHex,
        :final isLoadingMore,
        :final canLoadMore,
        :final isSyncing
      ) =>
        Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_notesNotifier.value != notes) {
                _notesNotifier.value = notes;
              }
              if (_scrollToTopOnNextBuild) {
                _scrollToTopOnNextBuild = false;
                if (_scrollController.hasClients) {
                  _scrollController.jumpTo(0);
                }
                if (mounted) {
                  setState(() {
                    _showAppBar = true;
                  });
                }
              }
            });

            final user = _loggedInUserProfile ?? profiles[currentUserHex];

            return Listener(
              onPointerDown: (event) {
                _swipeStartPosition = event.position;
              },
              onPointerUp: (event) {
                if (_swipeStartPosition != null) {
                  final delta = event.position - _swipeStartPosition!;
                  _swipeStartPosition = null;
                  _handleSwipe(delta);
                }
              },
              child: RefreshIndicator(
                onRefresh: () async {
                  context.read<FeedBloc>().add(const FeedRefreshed());
                },
                child: CustomScrollView(
                  key: const PageStorageKey<String>('feed_scroll'),
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
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
                      child:
                          SizedBox(height: isHashtagMode ? topPadding + 70 : 4),
                    ),
                    if (_isSearchMode)
                      _buildUserSearchResults(context)
                    else if (notes.isEmpty && isSyncing)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Loading your feed...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      widgets.NoteListWidget(
                        notes: notes,
                        currentUserHex: currentUserHex,
                        notesNotifier: _notesNotifier,
                        profiles: profiles,
                        isLoading: isLoadingMore,
                        canLoadMore: canLoadMore,
                        onLoadMore: () {
                          context
                              .read<FeedBloc>()
                              .add(const FeedLoadMoreRequested());
                        },
                        onEmptyRefresh: () {
                          context.read<FeedBloc>().add(const FeedRefreshed());
                        },
                        scrollController: _scrollController,
                      ),
                  ],
                ),
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
              Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context)!;
                  return PrimaryButton(
                    label: l10n.retryText,
                    onPressed: () {
                      context.read<FeedBloc>().add(const FeedRefreshed());
                    },
                  );
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

  Widget _buildNewNotesButton(
    BuildContext context,
    int count,
    AppThemeColors colors,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double bottom = bottomPadding + 16;
    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            _scrollToTopOnNextBuild = true;
            context.read<FeedBloc>().add(const FeedNewNotesAccepted());
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_upward_rounded,
                        size: 16,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.newNotesAvailable(count),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserSearchResults(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<UserSearchBloc, UserSearchState>(
      builder: (context, searchState) {
        return switch (searchState) {
          UserSearchLoading() => SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: context.colors.primary),
                      const SizedBox(height: 16),
                      Text(
                        l10n.searchingForUsers,
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          UserSearchError(:final message) => SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: context.colors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.searchError,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: TextStyle(color: context.colors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (context) {
                          final l10n = AppLocalizations.of(context)!;
                          return PrimaryButton(
                            label: l10n.retryText,
                            onPressed: () {
                              context.read<UserSearchBloc>().add(
                                  UserSearchQueryChanged(
                                      _searchController.text.trim()));
                            },
                            backgroundColor: context.colors.accent,
                            foregroundColor: context.colors.background,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          UserSearchLoaded(
            :final filteredUsers,
            :final filteredNotes,
            :final noteProfiles,
            :final isSearching,
          ) =>
            isSearching
                ? SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                                color: context.colors.primary),
                            const SizedBox(height: 16),
                            Text(
                              l10n.searchingDotDotDot,
                              style: TextStyle(
                                  color: context.colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : (filteredUsers.isEmpty && filteredNotes.isEmpty) &&
                        _searchController.text.trim().isNotEmpty
                    ? SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 48,
                                  color: context.colors.textSecondary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No results found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: context.colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try searching with a different term.',
                                  style: TextStyle(
                                      color: context.colors.textSecondary),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : (filteredUsers.isNotEmpty || filteredNotes.isNotEmpty)
                        ? _buildSearchResultsList(
                            context, filteredUsers, filteredNotes, noteProfiles)
                        : const SliverToBoxAdapter(child: SizedBox()),
          _ => const SliverToBoxAdapter(child: SizedBox()),
        };
      },
    );
  }

  Widget _buildSearchResultsList(
    BuildContext context,
    List<Map<String, dynamic>> users,
    List<Map<String, dynamic>> notes,
    Map<String, Map<String, dynamic>> noteProfiles,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final items = <_SearchResultItem>[];

    if (users.isNotEmpty) {
      items.add(_SearchResultItem(
          type: _SearchResultType.header, data: {'title': l10n.users}));
      for (final user in users) {
        items.add(_SearchResultItem(type: _SearchResultType.user, data: user));
      }
    }

    if (notes.isNotEmpty) {
      items.add(_SearchResultItem(
          type: _SearchResultType.header, data: {'title': l10n.notes}));
      for (final note in notes) {
        items.add(_SearchResultItem(
            type: _SearchResultType.note, data: note, profiles: noteProfiles));
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];

          switch (item.type) {
            case _SearchResultType.header:
              final isFirst = index == 0;
              return Padding(
                padding: EdgeInsets.fromLTRB(16, isFirst ? 4 : 16, 16, 8),
                child: Text(
                  item.data['title'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              );
            case _SearchResultType.user:
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FeedUserItemWidget(user: item.data),
                  const _FeedUserSeparator(),
                ],
              );
            case _SearchResultType.note:
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SearchNoteItemWidget(
                    note: item.data,
                    profiles: item.profiles ?? {},
                    currentUserHex: widget.userHex,
                  ),
                  const _FeedUserSeparator(),
                ],
              );
          }
        },
        childCount: items.length,
      ),
    );
  }
}

enum _SearchResultType { header, user, note }

class _SearchResultItem {
  final _SearchResultType type;
  final Map<String, dynamic> data;
  final Map<String, Map<String, dynamic>>? profiles;

  _SearchResultItem({
    required this.type,
    required this.data,
    this.profiles,
  });
}

class _SearchNoteItemWidget extends StatefulWidget {
  final Map<String, dynamic> note;
  final Map<String, Map<String, dynamic>> profiles;
  final String currentUserHex;

  const _SearchNoteItemWidget({
    required this.note,
    required this.profiles,
    required this.currentUserHex,
  });

  @override
  State<_SearchNoteItemWidget> createState() => _SearchNoteItemWidgetState();
}

class _SearchNoteItemWidgetState extends State<_SearchNoteItemWidget> {
  late final ValueNotifier<List<Map<String, dynamic>>> _notesNotifier;

  @override
  void initState() {
    super.initState();
    _notesNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  }

  @override
  void dispose() {
    _notesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NoteWidget(
      note: widget.note,
      currentUserHex: widget.currentUserHex,
      notesNotifier: _notesNotifier,
      profiles: widget.profiles,
      containerColor: Colors.transparent,
      isSmallView: true,
      isVisible: true,
    );
  }
}

class _FeedUserItemWidget extends StatefulWidget {
  final Map<String, dynamic> user;

  const _FeedUserItemWidget({required this.user});

  @override
  State<_FeedUserItemWidget> createState() => _FeedUserItemWidgetState();
}

class _FeedUserItemWidgetState extends State<_FeedUserItemWidget> {
  String? _currentUserHex;
  Map<String, dynamic>? _loadedProfile;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserHex();
    _loadAndSyncProfile();
  }

  Future<void> _loadCurrentUserHex() async {
    final authService = AppDI.get<AuthService>();
    final hex = authService.currentUserPubkeyHex;
    if (mounted) {
      setState(() {
        _currentUserHex = hex;
      });
    }
  }

  String get _displayName {
    final loaded = _loadedProfile?['name'] as String? ?? '';
    if (loaded.isNotEmpty) return loaded;
    return widget.user['name'] as String? ?? '';
  }

  String get _displayImage {
    final loaded = _loadedProfile?['profileImage'] as String? ?? '';
    if (loaded.isNotEmpty) return loaded;
    return widget.user['profileImage'] as String? ?? '';
  }

  Future<void> _loadAndSyncProfile() async {
    if (!mounted) return;
    final pubkey = widget.user['pubkeyHex'] as String? ??
        widget.user['pubkey'] as String? ??
        '';
    if (pubkey.isEmpty) return;

    final profileRepo = AppDI.get<ProfileRepository>();
    final profile = await profileRepo.getProfile(pubkey);

    if (profile != null && mounted) {
      setState(() {
        _loadedProfile = {
          'pubkeyHex': profile.pubkey,
          'name': profile.name ?? '',
          'profileImage': profile.picture ?? '',
          'about': profile.about ?? '',
          'banner': profile.banner ?? '',
          'nip05': profile.nip05 ?? '',
          'lud16': profile.lud16 ?? '',
          'website': profile.website ?? '',
        };
      });
    }

    final hasName = (profile?.name ?? '').isNotEmpty;
    final hasImage = (profile?.picture ?? '').isNotEmpty;

    if (!hasName || !hasImage) {
      final syncService = AppDI.get<SyncService>();
      try {
        await syncService.syncProfile(pubkey);
        if (!mounted) return;
        final synced = await profileRepo.getProfile(pubkey);
        if (synced != null && mounted) {
          setState(() {
            _loadedProfile = {
              'pubkeyHex': synced.pubkey,
              'name': synced.name ?? '',
              'profileImage': synced.picture ?? '',
              'about': synced.about ?? '',
              'banner': synced.banner ?? '',
              'nip05': synced.nip05 ?? '',
              'lud16': synced.lud16 ?? '',
              'website': synced.website ?? '',
            };
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _toggleFollow(UserTileBloc bloc, UserTileLoaded state) async {
    if (state.isFollowing == true) {
      final userName = (widget.user['name'] as String? ?? '').isNotEmpty
          ? widget.user['name'] as String
          : ((widget.user['nip05'] as String? ?? '').isNotEmpty
              ? (widget.user['nip05'] as String).split('@').first
              : 'this user');

      showUnfollowUserDialog(
        context: context,
        userName: userName,
        onConfirm: () {
          bloc.add(const UserTileFollowToggled());
        },
      );
      return;
    }

    bloc.add(const UserTileFollowToggled());
  }

  Widget _buildFollowButton(
      BuildContext context, UserTileLoaded state, UserTileBloc bloc) {
    final l10n = AppLocalizations.of(context)!;
    final isFollowing = state.isFollowing ?? false;
    return GestureDetector(
      onTap: state.isLoading ? null : () => _toggleFollow(bloc, state),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isFollowing
              ? context.colors.overlayLight
              : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: state.isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isFollowing
                        ? context.colors.textPrimary
                        : context.colors.background,
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFollowing
                        ? CarbonIcons.user_admin
                        : CarbonIcons.user_follow,
                    size: 16,
                    color: isFollowing
                        ? context.colors.textPrimary
                        : context.colors.background,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isFollowing ? l10n.following : l10n.follow,
                    style: TextStyle(
                      color: isFollowing
                          ? context.colors.textPrimary
                          : context.colors.background,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<UserTileBloc>(
      create: (context) {
        final userNpub = widget.user['npub'] as String? ?? '';
        final bloc = UserTileBloc(
          followingRepository: AppDI.get<FollowingRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
          userNpub: userNpub,
        );
        if (userNpub.isNotEmpty) {
          bloc.add(UserTileInitialized(userNpub: userNpub));
        }
        return bloc;
      },
      child: BlocBuilder<UserTileBloc, UserTileState>(
        builder: (context, state) {
          final userPubkeyHex = widget.user['pubkeyHex'] as String? ??
              widget.user['pubkey'] as String? ??
              '';
          final isCurrentUser =
              _currentUserHex != null && _currentUserHex == userPubkeyHex;
          final loadedState =
              state is UserTileLoaded ? state : const UserTileLoaded();

          return GestureDetector(
            onTap: () {
              final currentLocation = GoRouterState.of(context).matchedLocation;

              if (currentLocation.startsWith('/home/feed')) {
                context.push(
                    '/home/feed/profile?pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
              } else if (currentLocation.startsWith('/home/notifications')) {
                context.push(
                    '/home/notifications/profile?pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
              } else {
                context.push(
                    '/profile?pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _buildAvatar(context, _displayImage),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  () {
                                    final name = _displayName;
                                    return name.length > 25
                                        ? '${name.substring(0, 25)}...'
                                        : name;
                                  }(),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: context.colors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isCurrentUser && loadedState.isFollowing != null) ...[
                    const SizedBox(width: 10),
                    _buildFollowButton(
                        context, loadedState, context.read<UserTileBloc>()),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, String imageUrl) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey.shade800,
        child: Icon(
          Icons.person,
          size: 26,
          color: context.colors.textSecondary,
        ),
      );
    }

    return ClipOval(
      child: Container(
        width: 48,
        height: 48,
        color: Colors.transparent,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          memCacheWidth: 192,
          placeholder: (context, url) => Container(
            color: Colors.grey.shade800,
            child: Icon(
              Icons.person,
              size: 26,
              color: context.colors.textSecondary,
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade800,
            child: Icon(
              Icons.person,
              size: 26,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedUserSeparator extends StatelessWidget {
  const _FeedUserSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: Center(
        child: Container(
          height: 0.5,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

class _FavoriteListInfo {
  final String listId;
  final String title;
  final List<String> pubkeys;

  const _FavoriteListInfo({
    required this.listId,
    required this.title,
    required this.pubkeys,
  });
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _PinnedHeaderDelegate({required this.child, required this.height});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: height, child: child);
  }

  @override
  double get maxExtent => height;
  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}
