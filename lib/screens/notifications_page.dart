import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/models/notification_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/quote_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';

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
                  n.type == 'reaction') &&
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white, size: 24),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
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
          if (n.type == 'mention' && n.content!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                n.content!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
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
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: SidebarWidget(user: user),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : errorMessage != null
              ? Center(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              : CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  cacheExtent: 1500,
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    _notifications.isEmpty
                        ? const SliverToBoxAdapter(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.only(top: 64),
                                child: Text(
                                  'No notifications yet.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final n = _notifications[index];
                                return _buildNotificationTile(n);
                              },
                              childCount: _notifications.length,
                            ),
                          ),
                  ],
                ),
    );
  }
}
