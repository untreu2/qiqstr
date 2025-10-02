import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bounce/bounce.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../theme/theme_manager.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';
import '../data/services/nostr_data_service.dart';
import '../screens/profile_page.dart';

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

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _nostrDataService = AppDI.get<NostrDataService>();

    // IMMEDIATELY fetch fresh interactions for this note when stats page opens
    _fetchInteractionsForNote();
  }

  /// Fetch fresh interactions for the note
  Future<void> _fetchInteractionsForNote() async {
    try {
      debugPrint(' [NoteStatisticsPage] Fetching fresh interactions for note: ${widget.note.id}');
      await _nostrDataService.fetchInteractionsForNotes([widget.note.id]);

      // Update UI after fetching
      if (mounted) {
        setState(() {});
      }

      debugPrint(' [NoteStatisticsPage] Fresh interactions fetched');
    } catch (e) {
      debugPrint(' [NoteStatisticsPage] Error fetching interactions: $e');
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

        // Get user profile for navigation
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _navigateToProfile(npub),
                child: CircleAvatar(
                  radius: 26,
                  backgroundImage: user?.profileImage.isNotEmpty == true ? CachedNetworkImageProvider(user!.profileImage) : null,
                  backgroundColor: context.colors.grey800,
                  child: user?.profileImage.isNotEmpty != true ? Icon(Icons.person, color: context.colors.surface, size: 26) : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: () => _navigateToProfile(npub),
                        child: Text(
                          user?.name ?? npub.substring(0, 8),
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (zapAmount != null)
                          Text(
                            ' $zapAmount sats',
                            style: const TextStyle(
                              color: Color(0xFFECB200),
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
                                color: context.colors.textSecondary,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(List<Widget> items, String emptyText) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(
            emptyText,
            style: TextStyle(color: context.colors.textTertiary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
      separatorBuilder: (_, __) => Divider(color: context.colors.border, height: 1),
    );
  }

  Widget _buildFloatingBackButton(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.colors.backgroundTransparent,
              border: Border.all(
                color: context.colors.borderLight,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: Bounce(
              scaleFactor: 0.85,
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
              child: Icon(
                Icons.arrow_back,
                color: context.colors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get real interaction data from NostrDataService
    final reactions = _nostrDataService.getReactionsForNote(widget.note.id);
    final reposts = _nostrDataService.getRepostsForNote(widget.note.id);
    final zaps = _nostrDataService.getZapsForNote(widget.note.id);

    debugPrint(
        '[NoteStatisticsPage] Displaying interactions: ${reactions.length} reactions, ${reposts.length} reposts, ${zaps.length} zaps');

    // Build interaction widgets
    final reactionWidgets = reactions
        .map((reaction) => _buildEntry(
              npub: reaction.author,
              content: reaction.content,
            ))
        .toList();

    final repostWidgets = reposts
        .map((repost) => _buildEntry(
              npub: repost.author, // ReactionModel has author field
              content: 'Reposted',
            ))
        .toList();

    final zapWidgets = zaps
        .map((zap) => _buildEntry(
              npub: zap.sender,
              content: zap.comment ?? '',
              zapAmount: zap.amount,
            ))
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + 60),
                TabBar(
                  indicatorColor: context.colors.textPrimary,
                  labelColor: context.colors.textPrimary,
                  unselectedLabelColor: context.colors.textTertiary,
                  indicatorWeight: 1.5,
                  labelPadding: const EdgeInsets.symmetric(vertical: 12),
                  tabs: [
                    Tab(text: 'Reactions (${reactions.length})'),
                    Tab(text: 'Reposts (${reposts.length})'),
                    Tab(text: 'Zaps (${zaps.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildList(reactionWidgets, 'No reactions yet.'),
                      _buildList(repostWidgets, 'No reposts yet.'),
                      _buildList(zapWidgets, 'No zaps yet.'),
                    ],
                  ),
                ),
              ],
            ),
            _buildFloatingBackButton(context),
          ],
        ),
      ),
    );
  }
}
