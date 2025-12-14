import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

import '../../core/base/base_view_model.dart';
import '../../core/base/result.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';
import '../../data/services/media_service.dart';

class ComposeViewModel extends BaseViewModel with CommandMixin {
  final NoteRepository _noteRepository;
  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  String _content = '';
  bool _isReply = false;
  bool _isQuote = false;
  String? _rootId;
  String? _replyId;
  String? _parentAuthor;
  String? _quoteEventId;
  List<String> _relayUrls = [];
  List<List<String>>? _tags;

  final List<String> _mediaUrls = [];
  bool _isUploadingMedia = false;

  bool _isSearchingUsers = false;

  UIState<NoteModel> _postState = const UIState.initial();
  UIState<String> _authState = const UIState.initial();
  UIState<List<UserModel>> _userSuggestionsState = const UIState.initial();

  ComposeViewModel({
    required NoteRepository noteRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
  })  : _noteRepository = noteRepository,
        _authRepository = authRepository,
        _userRepository = userRepository {
    _setupCommands();
  }

  String get content => _content;
  bool get isReply => _isReply;
  bool get isQuote => _isQuote;
  String? get rootId => _rootId;
  String? get replyId => _replyId;
  String? get quoteEventId => _quoteEventId;
  List<String> get mediaUrls => _mediaUrls;
  bool get isUploadingMedia => _isUploadingMedia;
  bool get isSearchingUsers => _isSearchingUsers;
  UIState<NoteModel> get postState => _postState;
  UIState<String> get authState => _authState;
  UIState<List<UserModel>> get userSuggestionsState => _userSuggestionsState;

  bool get canPost => _content.trim().isNotEmpty && _content.trim().length <= 280;
  int get characterCount => _content.length;
  int get remainingCharacters => 280 - _content.length;

  bool get isPosting => _postState.isLoading;
  bool get isPostSuccessful => _postState.isLoaded;
  String? get postErrorMessage => _postState.error;

  SimpleCommand? _postNoteCommand;
  SimpleCommand? _clearContentCommand;
  SimpleParameterizedCommand<List<String>>? _uploadMediaCommand;
  SimpleParameterizedCommand<String>? _removeMediaCommand;
  SimpleParameterizedCommand<MentionParams>? _addMentionCommand;

  SimpleCommand get postNoteCommand => _postNoteCommand ??= SimpleCommand(_postNote);
  SimpleCommand get clearContentCommand => _clearContentCommand ??= SimpleCommand(_clearContent);
  SimpleParameterizedCommand<List<String>> get uploadMediaCommand =>
      _uploadMediaCommand ??= SimpleParameterizedCommand<List<String>>(_uploadMedia);
  SimpleParameterizedCommand<String> get removeMediaCommand => _removeMediaCommand ??= SimpleParameterizedCommand<String>(_removeMedia);
  SimpleParameterizedCommand<MentionParams> get addMentionCommand =>
      _addMentionCommand ??= SimpleParameterizedCommand<MentionParams>(_addMention);

  void _setupCommands() {
    registerCommand('postNote', postNoteCommand);
    registerCommand('clearContent', clearContentCommand);
    registerCommand('uploadMedia', uploadMediaCommand);
    registerCommand('removeMedia', removeMediaCommand);
    registerCommand('addMention', addMentionCommand);
  }

  void updateContent(String newContent) {
    _content = newContent;

    if (newContent.endsWith('@') || newContent.contains('@')) {
      _triggerUserSearch(newContent);
    }

    safeNotifyListeners();
  }

