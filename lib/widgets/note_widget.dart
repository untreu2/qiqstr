import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/screens/note_statistics_page.dart';
import 'package:qiqstr/screens/thread_page.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:qiqstr/widgets/interaction_bar_widget.dart';
import 'package:qiqstr/widgets/note_content_widget.dart';

import '../models/note_model.dart';
import '../services/data_service.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final DataService dataService;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;

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
    showDialog(
      context: context,
      builder: (_) => SendReplyDialog(
          dataService: widget.dataService, noteId: widget.note.id),
    );
  }

  void _handleRepostTap() {
    setState(() => _isRepostGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRepostGlowing = false);
    });

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Colors.black,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.repeat, color: Colors.white),
            title: const Text('Repost',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            onTap: () async {
              Navigator.pop(context);
              try {
                await widget.dataService.sendRepost(widget.note);
              } catch (_) {}
            },
          ),
          ListTile(
            leading: const Icon(Icons.format_quote, color: Colors.white),
            title: const Text('Quote',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            onTap: () {
              Navigator.pop(context);
              final bech32 = encodeBasicBech32(widget.note.id, 'note');
              final quoteText = 'nostr:$bech32';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShareNotePage(
                    dataService: widget.dataService,
                    initialText: quoteText,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 45),
        ],
      ),
    );
  }

  void _handleZapTap() {
    setState(() => _isZapGlowing = true);
    Future.delayed(const Duration(milliseconds: 400),
        () => mounted ? setState(() => _isZapGlowing = false) : null);

    final amountController = TextEditingController(text: '21');
    final noteController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 40,
            top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Amount (sats)',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Comment... (Optional)',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              onPressed: () async {
                final sats = int.tryParse(amountController.text.trim());
                if (sats == null || sats <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Enter a valid amount'),
                      duration: Duration(seconds: 2)));
                  return;
                }
                Navigator.pop(context);
                try {
                  final profile = await widget.dataService
                      .getCachedUserProfile(widget.note.author);
                  final user =
                      UserModel.fromCachedProfile(widget.note.author, profile);
                  final invoice = await widget.dataService.sendZap(
                    recipientPubkey: user.npub,
                    lud16: user.lud16,
                    noteId: widget.note.id,
                    amountSats: sats,
                    content: noteController.text.trim(),
                  );
                  await Clipboard.setData(ClipboardData(text: invoice));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('⚡ Copied!'),
                        duration: Duration(seconds: 2)));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Zap failed: $e'),
                        duration: const Duration(seconds: 2)));
                  }
                }
              },
              child: const Text('Copy to send'),
            ),
          ],
        ),
      ),
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
        builder: (_) => ThreadPage(rootNoteId: rootIdToShow, dataService: widget.dataService),
      ),
    );
  }

  Widget _buildRepostInfo(String npub, DateTime? ts) {
    final user = widget.profiles[npub];
    final name = user?.name ?? 'Unknown';
    final profileImage = user?.profileImage;

    return GestureDetector(
      onTap: () => _navigateToProfile(npub),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.repeat, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          profileImage != null && profileImage.isNotEmpty
              ? CircleAvatar(
                  radius: 10,
                  backgroundImage: CachedNetworkImageProvider(profileImage),
                  backgroundColor: Colors.transparent,
                )
              : const CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, size: 12, color: Colors.white),
                ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Reposted by $name',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ts != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '• ${_formatTimestamp(ts)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
            color: Colors.black,
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
                if (updatedNote.isReply) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: GestureDetector(
                      onTap: () => _navigateToProfile(updatedNote.author),
                      child: Row(
                        children: [
                          const Icon(Icons.reply, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Replied by ${authorUser?.name ?? 'Unknown'}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
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
                          child: CircleAvatar(
                            radius: 18.5,
                            backgroundImage:
                                (authorUser?.profileImage ?? '').isNotEmpty
                                    ? CachedNetworkImageProvider(
                                        authorUser!.profileImage)
                                    : null,
                            backgroundColor:
                                (authorUser?.profileImage ?? '').isEmpty
                                    ? Colors.grey
                                    : Colors.transparent,
                            child: (authorUser?.profileImage ?? '').isEmpty
                                ? const Icon(Icons.person,
                                    size: 20, color: Colors.white)
                                : null,
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
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            height: 0.1,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Text('• $_formattedTimestamp',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            NoteContentWidget(
                              parsedContent: parsed,
                              dataService: widget.dataService,
                              onNavigateToMentionProfile: _navigateToMentionProfile,
                            ),
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
