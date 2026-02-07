import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import 'note_event.dart';
import 'note_state.dart';

class NoteBloc extends Bloc<NoteEvent, NoteState> {
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;

  NoteBloc({
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
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
    final currentState = state is NoteComposeState
        ? (state as NoteComposeState)
        : const NoteComposeState(content: '');

    if (!currentState.canPost) return;

    emit(const NoteLoading());

    try {
      final currentUserHex = _authService.currentUserPubkeyHex;
      if (currentUserHex == null) {
        emit(const NoteError('Not authenticated. Please log in first.'));
        return;
      }

      if (currentState.isReply &&
          currentState.rootId != null &&
          currentState.parentAuthor != null) {
        final replyEvent = await _syncService.publishReply(
          content: event.content,
          rootId: currentState.rootId!,
          replyToId: currentState.replyId,
          parentAuthor: currentState.parentAuthor!,
        );
        emit(NoteComposedSuccess({
          'id': replyEvent.eventId,
          'content': event.content,
          'pubkey': replyEvent.pubkey,
          'created_at': replyEvent.createdAt,
        }));
      } else if (currentState.isQuote && currentState.quoteEventId != null) {
        final quotedContent =
            _buildQuoteContent(event.content, currentState.quoteEventId!);
        final quoteEvent = await _syncService.publishQuote(
          content: quotedContent,
          quotedNoteId: currentState.quoteEventId!,
        );
        emit(NoteComposedSuccess({
          'id': quoteEvent.eventId,
          'content': quotedContent,
          'pubkey': quoteEvent.pubkey,
          'created_at': quoteEvent.createdAt,
        }));
      } else {
        final noteEvent = await _syncService.publishNote(
          content: event.content,
          tags: event.tags,
        );
        emit(NoteComposedSuccess({
          'id': noteEvent.eventId,
          'content': event.content,
          'pubkey': noteEvent.pubkey,
          'created_at': noteEvent.createdAt,
        }));
      }

      add(const NoteContentCleared());
    } catch (e) {
      emit(NoteError(e.toString()));
    }
  }

  void _onNoteContentChanged(
    NoteContentChanged event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState
        ? (state as NoteComposeState)
        : const NoteComposeState(content: '');
    final trimmedContent = event.content.trim();
    final hasMedia = currentState.mediaUrls.isNotEmpty;
    final canPost =
        (trimmedContent.isNotEmpty || hasMedia) && trimmedContent.length <= 280;

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
    final currentState = state is NoteComposeState
        ? (state as NoteComposeState)
        : const NoteComposeState(content: '');

    final List<String> directUrls = [];
    final List<String> pathsToUpload = [];

    for (final path in event.filePaths) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        directUrls.add(path);
      } else {
        pathsToUpload.add(path);
      }
    }

    if (directUrls.isNotEmpty && pathsToUpload.isEmpty) {
      final updatedMediaUrls = [...currentState.mediaUrls, ...directUrls];
      emit(currentState.copyWith(
        mediaUrls: updatedMediaUrls,
        canPost: true,
      ));
      return;
    }

    emit(currentState.copyWith(isUploadingMedia: true));

    final List<String> uploadedUrls = [...directUrls];

    for (final filePath in pathsToUpload) {
      final url = await _syncService.uploadMedia(filePath);
      if (url != null) {
        uploadedUrls.add(url);
      }
    }

    if (uploadedUrls.isNotEmpty) {
      final updatedMediaUrls = [...currentState.mediaUrls, ...uploadedUrls];
      final latestState = state is NoteComposeState
          ? (state as NoteComposeState)
          : currentState;
      emit(latestState.copyWith(
        mediaUrls: updatedMediaUrls,
        isUploadingMedia: false,
        canPost: true,
      ));
    } else {
      emit(currentState.copyWith(isUploadingMedia: false));
      emit(const NoteError('No media files were uploaded successfully'));
    }
  }

  void _onNoteMediaRemoved(
    NoteMediaRemoved event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState
        ? (state as NoteComposeState)
        : const NoteComposeState(content: '');
    final updatedMediaUrls =
        currentState.mediaUrls.where((url) => url != event.url).toList();
    final trimmedContent = currentState.content.trim();
    final canPost =
        (trimmedContent.isNotEmpty || updatedMediaUrls.isNotEmpty) &&
            trimmedContent.length <= 280;
    emit(currentState.copyWith(mediaUrls: updatedMediaUrls, canPost: canPost));
  }

  void _onNoteMentionAdded(
    NoteMentionAdded event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState
        ? (state as NoteComposeState)
        : const NoteComposeState(content: '');

    try {
      final cursorPos = event.params.startIndex;
      if (cursorPos == -1 || cursorPos > currentState.content.length) return;

      final atIndex =
          currentState.content.substring(0, cursorPos).lastIndexOf('@');
      if (atIndex == -1) return;

      final mention = '@${event.params.name} ';
      final textAfterCursor = currentState.content.substring(cursorPos);
      final newContent =
          '${currentState.content.substring(0, atIndex)}$mention$textAfterCursor';

      emit(currentState.copyWith(
        content: newContent,
        isSearchingUsers: false,
        userSuggestions: const [],
        canPost:
            newContent.trim().isNotEmpty && newContent.trim().length <= 280,
      ));
    } catch (e) {
      final newContent = '${currentState.content}@${event.params.name} ';
      emit(currentState.copyWith(
        content: newContent,
        isSearchingUsers: false,
        userSuggestions: const [],
        canPost:
            newContent.trim().isNotEmpty && newContent.trim().length <= 280,
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
    final currentState = state is NoteComposeState
        ? (state as NoteComposeState)
        : const NoteComposeState(content: '');

    final isSearching = event.query.contains('@');
    if (!isSearching) {
      emit(currentState
          .copyWith(isSearchingUsers: false, userSuggestions: const []));
      return;
    }

    final query =
        event.query.substring(event.query.lastIndexOf('@') + 1).trim();
    if (query.isEmpty) {
      emit(currentState
          .copyWith(isSearchingUsers: false, userSuggestions: const []));
      return;
    }

    emit(currentState.copyWith(isSearchingUsers: true));

    try {
      final profiles =
          await _profileRepository.searchProfiles(query, limit: 10);
      final users = profiles.map((p) => p.toMap()).toList();
      emit(currentState.copyWith(
        isSearchingUsers: false,
        userSuggestions: users,
      ));
    } catch (e) {
      emit(currentState
          .copyWith(isSearchingUsers: false, userSuggestions: const []));
    }
  }

  void _onNoteReplySetup(
    NoteReplySetup event,
    Emitter<NoteState> emit,
  ) {
    final currentState = state is NoteComposeState
        ? (state as NoteComposeState)
        : const NoteComposeState(content: '');
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
    final currentState = state is NoteComposeState
        ? (state as NoteComposeState)
        : const NoteComposeState(content: '');
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
