import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../../models/user_model.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/quote_widget_viewmodel.dart';
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
    return ChangeNotifierProvider<QuoteWidgetViewModel>(
      create: (_) => QuoteWidgetViewModel(
        noteRepository: AppDI.get(),
        userRepository: AppDI.get(),
        bech32: bech32,
      ),
      child: Consumer<QuoteWidgetViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.isLoading) {
            return Container(
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
            );
          }

          if (viewModel.hasError || viewModel.note == null) {
            return const SizedBox.shrink();
          }

          return _QuoteContent(
            viewModel: viewModel,
            shortMode: shortMode,
          );
        },
      ),
    );
  }
}

class _QuoteContent extends StatelessWidget {
  final QuoteWidgetViewModel viewModel;
  final bool shortMode;

  const _QuoteContent({
    required this.viewModel,
    required this.shortMode,
  });

  void _navigateToThread(BuildContext context) {
    final note = viewModel.note;
    if (note == null) return;

    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push('/home/feed/thread?rootNoteId=${Uri.encodeComponent(note.id)}');
    } else if (currentLocation.startsWith('/home/notifications')) {
      context.push('/home/notifications/thread?rootNoteId=${Uri.encodeComponent(note.id)}');
    } else {
      context.push('/thread?rootNoteId=${Uri.encodeComponent(note.id)}');
    }
  }

  void _navigateToProfile(BuildContext context) {
    final user = viewModel.user;
    if (user == null) return;

    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push('/home/feed/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
    } else if (currentLocation.startsWith('/home/notifications')) {
      context.push('/home/notifications/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
    } else if (currentLocation.startsWith('/home/dm')) {
      context.push('/home/dm/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
    } else {
      context.push('/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
    }
  }

  void _navigateToMentionProfile(BuildContext context, String npub) {
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final basePath = currentLocation.startsWith('/home/feed')
        ? '/home/feed'
        : currentLocation.startsWith('/home/notifications')
            ? '/home/notifications'
            : currentLocation.startsWith('/home/dm')
                ? '/home/dm'
                : '';
    context.push('$basePath/profile?npub=${Uri.encodeComponent(npub)}');
  }

  UserModel _createFallbackUser(String npub) {
    final shortName = npub.length > 8 ? npub.substring(0, 8) : npub;
    return UserModel.create(
      pubkeyHex: npub,
      name: shortName,
      about: '',
      profileImage: '',
      banner: '',
      website: '',
      nip05: '',
      lud16: '',
      updatedAt: DateTime.now(),
      nip05Verified: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = viewModel.note!;
    final user = viewModel.user ?? _createFallbackUser(note.author);
    final parsedContent = viewModel.parsedContent ?? {
      'textParts': [{'type': 'text', 'text': note.content}],
      'mediaUrls': <String>[],
      'linkUrls': <String>[],
      'quoteIds': <String>[],
    };

    Map<String, dynamic> contentToShow = parsedContent;
    if (shortMode) {
      contentToShow = _createShortModeContent(parsedContent);
    } else if (viewModel.shouldTruncate) {
      contentToShow = _createTruncatedContent(parsedContent, note.id);
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
            _buildHeader(context, user),
            if (_hasContent(parsedContent))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: NoteContentWidget(
                  noteId: note.id,
                  parsedContent: contentToShow,
                  onNavigateToMentionProfile: (npub) => _navigateToMentionProfile(context, npub),
                  onShowMoreTap: viewModel.shouldTruncate ? (String noteId) => _navigateToThread(context) : null,
                  shortMode: shortMode,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserModel user) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _navigateToProfile(context),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: user.profileImage.isNotEmpty ? context.colors.surfaceTransparent : context.colors.secondary,
                backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
                child: user.profileImage.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 14,
                        color: context.colors.textPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name,
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
        if (viewModel.formattedTime != null)
          Text(
            viewModel.formattedTime!,
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
    final hasText = textParts?.any((p) => p['type'] == 'text' && (p['text'] as String? ?? '').trim().isNotEmpty) ?? false;
    final hasMedia = (parsedContent['mediaUrls'] as List?)?.isNotEmpty ?? false;
    return hasText || hasMedia;
  }

  Map<String, dynamic> _createShortModeContent(Map<String, dynamic> original) {
    try {
      const int limit = 120;
      final textParts = (original['textParts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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
      };
    } catch (e) {
      return original;
    }
  }

  Map<String, dynamic> _createTruncatedContent(Map<String, dynamic> original, String noteId) {
    try {
      const int limit = 140;
      final textParts = (original['textParts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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
      };
    } catch (e) {
      return original;
    }
  }
}
