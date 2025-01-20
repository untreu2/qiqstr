import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../models/note_model.dart';
import '../screens/profile_page.dart';
import '../widgets/video_preview.dart';
import '../widgets/photo_viewer_widget.dart';
import '../services/qiqstr_service.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final DataService dataService; 

  const NoteWidget({
    Key? key,
    required this.note,
    required this.reactionCount,
    required this.replyCount,
    required this.dataService, required this.repostCount, 
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

  Widget _buildMediaPreviews(List<String> mediaUrls) {
    if (mediaUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<String> imageUrls = mediaUrls
        .where((url) =>
            url.toLowerCase().endsWith('.jpg') ||
            url.toLowerCase().endsWith('.jpeg') ||
            url.toLowerCase().endsWith('.png') ||
            url.toLowerCase().endsWith('.webp') ||
            url.toLowerCase().endsWith('.gif'))
        .toList();

    final List<String> videoUrls = mediaUrls
        .where((url) =>
            url.toLowerCase().endsWith('.mp4') ||
            url.toLowerCase().endsWith('.mov'))
        .toList();

    List<String> allImageUrls = imageUrls;

    if (allImageUrls.isEmpty && videoUrls.isNotEmpty) {
      allImageUrls = videoUrls;
    }

    if (allImageUrls.length == 1) {
      String url = allImageUrls.first;
      if (videoUrls.contains(url)) {
        return VP(url: url);
      } else {
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PhotoViewerWidget(
                  imageUrls: imageUrls,
                  initialIndex: 0,
                ),
              ),
            );
          },
          child: AspectRatio(
            aspectRatio: 1.0,
            child: CachedNetworkImage(
              imageUrl: url,
              placeholder: (context, url) =>
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              errorWidget: (context, url, error) =>
                  const Icon(Icons.error, size: 20),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        );
      }
    } else {
      return Column(
        children: [
          SizedBox(
            height: 300,
            child: PageView.builder(
              controller: _pageController,
              itemCount: allImageUrls.length,
              onPageChanged: (index) {
                setState(() {});
              },
              itemBuilder: (context, index) {
                String url = allImageUrls[index];
                bool isVideo = videoUrls.contains(url);
                return GestureDetector(
                  onTap: isVideo
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PhotoViewerWidget(
                                imageUrls: imageUrls,
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: isVideo
                          ? Stack(
                              children: [
                                CachedNetworkImage(
                                  imageUrl: url,
                                  placeholder: (context, url) => const Center(
                                      child:
                                          CircularProgressIndicator(strokeWidth: 2)),
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.error, size: 20),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                                const Center(
                                  child: Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.white70,
                                    size: 50,
                                  ),
                                ),
                              ],
                            )
                          : AspectRatio(
                              aspectRatio: 1.0,
                              child: CachedNetworkImage(
                                imageUrl: url,
                                placeholder: (context, url) => const Center(
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2)),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error, size: 20),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4.0),
          SmoothPageIndicator(
            controller: _pageController,
            count: allImageUrls.length,
            effect: const WormEffect(
              activeDotColor: Colors.grey,
              dotHeight: 6.0,
              dotWidth: 6.0,
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
          padding:
              const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
          child: AnyLinkPreview(
            link: url,
            displayDirection: UIDirection.uiDirectionVertical,
            cache: const Duration(days: 7),
            backgroundColor: Colors.grey[900],
            errorWidget: Container(),
            bodyMaxLines: 3,
            bodyTextOverflow: TextOverflow.ellipsis,
            titleStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.white,
            ),
            bodyStyle: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";
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
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
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
                            radius: 16,
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
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 16.0,
                        color: _isGlowing ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 2.0),
                      Text(
                        widget.reactionCount.toString(),
                        style: const TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8.0),
                  Row(
                    children: [
                      const Icon(
                        Icons.reply,
                        size: 16.0,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 2.0),
                      Text(
                        widget.replyCount.toString(),
                        style: const TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey,
                        ),  
                      ),
                          const SizedBox(width: 8.0),
    const Icon(
      Icons.repeat,
      size: 16.0,
      color: Colors.grey,
    ),
    const SizedBox(width: 2.0),
    Text(
      widget.repostCount.toString(),
      style: const TextStyle(fontSize: 12.0, color: Colors.grey),
    ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            size: 14.0,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            'By ${widget.note.repostedByName ?? "Unknown"}',
                            style: const TextStyle(
                              fontSize: 12.0,
                              color: Colors.grey,
                            ),
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
                    child: _buildMediaPreviews(
                        parsedContent['mediaUrls'] as List<String>),
                  ),
                if (parsedContent['linkUrls'] != null &&
                    (parsedContent['linkUrls'] as List).isNotEmpty)
                  _buildLinkPreviews(
                      parsedContent['linkUrls'] as List<String>),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
                  child: Text(
                    _formatTimestamp(widget.note.timestamp),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6.0),
              child: Divider(height: 1, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
