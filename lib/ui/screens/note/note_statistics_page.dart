import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../../models/note_model.dart';
import '../../../models/user_model.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/note_statistics_viewmodel.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';

class NoteStatisticsPage extends StatefulWidget {
  final NoteModel note;

  const NoteStatisticsPage({
    super.key,
    required this.note,
  });

  @override
  State<NoteStatisticsPage> createState() => _NoteStatisticsPageState();
}

class _NoteStatisticsPageState extends State<NoteStatisticsPage> {
  late final NoteStatisticsViewModel _viewModel;
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showInteractionsBubble = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _viewModel = NoteStatisticsViewModel(
      userRepository: AppDI.get(),
      dataService: AppDI.get(),
      note: widget.note,
    );
    _viewModel.addListener(_onViewModelChanged);
    _scrollController = ScrollController()..addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showInteractionsBubble.value != shouldShow) {
        _showInteractionsBubble.value = shouldShow;
      }
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _scrollController.dispose();
    _showInteractionsBubble.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _navigateToProfile(String npub) async {
    try {
      if (mounted) {
        debugPrint('[NoteStatisticsPage] Navigating to profile: $npub');

        final user = await _viewModel.getUser(npub);

        if (mounted) {
          final currentLocation = GoRouterState.of(context).matchedLocation;
          if (currentLocation.startsWith('/home/feed')) {
            context.push('/home/feed/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
          } else if (currentLocation.startsWith('/home/notifications')) {
            context.push('/home/notifications/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
          } else if (currentLocation.startsWith('/home/dm')) {
            context.push('/home/dm/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
          } else {
            context.push('/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
          }
        }
      }
    } catch (e) {
      debugPrint('[NoteStatisticsPage] Navigate to profile error: $e');
    }
  }

  Widget _buildEntry({
    required String npub,
    required String content,
    int? zapAmount,
  }) {
    return FutureBuilder<UserModel>(
      future: _viewModel.getUser(npub),
      builder: (_, snapshot) {
        final user = snapshot.data;
        
        if (user == null) {
          return const SizedBox.shrink();
        }

        Widget? trailing;
        if (zapAmount != null || content.isNotEmpty) {
          trailing = Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (zapAmount != null)
                Text(
                  ' $zapAmount sats',
                  style: TextStyle(
                    color: context.colors.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (content.isNotEmpty) ...[
                if (zapAmount != null) const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    content,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: content.length <= 5 ? 20 : 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          );
        }

        return GestureDetector(
          onTap: () => _navigateToProfile(npub),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildAvatar(context, user.profileImage),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: trailing != null ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (user.nip05.isNotEmpty && user.nip05Verified) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                size: 16,
                                color: context.colors.accent,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        Flexible(
                          child: trailing,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(BuildContext context, String imageUrl) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey.shade800,
        child: Icon(
          Icons.person,
          size: 26,
          color: context.colors.textSecondary,
        ),
      );
    }

    return ClipOval(
      child: Container(
        width: 48,
        height: 48,
        color: Colors.transparent,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          memCacheWidth: 192,
          placeholder: (context, url) => Container(
            color: Colors.grey.shade800,
            child: Icon(
              Icons.person,
              size: 26,
              color: context.colors.textSecondary,
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade800,
            child: Icon(
              Icons.person,
              size: 26,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const TitleWidget(
      title: 'Interactions',
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<NoteStatisticsViewModel>.value(
      value: _viewModel,
      child: Consumer<NoteStatisticsViewModel>(
        builder: (context, viewModel, child) {
          if (!viewModel.isInitialized) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final cachedInteractions = viewModel.cachedInteractions!;

          final interactionWidgets = <Widget>[];
          for (int i = 0; i < cachedInteractions.length; i++) {
            final interaction = cachedInteractions[i];
          interactionWidgets.add(
            _buildEntry(
              npub: interaction['npub'],
              content: interaction['content'],
              zapAmount: interaction['zapAmount'],
            ),
          );
          if (i < cachedInteractions.length - 1) {
            interactionWidgets.add(const _UserSeparator());
          }
        }

        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(height: MediaQuery.of(context).padding.top + 60),
                  ),
                  SliverToBoxAdapter(
                    child: _buildHeader(context),
                  ),
                  SliverToBoxAdapter(
                    child: interactionWidgets.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 32),
                              child: Text(
                                'No interactions yet.',
                                style: TextStyle(color: context.colors.textTertiary),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => interactionWidgets[index],
                      childCount: interactionWidgets.length,
                      addAutomaticKeepAlives: true,
                      addRepaintBoundaries: false,
                    ),
                  ),
                ],
              ),
              TopActionBarWidget(
                onBackPressed: () => context.pop(),
                centerBubble: Text(
                  'Interactions',
                  style: TextStyle(
                    color: context.colors.background,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                centerBubbleVisibility: _showInteractionsBubble,
                onCenterBubbleTap: () {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                showShareButton: false,
          ),
        ],
      ),
    );
        },
      ),
    );
  }
}

class _UserSeparator extends StatelessWidget {
  const _UserSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: Center(
        child: Container(
          height: 0.5,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
