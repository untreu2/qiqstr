import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../../data/sync/sync_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../presentation/blocs/dm/dm_bloc.dart';
import '../../../presentation/blocs/dm/dm_event.dart';
import '../../../presentation/blocs/dm/dm_state.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/media/photo_viewer_widget.dart';

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
  final Map<String, Map<String, dynamic>?> _userCache = {};
  final Map<String, TextEditingController> _textControllers = {};
  bool _isInitialized = false;
  bool _isUploadingMedia = false;
  DmBloc? _dmBloc;

  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
  static const _videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm'];
  static const _blossomHosts = [
    'blossom.primal.net',
    'blossom.oxtr.dev',
    'blossom.band',
    'cdn.satellite.earth',
    'files.v0l.io',
    'void.cat',
    'nostr.build',
    'image.nostr.build',
  ];
  static final _hexHashPattern = RegExp(r'/[0-9a-f]{64}$');
  static const int _maxFileSizeBytes = 50 * 1024 * 1024;

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    super.dispose();
  }

  Future<void> _selectMedia(String recipientPubkeyHex) async {
    if (_isUploadingMedia || !mounted || _dmBloc == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.media,
      );

      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.first;
      if (file.path == null) return;

      if (file.size > _maxFileSizeBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File is too large (max 50MB)')),
          );
        }
        return;
      }

      setState(() {
        _isUploadingMedia = true;
      });

      final syncService = AppDI.get<SyncService>();
      final url = await syncService.uploadMedia(file.path!);

      if (!mounted) return;

      if (url != null && url.isNotEmpty) {
        final textController = _textControllers[recipientPubkeyHex];
        final currentText = textController?.text.trim() ?? '';
        final content = currentText.isNotEmpty ? '$currentText\n$url' : url;

        _dmBloc!.add(DmMessageSent(recipientPubkeyHex, content));
        textController?.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload media')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DmBloc>(
      create: (context) {
        final bloc = AppDI.get<DmBloc>();
        _dmBloc = bloc;
        if (!_isInitialized) {
          _isInitialized = true;
          Future.microtask(() {
            if (mounted) {
              bloc.add(DmConversationOpened(widget.pubkeyHex));
            }
          });
        }
        return bloc;
      },
      child: BlocBuilder<DmBloc, DmState>(
        builder: (context, state) {
          return _buildChatView(context, state, widget.pubkeyHex);
        },
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

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          switch (state) {
            DmChatLoaded(:final messages, :final pubkeyHex)
                when pubkeyHex == otherUserPubkeyHex =>
              messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final bottomPadding =
                            MediaQuery.of(context).padding.bottom;
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
                            final message =
                                messages[messages.length - 1 - index];
                            return _buildMessageBubble(context, message);
                          },
                        );
                      },
                    ),
            DmLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            DmError(:final message) => Center(
                child: Text(
                  'Error loading messages: $message',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
              ),
            _ => const Center(
                child: CircularProgressIndicator(),
              ),
          },
          TopActionBarWidget(
            topOffset: 6,
            onBackPressed: () {
              context.pop();
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
                    image: otherUser != null
                        ? (otherUser['profileImage'] as String? ?? '')
                                .isNotEmpty
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(
                                    otherUser['profileImage'] as String),
                                fit: BoxFit.cover,
                              )
                            : null
                        : null,
                  ),
                  child: otherUser == null ||
                          (otherUser['profileImage'] as String? ?? '').isEmpty
                      ? Icon(
                          CarbonIcons.user,
                          size: 14,
                          color: context.colors.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  otherUser != null &&
                          (otherUser['name'] as String? ?? '').isNotEmpty
                      ? otherUser['name'] as String
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
          if (state is DmChatLoaded && state.pubkeyHex == otherUserPubkeyHex)
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

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    if (_imageExtensions.any((ext) => lower.endsWith('.$ext'))) return true;
    if (_isBlossomUrl(url)) return true;
    return false;
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return _videoExtensions.any((ext) => lower.endsWith('.$ext'));
  }

  bool _isBlossomUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (_blossomHosts.any((h) => host == h || host.endsWith('.$h'))) {
        return true;
      }
      if (_hexHashPattern.hasMatch(uri.path)) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  bool _isMediaUrl(String url) {
    return _isImageUrl(url) || _isVideoUrl(url);
  }

  ({String text, List<String> mediaUrls}) _parseMessageContent(String content) {
    final lines = content.split('\n');
    final textLines = <String>[];
    final mediaUrls = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        if (_isMediaUrl(trimmed)) {
          mediaUrls.add(trimmed);
        } else {
          textLines.add(line);
        }
      } else {
        textLines.add(line);
      }
    }

    return (text: textLines.join('\n').trim(), mediaUrls: mediaUrls);
  }

  Widget _buildMessageBubble(
      BuildContext context, Map<String, dynamic> message) {
    final colors = context.colors;
    final isFromMe = message['isFromCurrentUser'] as bool? ?? false;
    final content = message['content'] as String? ?? '';
    final createdAt = message['createdAt'] as DateTime? ?? DateTime.now();

    final parsed = _parseMessageContent(content);

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
              decoration: BoxDecoration(
                color: isFromMe ? colors.textPrimary : colors.overlayLight,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomRight: isFromMe ? const Radius.circular(4) : null,
                  bottomLeft: !isFromMe ? const Radius.circular(4) : null,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (parsed.mediaUrls.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20).copyWith(
                        bottomRight: parsed.text.isNotEmpty
                            ? null
                            : (isFromMe ? const Radius.circular(4) : null),
                        bottomLeft: parsed.text.isNotEmpty
                            ? null
                            : (!isFromMe ? const Radius.circular(4) : null),
                      ),
                      child: Column(
                        children: parsed.mediaUrls.map((url) {
                          if (_isImageUrl(url)) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PhotoViewerWidget(imageUrls: [url]),
                                  ),
                                );
                              },
                              child: CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                placeholder: (_, __) => Container(
                                  height: 200,
                                  color: colors.overlayLight,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  height: 100,
                                  color: colors.overlayLight,
                                  child: Icon(CarbonIcons.image,
                                      color: colors.textSecondary),
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(CarbonIcons.play_filled,
                                    size: 20, color: colors.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    url.split('/').last,
                                    style: TextStyle(
                                      color: isFromMe
                                          ? colors.background
                                          : colors.accent,
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  if (parsed.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Text(
                        parsed.text,
                        style: TextStyle(
                          color:
                              isFromMe ? colors.background : colors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                ],
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
          GestureDetector(
            onTap: _isUploadingMedia
                ? null
                : () => _selectMedia(recipientPubkeyHex),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                shape: BoxShape.circle,
              ),
              child: _isUploadingMedia
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.textPrimary,
                      ),
                    )
                  : Icon(
                      CarbonIcons.image,
                      color: context.colors.textPrimary,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 8),
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
              if (content.isNotEmpty && _dmBloc != null) {
                _dmBloc!.add(DmMessageSent(recipientPubkeyHex, content));
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
