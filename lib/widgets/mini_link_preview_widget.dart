import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/link_preview_model.dart';

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
          color: Colors.white10,
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
                    color: Colors.grey.shade800,
                    child: const Icon(Icons.link, color: Colors.white38),
                  ),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.link, color: Colors.white38),
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
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Text(
                        domain,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
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
