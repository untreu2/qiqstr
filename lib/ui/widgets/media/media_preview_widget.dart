import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'photo_viewer_widget.dart';
import 'video_preview.dart';

class MediaPreviewWidget extends StatefulWidget {
  final List<String> mediaUrls;
  final String? authorProfileImageUrl;

  const MediaPreviewWidget({
    super.key,
    required this.mediaUrls,
    this.authorProfileImageUrl,
  });

  static const double borderRadius = 12.0;

  @override
  State<MediaPreviewWidget> createState() => _MediaPreviewWidgetState();
}

class _MediaPreviewWidgetState extends State<MediaPreviewWidget> {
  late final List<String> _videoUrls;
  late final List<String> _imageUrls;
  late final bool _hasVideo;
  late final bool _hasImages;

  @override
  void initState() {
    super.initState();
    _processUrls();
  }

  void _processUrls() {
    _videoUrls = widget.mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.mp4') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.mov');
    }).toList();

    _imageUrls = widget.mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif');
    }).toList();

    _hasVideo = _videoUrls.isNotEmpty;
    _hasImages = _imageUrls.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaUrls.isEmpty) return const SizedBox.shrink();

    if (_hasVideo) {
      return VP(
        url: _videoUrls.first,
        authorProfileImageUrl: widget.authorProfileImageUrl,
      );
    }

    if (!_hasImages) return const SizedBox.shrink();

    return _buildMediaGrid(context, _imageUrls);
  }

  Widget _buildMediaGrid(BuildContext context, List<String> imageUrls) {
    if (imageUrls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(MediaPreviewWidget.borderRadius),
        child: _buildImage(
          context,
          imageUrls[0],
          0,
          imageUrls,
          fit: BoxFit.cover,
        ),
      );
    } else if (imageUrls.length == 2) {
      return Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(MediaPreviewWidget.borderRadius),
                bottomLeft: Radius.circular(MediaPreviewWidget.borderRadius),
              ),
              child: _buildImage(
                context,
                imageUrls[0],
                0,
                imageUrls,
                aspectRatio: 3 / 4,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(MediaPreviewWidget.borderRadius),
                bottomRight: Radius.circular(MediaPreviewWidget.borderRadius),
              ),
              child: _buildImage(
                context,
                imageUrls[1],
                1,
                imageUrls,
                aspectRatio: 3 / 4,
              ),
            ),
          ),
        ],
      );
    } else if (imageUrls.length == 3) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final spacing = 4.0;
          final rightWidth = (totalWidth - spacing) / 3;
          final leftWidth = (totalWidth - spacing) * 2 / 3;
          final rightImageHeight = rightWidth;
          final totalRightHeight = rightImageHeight * 2 + spacing;
          final leftAspectRatio = leftWidth / totalRightHeight;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(MediaPreviewWidget.borderRadius),
                    bottomLeft:
                        Radius.circular(MediaPreviewWidget.borderRadius),
                  ),
                  child: _buildImage(
                    context,
                    imageUrls[0],
                    0,
                    imageUrls,
                    aspectRatio: leftAspectRatio,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topRight:
                            Radius.circular(MediaPreviewWidget.borderRadius),
                      ),
                      child: _buildImage(
                        context,
                        imageUrls[1],
                        1,
                        imageUrls,
                        aspectRatio: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomRight:
                            Radius.circular(MediaPreviewWidget.borderRadius),
                      ),
                      child: _buildImage(
                        context,
                        imageUrls[2],
                        2,
                        imageUrls,
                        aspectRatio: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    } else {
      int itemCount = imageUrls.length >= 4 ? 4 : imageUrls.length;

      return ClipRRect(
        borderRadius: BorderRadius.circular(MediaPreviewWidget.borderRadius),
        child: GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            return Stack(
              children: [
                _buildImage(
                  context,
                  imageUrls[index],
                  index,
                  imageUrls,
                  aspectRatio: 1.0,
                ),
                if (index == 3 && imageUrls.length > 4)
                  Container(
                    color: context.colors.overlayDark,
                    alignment: Alignment.center,
                    child: Text(
                      '+${imageUrls.length - 4}',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }
  }

  Widget _buildImage(
    BuildContext context,
    String url,
    int index,
    List<String> allUrls, {
    double? aspectRatio,
    BoxFit fit = BoxFit.cover,
    bool useAspectRatio = true,
    bool limitResolution = true,
  }) {
    Widget image = CachedNetworkImage(
      key: ValueKey('media_${url.hashCode}_$index'),
      imageUrl: url,
      fit: fit,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      maxHeightDiskCache: limitResolution ? 1500 : null,
      maxWidthDiskCache: limitResolution ? 1500 : null,
      memCacheWidth: limitResolution ? 1500 : null,
      placeholder: (context, url) => AspectRatio(
        aspectRatio: aspectRatio ?? 1.0,
        child: Container(
          color: context.colors.surfaceTransparent,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: context.colors.surfaceTransparent,
        child: Icon(Icons.broken_image, color: context.colors.textSecondary),
      ),
    );

    if (useAspectRatio && aspectRatio != null) {
      image = AspectRatio(aspectRatio: aspectRatio, child: image);
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          Navigator.of(context, rootNavigator: true).push(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 300),
              reverseTransitionDuration: const Duration(milliseconds: 200),
              pageBuilder: (_, __, ___) => PhotoViewerWidget(
                imageUrls: allUrls,
                initialIndex: index,
              ),
              transitionsBuilder: (_, animation, __, child) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
                    child: child,
                  ),
                );
              },
            ),
          );
        },
        child: image,
      ),
    );
  }
}
