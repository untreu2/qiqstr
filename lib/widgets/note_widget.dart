import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../models/note_model.dart';
import '../screens/note_detail_page.dart';
import '../screens/profile_page.dart';
import 'video_preview.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final Function(String)? onSendReaction;
  final Function(String)? onShowReplyDialog;
  final Function()? onAuthorTap;
  final Function()? onRepostedByTap;
  final Function()? onNoteTap;

  const NoteWidget({
    Key? key,
    required this.note,
    required this.reactionCount,
    required this.replyCount,
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
  final PageController _pageController = PageController();

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
            !mediaUrls.contains(url) && !url.toLowerCase().endsWith('.mp4'))
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
    if (mediaUrls.isEmpty) {
      return SizedBox.shrink();
    }

    if (mediaUrls.length == 1) {
      String url = mediaUrls.first;
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
    } else {
      return Column(
        children: [
          SizedBox(
            height: 500,
            child: PageView.builder(
              controller: _pageController,
              itemCount: mediaUrls.length,
              onPageChanged: (index) {
                setState(() {
                });
              },
              itemBuilder: (context, index) {
                String url = mediaUrls[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      color: Colors.black12,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.0),
                      child: url.toLowerCase().endsWith('.mp4')
                          ? VideoPreview(url: url)
                          : CachedNetworkImage(
                              imageUrl: url,
                              placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                              errorWidget: (context, url, error) => const Icon(Icons.error),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8.0),
          SmoothPageIndicator(
            controller: _pageController,
            count: mediaUrls.length,
            effect: WormEffect(
              activeDotColor: Colors.blueAccent,
              dotHeight: 8.0,
              dotWidth: 8.0,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildLinkPreviews(List<String> linkUrls) {
    return Column(
      children: linkUrls.map((url) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: AnyLinkPreview(
            link: url,
            displayDirection: UIDirection.uiDirectionVertical,
            cache: const Duration(days: 7),
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
              ? Border.all(color: Colors.pinkAccent, width: 2.0)
              : _isSwiped
                  ? Border.all(color: Colors.blueAccent, width: 2.0)
                  : null,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: widget.onAuthorTap ??
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ProfilePage(npub: widget.note.author)),
                          );
                        },
                    child: widget.note.authorProfileImage.isNotEmpty
                        ? CircleAvatar(
                            radius: 18,
                            backgroundImage: CachedNetworkImageProvider(widget.note.authorProfileImage),
                            backgroundColor: Colors.transparent,
                          )
                        : const CircleAvatar(
                            radius: 18,
                            child: Icon(Icons.person, size: 18),
                          ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: widget.onAuthorTap ??
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ProfilePage(npub: widget.note.author)),
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
                  Row(
                    children: [
                      Icon(
                        Icons.favorite_border,
                        size: 20.0,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        widget.reactionCount.toString(),
                        style: const TextStyle(
                          fontSize: 14.0,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16.0),
                  Row(
                    children: [
                      Icon(
                        Icons.reply,
                        size: 20.0,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        widget.replyCount.toString(),
                        style: const TextStyle(
                          fontSize: 14.0,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
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
                  if (widget.note.isRepost && widget.note.repostedBy != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, top: 4.0),
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
                            const SizedBox(width: 4.0),
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
                  if (parsedContent['text'] != null && (parsedContent['text'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        parsedContent['text'],
                        style: TextStyle(
                          fontSize: (parsedContent['text'] as String).length < 34 ? 20.0 : 16.0,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  if (parsedContent['mediaUrls'] != null && (parsedContent['mediaUrls'] as List).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: _buildMediaPreviews(parsedContent['mediaUrls'] as List<String>),
                    ),
                  if (parsedContent['linkUrls'] != null && (parsedContent['linkUrls'] as List).isNotEmpty)
                    _buildLinkPreviews(parsedContent['linkUrls'] as List<String>),
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(height: 1, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
