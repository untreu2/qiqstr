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
      _loadUserProfile();
      _checkFirstOpen();
    });
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
      await dataService.initialize();
      final profileData = await dataService.getCachedUserProfile(widget.npub);
      if (!mounted) return;
      setState(() {
        user = UserModel.fromCachedProfile(widget.npub, profileData);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          errorMessage = 'An error occurred while loading profile.';
        });
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }


  Widget _buildHeaderWithFilters(BuildContext context, double topPadding) {
    final colors = context.colors;
    
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          color: colors.backgroundTransparent,
          padding: EdgeInsets.fromLTRB(16, topPadding + 4, 16, 0),
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
                            backgroundImage:
                                user?.profileImage != null ? CachedNetworkImageProvider(user!.profileImage) : null,
                            child: user?.profileImage == null
                                ? Icon(Icons.person, color: colors.iconPrimary, size: 18)
                                : null,
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
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildFilterButton(context, NoteListFilterType.latest, "Latest"),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildFilterButton(context, NoteListFilterType.popular, "Popular"),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildFilterButton(context, NoteListFilterType.media, "Media"),
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

  Widget _buildFilterButton(BuildContext context, NoteListFilterType filterType, String label) {
    final bool isSelected = _selectedFilterType == filterType;
    final colors = context.colors;
    
    return TextButton(
      onPressed: () {
        if (_selectedFilterType != filterType) {
          setState(() {
            _selectedFilterType = filterType;
          });
        }
      },
      style: TextButton.styleFrom(
        backgroundColor: colors.surfaceTransparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? colors.accent : colors.borderAccent,
            width: 1.0,
          ),
        ),
        foregroundColor: isSelected ? colors.textPrimary : colors.textSecondary,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = topPadding + 108;
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
              : CustomScrollView(
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
                    NoteListWidget(
                      npub: widget.npub,
                      dataType: DataType.feed,
                      filterType: _selectedFilterType,
                    ),
                  ],
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
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}
