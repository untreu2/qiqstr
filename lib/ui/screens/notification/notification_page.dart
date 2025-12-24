import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/theme_manager.dart';
import '../../../core/ui/ui_state_builder.dart';
import '../../../presentation/providers/viewmodel_provider.dart';
import '../../../presentation/viewmodels/notification_viewmodel.dart';
import '../../../models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../widgets/note/note_content_widget.dart';
import '../../widgets/note/quote_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../../utils/string_optimizer.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  bool _isSelfNotification(dynamic item, String currentUserNpub) {
    if (currentUserNpub.isEmpty) return false;

    if (item is NotificationGroup) {
      return item.notifications.any((notification) => notification.author == currentUserNpub);
    } else if (item is NotificationModel) {
      return item.author == currentUserNpub;
    }

    return false;
  }


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
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Consumer<NotificationViewModel>(
                builder: (context, vm, child) {
                  return _buildHeader(context, viewModel);
                },
              ),
              Expanded(
                child: Consumer<NotificationViewModel>(
                  builder: (context, vm, child) {
                    return UIStateBuilder<List<dynamic>>(
                      state: vm.notificationsState,
                      builder: (context, notifications) {
                        final filteredNotifications = notifications.where((item) => !_isSelfNotification(item, vm.currentUserNpub)).toList();

                        return filteredNotifications.isEmpty
                            ? _buildEmptyContent(context)
                            : RefreshIndicator(
                                onRefresh: () => vm.refreshNotificationsCommand.execute(),
                                color: context.colors.textPrimary,
                                child: ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 80),
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: filteredNotifications.length,
                                  itemBuilder: (context, index) => _buildNotificationTile(
                                    filteredNotifications[index],
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
                              );
                      },
                      loading: () => _buildLoadingContent(context),
                      error: (message) => _buildErrorContent(context, message, vm),
                      empty: (message) => _buildEmptyContent(context),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, NotificationViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Notifications',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
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
                      onTap: () => _navigateToAuthorProfile(first.author, viewModel),
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
                                  onTap: () => _navigateToAuthorProfile(first.author, viewModel),
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
                          if (first.content.trim().isNotEmpty && first.type != 'repost' && first.type != 'reaction') ...[
                            const SizedBox(height: 4),
                            NoteContentWidget(
                              parsedContent: _parseContent(first.content),
                              noteId: first.id,
                              onNavigateToMentionProfile: (npub) => _navigateToProfileFromContent(npub, viewModel),
                            ),
                          ],
                          const SizedBox(height: 2),
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
                      onTap: () => _navigateToAuthorProfile(item.author, viewModel),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: context.colors.accent,
                        backgroundImage: image.isNotEmpty ? CachedNetworkImageProvider(image) : null,
                        child: image.isEmpty ? Icon(Icons.flash_on, size: 20, color: context.colors.background) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _navigateToAuthorProfile(item.author, viewModel),
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
                                      color: context.colors.accent,
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
                            const SizedBox(height: 4),
                            Text(
                              item.content,
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
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
                      onTap: () => _navigateToAuthorProfile(item.author, viewModel),
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
                            onTap: () => _navigateToAuthorProfile(item.author, viewModel),
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
                          if (item.content.trim().isNotEmpty && item.type != 'repost' && item.type != 'reaction') ...[
                            const SizedBox(height: 4),
                            NoteContentWidget(
                              parsedContent: _parseContent(item.content),
                              noteId: item.id,
                              onNavigateToMentionProfile: (npub) => _navigateToProfileFromContent(npub, viewModel),
                            ),
                          ],
                          const SizedBox(height: 2),
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

  void _navigateToProfileFromContent(String npub, NotificationViewModel viewModel) {
    _openUserProfile(context, npub, viewModel);
  }

  void _navigateToAuthorProfile(String npub, NotificationViewModel viewModel) {
    if (npub.isNotEmpty) {
      _openUserProfile(context, npub, viewModel);
    }
  }

  void _openUserProfile(BuildContext context, String npub, NotificationViewModel viewModel) async {
    try {
      final userResult = await viewModel.getUserProfile(npub);

      userResult.fold(
        (user) {
          if (context.mounted) {
            context.push('/home/notifications/profile?npub=${Uri.encodeComponent(user.npub)}&pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
          }
        },
        (error) {
          debugPrint('Error navigating to profile: $error');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to load profile: $error')),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('Error navigating to profile: $e');
    }
  }

  void _navigateToTargetNote(String targetEventId) {
    if (targetEventId.isNotEmpty) {
      context.push('/home/notifications/thread?rootNoteId=${Uri.encodeComponent(targetEventId)}');
    }
  }

  Map<String, dynamic> _parseContent(String content) {
    try {
      return StringOptimizer.instance.parseContentOptimized(content);
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

  Widget _buildLoadingContent(BuildContext context) {
    return Center(
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
    );
  }

  Widget _buildErrorContent(BuildContext context, String message, NotificationViewModel viewModel) {
    return Center(
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
            PrimaryButton(
              label: 'Retry',
              onPressed: () => viewModel.loadNotificationsCommand.execute(),
              backgroundColor: context.colors.textPrimary,
              foregroundColor: context.colors.background,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyContent(BuildContext context) {
    return Center(
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
    );
  }
}
