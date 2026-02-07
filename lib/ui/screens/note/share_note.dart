import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giphy_get/giphy_get.dart';

import '../../../core/di/app_di.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../presentation/blocs/note/note_bloc.dart';
import '../../../presentation/blocs/note/note_event.dart';
import '../../../presentation/blocs/note/note_state.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  static Future<bool?> show(BuildContext context,
      {String? initialText, String? replyToNoteId}) {
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
  static const String _errorSelectingUser = 'Error selecting user';
  static const String _errorSharingNote = 'Error sharing note';
  static const String _maxMediaFilesMessage =
      'Maximum $_maxMediaFiles media files allowed';
  static const String _fileTooLargeMessage = 'File is too large (max 50MB)';
  static const String _invalidFileTypeMessage =
      'Invalid file type. Only images and videos are allowed';
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
  final Map<String, String> _mentionMap = {};
  late final NoteBloc _noteBloc;

  @override
  void initState() {
    super.initState();
    _noteBloc = NoteBloc(
      profileRepository: AppDI.get<ProfileRepository>(),
      syncService: AppDI.get<SyncService>(),
      authService: AppDI.get<AuthService>(),
    );

    if (widget.replyToNoteId != null) {
      _noteBloc.add(NoteReplySetup(
        rootId: widget.replyToNoteId!,
        parentAuthor: 'unknown',
      ));
    }
    bool isQuote = false;
    if (widget.initialText != null &&
        widget.initialText!.startsWith('nostr:')) {
      final cleanId = widget.initialText!.replaceFirst('nostr:', '');
      _noteBloc.add(NoteQuoteSetup(cleanId));
      isQuote = true;
    }

    _initializeController();
    _setupTextListener();
    _requestInitialFocus();
    if (!isQuote &&
        widget.initialText != null &&
        widget.initialText!.isNotEmpty) {
      _noteController.text = widget.initialText!;
    }
  }

  @override
  void dispose() {
    _cleanupResources();
    super.dispose();
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
    _noteBloc.close();
  }

  String _formatUsername(String username) {
    return username.replaceAll(' ', '_');
  }

  Future<void> _selectMedia() async {
    if (!mounted) return;

    try {
      final state = _noteBloc.state;
      final isUploading =
          state is NoteComposeState ? state.isUploadingMedia : false;
      if (isUploading || !_canAddMoreMedia()) return;

      final result = await _pickMediaFiles();
      if (result == null || result.files.isEmpty) return;

      if (!mounted) return;

      await _processSelectedFiles(result.files);
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('$_errorSelectingMedia: ${e.toString()}');
      }
    }
  }

  Future<void> _selectGif() async {
    if (!mounted) return;

    try {
      final state = _noteBloc.state;
      final isUploading =
          state is NoteComposeState ? state.isUploadingMedia : false;
      if (isUploading || !_canAddMoreMedia()) return;

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
            _noteBloc.add(NoteMediaUploaded([gifUrl]));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error selecting GIF: ${e.toString()}');
      }
    }
  }

  bool _canAddMoreMedia() {
    final state = _noteBloc.state;
    final mediaCount = state is NoteComposeState ? state.mediaUrls.length : 0;
    if (mediaCount >= _maxMediaFiles) {
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
    final state = _noteBloc.state;
    final mediaCount = state is NoteComposeState ? state.mediaUrls.length : 0;
    final remainingSlots = _maxMediaFiles - mediaCount;
    final filesToProcess = files.take(remainingSlots).toList();

    if (files.length > remainingSlots) {
      _showErrorSnackBar('Only $remainingSlots more files can be added');
    }

    final validFiles = filesToProcess.where((file) {
      if (file.path == null) return false;
      if (!_isFileTypeValid(file)) {
        _showErrorSnackBar('${file.name}: $_invalidFileTypeMessage');
        return false;
      }
      if (!_isFileSizeValid(file)) {
        _showErrorSnackBar('${file.name} $_fileTooLargeMessage');
        return false;
      }
      return true;
    }).toList();

    if (validFiles.isNotEmpty) {
      final filePaths = validFiles.map((f) => f.path!).toList();
      _noteBloc.add(NoteMediaUploaded(filePaths));
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

  Future<void> _shareNote() async {
    if (!mounted) return;

    try {
      final state = _noteBloc.state;
      if (state is! NoteComposeState || state.isUploadingMedia) return;

      final noteContent = _prepareNoteContent(state);
      if (noteContent == null) return;

      _sendNote(noteContent);
    } catch (error) {
      if (mounted) {
        _showRetryableError(error.toString());
      }
    }
  }

  String? _prepareNoteContent(NoteComposeState state) {
    final hasQuote = _hasQuoteContent();
    String noteText = _noteController.text.trim();

    if (!_isNoteLengthValid(noteText)) return null;

    noteText = _replaceMentions(noteText, state);

    if (!_hasContent(noteText, hasQuote, state)) return null;

    return _buildFinalNoteContent(noteText, hasQuote, state);
  }

  bool _hasQuoteContent() {
    return widget.initialText != null &&
        widget.initialText!.startsWith('nostr:');
  }

  bool _isNoteLengthValid(String noteText) {
    return true;
  }

  String _replaceMentions(String noteText, NoteComposeState state) {
    _mentionMap.forEach((key, value) {
      noteText = noteText.replaceAll(key, value);
    });
    return noteText;
  }

  bool _hasContent(String noteText, bool hasQuote, NoteComposeState state) {
    if (noteText.isEmpty && state.mediaUrls.isEmpty && !hasQuote) {
      _showErrorSnackBar(_emptyNoteMessage);
      return false;
    }
    return true;
  }

  String _buildFinalNoteContent(
      String noteText, bool hasQuote, NoteComposeState state) {
    final mediaPart =
        state.mediaUrls.isNotEmpty ? "\n\n${state.mediaUrls.join("\n")}" : "";

    return "$noteText$mediaPart".trim();
  }

  void _sendNote(String content) {
    final hashtags = _extractHashtags(content);
    final tags = _createHashtagTags(hashtags);

    final additionalTags = <List<String>>[];
    additionalTags.addAll(tags);

    if (_isReply() && widget.replyToNoteId != null) {
      try {
        String eventIdHex;
        if (widget.replyToNoteId!.startsWith('note1')) {
          eventIdHex = decodeBasicBech32(widget.replyToNoteId!, 'note');
        } else if (RegExp(r'^[0-9a-fA-F]{64}$')
            .hasMatch(widget.replyToNoteId!)) {
          eventIdHex = widget.replyToNoteId!;
        } else {
          eventIdHex = widget.replyToNoteId!;
        }

        bool hasETag = false;
        for (final tag in additionalTags) {
          if (tag.isNotEmpty &&
              tag[0] == 'e' &&
              tag.length > 1 &&
              tag[1] == eventIdHex) {
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

    final state = _noteBloc.state;
    if (state is! NoteComposeState) return;

    final mentions = _mentionMap.keys.toList();
    _noteBloc.add(NoteComposed(
      content: content,
      replyToId: state.replyId,
      rootId: state.rootId,
      parentAuthor: state.parentAuthor,
      quoteEventId: state.quoteEventId,
      mentions: mentions,
      tags: additionalTags,
    ));
  }

  bool _isReply() {
    return widget.replyToNoteId != null && widget.replyToNoteId!.isNotEmpty;
  }

  List<String> _extractHashtags(String content) {
    // Regex to find hashtags (#word)
    final hashtagRegex = RegExp(r'#(\w+)');
    final matches = hashtagRegex.allMatches(content);

    return matches
        .map((match) =>
            match.group(1)!.toLowerCase()) // NIP-24 requires lowercase
        .toSet() // Remove duplicates
        .toList();
  }

  List<List<String>> _createHashtagTags(List<String> hashtags) {
    return hashtags.map((hashtag) => ['t', hashtag]).toList();
  }

  void _removeMedia(String url) {
    _noteBloc.add(NoteMediaRemoved(url));
  }

  void _onTextChanged() {
    final content = _noteController.text;
    _noteBloc.add(NoteContentChanged(content));
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
    _searchUsers(query);
  }

  void _searchUsers(String query) {
    if (query.isEmpty) {
      _noteBloc.add(NoteUserSearchRequested(''));
      return;
    }

    _noteBloc.add(NoteUserSearchRequested(query));
  }

  void _onUserSelected(Map<String, dynamic> user) {
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

  void _insertMention(Map<String, dynamic> user, int atIndex, int cursorPos) {
    final text = _noteController.text;
    final userName = user['name'] as String? ?? '';
    final username = _formatUsername(userName);
    final mentionKey = '@$username';

    final pubkeyHex = user['pubkeyHex'] as String? ?? '';
    final npub = user['npub'] as String? ?? '';

    String npubBech32;
    if (pubkeyHex.isNotEmpty) {
      npubBech32 = encodeBasicBech32(pubkeyHex, 'npub');
    } else if (npub.startsWith('npub1')) {
      npubBech32 = npub;
    } else {
      try {
        npubBech32 = encodeBasicBech32(npub, 'npub');
      } catch (e) {
        npubBech32 = npub;
      }
    }

    _mentionMap['nostr:$npubBech32'] = mentionKey;

    final textAfterCursor = text.substring(cursorPos);
    final newText = '${text.substring(0, atIndex)}$mentionKey $textAfterCursor';
    final newCursorPos = atIndex + mentionKey.length + 1;

    if (mounted) {
      _noteController.value = TextEditingValue(
        text: newText,
        selection:
            TextSelection.fromPosition(TextPosition(offset: newCursorPos)),
      );
    }
  }

  void _clearUserSearch() {
    if (mounted) {
      _searchUsers('');
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Semantics(
        label: 'Cancel',
        button: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
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
    return BlocProvider<NoteBloc>.value(
      value: _noteBloc,
      child: BlocListener<NoteBloc, NoteState>(
        listener: (context, state) {
          if (state is NoteComposedSuccess) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pop(true);
              }
            });
          }
        },
        child: BlocBuilder<NoteBloc, NoteState>(
          builder: (context, state) {
            final composeState = state is NoteComposeState
                ? state
                : const NoteComposeState(content: '');

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(child: _buildMainContent(composeState)),
                  if (composeState.isSearchingUsers)
                    _buildUserSuggestions(composeState),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMediaButton() {
    return BlocSelector<NoteBloc, NoteState, bool>(
      selector: (state) =>
          state is NoteComposeState ? state.isUploadingMedia : false,
      builder: (context, isUploading) {
        return Material(
          color: Colors.transparent,
          child: IgnorePointer(
            ignoring: isUploading,
            child: InkWell(
              onTap: _selectMedia,
              borderRadius: BorderRadius.circular(16),
              child: Semantics(
                label: isUploading
                    ? 'Uploading media files'
                    : 'Add media files to your post',
                button: true,
                enabled: !isUploading,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.overlayLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUploading)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                context.colors.textPrimary),
                          ),
                        )
                      else
                        Icon(Icons.attach_file,
                            size: 16, color: context.colors.textPrimary),
                      const SizedBox(width: 6),
                      Text(
                        isUploading ? _uploadingText : _addMediaText,
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildGifButton() {
    return BlocSelector<NoteBloc, NoteState, bool>(
      selector: (state) =>
          state is NoteComposeState ? state.isUploadingMedia : false,
      builder: (context, isUploading) {
        return Material(
          color: Colors.transparent,
          child: IgnorePointer(
            ignoring: isUploading,
            child: InkWell(
              onTap: _selectGif,
              borderRadius: BorderRadius.circular(16),
              child: Semantics(
                label: 'Add GIF from Giphy',
                button: true,
                enabled: !isUploading,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.overlayLight,
                    borderRadius: BorderRadius.circular(16),
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostButton() {
    return BlocSelector<NoteBloc, NoteState, bool>(
      selector: (state) => state is NoteLoading,
      builder: (context, isLoading) {
        return Material(
          color: Colors.transparent,
          child: IgnorePointer(
            ignoring: isLoading,
            child: InkWell(
              onTap: _shareNote,
              borderRadius: BorderRadius.circular(16),
              child: Semantics(
                label: isLoading
                    ? 'Posting your note, please wait'
                    : 'Post your note',
                button: true,
                enabled: !isLoading,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: isLoading
                      ? _buildPostingIndicator()
                      : _buildPostButtonText(),
                ),
              ),
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

  Widget _buildMainContent(NoteComposeState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isReply()) _buildReplyPreview(),
          const SizedBox(height: 12),
          _buildComposerRow(state),
          const SizedBox(height: 16),
          if (state.mediaUrls.isNotEmpty) _buildMediaList(state),
          if (_hasQuoteContent()) _buildQuoteWidget(),
        ],
      ),
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

  Widget _buildComposerRow(NoteState state) {
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
    return FutureBuilder<Map<String, dynamic>?>(
      future: _loadCurrentUser(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final profileImage = user?['profileImage'] as String? ?? '';
        return CircleAvatar(
          radius: _avatarRadius,
          backgroundImage: profileImage.isNotEmpty
              ? CachedNetworkImageProvider(profileImage)
              : null,
          backgroundColor: context.colors.surfaceTransparent,
          child: profileImage.isEmpty
              ? Icon(Icons.person, color: context.colors.textPrimary, size: 20)
              : null,
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _loadCurrentUser() async {
    final authService = AppDI.get<AuthService>();
    final profileRepository = AppDI.get<ProfileRepository>();
    final currentUserHex = authService.currentUserPubkeyHex;
    if (currentUserHex == null) return null;
    final profile = await profileRepository.getProfile(currentUserHex);
    return profile?.toMap();
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
          textCapitalization: TextCapitalization.sentences,
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

  Widget _buildMediaList(NoteComposeState state) {
    return SizedBox(
      height: _mediaListHeight,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: state.mediaUrls.length,
        onReorder: (oldIndex, newIndex) {
          _noteBloc.add(NoteMediaRemoved(state.mediaUrls[oldIndex]));
          if (newIndex > oldIndex) newIndex -= 1;
          _noteBloc.add(NoteMediaUploaded([state.mediaUrls[oldIndex]]));
        },
        itemBuilder: (context, index) {
          final url = state.mediaUrls[index];
          return _buildMediaItem(url, index);
        },
      ),
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
              child:
                  isVideo ? _buildVideoPreview(url) : _buildImagePreview(url),
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
    if (widget.initialText == null ||
        !widget.initialText!.startsWith('nostr:')) {
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
      final cleanId =
          eventId.startsWith('nostr:') ? eventId.substring(6) : eventId;

      if (cleanId.startsWith('note1')) {
        debugPrint(
            '[ShareNotePage] Event ID already in note1 format: $cleanId');
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

  Widget _buildUserSuggestions(NoteComposeState state) {
    if (state.userSuggestions.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(40),
            color: context.colors.textPrimary,
            child: Container(
              constraints:
                  const BoxConstraints(maxHeight: _userSuggestionsMaxHeight),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: state.userSuggestions.length,
                itemBuilder: (context, index) {
                  final user = state.userSuggestions[index];
                  return _buildUserSuggestionItem(user);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildUserSuggestionItem(Map<String, dynamic> user) {
    final userName = user['name'] as String? ?? '';
    final userAbout = user['about'] as String? ?? '';
    final userProfileImage = user['profileImage'] as String? ?? '';

    return Semantics(
      label: 'Mention $userName, $userAbout',
      button: true,
      child: GestureDetector(
        onTap: () => _onUserSelected(user),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: _avatarRadius,
                backgroundImage: userProfileImage.isNotEmpty
                    ? CachedNetworkImageProvider(userProfileImage)
                    : null,
                backgroundColor: context.colors.surfaceTransparent,
                child: userProfileImage.isEmpty
                    ? Icon(Icons.person,
                        color: context.colors.background, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: TextStyle(
                        color: context.colors.background,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (userAbout.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        userAbout,
                        style: TextStyle(
                          color:
                              context.colors.background.withValues(alpha: 0.7),
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
