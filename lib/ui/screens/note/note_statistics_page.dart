import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/note_model.dart';
import '../../../models/user_model.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/nostr_data_service.dart';
import '../profile/profile_page.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/title_widget.dart';

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
  late final NostrDataService _nostrDataService;
  late ScrollController _scrollController;
  bool _showInteractionsBubble = false;
  bool _isLoadingInteractions = false;
  
  List<Map<String, dynamic>>? _cachedInteractions;
  String? _lastNoteId;
  Timer? _updateTimer;
  StreamSubscription<List<NoteModel>>? _notesSubscription;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _nostrDataService = AppDI.get<NostrDataService>();
    _scrollController = ScrollController()..addListener(_scrollListener);

    _notesSubscription = _nostrDataService.notesStream.listen((notes) {
      if (mounted && _isLoadingInteractions) {
        final hasRelevantNote = notes.any((note) => note.id == widget.note.id);
        if (hasRelevantNote) {
          _buildInteractionsList();
          setState(() {});
        }
      }
    });

    _fetchInteractionsForNote();
    _buildInteractionsList();
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showInteractionsBubble != shouldShow) {
        setState(() {
          _showInteractionsBubble = shouldShow;
        });
      }
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _notesSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchInteractionsForNote() async {
    if (_isLoadingInteractions) return;

    try {
      setState(() {
        _isLoadingInteractions = true;
      });

      _updateTimer?.cancel();
      _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (mounted && _isLoadingInteractions) {
          _buildInteractionsList();
          setState(() {});
        } else {
          timer.cancel();
        }
      });

      debugPrint('[NoteStatisticsPage] Fetching interactions with EOSE for note: ${widget.note.id}');
      await _nostrDataService.fetchInteractionsForNotesWithEOSE(widget.note.id);

      _updateTimer?.cancel();
      _updateTimer = null;

      if (mounted) {
        _buildInteractionsList();
        setState(() {
          _isLoadingInteractions = false;
        });
      }

      debugPrint('[NoteStatisticsPage] Interactions fetched with EOSE');
    } catch (e) {
      debugPrint('[NoteStatisticsPage] Error fetching interactions: $e');
      _updateTimer?.cancel();
      _updateTimer = null;
      if (mounted) {
        _buildInteractionsList();
        setState(() {
          _isLoadingInteractions = false;
        });
      }
    }
  }

  Future<UserModel> _getUser(String npub) async {
    final result = await _userRepository.getUserProfile(npub);
    return result.fold(
      (user) => user,
      (error) => UserModel(
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePage(user: user),
            ),
          );
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

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: GestureDetector(
            onTap: () => _navigateToProfile(npub),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: user?.profileImage.isNotEmpty == true ? CachedNetworkImageProvider(user!.profileImage) : null,
                    backgroundColor: context.colors.grey800,
                    child: user?.profileImage.isNotEmpty != true ? Icon(Icons.person, color: context.colors.surface, size: 26) : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  user?.name ?? npub.substring(0, 8),
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (user?.nip05.isNotEmpty == true && user?.nip05Verified == true) ...[
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
                        Flexible(
                          child: Row(
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const TitleWidget(
      title: 'Interactions',
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
    );
  }

  void _buildInteractionsList() {
    if (_lastNoteId == widget.note.id && _cachedInteractions != null && !_isLoadingInteractions) {
      return;
    }
    
    final reactions = _nostrDataService.getReactionsForNote(widget.note.id);
    final reposts = _nostrDataService.getRepostsForNote(widget.note.id);
    final zaps = _nostrDataService.getZapsForNote(widget.note.id);

    debugPrint(
        '[NoteStatisticsPage] Building interactions: ${reactions.length} reactions, ${reposts.length} reposts, ${zaps.length} zaps');

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
    
    final interactionWidgets = _cachedInteractions!
        .map((interaction) => _buildEntry(
              npub: interaction['npub'],
              content: interaction['content'],
              zapAmount: interaction['zapAmount'],
            ))
        .toList();

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
                child: interactionWidgets.isEmpty && !_isLoadingInteractions
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
                ),
              ),
            ],
          ),
          const BackButtonWidget.floating(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _showInteractionsBubble ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
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
                      color: context.colors.buttonPrimary,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Text(
                      'Interactions',
                      style: TextStyle(
                        color: context.colors.buttonText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
