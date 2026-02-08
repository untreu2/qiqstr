import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../presentation/blocs/dm/dm_bloc.dart';
import '../../../presentation/blocs/dm/dm_event.dart';
import '../../../presentation/blocs/dm/dm_state.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../search/users_search_page.dart';
import '../../../l10n/app_localizations.dart';

class DmPage extends StatefulWidget {
  const DmPage({super.key});

  @override
  State<DmPage> createState() => _DmPageState();
}

class _DmPageState extends State<DmPage> with AutomaticKeepAliveClientMixin {
  String? _selectedChatPubkeyHex;
  final Map<String, Map<String, dynamic>?> _userCache = {};
  final Map<String, TextEditingController> _textControllers = {};
  bool _isInitialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    super.dispose();
  }

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
              bloc.add(const DmConversationsLoadRequested());
            }
          });
        }
        return bloc;
      },
      child: BlocBuilder<DmBloc, DmState>(
        builder: (context, state) {
          if (_selectedChatPubkeyHex != null) {
            return _buildChatView(context, state, _selectedChatPubkeyHex!);
          }
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
          _buildConversationsContent(context, state),
          _buildTopBar(context),
        ],
      ),
    );
  }

  Widget _buildConversationsContent(BuildContext context, DmState state) {
    final l10n = AppLocalizations.of(context)!;
    
    if (state is DmConversationsLoaded) {
      final conversations = state.conversations;

      if (conversations.isEmpty) {
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: TitleWidget(
                title: l10n.messages,
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
          context.read<DmBloc>().add(const DmConversationsLoadRequested());
        },
        color: context.colors.textPrimary,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: TitleWidget(
                title: l10n.messages,
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
                separatorBuilder: (_, __) => const _ConversationSeparator(),
              ),
            ),
          ],
        ),
      );
    }

    if (state is DmLoading) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: TitleWidget(
              title: l10n.messages,
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
      );
    }

    if (state is DmError) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: TitleWidget(
              title: l10n.messages,
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
                    l10n.errorLoadingConversations,
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context
                          .read<DmBloc>()
                          .add(const DmConversationsLoadRequested());
                    },
                    child: Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context)!;
                        return Text(l10n.retryText);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: TitleWidget(
            title: l10n.messages,
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
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 25,
      right: 16,
      child: GestureDetector(
        onTap: () => _showUserSearchDialog(context),
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
                l10n.newMessage,
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
            setState(() {
              _selectedChatPubkeyHex = otherUserPubkeyHex;
            });
            context
                .read<DmBloc>()
                .add(DmConversationOpened(otherUserPubkeyHex));
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

  Widget _buildChatView(
    BuildContext context,
    DmState state,
    String otherUserPubkeyHex,
  ) {
    final otherUser = _userCache[otherUserPubkeyHex];

    if (otherUser == null && !_userCache.containsKey(otherUserPubkeyHex)) {
      _userCache[otherUserPubkeyHex] = null;
      AppDI.get<ProfileRepository>()
          .getProfile(otherUserPubkeyHex)
          .then((profile) {
        if (mounted && profile != null) {
          setState(() {
            _userCache[otherUserPubkeyHex] = {
              'pubkeyHex': profile.pubkey,
              'name': profile.name ?? '',
              'profileImage': profile.picture ?? '',
            };
          });
        }
      });
    }

    final double topPadding = MediaQuery.of(context).padding.top;
    final otherUserProfileImage = otherUser?['profileImage'] as String? ?? '';
    final otherUserName = otherUser?['name'] as String? ?? '';

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          _buildMessagesContent(context, state, topPadding),
          TopActionBarWidget(
            topOffset: 6,
            onBackPressed: () {
              setState(() {
                _selectedChatPubkeyHex = null;
              });
            },
            centerBubble: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.colors.avatarPlaceholder,
                    image: otherUserProfileImage.isNotEmpty
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(
                                otherUserProfileImage),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: otherUserProfileImage.isEmpty
                      ? Icon(
                          CarbonIcons.user,
                          size: 14,
                          color: context.colors.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  otherUserName.isNotEmpty
                      ? otherUserName
                      : _hexToNpub(otherUserPubkeyHex).substring(0, 12),
                  style: TextStyle(
                    color: context.colors.background,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            showShareButton: false,
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildMessageInput(context, otherUserPubkeyHex),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesContent(
      BuildContext context, DmState state, double topPadding) {
    final l10n = AppLocalizations.of(context)!;
    
    if (state is DmChatLoaded) {
      final messages = state.messages;

      if (messages.isEmpty) {
        return Center(
          child: Text(
            l10n.noMessagesYet,
            style: TextStyle(color: context.colors.textSecondary),
          ),
        );
      }

      final bottomPadding = MediaQuery.of(context).padding.bottom;
      return ListView.builder(
        padding: EdgeInsets.only(
          top: topPadding + 60,
          bottom: 80 + bottomPadding,
          left: 16,
          right: 16,
        ),
        reverse: true,
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[messages.length - 1 - index];
          return _buildMessageBubble(context, message);
        },
      );
    }

    if (state is DmLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state is DmError) {
      return Center(
        child: Text(
          'Error loading messages: ${state.message}',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildMessageBubble(
      BuildContext context, Map<String, dynamic> message) {
    final colors = context.colors;
    final isFromMe = message['isFromCurrentUser'] as bool? ?? false;
    final content = message['content'] as String? ?? '';
    final createdAt = message['createdAt'] as DateTime? ?? DateTime.now();

    return RepaintBoundary(
      child: Align(
        alignment: isFromMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isFromMe ? colors.textPrimary : colors.overlayLight,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomRight: isFromMe ? const Radius.circular(4) : null,
                  bottomLeft: !isFromMe ? const Radius.circular(4) : null,
                ),
              ),
              child: Text(
                content,
                style: TextStyle(
                  color: isFromMe ? colors.background : colors.textPrimary,
                  fontSize: 15,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                right: isFromMe ? 8 : 0,
                left: !isFromMe ? 8 : 0,
                bottom: 12,
              ),
              child: Text(
                _formatTime(createdAt),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(
    BuildContext context,
    String recipientPubkeyHex,
  ) {
    final l10n = AppLocalizations.of(context)!;
    
    if (!_textControllers.containsKey(recipientPubkeyHex)) {
      _textControllers[recipientPubkeyHex] = TextEditingController();
    }
    final textController = _textControllers[recipientPubkeyHex]!;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: context.colors.background,
      ),
      child: Row(
        children: [
          Expanded(
            child: CustomInputField(
              controller: textController,
              hintText: l10n.typeAMessage,
              maxLines: null,
              height: null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final content = textController.text.trim();
              if (content.isNotEmpty) {
                context
                    .read<DmBloc>()
                    .add(DmMessageSent(recipientPubkeyHex, content));
                textController.clear();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                CarbonIcons.arrow_up,
                color: context.colors.background,
                size: 22,
              ),
            ),
          ),
        ],
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

  String _hexToNpub(String hex) {
    try {
      if (hex.startsWith('npub1')) {
        return hex;
      }
      return encodeBasicBech32(hex, 'npub');
    } catch (e) {
      return hex;
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
            setState(() {
              _selectedChatPubkeyHex = pubkeyHex;
            });
            context.read<DmBloc>().add(DmConversationOpened(pubkeyHex));
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
