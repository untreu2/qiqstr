import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qiqstr/ui/widgets/note/note_list_widget.dart' as widgets;
import 'package:qiqstr/ui/widgets/article/article_widget.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/auth_service.dart';
import '../../../presentation/blocs/profile/profile_bloc.dart';
import '../../../presentation/blocs/profile/profile_event.dart';
import '../../../presentation/blocs/profile/profile_state.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/user/profile_info_widget.dart';
import '../../../l10n/app_localizations.dart';

class ProfilePage extends StatefulWidget {
  final String pubkeyHex;

  const ProfilePage({super.key, required this.pubkeyHex});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late ScrollController _scrollController;

  static final _photoRegExp = RegExp(
    r'https?://\S+\.(jpg|jpeg|png|webp|gif)',
    caseSensitive: false,
  );

  static final _videoRegExp = RegExp(
    r'https?://\S+\.(mp4|mov)',
    caseSensitive: false,
  );

  final ValueNotifier<List<Map<String, dynamic>>> _notesNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Map<String, dynamic>>> _repliesNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Map<String, dynamic>>> _photosNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Map<String, dynamic>>> _videosNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Map<String, dynamic>>> _likesNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> _showUsernameBubbleNotifier =
      ValueNotifier<bool>(false);
  Timer? _scrollDebounceTimer;
  int _selectedTab = 0;
  static const int _tabCount = 6;
  final ScrollController _tabSelectorController = ScrollController();
  final Map<int, GlobalKey> _tabKeys = {};
  Offset? _swipeStartPosition;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;

