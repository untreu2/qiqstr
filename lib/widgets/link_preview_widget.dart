import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/theme_manager.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';
import '../models/link_preview_model.dart';

Future<LinkPreviewModel?> _fetchAndParseLink(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final document = html_parser.parse(response.body);
      final metaOgTitle = document.querySelector('meta[property="og:title"]');
      final metaTitle = document.querySelector('title');
      final metaOgImage = document.querySelector('meta[property="og:image"]');

      final String parsedTitle = metaOgTitle?.attributes['content'] ?? metaTitle?.text ?? url;
      final String? parsedImage = metaOgImage?.attributes['content'];

      return LinkPreviewModel(title: parsedTitle, imageUrl: parsedImage);
    }
  } catch (e) {}
  return null;
}

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

  static final Map<String, LinkPreviewModel> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  void _loadPreview() {
    final cached = _cache[widget.url];
    if (cached != null) {
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _title = cached.title;
            _imageUrl = cached.imageUrl;
            _isLoading = false;
          });
        }
      });
    } else {
      _fetchPreviewData();
    }
  }

  Future<void> _fetchPreviewData() async {
    Future.microtask(() async {
      try {
        final model = await compute(_fetchAndParseLink, widget.url);

        if (!mounted) return;

        if (model != null) {
          _cache[widget.url] = model;
          if (mounted) {
            setState(() {
              _title = model.title;
              _imageUrl = model.imageUrl;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: context.colors.accent,
          ),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: _imageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    fadeInDuration: Duration.zero,
                    errorWidget: (_, __, ___) {
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: context.colors.textPrimary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.colors.background,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Uri.parse(widget.url).host.replaceFirst('www.', ''),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.background.withValues(alpha: 0.7),
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
      color: context.colors.overlayLight,
      child: Center(
        child: Icon(
          Icons.link,
          color: context.colors.textSecondary,
          size: 28,
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
