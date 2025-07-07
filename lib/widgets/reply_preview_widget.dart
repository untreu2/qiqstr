import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../services/data_service.dart';
import 'note_content_widget.dart';

class ReplyPreviewWidget extends StatelessWidget {
  final String noteId;
  final DataService dataService;

  const ReplyPreviewWidget({
    super.key,
    required this.noteId,
    required this.dataService,
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NoteModel?>(
      future: dataService.getCachedNote(noteId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: const Text(
              'Note not found',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          );
        }

        final note = snapshot.data!;
        dataService.parseContentForNote(note);
        final parsed = note.parsedContent!;

        return FutureBuilder<Map<String, String>>(
          future: dataService.getCachedUserProfile(note.author),
          builder: (context, userSnapshot) {
            String authorName = 'Unknown';
            String authorImage = '';
            
            if (userSnapshot.hasData) {
              final user = UserModel.fromCachedProfile(note.author, userSnapshot.data!);
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
                      color: Colors.grey.shade600,
                      margin: const EdgeInsets.only(right: 8),
                    ),
                    const Icon(
                      Icons.reply,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Replying to',
                      style: TextStyle(
                        color: Colors.grey,
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
                    color: Colors.grey.shade900.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade800, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.white24,
                            backgroundImage: authorImage.isNotEmpty
                                ? CachedNetworkImageProvider(authorImage)
                                : null,
                            child: authorImage.isEmpty
                                ? const Icon(Icons.person, color: Colors.white, size: 12)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              authorName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '• ${_formatTimestamp(note.timestamp)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      NoteContentWidget(
                        parsedContent: parsed,
                        dataService: dataService,
                        onNavigateToMentionProfile: (id) => dataService.openUserProfile(context, id),
                      ),
                    ],
                  ),
                ),
                
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  height: 1,
                  color: Colors.grey.shade800,
                ),
              ],
            );
          },
        );
      },
    );
  }
}