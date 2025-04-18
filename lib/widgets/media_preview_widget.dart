import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/photo_viewer_widget.dart';
import 'video_preview.dart';

class MediaPreviewWidget extends StatelessWidget {
  final List<String> mediaUrls;

  const MediaPreviewWidget({Key? key, required this.mediaUrls})
      : super(key: key);

  static const double borderRadius = 16.0;
  static const EdgeInsets mediaPadding =
      EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0);

  @override
  Widget build(BuildContext context) {
    if (mediaUrls.isEmpty) return const SizedBox.shrink();

    final List<String> videoUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.mp4') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.mov');
    }).toList();

    if (videoUrls.isNotEmpty) {
      return Padding(
        padding: mediaPadding,
        child: VP(url: videoUrls.first),
      );
    }

    final List<String> imageUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif');
    }).toList();

    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: mediaPadding,
      child: _buildAdaptiveMediaGrid(context, imageUrls),
    );
  }

  Widget _buildAdaptiveMediaGrid(BuildContext context, List<String> imageUrls) {
    if (imageUrls.length == 1) {
      return _buildRoundedImage(
        context,
        imageUrls[0],
        0,
        imageUrls,
        useAspectRatio: false,
        fit: BoxFit.contain,
      );
    } else if (imageUrls.length == 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: _buildRoundedImage(
              context,
              imageUrls[0],
              0,
              imageUrls,
              aspectRatio: 1,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildRoundedImage(
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            flex: 2,
            child: _buildRoundedImage(
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
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRoundedImage(
                  context,
                  imageUrls[1],
                  1,
                  imageUrls,
                  aspectRatio: 1,
                ),
                const SizedBox(height: 4),
                _buildRoundedImage(
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
              _buildRoundedImage(
                context,
                imageUrls[index],
                index,
                imageUrls,
                aspectRatio: 1,
              ),
              if (index == 3 && imageUrls.length > 4)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+${imageUrls.length - 4}',
                    style: const TextStyle(
                      color: Colors.white,
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

  Widget _buildRoundedImage(
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
      errorWidget: (context, url, error) => const Icon(Icons.error, size: 20),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: image,
      ),
    );
  }
}
