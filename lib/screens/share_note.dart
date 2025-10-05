import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/di/app_di.dart';
import '../data/services/nostr_data_service.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/note_repository.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../models/user_model.dart';
import '../theme/theme_manager.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/toast_widget.dart';

class ShareNotePage extends StatefulWidget {
  final String? initialText;
  final String? replyToNoteId;

  const ShareNotePage({
    super.key,
    this.initialText,
    this.replyToNoteId,
  });

  @override
  State<ShareNotePage> createState() => _ShareNotePageState();
}

class _ShareNotePageState extends State<ShareNotePage> {
  static const String _serverUrl = "https://blossom.primal.net";
  static const int _maxMediaFiles = 10;
  static const int _maxUserSuggestions = 5;
  static const int _maxFileSizeBytes = 50 * 1024 * 1024;
  static const int _npubPreviewLength = 10;
  static const double _mediaItemSize = 160.0;
  static const double _mediaListHeight = 170.0;
  static const double _avatarRadius = 20.0;
  static const double _userSuggestionsMaxHeight = 200.0;

  static const double _fontSize = 15.0;
  static const double _lineHeight = 1.4;
  static const double _smallFontSize = 13.0;

  static const String _mentionPattern = r'nostr:(npub1[0-9a-z]+)';

  static const String _errorInitializingText = 'Error initializing text';
  static const String _errorLoadingUsers = 'Error loading users';
  static const String _errorLoadingProfile = 'Error loading profile';
  static const String _errorSelectingMedia = 'Error selecting media';
  static const String _errorUploadingFile = 'Error uploading file';
  static const String _errorSelectingUser = 'Error selecting user';
  static const String _errorSharingNote = 'Error sharing note';
  static const String _maxMediaFilesMessage = 'Maximum $_maxMediaFiles media files allowed';
  static const String _fileTooLargeMessage = 'File is too large (max 50MB)';
  static const String _invalidFileTypeMessage = 'Invalid file type. Only images and videos are allowed';
  static const String _emptyNoteMessage = 'Please enter a note or add media';
  
  static const List<String> _allowedExtensions = [
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif',
    'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v',
  ];

  static const String _uploadingText = 'Uploading...';
  static const String _addMediaText = 'Add media';
  static const String _postButtonText = 'Post!';
  static const String _retryText = 'Retry';
  static const String _hintText = "What's on your mind?";

  late TextEditingController _noteController;
  final FocusNode _focusNode = FocusNode();

  bool _isPosting = false;
  bool _isMediaUploading = false;
  final List<String> _mediaUrls = [];
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  bool _isSearchingUsers = false;
  String _userSearchQuery = '';
  final Map<String, String> _mentionMap = {};
  UserModel? _currentUser;

