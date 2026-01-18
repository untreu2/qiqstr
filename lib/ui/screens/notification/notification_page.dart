import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/theme_manager.dart';
import '../../../presentation/blocs/notification/notification_bloc.dart';
import '../../../presentation/blocs/notification/notification_event.dart' as notification_events;
import '../../../presentation/blocs/notification/notification_state.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
      return item.notifications.any((notification) {
        final author = notification['author'] as String? ?? '';
        return author == currentUserNpub;
      });
    } else if (item is Map<String, dynamic>) {
      final author = item['author'] as String? ?? '';
      return author == currentUserNpub;
    }

    return false;
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notificationRepository = AppDI.get<NotificationRepository>();
      notificationRepository.saveLastVisitTimestamp();
    });
  }

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
            body: switch (state) {
              NotificationLoading() => _buildLoadingContent(context),
              NotificationError(:final message) => _buildErrorContent(context, message),
              NotificationsLoaded(:final notifications, :final currentUserNpub) => notifications.isEmpty
                  ? _buildEmptyContent(context)
                  : RefreshIndicator(
                      onRefresh: () async {
                        context.read<NotificationBloc>().add(const notification_events.NotificationsRefreshRequested());
                      },
                      color: context.colors.textPrimary,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: _buildHeader(context, state),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.only(bottom: 80),
                            sliver: SliverList.separated(
                              itemCount: notifications.where((item) => !_isSelfNotification(item, currentUserNpub)).length,
                              itemBuilder: (context, index) {
                                final filteredNotifications = notifications.where((item) => !_isSelfNotification(item, currentUserNpub)).toList();
                                return _buildNotificationTile(
                                  filteredNotifications[index],
                                  state,
                                  index,
                                );
                              },
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
                          ),
                        ],
                      ),
                    ),
              _ => _buildLoadingContent(context),
            },
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NotificationsLoaded state) {
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

  Widget _buildNotificationTile(dynamic item, NotificationsLoaded state, int index) {
    return _NotificationTileWidget(
      item: item,
      onNavigateToTargetNote: _navigateToTargetNote,
      onNavigateToAuthorProfile: _navigateToAuthorProfile,
      onNavigateToProfileFromContent: _navigateToProfileFromContent,
      parseContent: _parseContent,
      encodeEventId: _encodeEventId,
      formatTimestamp: _formatTimestamp,
    );
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
      final userRepository = AppDI.get<UserRepository>();
      final userResult = await userRepository.getUserProfile(npub);

      userResult.fold(
        (user) {
          if (context.mounted) {
            final userNpub = user['npub'] as String? ?? '';
            final userPubkeyHex = user['pubkeyHex'] as String? ?? '';
            context.push('/home/notifications/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
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

  Widget _buildErrorContent(BuildContext context, String message) {
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
              onPressed: () {
                context.read<NotificationBloc>().add(const notification_events.NotificationsLoadRequested());
              },
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
              color: context.colors.textSecondary.withValues(alpha: 0.5),
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

class _NotificationTileWidget extends StatefulWidget {
  final dynamic item;
  final void Function(String) onNavigateToTargetNote;
  final void Function(String) onNavigateToAuthorProfile;
  final void Function(String) onNavigateToProfileFromContent;
  final Map<String, dynamic> Function(String) parseContent;
  final String Function(String) encodeEventId;
  final String Function(DateTime) formatTimestamp;

  const _NotificationTileWidget({
    required this.item,
    required this.onNavigateToTargetNote,
    required this.onNavigateToAuthorProfile,
    required this.onNavigateToProfileFromContent,
    required this.parseContent,
    required this.encodeEventId,
    required this.formatTimestamp,
  });

  @override
  State<_NotificationTileWidget> createState() => _NotificationTileWidgetState();
}

class _NotificationTileWidgetState extends State<_NotificationTileWidget> {
  final Map<String, Map<String, dynamic>> _locallyLoadedProfiles = {};
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadProfilesAsync();
  }

  Future<void> _loadProfilesAsync() async {
    if (_isDisposed || !mounted) return;

    try {
      final authorNpubs = <String>{};
      
      if (widget.item is NotificationGroup) {
        for (final notification in (widget.item as NotificationGroup).notifications) {
          final author = notification['author'] as String? ?? '';
          if (author.isNotEmpty) authorNpubs.add(author);
        }
      } else if (widget.item is Map<String, dynamic>) {
        final author = (widget.item as Map<String, dynamic>)['author'] as String? ?? '';
        if (author.isNotEmpty) authorNpubs.add(author);
      }

      final userRepository = AppDI.get<UserRepository>();
      for (final npub in authorNpubs) {
        if (_isDisposed || !mounted) return;
        
        final currentProfile = _locallyLoadedProfiles[npub];
        final shouldLoad = currentProfile == null ||
            (currentProfile['profileImage'] as String? ?? '').isEmpty ||
            (currentProfile['name'] as String? ?? '').isEmpty ||
            (currentProfile['name'] as String? ?? '') ==
                (npub.length > 8 ? npub.substring(0, 8) : npub);

        if (shouldLoad) {
          final userResult = await userRepository.getUserProfile(npub);
          userResult.fold(
            (user) {
              if (mounted && !_isDisposed) {
                setState(() {
                  _locallyLoadedProfiles[npub] = user;
                });
              }
            },
            (_) {},
          );
        }
      }
    } catch (e) {
      debugPrint('[NotificationTile] Load profiles error: $e');
    }
  }

  Map<String, dynamic> _getProfile(String npub) {
    return _locallyLoadedProfiles[npub] ?? {
      'pubkeyHex': npub,
      'name': npub.length > 8 ? npub.substring(0, 8) : npub,
      'about': '',
      'profileImage': '',
      'banner': '',
      'website': '',
      'nip05': '',
      'lud16': '',
      'updatedAt': DateTime.now(),
      'nip05Verified': false,
    };
  }

  String _buildGroupTitle(dynamic item, Map<String, Map<String, dynamic>> userProfiles) {
    if (item is NotificationGroup) {
      final notifications = item.notifications;
      final first = notifications.first;
      final count = notifications.length;
      final firstType = first['type'] as String? ?? '';
      final firstAuthor = first['author'] as String? ?? '';

      switch (firstType) {
        case 'reaction':
          if (count == 1) {
            final profile = userProfiles[firstAuthor] ?? _getProfile(firstAuthor);
            final name = (profile['name'] as String? ?? '').isNotEmpty ? profile['name'] as String : 'Someone';
            return '$name reacted to your post';
          } else {
            final personWord = count == 1 ? 'person' : 'people';
            return '$count $personWord reacted to your post';
          }
        case 'mention':
          if (count == 1) {
            final profile = userProfiles[firstAuthor] ?? _getProfile(firstAuthor);
            final name = (profile['name'] as String? ?? '').isNotEmpty ? profile['name'] as String : 'Someone';
            return '$name mentioned you';
          } else {
            final personWord = count == 1 ? 'person' : 'people';
            return '$count $personWord mentioned you';
          }
        case 'repost':
          if (count == 1) {
            final profile = userProfiles[firstAuthor] ?? _getProfile(firstAuthor);
            final name = (profile['name'] as String? ?? '').isNotEmpty ? profile['name'] as String : 'Someone';
            return '$name reposted your post';
          } else {
            final personWord = count == 1 ? 'person' : 'people';
            return '$count $personWord reposted your post';
          }
        default:
          return 'Notification';
      }
    } else if (item is Map<String, dynamic>) {
      final itemAuthor = item['author'] as String? ?? '';
      final itemType = item['type'] as String? ?? '';
      final profile = userProfiles[itemAuthor] ?? _getProfile(itemAuthor);
      final name = (profile['name'] as String? ?? '').isNotEmpty ? profile['name'] as String : 'Someone';

      switch (itemType) {
        case 'zap':
          return '$name zapped your post ${item['amount'] as int? ?? 0} sats';
        case 'reaction':
          return '$name reacted to your post';
        case 'mention':
          return '$name mentioned you';
        case 'repost':
          return '$name reposted your post';
        case 'follow':
          return '$name started following you';
        case 'unfollow':
          return '$name unfollowed you';
        default:
          return 'Notification from $name';
      }
    }

    return 'Notification';
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item is NotificationGroup) {
      final first = (widget.item as NotificationGroup).notifications.first;
      final firstAuthor = first['author'] as String? ?? '';
      final profile = _getProfile(firstAuthor);
      final image = profile['profileImage'] as String? ?? '';
      final targetEventId = first['targetEventId'] as String? ?? '';

      return GestureDetector(
        onTap: () => widget.onNavigateToTargetNote(targetEventId),
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
                      onTap: () => widget.onNavigateToAuthorProfile(firstAuthor),
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
                              final titleText = _buildGroupTitle(widget.item, _locallyLoadedProfiles);
                              final titleStyle = TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: context.colors.textPrimary,
                                height: 1.3,
                              );
                              if ((widget.item as NotificationGroup).notifications.length == 1) {
                                return GestureDetector(
                                  onTap: () => widget.onNavigateToAuthorProfile(firstAuthor),
                                  child: Text(titleText, style: titleStyle),
                                );
                              } else {
                                return Text(titleText, style: titleStyle);
                              }
                            },
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.formatTimestamp(() {
                              final timestamp = first['timestamp'];
                              if (timestamp is DateTime) return timestamp;
                              if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
                              final createdAt = first['created_at'] as int? ?? 0;
                              return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
                            }()),
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          if (() {
                            final content = first['content'] as String? ?? '';
                            final type = first['type'] as String? ?? '';
                            return content.trim().isNotEmpty && type != 'repost' && type != 'reaction';
                          }()) ...[
                            const SizedBox(height: 4),
                            NoteContentWidget(
                              parsedContent: widget.parseContent(first['content'] as String? ?? ''),
                              noteId: first['id'] as String? ?? '',
                              onNavigateToMentionProfile: widget.onNavigateToProfileFromContent,
                            ),
                          ],
                          const SizedBox(height: 2),
                          QuoteWidget(
                            bech32: widget.encodeEventId(targetEventId),
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
    } else if (widget.item is Map<String, dynamic> && ((widget.item as Map<String, dynamic>)['type'] as String? ?? '') == 'zap') {
      final item = widget.item as Map<String, dynamic>;
      final itemAuthor = item['author'] as String? ?? '';
      final profile = _getProfile(itemAuthor);
      final image = profile['profileImage'] as String? ?? '';
      final profileName = profile['name'] as String? ?? '';
      final displayName = profileName.isNotEmpty ? profileName : 'Anonymous';
      final targetEventId = item['targetEventId'] as String? ?? '';

      return GestureDetector(
        onTap: () => widget.onNavigateToTargetNote(targetEventId),
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
                      onTap: () => widget.onNavigateToAuthorProfile(itemAuthor),
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
                            onTap: () => widget.onNavigateToAuthorProfile(itemAuthor),
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
                                    text: '${item['amount'] as int? ?? 0} sats',
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
                            widget.formatTimestamp(() {
                              final timestamp = item['timestamp'];
                              if (timestamp is DateTime) return timestamp;
                              if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
                              final createdAt = item['created_at'] as int? ?? 0;
                              return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
                            }()),
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          if (() {
                            final content = item['content'] as String? ?? '';
                            return content.trim().isNotEmpty;
                          }()) ...[
                            const SizedBox(height: 4),
                            Text(
                              item['content'] as String? ?? '',
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          QuoteWidget(
                            bech32: widget.encodeEventId(targetEventId),
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
    } else if (widget.item is Map<String, dynamic>) {
      final item = widget.item as Map<String, dynamic>;
      final itemAuthor = item['author'] as String? ?? '';
      final itemType = item['type'] as String? ?? '';
      final profile = _getProfile(itemAuthor);
      final image = profile['profileImage'] as String? ?? '';
      final targetEventId = item['targetEventId'] as String? ?? '';

      return GestureDetector(
        onTap: () {
          if (itemType == 'follow' || itemType == 'unfollow') {
            widget.onNavigateToAuthorProfile(itemAuthor);
          } else {
            widget.onNavigateToTargetNote(targetEventId);
          }
        },
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
                      onTap: () => widget.onNavigateToAuthorProfile(itemAuthor),
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
                            onTap: () => widget.onNavigateToAuthorProfile(itemAuthor),
                            child: Text(
                              _buildGroupTitle(widget.item, _locallyLoadedProfiles),
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
                            widget.formatTimestamp(() {
                              final timestamp = item['timestamp'];
                              if (timestamp is DateTime) return timestamp;
                              if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
                              final createdAt = item['created_at'] as int? ?? 0;
                              return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
                            }()),
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          if (() {
                            final content = item['content'] as String? ?? '';
                            return content.trim().isNotEmpty && itemType != 'repost' && itemType != 'reaction' && itemType != 'follow' && itemType != 'unfollow';
                          }()) ...[
                            const SizedBox(height: 4),
                            NoteContentWidget(
                              parsedContent: widget.parseContent(item['content'] as String? ?? ''),
                              noteId: item['id'] as String? ?? '',
                              onNavigateToMentionProfile: widget.onNavigateToProfileFromContent,
                            ),
                          ],
                          if (itemType != 'follow' && itemType != 'unfollow') ...[
                            const SizedBox(height: 2),
                            QuoteWidget(
                              bech32: widget.encodeEventId(targetEventId),
                            ),
                          ],
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
}
