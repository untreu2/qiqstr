import 'package:flutter/material.dart';

class NotePage extends StatelessWidget {
  final String authorName;
  final String content;
  final String timestamp;
  final String? profileImageUrl;
  final String? nip05;

  NotePage({
    required this.authorName,
    required this.content,
    required this.timestamp,
    this.profileImageUrl,
    this.nip05,
  });

  bool isImageUrl(String url) {
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.gif') ||
        url.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Note'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                profileImageUrl != null && profileImageUrl!.isNotEmpty
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(profileImageUrl!),
                        radius: 24,
                      )
                    : CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey,
                      ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$authorName',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          SizedBox(width: 4),
                          if (nip05 != null && nip05!.isNotEmpty)
                            Icon(Icons.verified, color: Colors.purple, size: 16),
                        ],
                      ),
                      if (nip05 != null && nip05!.isNotEmpty)
                        Text(
                          nip05!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.purpleAccent,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            if (!isImageUrl(content))
              Text(
                content,
                style: TextStyle(fontSize: 16),
              )
            else
              Image.network(
                content,
                fit: BoxFit.contain,
              ),
            SizedBox(height: 20),
            Text(
              'Timestamp: $timestamp',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