  Future<void> _postNote() async {
    if (!canPost) {
      return;
    }

    try {
      _postState = const UIState.loading();
      safeNotifyListeners();

      final authResult = await _authRepository.isAuthenticated();
      if (authResult.isError || !authResult.data!) {
        _postState = const UIState.error('Not authenticated. Please log in first.');
        safeNotifyListeners();
        return;
      }

      Result<NoteModel> result;

      if (_isReply && _rootId != null && _parentAuthor != null) {
        result = await _noteRepository.postReply(
          content: _content,
          rootId: _rootId!,
          replyId: _replyId,
          parentAuthor: _parentAuthor!,
          relayUrls: _relayUrls.isNotEmpty ? _relayUrls : ['wss://relay.damus.io'],
        );
      } else if (_isQuote && _quoteEventId != null) {
        final quotedContent = _buildQuoteContent(_content, _quoteEventId!);
        result = await _noteRepository.postQuote(
          content: quotedContent,
          quotedEventId: _quoteEventId!,
          quotedEventPubkey: null, // Will be determined from tags
          relayUrl: _relayUrls.isNotEmpty ? _relayUrls.first : null,
          additionalTags: _tags,
        );
      } else {
        result = await _noteRepository.postNote(
          content: _content,
          tags: _tags,
        );
      }

      if (result.isSuccess) {
        _postState = UIState.loaded(result.data!);
        await _clearContent();
      } else {
        _postState = UIState.error(result.error ?? 'Failed to post note');
      }
      safeNotifyListeners();
    } catch (e) {
      _postState = UIState.error('Failed to post: ${e.toString()}');
      safeNotifyListeners();
    }
  }

  Future<void> _clearContent() async {
    _content = '';
    _isReply = false;
    _isQuote = false;
    _rootId = null;
    _replyId = null;
    _parentAuthor = null;
    _quoteEventId = null;
    _tags = null;
    _mediaUrls.clear();
    _postState = const UIState.initial();
    safeNotifyListeners();
  }

  Future<void> _uploadMedia(List<String> filePaths) async {
    try {
      _isUploadingMedia = true;
      safeNotifyListeners();

      const blossomUrl = 'https://blossom.primal.net'; // Default Blossom server
      final List<String> uploadedUrls = [];

      for (final filePath in filePaths) {
        try {
          final mediaUrl = await MediaService().sendMedia(filePath, blossomUrl);
          uploadedUrls.add(mediaUrl);
          if (kDebugMode) {
            print('[ComposeViewModel] Media uploaded successfully: $mediaUrl');
          }
        } catch (e) {
          if (kDebugMode) {
            print('[ComposeViewModel] Failed to upload media file $filePath: $e');
          }
        }
      }

      if (uploadedUrls.isNotEmpty) {
        _mediaUrls.addAll(uploadedUrls);
        if (kDebugMode) {
          print('[ComposeViewModel] Successfully uploaded ${uploadedUrls.length}/${filePaths.length} media files');
        }
      } else {
        throw Exception('No media files were uploaded successfully');
      }

      _isUploadingMedia = false;
      safeNotifyListeners();
    } catch (e) {
      _isUploadingMedia = false;
      setError(UnknownError(
        message: 'Failed to upload media: $e',
        userMessage: 'Failed to upload media',
        code: 'MEDIA_UPLOAD_ERROR',
      ));
    }
  }

  Future<void> _removeMedia(String url) async {
    _mediaUrls.remove(url);
    safeNotifyListeners();
  }

  Future<void> _addMention(MentionParams params) async {
    try {
      final cursorPos = params.startIndex;
      if (cursorPos == -1 || cursorPos > _content.length) return;

      final atIndex = _content.substring(0, cursorPos).lastIndexOf('@');
      if (atIndex == -1) return;

      final mention = '@${params.name} ';
      final textAfterCursor = _content.substring(cursorPos);
      _content = '${_content.substring(0, atIndex)}$mention$textAfterCursor';

      _isSearchingUsers = false;
      _userSuggestionsState = const UIState.initial();
      safeNotifyListeners();
    } catch (e) {
      _content = '$_content @${params.name} ';
      _isSearchingUsers = false;
      _userSuggestionsState = const UIState.initial();
      safeNotifyListeners();
    }
  }

  void _triggerUserSearch(String text) {
    _isSearchingUsers = text.contains('@');
    if (_isSearchingUsers) {
      _searchUsers(text);
    }
    safeNotifyListeners();
  }

