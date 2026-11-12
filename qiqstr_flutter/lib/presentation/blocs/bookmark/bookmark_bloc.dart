import 'dart:convert';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/encrypted_bookmark_service.dart';
import '../../../src/rust/api/relay.dart' as rust_relay;
import 'bookmark_event.dart';
import 'bookmark_state.dart';

class BookmarkBloc extends Bloc<BookmarkEvent, BookmarkState> {
  final FeedRepository _feedRepository;
  final SyncService _syncService;
  final AuthService _authService;

  BookmarkBloc({
    required this._feedRepository,
    required this._syncService,
    required this._authService,
  }) : super(const BookmarkInitial()) {
    on<BookmarkEvent>(_onEvent, transformer: sequential());
  }

  bool _isCurrentSession(int generation, String? userHex) =>
      generation == EncryptedBookmarkService.instance.sessionGeneration &&
      userHex == _authService.currentUserPubkeyHex;

  Future<void> _onEvent(
    BookmarkEvent event,
    Emitter<BookmarkState> emit,
  ) async {
    final sessionGeneration =
        EncryptedBookmarkService.instance.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    try {
      switch (event) {
        case BookmarkLoadRequested():
          await _onLoadRequested(event, emit);
        case BookmarkAdded():
          await _onBookmarkAdded(event, emit);
        case BookmarkRemoved():
          await _onBookmarkRemoved(event, emit);
        case BookmarkRefreshed():
          await _onBookmarkRefreshed(event, emit);
      }
    } catch (error) {
      if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
      final currentState = state;
      emit(BookmarkError(error.toString()));
      if (currentState is BookmarkLoaded) {
        emit(currentState);
      }
    }
  }

  Future<void> _onLoadRequested(
    BookmarkLoadRequested event,
    Emitter<BookmarkState> emit,
  ) async {
    final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
    if (pubkeyResult.isError || pubkeyResult.data == null) {
      emit(const BookmarkError('Not authenticated'));
      return;
    }
    final currentUserHex = pubkeyResult.data!;

    final bookmarkService = EncryptedBookmarkService.instance;

    if (!bookmarkService.isInitialized) {
      final pkResult = await _authService.getCurrentUserPrivateKey();
      if (!pkResult.isError && pkResult.data != null) {
        await bookmarkService.loadFromDatabase(
          userPubkeyHex: currentUserHex,
          privateKeyHex: pkResult.data!,
        );
      }
    }

    if (bookmarkService.bookmarkedEventIds.isNotEmpty) {
      final notes = await _fetchBookmarkedNotes(
        bookmarkService.bookmarkedEventIds,
      );
      emit(
        BookmarkLoaded(
          bookmarkedNotes: notes,
          removingStates: {},
          isSyncing: true,
        ),
      );
    } else {
      emit(
        const BookmarkLoaded(
          bookmarkedNotes: [],
          removingStates: {},
          isSyncing: true,
        ),
      );
    }

    try {
      await _syncService.syncBookmarkList(currentUserHex);
      if (bookmarkService.bookmarkedEventIds.isNotEmpty) {
        final notes = await _fetchBookmarkedNotes(
          bookmarkService.bookmarkedEventIds,
        );
        if (state is BookmarkLoaded) {
          final currentState = state as BookmarkLoaded;
          emit(
            BookmarkLoaded(
              bookmarkedNotes: notes,
              removingStates: currentState.removingStates,
              isSyncing: false,
            ),
          );
        }
      } else {
        if (state is BookmarkLoaded) {
          final currentState = state as BookmarkLoaded;
          emit(
            currentState.copyWith(bookmarkedNotes: const [], isSyncing: false),
          );
        }
      }
    } catch (_) {
      if (state is BookmarkLoaded) {
        final currentState = state as BookmarkLoaded;
        emit(currentState.copyWith(isSyncing: false));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBookmarkedNotes(
    List<String> eventIds,
  ) async {
    final validNotes = [...await _feedRepository.getNotesByIds(eventIds)];

    final foundIds = validNotes
        .map((n) => n.toMap()['id'] as String? ?? '')
        .toSet();
    final missingIds = eventIds.where((id) => !foundIds.contains(id)).toList();

    if (missingIds.isNotEmpty) {
      try {
        final batchJson = await rust_relay.fetchEventsByIds(
          eventIds: missingIds,
          timeoutSecs: 5,
        );
        final fetched = jsonDecode(batchJson) as List<dynamic>;
        if (fetched.isNotEmpty) {
          final events = fetched.cast<Map<String, dynamic>>();
          await _feedRepository.save(events);
        }
      } catch (_) {}

      final refetched = await _feedRepository.getNotesByIds(missingIds);
      for (final n in refetched) {
        validNotes.add(n);
      }
    }

    final allNotes = validNotes.map((n) => n.toMap()).toList();
    allNotes.sort((a, b) {
      final aTime = (a['created_at'] as num?)?.toInt() ?? 0;
      final bTime = (b['created_at'] as num?)?.toInt() ?? 0;
      return bTime.compareTo(aTime);
    });
    return allNotes;
  }

  Future<void> _onBookmarkAdded(
    BookmarkAdded event,
    Emitter<BookmarkState> emit,
  ) async {
    final service = EncryptedBookmarkService.instance;
    final sessionGeneration = service.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    if (service.isBookmarked(event.eventId)) return;
    final previousIds = service.bookmarkedEventIds;
    service.addBookmark(event.eventId);
    try {
      await _syncService.publishBookmark(
        bookmarkedEventIds: service.bookmarkedEventIds,
      );
    } catch (_) {
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      service.updateCache(eventIds: previousIds);
      rethrow;
    }
    if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
    if (state is BookmarkLoaded) {
      final notes = await _feedRepository.getNotesByIds([event.eventId]);
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      if (notes.isNotEmpty && !emit.isDone && state is BookmarkLoaded) {
        final current = state as BookmarkLoaded;
        emit(
          current.copyWith(
            bookmarkedNotes: [
              notes.first.toMap(),
              ...current.bookmarkedNotes.where(
                (note) => note['id'] != event.eventId,
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _onBookmarkRemoved(
    BookmarkRemoved event,
    Emitter<BookmarkState> emit,
  ) async {
    final currentState = state;
    if (currentState is! BookmarkLoaded) return;
    final service = EncryptedBookmarkService.instance;
    final sessionGeneration = service.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    final previousIds = service.bookmarkedEventIds;
    emit(
      currentState.copyWith(
        removingStates: {...currentState.removingStates, event.eventId: true},
      ),
    );
    service.removeBookmark(event.eventId);
    try {
      await _syncService.publishBookmark(
        bookmarkedEventIds: service.bookmarkedEventIds,
      );
    } catch (_) {
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      service.updateCache(eventIds: previousIds);
      if (!emit.isDone) emit(currentState);
      rethrow;
    }
    if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
    emit(
      currentState.copyWith(
        bookmarkedNotes: currentState.bookmarkedNotes
            .where((note) => note['id'] != event.eventId)
            .toList(),
        removingStates: {...currentState.removingStates}..remove(event.eventId),
      ),
    );
  }

  Future<void> _onBookmarkRefreshed(
    BookmarkRefreshed event,
    Emitter<BookmarkState> emit,
  ) async {
    await _onLoadRequested(const BookmarkLoadRequested(), emit);
  }
}
