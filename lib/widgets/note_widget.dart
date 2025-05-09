import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:qiqstr/screens/note_statistics_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import 'quote_widget.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final DataService dataService;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;

  const NoteWidget({
    super.key,
    required this.note,
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.dataService,
    required this.currentUserNpub,
    required this.notesNotifier,
  });

  @override
  _NoteWidgetState createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Future<Map<String, String>> _userProfileFuture;
  late final String _formattedTimestamp;

  bool _isReactionGlowing = false;
  bool _isReplyGlowing = false;
  bool _isRepostGlowing = false;
  bool _isZapGlowing = false;

  double _reactionScale = 1.0;
  double _replyScale = 1.0;
  double _repostScale = 1.0;
  double _zapScale = 1.0;

  @override
  void initState() {
    super.initState();
    _userProfileFuture =
        widget.dataService.getCachedUserProfile(widget.note.author);
    _formattedTimestamp = _formatTimestamp(widget.note.timestamp);
  }

  String _formatTimestamp(DateTime timestamp) {
    final d = DateTime.now().difference(timestamp);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
    if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
    return '${(d.inDays / 365).floor()}y';
  }

  void _navigateToMentionProfile(String id) {
    widget.dataService.openUserProfile(context, id);
  }

  void _navigateToStatisticsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteStatisticsPage(
            note: widget.note, dataService: widget.dataService),
      ),
    );
  }

  void _animateButton({
    required void Function() onStart,
    required void Function() onEnd,
  }) {
    setState(onStart);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(onEnd);
    });
  }

  Widget _buildContentText(Map<String, dynamic> parsed) {
    final parts = parsed['textParts'] as List<Map<String, dynamic>>;
    final mentionIds = parts
        .where((p) => p['type'] == 'mention')
        .map((p) => p['id'] as String)
        .toList();

    return FutureBuilder<Map<String, String>>(
      future: widget.dataService.resolveMentions(mentionIds),
      builder: (context, snapshot) {
        final mentions = snapshot.data ?? {};
        final spans = <InlineSpan>[];

        for (var p in parts) {
          if (p['type'] == 'text') {
            final text = p['text'] as String;
            final regex = RegExp(r'(https?:\/\/[^\s]+)');
            final matches = regex.allMatches(text);
            var last = 0;
            for (final m in matches) {
              if (m.start > last) {
                spans.add(TextSpan(
                  text: text.substring(last, m.start),
                  style: const TextStyle(fontSize: 15.5, color: Colors.white),
                ));
              }
              final url = text.substring(m.start, m.end);
              spans.add(TextSpan(
                text: url,
                style:
                    const TextStyle(color: Color(0xFFECB200), fontSize: 15.5),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => _onOpen(LinkableElement(url, url)),
              ));
              last = m.end;
            }
            if (last < text.length) {
              spans.add(TextSpan(
                text: text.substring(last),
                style: const TextStyle(fontSize: 15.5, color: Colors.white),
              ));
            }
          } else if (p['type'] == 'mention') {
            final username =
                mentions[p['id']] ?? '${p['id'].substring(0, 8)}...';
            spans.add(TextSpan(
              text: '@$username',
              style: const TextStyle(
                  color: Color(0xFFECB200),
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _navigateToMentionProfile(p['id']),
            ));
          }
        }
        return RichText(text: TextSpan(children: spans));
      },
    );
  }

  bool _hasZapped() {
    final zaps = widget.dataService.zapsMap[widget.note.id] ?? [];
    return zaps.any((z) => z.sender == widget.currentUserNpub);
  }

  bool _hasReacted() {
    final r = widget.dataService.reactionsMap[widget.note.id] ?? [];
    return r.any((e) => e.author == widget.currentUserNpub);
  }

  bool _hasReplied() {
    final r = widget.dataService.repliesMap[widget.note.id] ?? [];
    return r.any((e) => e.author == widget.currentUserNpub);
  }

  bool _hasReposted() {
    final r = widget.dataService.repostsMap[widget.note.id] ?? [];
    return r.any((e) => e.repostedBy == widget.currentUserNpub);
  }

  void _handleZapTap() {
    _animateButton(
      onStart: () {
        _zapScale = 1.2;
        _isZapGlowing = true;
      },
      onEnd: () {
        _zapScale = 1.0;
        _isZapGlowing = false;
      },
    );

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
          top: 8,
        ),
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

  void _handleReactionTap() async {
    if (_hasReacted()) return;
    _animateButton(
      onStart: () {
        _reactionScale = 1.2;
        _isReactionGlowing = true;
      },
      onEnd: () {
        _reactionScale = 1.0;
        _isReactionGlowing = false;
      },
    );
    try {
      await widget.dataService.sendReaction(widget.note.id, '💜');
    } catch (_) {}
  }

  void _handleReplyTap() {
    _animateButton(
      onStart: () {
        _replyScale = 1.2;
        _isReplyGlowing = true;
      },
      onEnd: () {
        _replyScale = 1.0;
        _isReplyGlowing = false;
      },
    );
    showDialog(
      context: context,
      builder: (_) => SendReplyDialog(
          dataService: widget.dataService, noteId: widget.note.id),
    );
  }

  void _handleRepostTap() async {
    _animateButton(
      onStart: () {
        _repostScale = 1.2;
        _isRepostGlowing = true;
      },
      onEnd: () {
        _repostScale = 1.0;
        _isRepostGlowing = false;
      },
    );
    try {
      await widget.dataService.sendRepost(widget.note);
    } catch (_) {}
  }

  Future<void> _onOpen(LinkableElement link) async {
    final url = Uri.parse(link.url);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _navigateToProfile(String npub) {
    widget.dataService.openUserProfile(context, npub);
  }

  Widget _buildRepostInfo(String npub, DateTime? ts) {
    return FutureBuilder<Map<String, String>>(
      future: widget.dataService.getCachedUserProfile(npub),
      builder: (_, snap) {
        var name = 'Unknown';
        if (snap.hasData) {
          name = snap.data!['name'] ?? 'Unknown';
        }
        return GestureDetector(
          onTap: () => _navigateToProfile(npub),
          child: Row(
            children: [
              const Icon(Icons.repeat, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Text('Reposted by $name',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                        overflow: TextOverflow.ellipsis),
                    if (ts != null) ...[
                      const SizedBox(width: 6),
                      Text('• ${_formatTimestamp(ts)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAction({
    required double scale,
    required String svg,
    required Color color,
    required int count,
    required VoidCallback onTap,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: scale),
      duration: const Duration(milliseconds: 300),
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: Row(
          children: [
            SvgPicture.asset(svg, width: 18, height: 18, color: color),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text('$count',
                  style: const TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ],
        ),
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

        return GestureDetector(
          onDoubleTapDown: (_) => _handleReactionTap(),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<Map<String, String>>(
                        future: _userProfileFuture,
                        builder: (_, snap) {
                          var imgUrl = '';
                          if (snap.hasData) {
                            final user = UserModel.fromCachedProfile(
                                updatedNote.author, snap.data!);
                            imgUrl = user.profileImage;
                          }
                          return GestureDetector(
                            onTap: () => _navigateToProfile(updatedNote.author),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundImage: imgUrl.isNotEmpty
                                    ? CachedNetworkImageProvider(imgUrl)
                                    : null,
                                backgroundColor: imgUrl.isEmpty
                                    ? Colors.grey
                                    : Colors.transparent,
                                child: imgUrl.isEmpty
                                    ? const Icon(Icons.person,
                                        size: 20, color: Colors.white)
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FutureBuilder<Map<String, String>>(
                              future: _userProfileFuture,
                              builder: (_, snap) {
                                if (!snap.hasData) {
                                  return Container(
                                      height: 20,
                                      width: 100,
                                      color: Colors.grey[700]);
                                }
                                final user = UserModel.fromCachedProfile(
                                    updatedNote.author, snap.data!);
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  user.name.length > 25
                                                      ? user.name
                                                          .substring(0, 25)
                                                      : user.name,
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.white,
                                                      height: 0.8),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 6),
                                                child: Text(
                                                    '• $_formattedTimestamp',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            if ((parsed['textParts'] as List).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(0),
                                child: _buildContentText(parsed),
                              ),
                            if ((parsed['mediaUrls'] as List).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: MediaPreviewWidget(
                                    mediaUrls:
                                        parsed['mediaUrls'] as List<String>),
                              ),
                            if ((parsed['linkUrls'] as List).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  children: (parsed['linkUrls'] as List<String>)
                                      .map((u) => LinkPreviewWidget(url: u))
                                      .toList(),
                                ),
                              ),
                            if ((parsed['quoteIds'] as List).isNotEmpty)
                              Column(
                                children: (parsed['quoteIds'] as List<String>)
                                    .map((q) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          child: QuoteWidget(
                                              bech32: q,
                                              dataService: widget.dataService),
                                        ))
                                    .toList(),
                              ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildAction(
                                  scale: _reactionScale,
                                  svg: 'assets/reaction_button.svg',
                                  color: _isReactionGlowing || _hasReacted()
                                      ? Colors.red.shade400
                                      : Colors.white,
                                  count: updatedNote.reactionCount,
                                  onTap: _handleReactionTap,
                                ),
                                _buildAction(
                                  scale: _replyScale,
                                  svg: 'assets/reply_button.svg',
                                  color: _isReplyGlowing || _hasReplied()
                                      ? Colors.blue.shade200
                                      : Colors.white,
                                  count: updatedNote.replyCount,
                                  onTap: _handleReplyTap,
                                ),
                                _buildAction(
                                  scale: _repostScale,
                                  svg: 'assets/repost_button.svg',
                                  color: _isRepostGlowing || _hasReposted()
                                      ? Colors.green.shade400
                                      : Colors.white,
                                  count: updatedNote.repostCount,
                                  onTap: _handleRepostTap,
                                ),
                                _buildAction(
                                  scale: _zapScale,
                                  svg: 'assets/zap_button.svg',
                                  color: _isZapGlowing || _hasZapped()
                                      ? const Color(0xFFECB200)
                                      : Colors.white,
                                  count: updatedNote.zapAmount,
                                  onTap: _handleZapTap,
                                ),
                                GestureDetector(
                                  onTap: _navigateToStatisticsPage,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(Icons.bar_chart,
                                        size: 18, color: Colors.grey),
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
