import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../services/data_service.dart';
import '../services/data_service_manager.dart';
import '../providers/user_provider.dart';
import 'base_provider.dart';

class NotesListProvider extends BaseProvider {
  final String npub;
  final DataType dataType;
  late final DataService dataService;

  List<NoteModel> _notes = [];
  List<NoteModel> _filteredNotes = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String? _errorMessage;

  bool _isInitialized = false;

  String? _currentUserNpub;

  int _newNotesCount = 0;
  List<String> _lastKnownNoteIds = [];

  List<NoteModel>? _cachedFilteredNotes;
  int _lastNotesLength = 0;

  bool _isPreloadingDependencies = false;
  final Set<String> _preloadedNoteIds = {};
  final Map<String, String> _preloadedMentions = {};
  final Map<String, NoteModel> _preloadedQuotes = {};
  final Set<String> _preloadedUserProfiles = {};

  int _displayedNotesCount = 25;
  static const int notesPerPage = 25;

  NotesListProvider({
    required this.npub,
    required this.dataType,
    DataService? sharedDataService,
  }) {
    if (sharedDataService != null) {
      dataService = sharedDataService;
    } else {
      dataService = DataServiceManager.instance.getOrCreateService(
        npub: npub,
        dataType: dataType,
      );
    }
    _initialize();
  }

  List<NoteModel> get notes {
    return _filteredNotes.take(_displayedNotesCount).toList();
  }

  List<NoteModel> get allFilteredNotes => _filteredNotes;

  bool get hasMoreNotes => _filteredNotes.length > _displayedNotesCount;

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _filteredNotes.isEmpty && !_isLoading;

  int get newNotesCount => _newNotesCount;
  bool get hasNewNotes => _newNotesCount > 0;

  String get currentUserNpub => _currentUserNpub ?? '';

  void loadMoreDisplayedNotes() {
    if (hasMoreNotes) {
      _displayedNotesCount += notesPerPage;
      if (_displayedNotesCount > _filteredNotes.length) {
        _displayedNotesCount = _filteredNotes.length;
      }
      safeNotifyListeners();
      debugPrint('[NotesListProvider] Displaying $_displayedNotesCount of ${_filteredNotes.length} notes');

      _loadProfilesForNewlyDisplayedNotes();
    }
  }

  void _loadProfilesForNewlyDisplayedNotes() {
    final newlyDisplayedStart = _displayedNotesCount - notesPerPage;
    final newlyDisplayedNotes = _filteredNotes.skip(newlyDisplayedStart).take(notesPerPage).toList();

    final userNpubs = <String>{};
    for (final note in newlyDisplayedNotes) {
      userNpubs.add(note.author);
      if (note.repostedBy != null) {
        userNpubs.add(note.repostedBy!);
      }
    }

    if (userNpubs.isNotEmpty) {
      UserProvider.instance.loadUsers(userNpubs.toList()).catchError((e) {
        handleError('newly displayed notes profile load', e);
      });
      debugPrint('[NotesListProvider] Loaded profiles for ${userNpubs.length} newly displayed notes');
    }

    final noteIds = newlyDisplayedNotes.map((note) => note.id).toList();
    if (noteIds.isNotEmpty) {
      fetchInteractionsForNotes(noteIds);
    }
  }

  void _initialize() {
    dataService.notesNotifier.addListener(_onNotesChanged);
    _onNotesChanged();
    _loadCurrentUserNpub();

    if (!_isInitialized) {
      final initDelay = dataType == DataType.profile ? const Duration(milliseconds: 50) : const Duration(milliseconds: 200);

      Timer(initDelay, () {
        _isInitialized = true;
        notifyListeners();
        _startPeriodicUpdates();
      });
    }
  }

  Future<void> _loadCurrentUserNpub() async {
    try {
      final storage = const FlutterSecureStorage();
      _currentUserNpub = await storage.read(key: 'npub');
      debugPrint('[NotesListProvider] Loaded current user npub: ${_currentUserNpub?.substring(0, 8)}...');
    } catch (e) {
      debugPrint('[NotesListProvider] Error loading current user npub: $e');
    }
  }

  void _onNotesChanged() {
    _notes = dataService.notesNotifier.value;
    _detectNewNotes();
    _preloadNoteDependenciesAndFilter();
  }

  void _detectNewNotes() {
    if (!_isInitialized || dataType != DataType.feed) return;

    final List<NoteModel> newFilteredNotes = [];
    for (final n in _notes) {
      if (!n.isReply || n.isRepost) {
        newFilteredNotes.add(n);
      }
    }
    final currentNoteIds = newFilteredNotes.map((n) => n.id).toList();

    if (_lastKnownNoteIds.isNotEmpty) {
      final newNoteIds = currentNoteIds.where((id) => !_lastKnownNoteIds.contains(id)).toList();
      if (newNoteIds.isNotEmpty) {
        _newNotesCount += newNoteIds.length;
      }
    }

    _lastKnownNoteIds = currentNoteIds;
  }

