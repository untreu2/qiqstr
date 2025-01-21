import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:qiqstr/widgets/link_preview_widget.dart';
import 'package:qiqstr/widgets/media_preview_widget.dart';
import '../models/note_model.dart';
import '../screens/profile_page.dart';
import '../services/qiqstr_service.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final DataService dataService; 

  const NoteWidget({
    Key? key,
    required this.note,
    required this.reactionCount,
    required this.replyCount,
    required this.dataService, 
  }) : super(key: key);

  @override
  _NoteWidgetState createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget> with SingleTickerProviderStateMixin {
  late AnimationController _highlightController;
  late Animation<double> _highlightAnimation;

  final PageController _pageController = PageController();

  bool _isGlowing = false;

  @override
  void initState() {
    super.initState();

    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _highlightAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _highlightController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _highlightController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _parseContent(String content) {
    final RegExp mediaRegExp =
        RegExp(r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4|mov))', caseSensitive: false);
    final Iterable<RegExpMatch> mediaMatches = mediaRegExp.allMatches(content);
    final List<String> mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();

    final RegExp linkRegExp = RegExp(r'(https?:\/\/\S+)', caseSensitive: false);
    final Iterable<RegExpMatch> linkMatches = linkRegExp.allMatches(content);
    final List<String> linkUrls = linkMatches
        .map((m) => m.group(0)!)
        .where((url) =>
            !mediaUrls.contains(url) &&
            !url.toLowerCase().endsWith('.mp4') &&
            !url.toLowerCase().endsWith('.mov'))
        .toList();

    final String text = content
        .replaceAll(mediaRegExp, '')
        .replaceAll(linkRegExp, '')
        .trim();

    return {
      'text': text,
      'mediaUrls': mediaUrls,
      'linkUrls': linkUrls,
    };
  }

  String _formatTimestamp(DateTime timestamp) {
    final Duration difference = DateTime.now().difference(timestamp);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} seconds ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else {
      return '${(difference.inDays / 365).floor()} years ago';
    }
  }

  void _showHighlight() {
    _highlightController.forward(from: 0.0).then((_) => _highlightController.reverse());
  }

  void _handleDoubleTap(TapDownDetails details) async {
    setState(() {
      _isGlowing = true;
    });
    try {
      await widget.dataService.sendReaction(widget.note.id, '💜');
      setState(() {
      });
    } catch (e) {
      print('Error sending reaction: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reaction: $e')),
      );
    } finally {
      _showHighlight();
      Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _isGlowing = false;
          });
        }
      });
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
      _showReplyDialog();
      _showHighlight();
    }
  }

  void _showReplyDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) => SendReplyDialog(
        dataService: widget.dataService,
        noteId: widget.note.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsedContent = _parseContent(widget.note.content);

    return GestureDetector(
      onDoubleTapDown: _handleDoubleTap,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: AnimatedBuilder(
        animation: _highlightAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: 1 - (_highlightAnimation.value * 0.05),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(_highlightAnimation.value * 0.8),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: child,
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                ProfilePage(npub: widget.note.author)),
                      );
                    },
                    child: widget.note.authorProfileImage.isNotEmpty
                        ? CircleAvatar(
                            radius: 20,
                            backgroundImage: CachedNetworkImageProvider(
                                widget.note.authorProfileImage),
                            backgroundColor: Colors.transparent,
                          )
                        : const CircleAvatar(
                            radius: 16,
                            child: Icon(Icons.person, size: 16),
                          ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                ProfilePage(npub: widget.note.author)),
                      );
                    },
                    child: Text(
                      widget.note.authorName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTimestamp(widget.note.timestamp),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (widget.note.isRepost && widget.note.repostedBy != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ProfilePage(npub: widget.note.repostedBy!),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(
                        Icons.repeat,
                        size: 16.0,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8.0),
                      widget.note.repostedByProfileImage != null &&
                              widget.note.repostedByProfileImage!.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ProfilePage(npub: widget.note.repostedBy!),
                                  ),
                                );
                              },
                              child: CircleAvatar(
                                radius: 12,
                                backgroundImage: CachedNetworkImageProvider(
                                    widget.note.repostedByProfileImage!),
                                backgroundColor: Colors.transparent,
                              ),
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
                              'Reposted by ${widget.note.repostedByName ?? "Unknown"}',
                              style: const TextStyle(
                                fontSize: 12.0,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.note.repostTimestamp != null) ...[
                              const SizedBox(width: 6.0),
                              Text(
                                '• ${_formatTimestamp(widget.note.repostTimestamp!)}',
                                style: const TextStyle(
                                  fontSize: 12.0,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (parsedContent['text'] != null &&
                (parsedContent['text'] as String).isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                child: Text(
                  parsedContent['text'],
                  style: TextStyle(
                    fontSize:
                        (parsedContent['text'] as String).length < 21
                            ? 20.0
                            : 15.0,
                    fontWeight: FontWeight.normal,
                  ),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 16.0,
                        color: _isGlowing ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        widget.reactionCount.toString(),
                        style: const TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24.0),
                  Row(
                    children: [
                      const Icon(
                        Icons.reply,
                        size: 16.0,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        widget.replyCount.toString(),
                        style: const TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6.0),
              child: Divider(
                height: 0.5, 
                thickness: 0.5,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
