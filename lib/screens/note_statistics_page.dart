import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bounce/bounce.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../models/user_model.dart';
import '../theme/theme_manager.dart';

class NoteStatisticsPage extends StatefulWidget {
  final NoteModel note;
  final DataService dataService;

  const NoteStatisticsPage({
    super.key,
    required this.note,
    required this.dataService,
  });

  @override
  State<NoteStatisticsPage> createState() => _NoteStatisticsPageState();
}

class _NoteStatisticsPageState extends State<NoteStatisticsPage> {
  Future<UserModel> _getUser(String npub) async {
    final cached = await widget.dataService.getCachedUserProfile(npub);
    return UserModel.fromCachedProfile(npub, cached);
  }

  void _navigateToProfile(String npub) {
    try {
      if (mounted) {
        widget.dataService.openUserProfile(context, npub);
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
                            '⚡ $zapAmount sats',
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
    final reactions = widget.dataService.reactionsMap[widget.note.id] ?? [];
    final reposts = widget.dataService.repostsMap[widget.note.id] ?? [];
    final zaps = widget.dataService.zapsMap[widget.note.id] ?? [];

    final reactionWidgets = reactions.map((r) => _buildEntry(npub: r.author, content: r.content)).toList();

    final repostWidgets = reposts.map((r) => _buildEntry(npub: r.repostedBy, content: '')).toList();

    final zapWidgets = zaps
        .map((z) => _buildEntry(
              npub: z.sender,
              zapAmount: z.amount,
              content: z.comment ?? '',
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
                  tabs: const [
                    Tab(text: 'Reactions'),
                    Tab(text: 'Reposts'),
                    Tab(text: 'Zaps'),
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
