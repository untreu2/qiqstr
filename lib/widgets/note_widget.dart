import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/screens/note_statistics_page.dart';
import 'package:qiqstr/screens/thread_page.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/widgets/interaction_bar_widget.dart';
import 'package:qiqstr/widgets/note_content_widget.dart';
import 'package:qiqstr/widgets/dialogs/repost_dialog.dart';
import 'package:qiqstr/widgets/dialogs/zap_dialog.dart';

import '../models/note_model.dart';
import '../services/data_service.dart';
import '../theme/theme_manager.dart';

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

class _NoteWidgetState extends State<NoteWidget>
    with AutomaticKeepAliveClientMixin {
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

  void _navigateToMentionProfile(String id) =>
      widget.dataService.openUserProfile(context, id);

  void _navigateToStatisticsPage() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteStatisticsPage(
              note: widget.note, dataService: widget.dataService),
        ),
      );    

  bool _hasZapped() => (widget.dataService.zapsMap[widget.note.id] ?? [])
      .any((z) => z.sender == widget.currentUserNpub);
  bool _hasReacted() => (widget.dataService.reactionsMap[widget.note.id] ?? [])
      .any((e) => e.author == widget.currentUserNpub);
  bool _hasReplied() => (widget.dataService.repliesMap[widget.note.id] ?? [])
      .any((e) => e.author == widget.currentUserNpub);
  bool _hasReposted() => (widget.dataService.repostsMap[widget.note.id] ?? [])
      .any((e) => e.repostedBy == widget.currentUserNpub);

  void _handleReactionTap() async {
    if (_hasReacted()) return;
    setState(() => _isReactionGlowing = true);
    Future.delayed(const Duration(milliseconds: 400),
        () => mounted ? setState(() => _isReactionGlowing = false) : null);
    try {
      await widget.dataService.sendReaction(widget.note.id, '+');
    } catch (_) {}
  }

  void _handleReplyTap() {
    setState(() => _isReplyGlowing = true);
    Future.delayed(const Duration(milliseconds: 400),
        () => mounted ? setState(() => _isReplyGlowing = false) : null);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareNotePage(
          dataService: widget.dataService,
          replyToNoteId: widget.note.id,
        ),
      ),
    );
  }

  void _handleRepostTap() {
    setState(() => _isRepostGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRepostGlowing = false);
    });

    showRepostDialog(
      context: context,
      dataService: widget.dataService,
      note: widget.note,
    );
  }

  void _handleZapTap() {
    setState(() => _isZapGlowing = true);
    Future.delayed(const Duration(milliseconds: 400),
        () => mounted ? setState(() => _isZapGlowing = false) : null);
    
    showZapDialog(
      context: context,
      dataService: widget.dataService,
      note: widget.note,
    );
  }

  void _navigateToProfile(String npub) =>
      widget.dataService.openUserProfile(context, npub);
  
  void _navigateToThreadPage(NoteModel note) {
    final String rootIdToShow =
        (note.isReply && note.rootId != null && note.rootId!.isNotEmpty) ? note.rootId! : note.id;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadPage(rootNoteId: rootIdToShow, dataService: widget.dataService, focusedNoteId: note.id),
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

    if (fullText.length <= characterLimit) {
      return NoteContentWidget(
        parsedContent: parsed,
        dataService: widget.dataService,
        onNavigateToMentionProfile: _navigateToMentionProfile,
      );
    }

    return NoteContentWidget(
      parsedContent: _createTruncatedParsedContentWithShowMore(parsed, characterLimit, note),
      dataService: widget.dataService,
      onNavigateToMentionProfile: _navigateToMentionProfile,
      onShowMoreTap: (noteId) => _navigateToThreadPage(note),
    );
  }

  Map<String, dynamic> _createTruncatedParsedContentWithShowMore(
      Map<String, dynamic> originalParsed, int characterLimit, NoteModel note) {
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

  Widget _buildRepostInfo(String npub, DateTime? ts) {
    final user = widget.profiles[npub];
    final name = user?.name ?? 'Unknown';
    final profileImage = user?.profileImage;

    return Builder(
      builder: (context) {
        final colors = context.colors;
        return GestureDetector(
          onTap: () => _navigateToProfile(npub),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.repeat, size: 16, color: colors.secondary),
              const SizedBox(width: 6),
              profileImage != null && profileImage.isNotEmpty
                  ? CircleAvatar(
                      radius: 11,
                      backgroundImage: CachedNetworkImageProvider(profileImage),
                      backgroundColor: colors.surfaceTransparent,
                    )
                  : CircleAvatar(
                      radius: 11,
                      backgroundColor: colors.avatarBackground,
                      child: Icon(Icons.person, size: 13, color: colors.iconPrimary),
                    ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Reposted by $name',
                        style: TextStyle(fontSize: 12, color: colors.secondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ts != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '• ${_formatTimestamp(ts)}',
                        style: TextStyle(fontSize: 12, color: colors.secondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;
    
    return ValueListenableBuilder<List<NoteModel>>(
      valueListenable: widget.notesNotifier,
      builder: (context, notes, _) {
        final index = notes.indexWhere((n) => n.id == widget.note.id);
        if (index == -1) return const SizedBox.shrink();
        final updatedNote = notes[index];

        widget.dataService.parseContentForNote(updatedNote);
        final parsed = updatedNote.parsedContent!;

        final authorUser = widget.profiles[updatedNote.author];

        return GestureDetector(
          onDoubleTapDown: (_) => _handleReactionTap(),
          onTap: () => _navigateToThreadPage(updatedNote),
          child: Container(
            color: widget.containerColor ?? colors.background,
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (updatedNote.isRepost && updatedNote.repostedBy != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _buildRepostInfo(
                        updatedNote.repostedBy!, updatedNote.repostTimestamp),
                  ),
                  const SizedBox(height: 8),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _navigateToProfile(updatedNote.author),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 21,
                                backgroundImage:
                                    (authorUser?.profileImage ?? '').isNotEmpty
                                        ? CachedNetworkImageProvider(
                                            authorUser!.profileImage)
                                        : null,
                                backgroundColor:
                                    (authorUser?.profileImage ?? '').isEmpty
                                        ? colors.avatarBackground
                                        : colors.surfaceTransparent,
                                child: (authorUser?.profileImage ?? '').isEmpty
                                    ? Icon(Icons.person,
                                        size: 23, color: colors.iconPrimary)
                                    : null,
                              ),
                              if (updatedNote.isReply)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: colors.secondary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.reply,
                                      size: 10,
                                      color: colors.iconPrimary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          (authorUser?.name ?? 'Unknown')
                                                      .length >
                                                  25
                                              ? (authorUser?.name ?? 'Unknown')
                                                  .substring(0, 25)
                                              : (authorUser?.name ?? 'Unknown'),
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: colors.textPrimary,
                                            height: 0.1,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Text('• $_formattedTimestamp',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: colors.secondary)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            _buildNoteContent(context, parsed, updatedNote),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: InteractionBar(
                                    reactionCount: updatedNote.reactionCount,
                                    replyCount: updatedNote.replyCount,
                                    repostCount: updatedNote.repostCount,
                                    zapAmount: updatedNote.zapAmount,
                                    isReactionGlowing: _isReactionGlowing,
                                    isReplyGlowing: _isReplyGlowing,
                                    isRepostGlowing: _isRepostGlowing,
                                    isZapGlowing: _isZapGlowing,
                                    hasReacted: _hasReacted(),
                                    hasReplied: _hasReplied(),
                                    hasReposted: _hasReposted(),
                                    hasZapped: _hasZapped(),
                                    onReactionTap: _handleReactionTap,
                                    onReplyTap: _handleReplyTap,
                                    onRepostTap: _handleRepostTap,
                                    onZapTap: _handleZapTap,
                                    onStatisticsTap: _navigateToStatisticsPage,
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
