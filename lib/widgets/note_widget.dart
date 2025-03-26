import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import 'package:flutter/services.dart';
import '../models/note_model.dart';
import '../screens/profile_page.dart';
import '../screens/hashtag_page.dart';
import '../services/qiqstr_service.dart';
import 'content_parser.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:linkify/linkify.dart';

class HashtagElement extends LinkableElement {
  HashtagElement(String text) : super(text, text);
}

class HashtagLinkifier extends Linkifier {
  @override
  List<LinkifyElement> parse(
      List<LinkifyElement> elements, LinkifyOptions options) {
    final List<LinkifyElement> ret = [];
    final hashtagRegex = RegExp(r'(#[a-zA-Z0-9_]+)');
    for (final element in elements) {
      if (element is TextElement) {
        final text = element.text;
        final matches = hashtagRegex.allMatches(text);
        if (matches.isEmpty) {
          ret.add(element);
        } else {
          int start = 0;
          for (final match in matches) {
            if (match.start > start) {
              ret.add(TextElement(text.substring(start, match.start)));
            }
            final hashtag = match.group(0)!;
            ret.add(HashtagElement(hashtag));
            start = match.end;
          }
          if (start < text.length) {
            ret.add(TextElement(text.substring(start)));
          }
        }
      } else {
        ret.add(element);
      }
    }
    return ret;
  }
}

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final DataService dataService;

  const NoteWidget({
    super.key,
    required this.note,
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.dataService,
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

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _formatTimestamp(DateTime timestamp) {
    final Duration difference = DateTime.now().difference(timestamp);
    if (difference.inSeconds < 60) return '${difference.inSeconds} seconds ago';
    if (difference.inMinutes < 60) return '${difference.inMinutes} minutes ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    if (difference.inDays < 30)
      return '${(difference.inDays / 7).floor()} weeks ago';
    if (difference.inDays < 365)
      return '${(difference.inDays / 30).floor()} months ago';
    return '${(difference.inDays / 365).floor()} years ago';
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

  void _handleReactionTap() async {
    _animateReactionButton();
    try {
      await widget.dataService.sendReaction(widget.note.id, '💜');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reaction: $e')),
      );
    }
  }

  void _handleDoubleTap(TapDownDetails details) async {
    _handleReactionTap();
  }

  void _handleReplyTap() {
    _animateReplyButton();
    _showReplyDialog();
  }

  void _handleRepostTap() {
    _animateRepostButton();
    _handleRepost();
  }

  Future<void> _handleRepost() async {
    try {
      await widget.dataService.sendRepost(widget.note);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending repost: $e')),
      );
    }
  }

  void _showReplyDialog() {
    showDialog(
      context: context,
      builder: (context) => SendReplyDialog(
        dataService: widget.dataService,
        noteId: widget.note.id,
      ),
    );
  }

  Future<void> _navigateToProfile(String npub) async {
    try {
      final profileData = await widget.dataService.getCachedUserProfile(npub);
      final user = UserModel.fromCachedProfile(npub, profileData);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfilePage(user: user),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
    }
  }

  Widget _buildAuthorInfo(String npub) {
    return FutureBuilder<Map<String, String>>(
      future: widget.dataService.getCachedUserProfile(npub),
      builder: (context, snapshot) {
        String name = 'Anonymous';
        String profileImage = '';
        if (snapshot.hasData) {
          name = snapshot.data!['name'] ?? 'Anonymous';
          profileImage = snapshot.data!['profileImage'] ?? '';
        }
        return Row(
          children: [
            GestureDetector(
              onTap: () => _navigateToProfile(npub),
              child: profileImage.isNotEmpty
                  ? CircleAvatar(
                      radius: 20,
                      backgroundImage: CachedNetworkImageProvider(profileImage),
                      backgroundColor: Colors.transparent,
                    )
                  : const CircleAvatar(
                      radius: 16,
                      child: Icon(Icons.person, size: 16),
                    ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _navigateToProfile(npub),
              child: Text(
                name,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRepostInfo(String npub, DateTime? repostTimestamp) {
    return FutureBuilder<Map<String, String>>(
      future: widget.dataService.getCachedUserProfile(npub),
      builder: (context, snapshot) {
        String name = 'Unknown';
        String profileImage = '';
        if (snapshot.hasData) {
          name = snapshot.data!['name'] ?? 'Unknown';
          profileImage = snapshot.data!['profileImage'] ?? '';
        }
        return GestureDetector(
          onTap: () => _navigateToProfile(npub),
          child: Row(
            children: [
              const Icon(Icons.repeat, size: 16.0, color: Colors.grey),
              const SizedBox(width: 8.0),
              profileImage.isNotEmpty
                  ? CircleAvatar(
                      radius: 12,
                      backgroundImage: CachedNetworkImageProvider(profileImage),
                      backgroundColor: Colors.transparent,
                    )
                  : const CircleAvatar(
                      radius: 12,
                      child: Icon(Icons.person, size: 12),
                    ),
              const SizedBox(width: 6.0),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Reposted by $name',
                      style:
                          const TextStyle(fontSize: 12.0, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (repostTimestamp != null) ...[
                      const SizedBox(width: 6.0),
                      Text(
                        '• ${_formatTimestamp(repostTimestamp)}',
                        style:
                            const TextStyle(fontSize: 12.0, color: Colors.grey),
                      ),
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

  Future<void> _onOpen(LinkableElement link) async {
    if (link is HashtagElement) {
      final String rawHashtag = link.text;
      final String cleanHashtag = rawHashtag.substring(1).toLowerCase();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              HashtagPage(npub: widget.dataService.npub, hashtag: cleanHashtag),
        ),
      );
    } else {
      final Uri url = Uri.parse(link.url);
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch ${link.url}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsedContent = parseContent(widget.note.content);
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTap,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 2.0),
                  child: Row(
                    children: [
                      _buildAuthorInfo(widget.note.author),
                      const Spacer(),
                      Text(
                        _formatTimestamp(widget.note.timestamp),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (widget.note.isRepost && widget.note.repostedBy != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 4.0),
                    child: _buildRepostInfo(
                        widget.note.repostedBy!, widget.note.repostTimestamp),
                  ),
                if (parsedContent['text'] != null &&
                    (parsedContent['text'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 4.0),
                    child: Linkify(
                      text: parsedContent['text'] as String,
                      onOpen: _onOpen,
                      style: TextStyle(
                        fontSize: (parsedContent['text'] as String).length < 21
                            ? 20.0
                            : 15.0,
                      ),
                      linkStyle: const TextStyle(
                        color: Colors.amberAccent,
                        fontStyle: FontStyle.italic,
                      ),
                      linkifiers: [
                        HashtagLinkifier(),
                        UrlLinkifier(),
                        EmailLinkifier(),
                      ],
                    ),
                  ),
                if (parsedContent['mediaUrls'] != null &&
                    (parsedContent['mediaUrls'] as List).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: MediaPreviewWidget(
                      mediaUrls: parsedContent['mediaUrls'] as List<String>,
                    ),
                  ),
                if (parsedContent['linkUrls'] != null &&
                    (parsedContent['linkUrls'] as List).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: LinkPreviewWidget(
                      linkUrls: parsedContent['linkUrls'] as List<String>,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 1.0, end: _reactionScale),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, scale, child) => Transform.scale(
                          scale: scale,
                          child: child,
                        ),
                        child: InkWell(
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: _handleReactionTap,
                          child: Row(
                            children: [
                              SvgPicture.asset(
                                'assets/reaction_button.svg',
                                width: 16.0,
                                height: 16.0,
                                color: _isReactionGlowing
                                    ? Colors.red
                                    : Colors.white,
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                widget.reactionCount.toString(),
                                style: const TextStyle(
                                    fontSize: 12.0, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24.0),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 1.0, end: _replyScale),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, scale, child) => Transform.scale(
                          scale: scale,
                          child: child,
                        ),
                        child: InkWell(
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: _handleReplyTap,
                          child: Row(
                            children: [
                              SvgPicture.asset(
                                'assets/reply_button.svg',
                                width: 16.0,
                                height: 16.0,
                                color: _isReplyGlowing
                                    ? Colors.blue
                                    : Colors.white,
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                widget.replyCount.toString(),
                                style: const TextStyle(
                                    fontSize: 12.0, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24.0),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 1.0, end: _repostScale),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, scale, child) => Transform.scale(
                          scale: scale,
                          child: child,
                        ),
                        child: InkWell(
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: _handleRepostTap,
                          child: Row(
                            children: [
                              SvgPicture.asset(
                                'assets/repost_button.svg',
                                width: 16.0,
                                height: 16.0,
                                color: _isRepostGlowing
                                    ? Colors.green
                                    : Colors.white,
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                widget.repostCount.toString(),
                                style: const TextStyle(
                                    fontSize: 12.0, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6.0),
                  child:
                      Divider(height: 0.5, thickness: 0.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
