import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

import '../theme/theme_manager.dart';
import '../core/ui/ui_state_builder.dart';
import '../presentation/providers/viewmodel_provider.dart';
import '../presentation/viewmodels/notification_viewmodel.dart';
import '../data/repositories/notification_repository.dart';
import '../models/notification_model.dart';
import '../widgets/note_content_widget.dart';
import '../widgets/quote_widget.dart';
import '../core/di/app_di.dart';
import '../data/services/nostr_data_service.dart';
import '../screens/profile_page.dart';
import '../screens/thread_page.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  @override
  Widget build(BuildContext context) {
    return ViewModelProvider.notification(
      builder: (context, viewModel) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (viewModel.isInitialized && !viewModel.isNotificationsLoading) {
            viewModel.loadNotificationsCommand.execute();
            
            Future.delayed(const Duration(milliseconds: 500), () {
              if (context.mounted) {
                viewModel.markAllAsReadCommand.execute();
              }
            });
          }
        });

        return Scaffold(
          backgroundColor: context.colors.background,
          body: Consumer<NotificationViewModel>(
            builder: (context, vm, child) {
              return UIStateBuilder<List<dynamic>>(
                state: vm.notificationsState,
                builder: (context, notifications) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, vm, notifications.length),
                      Expanded(
                        child: notifications.isEmpty
                            ? _buildEmptyState(context)
                            : RefreshIndicator(
                                onRefresh: () => vm.refreshNotificationsCommand.execute(),
                                color: context.colors.textPrimary,
                                child: ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 80),
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: notifications.length,
                                  itemBuilder: (context, index) => _buildNotificationTile(
                                    notifications[index],
                                    vm,
                                    index,
                                  ),
                                  separatorBuilder: (_, __) => SizedBox(
                                    height: 24,
                                    child: Center(
                                      child: Container(
                                        height: 0.5,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  );
                },
                loading: () => _buildLoadingState(context),
                error: (message) => _buildErrorState(context, message, viewModel),
                empty: (message) => _buildEmptyState(context),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, NotificationViewModel viewModel, int notificationCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SvgPicture.asset(
                    'assets/notification_button.svg',
                    width: 21,
                    height: 21,
                    colorFilter: ColorFilter.mode(
                      context.colors.textPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              if (notificationCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 33),
                  child: Text(
                    '$notificationCount notification${notificationCount != 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(dynamic item, NotificationViewModel viewModel, int index) {
    if (item is NotificationGroup) {
      final first = item.notifications.first;
      final profile = viewModel.userProfiles[first.author];
      final image = profile?.profileImage ?? '';

      return GestureDetector(
        onTap: () => _navigateToTargetNote(first.targetEventId),
        child: Container(
          color: context.colors.background,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _navigateToAuthorProfile(first.author),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: context.colors.grey800,
                        backgroundImage: image.isNotEmpty ? CachedNetworkImageProvider(image) : null,
                        child: image.isEmpty ? Icon(Icons.person, size: 20, color: context.colors.textPrimary) : null,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (context) {
                            final titleText = viewModel.buildGroupTitle(item);
                            final titleStyle = TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: context.colors.textPrimary,
                              height: 1.3,
                            );
                            if (item.notifications.length == 1) {
                              return GestureDetector(
                                onTap: () => _navigateToAuthorProfile(first.author),
                                child: Text(titleText, style: titleStyle),
                              );
                            } else {
                              return Text(titleText, style: titleStyle);
                            }
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(first.timestamp),
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        if (first.type == 'mention' && first.content.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          NoteContentWidget(
                            parsedContent: _parseContent(first.content),
                            noteId: first.id,
                            onNavigateToMentionProfile: _navigateToProfileFromContent,
                          ),
                        ],
                        const SizedBox(height: 8),
                        QuoteWidget(
                          bech32: _encodeEventId(first.targetEventId),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    } else if (item is NotificationModel && item.type == 'zap') {
      final profile = viewModel.userProfiles[item.author];
      final image = profile?.profileImage ?? '';
      final displayName = profile?.name.isNotEmpty == true ? profile!.name : 'Anonymous';

      return GestureDetector(
        onTap: () => _navigateToTargetNote(item.targetEventId),
        child: Container(
          color: context.colors.background,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _navigateToAuthorProfile(item.author),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.amber.shade700,
                      backgroundImage: image.isNotEmpty ? CachedNetworkImageProvider(image) : null,
                      child: image.isEmpty ? const Icon(Icons.flash_on, size: 20, color: Colors.white) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _navigateToAuthorProfile(item.author),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: context.colors.textPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: ' zapped your post ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    fontSize: 15,
                                    color: context.colors.textPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: '${item.amount} sats',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Colors.amber.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(item.timestamp),
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        if (item.content.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            item.content,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        QuoteWidget(
                          bech32: _encodeEventId(item.targetEventId),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    } else if (item is NotificationModel) {
      // Handle other single notification types (reaction, mention, repost)
      final profile = viewModel.userProfiles[item.author];
      final image = profile?.profileImage ?? '';

      return GestureDetector(
        onTap: () => _navigateToTargetNote(item.targetEventId),
        child: Container(
          color: context.colors.background,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _navigateToAuthorProfile(item.author),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: context.colors.grey800,
                        backgroundImage: image.isNotEmpty ? CachedNetworkImageProvider(image) : null,
                        child: image.isEmpty ? Icon(Icons.person, size: 20, color: context.colors.textPrimary) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _navigateToAuthorProfile(item.author),
                          child: Text(
                            viewModel.buildGroupTitle(item),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: context.colors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(item.timestamp),
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        if (item.type == 'mention' && item.content.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          NoteContentWidget(
                            parsedContent: _parseContent(item.content),
                            noteId: item.id,
                            onNavigateToMentionProfile: _navigateToProfileFromContent,
                          ),
                        ],
                        const SizedBox(height: 8),
                        QuoteWidget(
                          bech32: _encodeEventId(item.targetEventId),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    }

    return const SizedBox.shrink();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  void _navigateToProfileFromContent(String npub) {
    _openUserProfile(context, npub);
  }

  void _navigateToAuthorProfile(String npub) {
    if (npub.isNotEmpty) {
      _openUserProfile(context, npub);
    }
  }

  void _openUserProfile(BuildContext context, String npub) async {
    try {
      final nostrDataService = AppDI.get<NostrDataService>();
      final userResult = await nostrDataService.fetchUserProfile(npub);

      if (userResult.isSuccess && userResult.data != null) {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfilePage(user: userResult.data!),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to profile: $e');
    }
  }

  void _navigateToTargetNote(String targetEventId) {
    if (targetEventId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ThreadPage(rootNoteId: targetEventId),
        ),
      );
    }
  }

  Map<String, dynamic> _parseContent(String content) {
    try {
      return {
        'textParts': [
          {'type': 'text', 'text': content}
        ],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
      };
    } catch (e) {
      return {
        'textParts': [
          {'type': 'text', 'text': content}
        ],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
      };
    }
  }

  String _encodeEventId(String eventId) {
    try {
      return encodeBasicBech32(eventId, 'note');
    } catch (e) {
      return eventId;
    }
  }

  Widget _buildLoadingState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, context.read<NotificationViewModel>(), 0),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: context.colors.textPrimary,
                  strokeWidth: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading notifications...',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, String message, NotificationViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, viewModel, 0),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: context.colors.error.withOpacity(0.7),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Failed to load notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => viewModel.loadNotificationsCommand.execute(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.textPrimary,
                      foregroundColor: context.colors.background,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, context.read<NotificationViewModel>(), 0),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 80,
                    color: context.colors.textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No notifications yet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'When someone interacts with your posts,\nyou\'ll see it here',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
