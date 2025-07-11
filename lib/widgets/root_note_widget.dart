import 'package:flutter/material.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/note_content_widget.dart';
import 'package:qiqstr/widgets/interaction_bar_widget.dart';
import '../theme/theme_manager.dart';

class RootNoteWidget extends StatelessWidget {
  final NoteModel note;
  final DataService dataService;
  final void Function(String) onNavigateToMentionProfile;

  const RootNoteWidget({
    required this.note,
    required this.dataService,
    required this.onNavigateToMentionProfile,
    
    required this.isReactionGlowing,
    required this.isReplyGlowing,
    required this.isRepostGlowing,
    required this.isZapGlowing,
    required this.hasReacted,
    required this.hasReplied,
    required this.hasReposted,
    required this.hasZapped,
    required this.onReactionTap,
    required this.onReplyTap,
    required this.onRepostTap,
    required this.onZapTap,
    required this.onStatisticsTap,
    Key? key,
  }) : super(key: key);

  
  final bool isReactionGlowing;
  final bool isReplyGlowing;
  final bool isRepostGlowing;
  final bool isZapGlowing;
  final bool hasReacted;
  final bool hasReplied;
  final bool hasReposted;
  final bool hasZapped;
  final VoidCallback onReactionTap;
  final VoidCallback onReplyTap;
  final VoidCallback onRepostTap;
  final VoidCallback onZapTap;
  final VoidCallback onStatisticsTap;
  @override
  Widget build(BuildContext context) {
    final parsedContent = dataService.parseContent(note.content);
    final UserModel? authorProfile = dataService.profilesNotifier.value[note.author];
    final String authorName =
        authorProfile?.name.isNotEmpty ?? false ? authorProfile!.name : note.author.substring(0, 8);

    
    
    
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [


                  if (authorProfile?.profileImage.isNotEmpty ?? false) ...[
                    CircleAvatar(
                    radius: 21,
                      backgroundImage: NetworkImage(authorProfile!.profileImage), 
                    backgroundColor: context.colors.grey700,
                    ),
                  ] else ...[
                    CircleAvatar(
                    radius: 21,
                    backgroundColor: context.colors.grey700,
                    child: Icon(Icons.person, size: 23, color: context.colors.iconPrimary),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      authorName,
                    style: TextStyle(
                      fontSize: 16,
                      color: context.colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12), 
              NoteContentWidget(
                parsedContent: parsedContent,
                dataService: dataService,
              onNavigateToMentionProfile: onNavigateToMentionProfile,
              ),
              const SizedBox(height: 12), 
              InteractionBar(
                reactionCount: note.reactionCount,
                replyCount: note.replyCount,
                repostCount: note.repostCount,
                zapAmount: note.zapAmount, 
                isReactionGlowing: isReactionGlowing,
                isReplyGlowing: isReplyGlowing,
                isRepostGlowing: isRepostGlowing,
                isZapGlowing: isZapGlowing,
                hasReacted: hasReacted,
                hasReplied: hasReplied, 
                hasReposted: hasReposted,
                hasZapped: hasZapped,
                onReactionTap: onReactionTap,
                onReplyTap: onReplyTap,
                onRepostTap: onRepostTap,
                onZapTap: onZapTap,
                onStatisticsTap: onStatisticsTap,
              ),
            ],
          ),
        ),
      );
  }
}
