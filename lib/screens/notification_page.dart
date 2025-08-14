import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/notification_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/providers/notification_provider.dart';
import 'package:qiqstr/providers/user_provider.dart';
import 'package:qiqstr/widgets/note_content_widget.dart';
import 'package:qiqstr/widgets/quote_widget.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class NotificationPage extends StatefulWidget {
  final DataService dataService;

  const NotificationPage({super.key, required this.dataService});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
        final userProvider = Provider.of<UserProvider>(context, listen: false);

        // Initialize NotificationProvider if not already initialized
        if (!notificationProvider.isInitialized) {
          // Extract npub from DataService or get current user npub
          final npub = userProvider.currentUserNpub ?? '';
          if (npub.isNotEmpty) {
            notificationProvider.initialize(
              npub,
              dataService: widget.dataService,
              userProvider: userProvider,
            );
          }
        }

        // Mark all notifications as read
        notificationProvider.markAllAsRead();
      }
    });
  }

  void _navigateToProfileFromContent(String npub) {
    widget.dataService.openUserProfile(context, npub);
  }

  void _navigateToAuthorProfile(String npub) {
    if (npub.isNotEmpty) {
      widget.dataService.openUserProfile(context, npub);
    }
  }

  Widget _buildNotificationTile(dynamic item, NotificationProvider notificationProvider) {
    if (item is NotificationGroup) {
      final first = item.notifications.first;
      final profile = notificationProvider.userProfiles[first.author];
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
                    final titleText = notificationProvider.buildGroupTitle(item);
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
                )),
            if (first.type == 'mention' && first.content.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NoteContentWidget(
                  parsedContent: widget.dataService.parseContent(first.content),
                  dataService: widget.dataService,
                  onNavigateToMentionProfile: _navigateToProfileFromContent,
                ),
              ),
            if (first.type == 'mention' && first.content.trim().isNotEmpty) const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: QuoteWidget(
                bech32: encodeBasicBech32(first.targetEventId, 'note'),
                dataService: widget.dataService,
              ),
            ),
          ],
        ),
      );
    } else if (item is NotificationModel && item.type == 'zap') {
      final profile = notificationProvider.userProfiles[item.author];
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
                    '$displayName zapped your post ⚡${item.amount} sats',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: context.colors.textPrimary,
                    ),
                  ),
                )),
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
                bech32: encodeBasicBech32(item.targetEventId, 'note'),
                dataService: widget.dataService,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildHeader(BuildContext context, NotificationProvider notificationProvider) {
    final notificationsLast24Hours = notificationProvider.notificationsLast24Hours;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 6),
          Text(
            "You have $notificationsLast24Hours ${notificationsLast24Hours == 1 ? 'notification' : 'notifications'} in the last 24 hours.",
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeManager, NotificationProvider>(
      builder: (context, themeManager, notificationProvider, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: notificationProvider.isLoading
              ? Center(child: CircularProgressIndicator(color: context.colors.textPrimary))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, notificationProvider),
                    Expanded(
                      child: notificationProvider.displayNotifications.isEmpty
                          ? Center(
                              child: Text(
                                'No notifications yet.',
                                style: TextStyle(color: context.colors.textSecondary),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                await notificationProvider.refresh();
                              },
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: notificationProvider.displayNotifications.length,
                                itemBuilder: (context, index) => _buildNotificationTile(
                                  notificationProvider.displayNotifications[index],
                                  notificationProvider,
                                ),
                                separatorBuilder: (_, __) => Divider(
                                  color: context.colors.border,
                                  height: 1,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
