import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import 'package:qiqstr/widgets/quote_widget.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';

class NoteWidget extends StatefulWidget {
  final int index;
  final ValueNotifier<int> visibleIndexNotifier;
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final DataService dataService;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  const NoteWidget({
    super.key,
    required this.index,
    required this.visibleIndexNotifier,
    required this.note,
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.dataService,
    required this.currentUserNpub,
    required this.notesNotifier,
  });
  @override
  State<NoteWidget> createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget>
    with AutomaticKeepAliveClientMixin {
  bool _isVisible = false;
  bool _contentParsed = false;
  bool _isReactionGlowing = false,
      _isReplyGlowing = false,
      _isRepostGlowing = false,
      _isZapGlowing = false;
  double _reactionScale = 1, _replyScale = 1, _repostScale = 1, _zapScale = 1;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    widget.visibleIndexNotifier.addListener(_visibleIndexListener);
  }

  void _visibleIndexListener() {
    if (!_isVisible && widget.index <= widget.visibleIndexNotifier.value + 2) {
      setState(() => _isVisible = true);
    }
  }

  @override
  void dispose() {
    widget.visibleIndexNotifier.removeListener(_visibleIndexListener);
    super.dispose();
  }

  String _formatTimestamp(DateTime ts) {
    final d = DateTime.now().difference(ts);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    if (d.inDays < 30) return '${d.inDays ~/ 7}w';
    if (d.inDays < 365) return '${d.inDays ~/ 30}mo';
    return '${d.inDays ~/ 365}y';
  }

  void _ensureParsed(NoteModel n) {
    if (_contentParsed) return;
    widget.dataService.parseContentForNote(n);
    _contentParsed = true;
  }