  late NostrDataService _dataService;
  late UserRepository _userRepository;
  late NoteRepository _noteRepository;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeController();
    _loadInitialData();
    _setupTextListener();
    _requestInitialFocus();
  }

  @override
  void dispose() {
    _cleanupResources();
    super.dispose();
  }

  void _initializeServices() {
    _dataService = AppDI.get<NostrDataService>();
    _userRepository = AppDI.get<UserRepository>();
    _noteRepository = AppDI.get<NoteRepository>();
  }

  void _initializeController() {
    _noteController = TextEditingController();
  }

  void _loadInitialData() {
    _loadProfile();
    _loadUsers();
    _initializeText();
  }

  void _setupTextListener() {
    _noteController.addListener(_onTextChanged);
  }

  void _requestInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _cleanupResources() {
    _noteController.removeListener(_onTextChanged);
    _noteController.dispose();
    _focusNode.dispose();
  }

  Future<void> _initializeText() async {
    try {
      final initialText = _getInitialTextContent();

      if (!_containsMentions(initialText)) {
        _setTextContent(initialText);
        return;
      }

      await _processMentions(initialText);
    } catch (e) {
      _showErrorSnackBar('$_errorInitializingText: ${e.toString()}');
    }
  }

  String _getInitialTextContent() {
    if (widget.initialText == null) return '';
    return widget.initialText!.startsWith('nostr:') ? '' : widget.initialText!;
  }

  bool _containsMentions(String text) {
    return RegExp(_mentionPattern).hasMatch(text);
  }

  Future<void> _processMentions(String text) async {
    try {
      final mentionRegex = RegExp(_mentionPattern);
      final matches = mentionRegex.allMatches(text);

      final npubs = matches.map((m) => m.group(1)!).toList();

      final Map<String, String> resolvedNames = {};
      for (final npub in npubs) {
        try {
          final userResult = await _userRepository.getUserProfile(npub);
          if (userResult.isSuccess && userResult.data != null) {
            resolvedNames[npub] = userResult.data!.name;
          } else {
            resolvedNames[npub] = npub.substring(0, _npubPreviewLength);
          }
        } catch (e) {
          resolvedNames[npub] = npub.substring(0, _npubPreviewLength);
        }
      }

      String newText = text;
      for (var match in matches.toList().reversed) {
        final npub = match.group(1)!;
        final username = _formatUsername(resolvedNames[npub] ?? npub.substring(0, _npubPreviewLength));
        final mentionKey = '@$username';
        _mentionMap[mentionKey] = 'nostr:$npub';
        newText = newText.replaceRange(match.start, match.end, mentionKey);
      }

      _setTextContent(newText);
    } catch (e) {
      _showErrorSnackBar('$_errorInitializingText: ${e.toString()}');
    }
  }

  String _formatUsername(String username) {
    return username.replaceAll(' ', '_');
  }

  void _setTextContent(String text) {
    if (!mounted) return;
    setState(() {
      _noteController.text = text;
    });
  }

  Future<void> _loadUsers() async {
    try {
      debugPrint('[ShareNotePage] Loading users from Isar database...');
      
      final isarService = _userRepository.isarService;
      
      if (!isarService.isInitialized) {
        debugPrint('[ShareNotePage] Isar not initialized, waiting...');
        await isarService.waitForInitialization();
      }
      
      final isarProfiles = await isarService.getAllUserProfiles();
      
      final userModels = isarProfiles.map((isarProfile) {
        final profileData = isarProfile.toProfileData();
        return UserModel.fromCachedProfile(
          isarProfile.pubkeyHex,
          profileData,
        );
      }).toList();
      
      if (mounted) {
        setState(() {
          _allUsers = userModels;
        });
        debugPrint('[ShareNotePage]  Loaded ${userModels.length} users from Isar for mention suggestions');
      }
    } catch (e) {
      debugPrint('[ShareNotePage]  Error loading users from Isar: $e');
      _showErrorSnackBar('$_errorLoadingUsers: ${e.toString()}');
      
      try {
        final cachedUsers = _dataService.cachedUsers;
        if (mounted) {
          setState(() {
            _allUsers = cachedUsers;
          });
          debugPrint('[ShareNotePage] Using ${cachedUsers.length} users from NostrDataService fallback');
        }
      } catch (fallbackError) {
        debugPrint('[ShareNotePage]  Fallback also failed: $fallbackError');
      }
    }
  }

  Future<void> _loadProfile() async {
    try {
      const storage = FlutterSecureStorage();
      final npub = await storage.read(key: 'npub');

      if (npub == null || npub.isEmpty) return;

      final userResult = await _userRepository.getUserProfile(npub);
      if (userResult.isSuccess && userResult.data != null) {
        if (mounted) {
          setState(() {
            _currentUser = userResult.data;
          });
        }
      }
    } catch (e) {
      _showErrorSnackBar('$_errorLoadingProfile: ${e.toString()}');
    }
  }

  Future<void> _selectMedia() async {
    if (_isMediaUploading || !_canAddMoreMedia()) return;

    try {
      final result = await _pickMediaFiles();
      if (result == null || result.files.isEmpty) return;

      await _processSelectedFiles(result.files);
    } catch (e) {
      _showErrorSnackBar('$_errorSelectingMedia: ${e.toString()}');
    } finally {
      _setMediaUploadingState(false);
    }
  }

  bool _canAddMoreMedia() {
    if (_mediaUrls.length >= _maxMediaFiles) {
      _showErrorSnackBar(_maxMediaFilesMessage);
      return false;
    }
    return true;
  }

  Future<FilePickerResult?> _pickMediaFiles() async {
    return await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.media,
      allowedExtensions: null,
    );
  }

  Future<void> _processSelectedFiles(List<PlatformFile> files) async {
    final remainingSlots = _maxMediaFiles - _mediaUrls.length;
    final filesToProcess = files.take(remainingSlots).toList();

    if (files.length > remainingSlots) {
      _showErrorSnackBar('Only $remainingSlots more files can be added');
    }

    _setMediaUploadingState(true);

    for (var file in filesToProcess) {
      await _uploadSingleFile(file);
    }
  }

  Future<void> _uploadSingleFile(PlatformFile file) async {
    if (file.path == null) return;

    if (!_isFileTypeValid(file)) {
      _showErrorSnackBar('${file.name}: $_invalidFileTypeMessage');
      return;
    }

    if (!_isFileSizeValid(file)) {
      _showErrorSnackBar('${file.name} $_fileTooLargeMessage');
      return;
    }

    try {
      final mediaResult = await _dataService.sendMedia(file.path!, _serverUrl);
      if (mediaResult.isSuccess && mediaResult.data != null) {
        final uploadedUrl = mediaResult.data!;
        
        if (!_isValidMediaUrl(uploadedUrl)) {
          _showErrorSnackBar('${file.name}: Server returned invalid media URL (no valid extension)');
          debugPrint('[ShareNotePage] Invalid media URL from server: $uploadedUrl');
          return;
        }
        
        if (mounted) {
          setState(() {
            _mediaUrls.add(uploadedUrl);
          });
        }
        debugPrint('[ShareNotePage] Media uploaded successfully: $uploadedUrl');
      } else {
        throw Exception(mediaResult.error ?? 'Upload failed');
      }
    } catch (e) {
      _showErrorSnackBar('$_errorUploadingFile ${file.name}: ${e.toString()}');
    }
  }

  bool _isFileSizeValid(PlatformFile file) {
    return file.size <= _maxFileSizeBytes;
  }

  bool _isFileTypeValid(PlatformFile file) {
    if (file.name.isEmpty) return false;
    
    final extension = file.name.split('.').last.toLowerCase();
    return _allowedExtensions.contains(extension);
  }

  bool _isValidMediaUrl(String url) {
    if (url.isEmpty) return false;
    
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    
    final path = uri.path.toLowerCase();
    if (path.isEmpty) return false;
    
    final lastDotIndex = path.lastIndexOf('.');
    if (lastDotIndex == -1 || lastDotIndex == path.length - 1) {
      return false;
    }
    
    final extension = path.substring(lastDotIndex + 1);
    return _allowedExtensions.contains(extension);
  }

  void _setMediaUploadingState(bool isUploading) {
    if (mounted) {
      setState(() {
        _isMediaUploading = isUploading;
      });
    }
  }

  Future<void> _shareNote() async {
    if (_isPosting) return;

    final noteContent = _prepareNoteContent();
    if (noteContent == null) return;

    _setPostingState(true);

    try {
      await _sendNote(noteContent);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      _showRetryableError(error.toString());
    } finally {
      _setPostingState(false);
    }
  }

  String? _prepareNoteContent() {
    final hasQuote = _hasQuoteContent();
    String noteText = _noteController.text.trim();

    if (!_isNoteLengthValid(noteText)) return null;

    noteText = _replaceMentions(noteText);

    if (!_hasContent(noteText, hasQuote)) return null;

    return _buildFinalNoteContent(noteText, hasQuote);
  }

  bool _hasQuoteContent() {
    return widget.initialText != null && widget.initialText!.startsWith('nostr:');
  }

  bool _isNoteLengthValid(String noteText) {
    return true;
  }

  String _replaceMentions(String noteText) {
    _mentionMap.forEach((key, value) {
      noteText = noteText.replaceAll(key, value);
    });
    return noteText;
  }

  bool _hasContent(String noteText, bool hasQuote) {
    if (noteText.isEmpty && _mediaUrls.isEmpty && !hasQuote) {
      _showErrorSnackBar(_emptyNoteMessage);
      return false;
    }
    return true;
  }

  String _buildFinalNoteContent(String noteText, bool hasQuote) {
    final mediaPart = _mediaUrls.isNotEmpty ? "\n\n${_mediaUrls.join("\n")}" : "";

    String quotePart = "";
    if (hasQuote && widget.initialText != null) {
      final hexId = widget.initialText!.replaceFirst('nostr:', '');
      try {
        final note1Id = encodeBasicBech32(hexId, 'note');
        quotePart = "\n\nnostr:$note1Id";
        debugPrint('[ShareNotePage] Added quote as text: nostr:$note1Id');
      } catch (e) {
        debugPrint('[ShareNotePage] Error encoding hex to note1: $e');
        quotePart = "\n\nnostr:$hexId";
      }
    }

    return "$noteText$mediaPart$quotePart".trim();
  }

  Future<void> _sendNote(String content) async {
    if (_isReply()) {
      final result = await _noteRepository.postReply(
        content: content,
        rootId: widget.replyToNoteId!,
        parentAuthor: 'unknown',
        relayUrls: ['wss://relay.damus.io'],
      );

      if (result.isError) {
        throw Exception(result.error ?? 'Failed to post reply');
      }
    } else {
      debugPrint('[ShareNotePage] Sending as regular note with content: ${content.length > 100 ? content.substring(0, 100) : content}...');
      final result = await _noteRepository.postNote(content: content);

      if (result.isError) {
        throw Exception(result.error ?? 'Failed to post note');
      }
    }
  }

  bool _isReply() {
    return widget.replyToNoteId != null && widget.replyToNoteId!.isNotEmpty;
  }

  void _setPostingState(bool isPosting) {
    if (mounted) {
      setState(() {
        _isPosting = isPosting;
      });
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
    _handleMentionSearch();
  }

  void _handleMentionSearch() {
    final cursorPos = _noteController.selection.baseOffset;

    if (cursorPos == -1) {
      _setUserSearchState(false);
      return;
    }

    final currentWord = _getCurrentWord(cursorPos);

    if (currentWord.startsWith('@')) {
      final searchQuery = currentWord.substring(1);
      _setUserSearchState(true, searchQuery);
    } else {
      _setUserSearchState(false);
    }
  }

  String _getCurrentWord(int cursorPos) {
    final text = _noteController.text;
    final textBeforeCursor = text.substring(0, cursorPos);
    final words = textBeforeCursor.split(' ');
    return words.isNotEmpty ? words.last : '';
  }

  void _setUserSearchState(bool isSearching, [String query = '']) {
    if (!mounted) return;
    setState(() {
      _isSearchingUsers = isSearching;
      _userSearchQuery = query;
      if (isSearching) {
        _filterUsers();
      }
    });
  }

  void _filterUsers() {
    if (_userSearchQuery.isEmpty) {
      _setFilteredUsers(_allUsers.take(_maxUserSuggestions).toList());
      return;
    }

    final query = _userSearchQuery.toLowerCase().trim();
    if (query.isEmpty) return;

    final filtered = _getFilteredUsers(query);
    final sortedFiltered = _sortUsersByRelevance(filtered, query);

    _setFilteredUsers(sortedFiltered.take(_maxUserSuggestions).toList());
  }

  List<UserModel> _getFilteredUsers(String query) {
    return _allUsers.where((user) {
      final name = user.name.toLowerCase();
      final nip05 = user.nip05.toLowerCase();
      return name.contains(query) || nip05.contains(query);
    }).toList();
  }

  List<UserModel> _sortUsersByRelevance(List<UserModel> users, String query) {
    users.sort((a, b) {
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
    return users;
  }

  void _setFilteredUsers(List<UserModel> users) {
    if (mounted) {
      setState(() {
        _filteredUsers = users;
      });
    }
  }

  void _onUserSelected(UserModel user) {
    try {
      final cursorPos = _noteController.selection.baseOffset;
      if (cursorPos == -1) return;

      final atIndex = _findAtSymbolIndex(cursorPos);
      if (atIndex == -1) return;

      _insertMention(user, atIndex, cursorPos);
      _clearUserSearch();
    } catch (e) {
      _showErrorSnackBar('$_errorSelectingUser: ${e.toString()}');
    }
  }

  int _findAtSymbolIndex(int cursorPos) {
    final text = _noteController.text;
    final textBeforeCursor = text.substring(0, cursorPos);
    return textBeforeCursor.lastIndexOf('@');
  }

  void _insertMention(UserModel user, int atIndex, int cursorPos) {
    final text = _noteController.text;
    final username = _formatUsername(user.name);
    final mentionKey = '@$username';

    String npubBech32;
    if (user.pubkeyHex.isNotEmpty) {
      npubBech32 = encodeBasicBech32(user.pubkeyHex, 'npub');
    } else if (user.npub.startsWith('npub1')) {
      npubBech32 = user.npub;
    } else {
      try {
        npubBech32 = encodeBasicBech32(user.npub, 'npub');
      } catch (e) {
        npubBech32 = user.npub;
      }
    }

    _mentionMap[mentionKey] = 'nostr:$npubBech32';

    final textAfterCursor = text.substring(cursorPos);
    final newText = '${text.substring(0, atIndex)}$mentionKey $textAfterCursor';
    final newCursorPos = atIndex + mentionKey.length + 1;

    if (mounted) {
      _noteController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.fromPosition(TextPosition(offset: newCursorPos)),
      );
    }
  }

  void _clearUserSearch() {
    if (mounted) {
      setState(() {
        _isSearchingUsers = false;
        _filteredUsers = [];
      });
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    AppToast.error(context, message);
  }

  void _showRetryableError(String error) {
    if (!mounted) return;
    AppToast.show(
      context,
      '$_errorSharingNote: $error',
      type: ToastType.error,
      action: SnackBarAction(
        label: _retryText,
        onPressed: _shareNote,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'New Post',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          _buildAppBarActions(),
        ],
      ),
    );
  }

  Widget _buildAppBarActions() {
    return Row(
      children: [
        _buildMediaButton(),
        const SizedBox(width: 8),
        _buildPostButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(context),
              Expanded(child: _buildMainContent()),
              if (_isSearchingUsers) _buildUserSuggestions(),
            ],
          ),
          const BackButtonWidget.floating(),
        ],
      ),
    );
  }

  Widget _buildMediaButton() {
    return Semantics(
      label: _isMediaUploading ? 'Uploading media files' : 'Add media files to your post',
      button: true,
      enabled: !_isMediaUploading,
      child: GestureDetector(
        onTap: _isMediaUploading ? null : _selectMedia,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            borderRadius: BorderRadius.circular(40),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isMediaUploading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
                  ),
                )
              else
                Icon(Icons.attach_file, size: 16, color: context.colors.textPrimary),
              const SizedBox(width: 6),
              Text(
                _isMediaUploading ? _uploadingText : _addMediaText,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: _smallFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostButton() {
    return Semantics(
      label: _isPosting ? 'Posting your note, please wait' : 'Post your note',
      button: true,
      enabled: !_isPosting,
      child: GestureDetector(
        onTap: _isPosting ? null : _shareNote,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.buttonPrimary,
            borderRadius: BorderRadius.circular(40),
          ),
          child: _isPosting ? _buildPostingIndicator() : _buildPostButtonText(),
        ),
      ),
    );
  }

  Widget _buildPostingIndicator() {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        valueColor: AlwaysStoppedAnimation<Color>(context.colors.background),
      ),
    );
  }

  Widget _buildPostButtonText() {
    return Text(
      _postButtonText,
      style: TextStyle(
        color: context.colors.buttonText,
        fontSize: _smallFontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isReply()) _buildReplyPreview(),
          const SizedBox(height: 12),
          _buildComposerRow(),
          const SizedBox(height: 16),
          if (_mediaUrls.isNotEmpty) _buildMediaList(),
          if (_hasQuoteContent()) _buildQuoteWidget(),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 16, color: context.colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Replying to note',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUserAvatar(),
        const SizedBox(width: 12),
        Expanded(child: _buildTextInputStack()),
      ],
    );
  }

  Widget _buildUserAvatar() {
    return CircleAvatar(
      radius: _avatarRadius,
      backgroundImage: _currentUser?.profileImage.isNotEmpty == true
          ? CachedNetworkImageProvider(_currentUser!.profileImage)
          : null,
      backgroundColor: context.colors.surfaceTransparent,
      child: _currentUser?.profileImage.isEmpty != false
          ? Icon(Icons.person, color: context.colors.textPrimary, size: 20)
          : null,
    );
  }

  Widget _buildTextInputStack() {
    final textStyle = TextStyle(fontSize: _fontSize, height: _lineHeight);
    final strutStyle = StrutStyle(fontSize: _fontSize, height: _lineHeight);

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Semantics(
        label: 'Compose your note',
        textField: true,
        multiline: true,
        child: TextField(
          focusNode: _focusNode,
          controller: _noteController,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: textStyle.copyWith(color: context.colors.textPrimary),
          cursorColor: context.colors.textPrimary,
          strutStyle: strutStyle,
          decoration: InputDecoration(
            hintText: _noteController.text.isEmpty ? _hintText : "",
            hintStyle: textStyle.copyWith(color: context.colors.textSecondary),
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isCollapsed: true,
          ),
        ),
      ),
    );
  }

  Widget _buildMediaList() {
    return SizedBox(
      height: _mediaListHeight,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _mediaUrls.length,
        onReorder: _reorderMedia,
        itemBuilder: (context, index) {
          final url = _mediaUrls[index];
          return _buildMediaItem(url, index);
        },
      ),
    );
  }

  Widget _buildMediaItem(String url, int index) {
    return Padding(
      key: ValueKey(url),
      padding: const EdgeInsets.only(right: 8.0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: _mediaItemSize,
              height: _mediaItemSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: _mediaItemSize,
                height: _mediaItemSize,
                color: context.colors.surface,
                child: const Icon(Icons.broken_image),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _buildRemoveMediaButton(url),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoveMediaButton(String url) {
    return Semantics(
      label: 'Remove this media file',
      button: true,
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
    );
  }

  Widget _buildQuoteWidget() {
    if (widget.initialText == null || !widget.initialText!.startsWith('nostr:')) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.border),
        ),
        child: Text(
          'Quoting: ${widget.initialText!.replaceFirst('nostr:', '').substring(0, 8)}...',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12,
          ),
        ),
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
            constraints: const BoxConstraints(maxHeight: _userSuggestionsMaxHeight),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _filteredUsers.length,
              itemBuilder: (context, index) {
                final user = _filteredUsers[index];
                return _buildUserSuggestionItem(user);
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildUserSuggestionItem(UserModel user) {
    return Semantics(
      label: 'Mention ${user.name}, ${user.nip05}',
      button: true,
      child: ListTile(
        leading: CircleAvatar(
          radius: _avatarRadius,
          backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
          backgroundColor: context.colors.surfaceTransparent,
          child: user.profileImage.isEmpty ? Icon(Icons.person, color: context.colors.textPrimary, size: 20) : null,
        ),
        title: Text(
          user.name,
          style: TextStyle(color: context.colors.textPrimary),
        ),
        subtitle: Text(
          user.nip05,
          style: TextStyle(color: context.colors.textSecondary),
        ),
        onTap: () => _onUserSelected(user),
      ),
    );
  }
}
