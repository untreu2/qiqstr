import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/floating_bubble_widget.dart';

class WebViewPage extends StatefulWidget {
  final String url;

  const WebViewPage({
    super.key,
    required this.url,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _isLoading = progress < 100;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _currentUrl = url;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  String _getDisplayUrl() {
    final url = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.isNotEmpty) {
        return host;
      }
      return url.length > 30 ? '${url.substring(0, 30)}...' : url;
    } catch (e) {
      return url.length > 30 ? '${url.substring(0, 30)}...' : url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: WebViewWidget(
                    controller: _controller,
                    gestureRecognizers: {
                      Factory(() => EagerGestureRecognizer()),
                    },
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: bottomPadding + 14,
            left: 16,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.textPrimary,
                borderRadius: BorderRadius.circular(22.0),
              ),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  label: 'Close',
                  button: true,
                  child: Icon(
                    Icons.close,
                    color: colors.background,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          FloatingBubbleWidget(
            position: FloatingBubblePosition.bottom,
            isVisible: true,
            bottomOffset: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                      ),
                    ),
                  ),
                Flexible(
                  child: Text(
                    _getDisplayUrl(),
                    style: TextStyle(
                      color: colors.background,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: bottomPadding + 14,
            right: 16,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.textPrimary,
                borderRadius: BorderRadius.circular(22.0),
              ),
              child: GestureDetector(
                onTap: () async {
                  try {
                    final url = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
                    
                    final box = context.findRenderObject() as RenderBox?;
                    await SharePlus.instance.share(
                      ShareParams(
                        text: url,
                        sharePositionOrigin: box != null 
                            ? box.localToGlobal(Offset.zero) & box.size 
                            : null,
                      ),
                    );
                  } catch (e) {
                    debugPrint('[WebViewPage] Share error: $e');
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  label: 'Share',
                  button: true,
                  child: Icon(
                    CarbonIcons.share,
                    color: colors.background,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

