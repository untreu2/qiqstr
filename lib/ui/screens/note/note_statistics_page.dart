import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/note_model.dart';
import '../../../models/user_model.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';
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
  late final UserRepository _userRepository;
  late final DataService _nostrDataService;
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showInteractionsBubble = ValueNotifier(false);
  
  List<Map<String, dynamic>>? _cachedInteractions;
  String? _lastNoteId;
  StreamSubscription<List<NoteModel>>? _notesSubscription;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _nostrDataService = AppDI.get<DataService>();
    _scrollController = ScrollController()..addListener(_scrollListener);

    _notesSubscription = _nostrDataService.notesStream.listen((notes) {
      if (mounted) {
        final hasRelevantNote = notes.any((note) => note.id == widget.note.id);
        if (hasRelevantNote) {
          _buildInteractionsList();
          setState(() {});
        }
      }
    });

    _buildInteractionsList();
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
    _notesSubscription?.cancel();
    _scrollController.dispose();
    _showInteractionsBubble.dispose();
    super.dispose();
  }

  Future<UserModel> _getUser(String npub) async {
    final result = await _userRepository.getUserProfile(npub);
    return result.fold(
      (user) => user,
      (error) => UserModel.create(
        pubkeyHex: npub,
        name: '',
        about: '',
        profileImage: '',
        nip05: '',
        banner: '',
        lud16: '',
        website: '',
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _navigateToProfile(String npub) async {
    try {
      if (mounted) {
        debugPrint('[NoteStatisticsPage] Navigating to profile: $npub');

        final user = await _getUser(npub);

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
      future: _getUser(npub),
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

  void _buildInteractionsList() {
    if (_lastNoteId == widget.note.id && _cachedInteractions != null) {
      return;
    }
    
    final reactions = _nostrDataService.getReactionsForNote(widget.note.id);
    final reposts = _nostrDataService.getRepostsForNote(widget.note.id);
    final zaps = _nostrDataService.getZapsForNote(widget.note.id);

    final allInteractions = <Map<String, dynamic>>[];
    final seenReactions = <String>{};

    for (final reaction in reactions) {
      final reactionKey = '${reaction.author}:${reaction.content}';
      if (!seenReactions.contains(reactionKey)) {
        seenReactions.add(reactionKey);
        allInteractions.add({
          'type': 'reaction',
          'data': reaction,
          'timestamp': reaction.timestamp,
          'npub': reaction.author,
          'content': reaction.content,
        });
      }
    }

    final seenReposts = <String>{};
    for (final repost in reposts) {
      if (!seenReposts.contains(repost.author)) {
        seenReposts.add(repost.author);
        allInteractions.add({
          'type': 'repost',
          'data': repost,
          'timestamp': repost.timestamp,
          'npub': repost.author,
          'content': 'Reposted',
        });
      }
    }

    final seenZaps = <String>{};
    for (final zap in zaps) {
      if (!seenZaps.contains(zap.sender)) {
        seenZaps.add(zap.sender);
        allInteractions.add({
          'type': 'zap',
          'data': zap,
          'timestamp': zap.timestamp,
          'npub': zap.sender,
          'content': zap.comment ?? '',
          'zapAmount': zap.amount,
        });
      }
    }

    allInteractions.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
    
    _cachedInteractions = allInteractions;
    _lastNoteId = widget.note.id;
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedInteractions == null || _lastNoteId != widget.note.id) {
      _buildInteractionsList();
    }
    
    final interactionWidgets = <Widget>[];
    for (int i = 0; i < _cachedInteractions!.length; i++) {
      final interaction = _cachedInteractions![i];
      interactionWidgets.add(
        _buildEntry(
          npub: interaction['npub'],
          content: interaction['content'],
          zapAmount: interaction['zapAmount'],
        ),
      );
      if (i < _cachedInteractions!.length - 1) {
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
