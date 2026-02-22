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
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: SliverList.separated(
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  return _NotificationTile(
                    notification: notifications[index],
                  );
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

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _navigateToProfile(author),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: context.colors.avatarPlaceholder,
                backgroundImage:
                    image.isNotEmpty ? CachedNetworkImageProvider(image) : null,
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
                  _buildTargetNote(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
