import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/base/result.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';
import 'note_event.dart';
import 'note_state.dart';

class NoteBloc extends Bloc<NoteEvent, NoteState> {
  final NoteRepository _noteRepository;
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final DataService _dataService;

  NoteBloc({
    required NoteRepository noteRepository,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required DataService dataService,
  })  : _noteRepository = noteRepository,
        _authRepository = authRepository,
        _userRepository = userRepository,
        _dataService = dataService,
        super(const NoteComposeState(content: '')) {
    on<NoteComposed>(_onNoteComposed);
    on<NoteContentChanged>(_onNoteContentChanged);
    on<NoteMediaUploaded>(_onNoteMediaUploaded);
    on<NoteMediaRemoved>(_onNoteMediaRemoved);
    on<NoteMentionAdded>(_onNoteMentionAdded);
    on<NoteContentCleared>(_onNoteContentCleared);
    on<NoteUserSearchRequested>(_onNoteUserSearchRequested);
    on<NoteReplySetup>(_onNoteReplySetup);
    on<NoteQuoteSetup>(_onNoteQuoteSetup);
  }

  Future<void> _onNoteComposed(
    NoteComposed event,
    Emitter<NoteState> emit,
  ) async {
    final currentState = state is NoteComposeState ? (state as NoteComposeState) : const NoteComposeState(content: '');

    if (!currentState.canPost) return;

    emit(const NoteLoading());

    final authResult = await _authRepository.isAuthenticated();
    if (authResult.isError || !authResult.data!) {
      emit(const NoteError('Not authenticated. Please log in first.'));
      return;
    }

    Result<Map<String, dynamic>> result;

    if (currentState.isReply && currentState.rootId != null && currentState.parentAuthor != null) {
      result = await _noteRepository.postReply(
        content: event.content,
        rootId: currentState.rootId!,
        replyId: currentState.replyId,
        parentAuthor: currentState.parentAuthor!,
        relayUrls: event.relayUrls ?? ['wss://relay.damus.io'],
      );
    } else if (currentState.isQuote && currentState.quoteEventId != null) {
      final quotedContent = _buildQuoteContent(event.content, currentState.quoteEventId!);
      result = await _noteRepository.postQuote(
        content: quotedContent,
        quotedEventId: currentState.quoteEventId!,
        quotedEventPubkey: null,
        relayUrl: event.relayUrls?.isNotEmpty == true ? event.relayUrls!.first : null,
        additionalTags: event.tags,
      );
    } else {
      result = await _noteRepository.postNote(
        content: event.content,
        tags: event.tags,
      );
    }

    result.fold(
      (note) {
        emit(NoteComposedSuccess(note));
        add(const NoteContentCleared());
      },
      (error) => emit(NoteError(error)),
    );
  }

  void _onNoteContentChanged(
    NoteContentChanged event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState ? (state as NoteComposeState) : const NoteComposeState(content: '');
    final trimmedContent = event.content.trim();
    final canPost = trimmedContent.isNotEmpty && trimmedContent.length <= 280;

    if (event.content.contains('@')) {
      add(NoteUserSearchRequested(event.content));
    } else {
      emit(currentState.copyWith(
        content: event.content,
        canPost: canPost,
        isSearchingUsers: false,
        userSuggestions: const [],
      ));
    }
  }

  Future<void> _onNoteMediaUploaded(
    NoteMediaUploaded event,
    Emitter<NoteState> emit,
  ) async {
    final currentState = state is NoteComposeState ? (state as NoteComposeState) : const NoteComposeState(content: '');

    emit(currentState.copyWith(isUploadingMedia: true));

    try {
      const blossomUrl = 'https://blossom.primal.net';
      final List<String> uploadedUrls = [];

      for (final filePath in event.filePaths) {
        try {
          final mediaResult = await _dataService.sendMedia(filePath, blossomUrl);
          if (mediaResult.isSuccess && mediaResult.data != null) {
            uploadedUrls.add(mediaResult.data!);
          }
        } catch (e) {
          continue;
        }
      }

      if (uploadedUrls.isNotEmpty) {
        final updatedMediaUrls = [...currentState.mediaUrls, ...uploadedUrls];
        emit(currentState.copyWith(
          mediaUrls: updatedMediaUrls,
          isUploadingMedia: false,
        ));
      } else {
        emit(currentState.copyWith(isUploadingMedia: false));
        emit(NoteError('No media files were uploaded successfully'));
      }
    } catch (e) {
      emit(currentState.copyWith(isUploadingMedia: false));
      emit(NoteError('Failed to upload media: ${e.toString()}'));
    }
  }

