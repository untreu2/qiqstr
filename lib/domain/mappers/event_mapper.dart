import 'dart:convert';
import '../entities/feed_note.dart';
import '../entities/user_profile.dart';
import '../entities/notification_item.dart';
import '../entities/article.dart';

class EventMapper {
  FeedNote toFeedNote(
    Map<String, dynamic> event, {
    String? authorName,
    String? authorImage,
    String? authorNip05,
    int reactionCount = 0,
    int repostCount = 0,
    int replyCount = 0,
    int zapCount = 0,
  }) {
    final tags = _getTags(event);
    final kind = event['kind'] as int? ?? 1;

    bool isRepost = kind == 6;
    String? repostedBy;
    int? repostCreatedAt;
    String content = event['content'] as String? ?? '';
    String pubkey = event['pubkey'] as String? ?? '';
    String id = event['id'] as String? ?? '';
    int createdAt = event['created_at'] as int? ?? 0;

    String? rootId;
    String? parentId;
    bool isReply = false;
    bool isQuote = false;
    final eTags = <String>[];

    for (final tag in tags) {
      if (tag.isEmpty || tag.length < 2) continue;

      if (tag[0] == 'q') {
        isQuote = true;
        continue;
      }

      if (tag[0] == 'e') {
        final refId = tag[1];
        if (tag.length >= 4) {
          final marker = tag[3];
          if (marker == 'root') {
            rootId = refId;
          } else if (marker == 'reply') {
            parentId = refId;
          } else if (marker == 'mention') {
            continue;
          } else {
            eTags.add(refId);
          }
        } else {
          eTags.add(refId);
        }
      }
    }

    if (rootId == null && parentId == null && eTags.isNotEmpty && !isQuote) {
      if (eTags.length == 1) {
        rootId = eTags[0];
        parentId = eTags[0];
      } else {
        rootId = eTags.first;
        parentId = eTags.last;
      }
    }

    isReply = (rootId != null || parentId != null) && !isQuote;

    if (isRepost) {
      repostedBy = pubkey;
      repostCreatedAt = createdAt;

      for (final tag in tags) {
        if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
          id = tag[1];
          break;
        }
      }

      for (final tag in tags) {
        if (tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
          pubkey = tag[1];
          break;
        }
      }

      if (content.isNotEmpty) {
        try {
          final parsed = jsonDecode(content) as Map<String, dynamic>;
          content = parsed['content'] as String? ?? '';
          pubkey = parsed['pubkey'] as String? ?? pubkey;
          createdAt = parsed['created_at'] as int? ?? createdAt;

          final parsedTags = parsed['tags'] as List<dynamic>?;
          if (parsedTags != null) {
            rootId = null;
            parentId = null;
            final repostETags = <String>[];
            for (final tag in parsedTags) {
              if (tag is List &&
                  tag.isNotEmpty &&
                  tag[0] == 'e' &&
                  tag.length > 1) {
                final refId = tag[1] as String;
                repostETags.add(refId);
                if (tag.length >= 4) {
                  final marker = tag[3] as String?;
                  if (marker == 'root') {
                    rootId = refId;
                  } else if (marker == 'reply') {
                    parentId = refId;
                  }
                }
              }
            }
            if (rootId == null && parentId == null && repostETags.isNotEmpty) {
              if (repostETags.length == 1) {
                rootId = repostETags[0];
                parentId = repostETags[0];
              } else {
                rootId = repostETags.first;
                parentId = repostETags.last;
              }
            }
            isReply = rootId != null || parentId != null;
          }
        } catch (_) {}
      }
    }

