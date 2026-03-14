import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/services/image_cache_service.dart';

class AppImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext)? placeholder;
  final Widget Function(BuildContext)? errorWidget;
  final int? memCacheWidth;

  const AppImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth,
  });

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  _LoadState _state = _LoadState.loading;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AppImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      setState(() {
        _state = _LoadState.loading;
        _localPath = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _state = _LoadState.error);
      return;
    }
    try {
      final path = await ImageCacheService.instance.resolve(widget.url);
      if (!mounted) return;
      if (path != null && path.isNotEmpty) {
        setState(() {
          _localPath = path;
          _state = _LoadState.loaded;
        });
      } else {
        setState(() => _state = _LoadState.error);
      }
    } catch (_) {
      if (mounted) setState(() => _state = _LoadState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _LoadState.loading => SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.placeholder?.call(context) ?? const SizedBox.shrink(),
        ),
      _LoadState.error => SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.errorWidget?.call(context) ?? const SizedBox.shrink(),
        ),
      _LoadState.loaded => Image.file(
          File(_localPath!),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: widget.memCacheWidth,
          errorBuilder: (_, __, ___) =>
              widget.errorWidget?.call(context) ??
              SizedBox(width: widget.width, height: widget.height),
        ),
    };
  }
}

enum _LoadState { loading, loaded, error }

class AppCircleAvatar extends StatelessWidget {
  final String imageUrl;
  final double radius;
  final Widget fallback;

  const AppCircleAvatar({
    super.key,
    required this.imageUrl,
    required this.radius,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(radius: radius, child: fallback);
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: _RustFileImageProvider(imageUrl),
      onBackgroundImageError: (_, __) {},
      child: null,
    );
  }
}

class _RustFileImageProvider extends ImageProvider<_RustFileImageProvider> {
  final String url;
  const _RustFileImageProvider(this.url);

  @override
  Future<_RustFileImageProvider> obtainKey(ImageConfiguration config) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      _RustFileImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_load(decode));
  }

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final path = await ImageCacheService.instance.resolve(url);
    if (path == null || path.isEmpty) throw Exception('no image: $url');
    final file = File(path);
    final bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is _RustFileImageProvider && url == other.url;

  @override
  int get hashCode => url.hashCode;
}

ImageProvider appImageProvider(String url) {
  if (url.isEmpty) return const _EmptyImageProvider();
  return _RustFileImageProvider(url);
}

class _EmptyImageProvider extends ImageProvider<_EmptyImageProvider> {
  const _EmptyImageProvider();

  @override
  Future<_EmptyImageProvider> obtainKey(ImageConfiguration config) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      _EmptyImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      Future.error(Exception('empty url')),
    );
  }

  @override
  bool operator ==(Object other) => other is _EmptyImageProvider;

  @override
  int get hashCode => 0;
}
