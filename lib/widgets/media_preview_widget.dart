import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/photo_viewer_widget.dart';
import 'video_preview.dart';

class MediaPreviewWidget extends StatelessWidget {
  final List<String> mediaUrls;

  const MediaPreviewWidget({Key? key, required this.mediaUrls})
      : super(key: key);

  static const double borderRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    if (mediaUrls.isEmpty) return const SizedBox.shrink();

    final videoUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.mp4') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.mov');
    }).toList();

    if (videoUrls.isNotEmpty) {
      final videoUrl = videoUrls.first;

      return VP(url: videoUrl);
    }

    final imageUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif');
    }).toList();

    if (imageUrls.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: _buildMediaGrid(context, imageUrls),
    );
  }

  Widget _buildMediaGrid(BuildContext context, List<String> imageUrls) {
    if (imageUrls.length == 1) {
      return _buildImage(
        context,
        imageUrls[0],
        0,
        imageUrls,
        useAspectRatio: false,
        fit: BoxFit.contain,
      );
    } else if (imageUrls.length == 2) {
      return Row(
        children: [
          Expanded(
            child: _buildImage(
              context,
              imageUrls[0],
              0,
              imageUrls,
              aspectRatio: 1,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildImage(
              context,
              imageUrls[1],
              1,
              imageUrls,
              aspectRatio: 1,
            ),
          ),
        ],
      );
    } else if (imageUrls.length == 3) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildImage(
              context,
              imageUrls[0],
              0,
              imageUrls,
              aspectRatio: 1,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                _buildImage(
                  context,
                  imageUrls[1],
                  1,
                  imageUrls,
                  aspectRatio: 1,
                ),
                const SizedBox(height: 4),
                _buildImage(
                  context,
                  imageUrls[2],
                  2,
                  imageUrls,
                  aspectRatio: 1,
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      int itemCount = imageUrls.length >= 4 ? 4 : imageUrls.length;

      return GridView.builder(
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
                aspectRatio: 1,
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
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          );
        },
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
  }) {
    Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) => const Icon(Icons.error),
    );

    if (useAspectRatio && aspectRatio != null) {
      image = AspectRatio(aspectRatio: aspectRatio, child: image);
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PhotoViewerWidget(
              imageUrls: allUrls,
              initialIndex: index,
            ),
          ),
        );
      },
      child: image,
    );
  }
}
