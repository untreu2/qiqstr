import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../../core/ui/ui_state_builder.dart';
import '../../../presentation/providers/viewmodel_provider.dart';
import '../../../presentation/viewmodels/dm_viewmodel.dart';
import '../../../models/dm_message_model.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../core/di/app_di.dart';
import '../../../models/user_model.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../search/users_search_page.dart';

class DmPage extends StatefulWidget {
  const DmPage({super.key});

  @override
  State<DmPage> createState() => _DmPageState();
}

class _DmPageState extends State<DmPage> with AutomaticKeepAliveClientMixin {
  String? _selectedChatPubkeyHex;
  final Map<String, UserModel?> _userCache = {};
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
            if (_selectedChatPubkeyHex != null) {
              return _buildChatView(context, vm, _selectedChatPubkeyHex!);
            }
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TitleWidget(
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
              Expanded(
                child: UIStateBuilder<List<DmConversationModel>>(
                  state: viewModel.conversationsState,
                  builder: (context, conversations) {
                    if (conversations.isEmpty) {
                      return _buildEmptyState(context);
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        await viewModel.refreshConversations();
                      },
                      color: context.colors.textPrimary,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 0, bottom: 8),
                        itemCount: conversations.length,
                        itemBuilder: (context, index) {
                          return Column(
                            children: [
                              _buildConversationTile(
                                context,
                                conversations[index],
                                viewModel,
                              ),
                              if (index < conversations.length - 1) const _ConversationSeparator(),
                            ],
                          );
                        },
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error) => Center(
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
              ),
            ],
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
          setState(() {
            _selectedChatPubkeyHex = conversation.otherUserPubkeyHex;
          });
          viewModel.loadMessages(conversation.otherUserPubkeyHex);
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

  Widget _buildChatView(
    BuildContext context,
    DmViewModel viewModel,
    String otherUserPubkeyHex,
  ) {
    final userRepository = AppDI.get<UserRepository>();
    final otherUserNpub = _hexToNpub(otherUserPubkeyHex);
    final otherUser = _userCache[otherUserPubkeyHex];

    if (otherUser == null && !_userCache.containsKey(otherUserPubkeyHex)) {
      _userCache[otherUserPubkeyHex] = null;
      userRepository.getUserProfile(otherUserNpub).then((result) {
        if (mounted) {
          setState(() {
            _userCache[otherUserPubkeyHex] = result.data;
          });
        }
      });
    }

    final double topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          UIStateBuilder<List<DmMessageModel>>(
            state: viewModel.messagesState,
            builder: (context, messages) {
              if (messages.isEmpty) {
                return Center(
                  child: Text(
                    'No messages yet',
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
            },
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (error) => Center(
              child: Text(
                'Error loading messages',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            ),
          ),
          TopActionBarWidget(
            topOffset: 6,
            onBackPressed: () {
              setState(() {
                _selectedChatPubkeyHex = null;
              });
              viewModel.clearCurrentChat();
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
                    image: otherUser?.profileImage != null && otherUser!.profileImage.isNotEmpty
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(otherUser.profileImage),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: otherUser?.profileImage == null || otherUser!.profileImage.isEmpty
                      ? Icon(
                          CarbonIcons.user,
                          size: 14,
                          color: context.colors.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  otherUser?.name.isNotEmpty == true ? otherUser!.name : otherUserNpub.substring(0, 8),
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
            child: _buildMessageInput(context, viewModel, otherUserPubkeyHex),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, DmMessageModel message) {
    final colors = context.colors;
    final isFromMe = message.isFromCurrentUser;

    return RepaintBoundary(
      child: Align(
        alignment: isFromMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                message.content,
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
                _formatTime(message.createdAt),
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
    DmViewModel viewModel,
    String recipientPubkeyHex,
  ) {
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
              hintText: 'Type a message...',
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
                viewModel.sendMessage(recipientPubkeyHex, content);
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

  void _showUserSearchDialog(BuildContext context, DmViewModel viewModel) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UserSearchPage(
        onUserSelected: (user) {
          final pubkeyHex = user.pubkeyHex;
          setState(() {
            _selectedChatPubkeyHex = pubkeyHex;
          });
          viewModel.loadMessages(pubkeyHex);
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

