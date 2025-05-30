import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:qiqstr/services/data_service.dart';

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

  late ScrollController _scrollController;
  bool _showAppBar = true;
  double _fabOpacity = 1.0;

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
    if (direction == ScrollDirection.reverse && _fabOpacity != 0.3) {
      setState(() {
        _fabOpacity = 0.6;
        _showAppBar = false;
      });
    } else if (direction == ScrollDirection.forward && _fabOpacity != 1.0) {
      setState(() {
        _fabOpacity = 1.0;
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

  void _navigateToShareNotePage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareNotePage(dataService: dataService),
      ),
    );
  }

  SliverPersistentHeader _buildAnimatedHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double calculatedHeight = topPadding + 40 + 8;

    return SliverPersistentHeader(
      floating: true,
      delegate: _PinnedHeaderDelegate(
        height: calculatedHeight,
        child: AnimatedOpacity(
          opacity: _showAppBar ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.black.withOpacity(0.5),
                padding: EdgeInsets.fromLTRB(16, topPadding + 4, 16, 8),
                child: SizedBox(
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
                              backgroundColor: Colors.white24,
                              backgroundImage: user?.profileImage != null
                                  ? CachedNetworkImageProvider(
                                      user!.profileImage)
                                  : null,
                              child: user?.profileImage == null
                                  ? const Icon(Icons.person,
                                      color: Colors.white, size: 18)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
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
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn), 
                          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: SidebarWidget(user: user),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: AnimatedOpacity(
        opacity: _fabOpacity,
        duration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 80.0, right: 5.0),
          child: GestureDetector(
            onTap: _navigateToShareNotePage,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFECB200).withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    
                    child: Icon(CarbonIcons.add, size: 28, color: Colors.white), 
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const ColoredBox(color: Colors.black)
          : errorMessage != null
              ? Center(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              : CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  cacheExtent: 1500,
                  slivers: [
                    _buildAnimatedHeader(context),
                    NoteListWidget(
                      npub: widget.npub,
                      dataType: DataType.feed,
                    ),
                  ],
                ),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _PinnedHeaderDelegate({
    required this.child,
    required this.height,
  });

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