  void _onNoteMediaRemoved(
    NoteMediaRemoved event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState ? (state as NoteComposeState) : const NoteComposeState(content: '');
    final updatedMediaUrls = currentState.mediaUrls.where((url) => url != event.url).toList();
    emit(currentState.copyWith(mediaUrls: updatedMediaUrls));
  }

  void _onNoteMentionAdded(
    NoteMentionAdded event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState ? (state as NoteComposeState) : const NoteComposeState(content: '');

    try {
      final cursorPos = event.params.startIndex;
      if (cursorPos == -1 || cursorPos > currentState.content.length) return;

      final atIndex = currentState.content.substring(0, cursorPos).lastIndexOf('@');
      if (atIndex == -1) return;

      final mention = '@${event.params.name} ';
      final textAfterCursor = currentState.content.substring(cursorPos);
      final newContent = '${currentState.content.substring(0, atIndex)}$mention$textAfterCursor';

      emit(currentState.copyWith(
        content: newContent,
        isSearchingUsers: false,
        userSuggestions: const [],
        canPost: newContent.trim().isNotEmpty && newContent.trim().length <= 280,
      ));
    } catch (e) {
      final newContent = '${currentState.content}@${event.params.name} ';
      emit(currentState.copyWith(
        content: newContent,
        isSearchingUsers: false,
        userSuggestions: const [],
        canPost: newContent.trim().isNotEmpty && newContent.trim().length <= 280,
      ));
    }
  }

  void _onNoteContentCleared(
    NoteContentCleared event,
    Emitter<NoteState> emit,
  ) {
    emit(const NoteComposeState(content: ''));
  }

  Future<void> _onNoteUserSearchRequested(
    NoteUserSearchRequested event,
    Emitter<NoteState> emit,
  ) async {
    final currentState = state is NoteComposeState ? (state as NoteComposeState) : const NoteComposeState(content: '');

    final isSearching = event.query.contains('@');
    if (!isSearching) {
      emit(currentState.copyWith(isSearchingUsers: false, userSuggestions: const []));
      return;
    }

    final query = event.query.substring(event.query.lastIndexOf('@') + 1).trim();
    if (query.isEmpty) {
      emit(currentState.copyWith(isSearchingUsers: false, userSuggestions: const []));
      return;
    }

    emit(currentState.copyWith(isSearchingUsers: true));

    final result = await _userRepository.searchUsers(query);

    result.fold(
      (users) => emit(currentState.copyWith(
        isSearchingUsers: false,
        userSuggestions: users,
      )),
      (_) => emit(currentState.copyWith(isSearchingUsers: false, userSuggestions: const [])),
    );
  }

  void _onNoteReplySetup(
    NoteReplySetup event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState ? (state as NoteComposeState) : const NoteComposeState(content: '');
    emit(currentState.copyWith(
      isReply: true,
      isQuote: false,
      rootId: event.rootId,
      replyId: event.replyId,
      parentAuthor: event.parentAuthor,
    ));
  }

  void _onNoteQuoteSetup(
    NoteQuoteSetup event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState ? (state as NoteComposeState) : const NoteComposeState(content: '');
    emit(currentState.copyWith(
      isReply: false,
      isQuote: true,
      quoteEventId: event.quoteEventId,
    ));
  }

  String _buildQuoteContent(String content, String quoteEventId) {
    return '$content\nnostr:$quoteEventId';
  }
}