  void _preloadNoteDependenciesAndFilter() {
    if (_isPreloadingDependencies) return;

    if (_cachedFilteredNotes == null || _notes.length != _lastNotesLength) {
      final potentialNotes = <NoteModel>[];
      potentialNotes.addAll(_notes.where((n) => !n.isReply || n.isRepost));
      _cachedFilteredNotes = potentialNotes;
      _lastNotesLength = _notes.length;
    }

    if (_newNotesCount == 0) {
      _preloadDependenciesForNotes(_cachedFilteredNotes ?? []);
    }
  }

  Future<void> _preloadDependenciesForNotes(List<NoteModel> notes) async {
    if (_isPreloadingDependencies || notes.isEmpty) return;

    _isPreloadingDependencies = true;

    try {
      final limitedNotes = notes.take(50).toList();
      final dependencies = _extractNoteDependencies(limitedNotes);

      Future.microtask(() => _preloadUserProfiles(dependencies.userProfiles));
      await Future.delayed(const Duration(milliseconds: 10));

      Future.microtask(() => _preloadMentions(dependencies.mentions));
      await Future.delayed(const Duration(milliseconds: 10));

      Future.microtask(() => _preloadQuotes(dependencies.quotes));

      _filteredNotes = notes;

      if (_isInitialized) {
        safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('[NotesListProvider] Error preloading dependencies: $e');
      _filteredNotes = notes;
      if (_isInitialized) {
        safeNotifyListeners();
      }
    } finally {
      _isPreloadingDependencies = false;
    }
  }

  _NoteDependencies _extractNoteDependencies(List<NoteModel> notes) {
    final userProfiles = <String>{};
    final mentions = <String, List<String>>{};
    final quotes = <String>{};

    for (final note in notes) {
      userProfiles.add(note.author);
      if (note.repostedBy != null) {
        userProfiles.add(note.repostedBy!);
      }

      try {
        final parsedContent = note.parsedContentLazy;
        final textParts = (parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

        final noteMentions = <String>[];
        for (final part in textParts) {
          if (part['type'] == 'mention') {
            final mentionId = part['id'] as String?;
            if (mentionId != null) {
              noteMentions.add(mentionId);
            }
          }
        }

        if (noteMentions.isNotEmpty) {
          mentions[note.id] = noteMentions;
        }

        final quoteIds = (parsedContent['quoteIds'] as List<dynamic>?)?.cast<String>() ?? [];
        quotes.addAll(quoteIds);
      } catch (e) {
        debugPrint('[NotesListProvider] Error parsing note ${note.id}: $e');
      }
    }

    return _NoteDependencies(
      userProfiles: userProfiles.toList(),
      mentions: mentions,
      quotes: quotes.toList(),
    );
  }

  Future<void> _preloadUserProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return;

    final usersToLoad = userIds.where((id) => !_preloadedUserProfiles.contains(id)).toList();
    if (usersToLoad.isEmpty) return;

    try {
      await UserProvider.instance.loadUsers(usersToLoad);
      _preloadedUserProfiles.addAll(usersToLoad);
      debugPrint('[NotesListProvider] Pre-loaded ${usersToLoad.length} user profiles');
    } catch (e) {
      debugPrint('[NotesListProvider] Error pre-loading user profiles: $e');
    }
  }

  Future<void> _preloadMentions(Map<String, List<String>> mentionsByNote) async {
    if (mentionsByNote.isEmpty) return;

    final allMentionIds = <String>{};
    for (final mentions in mentionsByNote.values) {
      allMentionIds.addAll(mentions);
    }

    final mentionsToLoad = allMentionIds.where((id) => !_preloadedMentions.containsKey(id)).toList();
    if (mentionsToLoad.isEmpty) return;

    try {
      final resolvedMentions = await dataService.resolveMentions(mentionsToLoad);
      _preloadedMentions.addAll(resolvedMentions);
      debugPrint('[NotesListProvider] Pre-loaded ${resolvedMentions.length} mentions');
    } catch (e) {
      debugPrint('[NotesListProvider] Error pre-loading mentions: $e');
    }
  }

  Future<void> _preloadQuotes(List<String> quoteIds) async {
    if (quoteIds.isEmpty) return;

    final quotesToLoad = quoteIds.where((id) => !_preloadedQuotes.containsKey(id)).toList();
    if (quotesToLoad.isEmpty) return;

    try {
      for (final quoteId in quotesToLoad) {
        final eventId = _extractEventIdFromBech32(quoteId);
        if (eventId != null) {
          final quote = await dataService.getCachedNote(eventId);
          if (quote != null) {
            _preloadedQuotes[quoteId] = quote;

            if (!_preloadedUserProfiles.contains(quote.author)) {
              await UserProvider.instance.loadUser(quote.author);
              _preloadedUserProfiles.add(quote.author);
            }
          }
        }
      }
      debugPrint('[NotesListProvider] Pre-loaded ${_preloadedQuotes.length} quotes');
    } catch (e) {
      debugPrint('[NotesListProvider] Error pre-loading quotes: $e');
    }
  }

  String? _extractEventIdFromBech32(String bech32) {
    try {
      if (bech32.startsWith('note1')) {
        return decodeBasicBech32(bech32, 'note');
      } else if (bech32.startsWith('nevent1')) {
        final result = decodeTlvBech32Full(bech32, 'nevent');
        return result['type_0_main'];
      }
    } catch (e) {
      debugPrint('[NotesListProvider] Error extracting event ID from $bech32: $e');
    }
    return null;
  }

  Map<String, String> getMentionsForNote(String noteId) {
    final result = <String, String>{};
    try {
      final note = _notes.firstWhere((n) => n.id == noteId);
      final parsedContent = note.parsedContentLazy;
      final textParts = (parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

      for (final part in textParts) {
        if (part['type'] == 'mention') {
          final mentionId = part['id'] as String?;
          if (mentionId != null && _preloadedMentions.containsKey(mentionId)) {
            result[mentionId] = _preloadedMentions[mentionId]!;
          }
        }
      }
    } catch (e) {
      debugPrint('[NotesListProvider] Error getting mentions for note $noteId: $e');
    }
    return result;
  }

  NoteModel? getQuoteForBech32(String bech32) {
    return _preloadedQuotes[bech32];
  }

  UserModel? getPreloadedUser(String npub) {
    return UserProvider.instance.getUserIfExists(npub);
  }

  void _startPeriodicUpdates() {
    if (dataType == DataType.feed) {
      createPeriodicTimer(const Duration(minutes: 3), (timer) {
        _refreshNewNotes();
      });
    }
  }

  void _refreshNewNotes() {
    try {
      dataService.refreshNotes().catchError((e) {
        handleError('refresh notes', e);
      });
    } catch (e) {
      handleError('refresh new notes', e);
    }
  }

  void loadNewNotes() {
    if (_newNotesCount == 0) return;

    _filteredNotes = _cachedFilteredNotes ?? _notes.where((n) => !n.isReply || n.isRepost).toList();

    _newNotesCount = 0;
    _displayedNotesCount = 50;

    _lastKnownNoteIds = _filteredNotes.map((n) => n.id).toList();

    notifyListeners();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadUserProfiles();
    });
  }

