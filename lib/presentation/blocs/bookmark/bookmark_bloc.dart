import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/encrypted_bookmark_service.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../src/rust/api/relay.dart' as rust_relay;
import 'bookmark_event.dart';
import 'bookmark_state.dart';

class BookmarkBloc extends Bloc<BookmarkEvent, BookmarkState> {
  final FeedRepository _feedRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;

  BookmarkBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
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
    final noteFutures =
        eventIds.map((id) => _feedRepository.getNote(id)).toList();
    final noteResults = await Future.wait(noteFutures);

    final authorHexes = <String>{};
    final validNotes = <Map<String, dynamic>>[];
    final missingIds = <String>[];

    for (var i = 0; i < eventIds.length; i++) {
      final note = noteResults[i];
      if (note != null) {
        final noteMap = note.toMap();
        validNotes.add(noteMap);
        final authorHex = noteMap['author'] as String? ?? '';
        if (authorHex.isNotEmpty) authorHexes.add(authorHex);
      } else {
        missingIds.add(eventIds[i]);
      }
    }

    if (missingIds.isNotEmpty) {
      final fetchFutures = missingIds.map((id) async {
        try {
          final eventJson = await rust_relay.fetchEventById(
            eventId: id,
            timeoutSecs: 5,
          );
          if (eventJson == null) return null;

          final eventData = jsonDecode(eventJson) as Map<String, dynamic>;
          await RustDatabaseService.instance.saveEvents([eventData]);

          return await _feedRepository.getNote(id);
        } catch (_) {
          return null;
        }
      }).toList();

      final fetchedNotes = await Future.wait(fetchFutures);
      for (final note in fetchedNotes) {
        if (note == null) continue;
        final noteMap = note.toMap();
        validNotes.add(noteMap);
        final authorHex = noteMap['author'] as String? ?? '';
        if (authorHex.isNotEmpty) authorHexes.add(authorHex);
      }
    }

    if (authorHexes.isEmpty) return validNotes;

    final profiles =
        await _profileRepository.getProfiles(authorHexes.toList());

    for (final noteMap in validNotes) {
      final authorHex = noteMap['author'] as String? ?? '';
      final profile = profiles[authorHex];
      if (profile != null) {
        noteMap['authorName'] = profile.name ?? profile.displayName ?? '';
        noteMap['authorPicture'] = profile.picture ?? '';
      }
    }

    validNotes.sort((a, b) {
      final aTime = (a['created_at'] as num?) ?? 0;
      final bTime = (b['created_at'] as num?) ?? 0;
      return bTime.compareTo(aTime);
    });

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
      final note = await _feedRepository.getNote(event.eventId);
      if (note != null) {
        final noteMap = note.toMap();
        final authorHex = noteMap['author'] as String? ?? '';
        if (authorHex.isNotEmpty) {
          final profiles =
              await _profileRepository.getProfiles([authorHex]);
          final profile = profiles[authorHex];
          if (profile != null) {
            noteMap['authorName'] =
                profile.name ?? profile.displayName ?? '';
            noteMap['authorPicture'] = profile.picture ?? '';
          }
        }
        emit(currentState.copyWith(
          bookmarkedNotes: [noteMap, ...currentState.bookmarkedNotes],
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
