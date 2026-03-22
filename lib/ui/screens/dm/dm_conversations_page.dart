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
      padding: const EdgeInsets.fromLTRB(16, 100, 16, 8),
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
          const SizedBox(height: 2),
          Text(
            l10n.dmEncryptionNotice,
            style: TextStyle(
              fontSize: 13,
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
            shape: BoxShape.circle,
          ),
          child: Icon(
            CarbonIcons.add,
            size: 24,
            color: context.colors.background,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final selected = _tabController.index;
          return Container(
            height: 48,
            decoration: BoxDecoration(
              color: context.colors.overlayLight,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              children: [
                _buildPillTab(
                  context,
                  label: l10n.dmTabFollowing,
                  index: 0,
                  selected: selected == 0,
                ),
                _buildPillTab(
                  context,
                  label: l10n.dmTabOther,
                  index: 1,
                  selected: selected == 1,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPillTab(
    BuildContext context, {
    required String label,
    required int index,
    required bool selected,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? context.colors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(36),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? context.colors.background
                  : context.colors.textSecondary,
            ),
          ),
        ),
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
    final following =
        conversations.where((c) => c['isFollowing'] == true).toList();
    final other = conversations.where((c) => c['isFollowing'] != true).toList();

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
      child: ListView.builder(
        padding: EdgeInsets.only(
          top: 4,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 100,
        ),
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          return _buildConversationTile(context, conversations[index]);
        },
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
    final isFromCurrentUser = lastMessage?['isFromCurrentUser'] == true;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () {
            if (otherUserPubkeyHex.isNotEmpty) {
              context.push(
                  '/home/dm/chat?pubkey=${Uri.encodeComponent(otherUserPubkeyHex)}');
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.overlayLight,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              children: [
                _buildAvatar(context, otherUserProfileImage),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.6,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lastMessageTime != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(lastMessageTime),
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (lastMessageContent.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              if (isFromCurrentUser)
                                TextSpan(
                                  text:
                                      AppLocalizations.of(context)!.dmYouPrefix,
                                  style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.6,
                                  ),
                                ),
                              TextSpan(
                                text: lastMessageContent,
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CarbonIcons.chevron_right,
                  size: 16,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, String? imageUrl) {
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colors.overlayLight,
      ),
      child: ClipOval(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _avatarPlaceholder(context),
              )
            : _avatarPlaceholder(context),
      ),
    );
  }

  Widget _avatarPlaceholder(BuildContext context) {
    return Container(
      color: context.colors.overlayLight,
      child: Icon(
        CarbonIcons.user,
        color: context.colors.textSecondary,
        size: 22,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                CarbonIcons.chat,
                size: 32,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.noConversationsYet,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.startConversationBy,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
          GestureDetector(
            onTap: () {
              context
                  .read<DmBloc>()
                  .add(const dm_events.DmConversationsLoadRequested());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.textPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Text(
                l10n.retryText,
                style: TextStyle(
                  color: context.colors.background,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
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
          final pubkeyHex = user['pubkey'] as String? ?? '';
          if (pubkeyHex.isNotEmpty) {
            context
                .push('/home/dm/chat?pubkey=${Uri.encodeComponent(pubkeyHex)}');
          }
        },
      ),
    );
  }
}
