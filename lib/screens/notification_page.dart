import 'package:flutter/material.dart';
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
        // Initialize notifications on first build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (viewModel.isInitialized) {
            viewModel.loadNotificationsCommand.execute();
            viewModel.markAllAsReadCommand.execute();
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
                      _buildHeader(context, vm),
                      Expanded(
                        child: notifications.isEmpty
                            ? _buildEmptyState(context)
                            : RefreshIndicator(
                                onRefresh: () => vm.refreshNotificationsCommand.execute(),
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: notifications.length,
                                  itemBuilder: (context, index) => _buildNotificationTile(
                                    notifications[index],
                                    vm,
                                  ),
                                  separatorBuilder: (_, __) => Divider(
                                    color: context.colors.border,
                                    height: 1,
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

  Widget _buildHeader(BuildContext context, NotificationViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Row(
        children: [
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
    );
  }

  Widget _buildNotificationTile(dynamic item, NotificationViewModel viewModel) {
    if (item is NotificationGroup) {
      final first = item.notifications.first;
      final profile = viewModel.userProfiles[first.author];
      final image = profile?.profileImage ?? '';

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              horizontalTitleGap: 8,
              leading: GestureDetector(
                onTap: () => _navigateToAuthorProfile(first.author),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: context.colors.grey800,
                  backgroundImage: image.isNotEmpty ? CachedNetworkImageProvider(image) : null,
                  child: image.isEmpty ? Icon(Icons.person, size: 18, color: context.colors.textPrimary) : null,
                ),
              ),
              title: Builder(
                builder: (context) {
                  final titleText = viewModel.buildGroupTitle(item);
                  final titleStyle = TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: context.colors.textPrimary,
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
            ),
            if (first.type == 'mention' && first.content.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NoteContentWidget(
                  parsedContent: _parseContent(first.content),
                  noteId: first.id,
                  onNavigateToMentionProfile: _navigateToProfileFromContent,
                ),
              ),
            if (first.type == 'mention' && first.content.trim().isNotEmpty) const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: QuoteWidget(
                bech32: _encodeEventId(first.targetEventId),
              ),
            ),
          ],
        ),
      );
    } else if (item is NotificationModel && item.type == 'zap') {
      final profile = viewModel.userProfiles[item.author];
      final image = profile?.profileImage ?? '';
      final displayName = profile?.name.isNotEmpty == true ? profile!.name : 'Anonymous';

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              horizontalTitleGap: 8,
              leading: GestureDetector(
                onTap: () => _navigateToAuthorProfile(item.author),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: context.colors.grey800,
                  backgroundImage: image.isNotEmpty ? CachedNetworkImageProvider(image) : null,
                  child: image.isEmpty ? Icon(Icons.flash_on, size: 18, color: context.colors.textPrimary) : null,
                ),
              ),
              title: GestureDetector(
                onTap: () => _navigateToAuthorProfile(item.author),
                child: Text(
                  '$displayName zapped your post ${item.amount} sats',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
            if (item.content.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  item.content,
                  style: TextStyle(color: context.colors.textSecondary),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: QuoteWidget(
                bech32: _encodeEventId(item.targetEventId),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
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

  Map<String, dynamic> _parseContent(String content) {
    try {
      // Simple content parsing for notifications
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
        _buildHeader(context, context.read<NotificationViewModel>()),
        Expanded(
          child: Center(
            child: CircularProgressIndicator(color: context.colors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, String message, NotificationViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, viewModel),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: context.colors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load notifications',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: context.colors.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(color: context.colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => viewModel.loadNotificationsCommand.execute(),
                  child: const Text('Retry'),
                ),
              ],
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
        _buildHeader(context, context.read<NotificationViewModel>()),
        Expanded(
          child: Center(
            child: Text(
              'No notifications yet.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}
