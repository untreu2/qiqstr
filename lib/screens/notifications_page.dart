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
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final profileData =
          await widget.dataService.getCachedUserProfile(widget.npub);
      setState(() {
        user = UserModel.fromCachedProfile(widget.npub, profileData);
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load user profile.';
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  cacheExtent: 1500,
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(
                      child: ValueListenableBuilder(
                        valueListenable: widget.notificationsBox.listenable(),
                        builder: (context, Box<NotificationModel> box, _) {
                          final notifications = box.values
                              .where((n) =>
                                  (n.type == 'mention' ||
                                      n.type == 'repost' ||
                                      n.type == 'reaction') &&
                                  n.actorNpub != widget.npub)
                              .toList()
                            ..sort(
                                (a, b) => b.createdAt.compareTo(a.createdAt));

                          if (notifications.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.only(top: 64),
                                child: Text(
                                  'No notifications yet.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: notifications.length,
                            itemBuilder: (context, index) {
                              final n = notifications[index];
                              final selectedTargetId =
                                  n.targetEventIds.isNotEmpty
                                      ? n.targetEventIds.first
                                      : null;

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FutureBuilder<Map<String, String>>(
                                      future: widget.dataService
                                          .getCachedUserProfile(n.actorNpub),
                                      builder: (_, snap) {
                                        String name = 'Anonymous';
                                        String img = '';
                                        if (snap.hasData) {
                                          final u = UserModel.fromCachedProfile(
                                              n.actorNpub, snap.data!);
                                          name = u.name.isNotEmpty
                                              ? u.name
                                              : 'Anonymous';
                                          img = u.profileImage;
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 4),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              CircleAvatar(
                                                radius: 18,
                                                backgroundColor:
                                                    Colors.grey[800],
                                                backgroundImage: img.isNotEmpty
                                                    ? CachedNetworkImageProvider(
                                                        img)
                                                    : null,
                                                child: img.isEmpty
                                                    ? const Icon(Icons.person,
                                                        size: 18,
                                                        color: Colors.white)
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _formatNotificationTitle(
                                                      name, n),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 15,
                                                    color: Colors.white,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    if (selectedTargetId != null)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16),
                                        child: QuoteWidget(
                                          bech32: encodeBasicBech32(
                                              selectedTargetId, 'note'),
                                          dataService: widget.dataService,
                                        ),
                                      ),
                                    if (n.type == 'mention' &&
                                        n.content!.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        child: Text(
                                          n.content!,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    )
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
}