  Future<void> fetchInitialNotes() async {
    if (_isLoading) return;

    _setLoading(true);
    _clearError();

    try {
      _preloadNoteDependenciesAndFilter();
      if (dataService.notes.isNotEmpty) {
        _setLoading(false);
        debugPrint('[NotesListProvider] Instant display: ${dataService.notes.length} cached notes');
      }

      Future.microtask(() async {
        await dataService.initializeLightweight();
        _preloadNoteDependenciesAndFilter();

        if (_isLoading) {
          _setLoading(false);
        }

        Future.microtask(() async {
          try {
            if (dataType == DataType.profile) {
              Future.microtask(() => dataService.initializeHeavyOperations());
              Future.microtask(() => dataService.initializeConnections());
              debugPrint('[NotesListProvider] Profile: Background operations started');
            } else {
              Future.microtask(() => dataService.initializeHeavyOperations());
              Future.microtask(() => dataService.initializeConnections());

              createTimer(const Duration(milliseconds: 500), _refreshNewNotes);
              debugPrint('[NotesListProvider] Feed: Background operations started');
            }
            _preloadNoteDependenciesAndFilter();
          } catch (e) {
            handleError('background initialization', e);
          }
        });
      });
    } catch (e) {
      _setError('Failed to load notes: $e');
      debugPrint('[NotesListProvider] Initial fetch error: $e');
      _setLoading(false);
    }
  }

  Future<void> fetchMoreNotes() async {
    if (_isLoadingMore || _isLoading) return;

    _setLoadingMore(true);

    try {
      if (dataType == DataType.profile) {
        await dataService.loadMoreNotes();
        debugPrint('[NotesListProvider] Profile: Load more completed faster');
      } else {
        await dataService.loadMoreNotes();

        Future.microtask(() => _refreshNewNotes());
      }
    } catch (e) {
      debugPrint('[NotesListProvider] Load more error: $e');
    } finally {
      _setLoadingMore(false);
    }
  }

