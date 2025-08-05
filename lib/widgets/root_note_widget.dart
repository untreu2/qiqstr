import 'package:flutter/material.dart';
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
    final parsedContent = dataService.parseContent(note.content);

    return ListenableBuilder(
      listenable: UserProvider.instance,
      builder: (context, _) {
        final authorProfile = UserProvider.instance.getUserOrDefault(note.author);

        // Load user if not cached
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
                      CircleAvatar(
                        radius: 21,
                        backgroundImage: authorProfile.profileImage.isNotEmpty ? NetworkImage(authorProfile.profileImage) : null,
                        backgroundColor: context.colors.surfaceTransparent,
                        onBackgroundImageError: (exception, stackTrace) {},
                        child: authorProfile.profileImage.isEmpty
                            ? Icon(
                                Icons.person,
                                size: 24,
                                color: context.colors.textSecondary,
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              authorProfile.name.isNotEmpty ? authorProfile.name : note.author.substring(0, 8),
                              style: TextStyle(
                                fontSize: 16,
                                color: context.colors.textPrimary,
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (authorProfile.nip05.isNotEmpty)
                              Text(
                                authorProfile.nip05,
                                style: TextStyle(fontSize: 13, color: context.colors.secondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                NoteContentWidget(
                  parsedContent: parsedContent,
                  dataService: dataService,
                  onNavigateToMentionProfile: onNavigateToMentionProfile,
                  type: NoteContentType.big,
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
                  isLarge: true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