    return FeedNote(
      id: id,
      pubkey: pubkey,
      content: content,
      createdAt: createdAt,
      tags: tags,
      isRepost: isRepost,
      repostedBy: repostedBy,
      repostCreatedAt: repostCreatedAt,
      isReply: isReply,
      rootId: rootId,
      parentId: parentId,
      authorName: authorName,
      authorImage: authorImage,
      authorNip05: authorNip05,
      reactionCount: reactionCount,
      repostCount: repostCount,
      replyCount: replyCount,
      zapCount: zapCount,
    );
  }

  UserProfile toUserProfile(Map<String, dynamic> event) {
    String? name;
    String? displayName;
    String? about;
    String? picture;
    String? banner;
    String? nip05;
    String? lud16;
    String? website;
    final pubkey = event['pubkey'] as String? ?? '';
    final createdAt = event['created_at'] as int? ?? 0;

    try {
      final contentStr = event['content'] as String? ?? '{}';
      final content = jsonDecode(contentStr) as Map<String, dynamic>;
      name = content['name'] as String?;
      displayName = content['display_name'] as String?;
      about = content['about'] as String?;
      picture = content['picture'] as String?;
      banner = content['banner'] as String?;
      nip05 = content['nip05'] as String?;
      lud16 = content['lud16'] as String?;
      website = content['website'] as String?;
    } catch (_) {}

    return UserProfile(
      pubkey: pubkey,
      name: name,
      displayName: displayName,
      about: about,
      picture: picture,
      banner: banner,
      nip05: nip05,
      lud16: lud16,
      website: website,
      createdAt: createdAt,
    );
  }

  NotificationItem toNotificationItem(
    Map<String, dynamic> event, {
    String? fromName,
    String? fromImage,
  }) {
    final tags = _getTags(event);
    final kind = event['kind'] as int? ?? 1;
    final eventId = event['id'] as String? ?? '';
    final pubkey = event['pubkey'] as String? ?? '';
    final content = event['content'] as String? ?? '';
    final createdAt = event['created_at'] as int? ?? 0;

    NotificationType type;
    String? targetNoteId;
    int? zapAmount;

    switch (kind) {
      case 1:
        bool hasMention = false;
        for (final tag in tags) {
          if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
            targetNoteId = tag[1];
            if (tag.length >= 4 && (tag[3] == 'reply' || tag[3] == 'root')) {
              type = NotificationType.reply;
              hasMention = false;
              break;
            }
            hasMention = true;
          }
        }
        type = hasMention ? NotificationType.mention : NotificationType.reply;
        break;
      case 6:
        type = NotificationType.repost;
        for (final tag in tags) {
          if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
            targetNoteId = tag[1];
            break;
          }
        }
        break;
      case 7:
        type = NotificationType.reaction;
        for (final tag in tags) {
          if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
            targetNoteId = tag[1];
            break;
          }
        }
        break;
      case 9735:
        type = NotificationType.zap;
        String? zapSender;
        for (final tag in tags) {
          if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
            targetNoteId = tag[1];
          }
          if (tag.isNotEmpty && tag[0] == 'description' && tag.length > 1) {
            try {
              final zapReq = jsonDecode(tag[1]) as Map<String, dynamic>;
              zapSender = zapReq['pubkey'] as String?;
              final zapTags = zapReq['tags'] as List<dynamic>? ?? [];
              for (final zt in zapTags) {
                if (zt is List && zt.length >= 2 && zt[0] == 'amount') {
                  final millisats = int.tryParse(zt[1].toString());
                  if (millisats != null) {
                    zapAmount = millisats ~/ 1000;
                  }
                }
              }
            } catch (_) {}
          }
        }
        if (zapSender != null && zapSender.isNotEmpty) {
          return NotificationItem(
            id: eventId,
            type: type,
            fromPubkey: zapSender,
            targetNoteId: targetNoteId,
            content: content,
            createdAt: createdAt,
            fromName: fromName,
            fromImage: fromImage,
            zapAmount: zapAmount,
          );
        }
        break;
      default:
        type = NotificationType.mention;
    }

    return NotificationItem(
      id: eventId,
      type: type,
      fromPubkey: pubkey,
      targetNoteId: targetNoteId,
      content: content,
      createdAt: createdAt,
      fromName: fromName,
      fromImage: fromImage,
      zapAmount: zapAmount,
    );
  }

  Article toArticle(
    Map<String, dynamic> event, {
    String? authorName,
    String? authorImage,
  }) {
    final tags = _getTags(event);
    final eventId = event['id'] as String? ?? '';
    final pubkey = event['pubkey'] as String? ?? '';
    final content = event['content'] as String? ?? '';
    final createdAt = event['created_at'] as int? ?? 0;

    String title = '';
    String? image;
    String? summary;
    String dTag = '';
    int? publishedAt;
    List<String> hashtags = [];

    for (final tag in tags) {
      if (tag.isEmpty) continue;
      final tagName = tag[0];
      final tagValue = tag.length > 1 ? tag[1] : '';

      switch (tagName) {
        case 'd':
          dTag = tagValue;
          break;
        case 'title':
          title = tagValue;
          break;
        case 'image':
          image = tagValue;
          break;
        case 'summary':
          summary = tagValue;
          break;
        case 'published_at':
          publishedAt = int.tryParse(tagValue);
          break;
        case 't':
          if (tagValue.isNotEmpty) hashtags.add(tagValue);
          break;
      }
    }

    return Article(
      id: eventId,
      pubkey: pubkey,
      title: title,
      content: content,
      image: image,
      summary: summary,
      dTag: dTag,
      publishedAt: publishedAt ?? createdAt,
      createdAt: createdAt,
      hashtags: hashtags,
      authorName: authorName,
      authorImage: authorImage,
    );
  }

  Map<String, dynamic> feedNoteToEventData(FeedNote note) {
    return {
      'id': note.id,
      'pubkey': note.pubkey,
      'kind': note.isRepost ? 6 : 1,
      'created_at': note.createdAt,
      'content': note.content,
      'tags': note.tags,
      'sig': '',
    };
  }

  List<List<String>> _getTags(Map<String, dynamic> event) {
    final rawTags = event['tags'] as List<dynamic>? ?? [];
    return rawTags.map((tag) {
      if (tag is List) {
        return tag.map((t) => t.toString()).toList();
      }
      return <String>[];
    }).toList();
  }
}
