import 'package:flutter/material.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:collection/collection.dart';
import 'package:qiqstr/widgets/root_note_widget.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import 'package:qiqstr/screens/note_statistics_page.dart';
import 'package:qiqstr/screens/send_reply.dart';
import 'package:qiqstr/widgets/dialogs/repost_dialog.dart';
import 'package:qiqstr/widgets/dialogs/zap_dialog.dart';

class NoteWithDepth {
  final NoteModel note;
  final int depth;

  NoteWithDepth({required this.note, required this.depth});
}

class ThreadPage extends StatefulWidget {
  final String rootNoteId;
  final DataService dataService;

  const ThreadPage({
    Key? key,
    required this.rootNoteId,
    required this.dataService,
  }) : super(key: key);

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  List<NoteWithDepth> _threadedNotes = [];
  NoteModel? _rootNote;
  String? _currentUserNpub;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _isLoading = true;

  bool _isRootNoteReactionGlowing = false;
  bool _isRootNoteReplyGlowing = false;
  bool _isRootNoteRepostGlowing = false;
  bool _isRootNoteZapGlowing = false;

  @override
  void initState() {
    super.initState();
    widget.dataService.notesNotifier.addListener(_onNotesChanged);
    _loadThread();
  }

  @override
  void dispose() {
    widget.dataService.notesNotifier.removeListener(_onNotesChanged);
    super.dispose();
  }

  void _onNotesChanged() {
    _loadThread();
  }

  Future<void> _loadThread() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    _currentUserNpub = await _secureStorage.read(key: 'npub');
    if (!mounted) return;

    final allNotes = widget.dataService.notesNotifier.value;

    _rootNote = allNotes.firstWhereOrNull((n) => n.id == widget.rootNoteId);

    if (_rootNote == null) {
      if (mounted) {
        setState(() {
          _threadedNotes = [];
          _isLoading = false;
        });
      }
      return;
    }

    final threadNotesUnsorted = allNotes.where((note) {
      return note.id == widget.rootNoteId || note.rootId == widget.rootNoteId;
    }).toList();

    final threadNotesSorted = List<NoteModel>.from(threadNotesUnsorted)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    List<NoteWithDepth> result = [];
    _buildThreadRecursive(_rootNote!, threadNotesSorted, 0, result);

    if (mounted) {
      setState(() {
        _threadedNotes = result;
        _isLoading = false;
      });
    }
  }

  void _buildThreadRecursive(
    NoteModel currentNote,
    List<NoteModel> allThreadNotes,
    int currentDepth,
    List<NoteWithDepth> result,
  ) {
    result.add(NoteWithDepth(note: currentNote, depth: currentDepth));

    final children = allThreadNotes.where((note) => note.parentId == currentNote.id).toList();

    for (final child in children) {
      if (child.id != currentNote.id) {
        _buildThreadRecursive(child, allThreadNotes, currentDepth + 1, result);
      }
    }
  }

  
  bool _hasReacted(NoteModel note) {
    if (_currentUserNpub == null) return false;
    return (widget.dataService.reactionsMap[note.id] ?? []).any((e) => e.author == _currentUserNpub);
  }

  bool _hasReplied(NoteModel note) {
    if (_currentUserNpub == null) return false;
    return (widget.dataService.repliesMap[note.id] ?? []).any((e) => e.author == _currentUserNpub);
  }

  bool _hasReposted(NoteModel note) {
    if (_currentUserNpub == null) return false;
    return (widget.dataService.repostsMap[note.id] ?? []).any((e) => e.repostedBy == _currentUserNpub);
  }

  bool _hasZapped(NoteModel note) {
    if (_currentUserNpub == null) return false;
    return (widget.dataService.zapsMap[note.id] ?? []).any((z) => z.sender == _currentUserNpub);
  }

  void _navigateToProfile(String npub) {
    widget.dataService.openUserProfile(context, npub);
  }

  
  void _handleRootNoteReactionTap() async {
    if (_rootNote == null || _hasReacted(_rootNote!)) return;
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() => _isRootNoteReplyGlowing = true);
    Future.delayed(
        const Duration(milliseconds: 400), () => mounted ? setState(() => _isRootNoteReplyGlowing = false) : null);
    showDialog(
      context: context,
      builder: (_) => SendReplyDialog(dataService: widget.dataService, noteId: _rootNote!.id),
    );
  }

  void _handleRootNoteRepostTap() {
    if (_rootNote == null) return;
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() => _isRootNoteZapGlowing = true);
    Future.delayed(
        const Duration(milliseconds: 400), () => mounted ? setState(() => _isRootNoteZapGlowing = false) : null);

    showZapDialog(context: context, dataService: widget.dataService, note: _rootNote!);
  }

  void _handleRootNoteStatisticsTap() {
    if (_rootNote == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteStatisticsPage(note: _rootNote!, dataService: widget.dataService)),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'Thread',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _rootNote == null
                    ? const Center(child: Text('Root note not found.', style: TextStyle(color: Colors.white70)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 0, bottom: 8),
                        itemCount: _threadedNotes.length == 1 ? 2 : _threadedNotes.length,
                        itemBuilder: (context, index) {
                          if (_threadedNotes.length == 1 && index == 1) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                              child: Center(
                                child: Text(
                                  'No replies yet.',
                                  style: TextStyle(color: Colors.white70, fontSize: 16),
                                ),
                              ),
                            );
                          }

                          final item = _threadedNotes[index];
                          final isRootNote = item.depth == 0;

                          if (isRootNote) {
                            return RootNoteWidget(
                              note: item.note,
                              dataService: widget.dataService,
                              onNavigateToMentionProfile: _navigateToProfile,
                              isReactionGlowing: _isRootNoteReactionGlowing,
                              isReplyGlowing: _isRootNoteReplyGlowing,
                              isRepostGlowing: _isRootNoteRepostGlowing,
                              isZapGlowing: _isRootNoteZapGlowing,
                              hasReacted: _hasReacted(item.note),
                              hasReplied: _hasReplied(item.note),
                              hasReposted: _hasReposted(item.note),
                              hasZapped: _hasZapped(item.note),
                              onReactionTap: _handleRootNoteReactionTap,
                              onReplyTap: _handleRootNoteReplyTap,
                              onRepostTap: _handleRootNoteRepostTap,
                              onZapTap: _handleRootNoteZapTap,
                              onStatisticsTap: _handleRootNoteStatisticsTap,
                            );
                          } else {
                            return Padding(
                              padding: EdgeInsets.only(
                                left: item.depth == 1 ? 0.0 : (16.0 + (item.depth * 20.0)),
                                right: 16.0,
                                top: 4,
                                bottom: 4,
                              ),
                              child: NoteWidget(
                                key: ValueKey(item.note.id),
                                note: item.note,
                                reactionCount: item.note.reactionCount,
                                replyCount: item.note.replyCount,
                                repostCount: item.note.repostCount,
                                dataService: widget.dataService,
                                currentUserNpub: _currentUserNpub ?? '',
                                notesNotifier: widget.dataService.notesNotifier,
                                profiles: widget.dataService.profilesNotifier.value,
                              ),
                            );
                          }
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
