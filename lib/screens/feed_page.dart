import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/screens/notifications_page.dart';

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
  bool _showFAB = true;

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.Feed);
    _loadUserProfile();
    _checkFirstOpen();

    _scrollController = ScrollController();
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection ==
          ScrollDirection.reverse) {
        if (_showAppBar || _showFAB) {
          setState(() {
            _showAppBar = false;
            _showFAB = false;
          });
        }
      } else if (_scrollController.position.userScrollDirection ==
          ScrollDirection.forward) {
        if (!_showAppBar || !_showFAB) {
          setState(() {
            _showAppBar = true;
            _showFAB = true;
          });
        }
      }
    });
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
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() {});
      });
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted) setState(() {});
      });
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      await dataService.initialize();
      final profileData = await dataService.getCachedUserProfile(widget.npub);
      if (mounted) {
        setState(() {
          user = UserModel.fromCachedProfile(widget.npub, profileData);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'An error occurred while loading profile.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _navigateToShareNotePage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareNotePage(dataService: dataService),
      ),
    );
  }

  void _navigateToNotificationsPage() {
    final box = dataService.notificationsBox!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationsPage(
          npub: widget.npub,
          notificationsBox: box,
          dataService: dataService,
        ),
      ),
    );
  }

  SliverPersistentHeader _buildAnimatedHeader() {
    return SliverPersistentHeader(
      floating: true,
      delegate: _PinnedHeaderDelegate(
        child: AnimatedOpacity(
          opacity: _showAppBar ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.black.withOpacity(0.5),
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + 4,
                  16,
                  8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu,
                            color: Colors.white, size: 24),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Image.asset(
                        'assets/main_icon.png',
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.notifications_none,
                          color: Colors.white, size: 24),
                      onPressed: _navigateToNotificationsPage,
                    ),
                  ],
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
      floatingActionButton: AnimatedSlide(
        offset: _showFAB ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
        child: AnimatedOpacity(
          opacity: _showFAB ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 12),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _navigateToShareNotePage,
                    icon: SvgPicture.asset(
                      'assets/new_post_button.svg',
                      color: Colors.white,
                      width: 24,
                      height: 24,
                    ),
                    tooltip: 'New Note',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
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
                    _buildAnimatedHeader(),
                    NoteListWidget(
                      npub: widget.npub,
                      dataType: DataType.Feed,
                    ),
                  ],
                ),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _PinnedHeaderDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent => 125;

  @override
  double get minExtent => 125;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}
