import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:qiqstr/models/note_model.dart';
import '../models/reply_model.dart';
import '../screens/note_detail_page.dart';
import '../screens/profile_page.dart';
import 'video_preview.dart';

class ReplyWidget extends StatelessWidget {
  final ReplyModel reply;
  final Function()? onAuthorTap;
  final Function()? onReplyTap;

  const ReplyWidget({
    Key? key,
    required this.reply,
    this.onAuthorTap,
    this.onReplyTap,
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
    final parsedContent = _parseContent(reply.content);

    return Padding(
      padding: EdgeInsets.only(
        left: 16.0 * _getReplyDepth(reply),
        top: 8.0,
        bottom: 8.0,
      ),
      child: InkWell(
        onTap: onReplyTap ??
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NoteDetailPage(
                    note: ReplyToNoteModel(reply: reply),
                  ),
                ),
              );
            },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReplyHeader(context),
            const SizedBox(height: 4),
            if (parsedContent['text'] != null && parsedContent['text'] != '')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  parsedContent['text'],
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
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
                _formatTimestamp(reply.timestamp),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onAuthorTap ??
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfilePage(npub: reply.author),
                    ),
                  );
                },
           child: reply.authorProfileImage.isNotEmpty
              ? CircleAvatar(
                  radius: 16,
                  child: CachedNetworkImage(
                    imageUrl: reply.authorProfileImage,
                    placeholder: (context, url) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                    imageBuilder: (context, imageProvider) => ClipOval(
                      child: Image(
                        image: imageProvider,
                        width: 32, 
                        height: 32,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                )
              : const CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.person, size: 16),
                ),
        ),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: onAuthorTap ??
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(npub: reply.author),
                      ),
                    );
                  },
              child: Text(
                reply.authorName,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _formatTimestamp(reply.timestamp),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  int _getReplyDepth(ReplyModel reply) {
    return 0;
  }
}

class ReplyToNoteModel extends NoteModel {
  ReplyToNoteModel({required ReplyModel reply})
      : super(
          id: reply.id,
          content: reply.content,
          author: reply.author,
          authorName: reply.authorName,
          authorProfileImage: reply.authorProfileImage,
          timestamp: reply.timestamp,
          isRepost: false,
          repostedBy: null,
          repostedByName: '',
        );
}
