import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/services/qiqstr_service.dart';

class FeedPage extends StatefulWidget {
  final String npub;
  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage>
    with SingleTickerProviderStateMixin {
  UserModel? user;
  late DataService dataService;
  bool isLoading = true;
  String? errorMessage;

  final ScrollController _scrollController = ScrollController();
  bool _fabVisible = true;

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.Feed);
    _loadUserProfile();

    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection ==
          ScrollDirection.reverse) {
        if (_fabVisible) setState(() => _fabVisible = false);
      } else if (_scrollController.position.userScrollDirection ==
          ScrollDirection.forward) {
        if (!_fabVisible) setState(() => _fabVisible = true);
      }
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      await dataService.initialize();
      final profileData = await dataService.getCachedUserProfile(widget.npub);
      setState(() {
        user = UserModel.fromCachedProfile(widget.npub, profileData);
      });
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred while loading profile.';
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _navigateToShareNotePage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareNotePage(dataService: dataService),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
              tooltip: 'Open menu',
            ),
            const SizedBox(width: 8),
            const Text(
              'Feed',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.only(left: 16),
          child: Text(
            "Here are the notes from people you follow.",
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: SidebarWidget(user: user),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: AnimatedSlide(
        offset: _fabVisible ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: _fabVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          child: Padding(
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
              : NestedScrollView(
                  controller: _scrollController,
                  headerSliverBuilder: (context, innerScrolled) => [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 60, 20, 20),
                        child: _buildInfoSection(context),
                      ),
                    ),
                  ],
                  body: NoteListWidget(
                    npub: widget.npub,
                    dataType: DataType.Feed,
                  ),
                ),
    );
  }
}
