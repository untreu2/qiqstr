import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../../data/services/encrypted_media_service.dart';
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
  
  final List<Map<String, dynamic>> _attachedEncryptedMedia = [];

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
  static const int _maxFileSizeBytes = 50 * 1024 * 1024; // 50MB

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

      final encryptedMediaService = EncryptedMediaService.instance;
      final encryptResult = await encryptedMediaService.encryptMediaFile(file.path!);

      if (!mounted) return;

      if (encryptResult.isError) {
        setState(() {
          _isUploadingMedia = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Encryption failed: ${encryptResult.error}')),
        );
        return;
      }

      final encryptedMetadata = encryptResult.data!;

      final syncService = AppDI.get<SyncService>();
      final url = await syncService.uploadMedia(encryptedMetadata.encryptedFilePath);

      if (!mounted) return;

      await encryptedMediaService.cleanupEncryptedFile(encryptedMetadata.encryptedFilePath);

      if (url != null && url.isNotEmpty) {
        setState(() {
          _attachedEncryptedMedia.add({
            'url': url,
            'mimeType': encryptedMetadata.mimeType,
            'encryptionKey': encryptedMetadata.encryptionKey,
            'encryptionNonce': encryptedMetadata.encryptionNonce,
            'encryptedHash': encryptedMetadata.encryptedHash,
            'originalHash': encryptedMetadata.originalHash,
            'fileSize': encryptedMetadata.encryptedSize,
          });
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload encrypted media')),
          );
        }
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

  
  void _removeAttachedMedia(int index) {
    setState(() {
      _attachedEncryptedMedia.removeAt(index);
    });
  }

  
  
  void _sendMessage(String recipientPubkeyHex) {
    if (_dmBloc == null) return;
    final textController = _textControllers[recipientPubkeyHex];
    final text = textController?.text.trim() ?? '';

    if (text.isEmpty && _attachedEncryptedMedia.isEmpty) return;

    if (text.isNotEmpty) {
      _dmBloc!.add(DmMessageSent(recipientPubkeyHex, text));
    }

    for (final media in _attachedEncryptedMedia) {
      _dmBloc!.add(DmEncryptedMediaSent(
        recipientPubkeyHex: recipientPubkeyHex,
        encryptedFileUrl: media['url'] as String,
        mimeType: media['mimeType'] as String,
        encryptionKey: media['encryptionKey'] as String,
        encryptionNonce: media['encryptionNonce'] as String,
        encryptedHash: media['encryptedHash'] as String,
        originalHash: media['originalHash'] as String,
        fileSize: media['fileSize'] as int,
      ));
    }

    textController?.clear();
    setState(() {
      _attachedEncryptedMedia.clear();
    });
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
    final messageKind = message['kind'] as int? ?? 14;

    if (messageKind == 15) {
      return _buildEncryptedMediaBubble(context, message);
    }

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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CarbonIcons.locked,
                    size: 10,
                    color: colors.textSecondary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(createdAt),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  
  
  Widget _buildEncryptedMediaBubble(
      BuildContext context, Map<String, dynamic> message) {
    final colors = context.colors;
    final isFromMe = message['isFromCurrentUser'] as bool? ?? false;
    final createdAt = message['createdAt'] as DateTime? ?? DateTime.now();
    final encryptedUrl = message['content'] as String? ?? '';
    final mimeType = message['mimeType'] as String? ?? 'application/octet-stream';
    final encryptionKey = message['encryptionKey'] as String?;
    final encryptionNonce = message['encryptionNonce'] as String?;
    final originalHash = message['originalHash'] as String?;

    if (encryptionKey == null || encryptionNonce == null || originalHash == null) {
      return _buildLegacyMediaBubble(context, message);
    }

    final isImage = mimeType.startsWith('image/');
    final isVideo = mimeType.startsWith('video/');

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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomRight: isFromMe ? const Radius.circular(4) : null,
                  bottomLeft: !isFromMe ? const Radius.circular(4) : null,
                ),
                child: FutureBuilder<Widget>(
                  future: _decryptAndDisplayMedia(
                    encryptedUrl: encryptedUrl,
                    decryptionKey: encryptionKey,
                    decryptionNonce: encryptionNonce,
                    originalHash: originalHash,
                    mimeType: mimeType,
                    isImage: isImage,
                    isVideo: isVideo,
                    colors: colors,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        height: 200,
                        color: colors.overlayLight,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return Container(
                        height: 100,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(CarbonIcons.locked,
                                color: colors.textSecondary, size: 24),
                            const SizedBox(height: 8),
                            Text(
                              'Failed to decrypt media',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return snapshot.data!;
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                right: isFromMe ? 8 : 0,
                left: !isFromMe ? 8 : 0,
                bottom: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CarbonIcons.locked,
                      size: 10, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(createdAt),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegacyMediaBubble(
      BuildContext context, Map<String, dynamic> message) {
    final colors = context.colors;
    final isFromMe = message['isFromCurrentUser'] as bool? ?? false;
    final createdAt = message['createdAt'] as DateTime? ?? DateTime.now();
    final mediaUrl = message['content'] as String? ?? '';
    final mimeType = message['mimeType'] as String? ?? '';
    
    final isImage = mimeType.startsWith('image/') || _isImageUrl(mediaUrl);
    
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
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20).copyWith(
                      bottomRight: isFromMe ? const Radius.circular(4) : null,
                      bottomLeft: !isFromMe ? const Radius.circular(4) : null,
                    ),
                    child: isImage
                        ? CachedNetworkImage(
                            imageUrl: mediaUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            placeholder: (_, __) => Container(
                              height: 200,
                              color: colors.overlayLight,
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              height: 100,
                              color: colors.overlayLight,
                              child: Icon(CarbonIcons.image,
                                  color: colors.textSecondary),
                            ),
                          )
                        : Container(
                            height: 100,
                            padding: const EdgeInsets.all(16),
                            color: colors.overlayLight,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(CarbonIcons.warning,
                                    color: colors.textSecondary, size: 24),
                                const SizedBox(height: 8),
                                Text(
                                  'Legacy unencrypted media',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CarbonIcons.warning,
                      size: 10, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Not encrypted · ${_formatTime(createdAt)}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  
  
  Future<Widget> _decryptAndDisplayMedia({
    required String encryptedUrl,
    required String decryptionKey,
    required String decryptionNonce,
    required String originalHash,
    required String mimeType,
    required bool isImage,
    required bool isVideo,
    required dynamic colors,
  }) async {
    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(encryptedUrl));
      final response = await request.close();
      
      final encryptedBytes = await response.fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      httpClient.close();

      final encryptedMediaService = EncryptedMediaService.instance;
      final fileExtension = encryptedMediaService.getFileExtensionFromMimeType(mimeType);
      
      final decryptResult = await encryptedMediaService.decryptMediaFile(
        encryptedBytes: Uint8List.fromList(encryptedBytes),
        decryptionKey: decryptionKey,
        decryptionNonce: decryptionNonce,
        originalHash: originalHash,
        fileExtension: fileExtension,
      );

      if (decryptResult.isError) {
        return Container(
          height: 150,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CarbonIcons.locked, color: colors.textSecondary, size: 24),
              const SizedBox(height: 8),
              Text(
                'Decryption Error',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                decryptResult.error ?? 'Unknown error',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }

      final decryptedFilePath = decryptResult.data!;

      if (isImage) {
        return GestureDetector(
          onTap: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => PhotoViewerWidget(imageUrls: [decryptedFilePath]),
              ),
            );
          },
          child: Image.file(
            File(decryptedFilePath),
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => Container(
              height: 100,
              color: colors.overlayLight,
              child: Icon(CarbonIcons.image, color: colors.textSecondary),
            ),
          ),
        );
      } else if (isVideo) {
        return Container(
          height: 200,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CarbonIcons.play_filled_alt,
                  color: colors.textSecondary, size: 48),
              const SizedBox(height: 8),
              Text(
                'Video (tap to play)',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      } else {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(CarbonIcons.document, size: 20, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'File: $fileExtension',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      return Container(
        height: 100,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CarbonIcons.locked, color: colors.textSecondary, size: 24),
            const SizedBox(height: 8),
            Text(
              'Decryption failed',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
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
    final colors = context.colors;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: colors.background,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachedEncryptedMedia.isNotEmpty || _isUploadingMedia)
            _buildAttachedMediaPreview(colors),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: _isUploadingMedia
                    ? null
                    : () => _selectMedia(recipientPubkeyHex),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.overlayLight,
                    shape: BoxShape.circle,
                  ),
                  child: _isUploadingMedia
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textPrimary,
                          ),
                        )
                      : Icon(
                          CarbonIcons.image,
                          color: colors.textPrimary,
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
                  textCapitalization: TextCapitalization.sentences,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _sendMessage(recipientPubkeyHex),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CarbonIcons.arrow_up,
                    color: colors.background,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachedMediaPreview(AppThemeColors colors) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _attachedEncryptedMedia.length + (_isUploadingMedia ? 1 : 0),
        itemBuilder: (context, index) {
          if (_isUploadingMedia && index == _attachedEncryptedMedia.length) {
            return Container(
              width: 80,
              height: 80,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: colors.overlayLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            );
          }

          final media = _attachedEncryptedMedia[index];
          final mimeType = media['mimeType'] as String;
          final isImage = mimeType.startsWith('image/');
          
          return Stack(
            children: [
              Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: colors.overlayLight,
                    child: Center(
                      child: Icon(
                        isImage ? CarbonIcons.image : CarbonIcons.play_filled,
                        color: colors.textSecondary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 12,
                child: GestureDetector(
                  onTap: () => _removeAttachedMedia(index),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: colors.background,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      color: colors.textPrimary,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
