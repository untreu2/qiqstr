import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class _NoteListWidgetState extends State<NoteListWidget>
    with SingleTickerProviderStateMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();

  String? _currentUserNpub;
  bool _isInitializing = true;
  bool _preloadDone = false;

  late DataService _dataService;
  List<NoteModel> _pendingNotes = [];

  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _setupInitialService();
  }

  Future<void> _setupInitialService() async {
    _currentUserNpub = await _secureStorage.read(key: 'npub');
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final preloadKey =
        'note_preload_done_${widget.npub}_${widget.dataType.name}';
    final preloadAlreadyDone = prefs.getBool(preloadKey) ?? false;

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

    await _dataService.initialize();
    await _dataService.initializeConnections();

    if (!preloadAlreadyDone) {
      await Future.delayed(const Duration(seconds: 2));
      await _dataService.closeConnections();

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

      await _dataService.initialize();
      await _dataService.initializeConnections();

      _applyPendingNotes();

      for (int i = 0; i < 3; i++) {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 100));
        setState(() {});
      }

      await prefs.setBool(preloadKey, true);
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _preloadDone = true;
      });
    }
  }

  void _handleNewNote(NoteModel note) {
    _pendingNotes.add(note);
    if (_preloadDone) {
      _applyPendingNotes();
    }
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
    _scrollController.dispose();
    _dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _currentUserNpub == null) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: 100),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return ValueListenableBuilder<List<NoteModel>>(
      valueListenable: _dataService.notesNotifier,
      builder: (context, notes, child) {
        if (notes.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No notes found.'),
              ),
            ),
          );
        }

        final filteredNotes = _selectedTabIndex == 0
            ? notes
            : notes.where((n) => n.hasMedia).toList();

        return SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedTabIndex == 0
                            ? Colors.amber.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                        foregroundColor: _selectedTabIndex == 0
                            ? Colors.amber[800]
                            : Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedTabIndex = 0;
                        });
                      },
                      child: const Text("All Notes"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedTabIndex == 1
                            ? Colors.amber.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                        foregroundColor: _selectedTabIndex == 1
                            ? Colors.amber[800]
                            : Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedTabIndex = 1;
                        });
                      },
                      child: const Text("Media"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(filteredNotes.length, (index) {
              final note = filteredNotes[index];
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
            }),
          ]),
        );
      },
    );
  }
}
