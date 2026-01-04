import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giphy_get/giphy_get.dart';

import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/share_note_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../../../models/user_model.dart';
import '../../../constants/giphy_api_key.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/note/quote_widget.dart';
import '../../widgets/media/video_preview.dart';

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

  static Future<bool?> show(BuildContext context, {String? initialText, String? replyToNoteId}) {
    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShareNotePage(
        initialText: initialText,
        replyToNoteId: replyToNoteId,
      ),
    );
  }
}

class _ShareNotePageState extends State<ShareNotePage> {
  static const String _serverUrl = "https://blossom.primal.net";
  static const int _maxMediaFiles = 10;
  static const int _maxFileSizeBytes = 50 * 1024 * 1024;
  static const double _mediaItemSize = 160.0;
  static const double _mediaListHeight = 170.0;
  static const double _avatarRadius = 20.0;
  static const double _userSuggestionsMaxHeight = 200.0;

  static const double _fontSize = 15.0;
  static const double _lineHeight = 1.4;
  static const double _smallFontSize = 13.0;

  static const String _errorSelectingMedia = 'Error selecting media';
  static const String _errorUploadingFile = 'Error uploading file';
  static const String _errorSelectingUser = 'Error selecting user';
  static const String _errorSharingNote = 'Error sharing note';
  static const String _maxMediaFilesMessage = 'Maximum $_maxMediaFiles media files allowed';
  static const String _fileTooLargeMessage = 'File is too large (max 50MB)';
  static const String _invalidFileTypeMessage = 'Invalid file type. Only images and videos are allowed';
  static const String _emptyNoteMessage = 'Please enter a note or add media';

