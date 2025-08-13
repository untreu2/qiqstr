import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../services/data_service.dart';
import '../theme/theme_manager.dart';
import '../screens/thread_page.dart';
import '../providers/user_provider.dart';
import '../providers/interactions_provider.dart';
import 'interaction_bar_widget.dart';
import 'note_content_widget.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final DataService dataService;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;

  final Color? containerColor;
  final bool isSmallView;
  const NoteWidget({
    super.key,
    required this.note,
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.dataService,
    required this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.containerColor,
    this.isSmallView = true,
  });

  @override
  _NoteWidgetState createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final String _formattedTimestamp;

  bool _isReactionGlowing = false;
  bool _isReplyGlowing = false;
  bool _isRepostGlowing = false;
  bool _isZapGlowing = false;

  @override
  void initState() {
    super.initState();
    _formattedTimestamp = _formatTimestamp(widget.note.timestamp);
  }

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

  void _navigateToMentionProfile(String id) => widget.dataService.openUserProfile(context, id);

  // Get real-time interaction counts from InteractionsProvider

  void _navigateToProfile(String npub) {
    // Immediate navigation with optimized profile loading
    widget.dataService.openUserProfile(context, npub);
  }

  void _navigateToThreadPage(NoteModel note) {
    final String rootIdToShow = (note.isReply && note.rootId != null && note.rootId!.isNotEmpty) ? note.rootId! : note.id;

    // Only pass focusedNoteId if the note is a reply and we're showing a different root
    final String? focusedNoteId = (note.isReply && rootIdToShow != note.id) ? note.id : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadPage(rootNoteId: rootIdToShow, dataService: widget.dataService, focusedNoteId: focusedNoteId),
      ),
    );
  }

  Widget _buildNoteContent(BuildContext context, Map<String, dynamic> parsed, NoteModel note) {
    final textParts = (parsed['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    String fullText = '';

    for (var part in textParts) {
      if (part['type'] == 'text') {
        fullText += part['text'] as String;
      } else if (part['type'] == 'mention') {
        fullText += '@mention ';
      }
    }

    const int characterLimit = 280;
    final shouldTruncate = fullText.length > characterLimit;

    return NoteContentWidget(
      parsedContent: shouldTruncate ? _createTruncatedParsedContentWithShowMore(parsed, characterLimit, note) : parsed,
      dataService: widget.dataService,
      onNavigateToMentionProfile: _navigateToMentionProfile,
      onShowMoreTap: shouldTruncate ? (noteId) => _navigateToThreadPage(note) : null,
    );
  }

  Map<String, dynamic> _createTruncatedParsedContentWithShowMore(Map<String, dynamic> originalParsed, int characterLimit, NoteModel note) {
    final textParts = (originalParsed['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final truncatedParts = <Map<String, dynamic>>[];
    int currentLength = 0;

    for (var part in textParts) {
      if (part['type'] == 'text') {
        final text = part['text'] as String;
        if (currentLength + text.length <= characterLimit) {
          truncatedParts.add(part);
          currentLength += text.length;
        } else {
          final remainingChars = characterLimit - currentLength;
          if (remainingChars > 0) {
            truncatedParts.add({
              'type': 'text',
              'text': text.substring(0, remainingChars) + '... ',
            });
          }
          break;
        }
      } else if (part['type'] == 'mention') {
        if (currentLength + 8 <= characterLimit) {
          truncatedParts.add(part);
          currentLength += 8;
        } else {
          break;
        }
      }
    }

    truncatedParts.add({
      'type': 'show_more',
      'text': 'Show more...',
      'noteId': note.id,
    });

    return {
      'textParts': truncatedParts,
      'mediaUrls': originalParsed['mediaUrls'] ?? [],
      'linkUrls': originalParsed['linkUrls'] ?? [],
      'quoteIds': originalParsed['quoteIds'] ?? [],
    };
  }

  Widget _buildUserInfoWithReply(BuildContext context, UserModel authorUser, dynamic colors) {
    // Get reply info if this is a reply
    String? replyToText;
    if (widget.note.isReply && widget.note.parentId != null) {
      final parentNote = widget.notesNotifier.value.firstWhere(
        (note) => note.id == widget.note.parentId,
        orElse: () => NoteModel(
          id: '',
          content: '',
          author: widget.note.parentId!,
          timestamp: DateTime.now(),
        ),
      );

      final parentAuthor = UserProvider.instance.getUserOrDefault(parentNote.author);
      if (UserProvider.instance.getUser(parentNote.author) == null) {
        UserProvider.instance.loadUser(parentNote.author);
      }

      replyToText = 'Replying to @${parentAuthor.name.isNotEmpty ? parentAuthor.name : 'user'}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                authorUser.name.length > 25 ? '${authorUser.name.substring(0, 25)}...' : authorUser.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (authorUser.nip05.isNotEmpty) ...[
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '• ${authorUser.nip05}',
                    style: TextStyle(fontSize: 12.5, color: colors.secondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '• $_formattedTimestamp',
                style: TextStyle(fontSize: 12.5, color: colors.secondary),
              ),
            ),
          ],
        ),
        if (replyToText != null)
          Transform.translate(
            offset: const Offset(0, -4),
            child: Text(
              replyToText,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;

    widget.dataService.parseContentForNote(widget.note);
    final parsed = widget.note.parsedContent!;

    return ListenableBuilder(
      listenable: Listenable.merge([
        UserProvider.instance,
        InteractionsProvider.instance,
      ]),
      builder: (context, _) {
        final authorUser = UserProvider.instance.getUserOrDefault(widget.note.author);
        if (UserProvider.instance.getUser(widget.note.author) == null) {
          UserProvider.instance.loadUser(widget.note.author);
        }

        UserModel? reposterUser;
        if (widget.note.isRepost && widget.note.repostedBy != null) {
          reposterUser = UserProvider.instance.getUserOrDefault(widget.note.repostedBy!);
          if (UserProvider.instance.getUser(widget.note.repostedBy!) == null) {
            UserProvider.instance.loadUser(widget.note.repostedBy!);
          }
        }

        return GestureDetector(
          onTap: () => _navigateToThreadPage(widget.note),
          child: Container(
            color: widget.containerColor ?? colors.background,
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _navigateToProfile(widget.note.author),
                            child: Padding(
                              padding: widget.note.isRepost ? const EdgeInsets.only(top: 8, left: 10) : const EdgeInsets.only(top: 8),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: colors.surfaceTransparent,
                                child: authorUser.profileImage.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: authorUser.profileImage,
                                        imageBuilder: (context, imageProvider) {
                                          return Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              image: DecorationImage(
                                                image: imageProvider,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          );
                                        },
                                        placeholder: (context, url) => Icon(
                                          Icons.person,
                                          size: 24,
                                          color: colors.textSecondary,
                                        ),
                                        errorWidget: (context, url, error) => Icon(
                                          Icons.person,
                                          size: 24,
                                          color: colors.textSecondary,
                                        ),
                                      )
                                    : Icon(
                                        Icons.person,
                                        size: 24,
                                        color: colors.textSecondary,
                                      ),
                              ),
                            ),
                          ),
                          if (widget.note.isRepost && reposterUser != null)
                            Positioned(
                              top: 0,
                              left: 0,
                              child: GestureDetector(
                                onTap: () => _navigateToProfile(reposterUser!.npub),
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: colors.surface,
                                  child: reposterUser.profileImage.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: reposterUser.profileImage,
                                          imageBuilder: (context, imageProvider) => Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
                                            ),
                                          ),
                                          placeholder: (context, url) => Icon(Icons.person, size: 12, color: colors.textSecondary),
                                          errorWidget: (context, url, error) => Icon(Icons.person, size: 12, color: colors.textSecondary),
                                        )
                                      : Icon(Icons.person, size: 12, color: colors.textSecondary),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildUserInfoWithReply(context, authorUser, colors),
                            _buildNoteContent(context, parsed, widget.note),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: InteractionBar(
                                    noteId: widget.note.id,
                                    currentUserNpub: widget.currentUserNpub,
                                    dataService: widget.dataService,
                                    note: widget.note,
                                    isReactionGlowing: _isReactionGlowing,
                                    isReplyGlowing: _isReplyGlowing,
                                    isRepostGlowing: _isRepostGlowing,
                                    isZapGlowing: _isZapGlowing,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
}
