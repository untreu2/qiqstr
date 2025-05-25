import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import 'package:qiqstr/models/notification_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/quote_widget.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class NotificationPage extends StatefulWidget {
  final DataService dataService;

  const NotificationPage({Key? key, required this.dataService}) : super(key: key);

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  late Box<NotificationModel> notificationsBox;
  Map<String, UserModel?> userProfiles = {};
  List<_NotificationGroup> groupedNotifications = [];
  bool isLoading = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _initializeBoxAndStartTimer();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeBoxAndStartTimer() async {
    final box = widget.dataService.notificationsBox;
    if (box == null || !box.isOpen) return;

    notificationsBox = box;
    await _loadAndMarkRead();

    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _loadAndMarkRead();
    });
  }

  Future<void> _loadAndMarkRead() async {
    final all = notificationsBox.values
        .where((n) => ['mention', 'reaction', 'repost'].contains(n.type))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final limited = all.take(50).toList();

    for (final n in limited) {
      if (!n.isRead) {
        n.isRead = true;
        await n.save();
      }
    }

    final npubs = limited.map((n) => n.author).toSet();
    final loadedProfiles = <String, UserModel?>{};

    await Future.wait(npubs.map((npub) async {
      if (!userProfiles.containsKey(npub)) {
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

    for (final n in limited) {
      if (n.type == 'mention') {
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
          ..latest = n.timestamp.isAfter(grouped[key]!.latest)
              ? n.timestamp
              : grouped[key]!.latest;
      }
    }

    final combinedGroups = [...flatMentions, ...grouped.values];
    combinedGroups.sort((a, b) => b.latest.compareTo(a.latest));

    setState(() {
      groupedNotifications = combinedGroups;
      userProfiles = {...userProfiles, ...loadedProfiles};
      isLoading = false;
    });
  }

  String _buildTitle(_NotificationGroup group) {
    final first = group.notifications.first;
    final names = group.notifications.map((n) {
      final profile = userProfiles[n.author];
      return profile?.name.isNotEmpty == true ? profile!.name : 'Anonymous';
    }).toSet().toList();

    if (names.isEmpty) return 'Someone interacted';
    final mainName = names.first;
    final othersCount = names.length - 1;

    switch (first.type) {
      case 'mention':
        return '$mainName mentioned you';
      case 'reaction':
        return othersCount > 0
            ? '$mainName and $othersCount others reacted to your post'
            : '$mainName reacted to your post';
      case 'repost':
        return othersCount > 0
            ? '$mainName and $othersCount others reposted your post'
            : '$mainName reposted your post';
      default:
        return '$mainName interacted with your post';
    }
  }

  Widget _buildNotificationTile(_NotificationGroup group) {
    final first = group.notifications.first;
    final profile = userProfiles[first.author];
    final image = profile?.profileImage ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[800],
              backgroundImage: image.isNotEmpty
                  ? CachedNetworkImageProvider(image)
                  : null,
              child: image.isEmpty
                  ? const Icon(Icons.person, size: 18, color: Colors.white)
                  : null,
            ),
            title: Text(
              _buildTitle(group),
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ),
          if (first.type == 'mention' && first.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                first.content,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
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
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    padding: EdgeInsets.only(top: topPadding + 12, bottom: 12),
                    alignment: Alignment.center,
                    child: const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (groupedNotifications.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'No notifications yet.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildNotificationTile(groupedNotifications[index]),
                      childCount: groupedNotifications.length,
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
