import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/notification_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/note_content_widget.dart';
import 'package:qiqstr/widgets/quote_widget.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class NotificationPage extends StatefulWidget {
  final DataService dataService;

  const NotificationPage({Key? key, required this.dataService}) : super(key: key);

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  Map<String, UserModel?> userProfiles = {};
  List<dynamic> displayNotifications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    _updateDisplayData(widget.dataService.notificationsNotifier.value, isInitialLoad: true);
    widget.dataService.notificationsNotifier.addListener(_handleNotificationsUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.dataService.markAllUserNotificationsAsRead();
      }
    });
  }

  @override
  void dispose() {
    widget.dataService.notificationsNotifier.removeListener(_handleNotificationsUpdate);
    super.dispose();
  }

  void _handleNotificationsUpdate() {
    if (mounted) {
      _updateDisplayData(widget.dataService.notificationsNotifier.value);
    }
  }

  Future<void> _updateDisplayData(List<NotificationModel> notificationsFromNotifier, {bool isInitialLoad = false}) async {
    if (!mounted) return;

    final all = notificationsFromNotifier.where((n) => ['mention', 'reaction', 'repost', 'zap'].contains(n.type)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final limited = all.take(100).toList();

    final npubs = limited.map((n) => n.author).toSet();
    final loadedProfiles = <String, UserModel?>{};
    await Future.wait(npubs.map((npub) async {
      if (!userProfiles.containsKey(npub) || isInitialLoad) {
        try {
          final profile = await widget.dataService.getCachedUserProfile(npub);
          loadedProfiles[npub] = UserModel.fromCachedProfile(npub, profile);
        } catch (_) {
          loadedProfiles[npub] = null;
        }
      } else {
        loadedProfiles[npub] = userProfiles[npub];
      }
    }));

    final grouped = <String, _NotificationGroup>{};
    final flatMentions = <_NotificationGroup>[];
    final individualZaps = <NotificationModel>[];

    for (final n in limited) {
      if (n.type == 'zap') {
        individualZaps.add(n);
      } else if (n.type == 'mention') {
        flatMentions.add(_NotificationGroup(
          type: n.type,
          targetEventId: n.targetEventId,
          latest: n.timestamp,
        )..notifications.add(n));
      } else {
        final key = '${n.targetEventId}_${n.type}';
        grouped.putIfAbsent(
          key,
          () => _NotificationGroup(
            type: n.type,
            targetEventId: n.targetEventId,
            latest: n.timestamp,
          ),
        )
          ..notifications.add(n)
          ..latest = n.timestamp.isAfter(grouped[key]!.latest) ? n.timestamp : grouped[key]!.latest;
      }
    }

    final groupedItems = [...flatMentions, ...grouped.values];
    groupedItems.sort((a, b) => b.latest.compareTo(a.latest));
    individualZaps.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final combined = <dynamic>[...groupedItems, ...individualZaps]..sort((a, b) {
        final at = a is _NotificationGroup ? a.latest : a.timestamp;
        final bt = b is _NotificationGroup ? b.latest : b.timestamp;
        return bt.compareTo(at);
      });

    if (mounted) {
      setState(() {
        displayNotifications = combined;
        userProfiles = {...userProfiles, ...loadedProfiles};
        if (isInitialLoad) isLoading = false;
      });
    }
  }

  String _buildGroupTitle(_NotificationGroup group) {
    final first = group.notifications.first;
    final names = group.notifications
        .map((n) {
          final profile = userProfiles[n.author];
          return profile?.name.isNotEmpty == true ? profile!.name : 'Anonymous';
        })
        .toSet()
        .toList();

    if (names.isEmpty) return 'Someone interacted';
    final mainName = names.first;
    final othersCount = names.length - 1;

    switch (first.type) {
      case 'mention':
        return '$mainName mentioned you';
      case 'reaction':
        return othersCount > 0 ? '$mainName and $othersCount others reacted to your post' : '$mainName reacted to your post';
      case 'repost':
        return othersCount > 0 ? '$mainName and $othersCount others reposted your post' : '$mainName reposted your post';
      default:
        return '$mainName interacted with your post';
    }
  }

  void _navigateToProfileFromContent(String npub) {
    widget.dataService.openUserProfile(context, npub);
  }

  void _navigateToAuthorProfile(String npub) {
    if (npub.isNotEmpty) {
      widget.dataService.openUserProfile(context, npub);
    }
  }

  Widget _buildNotificationTile(dynamic item) {
    if (item is _NotificationGroup) {
      final first = item.notifications.first;
      final profile = userProfiles[first.author];
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
                    final titleText = _buildGroupTitle(item);
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
      final profile = userProfiles[item.author];
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

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: context.colors.textPrimary))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    padding: EdgeInsets.only(top: topPadding + 12, bottom: 8, left: 20),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                if (displayNotifications.isEmpty && !isLoading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'No notifications yet.',
                        style: TextStyle(color: context.colors.textTertiary),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildNotificationTile(displayNotifications[index]),
                      childCount: displayNotifications.length,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NotificationGroup {
  final String type;
  final String targetEventId;
  final List<NotificationModel> notifications = [];
  DateTime latest;

  _NotificationGroup({
    required this.type,
    required this.targetEventId,
    required this.latest,
  });
}
