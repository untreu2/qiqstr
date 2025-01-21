import 'package:flutter/material.dart';
import 'package:any_link_preview/any_link_preview.dart';

class LinkPreviewWidget extends StatelessWidget {
  final List<String> linkUrls;

  const LinkPreviewWidget({Key? key, required this.linkUrls}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: linkUrls.map((url) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
          child: AnyLinkPreview(
            link: url,
            displayDirection: UIDirection.uiDirectionVertical,
            cache: const Duration(days: 7),
            backgroundColor: Colors.grey[900],
            errorWidget: Container(),
            bodyMaxLines: 3,
            bodyTextOverflow: TextOverflow.ellipsis,
            titleStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.white,
            ),
            bodyStyle: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        );
      }).toList(),
    );
  }
}
