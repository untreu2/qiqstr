import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/photo_viewer_widget.dart';

class MediaPreviewWidget extends StatelessWidget {
  final List<String> mediaUrls;

  const MediaPreviewWidget({Key? key, required this.mediaUrls})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (mediaUrls.isEmpty) return const SizedBox.shrink();

    final List<String> imageUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif');
    }).toList();

    if (imageUrls.length == 1) {
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
        child: CachedNetworkImage(
          imageUrl: imageUrls.first,
          placeholder: (context, url) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (context, url, error) =>
              const Icon(Icons.error, size: 20),
          fit: BoxFit.fitWidth,
          width: double.infinity,
        ),
      );
    }

    return _buildGrid(context, imageUrls);
  }

  Widget _buildGrid(BuildContext context, List<String> imageUrls) {
    List<Widget> rows = [];

    for (int i = 0; i < imageUrls.length; i += 2) {
      if (i + 1 < imageUrls.length) {
        rows.add(
          Row(
            children: [
              Expanded(
                child: _buildImageItem(
                  context,
                  imageUrls[i],
                  i,
                  imageUrls,
                  isSquare: true,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildImageItem(
                  context,
                  imageUrls[i + 1],
                  i + 1,
                  imageUrls,
                  isSquare: true,
                ),
              ),
            ],
          ),
        );
      } else {
        rows.add(
          _buildImageItem(
            context,
            imageUrls[i],
            i,
            imageUrls,
            isSquare: false,
          ),
        );
      }
      rows.add(const SizedBox(height: 4));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _buildImageItem(
    BuildContext context,
    String url,
    int index,
    List<String> imageUrls, {
    required bool isSquare,
  }) {
    Widget imageWidget;

    if (isSquare) {
      imageWidget = AspectRatio(
        aspectRatio: 1,
        child: CachedNetworkImage(
          imageUrl: url,
          placeholder: (context, url) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (context, url, error) =>
              const Icon(Icons.error, size: 20),
          fit: BoxFit.cover,
        ),
      );
    } else {
      imageWidget = CachedNetworkImage(
        imageUrl: url,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => const Icon(Icons.error, size: 20),
        fit: BoxFit.fitWidth,
        width: double.infinity,
      );
    }

    return GestureDetector(
      onTap: () {
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
      child: imageWidget,
    );
  }
}
