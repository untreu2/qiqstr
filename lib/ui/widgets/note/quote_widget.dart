import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/quote_widget/quote_widget_bloc.dart';
import '../../../presentation/blocs/quote_widget/quote_widget_event.dart';
import '../../../presentation/blocs/quote_widget/quote_widget_state.dart';
import '../../../utils/thread_chain.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'note_content_widget.dart';

class QuoteWidget extends StatelessWidget {
  final String bech32;
  final bool shortMode;

  const QuoteWidget({
    super.key,
    required this.bech32,
    this.shortMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<QuoteWidgetBloc>(
      create: (context) {
        final bloc = QuoteWidgetBloc(
          feedRepository: AppDI.get<FeedRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          bech32: bech32,
        );
        bloc.add(QuoteWidgetLoadRequested(bech32: bech32));
        return bloc;
      },
      child: BlocBuilder<QuoteWidgetBloc, QuoteWidgetState>(
        builder: (context, state) {
          return switch (state) {
            QuoteWidgetLoading() => Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.border, width: 1),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            QuoteWidgetError() => Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.border, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.link_off,
                      size: 16,
                      color: context.colors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.eventNotFound,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            QuoteWidgetLoaded(
              :final note,
              :final user,
              :final formattedTime,
              :final parsedContent,
              :final shouldTruncate
            ) =>
              _QuoteContent(
                note: note,
                user: user,
                formattedTime: formattedTime,
                parsedContent: parsedContent,
                shouldTruncate: shouldTruncate,
                shortMode: shortMode,
              ),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}

class _QuoteContent extends StatelessWidget {
  final Map<String, dynamic> note;
  final Map<String, dynamic>? user;
  final String? formattedTime;
  final Map<String, dynamic>? parsedContent;
  final bool shouldTruncate;
  final bool shortMode;

  const _QuoteContent({
    required this.note,
    this.user,
    this.formattedTime,
    this.parsedContent,
    this.shouldTruncate = false,
    required this.shortMode,
  });

  void _navigateToThread(BuildContext context) {
    final noteId = note['id'] as String? ?? '';
    final isReply = note['isReply'] as bool? ?? false;
    final rootId = note['rootId'] as String?;
    final parentId = note['parentId'] as String?;

    final chain = <String>[];
    if (isReply && rootId != null && rootId.isNotEmpty) {
      chain.add(rootId);
      if (parentId != null &&
          parentId.isNotEmpty &&
          parentId != rootId &&
          parentId != noteId) {
        chain.add(parentId);
      }
      chain.add(noteId);
    } else {
      chain.add(noteId);
    }

    final chainStr = ThreadChain.build(chain);
    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push('/home/feed/thread/$chainStr');
    } else if (currentLocation.startsWith('/home/notifications')) {
      context.push('/home/notifications/thread/$chainStr');
    } else {
      context.push('/thread/$chainStr');
    }
  }

  void _navigateToProfile(BuildContext context) {
    if (user == null) return;

    final userNpub = user!['npub'] as String? ?? '';
    final userPubkeyHex = user!['pubkeyHex'] as String? ?? '';
    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push(
          '/home/feed/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
    } else if (currentLocation.startsWith('/home/notifications')) {
      context.push(
          '/home/notifications/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
    } else {
      context.push(
          '/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
    }
  }

  void _navigateToMentionProfile(BuildContext context, String npub) {
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final basePath = currentLocation.startsWith('/home/feed')
        ? '/home/feed'
        : currentLocation.startsWith('/home/notifications')
            ? '/home/notifications'
            : '';
    context.push('$basePath/profile?npub=${Uri.encodeComponent(npub)}');
  }

  Map<String, dynamic> _createFallbackUser(String npub) {
    final shortName = npub.length > 8 ? npub.substring(0, 8) : npub;
    return {
      'pubkeyHex': npub,
      'name': shortName,
      'about': '',
      'profileImage': '',
      'banner': '',
      'website': '',
      'nip05': '',
      'lud16': '',
      'updatedAt': DateTime.now(),
      'nip05Verified': false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final noteAuthor = note['author'] as String? ?? '';
    final noteContent = note['content'] as String? ?? '';
    final noteId = note['id'] as String? ?? '';
    final displayUser = user ?? _createFallbackUser(noteAuthor);
    final displayParsedContent = parsedContent ??
        {
          'textParts': [
            {'type': 'text', 'text': noteContent}
          ],
          'mediaUrls': <String>[],
          'linkUrls': <String>[],
          'quoteIds': <String>[],
          'articleIds': <String>[],
        };

    Map<String, dynamic> contentToShow = displayParsedContent;
    if (shortMode) {
      contentToShow = _createShortModeContent(displayParsedContent);
    } else if (shouldTruncate) {
      contentToShow = _createTruncatedContent(displayParsedContent, noteId);
    }

    return GestureDetector(
      onTap: () => _navigateToThread(context),
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, displayUser),
            if (_hasContent(displayParsedContent))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: NoteContentWidget(
                  noteId: noteId,
                  parsedContent: contentToShow,
                  onNavigateToMentionProfile: (npub) =>
                      _navigateToMentionProfile(context, npub),
                  onShowMoreTap: shouldTruncate
                      ? (String noteId) => _navigateToThread(context)
                      : null,
                  shortMode: shortMode,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Map<String, dynamic> user) {
    final userProfileImage = user['profileImage'] as String? ?? '';
    final userName = user['name'] as String? ?? '';
    return Row(
      children: [
        GestureDetector(
          onTap: () => _navigateToProfile(context),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: userProfileImage.isNotEmpty
                    ? context.colors.surfaceTransparent
                    : context.colors.secondary,
                backgroundImage: userProfileImage.isNotEmpty
                    ? CachedNetworkImageProvider(userProfileImage)
                    : null,
                child: userProfileImage.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 14,
                        color: context.colors.textPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                userName.length > 25
                    ? '${userName.substring(0, 25)}...'
                    : userName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const Spacer(),
        if (formattedTime != null)
          Text(
            formattedTime!,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
      ],
    );
  }

  bool _hasContent(Map<String, dynamic> parsedContent) {
    final textParts = parsedContent['textParts'] as List?;
    final hasText = textParts?.any((p) =>
            p['type'] == 'text' &&
            (p['text'] as String? ?? '').trim().isNotEmpty) ??
        false;
    final hasMedia = (parsedContent['mediaUrls'] as List?)?.isNotEmpty ?? false;
    return hasText || hasMedia;
  }

  Map<String, dynamic> _createShortModeContent(Map<String, dynamic> original) {
    try {
      const int limit = 120;
      final textParts =
          (original['textParts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final truncatedParts = <Map<String, dynamic>>[];
      int currentLength = 0;

      for (var part in textParts) {
        if (part['type'] == 'text') {
          final text = part['text'] as String? ?? '';
          if (currentLength + text.length <= limit) {
            truncatedParts.add(part);
            currentLength += text.length;
          } else {
            final remainingChars = limit - currentLength;
            if (remainingChars > 0) {
              truncatedParts.add({
                'type': 'text',
                'text': '${text.substring(0, remainingChars)}...',
              });
            }
            break;
          }
        } else if (part['type'] == 'mention') {
          if (currentLength + 8 <= limit) {
            truncatedParts.add(part);
            currentLength += 8;
          } else {
            break;
          }
        }
      }

      return {
        'textParts': truncatedParts,
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
        'articleIds': <String>[],
      };
    } catch (e) {
      return original;
    }
  }

  Map<String, dynamic> _createTruncatedContent(
      Map<String, dynamic> original, String noteId) {
    try {
      const int limit = 140;
      final textParts =
          (original['textParts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final truncatedParts = <Map<String, dynamic>>[];
      int currentLength = 0;

      for (var part in textParts) {
        if (part['type'] == 'text') {
          final text = part['text'] as String? ?? '';
          if (currentLength + text.length <= limit) {
            truncatedParts.add(part);
            currentLength += text.length;
          } else {
            final remainingChars = limit - currentLength;
            if (remainingChars > 0) {
              truncatedParts.add({
                'type': 'text',
                'text': '${text.substring(0, remainingChars)}... ',
              });
            }
            break;
          }
        } else if (part['type'] == 'mention') {
          if (currentLength + 8 <= limit) {
            truncatedParts.add(part);
            currentLength += 8;
          } else {
            break;
          }
        }
      }

      truncatedParts.add({
        'type': 'show_more',
        'text': 'Show more...',
        'noteId': noteId,
      });

      return {
        'textParts': truncatedParts,
        'mediaUrls': original['mediaUrls'] ?? [],
        'linkUrls': original['linkUrls'] ?? [],
        'quoteIds': original['quoteIds'] ?? [],
        'articleIds': original['articleIds'] ?? [],
      };
    } catch (e) {
      return original;
    }
  }
}