      final shouldShow = _scrollController.offset > 100;
      if (_showUsernameBubbleNotifier.value != shouldShow) {
        _showUsernameBubbleNotifier.value = shouldShow;
      }
    });
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _notesNotifier.dispose();
    _repliesNotifier.dispose();
    _photosNotifier.dispose();
    _videosNotifier.dispose();
    _likesNotifier.dispose();
    _showUsernameBubbleNotifier.dispose();
    _tabSelectorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BlocProvider<ProfileBloc>(
      create: (context) {
        final bloc = AppDI.get<ProfileBloc>();
        if (widget.pubkeyHex.isNotEmpty) {
          bloc.add(ProfileLoadRequested(widget.pubkeyHex));
        }
        return bloc;
      },
      child: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          if (state is! ProfileLoaded) {
            if (state is ProfileLoading) {
              return Scaffold(
                backgroundColor: colors.background,
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            if (state is ProfileError) {
              final l10n = AppLocalizations.of(context)!;
              return Scaffold(
                backgroundColor: colors.background,
                body: Center(child: Text(l10n.errorWithMessage(state.message))),
              );
            }
            return Scaffold(
              backgroundColor: colors.background,
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          final currentUser = state.user;

          return Scaffold(
            backgroundColor: colors.background,
            body: Stack(
              children: [
                _buildContent(context, state),
                TopActionBarWidget(
                  topOffset: 6,
                  onBackPressed: () => context.pop(),
                  centerBubble: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.avatarPlaceholder,
                          image: () {
                            final profileImage =
                                currentUser['profileImage'] as String? ?? '';
                            return profileImage.isNotEmpty
                                ? DecorationImage(
                                    image: CachedNetworkImageProvider(
                                        profileImage),
                                    fit: BoxFit.cover,
                                  )
                                : null;
                          }(),
                        ),
                        child: () {
                          final profileImage =
                              currentUser['profileImage'] as String? ?? '';
                          return profileImage.isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: 14,
                                  color: colors.textSecondary,
                                )
                              : null;
                        }(),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        () {
                          final name = currentUser['name'] as String? ?? '';
                          final nip05 = currentUser['nip05'] as String? ?? '';
                          return name.isNotEmpty
                              ? name
                              : (nip05.isNotEmpty
                                  ? nip05.split('@').first
                                  : 'Anonymous');
                        }(),
                        style: TextStyle(
                          color: colors.background,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  centerBubbleVisibility: _showUsernameBubbleNotifier,
                  onCenterBubbleTap: () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  onSharePressed: () => _handleShare(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  GlobalKey _getTabKey(int index) {
    return _tabKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _selectTab(int index) {
    if (_selectedTab != index) {
      setState(() => _selectedTab = index);
      _scrollToActiveTab(index);
    }
  }

  void _scrollToActiveTab(int tabIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _tabKeys[tabIndex];
      if (key == null || key.currentContext == null) return;
      if (!_tabSelectorController.hasClients) return;

      final renderBox = key.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final scrollRenderBox = _tabSelectorController
          .position.context.storageContext
          .findRenderObject() as RenderBox?;
      if (scrollRenderBox == null) return;

      final tabOffset =
          renderBox.localToGlobal(Offset.zero, ancestor: scrollRenderBox);
      final tabWidth = renderBox.size.width;
      final viewportWidth = _tabSelectorController.position.viewportDimension;
      final currentScroll = _tabSelectorController.offset;

      final tabLeft = tabOffset.dx + currentScroll;
      final tabCenter = tabLeft + tabWidth / 2;
      final targetScroll = (tabCenter - viewportWidth / 2).clamp(
        _tabSelectorController.position.minScrollExtent,
        _tabSelectorController.position.maxScrollExtent,
      );

      _tabSelectorController.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleSwipe(Offset delta) {
    final dx = delta.dx;
    final dy = delta.dy;
    if (dx.abs() < 80 || dx.abs() < dy.abs() * 1.5) return;

    if (dx < 0 && _selectedTab < _tabCount - 1) {
      _selectTab(_selectedTab + 1);
    } else if (dx > 0 && _selectedTab > 0) {
      _selectTab(_selectedTab - 1);
    }
  }

  Widget _buildContent(BuildContext context, ProfileState state) {
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
          context.read<ProfileBloc>().add(const ProfileRefreshed());
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          cacheExtent: 1200,
          slivers: [
            SliverToBoxAdapter(
              child: _buildProfileInfo(context, state),
            ),
            SliverToBoxAdapter(
              child: _buildTabSelector(context),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 8),
            ),
            _buildTabContent(context, state),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSelector(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    final tabs = <_ProfileTab>[
      _ProfileTab(label: l10n.notes, index: 0),
      _ProfileTab(label: l10n.replies, index: 1),
      _ProfileTab(label: l10n.photos, index: 2),
      _ProfileTab(label: l10n.videos, index: 3),
      _ProfileTab(label: l10n.likes, index: 4),
      _ProfileTab(label: l10n.reads, index: 5),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SingleChildScrollView(
        controller: _tabSelectorController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: tabs
              .expand((tab) => [
                    _buildTab(
                      key: _getTabKey(tab.index),
                      colors: colors,
                      label: tab.label,
                      isSelected: _selectedTab == tab.index,
                      onTap: () => _selectTab(tab.index),
                    ),
                    const SizedBox(width: 24),
                  ])
              .toList()
            ..removeLast(),
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, ProfileState state) {
    return switch (_selectedTab) {
      0 => _buildProfileNotes(context, state),
      1 => _buildProfileReplies(context, state),
      2 => _buildProfilePhotos(context, state),
      3 => _buildProfileVideos(context, state),
      4 => _buildProfileLikes(context, state),
      5 => _buildProfileReads(context, state),
      _ => _buildProfileNotes(context, state),
    };
  }

  Widget _buildTab({
    GlobalKey? key,
    required AppThemeColors colors,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
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
              label,
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

  Widget _buildProfileInfo(BuildContext context, ProfileState state) {
    if (state is! ProfileLoaded) {
      return const SizedBox.shrink();
    }
    final user = state.user;
    final pubkeyHex = user['pubkeyHex'] as String? ?? '';
    return ProfileInfoWidget(
      key: ValueKey(pubkeyHex),
      user: user,
      onNavigateToProfile: (npub) {
        context.push(
            '/profile?npub=${Uri.encodeComponent(npub)}&pubkeyHex=${Uri.encodeComponent(npub)}');
      },
    );
  }

  Widget _buildProfileNotes(BuildContext context, ProfileState state) {
    if (state is ProfileLoaded) {
      _notesNotifier.value = state.notes;

      return widgets.NoteListWidget(
        notes: state.notes,
        currentUserHex: state.currentUserHex,
        notesNotifier: _notesNotifier,
        profiles: state.profiles,
        isLoading: state.isLoadingMore,
        canLoadMore: state.canLoadMore,
        onLoadMore: () {
          context
              .read<ProfileBloc>()
              .add(const ProfileLoadMoreNotesRequested());
        },
        onEmptyRefresh: () {
          if (state.currentProfileHex.isNotEmpty) {
            context
                .read<ProfileBloc>()
                .add(ProfileNotesLoaded(state.currentProfileHex));
          }
        },
        scrollController: _scrollController,
      );
    }

    return _buildNonLoadedState(context, state);
  }

  Widget _buildProfileReplies(BuildContext context, ProfileState state) {
    if (state is ProfileLoaded) {
      _repliesNotifier.value = state.replies;

      return widgets.NoteListWidget(
        notes: state.replies,
        currentUserHex: state.currentUserHex,
        notesNotifier: _repliesNotifier,
        profiles: state.profiles,
        isLoading: state.isLoadingMoreReplies,
        canLoadMore: state.canLoadMoreReplies,
        onLoadMore: () {
          context
              .read<ProfileBloc>()
              .add(const ProfileLoadMoreRepliesRequested());
        },
        onEmptyRefresh: () {
          if (state.currentProfileHex.isNotEmpty) {
            context
                .read<ProfileBloc>()
                .add(ProfileRepliesLoaded(state.currentProfileHex));
          }
        },
        scrollController: _scrollController,
      );
    }

    return _buildNonLoadedState(context, state);
  }

  Widget _buildNonLoadedState(BuildContext context, ProfileState state) {
    if (state is ProfileLoading) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (state is ProfileError) {
      return SliverToBoxAdapter(
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
                  'Error loading notes',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  state.message,
                  style: TextStyle(color: context.colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Retry',
                  onPressed: () {
                    context.read<ProfileBloc>().add(const ProfileRefreshed());
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(l10n.noNotesFromThisUser),
            ),
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _filterByRegExp(
      List<Map<String, dynamic>> notes, RegExp regExp) {
    return notes.where((note) {
      final content = note['content'] as String? ?? '';
      return regExp.hasMatch(content);
    }).toList();
  }

  List<Map<String, dynamic>> _ownNotesSorted(ProfileLoaded state) {
    final ownNotes = [...state.notes, ...state.replies]
        .where((n) => n['isRepost'] != true)
        .toList();
    ownNotes.sort((a, b) {
      final aTime =
          a['repostCreatedAt'] as int? ?? a['created_at'] as int? ?? 0;
      final bTime =
          b['repostCreatedAt'] as int? ?? b['created_at'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });
    return ownNotes;
  }

  Widget _buildProfilePhotos(BuildContext context, ProfileState state) {
    if (state is ProfileLoaded) {
      final photoNotes = _filterByRegExp(_ownNotesSorted(state), _photoRegExp);
      _photosNotifier.value = photoNotes;

      return widgets.NoteListWidget(
        notes: photoNotes,
        currentUserHex: state.currentUserHex,
        notesNotifier: _photosNotifier,
        profiles: state.profiles,
        isLoading: state.isLoadingMore,
        canLoadMore: state.canLoadMore,
        onLoadMore: () {
          context
              .read<ProfileBloc>()
              .add(const ProfileLoadMoreNotesRequested());
        },
        scrollController: _scrollController,
      );
    }

    return _buildNonLoadedState(context, state);
  }

  Widget _buildProfileVideos(BuildContext context, ProfileState state) {
    if (state is ProfileLoaded) {
      final videoNotes = _filterByRegExp(_ownNotesSorted(state), _videoRegExp);
      _videosNotifier.value = videoNotes;

      return widgets.NoteListWidget(
        notes: videoNotes,
        currentUserHex: state.currentUserHex,
        notesNotifier: _videosNotifier,
        profiles: state.profiles,
        isLoading: state.isLoadingMore,
        canLoadMore: state.canLoadMore,
        onLoadMore: () {
          context
              .read<ProfileBloc>()
              .add(const ProfileLoadMoreNotesRequested());
        },
        scrollController: _scrollController,
      );
    }

    return _buildNonLoadedState(context, state);
  }

  Widget _buildProfileLikes(BuildContext context, ProfileState state) {
    if (state is ProfileLoaded) {
      _likesNotifier.value = state.likedNotes;

      return widgets.NoteListWidget(
        notes: state.likedNotes,
        currentUserHex: state.currentUserHex,
        notesNotifier: _likesNotifier,
        profiles: state.profiles,
        isLoading: state.isLoadingMoreLikes,
        canLoadMore: state.canLoadMoreLikes,
        onLoadMore: () {
          context
              .read<ProfileBloc>()
              .add(const ProfileLoadMoreLikesRequested());
        },
        scrollController: _scrollController,
      );
    }

    return _buildNonLoadedState(context, state);
  }

  Widget _buildProfileReads(BuildContext context, ProfileState state) {
    if (state is! ProfileLoaded) {
      return _buildNonLoadedState(context, state);
    }

    final articles = state.articles;
    if (articles.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              AppLocalizations.of(context)!.noArticlesFound,
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == articles.length) {
            if (state.canLoadMoreArticles) {
              context
                  .read<ProfileBloc>()
                  .add(const ProfileLoadMoreArticlesRequested());
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return const SizedBox.shrink();
          }
          return ArticleWidget(
            article: articles[index],
            currentUserHex: state.currentUserHex,
            profiles: state.profiles,
          );
        },
        childCount: articles.length + (state.canLoadMoreArticles ? 1 : 0),
      ),
    );
  }

  Future<void> _handleShare(BuildContext context) async {
    try {
      final authService = AppDI.get<AuthService>();
      final npub = authService.hexToNpub(widget.pubkeyHex) ?? widget.pubkeyHex;
      final nostrLink = 'nostr:$npub';

      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: nostrLink,
          sharePositionOrigin:
              box != null ? box.localToGlobal(Offset.zero) & box.size : null,
        ),
      );
    } catch (e) {
      debugPrint('[ProfilePage] Share error: $e');
    }
  }
}

class _ProfileTab {
  final String label;
  final int index;

  const _ProfileTab({required this.label, required this.index});
}
