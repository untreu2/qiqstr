import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../widgets/video_preview.dart';
import '../widgets/photo_viewer_widget.dart';

class MediaPreviewWidget extends StatefulWidget {
  final List<String> mediaUrls;

  const MediaPreviewWidget({super.key, required this.mediaUrls});

  @override
  _MediaPreviewWidgetState createState() => _MediaPreviewWidgetState();
}

class _MediaPreviewWidgetState extends State<MediaPreviewWidget> {
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<String> imageUrls = widget.mediaUrls
        .where((url) =>
            url.toLowerCase().endsWith('.jpg') ||
            url.toLowerCase().endsWith('.jpeg') ||
            url.toLowerCase().endsWith('.png') ||
            url.toLowerCase().endsWith('.webp') ||
            url.toLowerCase().endsWith('.gif'))
        .toList();

    final List<String> videoUrls = widget.mediaUrls
        .where((url) =>
            url.toLowerCase().endsWith('.mp4') ||
            url.toLowerCase().endsWith('.mov'))
        .toList();

    final List<String> allMediaUrls =
        imageUrls.isNotEmpty ? imageUrls : videoUrls;

    if (allMediaUrls.length == 1) {
      String url = allMediaUrls.first;
      bool isVideo = videoUrls.contains(url);

      return isVideo
          ? VP(url: url)
          : CachedNetworkImage(
              imageUrl: url,
              placeholder: (context, url) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) =>
                  const Icon(Icons.error, size: 20),
              fit: BoxFit.contain,
              width: double.infinity,
            );
    }

    return Column(
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: _pageController,
            itemCount: allMediaUrls.length,
            itemBuilder: (context, index) {
              String url = allMediaUrls[index];
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
                child: isVideo
                    ? VP(url: url)
                    : Container(
                        color: Colors.black,
                        child: CachedNetworkImage(
                          imageUrl: url,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error, size: 20),
                          fit: BoxFit.contain,
                        ),
                      ),
              );
            },
          ),
        ),
        if (allMediaUrls.length > 1) const SizedBox(height: 4.0),
        if (allMediaUrls.length > 1)
          SmoothPageIndicator(
            controller: _pageController,
            count: allMediaUrls.length,
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
