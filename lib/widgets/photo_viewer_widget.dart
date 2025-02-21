import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PhotoViewerWidget extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const PhotoViewerWidget({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  _PhotoViewerWidgetState createState() => _PhotoViewerWidgetState();
}

class _PhotoViewerWidgetState extends State<PhotoViewerWidget> {
  late PageController _pageController;
  late int currentIndex;

  bool _didPrecacheImages = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${currentIndex + 1} / ${widget.imageUrls.length}'),
        backgroundColor: Colors.transparent,
      ),
      body: PhotoViewGallery.builder(
        itemCount: widget.imageUrls.length,
        pageController: _pageController,
        onPageChanged: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        builder: (context, index) {
          return PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(widget.imageUrls[index]),
            minScale: PhotoViewComputedScale.contained * 1.0,
            maxScale: PhotoViewComputedScale.covered * 2.0,
            basePosition: Alignment.center,
          );
        },
        loadingBuilder: (context, event) => const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}
