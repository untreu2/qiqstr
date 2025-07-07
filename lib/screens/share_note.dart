import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/data_service.dart';
import '../models/user_model.dart';
import '../widgets/quote_widget.dart';
import '../widgets/reply_preview_widget.dart';

class ShareNotePage extends StatefulWidget {
  final DataService dataService;
  final String? initialText;
  final String? replyToNoteId;

  const ShareNotePage({
    super.key,
    required this.dataService,
    this.initialText,
    this.replyToNoteId,
  });

  @override
  _ShareNotePageState createState() => _ShareNotePageState();
}

class _ShareNotePageState extends State<ShareNotePage> {
  late TextEditingController _noteController;
  final FocusNode _focusNode = FocusNode();
  bool _isPosting = false;
  bool _isMediaUploading = false;
  final List<String> _mediaUrls = [];
  final String _serverUrl = "https://blossom.primal.net";
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialText ?? '');
    _loadProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadProfile() async {
    const storage = FlutterSecureStorage();
    final npub = await storage.read(key: 'npub');
    if (npub == null) return;

    final profileData = await widget.dataService.getCachedUserProfile(npub);

    if (!mounted) return;
    setState(() {
      _user = UserModel.fromCachedProfile(npub, profileData);
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _selectMedia() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.media,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _isMediaUploading = true;
      });
      try {
        for (var file in result.files) {
          if (file.path != null) {
            final url =
                await widget.dataService.sendMedia(file.path!, _serverUrl);
            if (mounted) {
              setState(() {
                _mediaUrls.add(url);
              });
            }
          }
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading media: $e')),
        );
      } finally {
        setState(() {
          _isMediaUploading = false;
        });
      }
    }
  }

  Future<void> _shareNote() async {
    if (_isPosting) return;
    if (_noteController.text.trim().isEmpty && _mediaUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a note')),
      );
      return;
    }
    setState(() {
      _isPosting = true;
    });
    try {
      final noteText = _noteController.text.trim();
      final mediaPart = _mediaUrls.isNotEmpty ? "\n${_mediaUrls.join("\n")}" : "";
      final finalNoteContent = "$noteText$mediaPart".trim();

      if (widget.replyToNoteId != null) {
        await widget.dataService.sendReply(widget.replyToNoteId!, finalNoteContent);
      } else {
        await widget.dataService.shareNote(finalNoteContent);
      }
      Navigator.of(context).pop();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing note: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
        });
      }
    }
  }

  void _removeMedia(String url) {
    setState(() {
      _mediaUrls.remove(url);
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          Row(
            children: [
              if (_isMediaUploading)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Uploading...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                onTap: _selectMedia,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Add media',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isPosting ? null : _shareNote,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: _isPosting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Post!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.replyToNoteId != null)
                ReplyPreviewWidget(
                  noteId: widget.replyToNoteId!,
                  dataService: widget.dataService,
                ),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white24,
                    backgroundImage: _user?.profileImage != null
                        ? CachedNetworkImageProvider(_user!.profileImage)
                        : null,
                    child: _user?.profileImage == null
                        ? const Icon(Icons.person,
                            color: Colors.white, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      focusNode: _focusNode,
                      controller: _noteController,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: const InputDecoration(
                        hintText: "What's on your mind?",
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_mediaUrls.isNotEmpty)
                SizedBox(
                  height: 170,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _mediaUrls.map((url) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  url,
                                  width: 160,
                                  height: 160,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 160,
                                    height: 160,
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => _removeMedia(url),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              if (widget.initialText != null && widget.initialText!.startsWith('nostr:'))
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: QuoteWidget(
                    bech32: widget.initialText!.replaceFirst('nostr:', ''),
                    dataService: widget.dataService,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
