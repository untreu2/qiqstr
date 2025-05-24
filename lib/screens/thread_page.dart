import 'package:flutter/material.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:collection/collection.dart';
import 'package:qiqstr/widgets/root_note_widget.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/widgets/note_widget.dart';

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

  void _navigateToProfile(String npub) {
    widget.dataService.openUserProfile(context, npub);
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
                              isReactionGlowing: false,
                              isReplyGlowing: false,
                              isRepostGlowing: false,
                              isZapGlowing: false,
                              hasReacted: false,
                              hasReplied: false,
                              hasReposted: false,
                              hasZapped: false,
                              onReactionTap: () {},
                              onReplyTap: () {},
                              onRepostTap: () {},
                              onZapTap: () {},
                              onStatisticsTap: () {},
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
