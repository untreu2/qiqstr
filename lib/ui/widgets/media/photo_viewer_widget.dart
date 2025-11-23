import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../common/snackbar_widget.dart';

class PhotoViewerWidget extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const PhotoViewerWidget({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<PhotoViewerWidget> createState() => _PhotoViewerWidgetState();
}

class _PhotoViewerWidgetState extends State<PhotoViewerWidget> {
  late PageController _pageController;
  late int currentIndex;
  bool _didPrecacheImages = false;
  bool _isDownloading = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didPrecacheImages) {
      for (var imageUrl in widget.imageUrls) {
        precacheImage(CachedNetworkImageProvider(imageUrl), context);
      }
      _didPrecacheImages = true;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _downloadImage(String imageUrl) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      final saved = await GallerySaver.saveImage(imageUrl);

      if (mounted) {
        if (saved == true) {
          AppSnackbar.success(context, 'Image saved to gallery');
        } else {
          AppSnackbar.error(context, 'Failed to save image to gallery');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Download error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 100) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1.0 - (_dragOffset.abs() / 300).clamp(0.0, 1.0)),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.black,
              ),
            ),
          Transform.translate(
            offset: Offset(0, _dragOffset),
            child: PhotoViewGallery.builder(
              itemCount: widget.imageUrls.length,
              pageController: _pageController,
              onPageChanged: (index) {
                setState(() {
                  currentIndex = index;
                });
              },
              builder: (context, index) {
                final imageUrl = widget.imageUrls[index];
                return PhotoViewGalleryPageOptions(
                  imageProvider: CachedNetworkImageProvider(imageUrl),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                  heroAttributes: PhotoViewHeroAttributes(tag: imageUrl),
                  basePosition: Alignment.center,
                );
              },
              loadingBuilder: (context, event) => const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              backgroundDecoration: const BoxDecoration(
                color: Colors.transparent,
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Builder(
              builder: (context) {
                final colors = context.colors;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.8),
                          border: Border.all(
                            color: colors.border.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 48),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '${currentIndex + 1} / ${widget.imageUrls.length}',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            IconActionButton(
                              icon: _isDownloading ? CarbonIcons.download : CarbonIcons.download,
                              iconColor: colors.textPrimary,
                              onPressed: _isDownloading ? null : () => _downloadImage(widget.imageUrls[currentIndex]),
                              size: ButtonSize.small,
                            ),
                            IconActionButton(
                              icon: CarbonIcons.close,
                              iconColor: colors.textPrimary,
                              onPressed: () => Navigator.of(context).pop(),
                              size: ButtonSize.small,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      ),
    );
  }
}
