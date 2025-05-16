import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/link_preview_model.dart';

class LinkPreviewWidget extends StatefulWidget {
  final String url;

  const LinkPreviewWidget({super.key, required this.url});

  @override
  State<LinkPreviewWidget> createState() => _LinkPreviewWidgetState();
}

class _LinkPreviewWidgetState extends State<LinkPreviewWidget> {
  String? _title;
  String? _imageUrl;
  bool _isLoading = true;
  Color? _dominantColor;

  late final Box<LinkPreviewModel> _cacheBox;

  @override
  void initState() {
    super.initState();
    _cacheBox = Hive.box<LinkPreviewModel>('link_preview_cache');
    _loadPreview();
  }

  void _loadPreview() {
    final cached = _cacheBox.get(widget.url);
    if (cached != null) {
      setState(() {
        _title = cached.title;
        _imageUrl = cached.imageUrl;
        _isLoading = false;
      });
      _updateDominantColor();
    } else {
      _fetchPreviewData();
    }
  }

  Future<void> _fetchPreviewData() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final metaOgTitle = document.querySelector('meta[property="og:title"]');
        final metaTitle = document.querySelector('title');
        final metaOgImage = document.querySelector('meta[property="og:image"]');

        final String parsedTitle =
            metaOgTitle?.attributes['content'] ?? metaTitle?.text ?? widget.url;
        final String? parsedImage = metaOgImage?.attributes['content'];

        if (!mounted) return;

        final model =
            LinkPreviewModel(title: parsedTitle, imageUrl: parsedImage);
        _cacheBox.put(widget.url, model);

        setState(() {
          _title = parsedTitle;
          _imageUrl = parsedImage;
          _isLoading = false;
        });

        _updateDominantColor();
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateDominantColor() async {
    if (_imageUrl == null) return;
    try {
      final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(_imageUrl!),
        size: const Size(200, 100),
      );
      if (!mounted) return;

      final dominant = palette.dominantColor?.color ?? Colors.black;

      final darkened = HSLColor.fromColor(dominant)
          .withLightness(
              (HSLColor.fromColor(dominant).lightness * 0.5).clamp(0.0, 1.0))
          .toColor();

      setState(() {
        _dominantColor = darkened;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }

    if (_title == null || _imageUrl == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: GestureDetector(
        onTap: () => _launchUrl(widget.url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    _imageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _imageUrl = null;
                          });
                        }
                      });
                      return _placeholder();
                    },
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: _dominantColor ?? Colors.black87,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Uri.parse(widget.url).host.replaceFirst('www.', ''),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade900,
      child: const Center(
        child: Icon(Icons.link, color: Colors.white38),
      ),
    );
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
