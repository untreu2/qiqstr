import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import '../models/note_model.dart';
import '../screens/profile_page.dart';
import '../services/qiqstr_service.dart';
import 'content_parser.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final DataService dataService;
  final String currentUserNpub;

  const NoteWidget({
    super.key,
    required this.note,
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.dataService,
    required this.currentUserNpub,
  });

  @override
  _NoteWidgetState createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget> {
  bool _isReactionGlowing = false;
  bool _isReplyGlowing = false;
  bool _isRepostGlowing = false;

  double _reactionScale = 1.0;
  double _replyScale = 1.0;
  double _repostScale = 1.0;

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

  Future<String?> _fetchUsername(String id) async {
    try {
      String? pubHex;
      if (id.startsWith('npub1')) {
        pubHex = decodeBasicBech32(id, 'npub');
      } else if (id.startsWith('nprofile1')) {
        pubHex = decodeTlvBech32Full(id, 'nprofile')['type_0_main'];
      }
      if (pubHex != null) {
        final data = await widget.dataService.getCachedUserProfile(pubHex);
        final user = UserModel.fromCachedProfile(pubHex, data);
        if (user.name.isNotEmpty) return user.name;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _navigateToMentionProfile(String id) async {
    try {
      String? pubHex;
      if (id.startsWith('npub1')) {
        pubHex = decodeBasicBech32(id, 'npub');
      } else if (id.startsWith('nprofile1')) {
        pubHex = decodeTlvBech32Full(id, 'nprofile')['type_0_main'];
      }
      if (pubHex == null) return;
      final data = await widget.dataService.getCachedUserProfile(pubHex);
      final user = UserModel.fromCachedProfile(pubHex, data);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(user: user)),
      );
    } catch (_) {}
  }

  Widget _buildContentText(Map<String, dynamic> parsed) {
    final parts = parsed['textParts'] as List<Map<String, dynamic>>;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts.map((p) {
        if (p['type'] == 'text') {
          final txt = p['text'] as String;
          return Linkify(
            text: txt,
            onOpen: _onOpen,
            style: TextStyle(
              fontSize: txt.length < 21 ? 20 : 15.5,
              color: Colors.white,
            ),
            linkStyle: const TextStyle(
              color: Colors.amberAccent,
              fontStyle: FontStyle.italic,
            ),
          );
        }
        return FutureBuilder<String?>(
          future: _fetchUsername(p['id']),
          builder: (_, snap) {
            final disp = snap.data?.isNotEmpty == true
                ? '@${snap.data}'
                : '@${p['id'].substring(0, 8)}...';
            return GestureDetector(
              onTap: () => _navigateToMentionProfile(p['id']),
              child: Text(
                disp,
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  void _animateReactionButton() {
    setState(() {
      _reactionScale = 1.2;
      _isReactionGlowing = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _reactionScale = 1.0;
          _isReactionGlowing = false;
        });
      }
    });
  }

  void _animateReplyButton() {
    setState(() {
      _replyScale = 1.2;
      _isReplyGlowing = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _replyScale = 1.0;
          _isReplyGlowing = false;
        });
      }
    });
  }

  void _animateRepostButton() {
    setState(() {
      _repostScale = 1.2;
      _isRepostGlowing = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _repostScale = 1.0;
          _isRepostGlowing = false;
        });
      }
    });
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

  void _handleReactionTap() async {
    _animateReactionButton();
    try {
      await widget.dataService.sendReaction(widget.note.id, '💜');
    } catch (_) {}
  }

  void _handleReplyTap() {
    _animateReplyButton();
    showDialog(
      context: context,
      builder: (_) => SendReplyDialog(
          dataService: widget.dataService, noteId: widget.note.id),
    );
  }

  void _handleRepostTap() async {
    _animateRepostButton();
    try {
      await widget.dataService.sendRepost(widget.note);
    } catch (_) {}
  }

  Future<void> _onOpen(LinkableElement link) async {
    final url = Uri.parse(link.url);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _navigateToProfile(String npub) async {
    try {
      final data = await widget.dataService.getCachedUserProfile(npub);
      final user = UserModel.fromCachedProfile(npub, data);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(user: user)),
      );
    } catch (_) {}
  }

  Widget _buildAuthorInfo(String npub) {
    return FutureBuilder<Map<String, String>>(
      future: widget.dataService.getCachedUserProfile(npub),
      builder: (_, snap) {
        String name = 'Anonymous';
        String nip05 = '';
        String img = '';
        if (snap.hasData) {
          final u = UserModel.fromCachedProfile(npub, snap.data!);
          name = u.name;
          nip05 = u.nip05;
          img = u.profileImage;
        }
        final tr = name.length > 25 ? '${name.substring(0, 25)}...' : name;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _navigateToProfile(npub),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: CircleAvatar(
                  radius: 20,
                  backgroundImage:
                      img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                  backgroundColor:
                      img.isEmpty ? Colors.grey : Colors.transparent,
                  child: img.isEmpty
                      ? const Icon(Icons.person, size: 20, color: Colors.white)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _navigateToProfile(npub),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (nip05.isNotEmpty)
                    Text(
                      nip05,
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRepostInfo(String npub, DateTime? ts) {
    return FutureBuilder<Map<String, String>>(
      future: widget.dataService.getCachedUserProfile(npub),
      builder: (_, snap) {
        String name = 'Unknown';
        String img = '';
        if (snap.hasData) {
          name = snap.data!['name'] ?? 'Unknown';
          img = snap.data!['profileImage'] ?? '';
        }
        return GestureDetector(
          onTap: () => _navigateToProfile(npub),
          child: Row(
            children: [
              const Icon(Icons.repeat, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              img.isNotEmpty
                  ? CircleAvatar(
                      radius: 12,
                      backgroundImage: CachedNetworkImageProvider(img),
                      backgroundColor: Colors.transparent,
                    )
                  : const CircleAvatar(
                      radius: 12,
                      child: Icon(Icons.person, size: 12),
                    ),
              const SizedBox(width: 6),
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

  Widget _buildInteractionAvatars() {
    final set = <String>{};
    set.addAll((widget.dataService.reactionsMap[widget.note.id] ?? [])
        .map((e) => e.author));
    set.addAll((widget.dataService.repliesMap[widget.note.id] ?? [])
        .map((e) => e.author));
    set.addAll((widget.dataService.repostsMap[widget.note.id] ?? [])
        .map((e) => e.repostedBy));
    if (set.isEmpty) return const SizedBox.shrink();
    final list = set.toList();
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: list.length,
      itemBuilder: (_, i) {
        final npub = list[i];
        return FutureBuilder<Map<String, String>>(
          future: widget.dataService.getCachedUserProfile(npub),
          builder: (_, snap) {
            String img = '';
            if (snap.hasData) img = snap.data!['profileImage'] ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _navigateToProfile(npub),
                child: CircleAvatar(
                  radius: 14,
                  backgroundImage:
                      img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                  backgroundColor:
                      img.isEmpty ? Colors.grey : Colors.transparent,
                  child: img.isEmpty
                      ? const Icon(Icons.person, size: 16, color: Colors.white)
                      : null,
                ),
              ),
            );
          },
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
            SvgPicture.asset(svg, width: 20, height: 20, color: color),
            const SizedBox(width: 4),
            Text('$count',
                style: const TextStyle(fontSize: 13, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseContent(widget.note.content);
    return GestureDetector(
      onDoubleTapDown: (_) => _handleReactionTap(),
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _buildAuthorInfo(widget.note.author),
                  const Spacer(),
                  Text(_formatTimestamp(widget.note.timestamp),
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (widget.note.isRepost && widget.note.repostedBy != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: _buildRepostInfo(
                    widget.note.repostedBy!, widget.note.repostTimestamp),
              ),
            if ((parsed['textParts'] as List).isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: _buildContentText(parsed),
              ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _buildAction(
                    scale: _reactionScale,
                    svg: 'assets/reaction_button.svg',
                    color: _isReactionGlowing || _hasReacted()
                        ? Colors.red.shade400
                        : Colors.white,
                    count: widget.reactionCount,
                    onTap: _handleReactionTap,
                  ),
                  const SizedBox(width: 16),
                  _buildAction(
                    scale: _replyScale,
                    svg: 'assets/reply_button.svg',
                    color: _isReplyGlowing || _hasReplied()
                        ? Colors.blue.shade200
                        : Colors.white,
                    count: widget.replyCount,
                    onTap: _handleReplyTap,
                  ),
                  const SizedBox(width: 16),
                  _buildAction(
                    scale: _repostScale,
                    svg: 'assets/repost_button.svg',
                    color: _isRepostGlowing || _hasReposted()
                        ? Colors.green.shade400
                        : Colors.white,
                    count: widget.repostCount,
                    onTap: _handleRepostTap,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child:
                        SizedBox(height: 36, child: _buildInteractionAvatars()),
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
