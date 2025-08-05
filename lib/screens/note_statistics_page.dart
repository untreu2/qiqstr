import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  Widget _buildEntry({
    required String npub,
    required String content,
    int? zapAmount,
  }) {
    return FutureBuilder<UserModel>(
      future: _getUser(npub),
      builder: (_, snapshot) {
        final user = snapshot.data;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            radius: 20,
            backgroundImage: user?.profileImage.isNotEmpty == true ? CachedNetworkImageProvider(user!.profileImage) : null,
            backgroundColor: context.colors.grey800,
            child: user?.profileImage.isNotEmpty != true ? Icon(Icons.person, color: context.colors.surface) : null,
          ),
          title: Text(
            user?.name ?? npub.substring(0, 8),
            style: TextStyle(color: context.colors.textPrimary),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (zapAmount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '⚡ $zapAmount sats',
                    style: const TextStyle(
                      color: Color(0xFFECB200),
                      fontSize: 13,
                    ),
                  ),
                ),
              if (content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    content,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 13,
                    ),
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
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back, color: context.colors.textPrimary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Note interactions',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
      ),
    );
  }
}