  Future<InlineSpan> _buildMentionsAwareSpan(
      Map<String, dynamic> parsed) async {
    final parts = parsed['textParts'] as List<Map<String, dynamic>>;
    final mentionIds = parts
        .where((p) => p['type'] == 'mention')
        .map((p) => p['id'] as String)
        .toList();
    final resolved = await widget.dataService.resolveMentions(mentionIds);
    final spans = <InlineSpan>[];
    for (final p in parts) {
      if (p['type'] == 'text') {
        final text = p['text'] as String;
        final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
        int idx = 0;
        for (final m in urlRegex.allMatches(text)) {
          if (m.start > idx) {
            spans.add(TextSpan(
              text: text.substring(idx, m.start),
              style: TextStyle(
                color: Colors.white,
                fontSize: text.length < 21 ? 20 : 15.5,
              ),
            ));
          }
          final link = text.substring(m.start, m.end);
          spans.add(TextSpan(
            text: link,
            style: const TextStyle(
              color: Colors.amberAccent,
              fontStyle: FontStyle.italic,
              fontSize: 15.5,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                final uri = Uri.parse(link);
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
          ));
          idx = m.end;
        }
        if (idx < text.length) {
          spans.add(TextSpan(
            text: text.substring(idx),
            style: TextStyle(
              color: Colors.white,
              fontSize: text.length < 21 ? 20 : 16,
            ),
          ));
        }
      } else if (p['type'] == 'mention') {
        final id = p['id'] as String;
        final nick = resolved[id] ?? '${id.substring(0, 8)}...';
        spans.add(TextSpan(
          text: '@$nick',
          style: const TextStyle(
            color: Colors.amberAccent,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
            fontSize: 15.5,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => widget.dataService.openUserProfile(context, id),
        ));
      }
    }
    return TextSpan(children: spans);
  }

  Widget _authorInfo(String npub) {
    return FutureBuilder<Map<String, String>>(
      future: widget.dataService.getCachedUserProfile(npub),
      builder: (_, snap) {
        if (!snap.hasData) {
          return Row(children: [
            const CircleAvatar(radius: 20, backgroundColor: Colors.grey),
            const SizedBox(width: 8),
            Container(width: 100, height: 12, color: Colors.grey[700]),
          ]);
        }
        final u = UserModel.fromCachedProfile(npub, snap.data!);
        return Row(
          children: [
            GestureDetector(
              onTap: () => widget.dataService.openUserProfile(context, npub),
              child: CircleAvatar(
                radius: 20,
                backgroundImage: u.profileImage.isNotEmpty
                    ? CachedNetworkImageProvider(u.profileImage)
                    : null,
                backgroundColor:
                    u.profileImage.isEmpty ? Colors.grey : Colors.transparent,
                child: u.profileImage.isEmpty
                    ? const Icon(Icons.person, size: 20, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    u.name.length > 25
                        ? '${u.name.substring(0, 25)}...'
                        : u.name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                if (u.nip05.isNotEmpty)
                  Text(u.nip05,
                      style: TextStyle(fontSize: 13, color: Colors.grey[400])),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _repostInfo(String npub, DateTime? ts) {
    return FutureBuilder<Map<String, String>>(
      future: widget.dataService.getCachedUserProfile(npub),
      builder: (_, snap) {
        final name = snap.hasData ? snap.data!['name'] ?? 'Unknown' : 'Unknown';
        return Row(
          children: [
            const Icon(Icons.repeat, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Text('Reposted by $name',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis),
                  if (ts != null) ...[
                    const SizedBox(width: 6),
                    Text('• ${_formatTimestamp(ts)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ]
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _action({
    required double scale,
    required String asset,
    required Color color,
    required int count,
    required VoidCallback onTap,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: scale),
      duration: const Duration(milliseconds: 300),
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: Row(
          children: [
            SvgPicture.asset(asset, width: 20, height: 20, color: color),
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

  bool _hasReacted() =>
      widget.dataService.reactionsMap[widget.note.id]
          ?.any((e) => e.author == widget.currentUserNpub) ??
      false;
  bool _hasReplied() =>
      widget.dataService.repliesMap[widget.note.id]
          ?.any((e) => e.author == widget.currentUserNpub) ??
      false;
  bool _hasReposted() =>
      widget.dataService.repostsMap[widget.note.id]
          ?.any((e) => e.repostedBy == widget.currentUserNpub) ??
      false;

  void _handleZap() {
    setState(() {
      _zapScale = 1.2;
      _isZapGlowing = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _zapScale = 1;
        _isZapGlowing = false;
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("I'm working on it"), duration: Duration(seconds: 1)));
  }

  void _handleReaction() async {
    setState(() {
      _reactionScale = 1.2;
      _isReactionGlowing = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted)
        setState(() {
          _reactionScale = 1;
          _isReactionGlowing = false;
        });
    });
    try {
      await widget.dataService.sendReaction(widget.note.id, '💜');
    } catch (_) {}
  }

  void _handleReply() {
    setState(() {
      _replyScale = 1.2;
      _isReplyGlowing = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted)
        setState(() {
          _replyScale = 1;
          _isReplyGlowing = false;
        });
    });
    showDialog(
        context: context,
        builder: (_) => SendReplyDialog(
            dataService: widget.dataService, noteId: widget.note.id));
  }

  void _handleRepost() async {
    setState(() {
      _repostScale = 1.2;
      _isRepostGlowing = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted)
        setState(() {
          _repostScale = 1;
          _isRepostGlowing = false;
        });
    });
    try {
      await widget.dataService.sendRepost(widget.note);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<List<NoteModel>>(
      valueListenable: widget.notesNotifier,
      builder: (_, notes, __) {
        final note = notes.firstWhere((n) => n.id == widget.note.id,
            orElse: () => widget.note);
        return VisibilityDetector(
          key: Key('note-${note.id}'),
          onVisibilityChanged: (info) {
            if (info.visibleFraction > 0.01) {
              if (!_isVisible) setState(() => _isVisible = true);
              if (widget.index > widget.visibleIndexNotifier.value) {
                widget.visibleIndexNotifier.value = widget.index;
              }
            }
          },
          child: !_isVisible
              ? SizedBox(height: note.estimatedHeight ?? 250)
              : _buildLoadedCard(note),
        );
      },
    );
  }

  Widget _buildLoadedCard(NoteModel n) {
    _ensureParsed(n);
    final parsed = n.parsedContent!;
    return GestureDetector(
      onDoubleTapDown: (_) => _handleReaction(),
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.isRepost && n.repostedBy != null) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: _repostInfo(n.repostedBy!, n.repostTimestamp),
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _authorInfo(n.author),
                  const Spacer(),
                  if (n.hasMedia)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child:
                          Icon(Icons.perm_media, size: 14, color: Colors.grey),
                    ),
                  Text(_formatTimestamp(n.timestamp),
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if ((parsed['textParts'] as List).isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: FutureBuilder<InlineSpan>(
                  future: _buildMentionsAwareSpan(parsed),
                  builder: (_, snap) => snap.hasData
                      ? RichText(text: snap.data!)
                      : const SizedBox(height: 20),
                ),
              ),
            const SizedBox(height: 6),
            if ((parsed['mediaUrls'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: MediaPreviewWidget(
                    mediaUrls: parsed['mediaUrls'] as List<String>),
              ),
            if ((parsed['linkUrls'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: (parsed['linkUrls'] as List<String>)
                      .map((u) => LinkPreviewWidget(url: u))
                      .toList(),
                ),
              ),
            if ((parsed['quoteIds'] as List).isNotEmpty)
              ...List.generate(
                (parsed['quoteIds'] as List).length,
                (i) => QuoteWidget(
                    bech32: parsed['quoteIds'][i],
                    dataService: widget.dataService),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _action(
                    scale: _reactionScale,
                    asset: 'assets/reaction_button.svg',
                    color: _isReactionGlowing || _hasReacted()
                        ? Colors.red.shade400
                        : Colors.white,
                    count: n.reactionCount,
                    onTap: _handleReaction,
                  ),
                  _action(
                    scale: _replyScale,
                    asset: 'assets/reply_button.svg',
                    color: _isReplyGlowing || _hasReplied()
                        ? Colors.blue.shade200
                        : Colors.white,
                    count: n.replyCount,
                    onTap: _handleReply,
                  ),
                  _action(
                    scale: _repostScale,
                    asset: 'assets/repost_button.svg',
                    color: _isRepostGlowing || _hasReposted()
                        ? Colors.green.shade400
                        : Colors.white,
                    count: n.repostCount,
                    onTap: _handleRepost,
                  ),
                  _action(
                    scale: _zapScale,
                    asset: 'assets/zap_button.svg',
                    color: _isZapGlowing ? Colors.amber.shade300 : Colors.white,
                    count: 0,
                    onTap: _handleZap,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 4, thickness: .5, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }
}
