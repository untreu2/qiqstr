import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import '../theme/theme_manager.dart';

class FeedPage extends StatefulWidget {
  final String npub;
  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  UserModel? user;
  late DataService dataService;
  bool isLoading = true;
  bool _isInitializingDataService = true;
  String? errorMessage;
  bool isFirstOpen = false;
  NoteListFilterType _selectedFilterType = NoteListFilterType.latest;

  late ScrollController _scrollController;
  bool _showAppBar = true;

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.feed);
    _scrollController = ScrollController()..addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProgressively();
      _checkFirstOpen();
    });
  }

  Future<void> _initializeProgressively() async {
    try {
      // Phase 1: Load user profile and lightweight DataService init
      await Future.wait([
        _loadUserProfile(),
        dataService.initializeLightweight(),
      ]);

      if (mounted) {
        setState(() {
          _isInitializingDataService = false;
        });
      }

      // Phase 2: Heavy operations in background
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          dataService.initializeHeavyOperations();
        }
      });
    } catch (e) {
      print('[FeedPage] Progressive initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitializingDataService = false;
          errorMessage = 'Failed to initialize feed';
        });
      }
    }
  }

  void _scrollListener() {
    final direction = _scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse) {
      setState(() {
        _showAppBar = false;
      });
    } else if (direction == ScrollDirection.forward) {
      setState(() {
        _showAppBar = true;
      });
    }

    // Infinite scroll support
    dataService.onScrollPositionChanged(
      _scrollController.position.pixels,
      _scrollController.position.maxScrollExtent,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkFirstOpen() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyOpened = prefs.getBool('feed_page_opened') ?? false;
    if (!alreadyOpened) {
      isFirstOpen = true;
      await prefs.setBool('feed_page_opened', true);
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      // Use lightweight profile loading without full DataService initialization
      final profileData = await dataService.getCachedUserProfile(widget.npub);
      if (!mounted) return;
      setState(() {
        user = UserModel.fromCachedProfile(widget.npub, profileData);
      });
    } catch (e) {
      print('[FeedPage] Error loading profile: $e');
      if (mounted) {
        // Create a default user instead of showing error
        setState(() {
          user = UserModel(
            npub: widget.npub,
            name: 'Anonymous',
            about: '',
            nip05: '',
            banner: '',
            profileImage: '',
            lud16: '',
            website: '',
            updatedAt: DateTime.now(),
          );
        });
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildHeaderWithFilters(BuildContext context, double topPadding) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      color: colors.background,
      padding: EdgeInsets.fromLTRB(16, topPadding + 4, 16, 8),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: colors.avatarPlaceholder,
                        backgroundImage: user?.profileImage != null ? CachedNetworkImageProvider(user!.profileImage) : null,
                        child: user?.profileImage == null ? Icon(Icons.person, color: colors.iconPrimary, size: 18) : null,
                      ),
                    ),
                  ),
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
                      color: colors.iconPrimary,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<NoteListFilterType>(
                    icon: Icon(
                      Icons.filter_list,
                      color: colors.iconPrimary,
                      size: 24,
                    ),
                    onSelected: (NoteListFilterType filterType) {
                      setState(() {
                        _selectedFilterType = filterType;
                      });
                    },
                    itemBuilder: (BuildContext context) => [
                      PopupMenuItem<NoteListFilterType>(
                        value: NoteListFilterType.latest,
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: _selectedFilterType == NoteListFilterType.latest ? colors.accent : colors.iconSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Latest',
                              style: TextStyle(
                                color: _selectedFilterType == NoteListFilterType.latest ? colors.accent : colors.textPrimary,
                                fontWeight: _selectedFilterType == NoteListFilterType.latest ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<NoteListFilterType>(
                        value: NoteListFilterType.media,
                        child: Row(
                          children: [
                            Icon(
                              Icons.photo_library,
                              color: _selectedFilterType == NoteListFilterType.media ? colors.accent : colors.iconSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Media',
                              style: TextStyle(
                                color: _selectedFilterType == NoteListFilterType.media ? colors.accent : colors.textPrimary,
                                fontWeight: _selectedFilterType == NoteListFilterType.media ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: colors.borderLight),
                    ),
                    elevation: 8,
                    offset: const Offset(0, 8),
                  ),
                ),
              ],
            ),
          ),
          // Loading indicator
          ValueListenableBuilder<bool>(
            valueListenable: dataService.isRefreshingNotifier,
            builder: (context, isRefreshing, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: isRefreshing ? 3 : 0,
                child: isRefreshing
                    ? LinearProgressIndicator(
                        backgroundColor: colors.borderLight,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                      )
                    : const SizedBox.shrink(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInitializingState(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    context.colors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading feed...',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
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
    final double headerHeight = topPadding + 55; // Simplified header without filter buttons
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      drawer: SidebarWidget(user: user),
      body: isLoading
          ? ColoredBox(color: colors.background)
          : errorMessage != null
              ? Center(
                  child: Text(
                    errorMessage!,
                    style: TextStyle(color: colors.textSecondary),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await dataService.refreshNotes();
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    cacheExtent: 1500,
                    slivers: [
                      SliverPersistentHeader(
                        floating: true,
                        delegate: _PinnedHeaderDelegate(
                          height: headerHeight,
                          child: AnimatedOpacity(
                            opacity: _showAppBar ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: _buildHeaderWithFilters(context, topPadding),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 8),
                      ),
                      _isInitializingDataService
                          ? _buildInitializingState(context)
                          : NoteListWidget(
                              key: ValueKey(_selectedFilterType),
                              npub: widget.npub,
                              dataType: DataType.feed,
                              filterType: _selectedFilterType,
                            ),
                    ],
                  ),
                ),
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
