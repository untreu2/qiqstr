import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';

class NoteListWidget extends StatefulWidget {
  final String npub;
  final DataType dataType;
  const NoteListWidget({super.key, required this.npub, required this.dataType});
  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _visibleIndexNotifier = ValueNotifier<int>(-1);
  String? _currentUserNpub;
  bool _isLoading = true;
  bool _delayElapsed = false;
  late DataService _dataService;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _delayElapsed = true);
    });
  }

  Future<void> _initialize() async {
    _currentUserNpub = await _secureStorage.read(key: 'npub');
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final preloadKey =
        'note_preload_done_${widget.npub}_${widget.dataType.name}';
    final preloadDone = prefs.getBool(preloadKey) ?? false;
    _dataService = DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: _handleNewNote,
      onReactionsUpdated: (_, __) {},
      onRepliesUpdated: (_, __) {},
      onRepostsUpdated: (_, __) {},
      onReactionCountUpdated: (_, __) {},
      onReplyCountUpdated: (_, __) {},
      onRepostCountUpdated: (_, __) {},
    );
    await _dataService.initialize();
    await _dataService.initializeConnections();
    if (!preloadDone) {
      await Future.delayed(const Duration(milliseconds: 1500));
      await _dataService.closeConnections();
      _dataService = DataService(
        npub: widget.npub,
        dataType: widget.dataType,
        onNewNote: _handleNewNote,
        onReactionsUpdated: (_, __) {},
        onRepliesUpdated: (_, __) {},
        onRepostsUpdated: (_, __) {},
        onReactionCountUpdated: (_, __) {},
        onReplyCountUpdated: (_, __) {},
        onRepostCountUpdated: (_, __) {},
      );
      await _dataService.initialize();
      await _dataService.initializeConnections();
      await prefs.setBool(preloadKey, true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _handleNewNote(NoteModel note) {
    if (_dataService.notesNotifier.value.length >= 75) return;
    _dataService.addPendingNote(note);
    _dataService.applyPendingNotes();

    _dataService.fetchInteractionsForEvents([note.id]);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _currentUserNpub == null || !_delayElapsed) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 300,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Loading...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      );
    }
    return ValueListenableBuilder<List<NoteModel>>(
      valueListenable: _dataService.notesNotifier,
      builder: (_, notes, __) {
        final filteredNotes = _selectedTabIndex == 0
            ? notes
            : notes.where((n) => n.hasMedia).toList();
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, index) {
              if (index == 0) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              setState(() => _selectedTabIndex = 0),
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
                          child: const Text('All Notes'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              setState(() => _selectedTabIndex = 1),
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
                          child: const Text('Media'),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final note = filteredNotes[index - 1];
              return RepaintBoundary(
                key: ValueKey(note.id),
                child: NoteWidget(
                  index: index - 1,
                  visibleIndexNotifier: _visibleIndexNotifier,
                  note: note,
                  reactionCount: note.reactionCount,
                  replyCount: note.replyCount,
                  repostCount: note.repostCount,
                  dataService: _dataService,
                  currentUserNpub: _currentUserNpub!,
                  notesNotifier: _dataService.notesNotifier,
                ),
              );
            },
            childCount: filteredNotes.length + 1,
          ),
        );
      },
    );
  }
}
