import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/theme_manager.dart';
import '../../../presentation/blocs/dm/dm_bloc.dart';
import '../../../presentation/blocs/dm/dm_event.dart' as dm_events;
import '../../../presentation/blocs/dm/dm_state.dart';
import '../../../core/di/app_di.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../search/users_search_page.dart';
import '../../../l10n/app_localizations.dart';

class DmConversationsPage extends StatefulWidget {
  const DmConversationsPage({super.key});

  @override
  State<DmConversationsPage> createState() => _DmConversationsPageState();
}

class _DmConversationsPageState extends State<DmConversationsPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bloc = AppDI.get<DmBloc>();
    if (bloc.state is! DmConversationsLoaded && bloc.state is! DmLoading) {
      bloc.add(const dm_events.DmConversationsLoadRequested());
    }
    return BlocProvider<DmBloc>.value(
      value: bloc,
      child: BlocBuilder<DmBloc, DmState>(
        builder: (context, state) {
          if (state is DmConversationsLoaded) {
            return _buildPage(context, state);
          }
          final cached = bloc.cachedConversations;
          if (cached != null) {
            return _buildPage(context, DmConversationsLoaded(cached));
          }
          return _buildPage(context, state);
        },
      ),
    );
  }

  Widget _buildPage(BuildContext context, DmState state) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(context),
              _buildTabBar(context),
              Expanded(
                child: _buildTabContent(context, state),
              ),
            ],
          ),
          _buildNewMessageButton(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 100, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.messages,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dmEncryptionNotice,
            style: TextStyle(
              fontSize: 15,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewMessageButton(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
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

  Widget _buildTabBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colors.divider.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: context.colors.textPrimary,
        unselectedLabelColor: context.colors.textSecondary,
        indicatorColor: context.colors.textPrimary,
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 0,
        labelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        tabs: [
          Tab(text: l10n.dmTabFollowing),
          Tab(text: l10n.dmTabOther),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, DmState state) {
    if (state is! DmConversationsLoaded) {
      if (state is DmLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state is DmError) {
        return _buildErrorState(context);
      }
      return const Center(child: CircularProgressIndicator());
    }

    final conversations = state.conversations;
    final following = conversations
        .where((c) => c['isFollowing'] == true)
        .toList();
    final other = conversations
        .where((c) => c['isFollowing'] != true)
        .toList();

    return TabBarView(
      controller: _tabController,
      children: [
        _buildConversationsList(context, following),
        _buildConversationsList(context, other),
      ],
    );
  }

  Widget _buildConversationsList(
    BuildContext context,
    List<Map<String, dynamic>> conversations,
  ) {
    if (conversations.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: () async {
        context
            .read<DmBloc>()
            .add(const dm_events.DmConversationsLoadRequested());
      },
      color: context.colors.textPrimary,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          return _buildConversationTile(context, conversations[index]);
        },
        separatorBuilder: (_, __) => const _ConversationSeparator(),
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
    final otherUserName = conversation['otherUserName'] as String? ?? '';
    final displayName = otherUserName.isNotEmpty
        ? otherUserName
        : (otherUserPubkeyHex.length > 12
            ? otherUserPubkeyHex.substring(0, 12)
            : otherUserPubkeyHex);
    final lastMessageTime = conversation['lastMessageTime'] as DateTime?;
    final lastMessage = conversation['lastMessage'] as Map<String, dynamic>?;
    final lastMessageContent = lastMessage?['content'] as String? ?? '';

    return RepaintBoundary(
      child: InkWell(
        onTap: () {
          if (otherUserPubkeyHex.isNotEmpty) {
            context.push(
                '/home/dm/chat?pubkeyHex=${Uri.encodeComponent(otherUserPubkeyHex)}');
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
    final l10n = AppLocalizations.of(context)!;
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
            l10n.noConversationsYet,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.startConversationBy,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.errorLoadingConversations,
            style: TextStyle(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              context
                  .read<DmBloc>()
                  .add(const dm_events.DmConversationsLoadRequested());
            },
            child: Text(l10n.retryText),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      final hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (difference.inDays == 1) {
      return l10n.yesterday;
    } else if (difference.inDays < 7) {
      return l10n.daysAgo(difference.inDays);
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
                '/home/dm/chat?pubkeyHex=${Uri.encodeComponent(pubkeyHex)}');
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
