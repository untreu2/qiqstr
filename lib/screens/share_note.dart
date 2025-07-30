import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../services/data_service.dart';
import '../models/user_model.dart';
import '../widgets/quote_widget.dart';
import '../widgets/reply_preview_widget.dart';
import '../theme/theme_manager.dart';

class ShareNotePage extends StatefulWidget {
  final DataService dataService;
  final String? initialText;
  final String? replyToNoteId;
//
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
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  bool _isSearchingUsers = false;
  String _userSearchQuery = '';
  final Map<String, String> _mentionMap = {};
  TextSpan _richTextSpan = const TextSpan();

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _loadProfile();
    _loadUsers();
    _noteController.addListener(_onTextChanged);
    _initializeText();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _initializeText() async {
    String initialText = (widget.initialText != null && widget.initialText!.startsWith('nostr:')) ? '' : widget.initialText ?? '';

    final mentionRegex = RegExp(r'nostr:(npub1[0-9a-z]+)');
    final matches = mentionRegex.allMatches(initialText);

    if (matches.isEmpty) {
      if (mounted) {
        setState(() {
          _noteController.text = initialText;
          _updateRichText();
        });
      }
      return;
    }

    final npubs = matches.map((m) => m.group(1)!).toList();
    final resolvedNames = await widget.dataService.resolveMentions(npubs);

    String newText = initialText;
    for (var match in matches.toList().reversed) {
      final npub = match.group(1)!;
      final username = (resolvedNames[npub] ?? npub.substring(0, 10)).replaceAll(' ', '_');
      final mentionKey = '@$username';
      _mentionMap[mentionKey] = 'nostr:$npub';
      newText = newText.replaceRange(match.start, match.end, mentionKey);
    }

    if (mounted) {
      setState(() {
        _noteController.text = newText;
        _updateRichText();
      });
    }
  }

