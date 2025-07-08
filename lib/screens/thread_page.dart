import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/root_note_widget.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/screens/note_statistics_page.dart';
import 'package:qiqstr/widgets/dialogs/repost_dialog.dart';
import 'package:qiqstr/widgets/dialogs/zap_dialog.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:collection/collection.dart';

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
    super.dispose();
  }

  void _onNotesChanged() => _loadRootNote();

  Future<void> _loadRootNote() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    _currentUserNpub = await _secureStorage.read(key: 'npub');
    final allNotes = widget.dataService.notesNotifier.value;

    _rootNote = allNotes.firstWhereOrNull((n) => n.id == widget.rootNoteId);

    if (widget.focusedNoteId != null && widget.focusedNoteId != widget.rootNoteId) {
      _focusedNote = allNotes.firstWhereOrNull((n) => n.id == widget.focusedNoteId);
    } else {
      _focusedNote = null;
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (widget.focusedNoteId != null && (_focusedNote != null || _rootNote?.id == widget.focusedNoteId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToFocusedNote();
        });
      }
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
        Scrollable.ensureVisible(context,
            duration: const Duration(milliseconds: 500), curve: Curves.easeInOut, alignment: 0.1);
      }
    }

    Future.delayed(const Duration(seconds: 2), () => {if (mounted) setState(() => _highlightedNoteId = null)});
  }

  bool _hasReacted(NoteModel note) {
    if (_currentUserNpub == null) return false;
    return (widget.dataService.reactionsMap[note.id] ?? [])
        .any((e) => e.author == _currentUserNpub);
  }

  bool _hasReplied(NoteModel note) {
    if (_currentUserNpub == null) return false;
    return (widget.dataService.repliesMap[note.id] ?? [])
        .any((e) => e.author == _currentUserNpub);
  }

  bool _hasReposted(NoteModel note) {
    if (_currentUserNpub == null) return false;
    return (widget.dataService.repostsMap[note.id] ?? [])
        .any((e) => e.repostedBy == _currentUserNpub);
  }

  bool _hasZapped(NoteModel note) {
    if (_currentUserNpub == null) return false;
    return (widget.dataService.zapsMap[note.id] ?? [])
        .any((z) => z.sender == _currentUserNpub);
  }

  void _navigateToProfile(String npub) {
    widget.dataService.openUserProfile(context, npub);
  }

  void _handleReactionTap(NoteModel note) async {
    if (_hasReacted(note)) return;
    setState(() => _isReactionGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isReactionGlowing = false);
    });
    try {
      await widget.dataService.sendReaction(note.id, '+');
    } catch (_) {}
  }

  void _handleReplyTap(NoteModel note) {
    setState(() => _isReplyGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isReplyGlowing = false);
    });

    showDialog(
      context: context,
      builder: (_) => SendReplyDialog(
        dataService: widget.dataService,
        noteId: note.id,
      ),
    );
  }

  void _handleRepostTap(NoteModel note) {
    setState(() => _isRepostGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRepostGlowing = false);
    });

    showRepostDialog(
      context: context,
      dataService: widget.dataService,
      note: note,
    );
  }

  void _handleZapTap(NoteModel note) {
    setState(() => _isZapGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isZapGlowing = false);
    });

    showZapDialog(context: context, dataService: widget.dataService, note: note);
  }

  void _handleStatisticsTap(NoteModel note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteStatisticsPage(note: note, dataService: widget.dataService),
      ),
    );
  }

  Widget _buildBlurredHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          height: topPadding + 56,
          color: Colors.black.withOpacity(0.5),
          padding: EdgeInsets.fromLTRB(8, topPadding, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Thread',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No replies yet',
            style: TextStyle(color: Colors.white70, fontSize: 16),
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
                  lineColor: Colors.grey[700]!,
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
                  child: NoteWidget(
                    note: reply,
                    reactionCount: reply.reactionCount,
                    replyCount: reply.replyCount,
                    repostCount: reply.repostCount,
                    dataService: widget.dataService,
                    currentUserNpub: _currentUserNpub!,
                    notesNotifier: widget.dataService.notesNotifier,
                    profiles: widget.dataService.profilesNotifier.value,
                    isSmallView: depth > 0,
                    containerColor: Colors.transparent,
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
    final NoteModel? displayRoot = _focusedNote ?? _rootNote;
    final NoteModel? contextNote = _focusedNote != null ? _rootNote : null;
    final isDisplayRootHighlighted = displayRoot?.id == _highlightedNoteId;

    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = topPadding + 56;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : displayRoot == null
              ? const Center(child: Text('Note not found.', style: TextStyle(color: Colors.white70)))
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
                              child: NoteWidget(
                                note: contextNote,
                                reactionCount: contextNote.reactionCount,
                                replyCount: contextNote.replyCount,
                                repostCount: contextNote.repostCount,
                                dataService: widget.dataService,
                                currentUserNpub: _currentUserNpub!,
                                notesNotifier: widget.dataService.notesNotifier,
                                profiles: widget.dataService.profilesNotifier.value,
                                isSmallView: true,
                                containerColor: Colors.transparent,
                              ),
                            ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            color: isDisplayRootHighlighted
                                ? Theme.of(context).primaryColor.withOpacity(0.1)
                                : Colors.transparent,
                            child: RootNoteWidget(
                              key: _focusedNote != null ? _focusedNoteKey : null,
                              note: displayRoot,
                              dataService: widget.dataService,
                              onNavigateToMentionProfile: _navigateToProfile,
                              isReactionGlowing: _isReactionGlowing,
                              isReplyGlowing: _isReplyGlowing,
                              isRepostGlowing: _isRepostGlowing,
                              isZapGlowing: _isZapGlowing,
                              hasReacted: _hasReacted(displayRoot),
                              hasReplied: _hasReplied(displayRoot),
                              hasReposted: _hasReposted(displayRoot),
                              hasZapped: _hasZapped(displayRoot),
                              onReactionTap: () => _handleReactionTap(displayRoot),
                              onReplyTap: () => _handleReplyTap(displayRoot),
                              onRepostTap: () => _handleRepostTap(displayRoot),
                              onZapTap: () => _handleZapTap(displayRoot),
                              onStatisticsTap: () => _handleStatisticsTap(displayRoot),
                            ),
                          ),
                          _buildThreadReplies(displayRoot),
                          const SizedBox(height: 24.0),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildBlurredHeader(context),
                    ),
                  ],
                ),
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
