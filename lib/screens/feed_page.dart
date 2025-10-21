import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qiqstr/widgets/note_list_widget.dart' as widgets;
import 'package:qiqstr/widgets/sidebar_widget.dart';
import '../theme/theme_manager.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../core/ui/ui_state_builder.dart';
import '../core/di/app_di.dart';
import '../presentation/providers/viewmodel_provider.dart';
import '../presentation/viewmodels/feed_viewmodel.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/user_repository.dart';
import '../services/relay_service.dart';
import '../constants/relays.dart';

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
  int _connectedRelayCount = 0;
  Timer? _relayCountTimer;

  final ValueNotifier<List<NoteModel>> _notesNotifier = ValueNotifier([]);
  final Map<String, UserModel> _profiles = {};

  UserModel? _currentUser;
  StreamSubscription<UserModel>? _userStreamSubscription;
  StreamSubscription<Map<String, UserModel>>? _profilesStreamSubscription;
  late UserRepository _userRepository;
  late WebSocketManager _webSocketManager;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _webSocketManager = WebSocketManager.instance;
    _scrollController = ScrollController()..addListener(_scrollListener);
    _loadInitialUser();
    _setupUserStreamListener();
    _startRelayCountTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstOpen();
    });
  }

  void _setupUserStreamListener() {
    _userStreamSubscription = _userRepository.currentUserStream.listen(
      (updatedUser) {
        debugPrint('[FeedPage] Received updated user data from stream: ${updatedUser.name}');
        if (mounted) {
          setState(() {
            _currentUser = updatedUser;
            _profiles[updatedUser.npub] = updatedUser;
            debugPrint('[FeedPage] Profile updated in UI: ${updatedUser.name} (image: ${updatedUser.profileImage.isNotEmpty ? "✓" : "✗"})');
          });
        }
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

  void _startRelayCountTimer() {
    _updateRelayCount();
    _relayCountTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateRelayCount();
    });
  }

  void _updateRelayCount() {
    if (mounted) {
      try {
        final activeSockets = _webSocketManager.activeSockets;
        final activeCount = activeSockets.length;
        final totalRelays = _webSocketManager.relayUrls.length;

        if (kDebugMode) {
          print('[FeedPage] Active connections: $activeCount / $totalRelays relays');
        }

        if (_connectedRelayCount != activeCount) {
          setState(() {
            _connectedRelayCount = activeCount;
          });
        }
      } catch (e) {
        if (kDebugMode) {
          print('[FeedPage] Error updating relay count: $e');
        }
        _getRelayCountFromPrefs();
      }
    }
  }

  Future<void> _getRelayCountFromPrefs() async {
    try {
      final relays = await getRelaySetMainSockets();
      if (mounted && relays.length != _connectedRelayCount) {
        setState(() {
          _connectedRelayCount = relays.length;
        });
        if (kDebugMode) {
          print('[FeedPage] Fallback to configured relay count: ${relays.length}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FeedPage] Error getting relay count from prefs: $e');
      }
    }
  }

  String _getRelayCountText() {
    if (_connectedRelayCount == 1) {
      return '1 relay';
    } else {
      return '$_connectedRelayCount relays';
    }
  }

  @override
  void dispose() {
    _userStreamSubscription?.cancel();
    _profilesStreamSubscription?.cancel();
    _relayCountTimer?.cancel();
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
      } catch (e) {
        // Silently ignore errors when checking first open status
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
        debugPrint('[FeedPage] Received profiles update: ${profiles.length} profiles');
        if (mounted) {
          setState(() {
            _profiles.addAll(profiles);
            
            if (_currentUser != null && profiles.containsKey(_currentUser!.npub)) {
              final updatedCurrentUser = profiles[_currentUser!.npub]!;
              if (updatedCurrentUser.profileImage.isNotEmpty || _currentUser!.profileImage.isEmpty) {
                _currentUser = updatedCurrentUser;
                debugPrint('[FeedPage]  Updated current user profile from stream: ${updatedCurrentUser.name} (image: ${updatedCurrentUser.profileImage.isNotEmpty ? "✓" : "✗"})');
              }
            }
          });
        }
      },
      onError: (error) {
        debugPrint('[FeedPage] Error in profiles stream: $error');
      },
    );
  }

  Widget _buildHeader(BuildContext context, double topPadding) {
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: isHashtagMode
                      ? GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Icon(
                            Icons.arrow_back,
                            size: 24,
                            color: colors.textPrimary,
                          ),
                        )
                      : GestureDetector(
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
                                            image: NetworkImage(_currentUser!.profileImage),
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
                      Text(
                        _getRelayCountText(),
                        style: TextStyle(
                          color: colors.secondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_connectedRelayCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            shape: BoxShape.circle,
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

    return ViewModelBuilder<FeedViewModel>(
      create: () => AppDI.get<FeedViewModel>(),
      onModelReady: (viewModel) {
        viewModel.initializeWithUser(widget.npub, hashtag: widget.hashtag);

        _setupProfilesStreamListener(viewModel);
      },
      builder: (context, viewModel) {
        return Scaffold(
          backgroundColor: colors.background,
          drawer: widget.hashtag == null ? const SidebarWidget() : null,
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
                              hasMore: viewModel.canLoadMore,
                              onLoadMore: notes.length >= 20 ? viewModel.loadMoreNotes : null,
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
              if (viewModel.pendingNotesCount > 0 && widget.hashtag == null)
                Positioned(
                  bottom: 104,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        viewModel.addPendingNotesToFeed();
                        scrollToTop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        decoration: BoxDecoration(
                          color: colors.buttonPrimary,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_upward, size: 15, color: colors.buttonText),
                            const SizedBox(width: 5),
                            Text(
                              'Show new notes',
                              style: TextStyle(
                                color: colors.buttonText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