  void refresh() {
    _notes.clear();
    _filteredNotes.clear();
    _displayedNotesCount = 50;
    notifyListeners();

    dataService.forceRefresh().then((_) {
      dataService.initializeConnections();
    }).catchError((e) {
      handleError('refresh', e);
    });
  }

  void _loadUserProfiles() {
    if (_filteredNotes.isEmpty) return;

    const int userProfileBatchSize = 12;
    final firstBatchNotes = _filteredNotes.take(userProfileBatchSize).toList();

    final userNpubs = <String>{};
    for (final note in firstBatchNotes) {
      userNpubs.add(note.author);
      if (note.repostedBy != null) {
        userNpubs.add(note.repostedBy!);
      }

      if (userNpubs.length >= userProfileBatchSize) break;
    }

    if (userNpubs.isNotEmpty) {
      UserProvider.instance.loadUsers(userNpubs.toList()).catchError((e) {
        handleError('user profile load', e);
      });

      debugPrint('[NotesListProvider] ${dataType.name}: Loaded ${userNpubs.length} user profiles');
    }
  }

  final Set<String> _fetchedInteractions = {};
  Timer? _interactionCleanupTimer;

  Future<void> fetchInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    try {
      final newNoteIds = noteIds.where((id) => !_fetchedInteractions.contains(id)).toList();

      if (newNoteIds.isEmpty) {
        debugPrint('[NotesListProvider] All ${noteIds.length} visible notes already have fetched interactions');
        return;
      }

      _fetchedInteractions.addAll(newNoteIds);

      Future.microtask(() async {
        await dataService.fetchInteractionsForEvents(newNoteIds, forceLoad: true);
      });

      debugPrint(
          '[NotesListProvider] Fetched interactions for ${newNoteIds.length} new visible notes (${noteIds.length - newNoteIds.length} already cached)');

      _scheduleInteractionCleanup();
    } catch (e) {
      handleError('fetching interactions for visible notes', e);

      _fetchedInteractions.removeWhere((id) => noteIds.contains(id));
    }
  }

  void _scheduleInteractionCleanup() {
    _interactionCleanupTimer?.cancel();

    _interactionCleanupTimer = Timer(const Duration(minutes: 10), () {
      if (_fetchedInteractions.length > 500) {
        if (_filteredNotes.isNotEmpty) {
          final recentNoteIds = _filteredNotes.take(300).map((note) => note.id).toSet();
          _fetchedInteractions.retainWhere((id) => recentNoteIds.contains(id));
          debugPrint('[NotesListProvider] Cleaned up interaction fetch cache: ${_fetchedInteractions.length} entries retained');
        }
      }
    });
  }

  Future<void> fetchProfilesForVisibleNotes(List<String> visibleNoteIds) async {
    if (visibleNoteIds.isEmpty) return;

    try {
      final visibleNotes = _filteredNotes.where((note) => visibleNoteIds.contains(note.id)).toList();

      if (visibleNotes.isEmpty) return;

      final authorNpubs = <String>{};
      for (final note in visibleNotes) {
        authorNpubs.add(note.author);
        if (note.repostedBy != null) {
          authorNpubs.add(note.repostedBy!);
        }
      }

      if (authorNpubs.isNotEmpty) {
        Future.microtask(() async {
          await UserProvider.instance.loadUsers(authorNpubs.toList());
        });
        debugPrint('[NotesListProvider] Loaded profiles for ${authorNpubs.length} authors of ${visibleNotes.length} visible notes');
      }
    } catch (e) {
      handleError('fetching profiles for visible notes', e);
    }
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      safeNotifyListeners();
    }
  }

  void _setLoadingMore(bool loading) {
    if (_isLoadingMore != loading) {
      _isLoadingMore = loading;
      safeNotifyListeners();
    }
  }

  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    safeNotifyListeners();
  }

  void _clearError() {
    if (_hasError) {
      _hasError = false;
      _errorMessage = null;
      safeNotifyListeners();
    }
  }

  void _clearPreloadedData() {
    _preloadedNoteIds.clear();
    _preloadedMentions.clear();
    _preloadedQuotes.clear();
    _preloadedUserProfiles.clear();
  }

  @override
  void dispose() {
    dataService.notesNotifier.removeListener(_onNotesChanged);
    DataServiceManager.instance.releaseService(npub: npub, dataType: dataType);

    _cachedFilteredNotes = null;
    _fetchedInteractions.clear();
    _interactionCleanupTimer?.cancel();
    _clearPreloadedData();

    super.dispose();
  }
}

class _NoteDependencies {
  final List<String> userProfiles;
  final Map<String, List<String>> mentions;
  final List<String> quotes;

  const _NoteDependencies({
    required this.userProfiles,
    required this.mentions,
    required this.quotes,
  });
}
