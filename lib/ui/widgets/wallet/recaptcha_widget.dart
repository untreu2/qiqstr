import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _recaptchaSiteKey = '6LfCd8YkAAAAANmVJgzN3SQY3n3fv1RhiS5PgMYM';

const _recaptchaHtml = '''
<!DOCTYPE html>
<html>
<head>
  <script src="https://www.google.com/recaptcha/api.js?render=$_recaptchaSiteKey"></script>
</head>
<body>
<script>
  grecaptcha.ready(function() {
    grecaptcha.execute('$_recaptchaSiteKey', {action: 'login'}).then(function(token) {
      Captcha.postMessage(token);
    }).catch(function(err) {
      Captcha.postMessage('ERROR:' + err);
    });
  });
</script>
</body>
</html>
''';

Future<String?> resolveRecaptcha(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    builder: (_) => const _RecaptchaResolver(),
  );
}

class _RecaptchaResolver extends StatefulWidget {
  const _RecaptchaResolver();

  @override
  State<_RecaptchaResolver> createState() => _RecaptchaResolverState();
}

class _RecaptchaResolverState extends State<_RecaptchaResolver> {
  late final WebViewController _controller;
  Timer? _timeout;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'Captcha',
        onMessageReceived: (message) {
          if (_resolved) return;
          _resolved = true;
          _timeout?.cancel();
          final token = message.message;
          if (token.startsWith('ERROR:') || token.isEmpty) {
            Navigator.of(context).pop(null);
          } else {
            Navigator.of(context).pop(token);
          }
        },
      )
      ..loadHtmlString(_recaptchaHtml, baseUrl: 'https://coinos.io');

    _timeout = Timer(const Duration(seconds: 15), () {
      if (mounted && !_resolved) {
        _resolved = true;
        Navigator.of(context).pop(null);
      }
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0.01,
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
