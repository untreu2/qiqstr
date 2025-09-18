import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:bounce/bounce.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/services/nostr_service.dart';
import 'package:qiqstr/constants/relays.dart';
import 'package:qiqstr/widgets/root_note_widget.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:collection/collection.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import '../providers/interactions_provider.dart';
import '../providers/media_provider.dart';

class ThreadPage extends StatefulWidget {
  final String rootNoteId;
  final String? focusedNoteId;
  final DataService dataService;

  const ThreadPage({
    Key? key,
    required this.rootNoteId,
    this.focusedNoteId,
    required this.dataService,
  }) : super(key: key);

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  NoteModel? _rootNote;
  NoteModel? _focusedNote;
  String? _currentUserNpub;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _focusedNoteKey = GlobalKey();
  String? _highlightedNoteId;

  bool _isLoading = true;

  bool _isReactionGlowing = false;
  bool _isReplyGlowing = false;
  bool _isRepostGlowing = false;
  bool _isZapGlowing = false;

  Set<String> _relevantNoteIds = {};

  Map<String, List<NoteModel>>? _cachedThreadHierarchy;
  String? _lastHierarchyRootId;
  int _lastNotesVersion = 0;

  Timer? _uiUpdateTimer;
  bool _hasPendingUIUpdate = false;
  Timer? _periodicInteractionTimer;

  static const int repliesPerPage = 10;
  static const int maxNestingDepth = 2;

  int _currentlyShownReplies = 10;

