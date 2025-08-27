import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Map<String, List<NoteModel>>? _cachedThreadHierarchy;
  String? _lastHierarchyRootId;
  int _lastNotesVersion = 0;

  Timer? _uiUpdateTimer;
  bool _hasPendingUIUpdate = false;

  static const int repliesPerPage = 10;
  static const int maxNestingDepth = 2;

  int _currentlyShownReplies = 10;

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
    _uiUpdateTimer?.cancel();
    super.dispose();
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
          break;
        }
      }
    }

    if (hasRelevantChanges) {
      _cachedThreadHierarchy = null;

      _debounceUIUpdate();

      Future.microtask(() => _fetchAllThreadUserProfiles());
    }
  }

  void _debounceUIUpdate() {
    if (_hasPendingUIUpdate) return;

    _hasPendingUIUpdate = true;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted && !_isLoading) {
        _hasPendingUIUpdate = false;
        _loadRootNote();
      }
    });
  }

  Timer? _reloadTimer;

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

      if (mounted) {
        setState(() => _isLoading = false);
        if (widget.focusedNoteId != null && (_focusedNote != null || _rootNote?.id == widget.focusedNoteId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToFocusedNote();
          });
        }
      }

      _loadAdditionalDataInBackground();

      _loadThreadInteractions();
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

  Future<void> _loadThreadInteractions() async {
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

      print('[ThreadPage] Loading interactions for ${threadEventIds.length} thread notes');

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
    final futures = noteIds.map((noteId) async {
      try {
        final note = await widget.dataService.getCachedNote(noteId).timeout(const Duration(seconds: 2));
        if (note != null) {
          print('[ThreadPage] Successfully fetched note: $noteId');
        } else {
          print('[ThreadPage] Failed to fetch note: $noteId');
        }
      } catch (e) {
        print('[ThreadPage] Error fetching note $noteId: $e');
      }
    });

    await Future.wait(futures).timeout(const Duration(seconds: 5));
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

  Map<String, List<NoteModel>> _getOrBuildThreadHierarchy(String rootId) {
    if (_cachedThreadHierarchy != null && _lastHierarchyRootId == rootId) {
      return _cachedThreadHierarchy!;
    }

    _cachedThreadHierarchy = widget.dataService.buildThreadHierarchy(rootId);
    _lastHierarchyRootId = rootId;
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

    final visibleReplies = directReplies.take(_currentlyShownReplies).toList();
    final hasMore = directReplies.length > _currentlyShownReplies;
    final remainingCount = directReplies.length - _currentlyShownReplies;

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
                    ...nestedReplies.take(5).toList().asMap().entries.map((entry) {
                      final index = entry.key;
                      final nestedReply = entry.value;
                      return _buildThreadReplyWithDepth(
                        nestedReply,
                        hierarchy,
                        depth + 1,
                        index == nestedReplies.take(5).length - 1,
                        [...parentIsLast, isLast],
                      );
                    }),
                    if (nestedReplies.length > 5)
                      Container(
                        margin: EdgeInsets.only(left: (depth + 1) * indentWidth + 8),
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: Text(
                          '${nestedReplies.length - 5} more replies...',
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
          reactionCount: noteToUse.reactionCount,
          replyCount: noteToUse.replyCount,
          repostCount: noteToUse.repostCount,
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
