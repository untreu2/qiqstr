import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:any_link_preview/any_link_preview.dart';
import '../models/note_model.dart';
import '../screens/note_detail_page.dart';
import '../screens/profile_page.dart';
import 'video_preview.dart';

class NoteWidget extends StatelessWidget {
  final NoteModel note;
  final Function()? onAuthorTap;
  final Function()? onRepostedByTap;
  final Function()? onNoteTap;

  const NoteWidget({
    Key? key,
    required this.note,
    this.onAuthorTap,
    this.onRepostedByTap,
    this.onNoteTap,
  }) : super(key: key);

  Map<String, dynamic> _parseContent(String content) {
    final RegExp mediaRegExp =
        RegExp(r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))', caseSensitive: false);
    final Iterable<RegExpMatch> mediaMatches = mediaRegExp.allMatches(content);

    final List<String> mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();

    final RegExp linkRegExp = RegExp(r'(https?:\/\/\S+)', caseSensitive: false);
    final Iterable<RegExpMatch> linkMatches = linkRegExp.allMatches(content);

    final List<String> linkUrls = linkMatches
        .map((m) => m.group(0)!)
        .where((url) => !mediaUrls.contains(url) && !url.toLowerCase().endsWith('.mp4'))
        .toList();

    final String text = content
        .replaceAll(mediaRegExp, '')
        .replaceAll(linkRegExp, '')
        .trim();

    return {
      'text': text,
      'mediaUrls': mediaUrls,
      'linkUrls': linkUrls,
    };
  }

  Widget _buildMediaPreviews(List<String> mediaUrls) {
    return Column(
      children: mediaUrls.map((url) {
        if (url.toLowerCase().endsWith('.mp4')) {
          return VideoPreview(url: url);
        } else {
          return CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error),
            fit: BoxFit.cover,
            width: double.infinity,
          );
        }
      }).toList(),
    );
  }

  Widget _buildLinkPreviews(List<String> linkUrls) {
    return Column(
      children: linkUrls.map((url) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: AnyLinkPreview(
            link: url,
            displayDirection: UIDirection.uiDirectionVertical,
            cache: Duration(days: 7),
            backgroundColor: Colors.black87,
            errorWidget: Container(),
            bodyMaxLines: 5,
            bodyTextOverflow: TextOverflow.ellipsis,
            titleStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
            bodyStyle: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final parsedContent = _parseContent(note.content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.isRepost)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 8.0),
            child: GestureDetector(
              onTap: onRepostedByTap ??
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(npub: note.repostedBy!),
                      ),
                    );
                  },
              child: Row(
                children: [
                  const Icon(
                    Icons.repeat,
                    size: 16.0,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4.0),
                  Text(
                    'Reposted by ${note.repostedByName}',
                    style: const TextStyle(
                      fontSize: 12.0,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        GestureDetector(
          onTap: onAuthorTap ??
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfilePage(npub: note.author)),
                );
              },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              children: [
                note.authorProfileImage.isNotEmpty
                    ? CircleAvatar(
                        radius: 18,
                        child: CachedNetworkImage(
                          imageUrl: note.authorProfileImage,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) => const Icon(Icons.error),
                          imageBuilder: (context, imageProvider) => ClipOval(
                            child: Image(
                              image: imageProvider,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      )
                    : const CircleAvatar(
                        radius: 12,
                        child: Icon(Icons.person, size: 16),
                      ),
                const SizedBox(width: 12),
                Text(
                  note.authorName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: onNoteTap ??
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NoteDetailPage(
                      note: note,
                    ),
                  ),
                );
              },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parsedContent['text'] != null && parsedContent['text'] != '')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(parsedContent['text']),
                ),
              if (parsedContent['mediaUrls'] != null && parsedContent['mediaUrls'].isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: _buildMediaPreviews(parsedContent['mediaUrls']),
                ),
              if (parsedContent['linkUrls'] != null && parsedContent['linkUrls'].isNotEmpty)
                _buildLinkPreviews(parsedContent['linkUrls']),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  _formatTimestamp(note.timestamp),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
