import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme_manager.dart';
import '../../../core/ui/ui_state_builder.dart';
import '../../../presentation/providers/viewmodel_provider.dart';
import '../../../presentation/viewmodels/dm_viewmodel.dart';
import '../../../models/dm_message_model.dart';
import '../../widgets/common/title_widget.dart';
import '../search/users_search_page.dart';

class DmConversationsPage extends StatefulWidget {
  const DmConversationsPage({super.key});

  @override
  State<DmConversationsPage> createState() => _DmConversationsPageState();
}

class _DmConversationsPageState extends State<DmConversationsPage> with AutomaticKeepAliveClientMixin {
  bool _isInitialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ViewModelProvider.dm(
      builder: (context, viewModel) {
        if (!_isInitialized) {
          _isInitialized = true;
          Future.microtask(() {
            if (mounted) {
              viewModel.loadConversations();
            }
          });
        }

        return Consumer<DmViewModel>(
          builder: (context, vm, child) {
            return _buildConversationList(context, vm);
          },
        );
      },
    );
  }

  Widget _buildConversationList(BuildContext context, DmViewModel viewModel) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          UIStateBuilder<List<DmConversationModel>>(
            state: viewModel.conversationsState,
            builder: (context, conversations) {
              if (conversations.isEmpty) {
                return CustomScrollView(
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
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  await viewModel.refreshConversations();
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
                            viewModel,
                          );
                        },
                        separatorBuilder: (_, __) => const _ConversationSeparator(),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => CustomScrollView(
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
            error: (error) => CustomScrollView(
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
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => viewModel.loadConversations(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildTopBar(context, viewModel),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, DmViewModel viewModel) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 25,
      right: 16,
      child: GestureDetector(
        onTap: () => _showUserSearchDialog(context, viewModel),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: context.colors.textPrimary,
            borderRadius: BorderRadius.circular(40),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CarbonIcons.add,
                size: 22,
                color: context.colors.background,
              ),
              const SizedBox(width: 8),
              Text(
                'New message',
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationTile(
    BuildContext context,
    DmConversationModel conversation,
    DmViewModel viewModel,
  ) {
    return RepaintBoundary(
      child: InkWell(
        onTap: () {
          context.push('/home/dm/chat?pubkeyHex=${Uri.encodeComponent(conversation.otherUserPubkeyHex)}');
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
                backgroundImage: conversation.otherUserProfileImage != null && conversation.otherUserProfileImage!.isNotEmpty
                    ? CachedNetworkImageProvider(conversation.otherUserProfileImage!)
                    : null,
                child: conversation.otherUserProfileImage == null || conversation.otherUserProfileImage!.isEmpty
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
                            conversation.displayName,
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
                        if (conversation.lastMessageTime != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              _formatTime(conversation.lastMessageTime!),
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (conversation.lastMessage != null) ...[
                      Text(
                        conversation.lastMessage!.content,
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

  void _showUserSearchDialog(BuildContext context, DmViewModel viewModel) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UserSearchPage(
        onUserSelected: (user) {
          context.push('/home/dm/chat?pubkeyHex=${Uri.encodeComponent(user.pubkeyHex)}');
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