  Future<void> _searchUsers(String query) async {
    try {
      _userSuggestionsState = const UIState.loading();
      safeNotifyListeners();

      final atIndex = query.lastIndexOf('@');
      if (atIndex == -1 || atIndex >= query.length) {
        _userSuggestionsState = const UIState.empty();
        safeNotifyListeners();
        return;
      }

      final startIndex = atIndex + 1;
      final searchTerm = startIndex < query.length ? query.substring(startIndex) : '';

      if (searchTerm.isEmpty) {
        _userSuggestionsState = const UIState.empty();
        safeNotifyListeners();
        return;
      }

      final searchResult = await _userRepository.searchUsers(searchTerm);

      if (searchResult.isSuccess) {
        _userSuggestionsState = UIState.loaded(searchResult.data!);
      } else {
        _userSuggestionsState = UIState.error(searchResult.error ?? 'Search failed');
      }
      safeNotifyListeners();
    } catch (e) {
      _userSuggestionsState = UIState.error('Search failed: $e');
      safeNotifyListeners();
    }
  }

  void initializeForReply({
    required String replyToNoteId,
    String? rootId,
    String parentAuthor = '',
    List<String>? relayUrls,
    String? initialContent,
  }) {
    _isReply = true;
    _isQuote = false;
    _rootId = rootId ?? replyToNoteId;
    _replyId = replyToNoteId;
    _parentAuthor = parentAuthor;
    _relayUrls = relayUrls ?? [];
    if (initialContent != null) {
      _content = initialContent;
    }
    safeNotifyListeners();
  }

  void initializeForQuote({
    required String quotedEventId,
    String? quotedEventPubkey,
    String? relayUrl,
    List<List<String>>? additionalTags,
    String? quoteEventId,
  }) {
    _isReply = false;
    _isQuote = true;
    _quoteEventId = quoteEventId ?? quotedEventId;

    final List<List<String>> quoteTags = [];

    if (quotedEventPubkey != null) {
      quoteTags.add(['q', quotedEventId, relayUrl ?? '', quotedEventPubkey]);
      quoteTags.add(['p', quotedEventPubkey]);
    } else {
      quoteTags.add(['q', quotedEventId, relayUrl ?? '']);
    }

    if (additionalTags != null) {
      quoteTags.addAll(additionalTags);
    }

    _tags = quoteTags;
    safeNotifyListeners();
  }

  Future<void> postRepost({
    required String noteId,
    required String noteAuthor,
  }) async {
    try {
      _postState = const UIState.loading();
      safeNotifyListeners();

      final authResult = await _authRepository.isAuthenticated();
      if (authResult.isError || !authResult.data!) {
        _postState = const UIState.error('Not authenticated. Please log in first.');
        safeNotifyListeners();
        return;
      }

      final result = await _noteRepository.repostNote(noteId);

      if (result.isSuccess) {
        _postState = const UIState.initial(); // Repost successful, reset state
        await _clearContent();
      } else {
        _postState = UIState.error(result.error ?? 'Failed to repost note');
      }
      safeNotifyListeners();
    } catch (e) {
      _postState = UIState.error('Failed to repost: ${e.toString()}');
      safeNotifyListeners();
    }
  }

  String _buildQuoteContent(String userContent, String quotedEventId) {
    final trimmedContent = userContent.trim();

    String noteId;
    try {
      if (quotedEventId.startsWith('note1')) {
        noteId = quotedEventId;
      } else {
        noteId = encodeBasicBech32(quotedEventId, 'note');
      }
    } catch (e) {
      noteId = quotedEventId.startsWith('note1') ? quotedEventId : quotedEventId;
    }

    final quotePart = 'nostr:$noteId';

    if (trimmedContent.isEmpty) {
      return quotePart;
    }

    return '$trimmedContent\n\n$quotePart';
  }

  void addTags(List<List<String>> tags) {
    _tags = (_tags ?? [])..addAll(tags);
    safeNotifyListeners();
  }

  void reset() {
    executeCommand('clearContent');
  }

  Future<void> checkAuthStatus() async {
    try {
      _authState = const UIState.loading();
      safeNotifyListeners();

      final authResult = await _authRepository.getCurrentUserNpub();

      if (authResult.isSuccess && authResult.data != null) {
        _authState = UIState.loaded(authResult.data!);
      } else {
        _authState = const UIState.error('Not authenticated');
      }
      safeNotifyListeners();
    } catch (e) {
      _authState = UIState.error('Auth check failed: $e');
      safeNotifyListeners();
    }
  }
}

class MentionParams {
  final String name;
  final String npub;
  final int startIndex;
  final int endIndex;

  MentionParams({
    required this.name,
    required this.npub,
    required this.startIndex,
    required this.endIndex,
  });
}
