import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/encrypted_bookmark_service.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../src/rust/api/relay.dart' as rust_relay;
import 'bookmark_event.dart';
import 'bookmark_state.dart';

class BookmarkBloc extends Bloc<BookmarkEvent, BookmarkState> {
  final SyncService _syncService;
  final AuthService _authService;

  BookmarkBloc({
    required SyncService syncService,
    required AuthService authService,
  })  : _syncService = syncService,
        _authService = authService,
        super(const BookmarkInitial()) {
    on<BookmarkLoadRequested>(_onLoadRequested);
    on<BookmarkAdded>(_onBookmarkAdded);
    on<BookmarkRemoved>(_onBookmarkRemoved);
    on<BookmarkRefreshed>(_onBookmarkRefreshed);
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
      final notes =
          await _fetchBookmarkedNotes(bookmarkService.bookmarkedEventIds);
      emit(BookmarkLoaded(
        bookmarkedNotes: notes,
        removingStates: {},
        isSyncing: true,
      ));
      _syncBookmarksInBackground(currentUserHex, emit);
    } else if (bookmarkService.isInitialized) {
      emit(const BookmarkLoaded(
        bookmarkedNotes: [],
        removingStates: {},
        isSyncing: true,
      ));
      _syncBookmarksInBackground(currentUserHex, emit);
    } else {
      emit(const BookmarkLoaded(bookmarkedNotes: [], removingStates: {}));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBookmarkedNotes(
      List<String> eventIds) async {
    final db = RustDatabaseService.instance;
    final validNotes = await db.getHydratedNotesByIds(eventIds);

    final foundIds = <String>{};
    for (final n in validNotes) {
      final id = n['id'] as String? ?? '';
      if (id.isNotEmpty) foundIds.add(id);
    }
    final missingIds =
        eventIds.where((id) => !foundIds.contains(id)).toList();

    if (missingIds.isNotEmpty) {
      try {
        final batchJson = await rust_relay.fetchEventsByIds(
          eventIds: missingIds,
          timeoutSecs: 5,
        );
        final fetched = jsonDecode(batchJson) as List<dynamic>;
        if (fetched.isNotEmpty) {
          final events = fetched.cast<Map<String, dynamic>>();
          await db.saveEvents(events);
        }
      } catch (_) {}

      final refetched = await db.getHydratedNotesByIds(missingIds);
      for (final n in refetched) {
        final id = n['id'] as String? ?? '';
        if (id.isNotEmpty && foundIds.add(id)) {
          validNotes.add(n);
        }
      }
    }

    return validNotes;
  }

  void _syncBookmarksInBackground(
      String currentUserHex, Emitter<BookmarkState> emit) {
    _syncService.syncBookmarkList(currentUserHex).then((_) async {
      final bookmarkService = EncryptedBookmarkService.instance;
      if (bookmarkService.bookmarkedEventIds.isEmpty) {
        if (state is BookmarkLoaded) {
          final currentState = state as BookmarkLoaded;
          emit(currentState.copyWith(isSyncing: false));
        }
        return;
      }

      final notes =
          await _fetchBookmarkedNotes(bookmarkService.bookmarkedEventIds);

      if (state is BookmarkLoaded) {
        final currentState = state as BookmarkLoaded;
        emit(BookmarkLoaded(
          bookmarkedNotes: notes,
          removingStates: currentState.removingStates,
          isSyncing: false,
        ));
      }
    }).catchError((_) {
      if (state is BookmarkLoaded) {
        final currentState = state as BookmarkLoaded;
        emit(currentState.copyWith(isSyncing: false));
      }
    });
  }

  Future<void> _onBookmarkAdded(
    BookmarkAdded event,
    Emitter<BookmarkState> emit,
  ) async {
    final bookmarkService = EncryptedBookmarkService.instance;
    bookmarkService.addBookmark(event.eventId);

    if (state is BookmarkLoaded) {
      final currentState = state as BookmarkLoaded;
      final db = RustDatabaseService.instance;
      final notes = await db.getHydratedNotesByIds([event.eventId]);
      if (notes.isNotEmpty) {
        emit(currentState.copyWith(
          bookmarkedNotes: [notes.first, ...currentState.bookmarkedNotes],
        ));
      }
    }

    try {
      await _syncService.publishBookmark(
        bookmarkedEventIds: bookmarkService.bookmarkedEventIds,
      );
    } catch (_) {}
  }

  Future<void> _onBookmarkRemoved(
    BookmarkRemoved event,
    Emitter<BookmarkState> emit,
  ) async {
    final currentState = state;
    if (currentState is! BookmarkLoaded) return;

    final removingStates =
        Map<String, bool>.from(currentState.removingStates);
    if (removingStates[event.eventId] == true) return;

    removingStates[event.eventId] = true;
    emit(currentState.copyWith(removingStates: removingStates));

    try {
      final bookmarkService = EncryptedBookmarkService.instance;
      bookmarkService.removeBookmark(event.eventId);

      await _syncService.publishBookmark(
        bookmarkedEventIds: bookmarkService.bookmarkedEventIds,
      );

      final updatedNotes = currentState.bookmarkedNotes.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId != event.eventId;
      }).toList();

      removingStates.remove(event.eventId);
      emit(BookmarkLoaded(
        bookmarkedNotes: updatedNotes,
        removingStates: removingStates,
      ));
    } catch (_) {
      removingStates.remove(event.eventId);
      emit(currentState.copyWith(removingStates: removingStates));
    }
  }

  Future<void> _onBookmarkRefreshed(
    BookmarkRefreshed event,
    Emitter<BookmarkState> emit,
  ) async {
    await _onLoadRequested(const BookmarkLoadRequested(), emit);
  }
}
