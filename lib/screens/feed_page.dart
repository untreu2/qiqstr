import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/services/data_service_manager.dart';
import 'package:qiqstr/providers/user_provider.dart';
import '../theme/theme_manager.dart';

class FeedPage extends StatefulWidget {
  final String npub;
  final DataService? dataService;
  const FeedPage({Key? key, required this.npub, this.dataService}) : super(key: key);

  @override
  FeedPageState createState() => FeedPageState();
}

class FeedPageState extends State<FeedPage> {
  late DataService dataService;
  bool isLoading = true;
  String? errorMessage;
  bool isFirstOpen = false;

  late ScrollController _scrollController;
  bool _showAppBar = true;
  NoteViewMode _currentViewMode = NoteViewMode.text;

  @override
  void initState() {
    super.initState();

    dataService = widget.dataService ??
        DataServiceManager.instance.getOrCreateService(
          npub: widget.npub,
          dataType: DataType.feed,
          onNewNote: (_) {
            if (mounted) setState(() {});
          },
          onReactionsUpdated: (_, __) {
            if (mounted) setState(() {});
          },
          onRepliesUpdated: (_, __) {
            if (mounted) setState(() {});
          },
          onRepostsUpdated: (_, __) {
            if (mounted) setState(() {});
          },
          onReactionCountUpdated: (_, __) {
            if (mounted) setState(() {});
          },
          onReplyCountUpdated: (_, __) {
            if (mounted) setState(() {});
          },
          onRepostCountUpdated: (_, __) {
            if (mounted) setState(() {});
          },
        );
    _scrollController = ScrollController()..addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProgressively();
      _checkFirstOpen();
    });
  }

  Future<void> _initializeProgressively() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      if (widget.dataService != null) {
        try {
          await userProvider.initialize();
          if (userProvider.currentUserNpub == widget.npub) {
            await userProvider.setCurrentUser(widget.npub);
          }
        } catch (e) {
          print('[FeedPage] UserProvider initialization error: $e');
        }
        print('[FeedPage] Using provided DataService - initialization complete');
      } else {
        try {
          await Future.wait([
            userProvider.initialize(),
            dataService.initializeLightweight(),
          ]);

          if (userProvider.currentUserNpub == widget.npub) {
            await userProvider.setCurrentUser(widget.npub);
          }

          if (mounted) {
            setState(() {});
          }

          Future.microtask(() async {
            try {
              await dataService.initializeHeavyOperations();
              await dataService.initializeConnections();
            } catch (e) {
              print('[FeedPage] Heavy operations error: $e');
            }
          });
        } catch (e) {
          print('[FeedPage] Initialization error: $e');
          if (mounted) {
            setState(() {
              errorMessage = 'Failed to initialize feed';
            });
          }
        }
      }
    } catch (e) {
      print('[FeedPage] Progressive initialization error: $e');
      if (mounted) {
        setState(() {
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
        print('[FeedPage] First open check error: $e');
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

  Widget _buildViewModeToggle(dynamic colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            icon: CarbonIcons.list,
            isSelected: _currentViewMode == NoteViewMode.text,
            onTap: () => _setViewMode(NoteViewMode.text),
            colors: colors,
          ),
          _buildToggleButton(
            icon: CarbonIcons.grid,
            isSelected: _currentViewMode == NoteViewMode.grid,
            onTap: () => _setViewMode(NoteViewMode.grid),
            colors: colors,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required dynamic colors,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? colors.primary : colors.iconSecondary,
        ),
      ),
    );
  }

  void _setViewMode(NoteViewMode mode) {
    if (_currentViewMode != mode) {
      setState(() {
        _currentViewMode = mode;
      });
    }
  }

  Widget _buildHeader(BuildContext context, double topPadding) {
    final colors = context.colors;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          width: double.infinity,
          color: colors.background.withOpacity(0.6),
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
                        builder: (context) => Consumer<UserProvider>(
                          builder: (context, userProvider, child) {
                            final user = userProvider.getUserOrDefault(widget.npub);
                            return GestureDetector(
                              onTap: () => Scaffold.of(context).openDrawer(),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: colors.avatarPlaceholder,
                                backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
                                child: user.profileImage.isEmpty ? Icon(Icons.person, color: colors.iconPrimary, size: 18) : null,
                              ),
                            );
                          },
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
                      child: _buildViewModeToggle(colors),
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

    return Scaffold(
      backgroundColor: colors.background,
      drawer: const SidebarWidget(),
      body: errorMessage != null
          ? Center(
              child: Text(
                errorMessage!,
                style: TextStyle(color: colors.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                Future.microtask(() => dataService.refreshNotes());
              },
              child: CustomScrollView(
                key: const PageStorageKey<String>('feed_scroll'),
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
                        child: _buildHeader(context, topPadding),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 8),
                  ),
                  NoteListWidgetFactory.create(
                    npub: widget.npub,
                    dataType: DataType.feed,
                    sharedDataService: dataService,
                    viewMode: _currentViewMode,
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
