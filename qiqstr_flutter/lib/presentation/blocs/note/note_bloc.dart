import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_concurrency/bloc_concurrency.dart';
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
    on<NoteComposed>(_onNoteComposed, transformer: droppable());
    on<NoteContentChanged>(_onNoteContentChanged);
    on<NoteMediaUploaded>(
      _onNoteMediaUploaded,
      transformer: sequential(),
    );
    on<NoteMediaRemoved>(_onNoteMediaRemoved);
    on<NoteMediaReordered>(_onNoteMediaReordered);
    on<NoteMentionAdded>(_onNoteMentionAdded);
    on<NoteContentCleared>(_onNoteContentCleared);
    on<NoteUserSearchRequested>(
      _onNoteUserSearchRequested,
      transformer: restartable(),
    );
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

    if (!currentState.canPost ||
        currentState.isUploadingMedia ||
        currentState.isPublishing) {
      emit(const NoteError(NoteFailure.invalidContent));
      emit(currentState);
      return;
    }

    final currentUserHex = _authService.currentUserPubkeyHex;
    if (currentUserHex == null) {
      emit(const NoteError(NoteFailure.authenticationRequired));
      emit(currentState);
      return;
    }

    emit(currentState.copyWith(isPublishing: true));
    try {
      final published = await _publish(event, currentState);
      emit(NoteComposedSuccess(published));
    } catch (_) {
      emit(const NoteError(NoteFailure.publishFailed));
      emit(currentState.copyWith(isPublishing: false));
    }
  }

  Future<Map<String, dynamic>> _publish(
    NoteComposed event,
    NoteComposeState currentState,
  ) {
    if (currentState.isReply &&
        currentState.rootId != null &&
        currentState.parentAuthor != null) {
      return _syncService.publishReply(
        content: event.content,
        rootId: currentState.rootId!,
        replyToId: currentState.replyId,
        parentAuthor: currentState.parentAuthor!,
        tags: event.tags,
      );
    } else if (currentState.isQuote && currentState.quoteEventId != null) {
      return _syncService.publishQuote(
        content: _buildQuoteContent(event.content, currentState.quoteEventId!),
        quotedNoteId: currentState.quoteEventId!,
        tags: event.tags,
      );
    } else {
      return _syncService.publishNote(
        content: event.content,
        tags: event.tags,
      );
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
        trimmedContent.isNotEmpty || hasMedia || currentState.isQuote;

    emit(currentState.copyWith(
      content: event.content,
      canPost: canPost,
    ));
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
      final updatedMediaUrls = {
        ...currentState.mediaUrls,
        ...directUrls,
      }.toList();
      emit(currentState.copyWith(
        mediaUrls: updatedMediaUrls,
        canPost: true,
      ));
      return;
    }

    emit(currentState.copyWith(isUploadingMedia: true));

    try {
      final List<String> uploadedUrls = [...directUrls];
      final Map<String, String> newDimensions = {};

      for (final filePath in pathsToUpload) {
        String? dim;
        if (_isImageFile(filePath)) {
          dim = await _getImageDimensions(filePath);
        }

        final url = await _syncService.uploadMedia(filePath);
        if (url != null) {
          uploadedUrls.add(url);
          if (dim != null) {
            newDimensions[url] = dim;
          }
        }
      }

      final latestState = state is NoteComposeState
          ? (state as NoteComposeState)
          : currentState;
      if (uploadedUrls.isNotEmpty) {
        final updatedMediaUrls = {
          ...latestState.mediaUrls,
          ...uploadedUrls,
        }.toList();
        final updatedDimensions = {
          ...latestState.mediaDimensions,
          ...newDimensions,
        };
        emit(latestState.copyWith(
          mediaUrls: updatedMediaUrls,
          mediaDimensions: updatedDimensions,
          isUploadingMedia: false,
          canPost: true,
        ));
        return;
      }

      emit(const NoteError(NoteFailure.mediaUploadFailed));
      emit(latestState.copyWith(isUploadingMedia: false));
    } catch (_) {
      final latestState = state is NoteComposeState
          ? (state as NoteComposeState)
          : currentState;
      emit(const NoteError(NoteFailure.mediaUploadFailed));
      emit(latestState.copyWith(isUploadingMedia: false));
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
    final updatedDimensions =
        Map<String, String>.from(currentState.mediaDimensions)
          ..remove(event.url);
    final trimmedContent = currentState.content.trim();
    final canPost = trimmedContent.isNotEmpty ||
        updatedMediaUrls.isNotEmpty ||
        currentState.isQuote;
    emit(currentState.copyWith(
      mediaUrls: updatedMediaUrls,
      mediaDimensions: updatedDimensions,
      canPost: canPost,
    ));
  }

  void _onNoteMediaReordered(
    NoteMediaReordered event,
    Emitter<NoteState> emit,
  ) {
    if (state is! NoteComposeState) return;
    final currentState = state as NoteComposeState;
    if (event.oldIndex < 0 ||
        event.oldIndex >= currentState.mediaUrls.length ||
        event.newIndex < 0 ||
        event.newIndex >= currentState.mediaUrls.length) {
      return;
    }

    final reordered = List<String>.from(currentState.mediaUrls);
    final item = reordered.removeAt(event.oldIndex);
    reordered.insert(event.newIndex, item);
    emit(currentState.copyWith(mediaUrls: reordered));
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
        canPost: newContent.trim().isNotEmpty,
      ));
    } catch (e) {
      final newContent = '${currentState.content}@${event.params.name} ';
      emit(currentState.copyWith(
        content: newContent,
        isSearchingUsers: false,
        userSuggestions: const [],
        canPost: newContent.trim().isNotEmpty,
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

    if (event.query.isEmpty) {
      emit(currentState
          .copyWith(isSearchingUsers: false, userSuggestions: const []));
      return;
    }

    emit(currentState.copyWith(isSearchingUsers: true));

    try {
      final profiles =
          await _profileRepository.searchProfiles(event.query, limit: 10);
      if (emit.isDone) return;
      final users = profiles.map((p) => p.toMap()).toList();
      final latestState = state is NoteComposeState
          ? (state as NoteComposeState)
          : currentState;
      emit(latestState.copyWith(
        isSearchingUsers: users.isNotEmpty,
        userSuggestions: users,
      ));
    } catch (e) {
      if (emit.isDone) return;
      final latestState = state is NoteComposeState
          ? (state as NoteComposeState)
          : currentState;
      emit(latestState
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
      canPost: true,
    ));
  }

  String _buildQuoteContent(String content, String quoteEventId) {
    final encodedId = quoteEventId.startsWith('note1')
        ? quoteEventId
        : _authService.encodeNoteId(quoteEventId);
    final trimmed = content.trim();
    if (trimmed.isEmpty) return 'nostr:$encodedId';
    return '$trimmed\nnostr:$encodedId';
  }

  static const _imageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.heic',
    '.heif',
  ];

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return _imageExtensions.any(lower.endsWith);
  }

  Future<String?> _getImageDimensions(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final dim = '${frame.image.width}x${frame.image.height}';
      frame.image.dispose();
      codec.dispose();
      return dim;
    } catch (_) {
      return null;
    }
  }
}
