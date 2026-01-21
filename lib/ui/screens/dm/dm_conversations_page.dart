import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme_manager.dart';
import '../../../presentation/blocs/dm/dm_bloc.dart';
import '../../../presentation/blocs/dm/dm_event.dart' as dm_events;
import '../../../presentation/blocs/dm/dm_state.dart';
import '../../../core/di/app_di.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/back_button_widget.dart';
import '../search/users_search_page.dart';

class DmConversationsPage extends StatefulWidget {
  const DmConversationsPage({super.key});

  @override
  State<DmConversationsPage> createState() => _DmConversationsPageState();
}

class _DmConversationsPageState extends State<DmConversationsPage>
    with AutomaticKeepAliveClientMixin {
  bool _isInitialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocProvider<DmBloc>(
      create: (context) {
        final bloc = AppDI.get<DmBloc>();
        if (!_isInitialized) {
          _isInitialized = true;
          Future.microtask(() {
            if (mounted) {
              bloc.add(const dm_events.DmConversationsLoadRequested());
            }
          });
        }
        return bloc;
      },
      child: BlocBuilder<DmBloc, DmState>(
        builder: (context, state) {
          return _buildConversationList(context, state);
        },
      ),
    );
  }

  Widget _buildConversationList(BuildContext context, DmState state) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          switch (state) {
            DmConversationsLoaded(:final conversations) => conversations.isEmpty
                ? CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: TitleWidget(
                          title: 'Messages',
                          fontSize: 32,
                          useTopPadding: true,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            MediaQuery.of(context).padding.top + 70,
                            16,
                            0,
                          ),
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(context),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      context
                          .read<DmBloc>()
                          .add(const dm_events.DmConversationsLoadRequested());
                    },
                    color: context.colors.textPrimary,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: TitleWidget(
                            title: 'Messages',
                            fontSize: 32,
                            useTopPadding: true,
                            padding: EdgeInsets.fromLTRB(
                              16,
                              MediaQuery.of(context).padding.top + 70,
                              16,
                              0,
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 8),
                          sliver: SliverList.separated(
                            itemCount: conversations.length,
                            itemBuilder: (context, index) {
                              return _buildConversationTile(
                                context,
                                conversations[index],
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const _ConversationSeparator(),
                          ),
                        ),
                      ],
                    ),
                  ),
            DmLoading() => CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: TitleWidget(
                      title: 'Messages',
                      fontSize: 32,
                      useTopPadding: true,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.of(context).padding.top + 70,
                        16,
                        0,
                      ),
                    ),
                  ),
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ],
              ),
            DmError() => CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: TitleWidget(
                      title: 'Messages',
                      fontSize: 32,
                      useTopPadding: true,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.of(context).padding.top + 70,
                        16,
                        0,
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Error loading conversations',
                            style:
                                TextStyle(color: context.colors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              context.read<DmBloc>().add(const dm_events
                                  .DmConversationsLoadRequested());
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            _ => CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: TitleWidget(
                      title: 'Messages',
                      fontSize: 32,
                      useTopPadding: true,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.of(context).padding.top + 70,
                        16,
                        0,
                      ),
                    ),
                  ),
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ],
              ),
          },
          _buildTopBar(context),
          const BackButtonWidget.floating(topOffset: 16),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 16,
      right: 16,
      child: GestureDetector(
        onTap: () => _showUserSearchDialog(context),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.colors.textPrimary,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            Icons.add,
            color: context.colors.background,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildConversationTile(
    BuildContext context,
    Map<String, dynamic> conversation,
  ) {
    final otherUserPubkeyHex =
        conversation['otherUserPubkeyHex'] as String? ?? '';
    final otherUserProfileImage =
        conversation['otherUserProfileImage'] as String?;
    final displayName = conversation['displayName'] as String? ?? '';
    final lastMessageTime = conversation['lastMessageTime'] as DateTime?;
    final lastMessage = conversation['lastMessage'] as Map<String, dynamic>?;
    final lastMessageContent = lastMessage?['content'] as String? ?? '';

    return RepaintBoundary(
      child: InkWell(
        onTap: () {
          if (otherUserPubkeyHex.isNotEmpty) {
            context.push(
                '/home/feed/dm/chat?pubkeyHex=${Uri.encodeComponent(otherUserPubkeyHex)}');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.colors.background,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: context.colors.border,
                backgroundImage: otherUserProfileImage != null &&
                        otherUserProfileImage.isNotEmpty
                    ? CachedNetworkImageProvider(otherUserProfileImage)
                    : null,
                child: otherUserProfileImage == null ||
                        otherUserProfileImage.isEmpty
                    ? Icon(
                        CarbonIcons.user,
                        color: context.colors.textSecondary,
                        size: 24,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 2.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (lastMessageTime != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              _formatTime(lastMessageTime),
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (lastMessageContent.isNotEmpty) ...[
                      Text(
                        lastMessageContent,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 2.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CarbonIcons.chat,
            size: 64,
            color: context.colors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation by messaging someone',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      final hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _showUserSearchDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UserSearchPage(
        onUserSelected: (user) {
          final pubkeyHex = user['pubkeyHex'] as String? ?? '';
          if (pubkeyHex.isNotEmpty) {
            context.push(
                '/home/feed/dm/chat?pubkeyHex=${Uri.encodeComponent(pubkeyHex)}');
          }
        },
      ),
    );
  }
}

class _ConversationSeparator extends StatelessWidget {
  const _ConversationSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Divider(
        height: 1,
        thickness: 0.6,
        color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
      ),
    );
  }
}
