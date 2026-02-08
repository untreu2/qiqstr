import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qiqstr/ui/widgets/note/note_list_widget.dart' as widgets;
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

  final ValueNotifier<List<Map<String, dynamic>>> _notesNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> _showUsernameBubbleNotifier =
      ValueNotifier<bool>(false);
  Timer? _scrollDebounceTimer;

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
    _showUsernameBubbleNotifier.dispose();
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

  Widget _buildContent(BuildContext context, ProfileState state) {
    return RefreshIndicator(
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
          _buildProfileNotes(context, state),
        ],
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
