import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../../theme/theme_manager.dart';
import '../../../core/ui/ui_state_builder.dart';
import '../../../presentation/providers/viewmodel_provider.dart';
import '../../../presentation/viewmodels/dm_viewmodel.dart';
import '../../../models/dm_message_model.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../core/di/app_di.dart';
import '../../../models/user_model.dart';

class DmChatPage extends StatefulWidget {
  final String pubkeyHex;

  const DmChatPage({
    super.key,
    required this.pubkeyHex,
  });

  @override
  State<DmChatPage> createState() => _DmChatPageState();
}

class _DmChatPageState extends State<DmChatPage> {
  final Map<String, UserModel?> _userCache = {};
  final Map<String, TextEditingController> _textControllers = {};
  bool _isInitialized = false;

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
    return ViewModelProvider.dm(
      builder: (context, viewModel) {
        if (!_isInitialized) {
          _isInitialized = true;
          Future.microtask(() {
            if (mounted) {
              viewModel.loadMessages(widget.pubkeyHex);
            }
          });
        }

        return Consumer<DmViewModel>(
          builder: (context, vm, child) {
            return _buildChatView(context, vm, widget.pubkeyHex);
          },
        );
      },
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
              context.pop();
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
}
