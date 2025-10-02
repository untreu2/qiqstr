import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../core/di/app_di.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/user_repository.dart';
import '../screens/profile_page.dart';
import 'note_content_widget.dart';

class ReplyPreviewWidget extends StatelessWidget {
  final String noteId;

  const ReplyPreviewWidget({
    super.key,
    required this.noteId,
  });

  String _formatTimestamp(DateTime timestamp) {
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

  void _navigateToProfile(BuildContext context, String npub) {
    AppDI.get<UserRepository>().getUserProfile(npub).then((result) {
      result.fold(
        (user) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfilePage(user: user),
          ),
        ),
        (error) => debugPrint('[ReplyPreviewWidget] Error navigating to profile: $error'),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NoteModel?>(
      future: AppDI.get<NoteRepository>().getNoteById(noteId).then((result) => result.fold((note) => note, (error) => null)),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Note not found',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
            ),
          );
        }

        final note = snapshot.data!;
        final parsed = note.parsedContentLazy;

        return FutureBuilder<UserModel?>(
          future: AppDI.get<UserRepository>().getUserProfile(note.author).then((result) => result.fold((user) => user, (error) => null)),
          builder: (context, userSnapshot) {
            String authorName = 'Unknown';
            String authorImage = '';

            if (userSnapshot.hasData && userSnapshot.data != null) {
              final user = userSnapshot.data!;
              authorName = user.name;
              authorImage = user.profileImage;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 2,
                      height: 20,
                      color: context.colors.grey600,
                      margin: const EdgeInsets.only(right: 8),
                    ),
                    Icon(
                      Icons.reply,
                      size: 16,
                      color: context.colors.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Replying to',
                      style: TextStyle(
                        color: context.colors.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.grey900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.grey800, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: context.colors.surfaceTransparent,
                            backgroundImage: authorImage.isNotEmpty ? CachedNetworkImageProvider(authorImage) : null,
                            child: authorImage.isEmpty ? Icon(Icons.person, color: context.colors.textPrimary, size: 12) : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              authorName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '• ${_formatTimestamp(note.timestamp)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      NoteContentWidget(
                        noteId: note.id,
                        parsedContent: parsed,
                        onNavigateToMentionProfile: (npub) => _navigateToProfile(context, npub),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  height: 1,
                  color: context.colors.grey800,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