  static const List<String> _allowedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
  ];

  static const String _uploadingText = 'Uploading...';
  static const String _addMediaText = 'Add media';
  static const String _postButtonText = 'Post!';
  static const String _retryText = 'Retry';
  static const String _hintText = "What's on your mind?";

  late TextEditingController _noteController;
  final FocusNode _focusNode = FocusNode();
  late final ShareNoteViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ShareNoteViewModel(
      dataService: AppDI.get(),
      userRepository: AppDI.get(),
      noteRepository: AppDI.get(),
      initialText: widget.initialText,
      replyToNoteId: widget.replyToNoteId,
    );
    _viewModel.addListener(_onViewModelChanged);
    _initializeController();
    _setupTextListener();
    _requestInitialFocus();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _cleanupResources();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _initializeController() {
    _noteController = TextEditingController();
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

  String _formatUsername(String username) {
    return username.replaceAll(' ', '_');
  }

  Future<void> _selectMedia() async {
    if (_viewModel.isMediaUploading || !_canAddMoreMedia()) return;

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

  Future<void> _selectGif() async {
    if (_viewModel.isMediaUploading || !_canAddMoreMedia()) return;

    try {
      final gif = await GiphyGet.getGif(
        context: context,
        apiKey: giphyApiKey,
        lang: GiphyLanguage.english,
        tabColor: context.colors.textPrimary,
        showGIFs: true,
        showStickers: false,
        showEmojis: false,
      );

      if (gif != null && gif.images != null) {
        final gifUrl = gif.images!.original?.url ?? gif.images!.downsized?.url;
        if (gifUrl != null && gifUrl.isNotEmpty) {
          if (mounted) {
            setState(() {
              _viewModel.addMediaUrl(gifUrl);
            });
          }
          debugPrint('[ShareNotePage] GIF added successfully: $gifUrl');
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error selecting GIF: ${e.toString()}');
    }
  }

  bool _canAddMoreMedia() {
    if (_viewModel.mediaUrls.length >= _maxMediaFiles) {
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
    final remainingSlots = _maxMediaFiles - _viewModel.mediaUrls.length;
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
      final mediaResult = await _viewModel.dataService.sendMedia(file.path!, _serverUrl);
      if (mediaResult.isSuccess && mediaResult.data != null) {
        final uploadedUrl = mediaResult.data!;

        if (!_isValidMediaUrl(uploadedUrl)) {
          _showErrorSnackBar('${file.name}: Server returned invalid media URL (no valid extension)');
          debugPrint('[ShareNotePage] Invalid media URL from server: $uploadedUrl');
          return;
        }

        if (mounted) {
          setState(() {
            _viewModel.addMediaUrl(uploadedUrl);
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

  bool _isVideoFile(String url) {
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
    const videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'];
    return videoExtensions.contains(extension);
  }

  void _setMediaUploadingState(bool isUploading) {
    if (mounted) {
      setState(() {
        _viewModel.setMediaUploading(isUploading);
      });
    }
  }

  Future<void> _shareNote() async {
    if (_viewModel.isPosting) return;

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
    _viewModel.mentionMap.forEach((key, value) {
      noteText = noteText.replaceAll(key, value);
    });
    return noteText;
  }

  bool _hasContent(String noteText, bool hasQuote) {
    if (noteText.isEmpty && _viewModel.mediaUrls.isEmpty && !hasQuote) {
      _showErrorSnackBar(_emptyNoteMessage);
      return false;
    }
    return true;
  }

  String _buildFinalNoteContent(String noteText, bool hasQuote) {
    final mediaPart = _viewModel.mediaUrls.isNotEmpty ? "\n\n${_viewModel.mediaUrls.join("\n")}" : "";

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
    final hashtags = _extractHashtags(content);
    final tags = _createHashtagTags(hashtags);
    
    final additionalTags = <List<String>>[];
    additionalTags.addAll(tags);
    
    if (widget.initialText != null && widget.initialText!.startsWith('nostr:')) {
      final cleanId = widget.initialText!.replaceFirst('nostr:', '');
      
      if (cleanId.startsWith('note1')) {
        try {
          final eventIdHex = decodeBasicBech32(cleanId, 'note');
          additionalTags.add(['e', eventIdHex]);
          debugPrint('[ShareNotePage] Added e tag for note: $eventIdHex');
        } catch (e) {
          debugPrint('[ShareNotePage] Error decoding note1 to hex: $e');
        }
      } else if (cleanId.startsWith('npub1')) {
        try {
          final pubkeyHex = decodeBasicBech32(cleanId, 'npub');
          additionalTags.add(['p', pubkeyHex]);
          debugPrint('[ShareNotePage] Added p tag for profile: $pubkeyHex');
        } catch (e) {
          debugPrint('[ShareNotePage] Error decoding npub1 to hex: $e');
        }
      } else if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cleanId)) {
        additionalTags.add(['e', cleanId]);
        debugPrint('[ShareNotePage] Added e tag for hex event ID: $cleanId');
      }
    }
    
    if (_isReply() && widget.replyToNoteId != null) {
      try {
        String eventIdHex;
        if (widget.replyToNoteId!.startsWith('note1')) {
          eventIdHex = decodeBasicBech32(widget.replyToNoteId!, 'note');
        } else if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(widget.replyToNoteId!)) {
          eventIdHex = widget.replyToNoteId!;
        } else {
          eventIdHex = widget.replyToNoteId!;
        }
        
        bool hasETag = false;
        for (final tag in additionalTags) {
          if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1 && tag[1] == eventIdHex) {
            hasETag = true;
            break;
          }
        }
        
        if (!hasETag) {
          additionalTags.add(['e', eventIdHex]);
          debugPrint('[ShareNotePage] Added e tag for reply: $eventIdHex');
        }
      } catch (e) {
        debugPrint('[ShareNotePage] Error processing replyToNoteId: $e');
      }
    }

    if (_isReply()) {
      final result = await _viewModel.noteRepository.postReply(
        content: content,
        rootId: widget.replyToNoteId!,
        parentAuthor: 'unknown',
        relayUrls: ['wss://relay.damus.io'],
        additionalTags: additionalTags,
      );

      if (result.isError) {
        throw Exception(result.error ?? 'Failed to post reply');
      }
    } else {
      debugPrint('[ShareNotePage] Sending as regular note with content: ${content.length > 100 ? content.substring(0, 100) : content}...');
      final result = await _viewModel.noteRepository.postNote(
        content: content,
        tags: additionalTags,
      );

      if (result.isError) {
        throw Exception(result.error ?? 'Failed to post note');
      }
    }
  }

  bool _isReply() {
    return widget.replyToNoteId != null && widget.replyToNoteId!.isNotEmpty;
  }

  List<String> _extractHashtags(String content) {
    // Regex to find hashtags (#word)
    final hashtagRegex = RegExp(r'#(\w+)');
    final matches = hashtagRegex.allMatches(content);

    return matches
        .map((match) => match.group(1)!.toLowerCase()) // NIP-24 requires lowercase
        .toSet() // Remove duplicates
        .toList();
  }

  List<List<String>> _createHashtagTags(List<String> hashtags) {
    return hashtags.map((hashtag) => ['t', hashtag]).toList();
  }

  void _setPostingState(bool isPosting) {
    if (mounted) {
      setState(() {
        _viewModel.setPosting(isPosting);
      });
    }
  }

  void _removeMedia(String url) {
    setState(() {
      _viewModel.removeMediaUrl(_viewModel.mediaUrls.indexOf(url));
    });
  }

  void _reorderMedia(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _viewModel.mediaUrls[oldIndex];
      _viewModel.removeMediaUrl(oldIndex);
      _viewModel.addMediaUrl(item);
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
    _viewModel.searchUsers(query);
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

    _viewModel.addMention('nostr:$npubBech32', mentionKey);

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
      _viewModel.searchUsers('');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    AppSnackbar.error(context, message);
  }

  void _showRetryableError(String error) {
    if (!mounted) return;
    AppSnackbar.error(
      context,
      '$_errorSharingNote: $error',
      action: SnackBarAction(
        label: _retryText,
        onPressed: _shareNote,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildCancelButton(),
          _buildAppBarActions(),
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    return Semantics(
      label: 'Cancel',
      button: true,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(40),
          ),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: context.colors.error,
              fontSize: _smallFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarActions() {
    return Row(
      children: [
        _buildGifButton(),
        const SizedBox(width: 8),
        _buildMediaButton(),
        const SizedBox(width: 8),
        _buildPostButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ShareNoteViewModel>.value(
      value: _viewModel,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildMainContent()),
            Consumer<ShareNoteViewModel>(
              builder: (context, vm, child) {
                if (vm.isSearchingUsers) return _buildUserSuggestions();
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaButton() {
    return Consumer<ShareNoteViewModel>(
      builder: (context, viewModel, child) {
        return Semantics(
          label: viewModel.isMediaUploading ? 'Uploading media files' : 'Add media files to your post',
          button: true,
          enabled: !viewModel.isMediaUploading,
          child: GestureDetector(
            onTap: viewModel.isMediaUploading ? null : _selectMedia,
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
                  if (viewModel.isMediaUploading)
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
                    viewModel.isMediaUploading ? _uploadingText : _addMediaText,
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
      },
    );
  }

  Widget _buildGifButton() {
    return Consumer<ShareNoteViewModel>(
      builder: (context, viewModel, child) {
        return Semantics(
          label: 'Add GIF from Giphy',
          button: true,
          enabled: !viewModel.isMediaUploading,
          child: GestureDetector(
            onTap: viewModel.isMediaUploading ? null : _selectGif,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Text(
                'GIF',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: _smallFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostButton() {
    return Consumer<ShareNoteViewModel>(
      builder: (context, viewModel, child) {
        return Semantics(
          label: viewModel.isPosting ? 'Posting your note, please wait' : 'Post your note',
          button: true,
          enabled: !viewModel.isPosting,
          child: GestureDetector(
            onTap: viewModel.isPosting ? null : _shareNote,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.textPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: viewModel.isPosting ? _buildPostingIndicator() : _buildPostButtonText(),
            ),
          ),
        );
      },
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
        color: context.colors.background,
        fontSize: _smallFontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildMainContent() {
    return Consumer<ShareNoteViewModel>(
      builder: (context, viewModel, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isReply()) _buildReplyPreview(),
              const SizedBox(height: 12),
              _buildComposerRow(),
              const SizedBox(height: 16),
              if (viewModel.mediaUrls.isNotEmpty) _buildMediaList(),
              if (_hasQuoteContent()) _buildQuoteWidget(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReplyPreview() {
    if (widget.replyToNoteId == null || widget.replyToNoteId!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: QuoteWidget(
        bech32: _encodeEventId(widget.replyToNoteId!),
        shortMode: true,
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
    return Consumer<ShareNoteViewModel>(
      builder: (context, viewModel, child) {
        return CircleAvatar(
          radius: _avatarRadius,
          backgroundImage: viewModel.currentUser?.profileImage.isNotEmpty == true ? CachedNetworkImageProvider(viewModel.currentUser!.profileImage) : null,
          backgroundColor: context.colors.surfaceTransparent,
          child: viewModel.currentUser?.profileImage.isEmpty != false ? Icon(Icons.person, color: context.colors.textPrimary, size: 20) : null,
        );
      },
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
    return Consumer<ShareNoteViewModel>(
      builder: (context, viewModel, child) {
        return SizedBox(
          height: _mediaListHeight,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: viewModel.mediaUrls.length,
            onReorder: _reorderMedia,
            itemBuilder: (context, index) {
              final url = viewModel.mediaUrls[index];
              return _buildMediaItem(url, index);
            },
          ),
        );
      },
    );
  }

  Widget _buildMediaItem(String url, int index) {
    final isVideo = _isVideoFile(url);

    return Padding(
      key: ValueKey(url),
      padding: const EdgeInsets.only(right: 8.0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: _mediaItemSize,
              height: _mediaItemSize,
              child: isVideo ? _buildVideoPreview(url) : _buildImagePreview(url),
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

  Widget _buildVideoPreview(String url) {
    return VP(url: url);
  }

  Widget _buildImagePreview(String url) {
    return Image.network(
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
      child: QuoteWidget(
        bech32: _encodeEventId(widget.initialText!),
        shortMode: true,
      ),
    );
  }

  String _encodeEventId(String eventId) {
    try {
      final cleanId = eventId.startsWith('nostr:') ? eventId.substring(6) : eventId;

      if (cleanId.startsWith('note1')) {
        debugPrint('[ShareNotePage] Event ID already in note1 format: $cleanId');
        return cleanId;
      }

      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cleanId)) {
        final encoded = encodeBasicBech32(cleanId, 'note');
        debugPrint('[ShareNotePage] Encoded hex to note1: $encoded');
        return encoded;
      }

      debugPrint('[ShareNotePage] Using event ID as is: $cleanId');
      return cleanId;
    } catch (e) {
      debugPrint('[ShareNotePage] Error encoding event ID: $e');
      return eventId;
    }
  }

  Widget _buildUserSuggestions() {
    return Consumer<ShareNoteViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.filteredUsers.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(40),
                color: context.colors.textPrimary,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: _userSuggestionsMaxHeight),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: viewModel.filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = viewModel.filteredUsers[index];
                      return _buildUserSuggestionItem(user);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildUserSuggestionItem(UserModel user) {
    return Semantics(
      label: 'Mention ${user.name}, ${user.about}',
      button: true,
      child: GestureDetector(
        onTap: () => _onUserSelected(user),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: _avatarRadius,
                backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
                backgroundColor: context.colors.surfaceTransparent,
                child: user.profileImage.isEmpty ? Icon(Icons.person, color: context.colors.background, size: 20) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: TextStyle(
                        color: context.colors.background,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (user.about.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.about,
                        style: TextStyle(
                          color: context.colors.background.withOpacity(0.7),
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
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
}
