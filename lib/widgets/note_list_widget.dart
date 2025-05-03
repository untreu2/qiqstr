import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
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

  int _selectedTabIndex = 1;

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

  Widget buildButton(int index, String label) {
    final isSelected = _selectedTabIndex == index;

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color:
              isSelected ? Colors.white.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white12,
            width: 1,
          ),
        ),
        child: TextButton(
          onPressed: () {
            setState(() {
              _selectedTabIndex = index;
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: isSelected ? Colors.white : Colors.white60,
            padding: const EdgeInsets.symmetric(vertical: 12),
            textStyle: const TextStyle(fontSize: 13),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: Size.zero,
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
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

        List<NoteModel> filteredNotes = notes;

        if (_selectedTabIndex == 0) {
          final cutoff = DateTime.now().subtract(const Duration(hours: 24));
          filteredNotes = notes
              .where((n) => n.timestamp.isAfter(cutoff))
              .toList()
            ..sort((a, b) => (b.reactionCount + b.replyCount + b.repostCount)
                .compareTo(a.reactionCount + a.replyCount + a.repostCount));
        } else if (_selectedTabIndex == 2) {
          filteredNotes = notes.where((n) => n.hasMedia).toList();
        }

        return SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              child: Row(
                children: [
                  buildButton(0, "Popular (24h)"),
                  const SizedBox(width: 6),
                  buildButton(1, "Latest"),
                  const SizedBox(width: 6),
                  buildButton(2, "Media"),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ...List.generate(filteredNotes.length, (index) {
              final note = filteredNotes[index];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NoteWidget(
                    key: ValueKey(note.id),
                    note: note,
                    reactionCount: note.reactionCount,
                    replyCount: note.replyCount,
                    repostCount: note.repostCount,
                    dataService: _dataService,
                    currentUserNpub: _currentUserNpub!,
                    notesNotifier: _dataService.notesNotifier,
                  ),
                  if (index < filteredNotes.length - 1)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      height: 1,
                      width: double.infinity,
                      color: Colors.white24,
                    ),
                ],
              );
            }),
          ]),
        );
      },
    );
  }
}