  @override
  void initState() {
    super.initState();
    widget.dataService.notesNotifier.addListener(_onNotesChanged);

    InteractionsProvider.instance.addListener(_onInteractionsChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRootNote();
      _startPeriodicInteractionFetch();
    });
  }

  @override
  void dispose() {
    widget.dataService.notesNotifier.removeListener(_onNotesChanged);
    InteractionsProvider.instance.removeListener(_onInteractionsChanged);
    _scrollController.dispose();
    _reloadTimer?.cancel();
    _uiUpdateTimer?.cancel();
    _periodicInteractionTimer?.cancel();
    super.dispose();
  }

  void _onInteractionsChanged() {
    if (mounted && !_isLoading) {
      // Multiple rapid UI updates for immediate visibility
      setState(() {});

      // Immediate follow-up updates
      Future.microtask(() {
        if (mounted && !_isLoading) {
          setState(() {});
        }
      });

      Future.delayed(const Duration(milliseconds: 16), () {
        if (mounted && !_isLoading) {
          setState(() {});
        }
      });

      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && !_isLoading) {
          setState(() {});
        }
      });
    }
  }

  void _onNotesChanged() {
    if (_isLoading) return;

    final allNotes = widget.dataService.notesNotifier.value;
    final currentVersion = allNotes.hashCode;

    if (currentVersion == _lastNotesVersion) return;
    _lastNotesVersion = currentVersion;

    bool hasRelevantChanges = false;

    if (_rootNote != null) {
      final currentRootNote = allNotes.firstWhereOrNull((n) => n.id == _rootNote!.id);
      if (currentRootNote != null && currentRootNote != _rootNote) {
        hasRelevantChanges = true;
      }
    }

    if (!hasRelevantChanges && _focusedNote != null) {
      final currentFocusedNote = allNotes.firstWhereOrNull((n) => n.id == _focusedNote!.id);
      if (currentFocusedNote != null && currentFocusedNote != _focusedNote) {
        hasRelevantChanges = true;
      }
    }

    if (!hasRelevantChanges && _rootNote != null) {
      for (final note in allNotes) {
        if (note.isReply && (note.rootId == _rootNote!.id || note.parentId == _rootNote!.id) && !_relevantNoteIds.contains(note.id)) {
          hasRelevantChanges = true;
          print('[ThreadPage] New reply detected: ${note.id} - forcing immediate UI update');
          break;
        }
      }
    }

    if (hasRelevantChanges) {
      _cachedThreadHierarchy = null;

      // Multiple immediate UI updates for new replies
      if (mounted) {
        setState(() {
          _updateRelevantNoteIds();
          _updateVisibleNotesInProvider();
        });

        // Force additional immediate updates
        Future.microtask(() {
          if (mounted) setState(() {});
        });

        Timer(const Duration(milliseconds: 16), () {
          if (mounted) setState(() {});
        });

        Timer(const Duration(milliseconds: 50), () {
          if (mounted) setState(() {});
        });
      }

      // Aggressive interaction fetching for new replies
      Future.microtask(() async {
        await _fetchPeriodicInteractions();
        if (mounted) {
          setState(() {});
          // Force another update after fetch
          Future.microtask(() {
            if (mounted) setState(() {});
          });
        }
      });

      _debounceUIUpdate();

      Future.microtask(() => _fetchAllThreadUserProfiles());
    }
  }

  void _debounceUIUpdate() {
    if (_hasPendingUIUpdate) return;

    _hasPendingUIUpdate = true;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted && !_isLoading) {
        _hasPendingUIUpdate = false;

        // Force immediate state updates without full reload
        setState(() {
          _updateRelevantNoteIds();
          _updateVisibleNotesInProvider();
        });

        // Additional updates to ensure visibility
        Future.microtask(() {
          if (mounted) setState(() {});
        });

        Timer(const Duration(milliseconds: 25), () {
          if (mounted) setState(() {});
        });
      }
    });
  }

  Timer? _reloadTimer;

  Future<void> _loadRootNote() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _currentUserNpub = await _secureStorage.read(key: 'npub');

      final allNotesFromNotifier = widget.dataService.notesNotifier.value;
      final allNotesFromArray = widget.dataService.notes;

      print('[ThreadPage] Looking for root note: ${widget.rootNoteId}');
      print('[ThreadPage] Notifier has ${allNotesFromNotifier.length} notes');
      print('[ThreadPage] Array has ${allNotesFromArray.length} notes');

      _rootNote = allNotesFromNotifier.firstWhereOrNull((n) => n.id == widget.rootNoteId) ??
          allNotesFromArray.firstWhereOrNull((n) => n.id == widget.rootNoteId);

      if (_rootNote != null) {
        print('[ThreadPage] Found root note in existing data: ${_rootNote!.id}');
      } else {
        print('[ThreadPage] Root note not found in existing data, trying network fetch: ${widget.rootNoteId}');
        await _fetchNotesById([widget.rootNoteId]);
        final updatedNotesNotifier = widget.dataService.notesNotifier.value;
        final updatedNotesArray = widget.dataService.notes;
        _rootNote = updatedNotesNotifier.firstWhereOrNull((n) => n.id == widget.rootNoteId) ??
            updatedNotesArray.firstWhereOrNull((n) => n.id == widget.rootNoteId);
      }

      if (widget.focusedNoteId != null && widget.focusedNoteId != widget.rootNoteId) {
        print('[ThreadPage] Looking for focused note: ${widget.focusedNoteId}');

        _focusedNote = allNotesFromNotifier.firstWhereOrNull((n) => n.id == widget.focusedNoteId) ??
            allNotesFromArray.firstWhereOrNull((n) => n.id == widget.focusedNoteId);

        if (_focusedNote != null) {
          print('[ThreadPage] Found focused note in existing data: ${_focusedNote!.id}');
        } else {
          print('[ThreadPage] Focused note not found in existing data, trying network fetch: ${widget.focusedNoteId}');
          await _fetchNotesById([widget.focusedNoteId!]);
          final updatedNotesNotifier = widget.dataService.notesNotifier.value;
          final updatedNotesArray = widget.dataService.notes;
          _focusedNote = updatedNotesNotifier.firstWhereOrNull((n) => n.id == widget.focusedNoteId) ??
              updatedNotesArray.firstWhereOrNull((n) => n.id == widget.focusedNoteId);
        }
      } else {
        _focusedNote = null;
      }

      _updateRelevantNoteIds();

      if (mounted) {
        setState(() => _isLoading = false);
        if (widget.focusedNoteId != null && (_focusedNote != null || _rootNote?.id == widget.focusedNoteId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToFocusedNote();
          });
        }
      }

      _updateRelevantNoteIds();
      _updateVisibleNotesInProvider();

      await _fetchMissingThreadReplies();

      _updateRelevantNoteIds();
      _updateVisibleNotesInProvider();

      await _forceLoadAllInteractions();

      if (mounted) {
        setState(() {});
        Future.microtask(() {
          if (mounted) setState(() {});
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) setState(() {});
        });
      }

      _loadAdditionalDataInBackground();
    } catch (e) {
      print('[ThreadPage] Error in _loadRootNote: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAdditionalDataInBackground() async {
    final futures = <Future>[];

    futures.add(
        _fetchMissingContextNotes().timeout(const Duration(seconds: 3)).catchError((e) => print('[ThreadPage] Context fetch timeout: $e')));

    futures.add(_fetchAllThreadUserProfiles()
        .timeout(const Duration(seconds: 3))
        .catchError((e) => print('[ThreadPage] Profiles fetch timeout: $e')));

    try {
      await Future.wait(futures).timeout(const Duration(seconds: 5));
    } catch (e) {
      print('[ThreadPage] Background loading timeout: $e');
    }

    if (mounted) {
      setState(() {
        _updateRelevantNoteIds();
      });
    }
  }

  Future<void> _forceLoadAllInteractions() async {
    if (_rootNote == null) return;

    try {
      final threadEventIds = <String>{_rootNote!.id};

      if (_focusedNote != null) {
        threadEventIds.add(_focusedNote!.id);
      }

      final threadHierarchy = _getOrBuildThreadHierarchy(_rootNote!.id);
      for (final replies in threadHierarchy.values) {
        for (final reply in replies) {
          threadEventIds.add(reply.id);
        }
      }

      print('[ThreadPage] Force loading interactions for ${threadEventIds.length} thread notes');

      final futures = <Future>[];

      // Immediate parallel fetching with minimal delays
      futures.add(widget.dataService
          .fetchInteractionsForEvents(threadEventIds.toList(), forceLoad: true)
          .timeout(const Duration(seconds: 5))
          .catchError((e) => print('[ThreadPage] DataService interaction fetch error: $e')));

      // Faster attempt intervals for quicker loading
      for (int attempt = 0; attempt < 5; attempt++) {
        futures.add(Future.delayed(Duration(milliseconds: attempt * 50), () async {
          try {
            await InteractionsProvider.instance.fetchInteractionsForNotes(threadEventIds.toList());
            print('[ThreadPage] InteractionsProvider attempt ${attempt + 1} completed');

            // Immediate UI update after each successful fetch
            if (mounted) {
              setState(() {});
            }
          } catch (e) {
            print('[ThreadPage] InteractionsProvider attempt ${attempt + 1} failed: $e');
          }
        }));
      }

      futures.add(Future.microtask(() {
        InteractionsProvider.instance.updateVisibleNotes(threadEventIds);
        return InteractionsProvider.instance.fetchInteractionsForNotes(threadEventIds.toList());
      }).catchError((e) => print('[ThreadPage] Direct visibility update error: $e')));

      await Future.wait(futures, eagerError: false);

      print('[ThreadPage] All interaction loading attempts completed');

      final threadNotes = <NoteModel>[];
      if (_rootNote != null) threadNotes.add(_rootNote!);
      if (_focusedNote != null) threadNotes.add(_focusedNote!);

      for (final replies in threadHierarchy.values) {
        threadNotes.addAll(replies);
      }

      final notesWithMedia = threadNotes.where((note) => note.hasMedia).toList();
      if (notesWithMedia.isNotEmpty) {
        Future.microtask(() {
          MediaProvider.instance.cacheImagesFromNotes(notesWithMedia);
        });
        print('[ThreadPage] Cached media for ${notesWithMedia.length} thread notes with media');
      }

      _forceUIUpdates();
    } catch (e) {
      print('[ThreadPage] Error in force loading interactions: $e');

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _forceLoadAllInteractions();
        }
      });
    }
  }

  void _forceUIUpdates() {
    if (!mounted) return;

    // Immediate updates
    setState(() {});
    InteractionsProvider.instance.notifyListeners();

    // Rapid sequence of updates for maximum responsiveness
    for (int i = 0; i < 10; i++) {
      Future.delayed(Duration(milliseconds: i * 25), () {
        if (mounted) {
          setState(() {});
          if (i % 3 == 0) {
            InteractionsProvider.instance.notifyListeners();
          }
        }
      });
    }

    // Final updates
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        InteractionsProvider.instance.notifyListeners();
        setState(() {});
      }
    });
  }

  void _startPeriodicInteractionFetch() {
    _periodicInteractionTimer?.cancel();
    _periodicInteractionTimer = Timer.periodic(
      const Duration(milliseconds: 200), // Faster interval for better responsiveness
      (timer) async {
        if (!mounted || _isLoading) return;

        try {
          await _fetchPeriodicInteractions();
        } catch (e) {
          print('[ThreadPage] Periodic interaction fetch error: $e');
        }
      },
    );
  }

  Future<void> _fetchPeriodicInteractions() async {
    if (_rootNote == null) return;

    final threadEventIds = <String>{_rootNote!.id};

    if (_focusedNote != null) {
      threadEventIds.add(_focusedNote!.id);
    }

    final threadHierarchy = _getOrBuildThreadHierarchy(_rootNote!.id);
    for (final replies in threadHierarchy.values) {
      for (final reply in replies) {
        threadEventIds.add(reply.id);
      }
    }

    // Aggressive parallel fetching for maximum speed
    final futures = <Future>[];

    // Multiple simultaneous fetch attempts
    futures.add(InteractionsProvider.instance.fetchInteractionsForNotes(threadEventIds.toList()));
    futures.add(widget.dataService.fetchInteractionsForEvents(threadEventIds.toList(), forceLoad: false));

    try {
      await Future.wait(futures, eagerError: false);
    } catch (e) {
      print('[ThreadPage] Periodic interaction fetch error: $e');
    }

    InteractionsProvider.instance.updateVisibleNotes(threadEventIds);

    // Force immediate UI update after interaction fetch
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _fetchAllThreadUserProfiles() async {
    if (_rootNote == null) return;

    final Set<String> allUserNpubs = {};

    allUserNpubs.add(_rootNote!.author);

    if (_focusedNote != null) {
      allUserNpubs.add(_focusedNote!.author);
    }

    if (_rootNote!.isRepost && _rootNote!.repostedBy != null) {
      allUserNpubs.add(_rootNote!.repostedBy!);
    }
    if (_focusedNote != null && _focusedNote!.isRepost && _focusedNote!.repostedBy != null) {
      allUserNpubs.add(_focusedNote!.repostedBy!);
    }

    final threadHierarchy = _getOrBuildThreadHierarchy(_rootNote!.id);
    for (final replies in threadHierarchy.values) {
      for (final reply in replies) {
        allUserNpubs.add(reply.author);

        if (reply.isRepost && reply.repostedBy != null) {
          allUserNpubs.add(reply.repostedBy!);
        }
      }
    }

    if (allUserNpubs.isNotEmpty) {
      print('[ThreadPage] Fetching profiles for ${allUserNpubs.length} thread users');
      try {
        await widget.dataService.fetchProfilesBatch(allUserNpubs.toList()).timeout(const Duration(seconds: 3));
      } catch (e) {
        print('[ThreadPage] Profile fetch timeout: $e');
      }
    }
  }

  Future<void> _fetchMissingThreadReplies() async {
    if (_rootNote == null) return;

    try {
      _cachedThreadHierarchy = null;
      final threadHierarchy = _getOrBuildThreadHierarchy(_rootNote!.id);

      _updateRelevantNoteIds();

      final allReplyIds = <String>[];
      for (final replies in threadHierarchy.values) {
        for (final reply in replies) {
          allReplyIds.add(reply.id);
        }
      }

      if (allReplyIds.isNotEmpty) {
        print('[ThreadPage] Found ${allReplyIds.length} replies, fetching their interactions');

        await widget.dataService
            .fetchInteractionsForEvents(allReplyIds, forceLoad: false)
            .timeout(const Duration(seconds: 2))
            .catchError((e) => print('[ThreadPage] Reply interactions fetch timeout: $e'));
      }

      print('[ThreadPage] Thread replies processing completed');

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('[ThreadPage] Error fetching thread replies: $e');
    }
  }

  Future<void> _fetchMissingContextNotes() async {
    final List<String> notesToFetch = [];

    if (_rootNote == null) {
      notesToFetch.add(widget.rootNoteId);
    }

    if (widget.focusedNoteId != null && _focusedNote == null) {
      notesToFetch.add(widget.focusedNoteId!);
    }

    if (_focusedNote != null && _focusedNote!.isReply) {
      if (_focusedNote!.rootId != null && _focusedNote!.rootId!.isNotEmpty) {
        final rootExists = widget.dataService.notesNotifier.value.any((n) => n.id == _focusedNote!.rootId);
        if (!rootExists) {
          notesToFetch.add(_focusedNote!.rootId!);
        }
      }

      if (_focusedNote!.parentId != null && _focusedNote!.parentId!.isNotEmpty && _focusedNote!.parentId != _focusedNote!.rootId) {
        final parentExists = widget.dataService.notesNotifier.value.any((n) => n.id == _focusedNote!.parentId);
        if (!parentExists) {
          notesToFetch.add(_focusedNote!.parentId!);
        }
      }
    }

    if (notesToFetch.isNotEmpty) {
      print('[ThreadPage] Fetching missing context notes: $notesToFetch');
      try {
        await _fetchNotesById(notesToFetch).timeout(const Duration(seconds: 3));

        final updatedNotes = widget.dataService.notesNotifier.value;
        _rootNote = updatedNotes.firstWhereOrNull((n) => n.id == widget.rootNoteId);
        if (widget.focusedNoteId != null) {
          _focusedNote = updatedNotes.firstWhereOrNull((n) => n.id == widget.focusedNoteId);
        }
      } catch (e) {
        print('[ThreadPage] Timeout fetching missing notes: $e');
      }
    }
  }

  Future<void> _fetchNotesById(List<String> noteIds) async {
    print('[ThreadPage] Fetching notes by ID: $noteIds');

    for (final noteId in noteIds) {
      try {
        print('[ThreadPage] Attempting to fetch note: $noteId');

        var note = await widget.dataService.getCachedNote(noteId).timeout(const Duration(seconds: 3));

        if (note == null) {
          print('[ThreadPage] Note not in cache, trying network fetch: $noteId');

          note = await _fetchNoteFromNetwork(noteId).timeout(const Duration(seconds: 5));

          if (note != null) {
            widget.dataService.notes.add(note);
            widget.dataService.eventIds.add(note.id);
            widget.dataService.addNote(note);

            if (widget.dataService.notesBox != null && widget.dataService.notesBox!.isOpen) {
              try {
                await widget.dataService.notesBox!.put(note.id, note);
              } catch (e) {
                print('[ThreadPage] Error saving note to cache: $e');
              }
            }
          }
        }

        if (note != null) {
          print('[ThreadPage] Successfully fetched note: $noteId');
        } else {
          print('[ThreadPage] Failed to fetch note after all attempts: $noteId');
        }
      } catch (e) {
        print('[ThreadPage] Error fetching note $noteId: $e');
      }
    }
  }

  void _updateRelevantNoteIds() {
    _relevantNoteIds.clear();

    if (_rootNote != null) {
      _relevantNoteIds.add(_rootNote!.id);

      final threadHierarchy = _getOrBuildThreadHierarchy(_rootNote!.id);
      for (final replies in threadHierarchy.values) {
        for (final reply in replies) {
          _relevantNoteIds.add(reply.id);
        }
      }
    }

    if (_focusedNote != null) {
      _relevantNoteIds.add(_focusedNote!.id);
    }
  }

  void _updateVisibleNotesInProvider() {
    InteractionsProvider.instance.updateVisibleNotes(_relevantNoteIds);
  }

  Future<NoteModel?> _fetchNoteFromNetwork(String eventId) async {
    final relayUrls = relaySetMainSockets.take(3).toList();

    for (final relayUrl in relayUrls) {
      try {
        final note = await _fetchNoteFromRelay(relayUrl, eventId);
        if (note != null) {
          return note;
        }
      } catch (e) {
        print('[ThreadPage] Error fetching from relay $relayUrl: $e');
        continue;
      }
    }

    return null;
  }

  Future<NoteModel?> _fetchNoteFromRelay(String relayUrl, String eventId) async {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));

      final filter = NostrService.createEventByIdFilter(eventIds: [eventId]);
      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);

      final completer = Completer<Map<String, dynamic>?>();

      late StreamSubscription sub;
      sub = ws.listen((event) {
        try {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(event);
          if (decoded is List && decoded.length >= 3) {
            if (decoded[0] == 'EVENT') {
              final eventData = decoded[2] as Map<String, dynamic>;
              if (eventData['id'] == eventId) {
                completer.complete(eventData);
              }
            } else if (decoded[0] == 'EOSE') {
              if (!completer.isCompleted) {
                completer.complete(null);
              }
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });

      if (ws.readyState == WebSocket.open) {
        ws.add(serializedRequest);
      }

      final eventData = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

      await sub.cancel();
      await ws.close();

      if (eventData != null) {
        final tags = eventData['tags'] as List<dynamic>? ?? [];
        String? rootId;
        String? parentId;
        String? replyMarker;
        bool isReply = false;
        List<Map<String, String>> eTags = [];
        List<Map<String, String>> pTags = [];

        for (var tag in tags) {
          if (tag is List && tag.isNotEmpty) {
            if (tag[0] == 'e' && tag.length >= 2) {
              final eTag = <String, String>{
                'eventId': tag[1] as String,
                'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
                'marker': tag.length > 3 ? (tag[3] as String? ?? '') : '',
                'pubkey': tag.length > 4 ? (tag[4] as String? ?? '') : '',
              };
              eTags.add(eTag);

              if (tag.length >= 4 && tag[3] == 'root') {
                rootId = tag[1] as String;
                isReply = true;
                replyMarker = 'root';
              } else if (tag.length >= 4 && tag[3] == 'reply') {
                parentId = tag[1] as String;
                replyMarker = 'reply';
                isReply = true;
              } else if (rootId == null && parentId == null) {
                parentId = tag[1] as String;
                isReply = true;
              }
            } else if (tag[0] == 'p' && tag.length >= 2) {
              final pTag = <String, String>{
                'pubkey': tag[1] as String,
                'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
                'petname': tag.length > 3 ? (tag[3] as String? ?? '') : '',
              };
              pTags.add(pTag);
            }
          }
        }

        return NoteModel(
          id: eventData['id'] as String,
          content: eventData['content'] as String,
          author: eventData['pubkey'] as String,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (eventData['created_at'] as int) * 1000,
          ),
          isReply: isReply,
          isRepost: (eventData['kind'] as int) == 6,
          rootId: rootId,
          parentId: parentId ?? (isReply ? rootId : null),
          rawWs: jsonEncode(eventData),
          eTags: eTags,
          pTags: pTags,
          replyMarker: replyMarker,
        );
      }

      return null;
    } catch (e) {
      try {
        await ws?.close();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _retryFetchNote() async {
    print('[ThreadPage] Retrying note fetch');
    setState(() => _isLoading = true);

    try {
      await _fetchNotesById([widget.rootNoteId]);

      if (widget.focusedNoteId != null) {
        await _fetchNotesById([widget.focusedNoteId!]);
      }

      await _loadRootNote();
    } catch (e) {
      print('[ThreadPage] Retry failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, List<NoteModel>> _getOrBuildThreadHierarchy(String rootId) {
    // Always rebuild hierarchy to catch new replies immediately
    _cachedThreadHierarchy = null;

    print('[ThreadPage] Building fresh thread hierarchy for root: $rootId');

    final allNotes = [
      ...widget.dataService.notesNotifier.value,
      ...widget.dataService.notes,
    ];

    print('[ThreadPage] Available notes for hierarchy: ${allNotes.length}');

    _cachedThreadHierarchy = widget.dataService.buildThreadHierarchy(rootId);
    _lastHierarchyRootId = rootId;

    int totalReplies = 0;
    for (final replies in _cachedThreadHierarchy!.values) {
      totalReplies += replies.length;
    }

    print('[ThreadPage] Fresh thread hierarchy built with $totalReplies total replies');

    // Force immediate UI update after hierarchy rebuild
    if (mounted) {
      Future.microtask(() {
        if (mounted) setState(() {});
      });
    }

    return _cachedThreadHierarchy!;
  }

  void _scrollToFocusedNote() {
    if (!mounted || widget.focusedNoteId == null) return;

    setState(() {
      _highlightedNoteId = widget.focusedNoteId;
    });

    if (_focusedNote != null) {
      final context = _focusedNoteKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut, alignment: 0.1);
      }
    }

    Future.delayed(const Duration(seconds: 2), () => {if (mounted) setState(() => _highlightedNoteId = null)});
  }

  void _navigateToProfile(String npub) {
    widget.dataService.openUserProfile(context, npub);
  }

  Widget _buildFloatingBackButton(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.colors.backgroundTransparent,
              border: Border.all(
                color: context.colors.borderLight,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: Bounce(
              scaleFactor: 0.85,
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
              child: Icon(
                Icons.arrow_back,
                color: context.colors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThreadReplies(NoteModel noteForReplies) {
    if (_currentUserNpub == null || _rootNote == null) return const SizedBox.shrink();

    final threadHierarchy = _getOrBuildThreadHierarchy(_rootNote!.id);
    final directReplies = threadHierarchy[noteForReplies.id] ?? [];

    if (directReplies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'No replies yet',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
          ),
        ),
      );
    }

    final sortedReplies = directReplies.toList()
      ..sort((a, b) {
        if (a.replyMarker == 'root' && b.replyMarker != 'root') return -1;
        if (b.replyMarker == 'root' && a.replyMarker != 'root') return 1;

        return a.timestamp.compareTo(b.timestamp);
      });

    final visibleReplies = sortedReplies.take(_currentlyShownReplies).toList();
    final hasMore = sortedReplies.length > _currentlyShownReplies;
    final remainingCount = sortedReplies.length - _currentlyShownReplies;

    return Column(
      children: [
        const SizedBox(height: 8.0),
        ...visibleReplies.asMap().entries.map((entry) {
          final index = entry.key;
          final reply = entry.value;
          return _buildThreadReplyWithDepth(
            reply,
            threadHierarchy,
            0,
            index == visibleReplies.length - 1 && !hasMore,
            const [],
          );
        }),
        if (hasMore)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _currentlyShownReplies += repliesPerPage;

                  if (_currentlyShownReplies > directReplies.length) {
                    _currentlyShownReplies = directReplies.length;
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.surface,
                foregroundColor: context.colors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(remainingCount > repliesPerPage
                  ? 'Load ${repliesPerPage} more replies (${remainingCount} remaining)'
                  : 'Load ${remainingCount} more replies'),
            ),
          ),
      ],
    );
  }

  Widget _buildThreadReplyWithDepth(
    NoteModel reply,
    Map<String, List<NoteModel>> hierarchy,
    int depth,
    bool isLast,
    List<bool> parentIsLast,
  ) {
    if (depth >= maxNestingDepth) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.colors.surfaceTransparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Text(
          'More replies... (${(hierarchy[reply.id] ?? []).length} nested)',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    const double indentWidth = 20.0;
    final isFocused = reply.id == widget.focusedNoteId;
    final isHighlighted = reply.id == _highlightedNoteId;
    final nestedReplies = hierarchy[reply.id] ?? [];

    final sortedNestedReplies = nestedReplies.toList()
      ..sort((a, b) {
        if (a.replyMarker == 'root' && b.replyMarker != 'root') return -1;
        if (b.replyMarker == 'root' && a.replyMarker != 'root') return 1;
        return a.timestamp.compareTo(b.timestamp);
      });

    return RepaintBoundary(
      child: Container(
        margin: EdgeInsets.only(
          left: depth * indentWidth,
          bottom: depth == 0 ? 8.0 : 2.0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (depth > 0)
              Container(
                width: 2,
                height: 40,
                margin: const EdgeInsets.only(right: 8, top: 8),
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            Expanded(
              child: Column(
                key: isFocused ? _focusedNoteKey : null,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: EdgeInsets.only(left: depth > 0 ? 8 : 0),
                    decoration: BoxDecoration(
                      color: isHighlighted ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _OptimizedNoteWidget(
                      noteId: reply.id,
                      fallbackNote: reply,
                      dataService: widget.dataService,
                      currentUserNpub: _currentUserNpub!,
                      isSmallView: depth > 0,
                    ),
                  ),
                  if (depth < maxNestingDepth - 1) ...[
                    ...sortedNestedReplies.take(5).toList().asMap().entries.map((entry) {
                      final index = entry.key;
                      final nestedReply = entry.value;
                      return _buildThreadReplyWithDepth(
                        nestedReply,
                        hierarchy,
                        depth + 1,
                        index == sortedNestedReplies.take(5).length - 1,
                        [...parentIsLast, isLast],
                      );
                    }),
                    if (sortedNestedReplies.length > 5)
                      Container(
                        margin: EdgeInsets.only(left: (depth + 1) * indentWidth + 8),
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: Text(
                          '${sortedNestedReplies.length - 5} more replies...',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        final NoteModel? displayRoot = _focusedNote ?? _rootNote;

        NoteModel? contextNote;
        if (_focusedNote != null && _focusedNote!.isReply && _focusedNote!.parentId != null) {
          final allNotes = widget.dataService.notesNotifier.value;
          contextNote = allNotes.firstWhereOrNull((n) => n.id == _focusedNote!.parentId);
        }
        final isDisplayRootHighlighted = displayRoot?.id == _highlightedNoteId;

        final double topPadding = MediaQuery.of(context).padding.top;
        final double headerHeight = topPadding + 60;

        return Scaffold(
          backgroundColor: context.colors.background,
          body: _isLoading
              ? Center(child: CircularProgressIndicator(color: context.colors.textPrimary))
              : displayRoot == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: context.colors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Note not found',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'The note may have been deleted or is not available',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => _retryFetchNote(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.colors.accent,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        SingleChildScrollView(
                          key: PageStorageKey<String>('thread_${widget.rootNoteId}'),
                          controller: _scrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: headerHeight),
                              if (contextNote != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                                  child: _OptimizedNoteWidget(
                                    noteId: contextNote.id,
                                    fallbackNote: contextNote,
                                    dataService: widget.dataService,
                                    currentUserNpub: _currentUserNpub!,
                                    isSmallView: true,
                                  ),
                                ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeInOut,
                                color: isDisplayRootHighlighted ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
                                child: RootNoteWidget(
                                  key: _focusedNote != null ? _focusedNoteKey : null,
                                  note: displayRoot,
                                  dataService: widget.dataService,
                                  currentUserNpub: _currentUserNpub!,
                                  onNavigateToMentionProfile: _navigateToProfile,
                                  isReactionGlowing: _isReactionGlowing,
                                  isReplyGlowing: _isReplyGlowing,
                                  isRepostGlowing: _isRepostGlowing,
                                  isZapGlowing: _isZapGlowing,
                                ),
                              ),
                              _buildThreadReplies(displayRoot),
                              const SizedBox(height: 24.0),
                            ],
                          ),
                        ),
                        _buildFloatingBackButton(context),
                      ],
                    ),
        );
      },
    );
  }
}

class _OptimizedNoteWidget extends StatefulWidget {
  final String noteId;
  final NoteModel fallbackNote;
  final DataService dataService;
  final String currentUserNpub;
  final bool isSmallView;

  const _OptimizedNoteWidget({
    Key? key,
    required this.noteId,
    required this.fallbackNote,
    required this.dataService,
    required this.currentUserNpub,
    required this.isSmallView,
  }) : super(key: key);

  @override
  State<_OptimizedNoteWidget> createState() => _OptimizedNoteWidgetState();
}

class _OptimizedNoteWidgetState extends State<_OptimizedNoteWidget> {
  NoteModel? _cachedNote;
  int _lastNotesHash = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<NoteModel>>(
      valueListenable: widget.dataService.notesNotifier,
      builder: (context, notes, child) {
        final currentHash = notes.hashCode;

        if (currentHash != _lastNotesHash) {
          final updatedNote = notes.firstWhereOrNull((n) => n.id == widget.noteId);
          if (updatedNote != null) {
            _cachedNote = updatedNote;
          }
          _lastNotesHash = currentHash;
        }

        final noteToUse = _cachedNote ?? widget.fallbackNote;

        return NoteWidget(
          note: noteToUse,
          dataService: widget.dataService,
          currentUserNpub: widget.currentUserNpub,
          notesNotifier: widget.dataService.notesNotifier,
          profiles: widget.dataService.profilesNotifier.value,
          isSmallView: widget.isSmallView,
          containerColor: Colors.transparent,
        );
      },
    );
  }
}

class _ThreadLinePainter extends CustomPainter {
  final int depth;
  final bool isLast;
  final List<bool> parentIsLast;
  final double indentWidth;
  final Color lineColor;

  _ThreadLinePainter({
    required this.depth,
    required this.isLast,
    required this.parentIsLast,
    required this.indentWidth,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0;

    for (int i = 0; i < depth - 1; i++) {
      if (!parentIsLast[i]) {
        final dx = (i * indentWidth) + (indentWidth / 2);
        canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      }
    }
    final dx = ((depth - 1) * indentWidth) + (indentWidth / 2);
    const endY = 20.0;
    canvas.drawLine(Offset(dx, 0), Offset(dx, isLast ? endY : size.height), paint);
    canvas.drawLine(Offset(dx, endY), Offset(dx + indentWidth / 2, endY), paint);
  }

  @override
  bool shouldRepaint(covariant _ThreadLinePainter oldDelegate) {
    return oldDelegate.depth != depth ||
        oldDelegate.isLast != isLast ||
        oldDelegate.parentIsLast != parentIsLast ||
        oldDelegate.indentWidth != indentWidth ||
        oldDelegate.lineColor != lineColor;
  }
}
