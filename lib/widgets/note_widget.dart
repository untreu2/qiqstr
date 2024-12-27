import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:any_link_preview/any_link_preview.dart';
import '../models/note_model.dart';
import '../screens/note_detail_page.dart';
import '../screens/profile_page.dart';
import 'video_preview.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final Function(String)? onSendReaction;
  final Function(String)? onShowReplyDialog;
  final Function()? onAuthorTap;
  final Function()? onRepostedByTap;
  final Function()? onNoteTap;

  const NoteWidget({
    Key? key,
    required this.note,
    this.onSendReaction,
    this.onShowReplyDialog,
    this.onAuthorTap,
    this.onRepostedByTap,
    this.onNoteTap,
  }) : super(key: key);

  @override
  _NoteWidgetState createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget> with SingleTickerProviderStateMixin {
  bool _isGlowing = false;
  bool _isSwiped = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _parseContent(String content) {
    final RegExp mediaRegExp =
        RegExp(r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))', caseSensitive: false);
    final Iterable<RegExpMatch> mediaMatches = mediaRegExp.allMatches(content);

    final List<String> mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();

    final RegExp linkRegExp = RegExp(r'(https?:\/\/\S+)', caseSensitive: false);
    final Iterable<RegExpMatch> linkMatches = linkRegExp.allMatches(content);

    final List<String> linkUrls = linkMatches
        .map((m) => m.group(0)!)
        .where((url) => !mediaUrls.contains(url) && !url.toLowerCase().endsWith('.mp4'))
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

  Widget _buildMediaPreviews(List<String> mediaUrls) {
    return Column(
      children: mediaUrls.map((url) {
        if (url.toLowerCase().endsWith('.mp4')) {
          return VideoPreview(url: url);
        } else {
          return CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error),
            fit: BoxFit.cover,
            width: double.infinity,
          );
        }
      }).toList(),
    );
  }

  Widget _buildLinkPreviews(List<String> linkUrls) {
    return Column(
      children: linkUrls.map((url) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: AnyLinkPreview(
            link: url,
            displayDirection: UIDirection.uiDirectionVertical,
            cache: Duration(days: 7),
            backgroundColor: Colors.black87,
            errorWidget: Container(),
            bodyMaxLines: 5,
            bodyTextOverflow: TextOverflow.ellipsis,
            titleStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
            bodyStyle: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
  }

  void _handleDoubleTap() {
    if (widget.onSendReaction != null) {
      widget.onSendReaction!(widget.note.id);
      _triggerGlow();
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
      if (widget.onShowReplyDialog != null) {
        widget.onShowReplyDialog!(widget.note.id);
        _triggerSwipe();
      }
    }
  }

  void _triggerGlow() {
    setState(() {
      _isGlowing = true;
    });
    Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isGlowing = false;
        });
      }
    });
  }

  void _triggerSwipe() {
    setState(() {
      _isSwiped = true;
    });
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isSwiped = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final parsedContent = _parseContent(widget.note.content);

    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          border: _isGlowing
              ? Border.all(color: Colors.white, width: 4.0)
              : _isSwiped
                  ? Border.all(color: Colors.white, width: 4.0)
                  : null,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.note.isRepost)
              Padding(
                padding: const EdgeInsets.only(left: 16.0, top: 8.0),
                child: GestureDetector(
                  onTap: widget.onRepostedByTap ??
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(npub: widget.note.repostedBy!),
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
                      SizedBox(width: 4.0),
                      Text(
                        'Reposted by ${widget.note.repostedByName ?? "Unknown"}',
                        style: const TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      if (widget.note.repostTimestamp != null)
                        Text(
                          'on ${_formatTimestamp(widget.note.repostTimestamp!)}',
                          style: const TextStyle(
                            fontSize: 12.0,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            GestureDetector(
              onTap: widget.onAuthorTap ??
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ProfilePage(npub: widget.note.author)),
                    );
                  },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
                child: Row(
                  children: [
                    widget.note.authorProfileImage.isNotEmpty
                        ? CircleAvatar(
                            radius: 18,
                            child: CachedNetworkImage(
                              imageUrl: widget.note.authorProfileImage,
                              placeholder: (context, url) =>
                                  const Center(child: CircularProgressIndicator()),
                              errorWidget: (context, url, error) => const Icon(Icons.error),
                              imageBuilder: (context, imageProvider) => ClipOval(
                                child: Image(
                                  image: imageProvider,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          )
                        : const CircleAvatar(
                            radius: 12,
                            child: Icon(Icons.person, size: 16),
                          ),
                    const SizedBox(width: 12),
                    Text(
                      widget.note.authorName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: widget.onNoteTap ??
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NoteDetailPage(
                          note: widget.note,
                        ),
                      ),
                    );
                  },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (parsedContent['text'] != null && parsedContent['text'] != '')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        parsedContent['text'],
                        style: TextStyle(
                          fontSize: parsedContent['text'].length < 34 ? 20.0 : 15.0,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  if (parsedContent['mediaUrls'] != null && parsedContent['mediaUrls'].isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: _buildMediaPreviews(parsedContent['mediaUrls']),
                    ),
                  if (parsedContent['linkUrls'] != null && parsedContent['linkUrls'].isNotEmpty)
                    _buildLinkPreviews(parsedContent['linkUrls']),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Text(
                      _formatTimestamp(widget.note.timestamp),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Divider(
                color: Colors.grey.shade400,
                thickness: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
