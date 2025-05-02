import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/screens/discover_page.dart';
import 'package:qiqstr/screens/users_search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
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

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.Feed);
    _loadUserProfile();
    _checkFirstOpen();
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
      Future.delayed(const Duration(milliseconds: 600), () {
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

  void _navigateToNotificationsPage() async {
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

  Widget _buildInfoSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Scaffold.of(context).openDrawer();
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Feed',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.explore, color: Colors.white, size: 24),
                tooltip: 'Discover',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DiscoverPage(npub: widget.npub),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.person_search,
                    color: Colors.white, size: 24),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserSearchPage()),
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.notifications_none,
                    color: Colors.white, size: 24),
                onPressed: _navigateToNotificationsPage,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "“If you don't believe me or don't get it, I don't have time to try to convince you, sorry.”",
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: SidebarWidget(
        user: user,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(right: 12, bottom: 12),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
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
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  cacheExtent: 1500,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildInfoSection(),
                    ),
                    NoteListWidget(
                      npub: widget.npub,
                      dataType: DataType.Feed,
                    ),
                  ],
                ),
    );
  }
}
