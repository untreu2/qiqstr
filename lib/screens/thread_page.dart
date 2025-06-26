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
  String? _currentUserNpub;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _focusedNoteKey = GlobalKey();
  String? _highlightedNoteId;

  bool _isLoading = true;

  bool _isRootNoteReactionGlowing = false;
  bool _isRootNoteReplyGlowing = false;
  bool _isRootNoteRepostGlowing = false;
  bool _isRootNoteZapGlowing = false;

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

    try {
      _rootNote = allNotes.firstWhere(
        (n) => n.id == widget.rootNoteId,
      );
    } catch (e) {
      _rootNote = null;
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (_rootNote != null && widget.focusedNoteId != null) {
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

    if (widget.focusedNoteId != _rootNote?.id) {
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

  void _handleRootNoteReactionTap() async {
    if (_rootNote == null || _hasReacted(_rootNote!)) return;
    setState(() => _isRootNoteReactionGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRootNoteReactionGlowing = false);
    });
    try {
      await widget.dataService.sendReaction(_rootNote!.id, '+');
    } catch (_) {}
  }

  void _handleRootNoteReplyTap() {
    if (_rootNote == null) return;
    setState(() => _isRootNoteReplyGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRootNoteReplyGlowing = false);
    });

    showDialog(
      context: context,
      builder: (_) => SendReplyDialog(
        dataService: widget.dataService,
        noteId: _rootNote!.id,
      ),
    );
  }

  void _handleRootNoteRepostTap() {
    if (_rootNote == null) return;
    setState(() => _isRootNoteRepostGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRootNoteRepostGlowing = false);
    });

    showRepostDialog(
      context: context,
      dataService: widget.dataService,
      note: _rootNote!,
    );
  }

  void _handleRootNoteZapTap() {
    if (_rootNote == null) return;
    setState(() => _isRootNoteZapGlowing = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRootNoteZapGlowing = false);
    });

    showZapDialog(
        context: context, dataService: widget.dataService, note: _rootNote!);
  }

  void _handleRootNoteStatisticsTap() {
    if (_rootNote == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteStatisticsPage(
            note: _rootNote!, dataService: widget.dataService),
      ),
    );
  }

  Widget _buildThreadReplies() {
    if (_rootNote == null || _currentUserNpub == null) return const SizedBox.shrink();

    final threadHierarchy = widget.dataService.buildThreadHierarchy(_rootNote!.id);
    final directReplies = threadHierarchy[_rootNote!.id] ?? [];

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

    return Column(
      children: [
        const SizedBox(height: 8.0),
        ...directReplies.map((reply) => _buildThreadReplyWithDepth(reply, threadHierarchy, 0)).toList(),
      ],
    );
  }

  Widget _buildThreadReplyWithDepth(NoteModel reply, Map<String, List<NoteModel>> hierarchy, int depth) {
    const double indentWidth = 20.0;
    const int maxDepth = 5;

    final actualDepth = depth > maxDepth ? maxDepth : depth;
    final leftPadding = actualDepth * indentWidth;
    final isFocused = reply.id == widget.focusedNoteId;
    final isHighlighted = reply.id == _highlightedNoteId;

    return Column(
      key: isFocused ? _focusedNoteKey : null,
      children: [
        if (depth > 0)
          Container(
            margin: EdgeInsets.only(left: leftPadding - 10),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 20,
                  color: Colors.grey[700],
                ),
                Container(
                  width: 8,
                  height: 2,
                  color: Colors.grey[700],
                ),
              ],
            ),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          margin: EdgeInsets.only(left: leftPadding),
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
        ...((hierarchy[reply.id] ?? [])
            .map((nestedReply) => _buildThreadReplyWithDepth(nestedReply, hierarchy, depth + 1))),
        if (depth == 0) const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRootHighlighted = _rootNote?.id == _highlightedNoteId;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Thread'),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _rootNote == null
              ? const Center(child: Text('Root note not found.', style: TextStyle(color: Colors.white70)))
              : SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                        color: isRootHighlighted ?? false
                            ? Theme.of(context).primaryColor.withOpacity(0.1)
                            : Colors.transparent,
                        child: RootNoteWidget(
                          note: _rootNote!,
                          dataService: widget.dataService,
                          onNavigateToMentionProfile: _navigateToProfile,
                          isReactionGlowing: _isRootNoteReactionGlowing,
                          isReplyGlowing: _isRootNoteReplyGlowing,
                          isRepostGlowing: _isRootNoteRepostGlowing,
                          isZapGlowing: _isRootNoteZapGlowing,
                          hasReacted: _hasReacted(_rootNote!),
                          hasReplied: _hasReplied(_rootNote!),
                          hasReposted: _hasReposted(_rootNote!),
                          hasZapped: _hasZapped(_rootNote!),
                          onReactionTap: _handleRootNoteReactionTap,
                          onReplyTap: _handleRootNoteReplyTap,
                          onRepostTap: _handleRootNoteRepostTap,
                          onZapTap: _handleRootNoteZapTap,
                          onStatisticsTap: _handleRootNoteStatisticsTap,
                        ),
                      ),
                      _buildThreadReplies(),
                    ],
                  ),
                ),
    );
  }
}
