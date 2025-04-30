import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';

class NoteListWidget extends StatefulWidget {
  final String npub;
  final DataType dataType;

  const NoteListWidget({
    super.key,
    required this.npub,
    required this.dataType,
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _currentUserNpub;
  bool _isInitializing = true;

  late final DataService _dataService;
  List<NoteModel> _pendingNotes = [];

  @override
  void initState() {
    super.initState();
    _dataService = DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: _handleNewNote,
      onReactionsUpdated: _handleReactionsUpdated,
      onRepliesUpdated: _handleRepliesUpdated,
      onRepostsUpdated: _handleRepostsUpdated,
      onReactionCountUpdated: (_, __) => setState(() {}),
      onReplyCountUpdated: (_, __) => setState(() {}),
      onRepostCountUpdated: (_, __) => setState(() {}),
    );
    _loadNpubAndInit();
  }

  Future<void> _loadNpubAndInit() async {
    _currentUserNpub = await _secureStorage.read(key: 'npub');
    if (!mounted) return;

    await _dataService.initialize();
    await _dataService.initializeConnections();

    setState(() => _isInitializing = false);
  }

  void _handleNewNote(NoteModel note) {
    _pendingNotes.add(note);
    setState(() {});
  }

  void _handleReactionsUpdated(String noteId, _) => setState(() {});
  void _handleRepliesUpdated(String noteId, _) => setState(() {});
  void _handleRepostsUpdated(String noteId, _) => setState(() {});

  void _applyPendingNotes() {
    _pendingNotes.forEach(_dataService.addPendingNote);
    _dataService.applyPendingNotes();
    _pendingNotes.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _currentUserNpub == null) {
      return const SliverToBoxAdapter(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ValueListenableBuilder<List<NoteModel>>(
      valueListenable: _dataService.notesNotifier,
      builder: (context, notes, child) {
        if (notes.isEmpty && _pendingNotes.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No notes found.'),
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (_pendingNotes.isNotEmpty && index == 0) {
                return GestureDetector(
                  onTap: _applyPendingNotes,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 24),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Text(
                      'Show ${_pendingNotes.length} new note${_pendingNotes.length > 1 ? "s" : ""}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black),
                    ),
                  ),
                );
              }

              final realIndex = _pendingNotes.isNotEmpty ? index - 1 : index;
              if (realIndex >= notes.length) return null;

              final note = notes[realIndex];

              return NoteWidget(
                key: ValueKey(note.id),
                note: note,
                reactionCount: note.reactionCount,
                replyCount: note.replyCount,
                repostCount: note.repostCount,
                dataService: _dataService,
                currentUserNpub: _currentUserNpub!,
                notesNotifier: _dataService.notesNotifier,
              );
            },
            childCount: _dataService.notesNotifier.value.length +
                (_pendingNotes.isNotEmpty ? 1 : 0),
          ),
        );
      },
    );
  }
}
