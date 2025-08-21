import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bounce/bounce.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/root_note_widget.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:collection/collection.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    widget.dataService.notesNotifier.addListener(_onNotesChanged);
    _loadRootNote();
  }

  @override
  void dispose() {
    widget.dataService.notesNotifier.removeListener(_onNotesChanged);
    _scrollController.dispose();
    _reloadTimer?.cancel();
    super.dispose();
  }

  void _onNotesChanged() {
    if (_isLoading) return; // Prevent changes during loading

    final allNotes = widget.dataService.notesNotifier.value;
    bool hasRelevantChanges = false;

    // Check if any relevant notes have actually changed
    allNotes.where((note) => _relevantNoteIds.contains(note.id)).toList();

    // Only reload if we have new relevant notes or if existing relevant notes have changed
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

    // Check for new replies to relevant notes
    if (!hasRelevantChanges && _rootNote != null) {
      for (final note in allNotes) {
        if (note.isReply && (note.rootId == _rootNote!.id || note.parentId == _rootNote!.id) && !_relevantNoteIds.contains(note.id)) {
          hasRelevantChanges = true;
          break;
        }
      }
    }

    if (hasRelevantChanges) {
      // Use a debounced approach to prevent rapid successive reloads
      _debounceReload();

      // Also fetch profiles for any new users in the thread
      Future.microtask(() => _fetchAllThreadUserProfiles());
    }
  }

  Timer? _reloadTimer;

  void _debounceReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isLoading) {
        _loadRootNote();
      }
    });
  }

  Future<void> _loadRootNote() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _currentUserNpub = await _secureStorage.read(key: 'npub');
      final allNotes = widget.dataService.notesNotifier.value;

      _rootNote = allNotes.firstWhereOrNull((n) => n.id == widget.rootNoteId);

      if (widget.focusedNoteId != null && widget.focusedNoteId != widget.rootNoteId) {
        _focusedNote = allNotes.firstWhereOrNull((n) => n.id == widget.focusedNoteId);
      } else {
        _focusedNote = null;
      }

      _updateRelevantNoteIds();

      // Show content immediately if we have the root note, don't wait for everything
      if (mounted) {
        setState(() => _isLoading = false);
        if (widget.focusedNoteId != null && (_focusedNote != null || _rootNote?.id == widget.focusedNoteId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToFocusedNote();
          });
        }
      }

      // Load additional data in background without blocking UI
      _loadAdditionalDataInBackground();

      // Fetch interactions for thread on ThreadPage - performance optimization
      _loadThreadInteractions();
    } catch (e) {
      print('[ThreadPage] Error in _loadRootNote: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Load additional data in background without blocking the UI
  Future<void> _loadAdditionalDataInBackground() async {
    // Run these operations in background with timeouts
    final futures = <Future>[];

    // Fetch missing context notes with timeout
    futures.add(
        _fetchMissingContextNotes().timeout(const Duration(seconds: 3)).catchError((e) => print('[ThreadPage] Context fetch timeout: $e')));

    // Fetch profiles with timeout
    futures.add(_fetchAllThreadUserProfiles()
        .timeout(const Duration(seconds: 3))
        .catchError((e) => print('[ThreadPage] Profiles fetch timeout: $e')));

    // Wait for all with overall timeout
    try {
      await Future.wait(futures).timeout(const Duration(seconds: 5));
    } catch (e) {
      print('[ThreadPage] Background loading timeout: $e');
    }

    // Update UI if needed after background loading
    if (mounted) {
      setState(() {
        _updateRelevantNoteIds();
      });
    }
  }

  /// Special interaction loading for threads - only runs on thread page
  Future<void> _loadThreadInteractions() async {
    if (_rootNote == null) return;

    try {
      // Collect eventIds for all notes in the thread
      final threadEventIds = <String>{_rootNote!.id};

      if (_focusedNote != null) {
        threadEventIds.add(_focusedNote!.id);
      }

      // Get all replies from thread hierarchy
      final threadHierarchy = widget.dataService.buildThreadHierarchy(_rootNote!.id);
      for (final replies in threadHierarchy.values) {
        for (final reply in replies) {
          threadEventIds.add(reply.id);
        }
      }

      print('[ThreadPage] Loading interactions for ${threadEventIds.length} thread notes');

      // Fetch interactions only for this thread's notes
      await widget.dataService
          .fetchInteractionsForEvents(threadEventIds.toList())
          .timeout(const Duration(seconds: 3))
          .catchError((e) => print('[ThreadPage] Thread interactions fetch timeout: $e'));
    } catch (e) {
      print('[ThreadPage] Error loading thread interactions: $e');
    }
  }

  Future<void> _fetchAllThreadUserProfiles() async {
    if (_rootNote == null) return;

    final Set<String> allUserNpubs = {};

    // Add root note author
    allUserNpubs.add(_rootNote!.author);

    // Add focused note author if exists
    if (_focusedNote != null) {
      allUserNpubs.add(_focusedNote!.author);
    }

    // Add reposted by user if it's a repost
    if (_rootNote!.isRepost && _rootNote!.repostedBy != null) {
      allUserNpubs.add(_rootNote!.repostedBy!);
    }
    if (_focusedNote != null && _focusedNote!.isRepost && _focusedNote!.repostedBy != null) {
      allUserNpubs.add(_focusedNote!.repostedBy!);
    }

    // Get all replies in the thread hierarchy
    final threadHierarchy = widget.dataService.buildThreadHierarchy(_rootNote!.id);
    for (final replies in threadHierarchy.values) {
      for (final reply in replies) {
        allUserNpubs.add(reply.author);
        // Add reposted by user if reply is a repost
        if (reply.isRepost && reply.repostedBy != null) {
          allUserNpubs.add(reply.repostedBy!);
        }
      }
    }

    // Fetch profiles for all users in the thread with timeout
    if (allUserNpubs.isNotEmpty) {
      print('[ThreadPage] Fetching profiles for ${allUserNpubs.length} thread users');
      try {
        await widget.dataService.fetchProfilesBatch(allUserNpubs.toList()).timeout(const Duration(seconds: 3));
      } catch (e) {
        print('[ThreadPage] Profile fetch timeout: $e');
      }
    }
  }

  Future<void> _fetchMissingContextNotes() async {
    final List<String> notesToFetch = [];

    // If root note is missing, try to fetch it
    if (_rootNote == null) {
      notesToFetch.add(widget.rootNoteId);
    }

    // If focused note is missing, try to fetch it
    if (widget.focusedNoteId != null && _focusedNote == null) {
      notesToFetch.add(widget.focusedNoteId!);
    }

    // If we have a focused note that's a reply, ensure we have its parent/root context
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

    // Fetch missing notes with timeout
    if (notesToFetch.isNotEmpty) {
      print('[ThreadPage] Fetching missing context notes: $notesToFetch');
      try {
        await _fetchNotesById(notesToFetch).timeout(const Duration(seconds: 3));

        // Refresh our local references after fetching
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
    final futures = noteIds.map((noteId) async {
      try {
        final note = await widget.dataService.getCachedNote(noteId).timeout(const Duration(seconds: 2));
        if (note != null) {
          print('[ThreadPage] Successfully fetched note: $noteId');
          // The note should already be added to the notes list by getCachedNote
        } else {
          print('[ThreadPage] Failed to fetch note: $noteId');
        }
      } catch (e) {
        print('[ThreadPage] Error fetching note $noteId: $e');
      }
    });

    await Future.wait(futures).timeout(const Duration(seconds: 5));
  }

  // _fetchThreadReplies removed - now using _loadThreadInteractions

  void _updateRelevantNoteIds() {
    _relevantNoteIds.clear();

    if (_rootNote != null) {
      _relevantNoteIds.add(_rootNote!.id);

      final threadHierarchy = widget.dataService.buildThreadHierarchy(_rootNote!.id);
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

    final threadHierarchy = widget.dataService.buildThreadHierarchy(_rootNote!.id);
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

    List<Widget> threadWidgets = [];
    for (int i = 0; i < directReplies.length; i++) {
      threadWidgets.add(
        _buildThreadReplyWithDepth(
          directReplies[i],
          threadHierarchy,
          0,
          i == directReplies.length - 1,
          const [],
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 8.0),
        ...threadWidgets,
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
    const double indentWidth = 20.0;

    final isFocused = reply.id == widget.focusedNoteId;
    final isHighlighted = reply.id == _highlightedNoteId;
    final nestedReplies = hierarchy[reply.id] ?? [];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (depth > 0)
            SizedBox(
              width: depth * indentWidth,
              child: CustomPaint(
                painter: _ThreadLinePainter(
                  depth: depth,
                  isLast: isLast,
                  parentIsLast: parentIsLast,
                  indentWidth: indentWidth,
                  lineColor: context.colors.border,
                ),
              ),
            ),
          Expanded(
            child: Column(
              key: isFocused ? _focusedNoteKey : null,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  margin: EdgeInsets.only(left: depth > 0 ? 8 : 0),
                  decoration: BoxDecoration(
                      color: isHighlighted ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8)),
                  child: ValueListenableBuilder<List<NoteModel>>(
                    valueListenable: widget.dataService.notesNotifier,
                    builder: (context, notes, child) {
                      final updatedReply = notes.firstWhereOrNull((n) => n.id == reply.id) ?? reply;
                      return NoteWidget(
                        note: updatedReply,
                        reactionCount: updatedReply.reactionCount,
                        replyCount: updatedReply.replyCount,
                        repostCount: updatedReply.repostCount,
                        dataService: widget.dataService,
                        currentUserNpub: _currentUserNpub!,
                        notesNotifier: widget.dataService.notesNotifier,
                        profiles: widget.dataService.profilesNotifier.value,
                        isSmallView: depth > 0,
                        containerColor: Colors.transparent,
                      );
                    },
                  ),
                ),
                if (depth < 2)
                  ...((hierarchy[reply.id] ?? []).asMap().entries.map((entry) {
                    final index = entry.key;
                    final nestedReply = entry.value;
                    return _buildThreadReplyWithDepth(
                      nestedReply,
                      hierarchy,
                      depth + 1,
                      index == nestedReplies.length - 1,
                      [...parentIsLast, isLast],
                    );
                  })),
                if (depth == 0) const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        final NoteModel? displayRoot = _focusedNote ?? _rootNote;
        final NoteModel? contextNote = _focusedNote != null ? _rootNote : null;
        final isDisplayRootHighlighted = displayRoot?.id == _highlightedNoteId;

        final double topPadding = MediaQuery.of(context).padding.top;
        final double headerHeight = topPadding + 60;

        return Scaffold(
          backgroundColor: context.colors.background,
          body: _isLoading
              ? Center(child: CircularProgressIndicator(color: context.colors.textPrimary))
              : displayRoot == null
                  ? Center(child: Text('Note not found.', style: TextStyle(color: context.colors.textSecondary)))
                  : Stack(
                      children: [
                        SingleChildScrollView(
                          controller: _scrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: headerHeight),
                              if (contextNote != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                                  child: ValueListenableBuilder<List<NoteModel>>(
                                    valueListenable: widget.dataService.notesNotifier,
                                    builder: (context, notes, child) {
                                      final updatedContextNote = notes.firstWhereOrNull((n) => n.id == contextNote.id) ?? contextNote;
                                      return NoteWidget(
                                        note: updatedContextNote,
                                        reactionCount: updatedContextNote.reactionCount,
                                        replyCount: updatedContextNote.replyCount,
                                        repostCount: updatedContextNote.repostCount,
                                        dataService: widget.dataService,
                                        currentUserNpub: _currentUserNpub!,
                                        notesNotifier: widget.dataService.notesNotifier,
                                        profiles: widget.dataService.profilesNotifier.value,
                                        isSmallView: true,
                                        containerColor: Colors.transparent,
                                      );
                                    },
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
