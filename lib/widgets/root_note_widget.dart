import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../providers/user_provider.dart';
import '../theme/theme_manager.dart';
import 'note_content_widget.dart';
import 'interaction_bar_widget.dart';

class RootNoteWidget extends StatelessWidget {
  final NoteModel note;
  final DataService dataService;
  final String currentUserNpub;
  final void Function(String) onNavigateToMentionProfile;

  final bool isReactionGlowing;
  final bool isReplyGlowing;
  final bool isRepostGlowing;
  final bool isZapGlowing;

  const RootNoteWidget({
    Key? key,
    required this.note,
    required this.dataService,
    required this.currentUserNpub,
    required this.onNavigateToMentionProfile,
    this.isReactionGlowing = false,
    this.isReplyGlowing = false,
    this.isRepostGlowing = false,
    this.isZapGlowing = false,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final parsedContent = note.parsedContentLazy;
    String formatTimestamp(DateTime timestamp) {
      final d = DateTime.now().difference(timestamp);
      if (d.inSeconds < 5) return 'now';
      if (d.inSeconds < 60) return '${d.inSeconds}s';
      if (d.inMinutes < 60) return '${d.inMinutes}m';
      if (d.inHours < 24) return '${d.inHours}h';
      if (d.inDays < 7) return '${d.inDays}d';
      if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
      if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
      return '${(d.inDays / 365).floor()}y';
    }

    final formattedTimestamp = formatTimestamp(note.timestamp);

    return ListenableBuilder(
      listenable: UserProvider.instance,
      builder: (context, _) {
        final authorProfile = UserProvider.instance.getUserOrDefault(note.author);

        if (UserProvider.instance.getUser(note.author) == null) {
          UserProvider.instance.loadUser(note.author);
        }

        return Card(
          margin: EdgeInsets.zero,
          color: context.colors.background,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => dataService.openUserProfile(context, note.author),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => dataService.openUserProfile(context, note.author),
                        child: _buildProfileImage(
                          imageUrl: authorProfile.profileImage,
                          radius: 21,
                          colors: context.colors,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      authorProfile.name.isNotEmpty ? authorProfile.name : note.author.substring(0, 8),
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: context.colors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (authorProfile.nip05.isNotEmpty && authorProfile.nip05Verified) ...[
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
                            if (authorProfile.nip05.isNotEmpty)
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    '• ${authorProfile.nip05}',
                                    style: TextStyle(fontSize: 13, color: context.colors.secondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text('• $formattedTimestamp', style: TextStyle(fontSize: 12.5, color: context.colors.secondary)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                NoteContentWidget(
                  parsedContent: parsedContent,
                  dataService: dataService,
                  onNavigateToMentionProfile: onNavigateToMentionProfile,
                  size: NoteContentSize.big,
                ),
                const SizedBox(height: 12),
                InteractionBar(
                  noteId: note.id,
                  currentUserNpub: currentUserNpub,
                  dataService: dataService,
                  note: note,
                  isReactionGlowing: isReactionGlowing,
                  isReplyGlowing: isReplyGlowing,
                  isRepostGlowing: isRepostGlowing,
                  isZapGlowing: isZapGlowing,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileImage({
    required String imageUrl,
    required double radius,
    required dynamic colors,
  }) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colors.surfaceTransparent,
        child: Icon(
          Icons.person,
          size: radius,
          color: colors.textSecondary,
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.surfaceTransparent,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => Icon(
            Icons.person,
            size: radius,
            color: colors.textSecondary,
          ),
          errorWidget: (context, url, error) => Icon(
            Icons.person,
            size: radius,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
