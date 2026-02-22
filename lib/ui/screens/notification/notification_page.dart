import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/list_separator_widget.dart';
import '../../widgets/note/quote_widget.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../../presentation/blocs/notification/notification_bloc.dart';
import '../../../presentation/blocs/notification/notification_event.dart'
    as notification_events;
import '../../../presentation/blocs/notification/notification_state.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../utils/thread_chain.dart';
import '../../../l10n/app_localizations.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotificationBloc>(
      create: (context) {
        final bloc = AppDI.get<NotificationBloc>();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          bloc.add(const notification_events.NotificationsLoadRequested());
        });
        return bloc;
      },
      child: BlocBuilder<NotificationBloc, NotificationState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: _buildBody(context, state),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, NotificationState state) {
    if (state is NotificationLoading || state is NotificationInitial) {
      return _buildLoadingContent(context);
    }

    if (state is NotificationError) {
      return _buildErrorContent(context, state.message);
    }

    if (state is NotificationsLoaded) {
      final notifications = state.notifications
          .where((n) => n['author'] != state.currentUserHex)
          .toList();

      if (notifications.isEmpty) {
        return _buildEmptyContent(context);
      }

      final grouped = _groupNotifications(notifications);

      return RefreshIndicator(
        onRefresh: () async {
          context
              .read<NotificationBloc>()
              .add(const notification_events.NotificationsRefreshRequested());
        },
        color: context.colors.textPrimary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
                child: _buildHeader(context, notifications)),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: SliverList.separated(
                itemCount: grouped.length,
                itemBuilder: (context, index) {
                  final item = grouped[index];
                  if (item['isGrouped'] == true) {
                    return _GroupedNotificationTile(notification: item);
                  }
                  return _NotificationTile(notification: item);
                },
                separatorBuilder: (_, __) =>
                    const ListSeparatorWidget(),
              ),
            ),
          ],
        ),
      );
    }

    return _buildLoadingContent(context);
  }

  Widget _buildHeader(
      BuildContext context, List<Map<String, dynamic>> notifications) {
    final l10n = AppLocalizations.of(context)!;
    final counts = _countRecentNotifications(notifications);

    if (counts == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
        child: Text(
          l10n.notifications,
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.notifications,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
                children: _buildSummarySpans(context, counts)),
          ),
          const SizedBox(height: 12),
          _buildActivityBar(context, counts),
        ],
      ),
    );
  }

  _NotificationCounts? _countRecentNotifications(
      List<Map<String, dynamic>> notifications) {
    final cutoff = DateTime.now()
            .subtract(const Duration(hours: 24))
            .millisecondsSinceEpoch ~/
        1000;

    final recent =
        notifications.where((n) => (n['createdAt'] as int? ?? 0) >= cutoff);

    int reactions = 0;
    int reposts = 0;
    int replies = 0;
    int mentions = 0;
    int zaps = 0;
    int totalSats = 0;

    for (final n in recent) {
      switch (n['type'] as String? ?? '') {
        case 'reaction':
          reactions++;
        case 'repost':
          reposts++;
        case 'reply':
          replies++;
        case 'mention':
          mentions++;
        case 'zap':
          zaps++;
          totalSats += (n['zapAmount'] as int? ?? 0);
      }
    }

    final total = reactions + reposts + replies + mentions + zaps;
    if (total == 0) return null;

    return _NotificationCounts(
      reactions: reactions,
      reposts: reposts,
      replies: replies,
      mentions: mentions,
      zaps: zaps,
      totalSats: totalSats,
      total: total,
    );
  }

  List<InlineSpan> _buildSummarySpans(
      BuildContext context, _NotificationCounts counts) {
    final l10n = AppLocalizations.of(context)!;

    final parts = <String>[];
    if (counts.reactions > 0) {
      parts.add(l10n.notificationReactionCount(counts.reactions));
    }
    if (counts.zaps > 0) {
      final zapStr = counts.totalSats > 0
          ? '${l10n.notificationZapCount(counts.zaps)} (${l10n.notificationZapSatsCount(counts.totalSats)})'
          : l10n.notificationZapCount(counts.zaps);
      parts.add(zapStr);
    }
    if (counts.reposts > 0) {
      parts.add(l10n.notificationRepostCount(counts.reposts));
    }
    if (counts.replies > 0) {
      parts.add(l10n.notificationReplyCount(counts.replies));
    }
    if (counts.mentions > 0) {
      parts.add(l10n.notificationMentionCount(counts.mentions));
    }

    final normalStyle = TextStyle(
      fontSize: 15,
      color: context.colors.textSecondary,
      height: 1.4,
    );
    final boldStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: context.colors.textPrimary,
      height: 1.4,
    );

    final spans = <InlineSpan>[
      TextSpan(text: l10n.notificationSummaryPrefix, style: normalStyle),
    ];

    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        if (i == parts.length - 1) {
          spans.add(TextSpan(
              text: l10n.notificationSummaryAnd, style: normalStyle));
        } else {
          spans.add(TextSpan(text: ', ', style: normalStyle));
        }
      }
      spans.add(TextSpan(text: parts[i], style: boldStyle));
    }

    return spans;
  }

  Widget _buildActivityBar(BuildContext context, _NotificationCounts counts) {
    final segments = <_BarSegment>[];

    if (counts.reactions > 0) {
      segments.add(_BarSegment(counts.reactions, context.colors.reaction));
    }
    if (counts.zaps > 0) {
      segments.add(_BarSegment(counts.zaps, context.colors.zap));
    }
    if (counts.reposts > 0) {
      segments.add(_BarSegment(counts.reposts, context.colors.repost));
    }
    if (counts.replies > 0) {
      segments.add(_BarSegment(counts.replies, context.colors.reply));
    }
    if (counts.mentions > 0) {
      segments.add(_BarSegment(
          counts.mentions, context.colors.textSecondary.withValues(alpha: 0.5)));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: segments[i].count,
                child: Container(
                  decoration: BoxDecoration(
                    color: segments[i].color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingContent(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        color: context.colors.textPrimary,
        strokeWidth: 2,
      ),
    );
  }

  Widget _buildErrorContent(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: context.colors.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.failedToLoadNotifications,
              style: TextStyle(
                fontSize: 18,
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
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                context.read<NotificationBloc>().add(
                    const notification_events.NotificationsLoadRequested());
              },
              child: Text(
                l10n.retryText,
                style: TextStyle(color: context.colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 80,
              color: context.colors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noNotificationsYet,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.whenSomeoneInteractsWithYourPosts,
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

class _NotificationCounts {
  final int reactions;
  final int reposts;
  final int replies;
  final int mentions;
  final int zaps;
  final int totalSats;
  final int total;

  const _NotificationCounts({
    required this.reactions,
    required this.reposts,
    required this.replies,
    required this.mentions,
    required this.zaps,
    required this.totalSats,
    required this.total,
  });
}

class _BarSegment {
  final int count;
  final Color color;

  const _BarSegment(this.count, this.color);
}

const _groupableTypes = {'reaction', 'repost', 'zap'};

List<Map<String, dynamic>> _groupNotifications(
    List<Map<String, dynamic>> notifications) {
  final result = <Map<String, dynamic>>[];
  final groups = <String, List<Map<String, dynamic>>>{};
  final groupOrder = <String, int>{};

  for (var i = 0; i < notifications.length; i++) {
    final n = notifications[i];
    final type = n['type'] as String? ?? '';
    final targetEventId = n['targetEventId'] as String? ?? '';

    if (_groupableTypes.contains(type) && targetEventId.isNotEmpty) {
      final key = '$type:$targetEventId';
      groups.putIfAbsent(key, () => []).add(n);
      groupOrder.putIfAbsent(key, () => i);
    } else {
      result.add({...n, '_sortIndex': i});
    }
  }

  for (final entry in groups.entries) {
    final items = entry.value;
    items.sort((a, b) =>
        (b['createdAt'] as int? ?? 0).compareTo(a['createdAt'] as int? ?? 0));

    if (items.length == 1) {
      result.add({...items.first, '_sortIndex': groupOrder[entry.key]!});
    } else {
      final seen = <String>{};
      final uniqueAuthors = <Map<String, dynamic>>[];
      for (final item in items) {
        final author = item['author'] as String? ?? '';
        if (author.isNotEmpty && seen.add(author)) {
          uniqueAuthors.add({
            'author': author,
            'fromName': item['fromName'],
            'fromImage': item['fromImage'],
            'name': item['name'],
            'profileImage': item['profileImage'],
          });
        }
      }

      final totalZapAmount = items.fold<int>(
          0, (sum, item) => sum + (item['zapAmount'] as int? ?? 0));

      result.add({
        ...items.first,
        'isGrouped': true,
        'groupedAuthors': uniqueAuthors,
        'groupCount': uniqueAuthors.length,
        'totalZapAmount': totalZapAmount,
        '_sortIndex': groupOrder[entry.key]!,
      });
    }
  }

  result.sort((a, b) =>
      (a['_sortIndex'] as int).compareTo(b['_sortIndex'] as int));

  return result;
}

class _NotificationTile extends StatefulWidget {
  final Map<String, dynamic> notification;

  const _NotificationTile({required this.notification});

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant _NotificationTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldName = oldWidget.notification['fromName'] as String? ?? '';
    final newName = widget.notification['fromName'] as String? ?? '';
    final oldImage = oldWidget.notification['fromImage'] as String? ?? '';
    final newImage = widget.notification['fromImage'] as String? ?? '';
    if ((newName.isNotEmpty && oldName.isEmpty) ||
        (newImage.isNotEmpty && oldImage.isEmpty)) {
      setState(() {
        _profile = {
          'name': newName,
          'profileImage': newImage,
        };
      });
    }
  }

  Future<void> _loadProfile() async {
    final author = widget.notification['author'] as String? ?? '';
    if (author.isEmpty) return;

    final fromName = widget.notification['fromName'] as String? ?? '';
    final fromImage = widget.notification['fromImage'] as String? ?? '';

    if (fromName.isNotEmpty || fromImage.isNotEmpty) {
      if (mounted) {
        setState(() {
          _profile = {
            'name': fromName,
            'profileImage': fromImage,
          };
        });
      }
      return;
    }

    try {
      final profileRepo = AppDI.get<ProfileRepository>();
      final profile = await profileRepo.getProfile(author);
      if (profile != null && mounted) {
        setState(() {
          _profile = {
            'name': profile.name ?? profile.displayName ?? '',
            'profileImage': profile.picture ?? '',
          };
        });
        return;
      }

      final syncService = AppDI.get<SyncService>();
      await syncService.syncProfile(author);
      final synced = await profileRepo.getProfile(author);
      if (synced != null && mounted) {
        setState(() {
          _profile = {
            'name': synced.name ?? synced.displayName ?? '',
            'profileImage': synced.picture ?? '',
          };
        });
      }
    } catch (e) {
      debugPrint('[NotificationTile] Error loading profile: $e');
    }
  }

  String _getTypeText(BuildContext context, String type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case 'reaction':
        return l10n.reactedToYourPost;
      case 'repost':
        return l10n.repostedYourPost;
      case 'reply':
        return l10n.repliedToYourPost;
      case 'mention':
        return l10n.mentionedYou;
      case 'zap':
        return l10n.zappedYou;
      default:
        return l10n.interactedWithYou;
    }
  }

  String _formatTimestamp(BuildContext context, int? createdAt) {
    final l10n = AppLocalizations.of(context)!;
    if (createdAt == null || createdAt == 0) return '';

    final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return l10n.now;
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }

  void _onTap() async {
    final targetEventId = widget.notification['targetEventId'] as String? ?? '';
    final type = widget.notification['type'] as String? ?? '';
    final notificationEventId = widget.notification['id'] as String? ?? '';

    if (type == 'follow' || type == 'unfollow') {
      final author = widget.notification['author'] as String? ?? '';
      if (author.isNotEmpty) {
        _navigateToProfile(author);
      }
    } else if (targetEventId.isNotEmpty) {
      final chain = <String>[];

      if (type == 'reply' && notificationEventId.isNotEmpty) {
        try {
          final feedRepo = AppDI.get<FeedRepository>();
          final replyNote = await feedRepo.getNoteRaw(notificationEventId);

          if (replyNote != null) {
            final replyRootId = replyNote['rootId'] as String?;
            final parentId = replyNote['parentId'] as String?;

            if (replyRootId != null && replyRootId.isNotEmpty) {
              chain.add(replyRootId);
              if (parentId != null &&
                  parentId.isNotEmpty &&
                  parentId != replyRootId &&
                  parentId != notificationEventId) {
                chain.add(parentId);
              }
              chain.add(notificationEventId);
            } else {
              chain.add(targetEventId);
              if (notificationEventId != targetEventId) {
                chain.add(notificationEventId);
              }
            }
          } else {
            chain.add(targetEventId);
          }
        } catch (e) {
          debugPrint('[NotificationTile] Error resolving thread: $e');
          chain.add(targetEventId);
        }
      } else {
        chain.add(targetEventId);
      }

      if (!mounted) return;

      final chainStr = ThreadChain.build(chain);
      context.push('/home/notifications/thread/$chainStr');
    }
  }

  void _navigateToProfile(String pubkeyHex) async {
    try {
      final authService = AppDI.get<AuthService>();
      final npub = authService.hexToNpub(pubkeyHex) ?? pubkeyHex;
      context.push(
          '/home/notifications/profile?npub=${Uri.encodeComponent(npub)}&pubkeyHex=${Uri.encodeComponent(pubkeyHex)}');
    } catch (e) {
      debugPrint('[NotificationTile] Error navigating to profile: $e');
    }
  }

  Widget _buildTargetNote(BuildContext context) {
    final targetEventId = widget.notification['targetEventId'] as String? ?? '';
    if (targetEventId.isEmpty) return const SizedBox.shrink();

    try {
      final noteBech32 = encodeBasicBech32(targetEventId, 'note');
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: QuoteWidget(bech32: noteBech32, shortMode: true),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.notification['type'] as String? ?? '';
    final author = widget.notification['author'] as String? ?? '';
    final createdAt = widget.notification['createdAt'] as int?;
    final content = widget.notification['content'] as String? ?? '';

    final name = _profile?['name'] as String? ?? '';
    final image = _profile?['profileImage'] as String? ?? '';
    final displayName = name.isNotEmpty
        ? name
        : (author.length > 8 ? '${author.substring(0, 8)}...' : author);

    return GestureDetector(
      onTap: _onTap,
      child: Container(
        color: context.colors.background,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _navigateToProfile(author),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: context.colors.avatarPlaceholder,
                    backgroundImage: image.isNotEmpty
                        ? CachedNetworkImageProvider(image)
                        : null,
                    child: image.isEmpty
                        ? Icon(Icons.person,
                            size: 22, color: context.colors.textSecondary)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
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
                                    text: ' ${_getTypeText(context, type)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontSize: 15,
                                      color: context.colors.textPrimary,
                                    ),
                                  ),
                                  if (type == 'zap') ...[
                                    TextSpan(
                                      text: ' ${AppLocalizations.of(context)!.notificationZapSatsCount(widget.notification['zapAmount'] as int? ?? 0)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: context.colors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTimestamp(context, createdAt),
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (content.isNotEmpty &&
                          type != 'reaction' &&
                          type != 'repost') ...[
                        const SizedBox(height: 4),
                        Text(
                          content.length > 100
                              ? '${content.substring(0, 100)}...'
                              : content,
                          style: TextStyle(
                            fontSize: 14,
                            color: context.colors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            _buildTargetNote(context),
          ],
        ),
      ),
    );
  }
}

class _GroupedNotificationTile extends StatefulWidget {
  final Map<String, dynamic> notification;

  const _GroupedNotificationTile({required this.notification});

  @override
  State<_GroupedNotificationTile> createState() =>
      _GroupedNotificationTileState();
}

class _GroupedNotificationTileState extends State<_GroupedNotificationTile> {
  final Map<String, Map<String, dynamic>> _profiles = {};

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  List<Map<String, dynamic>> get _authors =>
      (widget.notification['groupedAuthors'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<void> _loadProfiles() async {
    for (final author in _authors) {
      final pubkey = author['author'] as String? ?? '';
      if (pubkey.isEmpty) continue;

      final name = author['fromName'] as String? ?? '';
      final image = author['fromImage'] as String? ?? '';

      if (name.isNotEmpty || image.isNotEmpty) {
        _profiles[pubkey] = {'name': name, 'profileImage': image};
        continue;
      }

      try {
        final profileRepo = AppDI.get<ProfileRepository>();
        final profile = await profileRepo.getProfile(pubkey);
        if (profile != null && mounted) {
          _profiles[pubkey] = {
            'name': profile.name ?? profile.displayName ?? '',
            'profileImage': profile.picture ?? '',
          };
        } else {
          final syncService = AppDI.get<SyncService>();
          await syncService.syncProfile(pubkey);
          final synced = await profileRepo.getProfile(pubkey);
          if (synced != null && mounted) {
            _profiles[pubkey] = {
              'name': synced.name ?? synced.displayName ?? '',
              'profileImage': synced.picture ?? '',
            };
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  String _displayName(Map<String, dynamic> author) {
    final pubkey = author['author'] as String? ?? '';
    final cached = _profiles[pubkey];
    final name = cached?['name'] as String? ??
        author['fromName'] as String? ??
        author['name'] as String? ??
        '';
    if (name.isNotEmpty) return name;
    return pubkey.length > 8 ? '${pubkey.substring(0, 8)}...' : pubkey;
  }

  String _profileImage(Map<String, dynamic> author) {
    final pubkey = author['author'] as String? ?? '';
    final cached = _profiles[pubkey];
    return cached?['profileImage'] as String? ??
        author['fromImage'] as String? ??
        author['profileImage'] as String? ??
        '';
  }

  String _getTypeText(BuildContext context, String type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case 'reaction':
        return l10n.reactedToYourPost;
      case 'repost':
        return l10n.repostedYourPost;
      case 'reply':
        return l10n.repliedToYourPost;
      case 'mention':
        return l10n.mentionedYou;
      case 'zap':
        return l10n.zappedYou;
      default:
        return l10n.interactedWithYou;
    }
  }

  String _formatTimestamp(BuildContext context, int? createdAt) {
    final l10n = AppLocalizations.of(context)!;
    if (createdAt == null || createdAt == 0) return '';

    final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return l10n.now;
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }

  void _onTap() {
    final targetEventId =
        widget.notification['targetEventId'] as String? ?? '';
    if (targetEventId.isEmpty) return;
    if (!mounted) return;

    final chainStr = ThreadChain.build([targetEventId]);
    context.push('/home/notifications/thread/$chainStr');
  }

  void _navigateToProfile(String pubkeyHex) {
    try {
      final authService = AppDI.get<AuthService>();
      final npub = authService.hexToNpub(pubkeyHex) ?? pubkeyHex;
      context.push(
          '/home/notifications/profile?npub=${Uri.encodeComponent(npub)}&pubkeyHex=${Uri.encodeComponent(pubkeyHex)}');
    } catch (_) {}
  }

  Widget _buildTargetNote(BuildContext context) {
    final targetEventId =
        widget.notification['targetEventId'] as String? ?? '';
    if (targetEventId.isEmpty) return const SizedBox.shrink();

    try {
      final noteBech32 = encodeBasicBech32(targetEventId, 'note');
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: QuoteWidget(bech32: noteBech32, shortMode: true),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildStackedAvatars(BuildContext context) {
    final authors = _authors;
    final displayCount = authors.length > 3 ? 3 : authors.length;
    const radius = 18.0;
    const overlap = 14.0;
    final totalWidth = radius * 2 + (displayCount - 1) * (radius * 2 - overlap);

    return GestureDetector(
      onTap: () {
        final firstAuthor = authors.first['author'] as String? ?? '';
        if (firstAuthor.isNotEmpty) _navigateToProfile(firstAuthor);
      },
      child: SizedBox(
        width: totalWidth,
        height: radius * 2,
        child: Stack(
          children: List.generate(displayCount, (i) {
            final reversedIndex = displayCount - 1 - i;
            final author = authors[reversedIndex];
            final image = _profileImage(author);
            return Positioned(
              left: reversedIndex * (radius * 2 - overlap),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.background,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: radius - 2,
                  backgroundColor: context.colors.avatarPlaceholder,
                  backgroundImage: image.isNotEmpty
                      ? CachedNetworkImageProvider(image)
                      : null,
                  child: image.isEmpty
                      ? Icon(Icons.person,
                          size: 16, color: context.colors.textSecondary)
                      : null,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  List<InlineSpan> _buildNameSpans(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authors = _authors;
    final type = widget.notification['type'] as String? ?? '';
    final spans = <InlineSpan>[];

    final nameStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 15,
      color: context.colors.textPrimary,
    );
    final normalStyle = TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 15,
      color: context.colors.textPrimary,
    );

    if (authors.length <= 3) {
      for (var i = 0; i < authors.length; i++) {
        if (i > 0 && i < authors.length) {
          spans.add(TextSpan(text: ', ', style: normalStyle));
        }
        spans.add(TextSpan(text: _displayName(authors[i]), style: nameStyle));
      }
    } else {
      spans.add(TextSpan(text: _displayName(authors[0]), style: nameStyle));
      spans.add(TextSpan(text: ', ', style: normalStyle));
      spans.add(TextSpan(text: _displayName(authors[1]), style: nameStyle));
      spans.add(TextSpan(
        text: ' ${l10n.andCountOthers(authors.length - 2)}',
        style: normalStyle,
      ));
    }

    spans.add(TextSpan(
      text: ' ${_getTypeText(context, type)}',
      style: normalStyle,
    ));

    if (type == 'zap') {
      final totalZapAmount =
          widget.notification['totalZapAmount'] as int? ?? 0;
      if (totalZapAmount > 0) {
        spans.add(TextSpan(
          text: ' ${l10n.notificationZapSatsCount(totalZapAmount)}',
          style: nameStyle,
        ));
      }
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = widget.notification['createdAt'] as int?;

    return GestureDetector(
      onTap: _onTap,
      child: Container(
        color: context.colors.background,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStackedAvatars(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(children: _buildNameSpans(context)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTimestamp(context, createdAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _buildTargetNote(context),
          ],
        ),
      ),
    );
  }
}
