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
  static const String _serverUrl = "https://blossom.primal.net";
  static const int _maxMediaFiles = 10;
  static const int _maxNoteLength = 2000;
  static const int _maxUserSuggestions = 5;
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
    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing text: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadUsers() async {
    try {
      final box = await Hive.openBox<UserModel>('users');
      if (mounted) {
        setState(() {
          _allUsers = box.values.toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadProfile() async {
    try {
      const storage = FlutterSecureStorage();
      final npub = await storage.read(key: 'npub');
      if (npub == null || npub.isEmpty) return;

      final profileData = await widget.dataService.getCachedUserProfile(npub);

      if (!mounted) return;
      setState(() {
        _user = UserModel.fromCachedProfile(npub, profileData);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _noteController.removeListener(_onTextChanged);
    _noteController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _selectMedia() async {
    if (_isMediaUploading) return;

    if (_mediaUrls.length >= _maxMediaFiles) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $_maxMediaFiles media files allowed')),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.media,
        allowedExtensions: null,
      );

      if (result != null && result.files.isNotEmpty) {
        final remainingSlots = _maxMediaFiles - _mediaUrls.length;
        final filesToProcess = result.files.take(remainingSlots).toList();

        if (result.files.length > remainingSlots) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Only $remainingSlots more files can be added')),
          );
        }

        if (!mounted) return;
        setState(() {
          _isMediaUploading = true;
        });

        for (var file in filesToProcess) {
          if (file.path != null && file.size <= 50 * 1024 * 1024) {
            // 50MB limit
            try {
              final url = await widget.dataService.sendMedia(file.path!, _serverUrl);
              if (mounted) {
                setState(() {
                  _mediaUrls.add(url);
                });
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error uploading ${file.name}: ${e.toString()}')),
                );
              }
            }
          } else if (file.size > 50 * 1024 * 1024) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${file.name} is too large (max 50MB)')),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting media: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMediaUploading = false;
        });
      }
    }
  }

  Future<void> _shareNote() async {
    if (_isPosting) return;

    final hasQuote = widget.initialText != null && widget.initialText!.startsWith('nostr:');

    String noteText = _noteController.text.trim();

    // Validate note length
    if (noteText.length > _maxNoteLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note is too long (max $_maxNoteLength characters)')),
      );
      return;
    }

    // Replace mentions
    _mentionMap.forEach((key, value) {
      noteText = noteText.replaceAll(key, value);
    });

    if (noteText.isEmpty && _mediaUrls.isEmpty && !hasQuote) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a note or add media')),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isPosting = true;
    });

    try {
      final mediaPart = _mediaUrls.isNotEmpty ? "\n\n${_mediaUrls.join("\n")}" : "";
      final quotePart = hasQuote ? "\n\n${widget.initialText}" : "";
      final finalNoteContent = "$noteText$mediaPart$quotePart".trim();

      if (widget.replyToNoteId != null && widget.replyToNoteId!.isNotEmpty) {
        await widget.dataService.sendReply(widget.replyToNoteId!, finalNoteContent);
      } else {
        await widget.dataService.shareNote(finalNoteContent);
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing note: ${error.toString()}'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _shareNote,
            ),
          ),
        );
      }
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
          _filteredUsers = _allUsers.take(_maxUserSuggestions).toList();
        });
      }
      return;
    }

    final query = _userSearchQuery.toLowerCase().trim();
    if (query.isEmpty) return;

    final filtered = _allUsers.where((user) {
      final name = user.name.toLowerCase();
      final nip05 = user.nip05.toLowerCase();
      return name.contains(query) || nip05.contains(query);
    }).toList();

    // Sort by relevance: exact matches first, then starts with, then contains
    filtered.sort((a, b) {
      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();

      final aExact = aName == query ? 0 : 1;
      final bExact = bName == query ? 0 : 1;
      if (aExact != bExact) return aExact.compareTo(bExact);

      final aStarts = aName.startsWith(query) ? 0 : 1;
      final bStarts = bName.startsWith(query) ? 0 : 1;
      if (aStarts != bStarts) return aStarts.compareTo(bStarts);

      final aIndex = aName.indexOf(query);
      final bIndex = bName.indexOf(query);
      return aIndex.compareTo(bIndex);
    });

    if (mounted) {
      setState(() {
        _filteredUsers = filtered.take(_maxUserSuggestions).toList();
      });
    }
  }

  void _onUserSelected(UserModel user) {
    try {
      final text = _noteController.text;
      final selection = _noteController.selection;
      final cursorPos = selection.baseOffset;

      if (cursorPos == -1) return;

      final textBeforeCursor = text.substring(0, cursorPos);
      final atIndex = textBeforeCursor.lastIndexOf('@');

      if (atIndex == -1) return;

      final username = user.name.replaceAll(RegExp(r'\s+'), '_');
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting user: ${e.toString()}')),
        );
      }
    }
  }

  void _updateRichText() {
    final text = _noteController.text;
    final spans = <InlineSpan>[];
    var lastEnd = 0;

    try {
      final mentionKeys = _mentionMap.keys.map((e) => RegExp.escape(e)).join('|');

      final patterns = <String>[];
      if (mentionKeys.isNotEmpty) patterns.add('($mentionKeys)');
      patterns.addAll([r'(https?:\/\/[^\s]+)', r'(#\w+)']);

      final pattern = patterns.join('|');

      if (pattern.isEmpty || text.isEmpty) {
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
    } catch (e) {
      // Fallback to plain text if regex fails
      if (mounted) {
        setState(() {
          _richTextSpan = TextSpan(
            text: text,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
          );
        });
      }
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

    return Column(
      children: [
        Material(
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
                    backgroundColor: context.colors.surfaceTransparent,
                    child: user.profileImage.isEmpty ? Icon(Icons.person, color: context.colors.textPrimary, size: 20) : null,
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
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
