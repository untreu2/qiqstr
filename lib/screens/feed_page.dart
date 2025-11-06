import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/widgets/note_list_widget.dart' as widgets;
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/widgets/back_button_widget.dart';
import '../theme/theme_manager.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../core/ui/ui_state_builder.dart';
import '../core/di/app_di.dart';
import '../presentation/providers/viewmodel_provider.dart';
import '../presentation/viewmodels/feed_viewmodel.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/user_repository.dart';

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
  late final Map<String, UserModel> _profiles;

  UserModel? _currentUser;
  StreamSubscription<UserModel>? _userStreamSubscription;
  StreamSubscription<Map<String, UserModel>>? _profilesStreamSubscription;
  Timer? _profileUpdateThrottleTimer;
  bool _profileUpdatePending = false;
  late UserRepository _userRepository;

  @override
  void initState() {
    super.initState();
    _profiles = <String, UserModel>{};
    _userRepository = AppDI.get<UserRepository>();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _loadInitialUser();
    _setupUserStreamListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstOpen();
    });
  }

  Timer? _userUpdateThrottleTimer;
  bool _userUpdatePending = false;
  UserModel? _pendingUser;

  void _setupUserStreamListener() {
    _userStreamSubscription = _userRepository.currentUserStream.listen(
      (updatedUser) {
        if (!mounted) return;

        final hasChanges = _currentUser == null ||
            _currentUser!.npub != updatedUser.npub ||
            _currentUser!.profileImage != updatedUser.profileImage ||
            _currentUser!.name != updatedUser.name;

        if (!hasChanges) return;

        _pendingUser = updatedUser;
        _userUpdatePending = true;
        _userUpdateThrottleTimer?.cancel();
        _userUpdateThrottleTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _userUpdatePending && _pendingUser != null) {
            _userUpdatePending = false;
            setState(() {
              _currentUser = _pendingUser;
              _profiles[_pendingUser!.npub] = _pendingUser!;
            });
            _pendingUser = null;
          }
        });
      },
      onError: (error) {
        debugPrint('[FeedPage] Error in user stream: $error');
      },
    );
  }

  Future<void> _loadInitialUser() async {
    final user = await _getCurrentUser();
    if (mounted && user != null) {
      setState(() {
        _currentUser = user;
        _profiles[user.npub] = user;
      });

      if (user.profileImage.isEmpty) {
        debugPrint('[FeedPage] ️ Current user profile image missing, reloading...');
        _reloadCurrentUserProfile();
      } else {
        debugPrint('[FeedPage]  Current user loaded with profile image');
      }
    }
  }

  Future<void> _reloadCurrentUserProfile() async {
    try {
      final authRepository = AppDI.get<AuthRepository>();
      final npubResult = await authRepository.getCurrentUserNpub();

      if (npubResult.isError || npubResult.data == null) {
        return;
      }

      final userResult = await _userRepository.getUserProfile(npubResult.data!);
      userResult.fold(
        (user) {
          if (mounted) {
            setState(() {
              _currentUser = user;
              _profiles[user.npub] = user;
            });
            debugPrint('[FeedPage]  Reloaded current user: ${user.name} (image: ${user.profileImage.isNotEmpty ? "✓" : "✗"})');
          }
        },
        (error) {
          debugPrint('[FeedPage]  Failed to reload current user: $error');
        },
      );
    } catch (e) {
      debugPrint('[FeedPage]  Error reloading current user: $e');
    }
  }

  void _scrollListener() {
    final direction = _scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse && _showAppBar) {
      setState(() {
        _showAppBar = false;
      });
    } else if (direction == ScrollDirection.forward && !_showAppBar) {
      setState(() {
        _showAppBar = true;
      });
    }
  }

  @override
  void dispose() {
    _userStreamSubscription?.cancel();
    _profilesStreamSubscription?.cancel();
    _profileUpdateThrottleTimer?.cancel();
    _userUpdateThrottleTimer?.cancel();
    _scrollController.dispose();
    _notesNotifier.dispose();
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
      } catch (e) {}
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

  Future<UserModel?> _getCurrentUser() async {
    try {
      final authRepository = AppDI.get<AuthRepository>();
      final userRepository = AppDI.get<UserRepository>();

      final npubResult = await authRepository.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        return null;
      }

      final userResult = await userRepository.getUserProfile(npubResult.data!);
      return userResult.fold(
        (user) => user,
        (error) => null,
      );
    } catch (e) {
      debugPrint('Error getting current user: $e');
      return null;
    }
  }

  void _setupProfilesStreamListener(FeedViewModel viewModel) {
    _profilesStreamSubscription = viewModel.profilesStream.listen(
      (profiles) {
        if (!mounted || profiles.isEmpty) return;

        bool hasChanges = false;
        for (final entry in profiles.entries) {
          final existing = _profiles[entry.key];
          if (existing == null || existing.profileImage != entry.value.profileImage || existing.name != entry.value.name) {
            _profiles[entry.key] = entry.value;
            hasChanges = true;
          }
        }

        if (_currentUser != null && profiles.containsKey(_currentUser!.npub)) {
          final updatedCurrentUser = profiles[_currentUser!.npub]!;
          if (updatedCurrentUser.profileImage.isNotEmpty || _currentUser!.profileImage.isEmpty) {
            _currentUser = updatedCurrentUser;
            hasChanges = true;
          }
        }

        if (!hasChanges) return;

        _profileUpdatePending = true;
        _profileUpdateThrottleTimer?.cancel();
        _profileUpdateThrottleTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _profileUpdatePending) {
            _profileUpdatePending = false;
            setState(() {});
          }
        });
      },
      onError: (error) {
        debugPrint('[FeedPage] Error in profiles stream: $error');
      },
    );
  }

  Widget _buildHeader(BuildContext context, double topPadding, FeedViewModel viewModel) {
    final colors = context.colors;
    final isHashtagMode = widget.hashtag != null;

    return Container(
      width: double.infinity,
      color: colors.background.withValues(alpha: 0.8),
      padding: EdgeInsets.fromLTRB(16, topPadding + 4, 16, 8),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isHashtagMode)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: _currentUser != null
                          ? Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.avatarPlaceholder,
                                image: _currentUser!.profileImage.isNotEmpty == true
                                    ? DecorationImage(
                                        image: CachedNetworkImageProvider(_currentUser!.profileImage),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _currentUser!.profileImage.isEmpty != false
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
                  ),
                if (isHashtagMode)
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
                    child: isHashtagMode
                        ? Text(
                            '#${widget.hashtag}',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : SvgPicture.asset(
                            'assets/main_icon_white.svg',
                            width: 30,
                            height: 30,
                            colorFilter: ColorFilter.mode(colors.textPrimary, BlendMode.srcIn),
                          ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isHashtagMode) ...[
                        GestureDetector(
                          onTap: () => viewModel.toggleSortMode(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colors.textSecondary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  viewModel.sortMode == FeedSortMode.mostInteracted ? Icons.trending_up : Icons.access_time,
                                  size: 16,
                                  color: colors.textPrimary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  viewModel.sortMode == FeedSortMode.mostInteracted ? 'Popular' : 'Latest',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
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

        _setupProfilesStreamListener(viewModel);
      },
      builder: (context, viewModel) {
        return Scaffold(
          backgroundColor: colors.background,
          drawer: !isHashtagMode ? const SidebarWidget() : null,
          body: Stack(
            children: [
              UIStateBuilder<List<NoteModel>>(
                state: viewModel.feedState,
                builder: (context, notes) {
                  return RefreshIndicator(
                    onRefresh: viewModel.refreshFeed,
                    child: CustomScrollView(
                      key: const PageStorageKey<String>('feed_scroll'),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      cacheExtent: 1200,
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
                          child: SizedBox(height: isHashtagMode ? topPadding + 85 : 8),
                        ),
                        Builder(
                          builder: (context) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_notesNotifier.value != notes) {
                                _notesNotifier.value = notes;
                              }
                            });

                            return widgets.NoteListWidget(
                              notes: notes,
                              currentUserNpub: viewModel.currentUserNpub,
                              notesNotifier: _notesNotifier,
                              profiles: _profiles,
                              isLoading: viewModel.isLoadingMore,
                              canLoadMore: viewModel.canLoadMore,
                              onLoadMore: viewModel.loadMoreNotes,
                              scrollController: _scrollController,
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
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
                      ElevatedButton(
                        onPressed: () {
                          final viewModel = context.read<FeedViewModel>();
                          viewModel.refreshFeed();
                        },
                        child: const Text('Retry'),
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
                          color: colors.buttonPrimary,
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: Text(
                          '#${widget.hashtag}',
                          style: TextStyle(
                            color: colors.buttonText,
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