  Future<void> _loadUsers() async {
    final box = await Hive.openBox<UserModel>('users');
    if (mounted) {
      setState(() {
        _allUsers = box.values.toList();
      });
    }
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
    _noteController.removeListener(_onTextChanged);
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
            final url = await widget.dataService.sendMedia(file.path!, _serverUrl);
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

    final hasQuote = widget.initialText != null && widget.initialText!.startsWith('nostr:');

    String noteText = _noteController.text;
    _mentionMap.forEach((key, value) {
      noteText = noteText.replaceAll(key, value);
    });
    noteText = noteText.trim();

    if (noteText.isEmpty && _mediaUrls.isEmpty && !hasQuote) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a note')),
      );
      return;
    }

    setState(() {
      _isPosting = true;
    });

    try {
      final mediaPart = _mediaUrls.isNotEmpty ? "\n\n${_mediaUrls.join("\n")}" : "";
      final quotePart = hasQuote ? "\n\n${widget.initialText}" : "";
      final finalNoteContent = "$noteText$mediaPart$quotePart".trim();

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

  void _reorderMedia(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final String item = _mediaUrls.removeAt(oldIndex);
      _mediaUrls.insert(newIndex, item);
    });
  }

  void _onTextChanged() {
    _updateRichText();
    final text = _noteController.text;
    final cursorPos = _noteController.selection.baseOffset;

    if (cursorPos == -1) {
      if (mounted) {
        setState(() {
          _isSearchingUsers = false;
        });
      }
      return;
    }

    final textBeforeCursor = text.substring(0, cursorPos);
    final words = textBeforeCursor.split(' ');
    final currentWord = words.isNotEmpty ? words.last : '';

    if (currentWord.startsWith('@')) {
      final searchQuery = currentWord.substring(1);
      if (mounted) {
        setState(() {
          _userSearchQuery = searchQuery;
          _isSearchingUsers = true;
          _filterUsers();
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isSearchingUsers = false;
        });
      }
    }
  }

  void _filterUsers() {
    if (_userSearchQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _filteredUsers = _allUsers.take(5).toList();
        });
      }
      return;
    }

    final query = _userSearchQuery.toLowerCase();
    final filtered = _allUsers.where((user) {
      return user.name.toLowerCase().contains(query) || user.nip05.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) => a.name.toLowerCase().indexOf(query).compareTo(b.name.toLowerCase().indexOf(query)));

    if (mounted) {
      setState(() {
        _filteredUsers = filtered.take(5).toList();
      });
    }
  }

  void _onUserSelected(UserModel user) {
    final text = _noteController.text;
    final selection = _noteController.selection;
    final cursorPos = selection.baseOffset;

    if (cursorPos == -1) return;

    final textBeforeCursor = text.substring(0, cursorPos);
    final atIndex = textBeforeCursor.lastIndexOf('@');

    if (atIndex == -1) return;

    final username = user.name.replaceAll(' ', '_');
    final mentionKey = '@$username';
    final npubBech32 = encodeBasicBech32(user.npub, 'npub');
    _mentionMap[mentionKey] = 'nostr:$npubBech32';

    final textAfterCursor = text.substring(cursorPos);
    final newText = '${text.substring(0, atIndex)}$mentionKey $textAfterCursor';

    final newCursorPos = atIndex + mentionKey.length + 1;

    if (mounted) {
      _noteController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.fromPosition(TextPosition(offset: newCursorPos)),
      );

      setState(() {
        _isSearchingUsers = false;
        _filteredUsers = [];
      });
    }
  }

  void _updateRichText() {
    final text = _noteController.text;
    final spans = <InlineSpan>[];
    var lastEnd = 0;

    final mentionKeys = _mentionMap.keys.map((e) => RegExp.escape(e)).join('|');

    final pattern = [if (mentionKeys.isNotEmpty) '($mentionKeys)', r'(https?:\/\/[^\s]+)', r'(#\w+)'].where((p) => p.isNotEmpty).join('|');

    if (pattern.isEmpty) {
      spans.add(TextSpan(text: text));
    } else {
      final regex = RegExp(pattern, caseSensitive: false);
      final matches = regex.allMatches(text);

      for (final match in matches) {
        if (match.start > lastEnd) {
          spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
        }

        final matchedText = match.group(0)!;
        if (_mentionMap.containsKey(matchedText)) {
          spans.add(
            TextSpan(
              text: matchedText,
              style: TextStyle(
                color: context.colors.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        } else if (matchedText.startsWith('http')) {
          spans.add(
            TextSpan(
              text: matchedText,
              style: TextStyle(color: context.colors.accent),
            ),
          );
        } else if (matchedText.startsWith('#')) {
          spans.add(
            TextSpan(
              text: matchedText,
              style: TextStyle(color: context.colors.accent),
            ),
          );
        }
        lastEnd = match.end;
      }

      if (lastEnd < text.length) {
        spans.add(TextSpan(text: text.substring(lastEnd)));
      }
    }

    if (mounted) {
      setState(() {
        _richTextSpan = TextSpan(
          children: spans,
          style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(fontSize: 15, height: 1.4);
    final strutStyle = StrutStyle(fontSize: 15, height: 1.4);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          if (_mediaUrls.isNotEmpty)
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Container(
                  key: ValueKey(_mediaUrls.first),
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: CachedNetworkImageProvider(_mediaUrls.first),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: context.colors.background,
                    ),
                  ),
                ),
              ),
            ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.colors.textPrimary, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              actions: [
                Row(
                  children: [
                    if (_isMediaUploading)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Uploading...',
                              style: TextStyle(
                                color: context.colors.textPrimary,
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
                          color: context.colors.surfaceTransparent,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: context.colors.borderLight),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.attach_file, size: 16, color: context.colors.textPrimary),
                            const SizedBox(width: 6),
                            Text(
                              'Add media',
                              style: TextStyle(
                                color: context.colors.textPrimary,
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
                          color: context.colors.surfaceTransparent,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: context.colors.borderLight),
                        ),
                        child: _isPosting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
                                ),
                              )
                            : Text(
                                'Post!',
                                style: TextStyle(
                                  color: context.colors.textPrimary,
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
              child: Column(
                children: [
                  Expanded(
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: context.colors.surfaceTransparent,
                                backgroundImage: _user?.profileImage != null ? CachedNetworkImageProvider(_user!.profileImage) : null,
                                child: _user?.profileImage == null ? Icon(Icons.person, color: context.colors.textPrimary, size: 20) : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Stack(
                                  children: [
                                    RichText(
                                      text: _richTextSpan,
                                      strutStyle: strutStyle,
                                    ),
                                    TextField(
                                      focusNode: _focusNode,
                                      controller: _noteController,
                                      maxLines: null,
                                      textAlignVertical: TextAlignVertical.top,
                                      style: textStyle.copyWith(color: Colors.transparent),
                                      cursorColor: context.colors.textPrimary,
                                      strutStyle: strutStyle,
                                      decoration: InputDecoration(
                                        hintText: _noteController.text.isEmpty ? "What's on your mind?" : "",
                                        hintStyle: textStyle.copyWith(color: context.colors.textSecondary),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        isCollapsed: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_mediaUrls.isNotEmpty)
                            SizedBox(
                              height: 170,
                              child: ReorderableListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _mediaUrls.length,
                                onReorder: _reorderMedia,
                                itemBuilder: (context, index) {
                                  final url = _mediaUrls[index];
                                  return Padding(
                                    key: ValueKey(url),
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
                                              color: context.colors.surface,
                                              child: const Icon(Icons.broken_image),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: GestureDetector(
                                            onTap: () => _removeMedia(url),
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: context.colors.background,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.close,
                                                color: context.colors.textPrimary,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
                  if (_isSearchingUsers) _buildUserSuggestions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSuggestions() {
    if (_filteredUsers.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 4.0,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        topRight: Radius.circular(12),
      ),
      color: context.colors.surface,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: _filteredUsers.length,
          itemBuilder: (context, index) {
            final user = _filteredUsers[index];
            return ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
                backgroundColor: Colors.grey.shade800,
              ),
              title: Text(user.name, style: TextStyle(color: context.colors.textPrimary)),
              subtitle: Text(
                user.nip05,
                style: TextStyle(color: context.colors.textSecondary),
              ),
              onTap: () => _onUserSelected(user),
            );
          },
        ),
      ),
    );
  }
}
