import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';
import '../models/link_preview_model.dart';

Future<LinkPreviewModel?> _fetchAndParseMiniLink(String url) async {
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
  } catch (e) {
    // Silently ignore link preview parsing errors
  }
  return null;
}

class MiniLinkPreviewWidget extends StatefulWidget {
  final String url;

  const MiniLinkPreviewWidget({super.key, required this.url});

  @override
  State<MiniLinkPreviewWidget> createState() => _MiniLinkPreviewWidgetState();
}

class _MiniLinkPreviewWidgetState extends State<MiniLinkPreviewWidget> {
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
        final model = await compute(_fetchAndParseMiniLink, widget.url);

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
    final domain = Uri.parse(widget.url).host.replaceFirst('www.', '');

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _launchUrl(widget.url),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (_imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _imageUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 48,
                    height: 48,
                    color: context.colors.grey800,
                    child: Icon(Icons.link, color: context.colors.textTertiary),
                  ),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.colors.grey800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.link, color: context.colors.textTertiary),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: _title != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Text(
                        domain,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ],
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
