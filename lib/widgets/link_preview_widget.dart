import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
      );
    }

    if (_title == null) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text(
          widget.url,
          style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: 14,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _launchUrl(widget.url),
      child: _imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      _imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade900,
                        child: const Center(
                          child: Icon(Icons.link, color: Colors.white38),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      _title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
              ),
              child: Text(
                _title!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
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
