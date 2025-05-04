import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/models/notification_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/quote_widget.dart';

class NotificationsPage extends StatefulWidget {
  final String npub;
  final Box<NotificationModel> notificationsBox;
  final DataService dataService;

  const NotificationsPage({
    super.key,
    required this.npub,
    required this.notificationsBox,
    required this.dataService,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  UserModel? user;
  List<NotificationModel> _notifications = [];
  Map<String, UserModel?> _userProfilesCache = {};
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final profileData =
          await widget.dataService.getCachedUserProfile(widget.npub);
      user = UserModel.fromCachedProfile(widget.npub, profileData);

      final notifications = widget.notificationsBox.values
          .where((n) =>
              (n.type == 'mention' ||
                  n.type == 'repost' ||
                  n.type == 'reaction' ||
                  n.type == 'zap') &&
              n.actorNpub != widget.npub)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _notifications = notifications;
        isLoading = false;
      });

      _lazyLoadProfiles(notifications);
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load notifications.';
        isLoading = false;
      });
    }
  }

  Future<void> _lazyLoadProfiles(List<NotificationModel> notifications) async {
    final uniqueNpubs = notifications.map((n) => n.actorNpub).toSet();

    for (final npub in uniqueNpubs) {
      if (_userProfilesCache.containsKey(npub)) continue;

      try {
        final data = await widget.dataService.getCachedUserProfile(npub);
        final profile = UserModel.fromCachedProfile(npub, data);

        if (mounted) {
          setState(() {
            _userProfilesCache[npub] = profile;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _userProfilesCache[npub] = null;
          });
        }
      }
    }
  }

  Widget _buildNotificationTile(NotificationModel n) {
    final profile = _userProfilesCache[n.actorNpub];
    final name = profile?.name.isNotEmpty == true ? profile!.name : 'Anonymous';
    final img = profile?.profileImage ?? '';
    final selectedTargetId =
        n.targetEventIds.isNotEmpty ? n.targetEventIds.first : null;

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
              backgroundImage:
                  img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
              child: img.isEmpty
                  ? const Icon(Icons.person, size: 18, color: Colors.white)
                  : null,
            ),
            title: Text(
              _formatNotificationTitle(name, n),
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selectedTargetId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: QuoteWidget(
                bech32: encodeBasicBech32(selectedTargetId, 'note'),
                dataService: widget.dataService,
              ),
            ),
          if (n.type == 'mention' && n.content?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                n.content!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          if (n.type == 'zap' && n.zapAmount != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.flash_on, size: 16, color: Colors.amber),
                  const SizedBox(width: 6),
                  Text(
                    '${(n.zapAmount! ~/ 1000)} sats',
                    style: const TextStyle(color: Colors.amber, fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatNotificationTitle(String name, NotificationModel n) {
    switch (n.type) {
      case 'mention':
        return '$name mentioned you';
      case 'reaction':
        return '$name reacted ${n.content?.trim()} to your post';
      case 'repost':
        return '$name reposted you';
      case 'zap':
        final sats = (n.zapAmount ?? 0) ~/ 1000;
        return sats > 0
            ? '$name zapped you with $sats sats ⚡'
            : '$name zapped you ⚡';
      default:
        return '$name interacted with your post';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            if (isLoading)
              const Expanded(
                child: Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              )
            else if (errorMessage != null)
              Expanded(
                child: Center(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else if (_notifications.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No notifications yet.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final n = _notifications[index];
                    return _buildNotificationTile(n);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
